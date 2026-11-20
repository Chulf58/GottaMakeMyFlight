extends SceneTree
## Windowed Vulkan plate probe for small walk-boarding plane self-taxi (board
## 725ff41c): renders a 3-panel strip (`self_taxi_strip.png`) showing
## tp_plane_03a parked box-centred on stand_point with folded bridge and apron
## boarding walk, mid-180-degree pivot away from the bridge with no tug, and
## rolling forward out of the stand; plus `medium_tug_control.png` showing
## tp_plane_05a in PUSHBACK with its towbarless pushback tug intact.
##
## Run (one windowed Godot run project-wide):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/.claude/worktrees/small-plane-self-taxi/game \
##     -s res://spike/small_plane_self_taxi_probe.gd

const StarterFlight := preload("res://spike/starter_flight.gd")
const PASSENGER := preload("res://assets/people/tcp_male_character_01.glb")
const MAIN_SCENE := "res://main/main.tscn"
const OUT_DIR := "C:/Users/chulf/Gotta-make-my-flight/tools/blender/out/small-plane-self-taxi"
const MARGIN_PX := 8.0
const FOV := 50.0
const TILE_SIZE := Vector2i(640, 360)

var _failed := false
var _main: Node
var _cam: Camera3D
var _view: PlaneView
var _airside: Airside
var _gate := ""
var _stand: Dictionary = {}
var _guests: Array[Node3D] = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	print("PROBE out_dir=", OUT_DIR)
	_run.call_deferred()


