extends SceneTree
## Windowed plate probe for the jet bridge rooted at the gate's exit door
## (board 0adca5c6; rulings jet-bridge-starts-at-the-gate-s-exit-door-
## passengers-step-fr and jet-bridge-boarding-design-stair-box-at-the-exit-
## door-real-w). For planes 05, 06 and 07 docked at the gate it saves a plate
## through a tunnel B window with a guest-height marker (1.75 m, orange) on the
## tunnel floor, and a context plate with the stair box, the tunnel and the
## plane; then one plate of the stair box at the exit door seen over the
## terminal. It rules nothing.
##
## Run (one windowed Godot run project-wide; hold tools/blender/out/.windowed.lock):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/jet_bridge_board_plates_probe.gd
##
## Boots main.tscn with the starter shell and a gate desk (StarterFlight), so the
## real ApronStand gives gate A its stand and the real Airside lays out its
## bridge; the clock, the fleets and the PlaneViews stop processing and the
## probe poses the main PlaneView as update_pose() does. Every plate projects
## its subjects' bounds into the viewport with MARGIN_PX and casts camera rays
## at them before it is saved. The rays meet trimesh colliders on every mesh
## except the bridge's glass panes (TP_Glass_1A_D surfaces), which a passenger
## is seen through. On failure it prints PROBE_INVALID and exits 1. The HUD is
## hidden. Prints the world seed.

const StarterFlight := preload("res://spike/starter_flight.gd")
const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/jet_bridge_board"
const MARGIN_PX := 8.0
const FOV := 55.0
const GLASS := "TP_Glass_1A_D"
const MARKER_H := 1.75
## Where the marker stands in Tunnel_Slide's frame: tunnel B's floor top, in
## the middle of its second window (build_airside_props.py panels()).
const MARKER_AT := Vector3(0.0, -0.02, 3.15)
const MODELS: Array[String] = ["tp_plane_05a", "tp_plane_06a", "tp_plane_07a"]
## The share of rays that must reach the marker through the window, and the
## bridge in a context plate.
const MARKER_SEEN := 0.2
const SUBJECT_SEEN := 0.25

var _out_dir := ""
var _failed := false
var _main: Node
var _cam: Camera3D
var _view: PlaneView
var _airside: Airside
var _gate := ""
var _stand: Dictionary = {}
var _plates: Array[String] = []
var _marker: MeshInstance3D


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
	_view.gate = _gate
	var bridge: Node3D = _airside.props.bridges[_gate]["node"]
	var sill := (bridge.find_child("Mount_StairBottom", true, false) as Node3D).global_position
	var exit := Vector3(_stand["x"], sill.y, _stand["wall_z"])
	print(
		(
			"PROBE gate=%s stand=%s root=%s stair sill %s exit door %s (%.4f m apart)"
			% [_gate, _stand, bridge.global_position, sill, exit, sill.distance_to(exit)]
		)
	)
	if sill.distance_to(exit) > 0.01:
		_invalid("the stair box's sill is not on the exit door")
	_show_hud(false)
	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.far = 2000.0
	_main.add_child(_cam)
	_cam.make_current()
	_marker = _make_marker()
	_main.add_child(_marker)
	_add_colliders(_main, bridge)
	_add_bridge_colliders(bridge)
	for model in MODELS:
		await _model_plates(model, bridge)
	await _exit_plate(bridge, exit)
	_contact_sheet()
	_finish()


func _model_plates(model: String, bridge: Node3D) -> void:
	var entry: Dictionary = _airside.props.bridges[_gate]
	var plane := _pose(model)
	await _frames(3)
	var door: Vector3 = plane.global_transform * PlaneModels.PLANES[model]["doors"][0]
	var mount := (bridge.find_child("Mount_Door", true, false) as Node3D).global_position
	var pose: Dictionary = entry["pose"]
	print(
		(
			"BRIDGE %s docked=%s Mount_Door %.4f m off the door %s slide %.2f pitch %.2f"
			% [
				model,
				entry["docked"],
				mount.distance_to(door),
				door,
				pose["slide"],
				rad_to_deg(pose["pitch"])
			]
		)
	)
	if not entry["docked"]:
		_invalid("%s: the bridge did not dock" % model)
		return
	var slide := bridge.find_child("Tunnel_Slide", true, false) as Node3D
	var feet := slide.global_transform * MARKER_AT
	_marker.global_position = feet + Vector3.UP * MARKER_H / 2.0
	_marker.visible = true
	await _frames(2)
	# The window plate: from the apron side of tunnel B, square to its windows.
	var along := slide.global_basis.z.slide(Vector3.UP).normalized()
	var side := along.cross(Vector3.UP).normalized()
	if side.z > 0.0:
		side = -side
	_aim(_marker.global_position, rad_to_deg(atan2(side.x, side.z)), 5.0, 8.0)
	await _frames(3)
	var name := "board_window_%s.png" % model.substr(9, 2)
	print("MARKER %s feet %s (tunnel B floor), camera %s" % [model, feet, _cam.global_position])
	if _prove(name, _marker, MARKER_SEEN):
		await _save(name)
	# The context plate: the stair box, the tunnel and the plane from the north-east.
	var focus := (bridge.global_position + door) / 2.0 + Vector3.UP * 2.0
	_aim(focus, 135.0, 28.0, 36.0)
	await _frames(3)
	name = "board_context_%s.png" % model.substr(9, 2)
	if (
		_prove(name, bridge, SUBJECT_SEEN)
		and _prove(name, _marker, 0.0)
		and _seen(name, plane, SUBJECT_SEEN)
	):
		await _save(name)


## The stair box at the exit door, seen over the terminal from the south-west:
## the door in the wall and the stair box behind it.
func _exit_plate(bridge: Node3D, exit: Vector3) -> void:
	_marker.visible = false
	var box := bridge.find_child("StairBox_Mesh", true, false) as MeshInstance3D
	_aim(exit + Vector3(3.0, 1.5, -2.0), 325.0, 42.0, 22.0)
	await _frames(3)
	var name := "board_exit_door.png"
	if _prove(name, box, SUBJECT_SEEN):
		await _save(name)


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
## update_pose() does, and lets it report its door to the bridge.
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


func _make_marker() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.25
	capsule.height = MARKER_H
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.45, 0.1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	capsule.material = mat
	mi.mesh = capsule
	mi.name = "GuestMarker"
	mi.visible = false
	return mi


## Puts the camera `distance` from `focus`, `pitch` degrees above it, looking
## at it from yaw `yaw` (0: from the south, looking north).
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
			"INFRAME %s %s screen=(%.0f,%.0f)-(%.0f,%.0f) ok=%s"
			% [label, subject.name, lo.x, lo.y, hi.x, hi.y, ok]
		)
	)
	if not ok:
		_invalid("%s: %s leaves the viewport" % [label, subject.name])
		return false
	return need <= 0.0 or _seen(label, subject, need)


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
	var path := _out_dir.path_join("board_contact_sheet.png")
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
		var skipped := 0
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat != null and mat.resource_name == GLASS:
				skipped += 1
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
		print(
			(
				"COLLIDER %s triangles=%d glass_surfaces_skipped=%d"
				% [mi.name, faces.size() / 3, skipped]
			)
		)


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
