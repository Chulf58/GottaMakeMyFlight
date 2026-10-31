extends SceneTree
## Windowed plates of the ambient crows (BirdFlock) at landside zooms: one
## plate from a typical landside zoom, an 8-frame strip of a perched group
## under the entrance canopy, and an 8-frame strip of a canopy group that a
## real taxi scatters, through to its landing. Taxis come from
## LandsideSim.add_vehicle and drive the sim's own road; LandsideSim steps on
## every tick (ArrivalBookings.step) whether or not the airport is open, so
## the probe only dismisses the intro (which pauses the clock) and runs it.
##
## Proofs before each plate: every bird projects inside the viewport with a
## margin and outside every visible HUD panel, no shell or landside mesh is on
## the line from the camera to it, and a perched bird's lowest skinned vertex
## is on its patch top. Crops are taken in image pixels: the window renders
## 1920x1080 while unproject_position answers in the 1536x864 visible rect
## (stretch scale 1.25).
##
## Run windowed:
##   Godot --path game --display-driver windows --rendering-driver vulkan
##     --audio-driver Dummy -s res://spike/bird_flock_plates_probe.gd

const SIGHT := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/birds"
const MARGIN_PX := 8.0
const SETTLE_FRAMES := 120
const STRIP_GAP := 12
const CROP := 360
const TILE := 480
const FEET_TOLERANCE := 0.03
const WAIT_FRAMES := 9000
const TAXIS := 4
## A typical landside zoom: the curb, road and forecourt in one view.
const LANDSIDE_FOCUS := Vector3(-18.0, 0.0, -52.0)
const LANDSIDE_DISTANCE := 45.0
## The strips' frame: the canopy zone's perches, close in.
const CANOPY_FOCUS := Vector3(-25.8, 1.5, -60.0)
const CANOPY_DISTANCE := 24.0

var _main: Node3D
var _flock: BirdFlock
var _clock: SimClock
var _landside: LandsideSim
var _rig: TycoonCamera
var _cam: Camera3D
var _out := ""
var _frame := 0
var _stage := "settle"
var _tiles: Array[Image] = []
var _labels: PackedStringArray = []
var _group: Dictionary
var _next := 0
var _deadline := 0


func _initialize() -> void:
	_out = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out)
	var seed_value := randi()
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
	match _stage:
		"settle":
			return _stage_settle()
		"landside":
			return _stage_landside()
		"perched":
			return _stage_perched()
		"wait":
			return _stage_wait()
		"flight":
			return _stage_flight()
	return false


func _invalid(msg: String) -> bool:
	print("PROBE_INVALID ", msg)
	quit(1)
	return false


func _stage_settle() -> bool:
	if _frame == 10:
		(_main.get_node("PassengerHud") as PassengerHud).dismiss_intro()
		_clock.set_paused(false)
		_rig.glide_to(LANDSIDE_FOCUS, LANDSIDE_DISTANCE)
	if _frame == SETTLE_FRAMES - 5:
		var owners: Array[Node] = [_main.get_node("Airside"), _main.get_node("LandsideViews")]
		SIGHT.colliders(root, owners, {})
	if _frame >= SETTLE_FRAMES and not _rig.is_gliding():
		_cam = root.get_viewport().get_camera_3d()
		_stage = "landside"
	return false


func _stage_landside() -> bool:
	var canopy := _canopy_group()
	if canopy.is_empty():
		return _invalid("no group under the canopy")
	if not _prove_group(canopy, true):
		return false
	_image().save_png(_out.path_join("landside_zoom.png"))
	print("PLATE ", _out.path_join("landside_zoom.png"), " focus=", LANDSIDE_FOCUS)
	_group = canopy
	_rig.glide_to(CANOPY_FOCUS, CANOPY_DISTANCE)
	_stage = "perched"
	_next = _frame + 90
	return false


func _stage_perched() -> bool:
	if _frame < _next or _rig.is_gliding():
		return false
	if _tiles.is_empty() and not _prove_group(_group, true):
		return false
	_tiles.append(_crop(_centre(_group)))
	_labels.append("perched %s" % _clips(_group))
	_next = _frame + STRIP_GAP
	if _tiles.size() == 8:
		_sheet("strip_perched.png")
		for i in TAXIS:
			_landside.add_vehicle(LandsideVehicle.Kind.TAXI, LandsideVehicle.Intent.DROP, [])
		print("TAXIS added=", TAXIS)
		_stage = "wait"
		_deadline = _frame + WAIT_FRAMES
	return false


