extends SceneTree
## Windowed Vulkan plate probe for board f0513fb8 (mechanics parity fixes):
##   1. 01_bench_1a_seating.png  - male and female passengers seated on bench_1a,
##      grounded, facing outward, clear of backrest.
##   2. 02a_tug_approach.png     - pushback tug driving in from starboard apron
##      during DOORS_CLOSED while jet bridge is docked on port side.
##   3. 02b_tug_coupled.png      - pushback tug coupled at Mount_NoseGear at
##      PUSHBACK start, clear of terminal wall.
##   4. 02c_tug_pullaway.png     - pushback tug uncoupled and pulling clear on
##      starboard apron during early TAXI_OUT.

const PlateSight := preload("res://spike/plate_sight.gd")
const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/mechanics_parity"
const MODEL := "tp_plane_04a"
const MARGIN_PX := 8.0
const WALL_CLEAR_M := 0.3

var _out_dir := ""
var _failed := false
var _plates := 0
var _elapsed := 0.0
var _main: Node3D
var _rig: TycoonCamera
var _rig_cam: Camera3D
var _probe_cam: Camera3D
var _hud: PassengerHud
var _build: BuildMode
var _grid: BuildGrid
var _sim: PassengerSim
var _views: PassengerViews
var _airside: Airside
var _view: PlaneView
var _stand: Dictionary = {}


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	print("PROBE out_dir=", _out_dir)
	_run.call_deferred()


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 90.0:
		_invalid("probe timed out after 90s")
		_finish()
		return true
	return false


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for _i in count:
		await process_frame
	await RenderingServer.frame_post_draw


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
	_rig = _main.get_node("TycoonCamera")
	_rig_cam = _rig.get_node("Camera3D")
	_hud = _main.get_node("PassengerHud")
	_build = _main.get_node("BuildMode")
	_grid = _build.grid
	_sim = _main.get_node("PassengerSim")
	_views = _main.get_node("PassengerViews")
	_airside = _main.get_node("Airside")
	_view = _main.get_node("PlaneView")
	_view.set_process(false)
	for node in _main.find_children("*", "Node3D", true, false):
		if node is PlaneView and node != _view:
			(node as Node3D).visible = false
			node.set_process(false)
	await _frames(6)

	_hud.press_starter_terminal()
	await _frames(6)
	if _airside.gate_stands.is_empty():
		_invalid("no gate stand created by starter terminal")
		_finish()
		return
	var gate: String = _airside.gate_stands.keys()[0]
	_stand = _airside.gate_stands[gate]
	_view.gate = gate

	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	for node in _main.find_children("*", "Node3D", true, false):
		if node is MissMarkers or node is GapMarkers:
			(node as Node3D).visible = false

	await _capture_bench_plate()
	await _capture_tug_plates()
	_finish()


func _finish() -> void:
	if is_instance_valid(_main):
		_main.free()
	print("PROBE done failed=%s plates=%d" % [_failed, _plates])
	quit(1 if _failed or _plates == 0 else 0)


func _find_bench_spot() -> Vector2i:
	for y in range(2, _grid.size.y - 4):
		for x in range(3, _grid.size.x - 3):
			var anchor := Vector2i(x, y)
			if not _grid.is_passenger_cell(anchor):
				continue
			var ok := true
			for dy in range(3):
				if not _grid.is_passenger_cell(anchor + Vector2i(-1, dy)):
					ok = false
					break
				if not _grid.is_passenger_cell(anchor + Vector2i(-2, dy)):
					ok = false
					break
			if not ok:
				continue
			if _grid.validate(BuildEdit.place_object(&"bench_1a", anchor, 0)).ok:
				return anchor
	return Vector2i(-1, -1)


