extends SceneTree
## Windowed plate probe for the Toon City decor props and the prize car.
##
## Run (one windowed Godot run project-wide; this probe holds the slot while it runs):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://assets/decor/decor_plates_probe.gd
##
## Stages: the TC ramp measured on white spheres for each of the five TC materials (lit,
## middle and dark band, and a cast shadow); six-axis orthographic plates of every prop
## beside a 1 m cube; the chain hung between two posts; then a gallery on interior floor
## tiles in front of a row of 2.5 m walls, with standing and seated passengers, through
## the TycoonCamera close up and from 60 m and 120 m. Seated passengers sit by the sit
## clips' contract (seat top 0.53 m, contact 0.385 m male / 0.427 m female behind the
## root) on the measured seat of each bench; Bench_1A's seat is higher (vendor scale), so
## that plate shows the gap rather than hiding it. Plates go to tools/blender/out/decor/.
## Every plate proves its subjects are in frame (projected bounds inside the viewport)
## and hit by camera rays against colliders from their opaque surfaces; characters by
## their posed bone positions. Otherwise the probe prints PROBE_INVALID and exits 1.

const OUT_REL := "res://../tools/blender/out/decor"
const DECOR := "res://assets/decor/%s.glb"
const SUV := "res://assets/vehicles/tp_suv_01a.glb"
const FLOOR := "res://assets/interior/floor_tile.glb"
const WALL := "res://assets/interior/wall.glb"
const MALE := "res://assets/people/tcp_male_character_01.glb"
const FEMALE := "res://assets/people/tcp_female_character_01.glb"
const CAMERA := "res://camera/tycoon_camera.tscn"
const MAIN_SCENE := "res://main/main.tscn"
const GLASS := "res://assets/materials/tp_glass.tres"
const TC_MATERIALS := [
	"res://assets/materials/tc_road_1a_toon.tres",
	"res://assets/materials/tc_tree_1a_toon.tres",
	"res://assets/materials/tc_tree_3a_toon.tres",
	"res://assets/materials/tc_props_2a_toon.tres",
	"res://assets/materials/tc_building_4a_toon.tres",
]
const TOON_MATERIALS := [
	"res://assets/materials/tp_atlas_toon.tres",
	"res://assets/materials/tp_lights.tres",
	"res://assets/materials/tp_glass.tres",
]
const PROPS := [
	"tc_tree_3a_indoor",
	"tc_fountain_1a_indoor",
	"tc_statue_1b_indoor",
	"tc_bench_2a_indoor",
	"tc_bench_1a",
	"tc_plant_pot_1a",
	"tc_plant_pot_2a",
	"tc_bush_1a",
	"tc_trash_can_1a",
	"tc_metal_pole_1a",
	"tc_metal_pole_chain_1a",
]
## Seat contact behind the root, per character (SIT_CONTRACT of toon_clips.py).
const CONTACT_BEHIND := {MALE: 0.385, FEMALE: 0.427}
const SEAT_TOP := 0.53
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 90000
const SIX_AXIS := {
	"front": Vector3(0, 0, 1),
	"back": Vector3(0, 0, -1),
	"left": Vector3(-1, 0, 0),
	"right": Vector3(1, 0, 0),
	"top": Vector3(0, 1, 0),
	"bottom": Vector3(0, -1, 0),
}

var _out_dir := ""
var _failed := false
var _stage := "init"
var _heartbeat_ms := 0
var _guard_mutex := Mutex.new()
var _guard_stop := false
var _guard: Thread


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_beat("init")
	_guard = Thread.new()
	_guard.start(_watch)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	_beat(_stage)
	return false


func _beat(stage: String) -> void:
	_guard_mutex.lock()
	_stage = stage
	_heartbeat_ms = Time.get_ticks_msec()
	_guard_mutex.unlock()


## Guard thread: a frozen main thread never reaches _process, so check from here.
func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_guard_mutex.lock()
		var stop := _guard_stop
		var idle_ms := Time.get_ticks_msec() - _heartbeat_ms
		var stage := _stage
		_guard_mutex.unlock()
		if stop:
			return
		if idle_ms > HANG_LIMIT_MS:
			print("PROBE_INVALID hang stage=%s no heartbeat for %d ms" % [stage, idle_ms])
			OS.crash("decor plates probe hung")


