extends SceneTree
## Windowed plate probe for passengers boarding through the jet bridge (board
## 927ed9e0; decision bridge-boarding-sim-route-chosen-at-departure-from-the-
## fligh). It rules nothing. For planes 04, 05, 06 and 07 docked at the gate it
## puts real passengers on the sim's walk out (OutsideWalks.departure()) and
## lets PassengerViews draw them: one on the stair, one in the cab and one in
## the cab's door opening, 0.8 m short of the plane door (nearer, the opaque
## bellows hide it). It saves a plate of the stair from the east and one of the
## cab and the door from the east, both through the glazing. For plane 03 it
## saves one with a passenger just out of the apron door and one on its walk to
## the plane.
##
## Run (one windowed Godot run project-wide; hold tools/blender/out/.windowed.lock):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/bridge_boarding_plates_probe.gd
##
## Boots main.tscn with the starter shell and a gate desk (StarterFlight); the
## clock, the fleets and the PlaneViews stop processing, the probe poses the
## main PlaneView at the stand as update_pose() does (it reports its model to
## the bridge), and the passengers stand still where it puts them. Before a
## plate is saved every guest in it is projected into the viewport with
## MARGIN_PX and camera rays are cast at it; the rays meet colliders on every
## mesh except the bridge's glass panes. On failure it prints PROBE_INVALID and
## exits 1. The HUD CanvasLayers are hidden. Prints the world seed and, per
## guest, its point on the walk and the bridge floor under it.

const StarterFlight := preload("res://spike/starter_flight.gd")
const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/bridge_boarding"
const MARGIN_PX := 8.0
const FOV := 50.0
const GLASS := "TP_Glass_1A_D"
const DOCKING: Array[String] = ["tp_plane_04a", "tp_plane_05a", "tp_plane_06a", "tp_plane_07a"]
const ON_FOOT := "tp_plane_03a"
## The share of rays that must reach a guest.
const GUEST_SEEN := 0.15
const PROBE_FLIGHT := "PROBE"
## The cab and door plate's views, (yaw, pitch) in degrees, tried in order.
const CAB_VIEWS: Array[Vector2] = [
	Vector2(90.0, 8.0), Vector2(180.0, 8.0), Vector2(150.0, 10.0), Vector2(60.0, 10.0)
]

var _out_dir := ""
var _failed := false
var _main: Node
var _cam: Camera3D
var _view: PlaneView
var _airside: Airside
var _sim: PassengerSim
var _views: PassengerViews
var _gate := ""
var _stand: Dictionary = {}
var _exit := 0
var _plates: Array[String] = []


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	print("PROBE out_dir=", _out_dir)
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
	_sim = _main.get_node("PassengerSim")
	_views = _main.get_node("PassengerViews")
	await _frames(6)
	if not StarterFlight.add_gate_desk((_main.get_node("BuildMode") as BuildMode).grid):
		_invalid("the gate desk was refused")
		_finish()
		return
	await _frames(6)
	if _airside.gate_stands.is_empty() or _airside.props.bridges.is_empty():
		_invalid("no gate got a stand and a bridge")
		_finish()
		return
	_gate = _airside.gate_stands.keys()[0]
	_stand = _airside.gate_stands[_gate]
	_exit = int(_stand["exit"])
	_view.gate = _gate
	var starts := FlightSim.schedule_starts(clock.tick + 100000)
	if not _sim.flights.add_flight(PROBE_FLIGHT, starts, _gate):
		_invalid("the probe's flight was refused")
		_finish()
		return
	print("PROBE gate=%s stand=%s exit=%d" % [_gate, _stand, _exit])
	_show_hud(false)
	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.far = 2000.0
	_main.add_child(_cam)
	_cam.make_current()
	var bridge: Node3D = _airside.props.bridges[_gate]["node"]
	_add_colliders(_main, bridge)
	_add_bridge_colliders(bridge)
	for model in DOCKING:
		await _docked_plates(model)
	await _apron_plates()
	_contact_sheet()
	_finish()


