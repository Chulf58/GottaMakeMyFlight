extends SceneTree
## Windowed plates of the VIP crown (board 2348c245, VipMarker) over a passenger
## in a crowd: one at the home zoom, one close up. Boots main.tscn with
## NeedFacilityKit's terminal (a toilet room, a cafe and a screen stand, so a
## need icon is allowed to show: decision crowd-need-display-mood-overlay-gains-
## hunger-toilet-and-bore, point 3), opens the airport, lets a crowd of
## passengers arrive, picks the one with the most others around it, gives it a
## toilet need so the close-up shows the crown over
## a need icon row, and marks it as an accepted VIP through the director's
## snapshot, the door a load uses. The HUD's CanvasLayers are hidden
## for the plates (anti-pattern a-plate-probe-s-occlusion-rays-see-only-meshes-
## so-a-hud-pane).
##
## Proofs before a plate is saved: the subject's feet, head, crown anchor and
## crown rectangle project inside the frame by MARGIN_PX and in front of the
## camera; a physics ray from the camera to the head is not stopped more than
## BLOCK_M short of it; the subject's crown is visible and is the only crown
## shown (a control: every other passenger has none); at least CROWD_MIN other
## passengers are in frame; on the close-up the subject shows a need icon row
## (a control: no row would make the overlap check pass by accident) and the
## crown does not overlap it.
## Otherwise PROBE_INVALID, exit 1. A guard thread calls OS.crash() on a stall.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 600 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/vip_marker_plates_probe.gd
##
## Plates go to tools/blender/out/vip_marker/.

const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/vip_marker"
const MARGIN_PX := 8.0
const HANG_MS := 120000
const HEAD_M := 1.7
const BLOCK_M := 0.5
const WANT_PASSENGERS := 16
const ARRIVE_TICKS := 700
## Others within CROWD_M of the subject that make it a crowd.
const CROWD_M := 3.0
const CROWD_MIN := 3
## Frames after a camera move before the plate, so roof fades settle
## (anti-pattern a-plate-probe-that-waits-a-fixed-frame-count-can-take-its-si).
const SETTLE_FRAMES := 45
## The shots: a name, the camera distance as a fraction of home_distance, and
## whether the subject's need icon row must show (they hide at the home zoom).
const SHOTS := [["home", 1.0, false], ["close", 0.5, true]]

var _out_dir := ""
var _failed := false
var _main: Node3D
var _sim: PassengerSim
var _clock: SimClock
var _views: PassengerViews
var _director: IncidentDirector
var _rig: TycoonCamera
var _cam: Camera3D
var _saved: Array[String] = []
var _guard := Thread.new()
var _lock := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _stop := false


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_beat("boot")
	_guard.start(_watch)
	_run.call_deferred()