func _run() -> void:
	await _plate_bands()
	for stem in PROPS:
		await _plate_six_axis(stem, DECOR % stem)
	await _plate_six_axis("tp_suv_01a", SUV)
	await _plate_chain()
	await _plate_gallery()
	await _plate_main()
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


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


## Blit `img` into tile `slot` of a 3-column sheet of `tile`-sized tiles.
func _blit(sheet: Image, img: Image, slot: int, tile: Vector2i) -> void:
	var copy := img.duplicate() as Image
	copy.resize(tile.x, tile.y, Image.INTERPOLATE_LANCZOS)
	var at := Vector2i((slot % 3) * tile.x, floori(slot / 3.0) * tile.y)
	sheet.blit_rect(copy, Rect2i(Vector2i.ZERO, tile), at)


# ------------------------------------------------------------ geometry helpers


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


## Local-space triangles of a mesh's opaque surfaces (glass is left out).
func _opaque_faces(mi: MeshInstance3D) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for i in mi.mesh.get_surface_count():
		var mat := mi.get_active_material(i)
		if mat != null and mat.resource_path == GLASS:
			continue
		var arrays := mi.mesh.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if index.is_empty():
			faces.append_array(verts)
		else:
			for k in index:
				faces.append(verts[k])
	return faces


## A static body per mesh with a trimesh of its opaque surfaces only.
func _add_colliders(node: Node) -> void:
	for mi in _meshes(node):
		if mi.get_parent() is StaticBody3D or mi.skin != null:
			continue
		var faces := _opaque_faces(mi)
		if faces.is_empty():
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var shape_node := CollisionShape3D.new()
		shape_node.shape = shape
		var body := StaticBody3D.new()
		body.add_child(shape_node)
		mi.add_child(body)


## Every point projects inside the viewport with a margin, and none is behind the camera.
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
	print(
		(
			"INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) height_px=%.0f ok=%s"
			% [label, lo.x, lo.y, hi.x, hi.y, hi.y - lo.y, ok]
		)
	)
	if not ok:
		_invalid("%s: projected bounds leave the viewport" % label)
	return ok


## Rays from the camera to points on the subject's opaque, camera-facing triangles; at
## least half must hit the subject first. Godot front faces wind clockwise, so a
## triangle faces the camera when its (b - a) x (c - a) normal points away from it.
func _prove_visible(cam: Camera3D, label: String, subject: Node3D) -> bool:
	var targets: Array[Vector3] = []
	var ortho := cam.projection == Camera3D.PROJECTION_ORTHOGONAL
	for mi in _meshes(subject):
		var faces := _opaque_faces(mi)
		var facing: Array[Vector3] = []
		for i in range(0, faces.size() - 2, 3):
			var a: Vector3 = mi.global_transform * faces[i]
			var b: Vector3 = mi.global_transform * faces[i + 1]
			var c: Vector3 = mi.global_transform * faces[i + 2]
			var mid := (a + b + c) / 3.0
			var view := cam.global_basis.z if ortho else cam.global_position - mid
			if (b - a).cross(c - a).dot(view) < 0.0:
				facing.append(mid)
		var step := maxi(1, floori(facing.size() / 12.0))
		for i in range(0, facing.size(), step):
			targets.append(facing[i])
	var space := cam.get_world_3d().direct_space_state
	var hits := 0
	for t in targets:
		var from := t + cam.global_basis.z * 500.0 if ortho else cam.global_position
		var q := PhysicsRayQueryParameters3D.create(from, t + (t - from).normalized() * 0.05)
		var hit := space.intersect_ray(q)
		if hit and subject.is_ancestor_of(hit.collider):
			hits += 1
	var ok := hits * 2 >= targets.size() and hits > 0
	print("VISIBLE %s ray_hits=%d/%d ok=%s" % [label, hits, targets.size(), ok])
	if not ok:
		_invalid("%s: occluded or not hit (%d of %d rays)" % [label, hits, targets.size()])
	return ok


