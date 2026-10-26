extends SceneTree
## Windowed plate probe for the cafe pieces of the interior kit.
##
## Run (one windowed Godot run project-wide; take the slot lock first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/cafe_kit_plates_probe.gd
##
## Stages: six-axis orthographic plates of cafe_counter and cafe_table beside a 1 m
## cube; a seated-fit sheet with both characters placed on the table's Mount_SitRoot
## nodes through sit_down, sit_idle and stand_up; then a cafe corner (a staff member and
## a customer on the counter's mounts, two sitters at one of two tables) through the
## real TycoonCamera at two headings, close up, and from 30 m and 60 m. Plates go to
## tools/blender/out/cafe-kit/. Every plate proves each subject is in frame (projected
## bounds inside the viewport) and that the kit pieces are hit by camera rays against
## colliders built from their opaque surfaces, or the probe prints PROBE_INVALID and
## exits 1. Characters get no colliders (their rest-pose mesh is not the drawn pose);
## their posed bone positions must be in frame and at least half not hidden by the kit.
## `-- --tables=cafe_table,<other>` runs the seated-fit stage on more table pieces.
## The probe checks framing and visibility only; whether bodies clip the furniture is
## judged from the seated-fit strips.

const OUT_REL := "res://../tools/blender/out/cafe-kit"
const KIT := "res://assets/interior/%s.glb"
const MALE := "res://assets/people/tcp_male_character_01.glb"
const FEMALE := "res://assets/people/tcp_female_character_01.glb"
const CAMERA := "res://camera/tycoon_camera.tscn"
const GLASS := "res://assets/materials/tp_glass.tres"
const PIECES := ["cafe_counter", "cafe_table"]
const CLIPS := ["idle", "sit_down", "sit_idle", "stand_up"]
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
## North-west corner of the cafe corner on the ground, in metres; it is 7 x 5 cells.
const ROOM_NW := Vector3(-3.5, 0, -40)

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
			OS.crash("cafe kit probe hung")


