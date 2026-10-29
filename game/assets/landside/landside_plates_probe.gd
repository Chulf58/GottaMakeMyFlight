extends SceneTree
## Windowed plate probe for the landside assets: the taxis, SUVs and van, the surface lot
## (tp_parking_01a), the multi-storey car park (tc_parking_2a) and the authored kerb
## drop-off bay (tp_curb_bay_01a).
##
## Run (one windowed Godot run project-wide; this probe holds the slot while it runs):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://assets/landside/landside_plates_probe.gd
##
## Stages: six-axis orthographic plates of every asset beside a 1 m cube; then the real
## main.tscn with a random sim seed, the bay on the kerb in front of doors 5 and 6, a taxi
## and an SUV on its berth markers and a van in the through lane, all heading -x as
## traffic keeps right on the terminal-side carriageway (decision
## landside-traffic-drives-on-the-right-the-terminal-side-carri), and the lot and the
## multi-storey on the open ground past z -40 (an illustrative layout: the build spots
## belong to a later lane), seen close, from the default distance and from far away.
## Every plate proves its subjects are in frame (projected bounds inside the viewport)
## and hit by camera rays against colliders from their opaque surfaces; otherwise the
## probe prints PROBE_INVALID and exits 1. The bay is single-sided paint lying flat, so
## its edge-on and from-below views have nothing to hit; those tiles are proven in frame
## only and say so. Plates go to tools/blender/out/landside/.

const OUT_REL := "res://../tools/blender/out/landside"
const ASSET := "res://assets/%s.glb"
const CAMERA_RIG := "TycoonCamera"
const MAIN_SCENE := "res://main/main.tscn"
const GLASS := "res://assets/materials/tp_glass.tres"
const TOON_MATERIALS := [
	"res://assets/materials/tp_atlas_toon.tres",
	"res://assets/materials/tp_atlas_simple_toon.tres",
	"res://assets/materials/tp_lights.tres",
	"res://assets/materials/tp_glass.tres",
	"res://assets/materials/tc_building_17a_toon.tres",
]
const STEMS := [
	"vehicles/tp_taxi_01a",
	"vehicles/tp_taxi_01b",
	"vehicles/tp_taxi_01c",
	"vehicles/tp_suv_01b",
	"vehicles/tp_suv_01c",
	"vehicles/tp_van_01a",
	"landside/tp_parking_01a",
	"landside/tc_parking_2a",
	"landside/tp_curb_bay_01a",
]
const BAY := "landside/tp_curb_bay_01a"
## Measured on tp_airport_shell.glb (survey this lane): road and sidewalk top are one
## plane at y 0.107; the near kerb line runs at z -58.7 in the main scene (shell at z -80).
const ROAD_TOP := 0.107
const KERB_Z := -58.7
const GROUND_Y := -0.1
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 120000
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
var _main_plates: Array[Image] = []


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
			OS.crash("landside plates probe hung")


func _run() -> void:
	if not "--main-only" in OS.get_cmdline_user_args():
		for stem in STEMS:
			await _plate_six_axis(stem)
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


## Blit `img` into tile `slot` of a sheet with `cols` columns of `tile`-sized tiles.
func _blit(sheet: Image, img: Image, slot: int, tile: Vector2i, cols := 3) -> void:
	var copy := img.duplicate() as Image
	copy.resize(tile.x, tile.y, Image.INTERPOLATE_LANCZOS)
	var at := Vector2i((slot % cols) * tile.x, floori(slot / float(cols)) * tile.y)
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
		shape.backface_collision = true
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
			"INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) size_px=(%.0f, %.0f) ok=%s"
			% [label, lo.x, lo.y, hi.x, hi.y, hi.x - lo.x, hi.y - lo.y, ok]
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
	var blockers := {}
	for t in targets:
		var from := t + cam.global_basis.z * 500.0 if ortho else cam.global_position
		var q := PhysicsRayQueryParameters3D.create(from, t + (t - from).normalized() * 0.05)
		var hit := space.intersect_ray(q)
		if hit and subject.is_ancestor_of(hit.collider):
			hits += 1
		elif hit:
			var by: Node = hit.collider.get_parent()
			blockers[by.name] = int(blockers.get(by.name, 0)) + 1
	var ok := hits * 2 >= targets.size() and hits > 0
	print(
		(
			"VISIBLE %s ray_hits=%d/%d ok=%s blocked_by=%s"
			% [label, hits, targets.size(), ok, blockers]
		)
	)
	if not ok:
		_invalid("%s: occluded or not hit (%d of %d rays)" % [label, hits, targets.size()])
	return ok