func _run() -> void:
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	_clock = _main.get_node("SimClock") as SimClock
	var world_seed := randi()
	_clock.seed_rng(world_seed)
	print("PROBE sim_seed=", world_seed)
	# The probe builds its own terminal on an empty grid, with the toilet room and
	# cafe that let a need icon show (anti-pattern a-main-tscn-probe-that-builds-
	# its-own-terminal-at-raw-cells): the starter shell would refuse its first wall.
	var mode := _main.get_node("BuildMode") as BuildMode
	mode.starter_shell = false
	root.add_child(_main)
	_clock.set_paused(true)
	await _frames(5)
	NeedFacilityKit.build(mode.grid)
	if not StarterFlight.add_gate_desk(mode.grid):
		_invalid("the gate desk was refused")
		_finish()
		return
	(mode.get_node("BuildView") as BuildView).refresh(mode.grid)
	mode.set_tool(BuildMode.Tool.NONE)
	await _frames(20)
	_clock.set_process(false)
	_sim = _main.get_node("PassengerSim") as PassengerSim
	_views = _main.get_node("PassengerViews") as PassengerViews
	_director = _main.get_node("IncidentDirector") as IncidentDirector
	var staff := _main.get_node("Staff") as StaffSim
	StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(
		_clock, _main.get_node("FlightSim") as FlightSim, staff
	)
	print("PROBE tick=%d doors_close=%d" % [_clock.tick, doors])
	if doors < 0:
		_invalid("the airport did not open")
		_finish()
		return
	_beat("arrivals")
	for i in WANT_PASSENGERS:
		_sim.spawn_now(StarterFlight.first_flight())
	_clock.set_paused(false)
	var until := _clock.tick + ARRIVE_TICKS
	while _clock.tick < until:
		_clock.advance(SimClock.STEP)
	var built := NeedIcons.provided(_sim)
	print("PROBE provided=", built)
	if not built[NeedIcons.Need.TOILET]:
		_invalid("no toilet stall is usable, so the toilet icon would stay hidden")
		_finish()
		return
	var subject := _pick_subject()
	print(
		(
			"PROBE passengers=%d subject=%d stage=%s"
			% [
				_sim.passenger_ids().size(),
				subject,
				Passenger.Stage.keys()[_sim.get_passenger(subject).stage] if subject != 0 else "-"
			]
		)
	)
	if subject == 0:
		_invalid("no passenger stands in a crowd of %d within %.1f m" % [CROWD_MIN, CROWD_M])
		_finish()
		return
	_sim.get_passenger(subject).toilet_need = 100
	if not _mark_vip(subject):
		_invalid("the director refused the VIP snapshot")
		_finish()
		return
	# No tick: one more would send the subject to a stall, where its icon hides.
	_clock.set_paused(true)
	_views.sync()
	var marked := {}
	VipMarker.marked_ids(_director, marked)
	print("PROBE marked=%s" % [marked.keys()])
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	_rig = _main.get_node("TycoonCamera") as TycoonCamera
	_cam = _rig.get_node("Camera3D") as Camera3D
	_cam.make_current()
	await _frames(4)
	for shot: Array in SHOTS:
		_beat("plate_%s" % shot[0])
		await _plate(subject, shot[0], shot[1], shot[2])
	_contact_sheet()
	_finish()


## One accepted VIP incident marking `target`, in place of any other.
func _mark_vip(target: int) -> bool:
	var data := _director.to_snapshot()
	var incident := {
		"id": data["next_id"],
		"kind": IncidentCatalogue.VIP,
		"roll_day": 1,
		"state": IncidentCatalogue.ACCEPTED,
		"fire_tick": 0,
		"cell": [-1, -1],
		"mess_id": 0,
		"place": "",
		"outcome": "",
		"shown": false,
		"plan":
		{
			"flight": _sim.get_passenger(target).flight_id,
			"departs": 0,
			"bonus": IncidentTuning.VIP_BONUS_MONEY,
			"target": target,
			"good_mood": IncidentTuning.VIP_GOOD_MOOD,
			"miss_half_stars": IncidentTuning.VIP_MISS_HALF_STARS,
		},
	}
	data["incidents"] = [incident]
	data["next_id"] = int(data["next_id"]) + 1
	return _director.from_snapshot(data)