## The posed character's bone positions in world space (a skinned AABB is the rest pose).
func _landmarks(character: Node) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for skel in character.find_children("*", "Skeleton3D", true, false):
		var s := skel as Skeleton3D
		for i in s.get_bone_count():
			out.append(s.global_transform * s.get_bone_global_pose(i).origin)
	return out


## Landmarks in frame, and at least half of them not hidden by the colliders.
func _prove_character(cam: Camera3D, label: String, character: Node3D) -> bool:
	var points := _landmarks(character)
	if points.is_empty():
		_invalid("%s: no skeleton landmarks" % label)
		return false
	if not _prove_in_frame(cam, label, points):
		return false
	var ortho := cam.projection == Camera3D.PROJECTION_ORTHOGONAL
	var space := cam.get_world_3d().direct_space_state
	var clear := 0
	for p in points:
		var from := p + cam.global_basis.z * 500.0 if ortho else cam.global_position
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(from, p)).is_empty():
			clear += 1
	var ok := clear * 2 >= points.size()
	print("VISIBLE %s landmarks_clear=%d/%d ok=%s" % [label, clear, points.size(), ok])
	if not ok:
		_invalid("%s: character hidden (%d of %d)" % [label, clear, points.size()])
	return ok


## Every surface carries one of the toon .tres resources.
func _check_materials(label: String, node: Node) -> void:
	var count := 0
	var wrong := 0
	for mi in _meshes(node):
		for i in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(i)
			if (
				mat != null
				and (mat.resource_path in TC_MATERIALS or mat.resource_path in TOON_MATERIALS)
			):
				count += 1
			else:
				wrong += 1
				print("MATERIAL %s %s/%d -> %s" % [label, mi.name, i, mat])
	print("MATERIALS %s toon_surfaces=%d wrong=%d" % [label, count, wrong])
	if count == 0 or wrong > 0:
		_invalid("%s: %d surfaces without a toon material" % [label, wrong])


func _spawn(path: String, parent: Node, pos: Vector3, yaw_deg := 0.0) -> Node3D:
	var node: Node3D = load(path).instantiate()
	node.position = pos
	node.rotation_degrees.y = yaw_deg
	parent.add_child(node)
	return node


## A character posed at `t` seconds of `clip`.
func _person(path: String, parent: Node, pos: Vector3, yaw_deg: float, clip: String) -> Node3D:
	var person := _spawn(path, parent, pos, yaw_deg)
	var player: AnimationPlayer = person.find_child("AnimationPlayer", true, false)
	if player == null or not player.has_animation(clip):
		_invalid("%s has no %s clip" % [path.get_file(), clip])
		return person
	player.play(clip)
	player.seek(player.get_animation(clip).length * 0.5, true)
	player.pause()
	return person


func _cube(parent: Node, pos: Vector3) -> MeshInstance3D:
	var cube := MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.1)
	cube.material_override = mat
	cube.position = pos
	cube.name = "ReferenceCube1m"
	parent.add_child(cube)
	return cube


func _studio(sky := false) -> Node3D:
	var studio := Node3D.new()
	var env := Environment.new()
	if sky:
		# The main scene's look: procedural sky, sky ambient, filmic tonemap.
		var sky_res := Sky.new()
		sky_res.sky_material = ProceduralSkyMaterial.new()
		env.background_mode = Environment.BG_SKY
		env.sky = sky_res
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.82, 0.86, 0.9)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.75, 0.8, 0.9)
		env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	studio.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	studio.add_child(sun)
	root.add_child(studio)
	return studio


func _ortho_cam(parent: Node) -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.far = 1000.0
	parent.add_child(cam)
	cam.make_current()
	return cam


## Orthographic size (vertical extent) that fits the box's projection with 15% room.
func _ortho_size(cam: Camera3D, box: AABB) -> float:
	var inv := cam.global_transform.affine_inverse()
	var w := 0.0
	var h := 0.0
	for p in _corners(box):
		var local := inv * p - inv * box.get_center()
		w = maxf(w, absf(local.x) * 2.0)
		h = maxf(h, absf(local.y) * 2.0)
	var aspect := root.get_visible_rect().size.x / root.get_visible_rect().size.y
	return maxf(h, w / aspect) * 1.15


