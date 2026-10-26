extends SceneTree
## Windowed plate probe for the build view's kit drawing and wall cutaway.
##
## Run (one windowed Godot run project-wide; take the slot lock first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://tests/build/build_view_plates_probe.gd
##
## Builds a BuildMode room (8 x 6 floor, walls all round, a door and three glass
## walls in the south side, a desk, a scanner, a seat row and two characters),
## then looks at it through the real TycoonCamera at two yaws 90 degrees apart,
## plus a control shot at the first yaw with the cutaway off. Each subject must
## project inside the frame and be hit first by at least half of the camera
## rays aimed at its camera-facing opaque triangles, with every wall, post,
## floor tile and object as an occluder (glass panes excluded), or the probe
## prints PROBE_INVALID and exits 1. The control shot only reports its hits.
## Plates go to tools/blender/out/build_view/.

const OUT_REL := "res://../tools/blender/out/build_view"
const CAMERA := "res://camera/tycoon_camera.tscn"
const MALE := "res://assets/people/tcp_male_character_01.glb"
const FEMALE := "res://assets/people/tcp_female_character_01.glb"
const GLASS := "res://assets/materials/tp_glass.tres"
const GRID := Vector2i(16, 16)
## Room floor cells, inclusive.
const ROOM_MIN := Vector2i(4, 5)
const ROOM_MAX := Vector2i(11, 10)
const DOOR_X := 5
const GLASS_XS := [7, 8, 9]
const MARGIN_PX := 8.0
const WALL_PIECES := [
	"wall", "wall_glass", InteriorKit.GLASS_KERB, "wall_door", "wall_post", "floor_tile"
]

var _out_dir := ""
var _failed := false


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _run() -> void:
	var site := _studio()
	var mode := BuildMode.new()
	mode.grid_size = GRID
	mode.tool = BuildMode.Tool.NONE
	site.add_child(mode)
	var view: BuildView = mode.get_node("BuildView")
	var subjects := _build_room(mode, view, site)
	var rig: Node3D = load(CAMERA).instantiate()
	site.add_child(rig)
	var cam: Camera3D = rig.get_node("Camera3D")
	cam.make_current()
	var focus := mode.grid.cell_to_world(Vector2i(8, 8)) + Vector3(-0.5, 0, -0.5)
	var sheet: Array[Image] = []
	var shots := [
		["cutaway_yaw40", 0.7, true],
		["cutaway_yaw130", 0.7 + PI / 2.0, true],
		["control_no_cutaway_yaw40", 0.7, false],
	]
	for shot in shots:
		view.cutaway_enabled = shot[2]
		rig.position = focus
		rig.distance = 15.0
		rig.yaw = shot[1]
		rig.zoom(1.0)
		await _frames(6)
		print(
			(
				"CAMERA %s pos=%s yaw=%.2f pitch_deg=%.1f cut_edges=%d"
				% [
					shot[0],
					cam.global_position,
					shot[1],
					-cam.rotation_degrees.x,
					view.cut_edges().size()
				]
			)
		)
		print("CUT %s %s" % [shot[0], _cut_summary(view)])
		var occluders := _wall_colliders(view, site)
		await physics_frame
		await physics_frame
		var ok := true
		for key in subjects:
			var tag := "%s/%s" % [shot[0], key]
			ok = _prove_in_frame(cam, tag, _corners(_aabb_of(subjects[key]))) and ok
			ok = _prove_visible(cam, tag, subjects[key], shot[2]) and ok
		occluders.free()
		var img := await _grab()
		if ok or not shot[2]:
			_save(img, shot[0] + ".png")
			sheet.append(img)
	_save(_contact_sheet(sheet), "contact_sheet.png")
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _build_room(mode: BuildMode, view: BuildView, site: Node3D) -> Dictionary:
	var grid := mode.grid
	var door := Vector3i(DOOR_X, ROOM_MAX.y + 1, BuildGrid.Side.NORTH)
	view.wall_kind_source = func(cell: Vector2i, side: int) -> int:
		var edge := Vector3i(cell.x, cell.y, side)
		if edge == door:
			return InteriorKit.WallKind.DOOR
		if edge.y == door.y and side == BuildGrid.Side.NORTH and GLASS_XS.has(cell.x):
			return InteriorKit.WallKind.GLASS
		return InteriorKit.WallKind.PLAIN
	for y in range(ROOM_MIN.y, ROOM_MAX.y + 1):
		for x in range(ROOM_MIN.x, ROOM_MAX.x + 1):
			_must(grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1)))
	for x in range(ROOM_MIN.x, ROOM_MAX.x + 1):
		_must(grid.apply(BuildEdit.place_wall(Vector2i(x, ROOM_MIN.y), BuildGrid.Side.NORTH)))
		_must(grid.apply(BuildEdit.place_wall(Vector2i(x, ROOM_MAX.y), BuildGrid.Side.SOUTH)))
	for y in range(ROOM_MIN.y, ROOM_MAX.y + 1):
		_must(grid.apply(BuildEdit.place_wall(Vector2i(ROOM_MIN.x, y), BuildGrid.Side.WEST)))
		_must(grid.apply(BuildEdit.place_wall(Vector2i(ROOM_MAX.x, y), BuildGrid.Side.EAST)))
	_must(grid.apply(BuildEdit.place_object(&"checkin_desk", Vector2i(5, 6), 0)))
	_must(grid.apply(BuildEdit.place_object(&"security_scanner", Vector2i(10, 6), 0)))
	_must(grid.apply(BuildEdit.place_object(&"seat_row", Vector2i(6, 9), 0)))
	view.refresh(grid)
	var subjects := {}
	for child in view.get_children():
		if child.has_meta("record"):
			subjects[str(child.get_meta("record")["def"])] = child
	subjects["male"] = _spawn(MALE, site, grid.cell_to_world(Vector2i(5, 7)), 180.0)
	subjects["female"] = _spawn(FEMALE, site, grid.cell_to_world(Vector2i(8, 7)), 135.0)
	return subjects