func _plate(subject: int, shot: String, ratio: float, want_row: bool) -> void:
	var node := _views.node_for(subject)
	if node == null:
		_invalid("%s: the subject has no view" % shot)
		return
	_rig.yaw = 0.35
	_rig.distance = _rig.home_distance * ratio
	_rig.zoom(1.0)
	_rig.position = node.global_position * Vector3(1, 0, 1)
	await _frames(SETTLE_FRAMES)
	var tag := (
		"%s id=%d distance=%.1f home=%.1f" % [shot, subject, _rig.distance, _rig.home_distance]
	)
	var head := node.global_position + Vector3(0.0, _body_top_m(node), 0.0)
	var crown := node.get_node(VipMarker.SPRITE) as Sprite3D
	var ok := _in_frame(node.global_position, tag + " feet")
	ok = _in_frame(head, tag + " head") and ok
	ok = _in_frame(node.global_transform * crown.position, tag + " crown_anchor") and ok
	var rect := _crown_rect(node)
	ok = _rect_in_frame(rect, tag + " crown_rect") and ok
	ok = _ray_clear(head, tag) and ok
	var crowns := 0
	var in_frame := 0
	for id in _sim.passenger_ids():
		var other := _views.node_for(id)
		if other == null:
			continue
		if (other.get_node(VipMarker.SPRITE) as Sprite3D).visible:
			crowns += 1
		if id != subject and _on_screen(other.global_position + Vector3(0.0, 1.0, 0.0)):
			in_frame += 1
	var own := _icon_rects(node)
	var overlap := 0
	for icon in own:
		if icon.intersects(rect):
			overlap += 1
	print(
		(
			(
				"PLATE %s crown_visible=%s alpha=%.2f crown_rect=%s crowns=%d"
				+ " others_in_frame=%d own_icons=%d overlap=%d bubble='%s'"
			)
			% [
				tag,
				crown.visible,
				crown.modulate.a,
				rect,
				crowns,
				in_frame,
				own.size(),
				overlap,
				(node.get_node("Bubble") as Label3D).text,
			]
		)
	)
	var problem := ""
	if not crown.visible:
		problem = "the subject's crown is not shown"
	elif crowns != 1:
		problem = "%d crowns are shown, want 1" % crowns
	elif in_frame < CROWD_MIN:
		problem = "only %d other passengers in frame" % in_frame
	elif want_row and own.is_empty():
		problem = "the subject shows no need icon row to stack the crown over"
	elif overlap > 0:
		problem = "the crown overlaps its own need icons"
	elif not ok:
		problem = "the subject is out of frame or blocked"
	if problem != "":
		_invalid("%s: %s" % [tag, problem])
		return
	if DisplayServer.get_name() == "headless":
		return
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	_save(img, "vip_%s.png" % shot)
	var to_image := Vector2(img.get_size()) / root.get_visible_rect().size
	var centre := _cam.unproject_position(head) * to_image
	var crop := Rect2i(centre - Vector2(120, 140), Vector2i(240, 240))
	crop = crop.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var small := img.get_region(crop)
	small.resize(small.get_width() * 3, small.get_height() * 3, Image.INTERPOLATE_NEAREST)
	_save(small, "vip_%s_crop.png" % shot)


## The drawn passenger with the most other drawn passengers within CROWD_M, at
## least CROWD_MIN, or 0.
func _pick_subject() -> int:
	var best := 0
	var best_n := CROWD_MIN - 1
	for id in _sim.passenger_ids():
		var node := _views.node_for(id)
		if node == null:
			continue
		# A passenger inside a stall or at a table shows no need icon.
		var stage := _sim.get_passenger(id).stage
		if StageKinds.location(stage) == StageKinds.Location.FACILITY_SEAT:
			continue
		var near := 0
		for other_id in _sim.passenger_ids():
			var other := _views.node_for(other_id)
			if other_id != id and other != null:
				if other.global_position.distance_to(node.global_position) <= CROWD_M:
					near += 1
		if near > best_n:
			best = id
			best_n = near
	return best


## The crown's screen rectangle as VipMarker lays it out (CROWN_PX square, its
## bottom edge offset.y - SIZE / 2 texture pixels over the anchor).
func _crown_rect(node: Node3D) -> Rect2:
	var crown := node.get_node(VipMarker.SPRITE) as Sprite3D
	var at := _cam.unproject_position(node.global_transform * crown.position)
	var k := VipMarker.CROWN_PX / VipMarker.SIZE
	var centre := at + Vector2(crown.offset.x * k, -crown.offset.y * k)
	return Rect2(centre - Vector2.ONE * VipMarker.CROWN_PX / 2.0, Vector2.ONE * VipMarker.CROWN_PX)