# ------------------------------------------------------------ plates


## The TC ramp on white spheres, one per TC material, under one light of energy 1 with no
## ambient and a linear tonemap: the lit band must read white (>= 245), the middle band
## the ramp's 0.494 (175..198 in sRGB), the dark band and a cast shadow black (<= 12).
func _plate_bands() -> void:
	_beat("bands")
	var studio := Node3D.new()
	root.add_child(studio)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.3, 0.32, 0.36)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	studio.add_child(world_env)
	var to_light := Vector3(1, 0, 1).normalized()
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	studio.add_child(sun)
	sun.look_at_from_position(to_light * 20.0, Vector3.ZERO, Vector3.UP)
	var white := Image.create(4, 4, false, Image.FORMAT_RGB8)
	white.fill(Color.WHITE)
	var white_tex := ImageTexture.create_from_image(white)
	var across := Vector3(-1, 0, 1).normalized()
	var normals := {
		"lit": to_light,
		"middle": (to_light * 0.2 + across * sqrt(1.0 - 0.04)).normalized(),
		"dark": (to_light * -0.4 + across * sqrt(1.0 - 0.16)).normalized(),
	}
	var centres: Array[Vector3] = []
	for i in TC_MATERIALS.size():
		var mat: ShaderMaterial = (load(TC_MATERIALS[i]) as ShaderMaterial).duplicate()
		mat.next_pass = null
		mat.set_shader_parameter("albedo_texture", white_tex)
		for row in 2:
			var ball := MeshInstance3D.new()
			ball.mesh = SphereMesh.new()
			(ball.mesh as SphereMesh).radius = 1.0
			(ball.mesh as SphereMesh).height = 2.0
			ball.material_override = mat
			ball.position = Vector3(i * 3.0, -row * 3.5, 0)
			studio.add_child(ball)
		centres.append(Vector3(i * 3.0, 0, 0))
		# An occluder between the light and the second ball's lit pole.
		var block := MeshInstance3D.new()
		block.add_to_group("decor_probe_occluder")
		block.mesh = BoxMesh.new()
		(block.mesh as BoxMesh).size = Vector3(1.2, 1.2, 1.2)
		block.position = Vector3(i * 3.0, -3.5, 0) + to_light * 3.0
		studio.add_child(block)
	var cam := _ortho_cam(studio)
	cam.look_at_from_position(Vector3(6, -1.75, 50), Vector3(6, -1.75, 0), Vector3.UP)
	cam.size = 9.0
	var all_points: Array[Vector3] = []
	for c in centres:
		for band in normals:
			all_points.append(c + normals[band])
		all_points.append(c + Vector3(0, -3.5, 0) + to_light)
	if not _prove_in_frame(cam, "bands", all_points):
		studio.queue_free()
		return
	# Control: the same pixels with the occluders casting no shadow must read lit.
	for block in studio.get_tree().get_nodes_in_group("decor_probe_occluder"):
		(block as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var control := await _grab()
	for block in studio.get_tree().get_nodes_in_group("decor_probe_occluder"):
		(block as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var img := await _grab()
	for i in centres.size():
		var c := centres[i]
		var line := "BANDS %s" % TC_MATERIALS[i].get_file()
		var ok := true
		var values := {}
		for band in normals:
			values[band] = _pixel(img, cam, c + normals[band] * 0.97)
		var pole := c + Vector3(0, -3.5, 0) + to_light * 0.97
		values["shadow_off"] = _pixel(control, cam, pole)
		values["shadow"] = _pixel(img, cam, pole)
		for band in values:
			line += " %s=%d" % [band, values[band]]
		ok = values["lit"] >= 245 and values["middle"] >= 175 and values["middle"] <= 198
		ok = ok and values["dark"] <= 12 and values["shadow"] <= 12 and values["shadow_off"] >= 245
		print("%s ok=%s" % [line, ok])
		if not ok:
			_invalid("bands: %s does not show the TC ramp" % TC_MATERIALS[i].get_file())
	_save(img, "tc_ramp_bands.png")
	studio.queue_free()
	await _frames(2)


func _pixel(img: Image, cam: Camera3D, point: Vector3) -> int:
	var per := float(img.get_width()) / root.get_visible_rect().size.x
	var px := Vector2i((cam.unproject_position(point) * per).round())
	return roundi(img.get_pixelv(px).r * 255.0)


## Six orthographic views of one asset beside a 1 m cube, as a 3 x 2 sheet.
func _plate_six_axis(stem: String, path: String) -> void:
	_beat("six_axis_" + stem)
	var studio := _studio()
	var subject := _spawn(path, studio, Vector3.ZERO)
	_check_materials(stem, subject)
	var box := _aabb_of(subject)
	var cube := _cube(studio, Vector3(box.end.x + 1.0, 0.5, box.end.z + 1.0))
	var whole := box.merge(_aabb_of(cube))
	print(
		(
			"MEASURE %s size_m=(%.3f, %.3f, %.3f) min=%s max=%s"
			% [stem, box.size.x, box.size.y, box.size.z, box.position, box.end]
		)
	)
	_add_colliders(studio)
	await physics_frame
	await physics_frame
	var cam := _ortho_cam(studio)
	var sheet := Image.create(1920, 720, false, Image.FORMAT_RGBA8)
	var slot := 0
	for view in SIX_AXIS:
		var dir: Vector3 = SIX_AXIS[view]
		var up := Vector3.FORWARD if absf(dir.y) > 0.5 else Vector3.UP
		cam.look_at_from_position(whole.get_center() + dir * 200.0, whole.get_center(), up)
		cam.size = _ortho_size(cam, whole)
		var tag := "%s_%s" % [stem, view]
		await _frames(3)
		if _prove_in_frame(cam, tag, _corners(whole)) and _prove_visible(cam, tag, subject):
			_blit(sheet, await _grab(), slot, Vector2i(640, 360))
		slot += 1
	_save(sheet, "six_axis_%s_sheet.png" % stem)
	studio.queue_free()
	await _frames(2)


## Two posts 2 m apart with the chain hung from the first, front-on and three-quarter.
func _plate_chain() -> void:
	_beat("chain")
	var studio := _studio()
	var posts := Node3D.new()
	posts.name = "Stanchions"
	studio.add_child(posts)
	_spawn(DECOR % "tc_metal_pole_1a", posts, Vector3.ZERO)
	_spawn(DECOR % "tc_metal_pole_1a", posts, Vector3(0, 0, 2))
	var chain := _spawn(DECOR % "tc_metal_pole_chain_1a", studio, Vector3.ZERO)
	var cube := _cube(studio, Vector3(1.5, 0.5, 1.0))
	var box := _aabb_of(chain)
	print(
		(
			"CHAIN span_z=(%.3f, %.3f) hang_y=(%.3f, %.3f)"
			% [box.position.z, box.end.z, box.position.y, box.end.y]
		)
	)
	_add_colliders(studio)
	await physics_frame
	await physics_frame
	var whole := _aabb_of(posts).merge(_aabb_of(chain)).merge(_aabb_of(cube))
	var cam := _ortho_cam(studio)
	cam.look_at_from_position(Vector3(-200, 0.9, 1.0), Vector3(0, 0.9, 1.0), Vector3.UP)
	cam.size = _ortho_size(cam, whole)
	await _frames(3)
	if (
		_prove_in_frame(cam, "chain_side", _corners(whole))
		and _prove_visible(cam, "chain_side/chain", chain)
		and _prove_visible(cam, "chain_side/posts", posts)
	):
		_save(await _grab(), "chain_side.png")
	var persp := Camera3D.new()
	studio.add_child(persp)
	persp.make_current()
	persp.look_at_from_position(Vector3(-2.6, 1.9, 3.6), Vector3(0, 0.9, 1.0), Vector3.UP)
	await _frames(3)
	if (
		_prove_in_frame(persp, "chain_34", _corners(whole))
		and _prove_visible(persp, "chain_34/chain", chain)
	):
		_save(await _grab(), "chain_34.png")
	studio.queue_free()
	await _frames(2)


## The seat of a bench: up-facing triangles at the seat height (bench local space).
## Returns {centre: Vector3 local, facing: Vector3 local (+X, -X or +Z)}.
func _seat(bench: Node3D, height: float, side: String, part := "") -> Dictionary:
	var pts: Array[Vector3] = []
	var back: Array[Vector3] = []
	for mi in _meshes(bench):
		if part != "" and mi.name != part:
			continue
		var faces := _opaque_faces(mi)
		var to_bench := bench.global_transform.affine_inverse() * mi.global_transform
		for i in range(0, faces.size() - 2, 3):
			var a: Vector3 = to_bench * faces[i]
			var b: Vector3 = to_bench * faces[i + 1]
			var c: Vector3 = to_bench * faces[i + 2]
			var mid := (a + b + c) / 3.0
			# Godot front faces wind clockwise: the outward normal is -(b - a) x (c - a).
			var up := -(b - a).cross(c - a).normalized().y
			if absf(mid.y - height) < 0.03 and up > 0.9:
				pts.append(mid)
			if mid.y > height + 0.35:
				back.append(mid)
	var centre := Vector3.ZERO
	for p in pts:
		centre += p
	centre /= maxf(1.0, pts.size())
	var facing := Vector3(0, 0, 1)
	if side == "z":
		# The round tree bench: the seat ring on the +Z side, facing out.
		var ring: Array[Vector3] = []
		for p in pts:
			if p.z > 0.6 and absf(p.x) < 0.6:
				ring.append(p)
		centre = Vector3.ZERO
		for p in ring:
			centre += p
		centre /= maxf(1.0, ring.size())
		pts = ring
	else:
		var b := Vector3.ZERO
		for p in back:
			b += p
		b /= maxf(1.0, back.size())
		facing = Vector3(signf(centre.x - b.x), 0, 0)
	print(
		(
			"SEAT %s height=%.2f triangles=%d centre=%s facing=%s"
			% [bench.name, height, pts.size(), centre, facing]
		)
	)
	if pts.is_empty():
		_invalid("%s: no seat triangles at %.2f" % [bench.name, height])
	return {"centre": centre, "facing": facing}


## A seated passenger whose seat contact lands on the seat centre (sit contract).
func _sit(path: String, parent: Node, bench: Node3D, seat: Dictionary) -> Node3D:
	var facing: Vector3 = bench.global_basis * (seat["facing"] as Vector3)
	var contact: Vector3 = bench.global_transform * (seat["centre"] as Vector3)
	var rooted := contact + facing * float(CONTACT_BEHIND[path])
	rooted.y = 0.0
	var yaw := rad_to_deg(atan2(facing.x, facing.z))
	print(
		(
			"SIT %s on %s contact=%s seat_y=%.3f clip_seat_y=%.2f gap=%.3f"
			% [path.get_file(), bench.name, contact, contact.y, SEAT_TOP, contact.y - SEAT_TOP]
		)
	)
	return _person(path, parent, rooted, yaw, "sit_idle")


func _gallery_site() -> Dictionary:
	var site := _studio(true)
	for x in range(-14, 26):
		_spawn(WALL, site, Vector3(x + 0.5, 0, -3.0))
		for z in range(-3, 6):
			_spawn(FLOOR, site, Vector3(x + 0.5, 0, z + 0.5))
	var s := {"site": site}
	s["tree"] = _spawn(DECOR % "tc_tree_3a_indoor", site, Vector3(-12, 0, 0))
	s["fountain"] = _spawn(DECOR % "tc_fountain_1a_indoor", site, Vector3(-8.5, 0, 0))
	s["statue"] = _spawn(DECOR % "tc_statue_1b_indoor", site, Vector3(-5.5, 0, 0))
	s["tree_bench"] = _spawn(DECOR % "tc_bench_2a_indoor", site, Vector3(-1, 0, 0.5))
	s["bench"] = _spawn(DECOR % "tc_bench_1a", site, Vector3(3.5, 0, 0.5))
	s["pot_1a"] = _spawn(DECOR % "tc_plant_pot_1a", site, Vector3(6.5, 0, 0))
	s["pot_2a"] = _spawn(DECOR % "tc_plant_pot_2a", site, Vector3(8.8, 0, 0))
	s["bush"] = _spawn(DECOR % "tc_bush_1a", site, Vector3(11.2, 0, 0))
	s["can"] = _spawn(DECOR % "tc_trash_can_1a", site, Vector3(13.4, 0, 0))
	var posts := Node3D.new()
	posts.name = "Stanchions"
	site.add_child(posts)
	_spawn(DECOR % "tc_metal_pole_1a", posts, Vector3(16, 0, 3), 90.0)
	_spawn(DECOR % "tc_metal_pole_1a", posts, Vector3(18, 0, 3), 90.0)
	s["posts"] = posts
	s["chain"] = _spawn(DECOR % "tc_metal_pole_chain_1a", site, Vector3(16, 0, 3), 90.0)
	s["car"] = _spawn(SUV, site, Vector3(17.5, 0, 0), 90.0)
	s["cube"] = _cube(site, Vector3(-14, 0.5, 2))
	# Bench_1A faces along X at vendor scale; turn it to face the camera (+Z).
	var bench: Node3D = s["bench"]
	var seat_1a := _seat(bench, 0.75, "x")
	bench.rotation_degrees.y = -90.0 * signf((seat_1a["facing"] as Vector3).x)
	var seat_2a := _seat(s["tree_bench"], SEAT_TOP, "z", "Bench_2A")
	s["stand_f"] = _person(FEMALE, site, Vector3(-10.6, 0, 0.8), 0.0, "idle")
	s["stand_m"] = _person(MALE, site, Vector3(-4.3, 0, 0.8), 0.0, "idle")
	s["sit_2a"] = _sit(FEMALE, site, s["tree_bench"], seat_2a)
	s["sit_1a"] = _sit(MALE, site, bench, seat_1a)
	for key in ["tree", "fountain", "statue", "tree_bench", "bench", "car"]:
		_check_materials(key, s[key])
	return s


## The gallery through the TycoonCamera: close views, a seated close-up, 60 m and 120 m.
func _plate_gallery() -> void:
	_beat("gallery")
	var s := _gallery_site()
	var site: Node3D = s["site"]
	var people := ["stand_f", "stand_m", "sit_2a", "sit_1a"]
	for key in s:
		if key != "site" and key not in people:
			_add_colliders(s[key])
	var rig: Node3D = load(CAMERA).instantiate()
	site.add_child(rig)
	await _frames(20)
	await physics_frame
	await physics_frame
	var cam: Camera3D = rig.get_node("Camera3D")
	cam.make_current()
	var left := ["tree", "fountain", "statue", "tree_bench", "cube", "stand_f", "stand_m", "sit_2a"]
	var right := ["bench", "pot_1a", "pot_2a", "bush", "can", "sit_1a"]
	var shots := [
		["gallery_close_left", Vector3(-7.5, 0, 0.5), 14.0, 0.0, left],
		["gallery_close_right", Vector3(8.5, 0, 0.5), 14.0, 0.0, right],
		["gallery_close_car", Vector3(17, 0, 1), 11.0, 0.5, ["car", "posts", "chain"]],
		["gallery_distance_60m", Vector3(5, 0, 1), 60.0, 0.0, left + right + ["car", "posts"]],
		["gallery_distance_120m", Vector3(5, 0, 1), 120.0, 0.0, ["tree", "statue", "car", "bench"]],
	]
	for shot in shots:
		rig.position = shot[1]
		rig.distance = shot[2]
		rig.yaw = shot[3]
		rig.zoom(1.0)
		await _frames(4)
		print("CAMERA %s pos=%s distance=%.1f" % [shot[0], cam.global_position, shot[2]])
		if _prove_subjects(cam, shot[0], s, shot[4], people):
			_save(await _grab(), shot[0] + ".png")
	var close := Camera3D.new()
	site.add_child(close)
	close.make_current()
	var seated := [
		[
			"seated_tree_bench",
			Vector3(1.6, 1.7, 5.6),
			Vector3(-1, 0.8, 1.5),
			["tree_bench", "sit_2a"]
		],
		["seated_bench_1a", Vector3(5.6, 1.5, 4.5), Vector3(3.5, 0.7, 0.7), ["bench", "sit_1a"]],
	]
	for shot in seated:
		close.look_at_from_position(shot[1], shot[2], Vector3.UP)
		await _frames(3)
		if _prove_subjects(close, shot[0], s, shot[3], people):
			_save(await _grab(), shot[0] + ".png")
	site.queue_free()
	await _frames(2)


func _prove_subjects(
	cam: Camera3D, label: String, s: Dictionary, keys: Array, people: Array
) -> bool:
	var ok := true
	for key in keys:
		var tag := "%s/%s" % [label, key]
		if key in people:
			ok = _prove_character(cam, tag, s[key]) and ok
		else:
			ok = _prove_in_frame(cam, tag, _corners(_aabb_of(s[key]))) and ok
			ok = _prove_visible(cam, tag, s[key]) and ok
	return ok


## The real game: main.tscn with a random sim seed, a decor group set on the floor in
## front of the TycoonCamera's home focus, from the camera's home framing and close up.
## Rays are cast against colliders from every mesh in the scene, except meshes whose
## dissolve shader currently drops them (the shell roof near the camera).
func _plate_main() -> void:
	_beat("main")
	var main: Node3D = (load(MAIN_SCENE) as PackedScene).instantiate()
	var clock := main.get_node("SimClock") as SimClock
	var sim_seed := randi()
	clock.seed_rng(sim_seed)
	print("PROBE sim_seed=", sim_seed)
	root.add_child(main)
	clock.set_process(false)
	var mode := main.get_node("BuildMode") as Node3D
	mode.set_process(false)
	(mode.get_node("Ghost") as Node3D).visible = false
	var rig: Node3D = main.get_node("TycoonCamera")
	var cam: Camera3D = main.get_node("TycoonCamera/Camera3D")
	await _frames(20)
	var focus := rig.global_position
	print("MAIN focus=%s" % focus)
	var group := Node3D.new()
	group.name = "DecorGroup"
	main.add_child(group)
	var s := {}
	s["tree"] = _spawn(DECOR % "tc_tree_3a_indoor", group, focus + Vector3(-5, 0, 2))
	s["fountain"] = _spawn(DECOR % "tc_fountain_1a_indoor", group, focus + Vector3(-2, 0, 2))
	s["tree_bench"] = _spawn(DECOR % "tc_bench_2a_indoor", group, focus + Vector3(2, 0, 2))
	s["statue"] = _spawn(DECOR % "tc_statue_1b_indoor", group, focus + Vector3(5.5, 0, 2))
	s["car"] = _spawn(SUV, group, focus + Vector3(0, 0, 6), 90.0)
	s["pot"] = _spawn(DECOR % "tc_plant_pot_2a", group, focus + Vector3(-5, 0, 6))
	s["person"] = _person(FEMALE, group, focus + Vector3(-3.5, 0, 3), 0.0, "idle")
	for mi in _meshes(main):
		if not _dropped(mi):
			_add_colliders(mi)
	await physics_frame
	await physics_frame
	var keys := ["tree", "fountain", "tree_bench", "statue", "car", "pot", "person"]
	for shot in [["main_home", -1.0], ["main_close", 22.0]]:
		if shot[1] > 0.0:
			rig.distance = shot[1]
			rig.zoom(1.0)
		await _frames(6)
		print("CAMERA %s pos=%s focus=%s" % [shot[0], cam.global_position, rig.global_position])
		if _prove_subjects(cam, shot[0], s, keys, ["person"]):
			_save(await _grab(), shot[0] + ".png")
	main.queue_free()
	await _frames(2)


## Whether a dissolve material currently drops this mesh (dissolve >= 0.5).
func _dropped(mi: MeshInstance3D) -> bool:
	if mi.mesh == null:
		return true
	for i in mi.mesh.get_surface_count():
		var mat := mi.get_active_material(i) as ShaderMaterial
		if mat != null:
			var amount: Variant = mat.get_shader_parameter("dissolve")
			if amount != null and float(amount) >= 0.5:
				return true
	return false
