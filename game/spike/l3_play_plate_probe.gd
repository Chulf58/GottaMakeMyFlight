extends SceneTree
## Play pieces toned to the Toon palette (board item L3): one windowed run that
## plates play_blocks and play_slide beside two neighbouring catalog pieces (the
## lounge armchair and sofa) and a 1 m reference cube, in main.tscn's light
## (procedural sky, sky ambient, Filmic tonemap, its sun). Each piece is drawn by
## BuildView.make_object_node, as the game draws it. Two plates: the row of four
## and a closer view of the two play pieces. Before each plate is saved every
## subject's bounds must project inside the viewport with a margin, and at least
## half of the camera rays to points on each subject's top must hit that subject
## first, or the probe prints PROBE_INVALID and exits 1.
##
## Run (one windowed Godot run project-wide; hold tools/blender/out/.windowed.lock):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/l3_play_plate_probe.gd
##
## Plates go to tools/blender/out/l3_play/ in the main checkout, also when the
## probe runs from a worktree under .claude/worktrees/.

const OUT_SUB := "tools/blender/out/l3_play"
const WINDOW := Vector2i(1920, 1080)
const MARGIN_PX := 24.0
const FOV := 40.0
const YAW_DEG := 45.0
## [catalog id, x position of the footprint centre]
const ROW := [
	[&"lounge_armchair", -3.0],
	[&"play_blocks", -1.0],
	[&"play_slide", 1.5],
	[&"lounge_sofa", 4.0],
]

var _cam: Camera3D
var _out_dir := ""
var _failed := false


func _initialize() -> void:
	root.size = WINDOW
	var here := ProjectSettings.globalize_path("res://").get_base_dir().get_base_dir()
	var marker := "/.claude/worktrees/"
	if here.contains(marker):
		here = here.substr(0, here.find(marker))
	_out_dir = here.path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _run() -> void:
	_studio()
	var subjects := {}
	for entry in ROW:
		var def := BuildCatalog.get_def(entry[0])
		if def == null:
			_invalid("no catalog def for %s" % entry[0])
			return
		var node := BuildView.make_object_node(def, null)
		node.name = String(entry[0])
		node.position = Vector3(entry[1], 0.0, 0.0)
		root.add_child(node)
		subjects[entry[0]] = node
	var cube := MeshInstance3D.new()
	cube.name = "ReferenceCube1m"
	cube.mesh = BoxMesh.new()
	var cube_mat := StandardMaterial3D.new()
	cube_mat.albedo_color = Color(1.0, 0.45, 0.1)
	cube.material_override = cube_mat
	cube.position = Vector3(-1.0, 0.5, -2.2)
	root.add_child(cube)
	await _frames(3)
	for node: Node3D in subjects.values():
		_add_colliders(node)
	await physics_frame
	await physics_frame
	var all: Array[Node3D] = []
	all.assign(subjects.values())
	await _plate("row", all, [cube])
	await _plate("play_pair", [subjects[&"play_blocks"], subjects[&"play_slide"]], [])
	quit(1 if _failed else 0)


func _studio() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
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
	sun.shadow_blur = 2.0
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.5, 0.3)
	ground.material_override = mat
	ground.position.y = -0.1
	root.add_child(ground)
	_cam = Camera3D.new()
	_cam.fov = FOV
	root.add_child(_cam)
	_cam.make_current()


func _plate(tag: String, subjects: Array, extras: Array) -> void:
	var box := AABB()
	var first := true
	for node: Node3D in subjects + extras:
		var b := _aabb_of(node)
		box = b if first else box.merge(b)
		first = false
	var pitch := deg_to_rad(TycoonCamera.STEP_PITCH_DEGREES[TycoonCamera.AngleStep.MEDIUM])
	var yaw := deg_to_rad(YAW_DEG)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var r := maxf(box.size.length() / 2.0, 0.5)
	var dist := r / sin(deg_to_rad(FOV / 2.0)) * 1.02
	_cam.look_at_from_position(box.get_center() + dir * dist, box.get_center(), Vector3.UP)
	await _frames(4)
	var deg := rad_to_deg(pitch)
	print("PLATE %s camera=%s pitch_deg=%.1f dist=%.2f" % [tag, _cam.position, deg, dist])
	for node: Node3D in subjects + extras:
		if not _in_frame("%s/%s" % [tag, node.name], _aabb_of(node)):
			return
	for node: Node3D in subjects:
		if not _visible("%s/%s" % [tag, node.name], node):
			return
	await _frames(4)
	var img := root.get_texture().get_image()
	var path := _out_dir.path_join("%s.png" % tag)
	var err := img.save_png(path)
	print("SAVED %s size=%s err=%d" % [path, img.get_size(), err])


func _in_frame(label: String, box: AABB) -> bool:
	var rect := Rect2(Vector2.ZERO, Vector2(WINDOW)).grow(-MARGIN_PX)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var p := box.get_endpoint(i)
		if _cam.is_position_behind(p):
			_invalid("%s: corner behind the camera" % label)
			return false
		var s := _cam.unproject_position(p)
		lo = lo.min(s)
		hi = hi.max(s)
	var ok := rect.has_point(lo) and rect.has_point(hi)
	print("INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) ok=%s" % [label, lo.x, lo.y, hi.x, hi.y, ok])
	if not ok:
		_invalid("%s: projected bounds leave the viewport" % label)
	return ok


## Rays from the camera to a 3x3 grid on the top of the subject's bounds, aimed
## a little below the top so they meet the piece; at least half must hit it first.
func _visible(label: String, subject: Node3D) -> bool:
	var box := _aabb_of(subject)
	var space := _cam.get_world_3d().direct_space_state
	var hits := 0
	var total := 0
	for ix in 3:
		for iz in 3:
			var p := Vector3(
				box.position.x + box.size.x * (0.25 + 0.25 * ix),
				box.position.y + box.size.y * 0.5,
				box.position.z + box.size.z * (0.25 + 0.25 * iz)
			)
			var from := _cam.global_position
			var query := PhysicsRayQueryParameters3D.create(from, from + (p - from) * 1.5)
			var hit := space.intersect_ray(query)
			total += 1
			if not hit.is_empty() and subject.is_ancestor_of(hit["collider"]):
				hits += 1
	var ok := hits * 2 >= total
	print("VISIBLE %s hits=%d/%d ok=%s" % [label, hits, total, ok])
	if not ok:
		_invalid("%s: hidden from the camera" % label)
	return ok


func _add_colliders(node: Node) -> void:
	for mi in _meshes(node):
		if mi.mesh != null:
			mi.create_trimesh_collision()


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


func _aabb_of(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(node):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _invalid(msg: String) -> void:
	print("PROBE_INVALID " + msg)
	_failed = true
	quit(1)
