extends SceneTree
## Windowed plate probe for the PlaneModels table (board f7ceaeeb): every plane
## side by side on the apron of the main scene, each parked on its pose point
## with the table's model_offset, beside the jet bridge and 1 m cubes.
##
## Run (one windowed Godot run project-wide; this probe holds the slot):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://tests/flights/plane_models_plates_probe.gd
##
## Drawn from the table, so a wrong row shows on the plate: the "aabb"
## footprint (cyan), the swing circle about the pose point (orange), a red
## ball on every door point and a yellow post on every pose point.
## Plates: a top lineup, an iso lineup, a port-side view per plane and a
## jet bridge close-up, then a contact sheet, under tools/blender/out/plane-models/.
## Every plate projects its subjects' bounds into the viewport with a margin and
## casts rays at them (temporary trimesh colliders); on a failure it prints
## PROBE_INVALID and exits 1.

const OUT_REL := "res://../tools/blender/out/plane-models"
const MAIN_SCENE := "res://main/main.tscn"
const POSE_Z := -175.0
const START_X := -120.0
const GAP_M := 10.0
const MARGIN_PX := 8.0
const WINDOW := Vector2i(1600, 900)
const TRUCK := "tp_loading_truck_01a"
## How far above the plane's middle the side camera sits, 60 m out: about 20
## degrees up by default, so a low wing does not hide a rear door; level for
## the high-wing planes, whose wing and engines are above their door.
const SIDE_LIFT := {"tp_plane_03a": 0.0, "tp_plane_04a": 0.0}

var _out_dir := ""
var _failed := false
var _main: Node3D
var _cam: Camera3D
## Model name -> {"node": Node3D, "holder": Node3D, "pose": Vector3}.
var _placed := {}
var _plates: Array[String] = []
## The holder the marker helpers add to.
var _holder: Node3D
var _labels: Array[Label3D] = []


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	DisplayServer.window_set_size(WINDOW)
	root.size = WINDOW
	_run.call_deferred()


func _run() -> void:
	_main = load(MAIN_SCENE).instantiate()
	root.add_child(_main)
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	_place_all()
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.current = true
	await _frames(10)
	await physics_frame
	await physics_frame
	await _plate_top()
	await _plate_iso()
	for model: String in PlaneModels.PLANES:
		await _plate_side(model)
	await _plate_truck()
	_contact_sheet()
	_finish()


func _finish() -> void:
	print("PROBE done plates=%d failed=%s" % [_plates.size(), _failed])
	quit(1 if _failed else 0)


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


# ------------------------------------------------------------ the lineup


## Each subject and its markers go under one holder, so a plate can hide a
## whole subject; the labels stay apart and show on the lineup plates only.
func _place_all() -> void:
	var x := START_X
	for model: String in PlaneModels.PLANES:
		var row: Dictionary = PlaneModels.PLANES[model]
		var half: float = row["half_span"]
		var pose := Vector3(x + half, 0.0, POSE_Z)
		_new_holder()
		var node: Node3D = load(row["path"]).instantiate()
		node.position = pose + (row["model_offset"] as Vector3)
		_holder.add_child(node)
		_placed[model] = {"node": node, "holder": _holder, "pose": pose}
		for door: Vector3 in row["doors"]:
			_ball(node.position + door, Color(0.9, 0.1, 0.1))
		_post(pose)
		_footprint(node.position, row["aabb"])
		_circle(pose, row["own_swing_radius"])
		_label(model, pose + Vector3(0, 0.3, float(row["length"]) / 2.0 + 4.0))
		if x == START_X:
			_cube(Vector3(START_X - 3.0, 0.5, POSE_Z))
		x += 2.0 * half + GAP_M
	var truck_row: Dictionary = PlaneModels.PIECES[TRUCK]
	_new_holder()
	var truck: Node3D = load(truck_row["path"]).instantiate()
	truck.position = Vector3(x + 2.0, 0.0, POSE_Z)
	_holder.add_child(truck)
	_placed[TRUCK] = {"node": truck, "holder": _holder, "pose": truck.position}
	_footprint(truck.position, truck_row["aabb"])
	_cube(truck.position + Vector3(4.0, 0.5, 0.0))
	_label(TRUCK, truck.position + Vector3(-6.0, 0.3, 11.0))
	for entry: Dictionary in _placed.values():
		for mi in (entry["node"] as Node3D).find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).create_trimesh_collision()


func _new_holder() -> void:
	_holder = Node3D.new()
	_main.add_child(_holder)


