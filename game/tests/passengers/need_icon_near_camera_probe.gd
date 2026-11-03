extends SceneTree
## Windowed plates of need icons over a passenger close to the camera (board
## 73e15dd7 part 6: "at close zoom a need icon sits on the head of a passenger
## right under the camera"). The room label at close zoom (part 5) is already
## plated by game/spike/room_label_zoom_plate_probe.gd. Boots main.tscn with the starter shell,
## opens the airport, lets passengers arrive and makes every one hungry. The
## camera goes to its closest zoom (TycoonCamera.min_distance) with the
## passenger nearest the focus placed in front of the camera, so it stands
## close to the lens.
##
## Measures, per plate and in screen pixels of the viewport:
##   OWN_GAP     the gap between the subject's head top and its own icon row;
##               a gap under 0 means the icon sits on its own head
##   FOREIGN     how many icons of OTHER passengers land on the subject's head
##               rect (icons draw with no depth test, so a passenger behind
##               the subject can put an icon on the subject's head)
## Proofs before a plate is saved: the head, the feet and the icon anchor
## project inside the frame by MARGIN_PX and in front of the camera, a
## physics ray from the camera to the head is not blocked nearer than
## BLOCK_M, the subject's icon is visible, and at least one other icon is
## visible (a control: a count of zero would pass by accident). Otherwise
## PROBE_INVALID, exit 1. A guard thread calls OS.crash() on a stall.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 600 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://tests/passengers/need_icon_near_camera_probe.gd
##
## Plates go to tools/blender/out/need_icon_near_camera/.

const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/need_icon_near_camera"
const MARGIN_PX := 8.0
const HANG_MS := 120000
const HEAD_M := 1.7
const HEAD_RECT_M := 0.35
const BLOCK_M := 0.5
const WANT_PASSENGERS := 10
const ARRIVE_LIMIT_TICKS := 1500
## Metres the camera focus sits ahead of the subject, along the view's ground
## direction, so the subject stands between the focus and the lens.
const AHEAD_M := 2.5
## Distances as a fraction of home_distance: the closest zoom, then a middle one.
const CLOSE_RATIOS := [0.0, 0.4]

var _out_dir := ""
var _failed := false
var _main: Node3D
var _sim: PassengerSim
var _clock: SimClock
var _views: PassengerViews
var _rig: TycoonCamera
var _cam: Camera3D
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
	root.add_child(_main)
	_clock.set_paused(true)
	await _frames(5)
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	(_main.get_node("BuildMode") as BuildMode).set_tool(BuildMode.Tool.NONE)
	await _frames(20)
	_clock.set_process(false)
	_sim = _main.get_node("PassengerSim") as PassengerSim
	_views = _main.get_node("PassengerViews") as PassengerViews
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
		_sim.get_passenger(_sim.spawn_now(StarterFlight.first_flight())).hunger = 100
	_clock.set_paused(false)
	var until := _clock.tick + ARRIVE_LIMIT_TICKS
	while _clock.tick < until:
		_clock.advance(SimClock.STEP)
		for id in _sim.passenger_ids():
			_sim.get_passenger(id).hunger = 100
	await _frames(2)
	print("PROBE passengers=%d" % _sim.passenger_ids().size())
	_rig = _main.get_node("TycoonCamera") as TycoonCamera
	_cam = _rig.get_node("Camera3D") as Camera3D
	_cam.make_current()
	_clock.set_paused(true)
	await _frames(4)
	for ratio: float in CLOSE_RATIOS:
		_beat("plate_%.2f" % ratio)
		await _plate(ratio)
	_finish()