func _run() -> void:
	_main = load(MAIN_SCENE).instantiate()
	var clock: SimClock = _main.get_node("SimClock")
	var world_seed := randi()
	clock.seed_rng(world_seed)
	print("PROBE world_seed=%d" % world_seed)
	root.add_child(_main)
	clock.set_process(false)
	for fleet in _main.find_children("*", "PlaneFleet", true, false):
		fleet.set_process(false)
	_view = _main.get_node("PlaneView")
	_view.set_process(false)
	(_main.get_node("PlaneView2") as Node).set_process(false)
	_airside = _main.get_node("Airside")
	await _frames(6)
	if not StarterFlight.add_gate_desk((_main.get_node("BuildMode") as BuildMode).grid):
		_invalid("gate desk refused")
		_finish()
		return
	await _frames(6)
	if _airside.gate_stands.is_empty():
		_invalid("no gate stand")
		_finish()
		return
	_gate = _airside.gate_stands.keys()[0]
	_stand = _airside.gate_stands[_gate]
	_view.gate = _gate
	_show_hud(false)
	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.far = 2000.0
	_main.add_child(_cam)
	_cam.make_current()

	var strip := Image.create(TILE_SIZE.x * 3, TILE_SIZE.y, false, Image.FORMAT_RGBA8)
	var stand_pos := StandPlacement.stand_point(_stand)
	var bridge: Node3D = _airside.props.bridges[_gate]["node"]
	var apron_walk: PackedVector3Array = (
		JetBridgePose
		. pose_for(_stand, "tp_plane_03a", false, JetBridgePose.ground_y(_stand))["apron_walk"]
	)

	# Tile 1: tp_plane_03a parked at gate with folded bridge and apron walkers.
	var model := _pose("tp_plane_03a", PlaneClasses.SMALL, FlightSim.State.BOARDING, 0.5, 10.0)
	var prop := model.find_child(PlaneView.PROPELLER_NODE, true, false) as Node3D
	if prop == null:
		_invalid("missing propeller node on 03a")
	else:
		var boarding_basis := prop.basis
		_pose("tp_plane_03a", PlaneClasses.SMALL, FlightSim.State.BOARDING, 0.5, 14.5)
		if not prop.basis.is_equal_approx(boarding_basis):
			_invalid("propeller moved during BOARDING")
	_spawn_guests(apron_walk)
	_add_colliders(_main)
	var focus_parked := stand_pos.lerp(apron_walk[1], 0.35) + Vector3(0.0, 1.0, 0.0)
	_aim(focus_parked, 70.0, 26.0, 25.0)
	await _frames(3)
	var tug := (_view.get_node("Props") as PlaneProps).tug
	if tug.is_visible_in_tree():
		_invalid("tug visible on 03a at gate")
	if not _prove("03a_parked", [model, bridge] + _guests, true):
		_finish()
		return
	var img1 := await _capture()
	img1.resize(TILE_SIZE.x, TILE_SIZE.y)
	strip.blit_rect(img1, Rect2i(Vector2i.ZERO, TILE_SIZE), Vector2i(0, 0))
	_clear_guests()

	# Tile 2: tp_plane_03a mid-180 turn in PUSHBACK (t = 0.20, pilot's right / west).
	# Record propeller rotation across multiple pivot steps and verify hub stability.
	_pose("tp_plane_03a", PlaneClasses.SMALL, FlightSim.State.PUSHBACK, 0.10, 12.0)
	var hub_a := prop.position
	var basis_a := prop.basis
	_pose("tp_plane_03a", PlaneClasses.SMALL, FlightSim.State.PUSHBACK, 0.30, 36.0)
	var delta_turn := basis_a.x.angle_to(prop.basis.x)
	var hub_shift := prop.position.distance_to(hub_a)
	print("PROBE pushback_pivot_prop_delta_rad=%.4f hub_shift=%.6f" % [delta_turn, hub_shift])
	if delta_turn <= 0.1:
		_invalid("propeller rotation delta zero during PUSHBACK pivot: %.4f" % delta_turn)
	if prop.position.distance_to(hub_a) > 1e-5:
		_invalid("propeller hub shifted during PUSHBACK pivot")
	model = _pose("tp_plane_03a", PlaneClasses.SMALL, FlightSim.State.PUSHBACK, 0.20, 24.0)
	_add_colliders(_main)
	_aim(stand_pos + Vector3(0.0, 1.0, 2.0), 155.0, 32.0, 26.0)
	await _frames(3)
	if tug.is_visible_in_tree():
		_invalid("tug visible on 03a mid-turn")
	if not _prove("03a_mid_turn", [model, bridge], true):
		_finish()
		return
	var img2 := await _capture()
	img2.resize(TILE_SIZE.x, TILE_SIZE.y)
	strip.blit_rect(img2, Rect2i(Vector2i.ZERO, TILE_SIZE), Vector2i(TILE_SIZE.x, 0))

	# Tile 3: tp_plane_03a rolling forward out in PUSHBACK (t = 0.75, facing north).
	model = _pose("tp_plane_03a", PlaneClasses.SMALL, FlightSim.State.PUSHBACK, 0.75, 90.0)
	_add_colliders(_main)
	var back_pos := StandPlacement.pushback_end(_stand)
	_aim(stand_pos.lerp(back_pos, 0.55) + Vector3(0.0, 1.0, 0.0), 140.0, 32.0, 32.0)
	await _frames(3)
	if tug.is_visible_in_tree():
		_invalid("tug visible on 03a roll-out")
	if not _prove("03a_roll_out", [model], true):
		_finish()
		return
	var img3 := await _capture()
	img3.resize(TILE_SIZE.x, TILE_SIZE.y)
	strip.blit_rect(img3, Rect2i(Vector2i.ZERO, TILE_SIZE), Vector2i(TILE_SIZE.x * 2, 0))

	var strip_path := OUT_DIR.path_join("self_taxi_strip.png")
	if strip.save_png(strip_path) != OK:
		_invalid("could not save %s" % strip_path)
	else:
		print("PLATE saved ", strip_path)

	# Control: tp_plane_05a in PUSHBACK (t = 0.35) with its pushback tug intact.
	model = _pose("tp_plane_05a", PlaneClasses.MEDIUM, FlightSim.State.PUSHBACK, 0.35)
	_add_colliders(_main)
	var tug_box := _aabb_of(tug)
	var control_focus := _aabb_of(model).merge(tug_box).get_center()
	_aim(control_focus, 130.0, 26.0, 48.0)
	await _frames(3)
	if not tug.is_visible_in_tree():
		_invalid("tug hidden on 05a control")
	if not _prove("05a_tug_control", [model, tug], true):
		_finish()
		return
	var ctrl := await _capture()
	var ctrl_path := OUT_DIR.path_join("medium_tug_control.png")
	if ctrl.save_png(ctrl_path) != OK:
		_invalid("could not save %s" % ctrl_path)
	else:
		print("PLATE saved ", ctrl_path)
	_finish()


func _pose(model: String, plane_class: String, state: int, t: float, sim_time := 0.0) -> Node3D:
	_view.show_model(model)
	var path := _view._path(FlightSim.State.PUSHBACK, plane_class)
	var entry := _view._entry_dir(FlightSim.State.PUSHBACK, plane_class)
	var pose := FlightPose.pose(
		state if state == FlightSim.State.PUSHBACK else FlightSim.State.TAXI_IN,
		t if state == FlightSim.State.PUSHBACK else 1.0,
		(
			path
			if state == FlightSim.State.PUSHBACK
			else _view._path(FlightSim.State.TAXI_IN, plane_class)
		),
		entry,
		{},
		0.0,
		PlaneClasses.self_taxis(model)
	)
	pose.origin.y += PlaneView.ground_height_at(pose.origin)
	_view.transform = pose
	_view.phase = state
	_view.visible = true
	_view.flight_id = "probe"
	_view._set_model_position(_view.model_position_at(state, pose, plane_class))
	_view._spin_propeller(sim_time)
	_view._follow_props()
	return _view.get_node("Pivot").get_child(0) as Node3D