## Plane `model` docked: guests on the stair, in the cab and at the door.
func _docked_plates(model: String) -> void:
	var entry: Dictionary = _airside.props.bridges[_gate]
	_pose(model)
	await _frames(3)
	var walk := OutsideWalks.departure(_sim, _exit, model)
	var docks := OutsideWalks.docks_at(_sim, _exit, model)
	print("WALK %s docked=%s docks_at=%s %s" % [model, entry["docked"], docks, walk])
	if not entry["docked"] or walk.size() != 6:
		_invalid("%s: the bridge did not dock or the walk is not the bridge's" % model)
		return
	var walker := Passenger.new()
	walker.apron = walk
	var mm := [0, 0, 0, 0, 0, 0]
	for i in range(1, walk.size()):
		mm[i] = mm[i - 1] + walker.apron_segment_mm(i)
	# Stair: halfway up; cab: in its back half, 0.9 m short of the cab floor
	# point (off the line from the east camera to the door guest);
	# door: 0.8 m short of the plane door, in the cab's door opening (nearer
	# the plane it is inside the opaque bellows, which no camera sees through).
	var stair := _guest(walk, (mm[2] + mm[3]) / 2)
	var cab := _guest(walk, mm[4] - 900)
	var door := _guest(walk, mm[5] - 800)
	await _show_guests()
	var tag := model.substr(9, 2)
	var top: Vector3 = walk[3]
	_aim((walk[2] + top) / 2.0 + Vector3.UP * 1.0, 90.0, 10.0, 9.0)
	await _frames(3)
	var name := "bridge_board_%s_stair.png" % tag
	if _proved(name, [stair]):
		await _save(name)
	# From the east; plane 04's port engine stands in that view, so other
	# views follow. Each view is proved; the first that passes is saved.
	name = "bridge_board_%s_cab_door.png" % tag
	var failed := _failed
	for view: Vector2 in CAB_VIEWS:
		_failed = failed
		_aim((walk[4] + walk[5]) / 2.0 + Vector3.UP * 0.9, view.x, view.y, 8.0)
		await _frames(3)
		if _proved(name, [cab, door]):
			await _save(name)
			break
	_clear_guests()


## Plane 03: a guest at the apron door and one on the walk to the plane.
func _apron_plates() -> void:
	var entry: Dictionary = _airside.props.bridges[_gate]
	_pose(ON_FOOT)
	await _frames(3)
	var walk := OutsideWalks.departure(_sim, _exit, ON_FOOT)
	var want := JetBridgePose.pose_for(_stand, ON_FOOT, false, _sim.site.ground_height)
	var apron_door: Vector3 = want["mounts"][&"Mount_ApronDoor"]
	print("WALK 03 docked=%s %s apron door %s" % [entry["docked"], walk, apron_door])
	if entry["docked"] or walk.size() != 4:
		_invalid("03: the bridge docked or the walk is not the apron door's")
		return
	var walker := Passenger.new()
	walker.apron = walk
	var to_door := walker.apron_segment_mm(1) + walker.apron_segment_mm(2)
	# One just out of the apron door, one halfway on to the plane door. The
	# cameras stand low, under the 03's high wing.
	var at_door := _guest(walk, to_door + 300)
	var out := _guest(walk, to_door + walker.apron_segment_mm(3) / 2)
	await _show_guests()
	_aim(walk[2] + Vector3.UP * 0.9, 180.0, 4.0, 6.0)
	await _frames(3)
	var name := "bridge_board_03_apron_door.png"
	if _proved(name, [at_door]):
		await _save(name)
	_aim((walk[2] + walk[3]) / 2.0 + Vector3.UP * 0.9, 160.0, 3.0, 9.0)
	await _frames(3)
	name = "bridge_board_03_apron_walk.png"
	if _proved(name, [out]):
		await _save(name)
	_clear_guests()