func _run() -> void:
	for piece in PIECES:
		var sheet := Image.create(1920, 720, false, Image.FORMAT_RGBA8)
		await _plate_six_axis(piece, sheet)
		_save(sheet, "six_axis_%s_sheet.png" % piece)
	# `-- --tables=a,b` runs the seated-fit stage on other table pieces too.
	var tables := ["cafe_table"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tables="):
			tables = Array(arg.trim_prefix("--tables=").split(","))
	for piece in tables:
		await _plate_seated_fit(piece)
	await _plate_corner()
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
	img.resize(tile.x, tile.y, Image.INTERPOLATE_LANCZOS)
	var at := Vector2i((slot % 3) * tile.x, floori(slot / 3.0) * tile.y)
	sheet.blit_rect(img, Rect2i(Vector2i.ZERO, tile), at)


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


## World-space triangles of a mesh's opaque surfaces (glass is left out).
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
	print("INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) ok=%s" % [label, lo.x, lo.y, hi.x, hi.y, ok])
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


func _spawn(path: String, parent: Node, pos: Vector3, yaw_deg := 0.0) -> Node3D:
	var node: Node3D = load(path).instantiate()
	node.position = pos
	node.rotation_degrees.y = yaw_deg
	parent.add_child(node)
	return node


func _player(node: Node) -> AnimationPlayer:
	return node.find_child("AnimationPlayer", true, false)


## Holds `clip` at `t` seconds on a character.
func _pose(character: Node, clip: String, t: float) -> void:
	var player := _player(character)
	player.play(clip)
	player.seek(t, true)
	player.pause()


## A character with its root on `mount` of `piece` (position and facing), posed, or
## null (after PROBE_INVALID) when the mount, the player or a clip is missing.
func _at_mount(
	path: String, parent: Node, piece: Node3D, mount: String, clip: String, t: float
) -> Node3D:
	var marker := piece.find_child(mount, true, false) as Node3D
	if marker == null:
		_invalid("%s has no %s node" % [piece.name, mount])
		return null
	var character: Node3D = load(path).instantiate()
	parent.add_child(character)
	character.global_transform = marker.global_transform
	print(
		(
			"MOUNT %s/%s at=%s facing=%s"
			% [piece.name, mount, marker.global_position, marker.global_basis.z]
		)
	)
	var player := _player(character)
	if player == null:
		_invalid("%s has no AnimationPlayer" % path.get_file())
		return null
	for clip_name in CLIPS:
		if not player.has_animation(clip_name):
			_invalid("%s has no %s clip" % [path.get_file(), clip_name])
			return null
	_pose(character, clip, t)
	return character


## The posed character's bone positions in world space: in-frame landmarks that follow
## the drawn pose (a skinned mesh's AABB is its rest pose).
func _landmarks(character: Node) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for skel in character.find_children("*", "Skeleton3D", true, false):
		var s := skel as Skeleton3D
		for i in s.get_bone_count():
			out.append(s.global_transform * s.get_bone_global_pose(i).origin)
	return out


## The character's landmarks are in frame, and at least half of them are not hidden by
## the kit pieces (the only colliders) from the camera.
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
		_invalid("%s: character hidden by furniture (%d of %d)" % [label, clear, points.size()])
	return ok


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


## Six orthographic views of one piece beside a 1 m cube, as a 3 x 2 sheet.
func _plate_six_axis(piece: String, sheet: Image) -> void:
	_beat("six_axis_" + piece)
	var studio := _studio()
	var subject := _spawn(KIT % piece, studio, Vector3.ZERO)
	var box := _aabb_of(subject)
	var cube := _cube(studio, Vector3(box.end.x + 1.0, 0.5, box.end.z + 1.0))
	var whole := box.merge(_aabb_of(cube))
	print(
		(
			"MEASURE %s size_m=(%.3f, %.3f, %.3f) min=%s"
			% [piece, box.size.x, box.size.y, box.size.z, box.position]
		)
	)
	_add_colliders(studio)
	await physics_frame
	await physics_frame
	var cam := _ortho_cam(studio)
	var slot := 0
	for view in SIX_AXIS:
		var dir: Vector3 = SIX_AXIS[view]
		var up := Vector3.FORWARD if absf(dir.y) > 0.5 else Vector3.UP
		cam.look_at_from_position(whole.get_center() + dir * 200.0, whole.get_center(), up)
		cam.size = _ortho_size(cam, whole)
		var tag := "%s_%s" % [piece, view]
		await _frames(3)
		if _prove_in_frame(cam, tag, _corners(whole)) and _prove_visible(cam, tag, subject):
			var img := await _grab()
			_save(img, "six_axis_%s.png" % tag)
			_blit(sheet, img, slot, Vector2i(640, 360))
		slot += 1
	studio.queue_free()
	await _frames(2)


## Both characters at one table from its Mount_SitRoot nodes, side-on from the front
## (Godot +Z) at true scale, through sitting down, the seated idle and standing up.
func _plate_seated_fit(piece: String) -> void:
	_beat("seated_fit_" + piece)
	var studio := _studio()
	var table := _spawn(KIT % piece, studio, Vector3.ZERO)
	table.name = piece
	_add_colliders(table)
	var male := _at_mount(MALE, studio, table, "Mount_SitRoot_L", "sit_idle", 0.0)
	var female := _at_mount(FEMALE, studio, table, "Mount_SitRoot_R", "sit_idle", 0.0)
	if male == null or female == null:
		studio.queue_free()
		return
	await physics_frame
	await physics_frame
	var down := _player(male).get_animation("sit_down").length
	var up := _player(male).get_animation("stand_up").length
	var idle := _player(male).get_animation("sit_idle").length
	var steps := [
		["sit_down", 0.0],
		["sit_down", down * 0.25],
		["sit_down", down * 0.5],
		["sit_down", down * 0.75],
		["sit_down", down],
		["sit_idle", idle * 0.5],
		["stand_up", up * 0.33],
		["stand_up", up * 0.66],
		["stand_up", up],
	]
	var cam := _ortho_cam(studio)
	var box := _aabb_of(table)
	var frame_box := AABB(
		Vector3(box.position.x - 0.2, 0.0, -0.5), Vector3(box.size.x + 0.4, 2.0, 1.0)
	)
	cam.look_at_from_position(Vector3(0, 1.0, 200), Vector3(0, 1.0, 0), Vector3.UP)
	cam.size = _ortho_size(cam, frame_box)
	var sheet := Image.create(1920, 1080, false, Image.FORMAT_RGBA8)
	for i in steps.size():
		for character in [male, female]:
			_pose(character, steps[i][0], steps[i][1])
		var tag := "seated_fit_%s_%s_%.2f" % [piece, steps[i][0], steps[i][1]]
		await _frames(3)
		var ok := _prove_visible(cam, tag, table)
		ok = _prove_character(cam, tag + "/male", male) and ok
		ok = _prove_character(cam, tag + "/female", female) and ok
		if ok:
			var img := await _grab()
			if steps[i][0] == "sit_idle":
				_save(img, "seated_fit_%s_front.png" % piece)
			_blit(sheet, img, i, Vector2i(640, 360))
	_save(sheet, "seated_fit_%s_strip.png" % piece)
	# A perspective three-quarter view of the seated idle.
	for character in [male, female]:
		_pose(character, "sit_idle", idle * 0.5)
	var persp := Camera3D.new()
	studio.add_child(persp)
	persp.make_current()
	persp.look_at_from_position(Vector3(1.9, 1.8, 2.5), Vector3(0, 0.6, 0), Vector3.UP)
	await _frames(3)
	var tag34 := "seated_fit_%s_34" % piece
	var ok34 := _prove_in_frame(persp, tag34, _corners(_aabb_of(table)))
	ok34 = _prove_visible(persp, tag34, table) and ok34
	ok34 = _prove_character(persp, tag34 + "/male", male) and ok34
	ok34 = _prove_character(persp, tag34 + "/female", female) and ok34
	if ok34:
		_save(await _grab(), tag34 + ".png")
	studio.queue_free()
	await _frames(2)


func _kit(piece: String, parent: Node, pos: Vector3, yaw_deg := 0.0) -> Node3D:
	var node := _spawn(KIT % piece, parent, pos, yaw_deg)
	node.name = "%s_%d" % [piece, parent.get_child_count()]
	return node


## A wall piece on a cell edge: `cell` is the cell, `side` 0 north, 3 west.
func _edge(piece: String, parent: Node, cell: Vector2i, side: int) -> Node3D:
	var step := Vector2(0, -1) if side == 0 else Vector2(-1, 0)
	var at := ROOM_NW + Vector3(cell.x + 0.5 + step.x * 0.5, 0, cell.y + 0.5 + step.y * 0.5)
	return _kit(piece, parent, at, 90.0 if step.x != 0 else 0.0)


## Footprint centre of an object anchored at `anchor` with `size` cells, facing 0.
func _object(piece: String, parent: Node, anchor: Vector2i, size: Vector2i) -> Node3D:
	var centre := ROOM_NW + Vector3(anchor.x + size.x / 2.0, 0, anchor.y + size.y / 2.0)
	return _kit(piece, parent, centre)


## A 7 x 5 cafe corner: walls on the north and west edges, the counter one row in from
## the north wall (the staff row), one table with two sitters and one empty table.
func _build_corner(site: Node3D) -> Dictionary:
	var room := Node3D.new()
	room.name = "Corner"
	site.add_child(room)
	for y in 5:
		for x in 7:
			_kit("floor_tile", room, ROOM_NW + Vector3(x + 0.5, 0, y + 0.5))
	for x in 7:
		_edge("wall", room, Vector2i(x, 0), 0)
	for y in 5:
		_edge("wall", room, Vector2i(0, y), 3)
	for corner in [Vector2i(0, 0), Vector2i(7, 0), Vector2i(0, 5)]:
		_kit("wall_post", room, ROOM_NW + Vector3(corner.x, 0, corner.y))
	var s := {}
	s["counter"] = _object("cafe_counter", room, Vector2i(1, 1), Vector2i(2, 1))
	s["table"] = _object("cafe_table", room, Vector2i(3, 3), Vector2i(3, 1))
	s["table_empty"] = _object("cafe_table", room, Vector2i(4, 1), Vector2i(3, 1))
	s["room"] = room
	return s


func _plate_corner() -> void:
	_beat("corner")
	var site := _studio(true)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(700, 700)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.36, 0.5, 0.3)
	ground_mat.roughness = 1.0
	ground.material_override = ground_mat
	ground.position.y = -0.05
	site.add_child(ground)
	var s := _build_corner(site)
	s["cube"] = _cube(site, ROOM_NW + Vector3(7.5, 0.5, 4.5))
	_add_colliders(site)
	var counter: Node3D = s["counter"]
	var table: Node3D = s["table"]
	s["staff"] = _at_mount(MALE, site, counter, "Mount_Staff", "idle", 0.0)
	s["customer"] = _at_mount(FEMALE, site, counter, "Mount_Order", "idle", 0.5)
	s["sitter_l"] = _at_mount(FEMALE, site, table, "Mount_SitRoot_L", "sit_idle", 0.0)
	s["sitter_r"] = _at_mount(MALE, site, table, "Mount_SitRoot_R", "sit_idle", 1.0)
	var people := ["staff", "customer", "sitter_l", "sitter_r"]
	for key in people:
		if s[key] == null:
			site.queue_free()
			return
	var rig: Node3D = load(CAMERA).instantiate()
	site.add_child(rig)
	await _frames(20)
	await physics_frame
	await physics_frame
	var cam: Camera3D = rig.get_node("Camera3D")
	cam.make_current()
	var focus := ROOM_NW + Vector3(3.5, 0, 2.5)
	var kit := ["counter", "table", "table_empty"]
	var shots := [
		["corner_close_yaw0", 14.0, 0.0, kit + people + ["cube"]],
		# At this heading the counter hides the staff member's legs (18 of 38 bones).
		["corner_close_yaw46", 14.0, 0.8, kit + ["customer", "sitter_l", "sitter_r"]],
		["corner_near_yaw0", 7.0, 0.0, ["counter", "table", "customer", "sitter_l"]],
		["corner_mid_yaw0", 30.0, 0.0, kit + people + ["room"]],
		["corner_distance_yaw0", 60.0, 0.0, kit + ["room"]],
	]
	for shot in shots:
		rig.position = focus
		rig.distance = shot[1]
		rig.yaw = shot[2]
		rig.zoom(1.0)
		await _frames(4)
		print(
			(
				"CAMERA %s pos=%s yaw=%.2f distance=%.1f"
				% [shot[0], cam.global_position, shot[2], shot[1]]
			)
		)
		var ok := true
		for key in shot[3]:
			var tag := "%s/%s" % [shot[0], key]
			if key in people:
				ok = _prove_character(cam, tag, s[key]) and ok
			else:
				ok = _prove_in_frame(cam, tag, _corners(_aabb_of(s[key]))) and ok
				ok = _prove_visible(cam, tag, s[key]) and ok
		if ok:
			_save(await _grab(), shot[0] + ".png")
	site.queue_free()
	await _frames(2)