## Screen rectangles of the need icons a passenger node shows (ICON_PX square).
func _icon_rects(node: Node3D) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var k := NeedIcons.ICON_PX / NeedIcons.SIZE
	for sprite_name in NeedIcons.SPRITES:
		var sprite := node.get_node(sprite_name) as Sprite3D
		if not sprite.visible:
			continue
		var at := _cam.unproject_position(node.global_transform * sprite.position)
		var centre := at + Vector2(sprite.offset.x * k, -sprite.offset.y * k)
		out.append(
			Rect2(centre - Vector2.ONE * NeedIcons.ICON_PX / 2.0, Vector2.ONE * NeedIcons.ICON_PX)
		)
	return out


## The height over the node's root of the top of its skinned body meshes.
func _body_top_m(node: Node3D) -> float:
	var top := 0.0
	for skeleton in node.find_children("*", "Skeleton3D", true, false):
		for mesh in skeleton.find_children("*", "MeshInstance3D", true, false):
			var box := (
				(mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()
			)
			top = maxf(top, box.end.y - node.global_position.y)
	return top if top > 0.0 else HEAD_M


func _frame_rect() -> Rect2:
	var size := root.get_visible_rect().size
	return Rect2(Vector2.ONE * MARGIN_PX, size - Vector2.ONE * MARGIN_PX * 2.0)


func _on_screen(point: Vector3) -> bool:
	if _cam.is_position_behind(point):
		return false
	return _frame_rect().has_point(_cam.unproject_position(point))


func _in_frame(point: Vector3, label: String) -> bool:
	var behind := _cam.is_position_behind(point)
	var screen := _cam.unproject_position(point)
	var ok := not behind and _frame_rect().has_point(screen)
	print("INFRAME %s screen=(%.0f,%.0f) behind=%s ok=%s" % [label, screen.x, screen.y, behind, ok])
	return ok


func _rect_in_frame(rect: Rect2, label: String) -> bool:
	var ok := _frame_rect().encloses(rect)
	print("INFRAME %s rect=%s ok=%s" % [label, rect, ok])
	return ok


## A physics ray from the camera to `point` is not stopped more than BLOCK_M short of it.
func _ray_clear(point: Vector3, label: String) -> bool:
	var space := _cam.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(_cam.global_position, point)
	var hit := space.intersect_ray(query)
	var short := 0.0
	if not hit.is_empty():
		short = (
			_cam.global_position.distance_to(point)
			- _cam.global_position.distance_to(hit["position"])
		)
	var ok := short <= BLOCK_M
	print("RAY %s hit=%s short_m=%.2f ok=%s" % [label, not hit.is_empty(), short, ok])
	return ok


## One sheet of every plate saved this run, each at half size, side by side.
func _contact_sheet() -> void:
	if _failed or _saved.is_empty():
		return
	var images: Array[Image] = []
	var width := 0
	var height := 0
	for path in _saved:
		var img := Image.load_from_file(path)
		img.convert(Image.FORMAT_RGBA8)
		img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
		images.append(img)
		width += img.get_width()
		height = maxi(height, img.get_height())
	var sheet := Image.create(width, height, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.1, 0.1, 0.12))
	var x := 0
	for img in images:
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(x, 0))
		x += img.get_width()
	var path := _out_dir.path_join("vip_contact_sheet.png")
	if sheet.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, sheet.get_size()])


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	_saved.append(path)
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
		_beat(_stage)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _beat(stage: String) -> void:
	_lock.lock()
	_stage = stage
	_beat_ms = Time.get_ticks_msec()
	_lock.unlock()


func _finish() -> void:
	_lock.lock()
	_stop = true
	_lock.unlock()
	_guard.wait_to_finish()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_lock.lock()
		var stop := _stop
		var stage := _stage
		var silent := Time.get_ticks_msec() - _beat_ms
		_lock.unlock()
		if stop:
			return
		if silent > HANG_MS:
			print("PROBE_INVALID hang: stage=%s silent_ms=%d" % [stage, silent])
			OS.crash("vip_marker_plates_probe: main thread stalled in %s" % stage)
