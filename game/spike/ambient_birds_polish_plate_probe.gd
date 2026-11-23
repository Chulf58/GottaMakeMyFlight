extends SceneTree
## Windowed Vulkan plates for Ambient Birds Road Polish (decision 2be8c419):
## 1) 01_curb_ground_strolling.png - curb/road ground birds strolling/idling
## 2) 02_elevated_perches.png - elevated lamppost/bench/tree perched bird
## 3) 03_scatter_puff_banking.png - startled scatter takeoff puff + banking arc
## 4) 04_landside_overview.png - wide landside overview across road & verges
##
## Run windowed (single slot only):
##   ./tools/godot.sh --path game --display-driver windows --rendering-driver vulkan \
##     --audio-driver Dummy -s res://spike/ambient_birds_polish_plate_probe.gd

const SIGHT := preload("res://spike/plate_sight.gd")
const IntroClose := preload("res://spike/intro_close.gd")
const OUT_REL := "res://../tools/blender/out/birds_polish"
const MARGIN_PX := 8.0
const SETTLE_FRAMES := 90
const WAIT_TICKS := 3600
const TAXIS := 6

var _main: Node3D
var _flock: BirdFlock
var _clock: SimClock
var _landside: LandsideSim
var _rig: TycoonCamera
var _cam: Camera3D
var _out := ""
var _frame := 0
var _stage := "settle"
var _group: Dictionary = {}
var _scatter_origin := Vector3.ZERO
var _deadline := 0
var _scatter_frames := 0
var _colliders: Node3D
var _done := false


func _initialize() -> void:
	_out = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out)
	var seed_value := IntroClose.seed_or_random()
	print("PROBE seed=", seed_value, " out=", _out)
	_main = load("res://main/main.tscn").instantiate()
	root.add_child(_main)
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(seed_value)
	_landside = _main.get_node("LandsideSim")
	_flock = _main.get_node("BirdFlock")
	_flock.rng.seed = seed_value
	_flock.rebuild()
	_rig = _main.get_node("TycoonCamera")


func _process(_delta: float) -> bool:
	_frame += 1
	if _done:
		return true
	return call("_stage_" + _stage)


func _invalid(msg: String) -> bool:
	print("PROBE_INVALID ", msg)
	_finish(1)
	return false


func _finish(code: int) -> void:
	if _done:
		return
	_done = true
	_group = {}
	_flock = null
	_rig = null
	_cam = null
	if _colliders != null:
		_colliders.free()
	_main.free()
	quit(code)


func _refresh_colliders() -> void:
	if _colliders != null:
		_colliders.free()
	var owners: Array[Node] = [_main.get_node("Airside"), _main.get_node("LandsideViews")]
	_colliders = SIGHT.colliders(root, owners, {})


func _stage_settle() -> bool:
	if _frame == 10:
		var intro_problem := IntroClose.close(_main)
		if intro_problem != "":
			return _invalid(intro_problem)
		_clock.set_paused(false)
		_deadline = _clock.tick + 400
	if _frame >= SETTLE_FRAMES:
		_cam = root.get_viewport().get_camera_3d()
		var walking_group := _find_walking_ground_group()
		if walking_group.is_empty() and _clock.tick < _deadline:
			return false
		_group = walking_group if not walking_group.is_empty() else _find_ground_group()
		if _group.is_empty():
			return _invalid("no ground group found")
		_clock.set_paused(true)
		_rig.glide_to(_centre(_group), 13.0)
		_stage = "plate_ground"
	return false


func _stage_plate_ground() -> bool:
	if _rig.is_gliding():
		return false
	_refresh_colliders()
	if not _prove_group(_group):
		return false
	var path := _out.path_join("01_curb_ground_strolling.png")
	_image().save_png(path)
	print("PLATE ", path, " spot=", _group["spot"], " kind=", BirdPerches.spot_kind(_group["spot"]))
	var elev := _find_elevated_group()
	if elev.is_empty():
		return _invalid("no elevated group found")
	_group = elev
	_rig.glide_to(_centre(_group) + Vector3(0.0, -0.7, 0.0), 14.0)
	_stage = "plate_elevated"
	return false


func _stage_plate_elevated() -> bool:
	if _rig.is_gliding():
		return false
	_refresh_colliders()
	if not _prove_group(_group):
		return false
	var path := _out.path_join("02_elevated_perches.png")
	_image().save_png(path)
	print("PLATE ", path, " spot=", _group["spot"], " kind=", BirdPerches.spot_kind(_group["spot"]))
	_clock.set_paused(false)
	for i in TAXIS:
		_landside.add_vehicle(LandsideVehicle.Kind.TAXI, LandsideVehicle.Intent.DROP, [])
	_deadline = _clock.tick + WAIT_TICKS
	_stage = "wait_scatter"
	return false


func _stage_wait_scatter() -> bool:
	for g in _flock.groups:
		if g["target"] >= 0 and _flock.active_puff_count() > 0:
			_group = g
			_scatter_origin = BirdPerches.spot_pos(g["spot"])
			_scatter_frames = 0
			_stage = "advance_scatter"
			return false
	if _clock.tick > _deadline:
		return _invalid("no startled scatter with puff observed within %d ticks" % WAIT_TICKS)
	return false