## Every surface carries one of the toon .tres resources.
func _check_materials(label: String, node: Node) -> void:
	var count := 0
	var wrong := 0
	for mi in _meshes(node):
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


func _spawn(stem: String, parent: Node, pos: Vector3, yaw_deg := 0.0) -> Node3D:
	var node: Node3D = load(ASSET % stem).instantiate()
	node.position = pos
	node.rotation_degrees.y = yaw_deg
	parent.add_child(node)
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


## Per-part node origins and bounds in the asset's frame (hinges of the barrier arms,
## the berth markers of the bay).
func _report_parts(stem: String, subject: Node3D) -> void:
	for mi in _meshes(subject):
		if "Barrier" in mi.name:
			var box: AABB = mi.global_transform * mi.get_aabb()
			print(
				(
					"PART %s %s origin=%s rotation_deg=%s aabb_min=%s aabb_max=%s"
					% [
						stem,
						mi.name,
						mi.global_position,
						mi.global_rotation_degrees,
						box.position,
						box.end
					]
				)
			)
	for marker in subject.find_children("Mount_*", "Node3D", true, false):
		print("MARKER %s %s at=%s" % [stem, marker.name, (marker as Node3D).global_position])


# ------------------------------------------------------------ plates


## Six orthographic views of one asset beside a 1 m cube, as a 3 x 2 sheet.
func _plate_six_axis(stem: String) -> void:
	var label := stem.get_file()
	_beat("six_axis_" + label)
	var studio := _studio()
	var subject := _spawn(stem, studio, Vector3.ZERO)
	_check_materials(label, subject)
	_report_parts(label, subject)
	var box := _aabb_of(subject)
	var cube := _cube(studio, Vector3(box.end.x + 1.0, 0.5, box.end.z + 1.0))
	var whole := box.merge(_aabb_of(cube))
	print(
		(
			"MEASURE %s size_m=(%.3f, %.3f, %.3f) min=%s max=%s"
			% [label, box.size.x, box.size.y, box.size.z, box.position, box.end]
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
		var ok := _prove_in_frame(cam, tag, _corners(whole))
		if stem == BAY and view != "top":
			print("VISIBLE %s skipped: flat single-sided paint, seen edge-on or from below" % tag)
		else:
			ok = _prove_visible(cam, tag, subject) and ok
		if ok:
			_blit(sheet, await _grab(), slot, Vector2i(640, 360))
		slot += 1
	_save(sheet, "six_axis_%s_sheet.png" % label)
	studio.queue_free()
	await _frames(2)


## The real game: main.tscn with a random sim seed and the landside set placed on and
## past the road. Rays are cast against colliders from every mesh in the scene, except
## meshes whose dissolve shader currently drops them (the shell roof near the camera).
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
	var rig: Node3D = main.get_node(CAMERA_RIG)
	var cam: Camera3D = main.get_node(CAMERA_RIG + "/Camera3D")
	await _frames(10)
	var group := Node3D.new()
	group.name = "LandsideGroup"
	main.add_child(group)
	var s := {}
	# Bay on the near kerb in front of doors 5 and 6 (x 16 and 25).
	s["bay"] = _spawn(BAY, group, Vector3(20.5, ROAD_TOP, KERB_Z))
	var berth_1: Node3D = s["bay"].find_child("Mount_Berth_1", true, false)
	var berth_2: Node3D = s["bay"].find_child("Mount_Berth_2", true, false)
	if berth_1 == null or berth_2 == null:
		_invalid("bay has no berth markers")
		main.queue_free()
		return
	s["taxi"] = _spawn("vehicles/tp_taxi_01a", group, berth_1.global_position, -90.0)
	s["suv"] = _spawn("vehicles/tp_suv_01b", group, berth_2.global_position, -90.0)
	s["van"] = _spawn("vehicles/tp_van_01a", group, Vector3(2.0, ROAD_TOP, -53.5), -90.0)
	# Lot across the road from the bay, its barrier side (local -x) facing the road (slab z
	# -40..-7.7); the multi-storey further west, where it does not hide the bay from the
	# default heading (from (22, 0, -14) it filled the close view of the kerb), in the
	# vendor heading: turned 180 degrees its ground-floor entry arrows faced away from the road.
	s["lot"] = _spawn("landside/tp_parking_01a", group, Vector3(18.0, GROUND_Y, -32.7), -90.0)
	s["multi"] = _spawn("landside/tc_parking_2a", group, Vector3(-26.0, GROUND_Y, -14.0))
	for key in s:
		var b := _aabb_of(s[key])
		print("PLACED %s min=%s max=%s" % [key, b.position, b.end])
	for mi in _meshes(main):
		_add_colliders(mi)
	await physics_frame
	await physics_frame
	var near := ["bay", "taxi", "suv", "van"]
	var shots := [
		["main_landside_close", Vector3(20.5, 0, -56.0), 30.0, 0.0, near],
		["main_landside_angle", Vector3(14.0, 0, -52.0), 45.0, -0.6, near],
		["main_landside_mid", Vector3(2.0, 0, -28.0), 120.0, 0.0, near + ["lot", "multi"]],
		["main_landside_distance", Vector3(0, 0, -40.0), 200.0, 0.0, near + ["lot", "multi"]],
		["main_landside_max", Vector3(0, 0, -40.0), 300.0, 0.0, near + ["lot", "multi"]],
	]
	for shot in shots:
		_beat(shot[0])
		rig.position = shot[1]
		rig.set("yaw", shot[3])
		rig.distance = shot[2]
		rig.zoom(1.0)
		# Let the roof cutaway finish its transition (0.4 s) before reading its state.
		await create_timer(1.5).timeout
		await _frames(4)
		_report_roof(main, shot[0])
		# Colliders follow the dissolve state of this camera position.
		for body in main.find_children("*", "StaticBody3D", true, false):
			var mi := body.get_parent() as MeshInstance3D
			if mi != null:
				(body as StaticBody3D).process_mode = (
					Node.PROCESS_MODE_DISABLED if _dropped(mi) else Node.PROCESS_MODE_INHERIT
				)
		await physics_frame
		await physics_frame
		print(
			(
				"CAMERA %s pos=%s focus=%s distance=%.1f yaw=%.2f"
				% [shot[0], cam.global_position, rig.global_position, shot[2], shot[3]]
			)
		)
		var ok := true
		for key in shot[4]:
			var tag := "%s/%s" % [shot[0], key]
			ok = _prove_in_frame(cam, tag, _corners(_aabb_of(s[key]))) and ok
			ok = _prove_visible(cam, tag, s[key]) and ok
		if ok:
			var img := await _grab()
			_save(img, shot[0] + ".png")
			_main_plates.append(img)
		else:
			# Evidence of what failed; the run still fails.
			_save(await _grab(), shot[0] + "_INVALID.png")
	main.queue_free()
	await _frames(2)
	if not _main_plates.is_empty():
		var sheet := Image.create(1920, 1080, false, Image.FORMAT_RGBA8)
		for i in _main_plates.size():
			_blit(sheet, _main_plates[i], i, Vector2i(960, 540), 2)
		_save(sheet, "main_landside_contact_sheet.png")


## Whether a dissolve material has fully dropped this mesh (dissolve >= 0.99). A mesh
## part-way through its fade still draws pixels, so it keeps its collider.
func _dropped(mi: MeshInstance3D) -> bool:
	if mi.mesh == null:
		return true
	for i in mi.mesh.get_surface_count():
		var mat := mi.get_active_material(i) as ShaderMaterial
		if mat != null:
			var amount: Variant = mat.get_shader_parameter("dissolve")
			if amount != null and float(amount) >= 0.99:
				return true
	return false


## The roof pieces' dissolve amounts at this camera position (0 drawn, 1 gone).
func _report_roof(main: Node, label: String) -> void:
	var parts := []
	for piece in ["Upper", "Canopy", "Poles", "Lights_Upper"]:
		var mi := main.find_child(piece, true, false) as MeshInstance3D
		if mi == null or mi.mesh == null:
			parts.append("%s=missing" % piece)
			continue
		var mat := mi.get_active_material(0) as ShaderMaterial
		var amount: Variant = mat.get_shader_parameter("dissolve") if mat != null else null
		parts.append("%s=%s" % [piece, amount])
	print("ROOF %s %s" % [label, " ".join(parts)])
