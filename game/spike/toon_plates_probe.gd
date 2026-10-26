extends SceneTree
## Windowed plate probe for the first Toon Series import batch.
##
## Run (one windowed Godot run project-wide; this probe holds the slot while it runs):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game -s res://spike/toon_plates_probe.gd
##
## Stages: a direct-light calibration of the toon shader (is ALBEDO multiplied in once
## after light()?), the main scene through the TycoonCamera at its default framing,
## six-axis orthographic plates of the plane and the male character beside a 1 m cube,
## then the whole batch placed in the main scene: close, scale and distance shots and an
## idle frame strip. Plates go to tools/blender/out/toon_import/.
## Every plate proves its subjects are in frame (projected bounds inside the viewport,
## none behind the camera) and hit by rays (temporary trimesh colliders) before it is
## saved; otherwise the probe prints PROBE_INVALID and exits 1.

const OUT_REL := "res://../tools/blender/out/toon_import"
const MAIN_SCENE := "res://main/main.tscn"
const PLANE := "res://assets/planes/tp_plane_05a.glb"
const MALE := "res://assets/people/tcp_male_character_01.glb"
const FEMALE := "res://assets/people/tcp_female_character_01.glb"
const TRUCK := "res://assets/vehicles/tp_loading_truck_01a.glb"
const TERMINAL := "res://assets/buildings/tp_airport_01a.glb"
const RUNWAY := "res://assets/airside/tp_runway_0%da.glb"
const TOON_MATERIALS := [
	"res://assets/materials/tp_atlas_toon.tres",
	"res://assets/materials/tp_atlas_simple_toon.tres",
	"res://assets/materials/tcp_atlas_toon.tres",
	"res://assets/materials/tp_glass.tres",
	"res://assets/materials/tp_lights.tres",
]
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
			OS.crash("toon plates probe hung")


func _run() -> void:
	await _calibrate()
	var main: Node3D = load(MAIN_SCENE).instantiate()
	root.add_child(main)
	await _plate_main_camera(main)
	main.queue_free()
	await _frames(2)
	await _plate_six_axis("plane", PLANE, false)
	await _plate_six_axis("male", MALE, true)
	await _plate_in_context()
	_finish()


func _finish() -> void:
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
	return root.get_texture().get_image()


func _save(img: Image, name: String) -> void:
	var path := _out_dir.path_join(name)
	var err := img.save_png(path)
	if err != OK:
		_invalid("could not save %s (error %d)" % [path, err])
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


# ------------------------------------------------------------ calibration


## Direct light only (no sky, no ambient, linear tonemap): a white and a mid-grey
## albedo under a light of energy 1 straight above must read 255 and ~188 (linear 0.5).
## No multiply after light() reads grey as 255; a double multiply reads ~137.
func _calibrate() -> void:
	_beat("calibrate")
	var studio := Node3D.new()
	root.add_child(studio)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	studio.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-90, 0, 0)
	studio.add_child(sun)
	var base: ShaderMaterial = load(TOON_MATERIALS[0])
	var patches := {"white": Color(1, 1, 1), "grey": Color(0.7354, 0.7354, 0.7354)}
	var x := -1.5
	for key in patches:
		var mat: ShaderMaterial = base.duplicate()
		mat.next_pass = null
		var swatch := Image.create(4, 4, false, Image.FORMAT_RGB8)
		swatch.fill(patches[key])
		mat.set_shader_parameter("albedo_texture", ImageTexture.create_from_image(swatch))
		var quad := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(2, 2)
		quad.mesh = plane
		quad.material_override = mat
		quad.position = Vector3(x, 0, 0)
		studio.add_child(quad)
		x += 3.0
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 4.0
	cam.position = Vector3(0, 5, 0)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	studio.add_child(cam)
	cam.make_current()
	var img := await _grab()
	var white := img.get_pixelv(Vector2i(cam.unproject_position(Vector3(-1.5, 0, 0))))
	var grey := img.get_pixelv(Vector2i(cam.unproject_position(Vector3(1.5, 0, 0))))
	# Expected: white >= 245, grey 178..198. Grey 255 = no multiply, ~137 = double.
	print("CALIBRATION white=%d grey=%d" % [roundi(white.r * 255.0), roundi(grey.r * 255.0)])
	if white.r * 255.0 < 245.0 or grey.r * 255.0 < 178.0 or grey.r * 255.0 > 198.0:
		_invalid("calibration: toon light() does not give a single albedo multiply")
	studio.queue_free()
	await _frames(2)


# ------------------------------------------------------------ proofs