func _unshaded(color: Color, on_top := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = on_top
	return mat


func _ball(at: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.35
	mesh.height = 0.7
	mi.mesh = mesh
	mi.material_override = _unshaded(color)
	mi.position = at
	_holder.add_child(mi)


func _post(at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.4
	mesh.bottom_radius = 0.4
	mesh.height = 0.3
	mi.mesh = mesh
	mi.material_override = _unshaded(Color(1.0, 0.85, 0.1))
	mi.position = at + Vector3(0, 0.15, 0)
	_holder.add_child(mi)


func _cube(at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.material_override = _unshaded(Color(0.95, 0.95, 0.95))
	mi.position = at
	_holder.add_child(mi)


func _lines(points: PackedVector3Array, color: Color) -> void:
	var mesh := ImmediateMesh.new()
	# Drawn over everything: the apron paving would hide a line at ground level.
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _unshaded(color, true))
	for p in points:
		mesh.surface_add_vertex(p)
	mesh.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	_holder.add_child(mi)


func _footprint(origin: Vector3, box: AABB) -> void:
	var lo := origin + box.position
	var hi := origin + box.end
	var y := 0.15
	_lines(
		PackedVector3Array(
			[
				Vector3(lo.x, y, lo.z),
				Vector3(hi.x, y, lo.z),
				Vector3(hi.x, y, hi.z),
				Vector3(lo.x, y, hi.z),
				Vector3(lo.x, y, lo.z),
			]
		),
		Color(0.1, 0.9, 0.95)
	)


func _circle(centre: Vector3, radius: float) -> void:
	var pts := PackedVector3Array()
	for i in 97:
		var a := TAU * i / 96.0
		pts.append(centre + Vector3(cos(a) * radius, 0.15, sin(a) * radius))
	_lines(pts, Color(1.0, 0.55, 0.1))


func _label(text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = 0.04
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = at
	_main.add_child(label)
	_labels.append(label)


# ------------------------------------------------------------ proofs


func _box_of(model: String) -> AABB:
	var entry: Dictionary = _placed[model]
	var row: Dictionary = PlaneModels.PLANES.get(model, PlaneModels.PIECES.get(model, {}))
	var box: AABB = row["aabb"]
	box.position += (entry["node"] as Node3D).position
	return box


func _corners(box: AABB) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in 8:
		out.append(box.get_endpoint(i))
	return out


func _in_frame(label: String, boxes: Array[AABB]) -> bool:
	var rect := Rect2(Vector2.ZERO, Vector2(root.size)).grow(-MARGIN_PX)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for box in boxes:
		for p in _corners(box):
			if _cam.is_position_behind(p):
				_invalid("%s: %s is behind the camera" % [label, p])
				return false
			var s := _cam.unproject_position(p)
			lo = lo.min(s)
			hi = hi.max(s)
	var ok := rect.has_point(lo) and rect.has_point(hi)
	print("INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) ok=%s" % [label, lo.x, lo.y, hi.x, hi.y, ok])
	if not ok:
		_invalid("%s: projected bounds leave the viewport" % label)
	return ok


## A ray from the camera at `target` must first hit `model` within `near_m`.
func _ray_hits(model: String, target: Vector3, near_m: float) -> bool:
	var from := _cam.global_position
	if _cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		from = target + _cam.global_basis.z * 400.0
	var q := PhysicsRayQueryParameters3D.create(from, target + (target - from).normalized() * 1.0)
	var hit := _cam.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		print("RAY %s at %s hit nothing" % [model, target])
		return false
	var node := _placed[model]["node"] as Node3D
	var collider := hit["collider"] as Node
	var at: Vector3 = hit["position"]
	var ok := node.is_ancestor_of(collider) and at.distance_to(target) <= near_m
	if not ok:
		print("RAY %s at %s hit %s at %s" % [model, target, collider.get_parent().name, at])
	return ok


## Shows only `model` and its markers of the placed subjects, no label, and
## gives only it colliders, so a close view sees no neighbour; with `model` ""
## shows all.
func _isolate(model: String) -> void:
	for label in _labels:
		label.visible = model == ""
	for name: String in _placed:
		var node := _placed[name]["node"] as Node3D
		var on := model == "" or name == model
		(_placed[name]["holder"] as Node3D).visible = on
		for body in node.find_children("*", "StaticBody3D", true, false):
			(body as StaticBody3D).collision_layer = 1 if on else 0


func _visible(label: String, model: String, targets: Array[Vector3], near_m: float) -> bool:
	var hits := 0
	for t in targets:
		if _ray_hits(model, t, near_m):
			hits += 1
	var ok := hits == targets.size()
	print("VISIBLE %s %s ray_hits=%d/%d ok=%s" % [label, model, hits, targets.size(), ok])
	if not ok:
		_invalid("%s: %s occluded (%d of %d rays)" % [label, model, hits, targets.size()])
	return ok


func _save(name: String) -> void:
	await _frames(6)
	var img := root.get_texture().get_image()
	var path := _out_dir.path_join(name)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	_plates.append(path)
	print("PLATE saved %s size=%s" % [path, img.get_size()])


# ------------------------------------------------------------ plates


func _all_boxes() -> Array[AABB]:
	var boxes: Array[AABB] = []
	for model: String in _placed:
		boxes.append(_box_of(model))
	return boxes


## The ground point under each subject's middle; a ray from the camera at it
## must hit the subject first (the ground has no collider).
func _grounds() -> Dictionary:
	var out := {}
	for model: String in _placed:
		var box := _box_of(model)
		out[model] = Vector3(box.get_center().x, 0.05, box.get_center().z)
	return out


func _plate_top() -> void:
	var all := _all_boxes()
	var span := AABB(all[0])
	for box in all:
		span = span.merge(box)
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.size = span.size.x + 16.0
	_cam.global_position = span.get_center() + Vector3(0, 200, 0)
	_cam.look_at(span.get_center(), Vector3.FORWARD)
	await _frames(3)
	var ok := _in_frame("top", all)
	var grounds := _grounds()
	for model: String in grounds:
		ok = _visible("top", model, [grounds[model]], INF) and ok
	if ok:
		await _save("lineup_top.png")


func _plate_iso() -> void:
	var all := _all_boxes()
	var span := AABB(all[0])
	for box in all:
		span = span.merge(box)
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.fov = 40.0
	var centre := span.get_center()
	_cam.global_position = centre + Vector3(-60, 95, 175)
	_cam.look_at(centre, Vector3.UP)
	await _frames(3)
	var ok := _in_frame("iso", all)
	var grounds := _grounds()
	for model: String in grounds:
		ok = _visible("iso", model, [grounds[model]], INF) and ok
	if ok:
		await _save("lineup_iso.png")


## Port side (+x) from SIDE_LIFT, the other subjects hidden: a ray at each
## port door, 0.4 m above its sill, must hit the plane's skin within 0.8 m of
## it, and the cube beside the tail gives the scale.
func _plate_side(model: String) -> void:
	var row: Dictionary = PlaneModels.PLANES[model]
	var node := _placed[model]["node"] as Node3D
	var box := _box_of(model)
	var doors: Array[Vector3] = []
	for door: Vector3 in row["doors"]:
		if door.x > 0.0:
			doors.append(node.position + door + Vector3(0, 0.4, 0))
	_isolate(model)
	await physics_frame
	await physics_frame
	var cube := Vector3(box.end.x + 2.0, 0.5, box.position.z - 2.5)
	var cube_mi := MeshInstance3D.new()
	cube_mi.mesh = BoxMesh.new()
	cube_mi.material_override = _unshaded(Color(0.95, 0.95, 0.95))
	cube_mi.position = cube
	_main.add_child(cube_mi)
	# Fit the plane, its swing circle and the cube, and prove all three in frame.
	var radius := float(row["own_swing_radius"])
	var pose: Vector3 = _placed[model]["pose"]
	var circle_box := AABB(
		pose - Vector3(radius, 0.0, radius), Vector3(2.0 * radius, 0.3, 2.0 * radius)
	)
	var cube_box := AABB(cube - Vector3.ONE * 0.5, Vector3.ONE)
	var span := box.merge(circle_box).merge(cube_box)
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.size = span.size.z + 6.0
	var centre := Vector3(box.get_center().x, box.get_center().y, span.get_center().z)
	var lift: float = SIDE_LIFT.get(model, 22.0)
	_cam.global_position = Vector3(box.end.x + 60.0, centre.y + lift, centre.z)
	_cam.look_at(centre, Vector3.UP)
	await _frames(3)
	var ok := _in_frame("side_" + model, [box, circle_box, cube_box])
	ok = _visible("side_" + model, model, doors, 0.8) and ok
	if ok:
		await _save("side_%s.png" % model)
	cube_mi.queue_free()
	_isolate("")
	await physics_frame
	await physics_frame


func _plate_truck() -> void:
	var box := _box_of(TRUCK)
	for label in _labels:
		label.visible = false
	var at := (_placed[TRUCK]["node"] as Node3D).position + Vector3(4.0, 0.5, 0.0)
	var cube_box := AABB(at - Vector3.ONE * 0.5, Vector3.ONE)
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.fov = 40.0
	var centre := box.get_center()
	_cam.global_position = centre + Vector3(18, 9, 16)
	_cam.look_at(centre, Vector3.UP)
	await _frames(3)
	var ok := _in_frame("truck", [box, cube_box])
	ok = _visible("truck", TRUCK, [_grounds()[TRUCK]], INF) and ok
	if ok:
		await _save("truck_close.png")


func _contact_sheet() -> void:
	if _plates.is_empty():
		return
	var cols := 3
	var tile := Vector2i(WINDOW.x / 2, WINDOW.y / 2)
	var rows := ceili(_plates.size() / float(cols))
	var sheet := Image.create(tile.x * cols, tile.y * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.1, 0.1, 0.1))
	for i in _plates.size():
		var img := Image.load_from_file(_plates[i])
		img.convert(Image.FORMAT_RGBA8)
		img.resize(tile.x, tile.y)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, tile), Vector2i(i % cols, i / cols) * tile)
	var path := _out_dir.path_join("contact_sheet.png")
	if sheet.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("SHEET saved %s tiles=%d" % [path, _plates.size()])