## A passenger of the probe's flight on `walk`, `mm` along it, standing still
## (the clock is stopped). Returns its id.
func _guest(walk: Array[Vector3], mm: int) -> int:
	var id := _sim.spawn_now(PROBE_FLIGHT)
	var p := _sim.get_passenger(id)
	p.stage = Passenger.Stage.APRON
	p.exit_object = _exit
	p.apron = walk.duplicate()
	p.apron_mm = mm
	var at := p.apron_position()
	print("GUEST %d at %d of %d mm: %s" % [id, mm, p.apron_total_mm(), at])
	return id


## Draws the guests where the sim has them and gives their meshes colliders.
func _show_guests() -> void:
	_views.snap()
	await _frames(4)
	for id in _sim.passenger_ids():
		var node := _views.node_for(id)
		if node != null:
			_add_colliders(node, null)
			print("DRAWN %d at %s" % [id, node.global_position])
	await _frames(2)


## The sim has no call that drops a passenger, so the plate's guests are put
## out of sight, 50 m under the site.
func _clear_guests() -> void:
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		p.apron.assign([Vector3(0.0, -50.0, 0.0)])
		p.apron_mm = 0
	_views.snap()


## Every guest of `ids` is drawn, in frame and seen through the glazing.
func _proved(label: String, ids: Array) -> bool:
	for id: int in ids:
		var node := _views.node_for(id)
		if node == null:
			_invalid("%s: guest %d is not drawn" % [label, id])
			return false
		if not _prove(label, node, GUEST_SEEN):
			return false
	return true


func _finish() -> void:
	print("PROBE done failed=%s plates=%d" % [_failed, _plates.size()])
	quit(1 if _failed else 0)


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


## Poses the main PlaneView with `model` parked at the stand in BOARDING, as
## update_pose() does, and lets it report its model to the bridge.
func _pose(model: String) -> Node3D:
	var plane_class := _class_of(model)
	_view.show_model(model)
	var path := _view._path(FlightSim.State.PUSHBACK, plane_class)
	var entry := _view._entry_dir(FlightSim.State.PUSHBACK, plane_class)
	var pose := FlightPose.pose(FlightSim.State.PUSHBACK, 0.0, path, entry)
	pose.origin.y += PlaneView.ground_height_at(pose.origin)
	_view.transform = pose
	_view.phase = FlightSim.State.BOARDING
	_view.visible = true
	_view.flight_id = "probe"
	_view._set_model_position(_view.model_position_at(FlightSim.State.BOARDING, pose, plane_class))
	_view._follow_props()
	var model_node: Node3D = _view.get_node("Pivot").get_child(0)
	if model_node.find_children("*", "StaticBody3D", true, false).is_empty():
		_add_colliders(model_node, null)
	return model_node


func _class_of(model: String) -> String:
	for cls: String in PlaneClasses.CLASSES:
		if PlaneClasses.CLASSES[cls]["models"].has(model):
			return cls
	return PlaneClasses.MEDIUM


## Puts the camera `distance` from `focus`, `pitch` degrees above it, looking
## at it from yaw `yaw` (0: from the south, looking north; 90: from the east).
func _aim(focus: Vector3, yaw: float, pitch: float, distance: float) -> void:
	var y := deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	var back := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
	_cam.look_at_from_position(focus + back * distance, focus, Vector3.UP)