## One plate at `ratio` of the home distance (0 means min_distance).
func _plate(ratio: float) -> void:
	var subject := _pick_subject()
	if subject == 0:
		_invalid("no passenger with a shown icon to look at")
		return
	var node := _views.node_for(subject)
	var distance := _rig.min_distance if ratio <= 0.0 else _rig.home_distance * ratio
	_rig.yaw = 0.35
	_rig.distance = distance
	_rig.zoom(1.0)
	await _frames(2)
	var ahead := -_cam.global_basis.z
	ahead.y = 0.0
	_rig.position = node.global_position * Vector3(1, 0, 1) + ahead.normalized() * AHEAD_M
	await _frames(8)
	var tag := (
		"close_%s id=%d distance=%.1f"
		% ["min" if ratio <= 0.0 else "%.2f" % ratio, subject, _rig.distance]
	)
	var body_top := _body_top_m(node)
	var head := node.global_position + Vector3(0.0, body_top, 0.0)
	print("PROBE %s body_top_m=%.2f icon_anchor_m=%.2f" % [tag, body_top, NeedIcons.LIFT_M])
	var ok := _in_frame(head, tag + " head") and _in_frame(node.global_position, tag + " feet")
	var first := node.get_node(NeedIcons.SPRITES[0]) as Sprite3D
	ok = _in_frame(node.global_transform * first.position, tag + " anchor") and ok
	ok = _ray_clear(head, tag) and ok
	if not first.visible:
		_invalid("%s: the subject's icon is not visible" % tag)
		return
	var to_plate := Vector2(root.get_texture().get_size()) / root.get_visible_rect().size
	for id in _sim.passenger_ids():
		var other := _views.node_for(id)
		var sprite := other.get_node(NeedIcons.SPRITES[0]) as Sprite3D
		print(
			(
				"WHO %s id=%d stage=%s needs=%d root_plate=%s head_plate=%s anchor_plate=%s"
				% [
					tag.get_slice(" ", 0),
					id,
					Passenger.Stage.keys()[_sim.get_passenger(id).stage],
					other.get_meta(&"needs", 0),
					(_cam.unproject_position(other.global_position) * to_plate).round(),
					(
						(
							_cam.unproject_position(
								other.global_position + Vector3(0.0, _body_top_m(other), 0.0)
							)
							* to_plate
						)
						. round()
					),
					(
						(
							_cam.unproject_position(other.global_transform * sprite.position)
							* to_plate
						)
						. round()
					),
				]
			)
		)
	var head_rect := _head_rect(head)
	var own := _icon_rects(node)
	var foreign := 0
	for id in _sim.passenger_ids():
		if id == subject:
			continue
		for rect in _icon_rects(_views.node_for(id)):
			if rect.intersects(head_rect):
				foreign += 1
	var other_icons := 0
	for id in _sim.passenger_ids():
		other_icons += _icon_rects(_views.node_for(id)).size() if id != subject else 0
	var gap := INF
	for rect in own:
		gap = minf(gap, head_rect.position.y - rect.end.y)
	print(
		(
			"PLATE %s head_rect=%s own_icons=%d OWN_GAP=%.1f FOREIGN=%d other_icons=%d"
			% [tag, head_rect, own.size(), gap, foreign, other_icons]
		)
	)
	if other_icons == 0:
		_invalid("%s: no other icon is visible, the FOREIGN count proves nothing" % tag)
		return
	if not ok:
		_invalid("%s: the subject is out of frame or blocked" % tag)
		return
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	_save(img, "%s.png" % tag.get_slice(" ", 0))
	var to_image := Vector2(img.get_size()) / root.get_visible_rect().size
	var crop := Rect2i(head_rect.get_center() * to_image - Vector2(120, 120), Vector2i(240, 240))
	crop = crop.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var small := img.get_region(crop)
	small.resize(small.get_width() * 3, small.get_height() * 3, Image.INTERPOLATE_NEAREST)
	_save(small, "%s_crop.png" % tag.get_slice(" ", 0))


## The height over the node's root of the top of its skinned body meshes, in
## metres (the body's own bounds, not an assumed height).
func _body_top_m(node: Node3D) -> float:
	var top := 0.0
	for skeleton in node.find_children("*", "Skeleton3D", true, false):
		for mesh in skeleton.find_children("*", "MeshInstance3D", true, false):
			var box := (
				(mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()
			)
			top = maxf(top, box.end.y - node.global_position.y)
	return top if top > 0.0 else HEAD_M


## The passenger with a shown icon nearest the rig's current focus.
func _pick_subject() -> int:
	var best := 0
	var best_d := INF
	for id in _sim.passenger_ids():
		var node := _views.node_for(id)
		if node == null or node.get_meta(&"needs", 0) == 0:
			continue
		var d := node.global_position.distance_to(_rig.global_position)
		if d < best_d:
			best = id
			best_d = d
	return best


## The screen rectangle of the top HEAD_RECT_M of a person whose head top is `head`.
func _head_rect(head: Vector3) -> Rect2:
	var top := _cam.unproject_position(head + Vector3(0.0, 0.1, 0.0))
	var low := _cam.unproject_position(head - Vector3(0.0, HEAD_RECT_M, 0.0))
	var height := absf(low.y - top.y)
	return Rect2(Vector2(top.x - height / 2.0, top.y), Vector2(height, height))


## Screen rectangles of the icons a passenger node shows, as NeedIcons lays them
## out (ICON_PX square around the sprite's offset from its anchor).
func _icon_rects(node: Node3D) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var count: int = node.get_meta(&"needs", 0)
	var k := NeedIcons.ICON_PX / NeedIcons.SIZE
	for i in count:
		var sprite := node.get_node(NeedIcons.SPRITES[i]) as Sprite3D
		if not sprite.visible:
			continue
		var anchor := node.global_transform * sprite.position
		if _cam.is_position_behind(anchor):
			continue
		var at := _cam.unproject_position(anchor)
		var centre := at + Vector2(sprite.offset.x * k, -sprite.offset.y * k)
		out.append(
			Rect2(centre - Vector2.ONE * NeedIcons.ICON_PX / 2.0, Vector2.ONE * NeedIcons.ICON_PX)
		)
	return out


func _in_frame(point: Vector3, label: String) -> bool:
	var size := root.get_visible_rect().size
	var rect := Rect2(Vector2.ONE * MARGIN_PX, size - Vector2.ONE * MARGIN_PX * 2.0)
	var behind := _cam.is_position_behind(point)
	var screen := _cam.unproject_position(point)
	var ok := not behind and rect.has_point(screen)
	print("INFRAME %s screen=(%.0f,%.0f) behind=%s ok=%s" % [label, screen.x, screen.y, behind, ok])
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


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
		_beat(_stage)
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
			OS.crash("need_icon_near_camera_probe: main thread stalled in %s" % stage)