func _aabb_of(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(node):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## The node itself when it is a mesh, plus every mesh below it.
func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		out.append(mi)
	return out


func _corners(box: AABB) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in 8:
		out.append(box.get_endpoint(i))
	return out


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
	print("INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) ok=%s" % [label, lo.x, lo.y, hi.x, hi.y, ok])
	if not ok:
		_invalid("%s: projected bounds leave the viewport" % label)
	return ok


## Rays from the camera to sampled surface points of the subject; at least half must
## hit the subject first. Supporting evidence only: the plate itself shows visibility.
func _prove_visible(cam: Camera3D, label: String, subject: Node3D) -> bool:
	var targets: Array[Vector3] = []
	var centre := _aabb_of(subject).get_center()
	for mi in _meshes(subject):
		var faces: PackedVector3Array = mi.mesh.get_faces()
		var step := maxi(1, floori(faces.size() / 6.0))
		for i in range(0, faces.size(), step):
			# A vertex on an outer edge can slip past its own trimesh; aim 5% inside.
			targets.append((mi.global_transform * faces[i]).lerp(centre, 0.05))
	var space := cam.get_world_3d().direct_space_state
	var hits := 0
	for t in targets:
		var from := cam.global_position
		if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
			from = t + cam.global_basis.z * 500.0
		var q := PhysicsRayQueryParameters3D.create(from, t + (t - from).normalized() * 0.05)
		var hit := space.intersect_ray(q)
		if hit and (hit.collider == subject or subject.is_ancestor_of(hit.collider)):
			hits += 1
	var ok := hits * 2 >= targets.size() and hits > 0
	print("VISIBLE %s ray_hits=%d/%d ok=%s" % [label, hits, targets.size(), ok])
	if not ok:
		_invalid("%s: occluded or not hit (%d of %d rays)" % [label, hits, targets.size()])
	return ok


func _add_colliders(node: Node) -> void:
	for mi in _meshes(node):
		if mi.mesh != null:
			mi.create_trimesh_collision()


## Every surface of an imported asset carries one of the toon .tres resources.
func _check_materials(label: String, node: Node) -> void:
	var count := 0
	var wrong := 0
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(i)
			if mat != null and mat.resource_path in TOON_MATERIALS:
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
	_check_materials(path.get_file(), node)
	var player: AnimationPlayer = node.find_child("AnimationPlayer", true, false)
	if player != null:
		print("ANIM %s list=%s" % [path.get_file(), player.get_animation_list()])
		player.play("idle")
	return node


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


func _studio() -> Node3D:
	var studio := Node3D.new()
	var env := Environment.new()
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


# ------------------------------------------------------------ plates


func _plate_main_camera(main: Node3D) -> void:
	_beat("main_camera")
	await _frames(20)
	var rig: Node3D = main.get_node("TycoonCamera")
	var cam: Camera3D = main.get_node("TycoonCamera/Camera3D")
	var ground: Node3D = main.get_node("Ground")
	_add_colliders(main)
	await physics_frame
	await physics_frame
	var focus: Array[Vector3] = [rig.global_position]
	print(
		"MAINCAM cam_pos=%s focus=%s fov=%.1f" % [cam.global_position, rig.global_position, cam.fov]
	)
	if _prove_in_frame(cam, "main_focus", focus) and _prove_visible(cam, "main_ground", ground):
		_save(await _grab(), "main_camera_default.png")


func _plate_six_axis(label: String, path: String, animated: bool) -> void:
	_beat("six_axis_" + label)
	var studio := _studio()
	var subject := _spawn(path, studio, Vector3.ZERO)
	if animated:
		var player: AnimationPlayer = subject.find_child("AnimationPlayer", true, false)
		player.seek(0.0, true)
		player.pause()
	var box := _aabb_of(subject)
	var cube := _cube(studio, Vector3(box.end.x + 1.0, 0.5, box.end.z + 1.0))
	var whole := box.merge(_aabb_of(cube))
	print(
		(
			"MEASURE %s size_m=(%.3f, %.3f, %.3f) pos=%s"
			% [label, box.size.x, box.size.y, box.size.z, box.position]
		)
	)
	_add_colliders(studio)
	await physics_frame
	await physics_frame
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.far = 1000.0
	studio.add_child(cam)
	cam.make_current()
	var sheet := Image.create(1920, 720, false, Image.FORMAT_RGBA8)
	var slot := 0
	for view in SIX_AXIS:
		var dir: Vector3 = SIX_AXIS[view]
		var up := Vector3.FORWARD if absf(dir.y) > 0.5 else Vector3.UP
		cam.look_at_from_position(whole.get_center() + dir * 200.0, whole.get_center(), up)
		cam.size = _ortho_size(cam, whole)
		var tag := "%s_%s" % [label, view]
		await _frames(3)
		if not _prove_in_frame(cam, tag, _corners(whole)):
			continue
		if not _prove_visible(cam, tag, subject):
			continue
		var img := await _grab()
		img.convert(Image.FORMAT_RGBA8)
		_save(img, "six_axis_%s.png" % tag)
		img.resize(640, 360, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(
			img, Rect2i(0, 0, 640, 360), Vector2i((slot % 3) * 640, floori(slot / 3.0) * 360)
		)
		slot += 1
	_save(sheet, "six_axis_%s_sheet.png" % label)
	studio.queue_free()
	await _frames(2)


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


func _plate_in_context() -> void:
	_beat("in_context")
	var main: Node3D = load(MAIN_SCENE).instantiate()
	root.add_child(main)
	var site := Node3D.new()
	site.name = "ToonBatch"
	main.add_child(site)
	# A straight runway along X on the far side of the apron: end, four straights, end.
	_spawn(RUNWAY % 1, site, Vector3(-192, 0, 40), 180.0)
	var runway: Node3D = null
	for i in 4:
		var piece := _spawn(RUNWAY % (i + 2), site, Vector3(-144 + 96 * i, 0, 40))
		if i == 2:
			runway = piece
	_spawn(RUNWAY % 1, site, Vector3(192, 0, 40))
	# The terminal's road and car park face its local +Z, so it turns 180 degrees to put
	# the landside away from the apron.
	var terminal := _spawn(TERMINAL, site, Vector3(0, 0, -60), 180.0)
	var plane := _spawn(PLANE, site, Vector3(0, 0, -12))
	var truck := _spawn(TRUCK, site, Vector3(20, 0, -14))
	var male := _spawn(MALE, site, Vector3(-8, 0, -30))
	var female := _spawn(FEMALE, site, Vector3(-6.2, 0, -30), 20.0)
	var cube := _cube(site, Vector3(-10, 0.5, -30))
	await _frames(20)
	_add_colliders(main)
	await physics_frame
	await physics_frame
	var rig: Node3D = main.get_node("TycoonCamera")
	var cam: Camera3D = main.get_node("TycoonCamera/Camera3D")
	var shots := [
		[
			"in_context_close",
			Vector3(-2, 0, -16),
			55.0,
			[plane, truck, male, female, cube],
			[],
			0.0
		],
		["in_context_scale", Vector3(-7.5, 0, -30), 12.0, [male, female, cube], [], 0.0],
		# Side-on (yaw 90) so the terminal-to-runway depth runs across the wide axis. A 96 m
		# runway piece cannot fit whole beside the terminal; its centre must.
		[
			"in_context_distance",
			Vector3(0, 0, -30),
			120.0,
			[terminal, plane, truck],
			[runway],
			PI / 2
		],
	]
	for shot in shots:
		rig.position = shot[1]
		rig.distance = shot[2]
		rig.yaw = shot[5]
		rig.zoom(1.0)
		await _frames(4)
		if await _prove_shot(cam, shot[0], shot[3], shot[4]):
			_save(await _grab(), shot[0] + ".png")
	await _idle_strip(rig, cam, [male, female, cube])
	main.queue_free()
	await _frames(2)


## `whole` subjects must fit entirely; `partial` ones need only their bounds centre.
func _prove_shot(cam: Camera3D, label: String, whole: Array, partial: Array) -> bool:
	var ok := true
	for s in whole + partial:
		var tag := "%s/%s" % [label, s.name]
		var points: Array[Vector3] = _corners(_aabb_of(s))
		if s in partial:
			points = [_aabb_of(s).get_center()]
		ok = _prove_in_frame(cam, tag, points) and ok
		ok = _prove_visible(cam, tag, s) and ok
	return ok


## Four moments of the idle loop, cropped to the people and the cube, side by side.
func _idle_strip(rig: Node3D, cam: Camera3D, subjects: Array) -> void:
	_beat("idle_strip")
	rig.position = Vector3(-7.5, 0, -30)
	rig.distance = 12.0
	rig.yaw = 0.0
	rig.zoom(1.0)
	await _frames(4)
	if not await _prove_shot(cam, "idle_strip", subjects, []):
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for s in subjects:
		for p in _corners(_aabb_of(s)):
			lo = lo.min(cam.unproject_position(p))
			hi = hi.max(cam.unproject_position(p))
	var crop := Rect2i(Rect2(lo, hi - lo).grow(24.0)).intersection(
		Rect2i(Vector2i.ZERO, Vector2i(root.get_visible_rect().size))
	)
	var players: Array[AnimationPlayer] = []
	for s in subjects:
		var p: AnimationPlayer = s.find_child("AnimationPlayer", true, false)
		if p != null:
			players.append(p)
	var length := players[0].get_animation("idle").length
	print("IDLE length_s=%.3f loop=%s" % [length, players[0].get_animation("idle").loop_mode])
	var strip := Image.create(crop.size.x * 4, crop.size.y, false, Image.FORMAT_RGBA8)
	for k in 4:
		for p in players:
			p.seek(length * k / 4.0, true)
			p.pause()
		var img := await _grab()
		img.convert(Image.FORMAT_RGBA8)
		strip.blit_rect(img, crop, Vector2i(k * crop.size.x, 0))
	_save(strip, "idle_strip.png")
