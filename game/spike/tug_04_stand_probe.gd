extends SceneTree
## Windowed plate probe for plane 04's stop (board f8c8987c, decision plane-04-
## stops-further-out-with-the-passenger-walk-ending-at): model 04 at the start
## of its pushback, with the towbarless tug on its nose wheel, beside the
## terminal's wall line. It prints the tug front's gap to the wall line and
## saves tug_04_stand plates; it rules nothing.
##
## Run (one windowed Godot run project-wide; hold tools/blender/out/.windowed.lock):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game -s res://spike/tug_04_stand_probe.gd
##
## Boots main.tscn with the starter shell and a gate desk (StarterFlight), so the
## real ApronStand gives gate A its stand. No flight runs: the clock, the
## PlaneFleets and the main PlaneView stop processing, and the probe poses that
## PlaneView as update_pose() does (FlightPose.pose, model_position_at, then
## _follow_props(), which places the tug). Each plate projects the tug's bounds
## into the viewport with MARGIN_PX and casts camera rays at the tug and the
## plane (trimesh colliders on every mesh) before it is saved; on failure it
## prints PROBE_INVALID and exits 1. The HUD is hidden. Prints the world seed.

const StarterFlight := preload("res://spike/starter_flight.gd")
const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/tug_04_stand"
const MODEL := "tp_plane_04a"
const MARGIN_PX := 8.0
## The least gap between the tug's front and the wall line (the ruling).
const WALL_CLEAR_M := 0.3
## Camera yaw, pitch and distance for each plate, looking at the tug's front.
const EYES: Array[Vector3] = [
	Vector3(270.0, 12.0, 14.0),
	Vector3(240.0, 30.0, 20.0),
	Vector3(300.0, 55.0, 30.0),
]

var _out_dir := ""
var _failed := false
var _main: Node
var _cam: Camera3D
var _view: PlaneView
var _stand: Dictionary = {}
var _plates := 0


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
	var airside: Airside = _main.get_node("Airside")
	await _frames(6)
	if not StarterFlight.add_gate_desk((_main.get_node("BuildMode") as BuildMode).grid):
		_invalid("the gate desk was refused")
		_finish()
		return
	await _frames(6)
	if airside.gate_stands.is_empty():
		_invalid("no gate got a stand")
		_finish()
		return
	var gate: String = airside.gate_stands.keys()[0]
	_stand = airside.gate_stands[gate]
	_view.gate = gate
	print("PROBE gate=%s stand=%s" % [gate, _stand])
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 2000.0
	_main.add_child(_cam)
	_cam.make_current()
	_add_colliders(_main)
	await _plates_at_pushback_start()
	_finish()


func _plates_at_pushback_start() -> void:
	var plane := _pose()
	await _frames(2)
	var tug := (_view.get_node("Props") as PlaneProps).tug
	if not tug.visible:
		_invalid("the tug is hidden at the start of pushback")
		return
	var wall := float(_stand["wall_z"])
	var box := _aabb_of(tug)
	var nose := _aabb_of(plane).end.z
	var door: Vector3 = plane.global_transform * PlaneModels.PLANES[MODEL]["doors"][0]
	var walk_end := StandPlacement.door_point(_stand, MODEL)
	print(
		(
			(
				"TUG %s at pushback start: tug front z %.3f, nose z %.3f, wall z %.3f, tug clear"
				+ " of the wall by %.3f m (needs %.2f); drawn door %s, walk end %s (%.3f m along)"
			)
			% [
				MODEL,
				box.end.z,
				nose,
				wall,
				wall - box.end.z,
				WALL_CLEAR_M,
				door,
				walk_end,
				absf(walk_end.z - door.z),
			]
		)
	)
	if wall - box.end.z < WALL_CLEAR_M:
		_invalid("the tug front is %.3f m from the wall line" % (wall - box.end.z))
	var front := Vector3(box.get_center().x, box.position.y + 0.6, box.end.z)
	for i in EYES.size():
		_aim(front, EYES[i].x, EYES[i].y, EYES[i].z)
		await _frames(3)
		var name := "tug_04_stand_%d.png" % i
		if _prove(name, tug) and _prove_seen(name, plane):
			await _save(name)


## Poses the main PlaneView with model 04 at the start of pushback, as
## update_pose() does, and lets it place its props. Returns the model node.
func _pose() -> Node3D:
	_view.show_model(MODEL)
	var plane_class := PlaneClasses.MEDIUM
	var path := _view._path(FlightSim.State.PUSHBACK, plane_class)
	var entry := _view._entry_dir(FlightSim.State.PUSHBACK, plane_class)
	var pose := FlightPose.pose(FlightSim.State.PUSHBACK, 0.0, path, entry)
	pose.origin.y += PlaneView.ground_height_at(pose.origin)
	_view.transform = pose
	_view.phase = FlightSim.State.PUSHBACK
	_view.visible = true
	_view.flight_id = "probe"
	_view._set_model_position(_view.model_position_at(FlightSim.State.PUSHBACK, pose, plane_class))
	_view._follow_props()
	var model_node: Node3D = _view.get_node("Pivot").get_child(0)
	if model_node.find_children("*", "StaticBody3D", true, false).is_empty():
		_add_colliders(model_node)
	return model_node


func _finish() -> void:
	print("PROBE done failed=%s plates=%d" % [_failed, _plates])
	quit(1 if _failed or _plates == 0 else 0)


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


## Puts the camera `distance` from `focus`, `pitch` degrees above it, looking
## at it from yaw `yaw` (0: from the south, looking north).
func _aim(focus: Vector3, yaw: float, pitch: float, distance: float) -> void:
	var y := deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	var back := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
	_cam.look_at_from_position(focus + back * distance, focus, Vector3.UP)


## Proves `subject`'s bounds lie in the viewport with MARGIN_PX and that camera
## rays reach it first. A hidden subject, or one with no visible mesh, fails.
func _prove(label: String, subject: Node3D) -> bool:
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
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
	return _prove_seen(label, subject)


## Proves camera rays reach `subject` first, without needing all of it in frame.
func _prove_seen(label: String, subject: Node3D) -> bool:
	if _report_rays("VISIBLE %s %s" % [label, subject.name], subject) < 0.25:
		_invalid("%s: %s is occluded" % [label, subject.name])
		return false
	return true


## Casts rays from the camera at sampled surface points of `subject` and prints
## the share that hit it first.
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


func _save(name: String) -> void:
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