func _must(result: BuildResult) -> void:
	if not result.ok:
		_invalid("room edit refused: %s" % result.reason_text())


func _cut_summary(view: BuildView) -> String:
	var counts := view.piece_counts()
	var parts := []
	for piece in WALL_PIECES:
		parts.append("%s=%d" % [piece, counts.get(piece, 0)])
	var low := 0
	for at in view.piece_transforms("wall"):
		if at.basis.get_scale().y < 0.5:
			low += 1
	parts.append("wall_stubs=%d" % low)
	return " ".join(parts)


## Static bodies for every instance the view's multimeshes actually draw (read back
## from the renderer, so a misplaced instance shows), glass panes left out.
func _wall_colliders(view: BuildView, site: Node3D) -> Node3D:
	var holder := Node3D.new()
	holder.name = "WallColliders"
	site.add_child(holder)
	for child in view.get_children():
		if child is MultiMeshInstance3D:
			var multimesh := (child as MultiMeshInstance3D).multimesh
			var local_faces := _opaque_faces(multimesh.mesh)
			if local_faces.is_empty():
				continue
			for i in multimesh.instance_count:
				if multimesh.get_instance_transform(i) == Transform3D.IDENTITY:
					_invalid("%s: instance %d read back as identity" % [child.name, i])
				var at: Transform3D = (
					(child as Node3D).global_transform * multimesh.get_instance_transform(i)
				)
				var faces := PackedVector3Array()
				for p in local_faces:
					faces.append(at * p)
				holder.add_child(_body(faces))
	for child in view.get_children():
		if child.has_meta("record"):
			_add_colliders(child)
	return holder


func _body(faces: PackedVector3Array) -> StaticBody3D:
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var shape_node := CollisionShape3D.new()
	shape_node.shape = shape
	var body := StaticBody3D.new()
	body.add_child(shape_node)
	return body


## A body under each mesh of `node`, so a hit's collider is inside the subject.
func _add_colliders(node: Node) -> void:
	for mi in _meshes(node):
		if mi.find_children("*", "StaticBody3D", false, false).size() > 0:
			continue
		var faces := PackedVector3Array()
		for p in _opaque_faces(mi.mesh):
			faces.append(p)
		if not faces.is_empty():
			var body := _body(faces)
			mi.add_child(body)


func _opaque_faces(mesh: Mesh) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		if mat != null and mat.resource_path == GLASS:
			continue
		var arrays := mesh.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if index.is_empty():
			faces.append_array(verts)
		else:
			for k in index:
				faces.append(verts[k])
	return faces


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		out.append(mi)
	return out