func _capture_bench_plate() -> void:
	var anchor := _find_bench_spot()
	if anchor.x < 0:
		_invalid("no clear bench_1a spot on starter terminal floor")
		return
	var placed := _grid.apply(BuildEdit.place_object(&"bench_1a", anchor, 0))
	if not placed.ok:
		_invalid("bench_1a placement refused: %s" % placed.reason_text())
		return
	var build_view := _build.get_node("BuildView") as BuildView
	build_view.refresh(_grid)
	_sim.layout.rebuild(_grid)
	var bench_seats := _sim.layout.seats.filter(
		func(s: Dictionary) -> bool: return s["object_id"] == placed.object_id
	)
	if bench_seats.size() != 2:
		_invalid("expected 2 seats on bench_1a, got %d" % bench_seats.size())
		return

	if _sim.flights.flight_ids().is_empty():
		_sim.flights.add_flight(FlightSim.DEFAULT_ID, FlightSim.schedule_starts(0), _view.gate)
	if _sim.flights.flight_ids().is_empty():
		_invalid("no flights available to spawn bench passengers")
		return
	var fid := _sim.flights.flight_ids()[0]
	var pax_ids: Array[int] = []
	for i in 2:
		var seat: Dictionary = bench_seats[i]
		var pid := _sim.spawn_now(fid)
		if pid <= 0:
			_invalid("failed to spawn passenger for flight %s" % fid)
			return
		var p := _sim.get_passenger(pid)
		p.variant = i % 2
		p.cleared = true
		p.stage = Passenger.Stage.SEATED
		p.seat_object = placed.object_id
		p.seat_cell = seat["cell"]
		p.seat_front = seat["front"]
		p.seat_piece = Relocation.placement(_grid, placed.object_id)
		p.at = seat["front"]
		p.clear_path()
		pax_ids.append(pid)

	_views.snap()
	await _frames(6)

	var def := BuildCatalog.get_def(&"bench_1a")
	var bench_xf := BuildView.object_transform(_grid, def.footprint(anchor, 0), 0)
	var bench_node := build_view.find_child("bench_1a", true, false) as Node3D
	if bench_node == null:
		for child in build_view.get_children():
			if (
				child is Node3D
				and (child as Node3D).global_position.distance_to(bench_xf.origin) < 0.2
			):
				bench_node = child as Node3D
				break

	_rig.stop_follow()
	_rig.position = Vector3(bench_xf.origin.x - 0.35, 0.0, bench_xf.origin.z)
	_rig.yaw = -PI * 0.32
	_rig.distance = 6.2
	await _frames(10)

	var subjects := {}
	for i in pax_ids.size():
		var node := _views._nodes.get(pax_ids[i]) as Node3D
		if node == null:
			_invalid("missing PassengerViews node for passenger %d" % pax_ids[i])
			return
		subjects[node] = "pax_%d" % i
	if bench_node != null:
		subjects[bench_node] = "bench"

	if await _check_bench_visibility(build_view, subjects):
		await _save_plate("01_bench_1a_seating.png")


func _check_bench_visibility(build_view: BuildView, subjects: Dictionary) -> bool:
	var owners: Array[Node] = [build_view, _views]
	var holder := PlateSight.colliders(root, owners, subjects)
	var bounds: Dictionary = holder.get_meta("bounds")
	await physics_frame
	await physics_frame

	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	var space := _rig_cam.get_world_3d().direct_space_state
	var all_ok := true
	for tag_val in subjects.values():
		var tag := str(tag_val)
		var box: AABB = bounds.get(tag, AABB())
		if not _prove_box_in_frame("01_bench_1a_seating", _rig_cam, tag, box, rect):
			all_ok = false
			break
		if tag.begins_with("pax_"):
			var targets: Array[Vector3] = []
			var c := box.get_center()
			for dy in [-0.2, 0.0, 0.25]:
				targets.append(c + Vector3(0.0, dy, 0.0))
			var lines := PlateSight.sight_lines(space, _rig_cam.global_position, targets, tag)
			print(
				(
					"VISIBLE 01_bench_1a_seating %s on=%d blockers=%s"
					% [tag, (lines["on_subject"] as Array).size(), lines["blockers"]]
				)
			)
			if (
				(lines["on_subject"] as Array).is_empty()
				or not (lines["blockers"] as Array).is_empty()
			):
				_invalid("01_bench_1a_seating: %s occluded (%s)" % [tag, lines])
				all_ok = false
				break
	holder.free()
	return all_ok