func _stage_advance_scatter() -> bool:
	_scatter_frames += 1
	var max_t := -1.0
	for b in _group["birds"]:
		max_t = maxf(max_t, float(b["t"]))
	if max_t < 0.35 and _scatter_frames < 25:
		return false
	_clock.set_paused(true)
	var mid := (_scatter_origin + _centre(_group)) * 0.5
	_rig.glide_to(mid + Vector3(0.0, 1.0, 0.0), 18.0)
	_stage = "plate_scatter"
	return false


func _stage_plate_scatter() -> bool:
	if _rig.is_gliding():
		return false
	_refresh_colliders()
	if not _prove_group(_group):
		return false
	var huds := _hud_rects()
	var puff_why := _on_screen(_scatter_origin + Vector3(0.0, 0.25, 0.0), huds)
	if puff_why != "":
		return _invalid("scatter puff origin %s" % puff_why)
	var path := _out.path_join("03_scatter_puff_banking.png")
	_image().save_png(path)
	print(
		"PLATE ",
		path,
		" puffs=",
		_flock.active_puff_count(),
		" roll_rad=",
		_group["birds"][0]["roll"]
	)
	_rig.glide_to(Vector3(-4.0, 1.0, -49.0), 72.0)
	_stage = "plate_overview"
	return false


func _stage_plate_overview() -> bool:
	if _rig.is_gliding():
		return false
	var huds := _hud_rects()
	var visible_groups := 0
	for g in _flock.groups:
		var ok := true
		for b in g["birds"]:
			var at := (b["node"] as Node3D).global_position + Vector3.UP * 0.35
			if _on_screen(at, huds) != "":
				ok = false
				break
		if ok:
			visible_groups += 1
	print("OVERVIEW visible_groups=", visible_groups, " total_groups=", _flock.groups.size())
	if visible_groups < 3:
		return _invalid("only %d bird groups in overview frame" % visible_groups)
	var path := _out.path_join("04_landside_overview.png")
	_image().save_png(path)
	print("PLATE ", path)
	print("PROBE_DONE")
	_finish(0)
	return false


func _find_walking_ground_group() -> Dictionary:
	for g in _flock.groups:
		if BirdPerches.is_elevated(g["spot"]) or g["target"] >= 0:
			continue
		for b in g["birds"]:
			if b["clip"] == "walk":
				return g
	return {}


func _find_ground_group() -> Dictionary:
	for g in _flock.groups:
		if not BirdPerches.is_elevated(g["spot"]) and g["target"] < 0:
			return g
	return {}


func _find_elevated_group() -> Dictionary:
	for want in ["lamp_ped", "bench", "tree_planter", "lamp_hwy", "pine", "tree_leaf"]:
		for g in _flock.groups:
			if BirdPerches.spot_kind(g["spot"]) == want and g["target"] < 0:
				return g
	for g in _flock.groups:
		if BirdPerches.is_elevated(g["spot"]) and g["target"] < 0:
			return g
	return {}


func _centre(g: Dictionary) -> Vector3:
	var c := Vector3.ZERO
	for b in g["birds"]:
		c += (b["node"] as Node3D).global_position
	return c / float(g["birds"].size()) + Vector3.UP * 0.35


func _hud_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var screen := root.get_viewport().get_visible_rect()
	for node in root.find_children("*", "Control", true, false):
		var c := node as Control
		if not c.is_visible_in_tree() or not (c is PanelContainer or c is Panel or c is Button):
			continue
		var r := c.get_global_rect()
		if r.get_area() < screen.get_area() * 0.5:
			out.append(r)
	return out


func _on_screen(p: Vector3, huds: Array[Rect2]) -> String:
	var size := root.get_viewport().get_visible_rect().size
	var sp := _cam.unproject_position(p)
	if _cam.is_position_behind(p):
		return "behind the camera"
	if not Rect2(Vector2.ONE * MARGIN_PX, size - Vector2.ONE * 2.0 * MARGIN_PX).has_point(sp):
		return "outside the frame at %s" % sp
	for r in huds:
		if r.grow(MARGIN_PX).has_point(sp):
			return "under a HUD panel %s at %s" % [r, sp]
	return ""


func _prove_group(g: Dictionary) -> bool:
	var huds := _hud_rects()
	var targets: Array[Vector3] = []
	for b in g["birds"]:
		var at: Vector3 = (b["node"] as Node3D).global_position + Vector3.UP * 0.35
		var why := _on_screen(at, huds)
		if why != "":
			return _invalid("bird at %s %s" % [at, why])
		targets.append(at)
	var space := root.world_3d.direct_space_state
	var lines: Dictionary = SIGHT.sight_lines(space, _cam.global_position, targets, "none")
	var c := _centre(g)
	var tall := (
		(
			_cam.unproject_position(c + Vector3.UP * 0.35)
			- _cam.unproject_position(c - Vector3.UP * 0.35)
		)
		. length()
	)
	print(
		"INFRAME birds=",
		targets.size(),
		" screen=",
		_cam.unproject_position(c),
		" OCCLUSION clear=",
		lines["past"],
		" blockers=",
		lines["blockers"],
		" bird_px_tall_1080=",
		tall * 1.25
	)
	if not (lines["blockers"] as Array).is_empty():
		return _invalid("sight lines blocked by %s" % [lines["blockers"]])
	return true


func _image() -> Image:
	return root.get_viewport().get_texture().get_image()