func _stage_wait() -> bool:
	for g in _flock.groups:
		if g["target"] >= 0 and BirdPerches.ZONES[g["spot"]] == BirdPerches.Zone.UNDER_CANOPY:
			_group = g
			var near := BirdPerches.nearest(BirdPerches.SPOTS[g["spot"]], _flock.threats_now())
			print("SCATTER spot=", g["spot"], " target=", g["target"], " nearest_threat_m=", near)
			_stage = "flight"
			_next = _frame
			return false
	if _frame > _deadline:
		return _invalid("no canopy group scattered within %d frames" % WAIT_FRAMES)
	return false


func _stage_flight() -> bool:
	# Tiles 1-7 at even steps of the first bird's own flight time (0 to its
	# landing), tile 8 once the whole group has landed.
	var b: Dictionary = _group["birds"][0]
	var landed: bool = _group["target"] < 0
	var due := float(_tiles.size()) * float(b["dur"]) / 6.0
	var take := (_tiles.size() < 7 and float(b["t"]) >= due) or (_tiles.size() == 7 and landed)
	if not take:
		return false
	_tiles.append(_crop(_centre(_group)))
	_labels.append(
		"%s t=%.2f/%.2f y=%.2f" % [_clips(_group), b["t"], b["dur"], b["node"].position.y]
	)
	print("FLIGHT tile=", _tiles.size(), " ", _labels[_labels.size() - 1])
	if _tiles.size() < 8:
		return false
	_sheet("strip_scatter.png")
	if _prove_group(_group, true):
		print("PROBE_DONE")
		quit(0)
	return false


func _canopy_group() -> Dictionary:
	for g in _flock.groups:
		if BirdPerches.ZONES[g["spot"]] == BirdPerches.Zone.UNDER_CANOPY and g["target"] < 0:
			return g
	return {}


func _clips(g: Dictionary) -> String:
	var names := PackedStringArray()
	for b in g["birds"]:
		names.append(b["clip"])
	return ",".join(names)


func _centre(g: Dictionary) -> Vector3:
	var c := Vector3.ZERO
	for b in g["birds"]:
		c += (b["node"] as Node3D).global_position
	return c / float(g["birds"].size()) + Vector3.UP * 0.35


## The visible HUD panels, in the visible rect's coordinates.
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


## In frame and clear of the HUD, seen (no shell or landside mesh on the line
## from the camera; the colliders hold no bird) and, when `perched`, the feet
## on the patch top. Prints the numbers and the bird's size on screen.
func _prove_group(g: Dictionary, perched: bool) -> bool:
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
		" huds=",
		huds.size(),
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
	if perched:
		return _prove_feet(g)
	return true


func _prove_feet(g: Dictionary) -> bool:
	var top: float = BirdPerches.SPOTS[g["spot"]].y
	var low := INF
	var high := -INF
	for b in g["birds"]:
		var lowest := INF
		for mi in (b["node"] as Node).find_children("*", "MeshInstance3D", true, false):
			var inst := mi as MeshInstance3D
			if not inst.visible:
				continue
			for v in inst.bake_mesh_from_current_skeleton_pose().get_faces():
				lowest = minf(lowest, (inst.global_transform * v).y)
		low = minf(low, lowest - top)
		high = maxf(high, lowest - top)
	print("FEET spot=", g["spot"], " gap_min_m=", low, " gap_max_m=", high)
	if absf(low) > FEET_TOLERANCE or absf(high) > FEET_TOLERANCE:
		return _invalid("feet off the patch top by %.3f..%.3f m" % [low, high])
	return true


func _image() -> Image:
	return root.get_viewport().get_texture().get_image()


## A CROP-pixel square of the rendered image around `centre`, scaled from the
## visible rect (unproject_position) to the image's own pixels.
func _crop(centre: Vector3) -> Image:
	var img := _image()
	var scale := Vector2(img.get_size()) / root.get_viewport().get_visible_rect().size
	var sp := _cam.unproject_position(centre) * scale
	var r := Rect2i(Vector2i(sp) - Vector2i(CROP / 2, CROP / 2), Vector2i(CROP, CROP))
	r.position = r.position.clamp(Vector2i.ZERO, img.get_size() - r.size)
	var tile := img.get_region(r)
	tile.resize(TILE, TILE, Image.INTERPOLATE_BILINEAR)
	return tile


func _sheet(name: String) -> void:
	var sheet := Image.create(TILE * 4, TILE * 2, false, _tiles[0].get_format())
	for i in _tiles.size():
		var at := Vector2i((i % 4) * TILE, (i / 4) * TILE)
		sheet.blit_rect(_tiles[i], Rect2i(Vector2i.ZERO, _tiles[i].get_size()), at)
	sheet.save_png(_out.path_join(name))
	print("PLATE ", _out.path_join(name), " tiles=", " | ".join(_labels))
	_tiles.clear()
	_labels.clear()