func _capture_tug_plates() -> void:
	for sp in _main.find_children("*", "Sprite3D", true, false):
		(sp as Sprite3D).visible = false
	_probe_cam = Camera3D.new()
	_probe_cam.fov = 55.0
	_probe_cam.far = 2000.0
	_main.add_child(_probe_cam)
	_probe_cam.make_current()
	_rig.set_process(false)

	var props := _view.get_node("Props") as PlaneProps
	var tug := props.tug
	var wall_z := float(_stand["wall_z"])
	var bridge := _airside.props.bridges[_view.gate]["node"] as Node3D

	# 02a: DOORS_CLOSED tug approach (t = 0.6) with docked jet bridge on port side.
	var plane := _pose_plane(FlightSim.State.DOORS_CLOSED, 0.6)
	await _frames(4)
	_add_colliders(plane)
	_add_colliders(tug)
	_add_colliders(bridge)
	var box_a := _aabb_of(tug)
	print(
		(
			"TUG 02a approach: wall_clear=%.3f bridge_docked=%s"
			% [wall_z - box_a.end.z, _airside.props.bridges[_view.gate]["docked"]]
		)
	)
	if wall_z - box_a.end.z < WALL_CLEAR_M:
		_invalid("02a tug too close to wall: %.3f" % (wall_z - box_a.end.z))
		return
	var focus_a := box_a.get_center().lerp(_aabb_of(plane).get_center(), 0.15)
	_aim_probe(focus_a, 305.0, 24.0, 18.0)
	await _frames(4)
	if _prove_node("02a_tug_approach", tug) and _prove_seen("02a_tug_approach", plane):
		await _save_plate("02a_tug_approach.png")

	# 02b: PUSHBACK coupled (t = 0.0).
	plane = _pose_plane(FlightSim.State.PUSHBACK, 0.0)
	await _frames(4)
	var gear := plane.global_transform * PlaneProps.nose_gear_contact(plane, MODEL)
	var on_gear := tug.find_child("Mount_NoseGear", true, false) as Node3D
	var gear_off := on_gear.global_position.distance_to(gear)
	var box_b := _aabb_of(tug)
	print("TUG 02b coupled: gear_off=%.4f wall_clear=%.3f" % [gear_off, wall_z - box_b.end.z])
	if gear_off >= 0.01 or wall_z - box_b.end.z < WALL_CLEAR_M:
		_invalid("02b tug not coupled or wall gap violated")
		return
	_aim_probe(box_b.get_center(), 266.0, 23.0, 13.5)
	await _frames(4)
	if _prove_node("02b_tug_coupled", tug) and _prove_seen("02b_tug_coupled", plane):
		await _save_plate("02b_tug_coupled.png")

	# 02c: TAXI_OUT pull-away (t = 0.04).
	plane = _pose_plane(FlightSim.State.TAXI_OUT, 0.04)
	await _frames(4)
	var box_c := _aabb_of(tug)
	var focus_c := box_c.get_center().lerp(_aabb_of(plane).get_center(), 0.2)
	print(
		"TUG 02c pullaway: tug_pos=%s plane_pos=%s" % [tug.global_position, plane.global_position]
	)
	_aim_probe(focus_c, 125.0, 26.0, 20.0)
	await _frames(4)
	if _prove_node("02c_tug_pullaway", tug) and _prove_seen("02c_tug_pullaway", plane):
		await _save_plate("02c_tug_pullaway.png")