## Proves `subject`'s bounds lie in the viewport with MARGIN_PX and that at
## least `need` of the camera rays at it reach it first.
func _prove(label: String, subject: Node3D, need: float) -> bool:
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	if not subject.is_visible_in_tree():
		_invalid("%s: %s is hidden" % [label, subject.name])
		return false
	var box := _aabb_of(subject)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var p := box.get_endpoint(i)
		if _cam.is_position_behind(p):
			_invalid("%s: %s is behind the camera" % [label, subject.name])
			return false
		var s := _cam.unproject_position(p)
		lo = lo.min(s)
		hi = hi.max(s)
	var ok := rect.has_point(lo) and rect.has_point(hi)
	print(
		(
			"INFRAME %s %s centre=%s screen=(%.0f,%.0f)-(%.0f,%.0f) ok=%s"
			% [label, subject.name, box.get_center(), lo.x, lo.y, hi.x, hi.y, ok]
		)
	)
	if not ok:
		_invalid("%s: %s leaves the viewport" % [label, subject.name])
		return false
	return _seen(label, subject, need)


## Casts rays from the camera at sampled surface points of `subject`; at least
## `need` of them must reach it first.
func _seen(label: String, subject: Node3D, need: float) -> bool:
	var targets: Array[Vector3] = []
	var centre := _aabb_of(subject).get_center()
	for mi in _meshes(subject):
		if not mi.is_visible_in_tree():
			continue
		var faces: PackedVector3Array = mi.mesh.get_faces()
		var step := maxi(1, floori(faces.size() / 60.0))
		for i in range(0, faces.size(), step):
			targets.append((mi.global_transform * faces[i]).lerp(centre, 0.05))
	var space := _cam.get_world_3d().direct_space_state
	var hits := 0
	var blockers := {}
	for t in targets:
		var q := PhysicsRayQueryParameters3D.create(
			_cam.global_position, t + (t - _cam.global_position).normalized() * 0.05
		)
		var hit := space.intersect_ray(q)
		if hit and (hit.collider == subject or subject.is_ancestor_of(hit.collider)):
			hits += 1
		else:
			var key := "<nothing>" if not hit else String((hit.collider as Node).get_parent().name)
			blockers[key] = int(blockers.get(key, 0)) + 1
	var share := float(hits) / maxf(1.0, targets.size())
	print(
		(
			"VISIBLE %s %s ray_hits=%d/%d share=%.2f need=%.2f blocked_by=%s"
			% [label, subject.name, hits, targets.size(), share, need, blockers]
		)
	)
	if share < need:
		_invalid("%s: %s is occluded" % [label, subject.name])
		return false
	return true


func _save(name: String) -> void:
	await _frames(2)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := _out_dir.path_join(name)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	_plates.append(path)
	print("PLATE saved %s" % path)


func _contact_sheet() -> void:
	if _plates.is_empty():
		return
	var tile := Vector2i(533, 300)
	var cols := 3
	var rows := ceili(_plates.size() / float(cols))
	var sheet := Image.create(tile.x * cols, tile.y * rows, false, Image.FORMAT_RGBA8)
	for i in _plates.size():
		var img := Image.load_from_file(_plates[i])
		img.resize(tile.x, tile.y)
		sheet.blit_rect(
			img, Rect2i(Vector2i.ZERO, tile), Vector2i(i % cols, floori(i / float(cols))) * tile
		)
	var path := _out_dir.path_join("bridge_board_contact_sheet.png")
	sheet.save_png(path)
	print("PLATE saved %s" % path)


func _show_hud(on: bool) -> void:
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = on


## Trimesh colliders on every mesh under `node`, except those under `skip`.
func _add_colliders(node: Node, skip: Node) -> void:
	for mi in _meshes(node):
		if skip != null and (mi == skip or skip.is_ancestor_of(mi)):
			continue
		if mi.mesh != null and mi.find_children("*", "StaticBody3D", false, false).is_empty():
			mi.create_trimesh_collision()


## Colliders on the bridge's meshes from every surface but the glass panes.
func _add_bridge_colliders(bridge: Node3D) -> void:
	for mi in _meshes(bridge):
		var faces := PackedVector3Array()
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat != null and mat.resource_name == GLASS:
				continue
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if index.is_empty():
				faces.append_array(verts)
			else:
				for i in index:
					faces.append(verts[i])
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		mi.add_child(body)


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