func _aabb_of(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(node):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _corners(box: AABB) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in 8:
		out.append(box.get_endpoint(i))
	return out


func _prove_in_frame(cam: Camera3D, label: String, points: Array[Vector3]) -> bool:
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		if cam.is_position_behind(p):
			_invalid("%s: point %s is behind the camera" % [label, p])
			return false
		var s := cam.unproject_position(p)
		lo = lo.min(s)
		hi = hi.max(s)
	var ok := rect.has_point(lo) and rect.has_point(hi)
	print("INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) ok=%s" % [label, lo.x, lo.y, hi.x, hi.y, ok])
	if not ok:
		_invalid("%s: projected bounds leave the viewport" % label)
	return ok


## Rays from the camera to points on the subject's opaque camera-facing
## triangles (rest pose for characters); at least half must hit the subject
## first. With `strict` false the result is only reported.
func _prove_visible(cam: Camera3D, label: String, subject: Node3D, strict: bool) -> bool:
	var targets: Array[Vector3] = []
	var centre := _aabb_of(subject).get_center()
	for mi in _meshes(subject):
		var faces := _opaque_faces(mi.mesh)
		var facing: Array[Vector3] = []
		for i in range(0, faces.size() - 2, 3):
			var a: Vector3 = mi.global_transform * faces[i]
			var b: Vector3 = mi.global_transform * faces[i + 1]
			var c: Vector3 = mi.global_transform * faces[i + 2]
			var mid := (a + b + c) / 3.0
			if (b - a).cross(c - a).dot(cam.global_position - mid) < 0.0:
				facing.append(mid)
		var step := maxi(1, floori(facing.size() / 12.0))
		for i in range(0, facing.size(), step):
			targets.append(facing[i].lerp(centre, 0.03))
	var space := cam.get_world_3d().direct_space_state
	var hits := 0
	for t in targets:
		var from := cam.global_position
		var q := PhysicsRayQueryParameters3D.create(from, t + (t - from).normalized() * 0.05)
		var hit := space.intersect_ray(q)
		if hit and subject.is_ancestor_of(hit.collider):
			hits += 1
	var ok := hits * 2 >= targets.size() and hits > 0
	var kind := "VISIBLE" if strict else "CONTROL"
	print("%s %s ray_hits=%d/%d ok=%s" % [kind, label, hits, targets.size(), ok])
	if strict and not ok:
		_invalid("%s: occluded or not hit (%d of %d rays)" % [label, hits, targets.size()])
	return ok or not strict


func _spawn(path: String, parent: Node, pos: Vector3, yaw_deg: float) -> Node3D:
	var node: Node3D = load(path).instantiate()
	node.position = pos
	node.rotation_degrees.y = yaw_deg
	parent.add_child(node)
	var player: AnimationPlayer = node.find_child("AnimationPlayer", true, false)
	if player != null:
		player.play("idle")
		player.seek(0.0, true)
		player.pause()
	_add_colliders(node)
	return node


## The main scene's look, with the ground lowered under the build area.
func _studio() -> Node3D:
	var studio := Node3D.new()
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	studio.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.transform = Transform3D(
		Basis(
			Vector3(0.866025, 0, -0.5),
			Vector3(-0.353553, 0.707107, -0.612372),
			Vector3(0.353553, 0.707107, 0.612372)
		),
		Vector3(0, 20, 0)
	)
	sun.shadow_enabled = true
	studio.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(700, 700)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.36, 0.5, 0.3)
	ground_mat.roughness = 1.0
	ground.material_override = ground_mat
	ground.position.y = -0.1
	studio.add_child(ground)
	root.add_child(studio)
	return studio


func _contact_sheet(images: Array[Image]) -> Image:
	var tile := Vector2i(960, 540)
	var sheet := Image.create(tile.x * 2, tile.y * 2, false, Image.FORMAT_RGBA8)
	for i in images.size():
		var small := images[i].duplicate() as Image
		small.resize(tile.x, tile.y)
		sheet.blit_rect(small, Rect2i(Vector2i.ZERO, tile), Vector2i(i % 2, i / 2) * tile)
	return sheet


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _grab() -> Image:
	await _frames(4)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