func _pose_plane(at_phase: int, progress: float) -> Node3D:
	_view.show_model(MODEL)
	var p_class := PlaneClasses.MEDIUM
	var moving: int = PlaneView.REST_AFTER.get(at_phase, at_phase)
	var move_t := 1.0 if PlaneView.REST_AFTER.has(at_phase) else progress
	var path := _view._path(moving, p_class)
	var entry := _view._entry_dir(moving, p_class)
	var pose := FlightPose.pose(moving, move_t, path, entry)
	pose.origin.y += PlaneView.ground_height_at(pose.origin)
	_view.transform = pose
	_view.phase = at_phase
	_view._phase_progress = progress
	_view.visible = true
	_view.flight_id = "probe"
	_view._set_model_position(_view.model_position_at(at_phase, pose, p_class))
	var props := _view.get_node("Props") as PlaneProps
	var uncouple_xform := Transform3D.IDENTITY
	if at_phase == FlightSim.State.TAXI_OUT:
		var push_path := _view._path(FlightSim.State.PUSHBACK, p_class)
		var push_entry := _view._entry_dir(FlightSim.State.PUSHBACK, p_class)
		var push_pose := FlightPose.pose(FlightSim.State.PUSHBACK, 1.0, push_path, push_entry)
		push_pose.origin.y += PlaneView.ground_height_at(push_pose.origin)
		var model_pos := _view.model_position_at(FlightSim.State.PUSHBACK, push_pose, p_class)
		uncouple_xform = push_pose * Transform3D(Basis.IDENTITY, model_pos)
	var model_node := _view.get_node("Pivot").get_child(0) as Node3D
	props.follow(
		true,
		model_node,
		MODEL,
		at_phase,
		_view.gate,
		_airside,
		_view.get_instance_id(),
		progress,
		uncouple_xform
	)
	if model_node.find_children("*", "StaticBody3D", true, false).is_empty():
		_add_colliders(model_node)
	return model_node


func _aim_probe(focus: Vector3, yaw: float, pitch: float, distance: float) -> void:
	var y := deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	var back := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
	_probe_cam.look_at_from_position(focus + back * distance, focus, Vector3.UP)


func _prove_box_in_frame(label: String, cam: Camera3D, tag: String, box: AABB, rect: Rect2) -> bool:
	if box.size == Vector3.ZERO:
		_invalid("%s: %s has empty bounds" % [label, tag])
		return false
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var p := box.get_endpoint(i)
		if cam.is_position_behind(p):
			_invalid("%s: %s is behind camera" % [label, tag])
			return false
		var s := cam.unproject_position(p)
		lo = lo.min(s)
		hi = hi.max(s)
	var ok := rect.has_point(lo) and rect.has_point(hi)
	print(
		(
			"INFRAME %s %s screen=(%.0f,%.0f)-(%.0f,%.0f) ok=%s"
			% [label, tag, lo.x, lo.y, hi.x, hi.y, ok]
		)
	)
	if not ok:
		_invalid("%s: %s leaves viewport" % [label, tag])
	return ok


func _prove_node(label: String, subject: Node3D) -> bool:
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	if not subject.is_visible_in_tree():
		_invalid("%s: %s hidden" % [label, subject.name])
		return false
	if not _prove_box_in_frame(label, _probe_cam, subject.name, _aabb_of(subject), rect):
		return false
	return _prove_seen(label, subject)


func _prove_seen(label: String, subject: Node3D) -> bool:
	var targets: Array[Vector3] = []
	var box := _aabb_of(subject)
	var centre := box.get_center()
	for mi in _meshes(subject):
		if not mi.is_visible_in_tree():
			continue
		var faces: PackedVector3Array = mi.mesh.get_faces()
		var step := maxi(1, floori(faces.size() / 24.0))
		for i in range(0, faces.size(), step):
			targets.append((mi.global_transform * faces[i]).lerp(centre, 0.05))
	var space := _probe_cam.get_world_3d().direct_space_state
	var hits := 0
	for t in targets:
		var q := PhysicsRayQueryParameters3D.create(
			_probe_cam.global_position, t + (t - _probe_cam.global_position).normalized() * 0.05
		)
		var hit := space.intersect_ray(q)
		if hit and (hit.collider == subject or subject.is_ancestor_of(hit.collider)):
			hits += 1
	var share := float(hits) / maxf(1.0, targets.size())
	print(
		(
			"VISIBLE %s %s ray_hits=%d/%d share=%.2f"
			% [label, subject.name, hits, targets.size(), share]
		)
	)
	if share < 0.25:
		_invalid("%s: %s occluded" % [label, subject.name])
		return false
	return true


func _save_plate(name: String) -> void:
	await _frames(2)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := _out_dir.path_join(name)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	_plates += 1
	print("PLATE saved %s" % path)


func _add_colliders(node: Node) -> void:
	for mi in _meshes(node):
		if mi.mesh != null and mi.find_children("*", "StaticBody3D", false, false).is_empty():
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