func _spawn_guests(walk: PackedVector3Array) -> void:
	_clear_guests()
	# apron_walk indices: 2 (outside apron door), 3 (prop/strut-clear waypoint), 4 (door end).
	for i in range(2, walk.size()):
		var g: Node3D = PASSENGER.instantiate()
		g.name = "Guest%d" % (i - 1)
		g.position = walk[2].lerp(walk[3], 0.20) if i == 2 else walk[i]
		if i + 1 < walk.size():
			var dir := walk[i + 1] - walk[i]
			g.rotation.y = atan2(dir.x, dir.z)
		else:
			var dir := walk[i] - walk[i - 1]
			g.rotation.y = atan2(dir.x, dir.z)
		_main.add_child(g)
		_add_colliders(g)
		_guests.append(g)


func _clear_guests() -> void:
	for g in _guests:
		g.queue_free()
	_guests.clear()


func _aim(focus: Vector3, yaw: float, pitch: float, distance: float) -> void:
	var y := deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	var back := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
	_cam.look_at_from_position(focus + back * distance, focus, Vector3.UP)


func _prove(label: String, subjects: Array, need_rays: bool) -> bool:
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	for subject: Node3D in subjects:
		var shown := _meshes(subject).filter(
			func(mi: MeshInstance3D) -> bool: return mi.is_visible_in_tree()
		)
		if not subject.is_visible_in_tree() or shown.is_empty():
			_invalid("%s: %s is hidden or has no visible mesh" % [label, subject.name])
			return false
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for i in 8:
			var p := _aabb_of(subject).get_endpoint(i)
			if _cam.is_position_behind(p):
				_invalid("%s: %s is behind the camera" % [label, subject.name])
				return false
			var s := _cam.unproject_position(p)
			lo = lo.min(s)
			hi = hi.max(s)
		var ok := rect.has_point(lo) and rect.has_point(hi)
		print(
			(
				"INFRAME %s %s screen=(%.0f,%.0f)-(%.0f,%.0f) ok=%s"
				% [label, subject.name, lo.x, lo.y, hi.x, hi.y, ok]
			)
		)
		if not ok:
			_invalid("%s: %s leaves the viewport" % [label, subject.name])
			return false
		if need_rays and _report_rays("VISIBLE %s %s" % [label, subject.name], subject) < 0.25:
			_invalid("%s: %s is occluded" % [label, subject.name])
			return false
	return true


func _report_rays(label: String, subject: Node3D) -> float:
	var targets: Array[Vector3] = []
	var centre := _aabb_of(subject).get_center()
	for mi in _meshes(subject):
		if not mi.is_visible_in_tree():
			continue
		var faces: PackedVector3Array = mi.mesh.get_faces()
		var step := maxi(1, floori(faces.size() / 24.0))
		for i in range(0, faces.size(), step):
			targets.append((mi.global_transform * faces[i]).lerp(centre, 0.05))
	var space := _cam.get_world_3d().direct_space_state
	var hits := 0
	for t in targets:
		var q := PhysicsRayQueryParameters3D.create(
			_cam.global_position, t + (t - _cam.global_position).normalized() * 0.05
		)
		var hit := space.intersect_ray(q)
		if hit and (hit.collider == subject or subject.is_ancestor_of(hit.collider)):
			hits += 1
	var share := float(hits) / maxf(1.0, targets.size())
	print("%s ray_hits=%d/%d share=%.2f" % [label, hits, targets.size(), share])
	return share


func _capture() -> Image:
	await _frames(2)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _show_hud(on: bool) -> void:
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = on


func _add_colliders(node: Node) -> void:
	for mi in _meshes(node):
		if mi.mesh == null:
			continue
		var bodies := mi.find_children("*", "StaticBody3D", false, false)
		if not mi.is_visible_in_tree():
			for b in bodies:
				mi.remove_child(b)
				b.queue_free()
		elif bodies.is_empty():
			mi.create_trimesh_collision()


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		out.append(mi)
	return out


func _aabb_of(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(node):
		if not mi.is_visible_in_tree():
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _finish() -> void:
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)
