extends SceneTree
## Windowed plate probe for the terminal interior kit.
##
## Run (one windowed Godot run project-wide; take the slot lock first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://assets/interior/interior_kit_plates_probe.gd
##
## Stages: six-axis orthographic plates beside a 1 m cube for every piece (a sheet each
## for the desk, scanner and seat row, one combined sheet for the rest); a scanner fit
## plate that measures a character's width against the arch; then a small room built
## from the kit beside tp_airport_01a with both characters, through the real
## TycoonCamera at pitch 55. Plates go to tools/blender/out/interior_kit/.
## Every plate proves each subject is in frame (projected bounds inside the viewport)
## and hit by camera rays against colliders built from its opaque surfaces only, or the
## probe prints PROBE_INVALID and exits 1.

const OUT_REL := "res://../tools/blender/out/interior_kit"
const KIT := "res://assets/interior/%s.glb"
const MALE := "res://assets/people/tcp_male_character_01.glb"
const FEMALE := "res://assets/people/tcp_female_character_01.glb"
const TERMINAL := "res://assets/buildings/tp_airport_01a.glb"
const CAMERA := "res://camera/tycoon_camera.tscn"
const GLASS := "res://assets/materials/tp_glass.tres"
const SHEET_PIECES := ["checkin_desk", "security_scanner", "seat_row"]
const OTHER_PIECES := [
	"floor_tile", "wall", "wall_post", "wall_glass", "wall_door", "kiosk", "info_screen"
]
const SCANNER_CLEAR_M := 0.70
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
## North-west corner of the room on the ground, in metres; the room is 8 x 6 cells.
const ROOM_NW := Vector3(-4, 0, -36)

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
			OS.crash("interior kit probe hung")


func _run() -> void:
	for piece in SHEET_PIECES:
		var sheet := Image.create(1920, 720, false, Image.FORMAT_RGBA8)
		await _plate_six_axis(piece, sheet, 0, Vector2i(640, 360), 3)
		_save(sheet, "six_axis_%s_sheet.png" % piece)
	var others := Image.create(1920, 180 * OTHER_PIECES.size(), false, Image.FORMAT_RGBA8)
	for i in OTHER_PIECES.size():
		await _plate_six_axis(OTHER_PIECES[i], others, i * 6, Vector2i(320, 180), 6)
	_save(others, "six_axis_other_pieces_sheet.png")
	await _plate_scanner_fit()
	await _plate_room()
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
## Supporting evidence only: the plate shows visibility.
func _prove_visible(cam: Camera3D, label: String, subject: Node3D) -> bool:
	var targets: Array[Vector3] = []
	var centre := _aabb_of(subject).get_center()
	for mi in _meshes(subject):
		var faces := _opaque_faces(mi)
		var facing: Array[Vector3] = []
		for i in range(0, faces.size() - 2, 3):
			var a: Vector3 = mi.global_transform * faces[i]
			var b: Vector3 = mi.global_transform * faces[i + 1]
			var c: Vector3 = mi.global_transform * faces[i + 2]
			var mid := (a + b + c) / 3.0
			var view := cam.global_position - mid
			if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
				view = cam.global_basis.z
			if (b - a).cross(c - a).dot(view) < 0.0:
				facing.append(mid)
		var step := maxi(1, floori(facing.size() / 12.0))
		for i in range(0, facing.size(), step):
			targets.append(facing[i].lerp(centre, 0.03))
	var space := cam.get_world_3d().direct_space_state
	var hits := 0
	for t in targets:
		var from := cam.global_position
		if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
			from = t + cam.global_basis.z * 500.0
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
	var player: AnimationPlayer = node.find_child("AnimationPlayer", true, false)
	if player != null:
		player.play("idle")
		player.seek(0.0, true)
		player.pause()
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


## Six orthographic views of one piece beside a 1 m cube, blitted into `sheet` from
## tile `first` in tiles of `tile` pixels, `columns` to a row.
func _plate_six_axis(piece: String, sheet: Image, first: int, tile: Vector2i, columns: int) -> void:
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
	var slot := first
	for view in SIX_AXIS:
		var dir: Vector3 = SIX_AXIS[view]
		var up := Vector3.FORWARD if absf(dir.y) > 0.5 else Vector3.UP
		cam.look_at_from_position(whole.get_center() + dir * 200.0, whole.get_center(), up)
		cam.size = _ortho_size(cam, whole)
		var tag := "%s_%s" % [piece, view]
		await _frames(3)
		if not _prove_in_frame(cam, tag, _corners(whole)) or not _prove_visible(cam, tag, subject):
			slot += 1
			continue
		var img := await _grab()
		if piece in SHEET_PIECES:
			_save(img, "six_axis_%s.png" % tag)
		img.resize(tile.x, tile.y, Image.INTERPOLATE_LANCZOS)
		var at := Vector2i((slot % columns) * tile.x, floori(slot / float(columns)) * tile.y)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, tile), at)
		slot += 1
	studio.queue_free()
	await _frames(2)


## The female character standing in the scanner arch, front orthographic. Her width is
## measured off a render with only her visible, at two idle moments and two headings.
func _plate_scanner_fit() -> void:
	_beat("scanner_fit")
	var studio := _studio()
	var scanner := _spawn(KIT % "security_scanner", studio, Vector3.ZERO)
	var female := _spawn(FEMALE, studio, Vector3.ZERO)
	var cam := _ortho_cam(studio)
	cam.look_at_from_position(Vector3(0, 1.2, 200), Vector3(0, 1.2, 0), Vector3.UP)
	cam.size = 3.0
	var px_per_m := root.get_visible_rect().size.y / cam.size
	var player: AnimationPlayer = female.find_child("AnimationPlayer", true, false)
	var length := player.get_animation("idle").length
	scanner.visible = false
	var widest := 0.0
	for heading in [0.0, 90.0]:
		female.rotation_degrees.y = heading
		for k in 2:
			player.seek(length * k / 2.0, true)
			var img := await _grab()
			var width := _silhouette_width_px(img) / px_per_m
			widest = maxf(widest, width) if heading == 0.0 else widest
			print(
				"MEASURE female heading=%d t=%.2f width_m=%.3f" % [heading, length * k / 2.0, width]
			)
	print("MEASURE scanner clear_m=%.2f female_front_width_m=%.3f" % [SCANNER_CLEAR_M, widest])
	female.visible = false
	var male := _spawn(MALE, studio, Vector3.ZERO)
	var male_player: AnimationPlayer = male.find_child("AnimationPlayer", true, false)
	var male_widest := 0.0
	for k in 2:
		male_player.seek(male_player.get_animation("idle").length * k / 2.0, true)
		male_widest = maxf(male_widest, _silhouette_width_px(await _grab()) / px_per_m)
	print("MEASURE scanner clear_m=%.2f male_front_width_m=%.3f" % [SCANNER_CLEAR_M, male_widest])
	male.queue_free()
	female.visible = true
	for width in [widest, male_widest]:
		if width < 0.3 or width >= SCANNER_CLEAR_M:
			_invalid(
				(
					"scanner fit: character width %.3f m against a %.2f m arch"
					% [width, SCANNER_CLEAR_M]
				)
			)
	female.rotation_degrees.y = 0.0
	player.seek(0.0, true)
	scanner.visible = true
	_add_colliders(studio)
	await physics_frame
	await physics_frame
	var points := _corners(_aabb_of(scanner))
	if _prove_in_frame(cam, "scanner_fit", points) and _prove_visible(cam, "scanner_fit", scanner):
		_save(await _grab(), "scanner_fit_front.png")
	studio.queue_free()
	await _frames(2)


## Pixel columns between the first and last non-background pixel, over the whole image.
func _silhouette_width_px(img: Image) -> float:
	var bg := img.get_pixel(2, 2)
	var lo := img.get_width()
	var hi := -1
	for y in range(0, img.get_height(), 2):
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b) > 0.06:
				lo = mini(lo, x)
				hi = maxi(hi, x)
	return maxf(0.0, hi - lo + 1)


func _kit(piece: String, parent: Node, pos: Vector3, yaw_deg := 0.0) -> Node3D:
	var node := _spawn(KIT % piece, parent, pos, yaw_deg)
	node.name = "%s_%d" % [piece, parent.get_child_count()]
	return node


## A wall piece on a cell edge: `cell` is the cell, `side` 0 north, 1 east, 2 south, 3 west.
func _edge(piece: String, parent: Node, cell: Vector2i, side: int) -> Node3D:
	var steps := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
	var step: Vector2 = steps[side]
	var at := ROOM_NW + Vector3(cell.x + 0.5 + step.x * 0.5, 0, cell.y + 0.5 + step.y * 0.5)
	return _kit(piece, parent, at, 90.0 if step.x != 0 else 0.0)


func _post(parent: Node, corner: Vector2i) -> Node3D:
	return _kit("wall_post", parent, ROOM_NW + Vector3(corner.x, 0, corner.y))


## Footprint centre of an object anchored at `anchor` with `size` cells, facing 0.
func _object(piece: String, parent: Node, anchor: Vector2i, size: Vector2i) -> Node3D:
	var centre := ROOM_NW + Vector3(anchor.x + size.x / 2.0, 0, anchor.y + size.y / 2.0)
	return _kit(piece, parent, centre)


func _build_room(site: Node3D) -> Dictionary:
	var room := Node3D.new()
	room.name = "Room"
	site.add_child(room)
	for y in 6:
		for x in 8:
			_kit("floor_tile", room, ROOM_NW + Vector3(x + 0.5, 0, y + 0.5))
	var subjects := {}
	for x in 8:
		_edge("wall", room, Vector2i(x, 0), 0)
		var south := "wall"
		if x == 1:
			south = "wall_door"
		elif x >= 3:
			south = "wall_glass"
		var piece := _edge(south, room, Vector2i(x, 5), 2)
		if x == 1:
			subjects["door"] = piece
		elif x == 5:
			subjects["glass"] = piece
	for y in 6:
		_edge("wall", room, Vector2i(0, y), 3)
		_edge("wall", room, Vector2i(7, y), 1)
	# An interior partition off the north wall: a T-junction and a free end.
	_edge("wall", room, Vector2i(5, 0), 3)
	_edge("wall", room, Vector2i(5, 1), 3)
	for corner in [
		Vector2i(0, 0),
		Vector2i(8, 0),
		Vector2i(0, 6),
		Vector2i(8, 6),
		Vector2i(3, 6),
		Vector2i(5, 0),
		Vector2i(5, 2)
	]:
		_post(room, corner)
	subjects["desk"] = _object("checkin_desk", room, Vector2i(1, 1), Vector2i(2, 1))
	subjects["scanner"] = _object("security_scanner", room, Vector2i(7, 2), Vector2i(1, 2))
	subjects["seats"] = _object("seat_row", room, Vector2i(2, 3), Vector2i(3, 1))
	subjects["kiosk"] = _object("kiosk", room, Vector2i(0, 4), Vector2i.ONE)
	subjects["screen"] = _object("info_screen", room, Vector2i(5, 4), Vector2i.ONE)
	# A free-standing cross junction east of the room.
	var cross := Node3D.new()
	cross.name = "CrossJunction"
	site.add_child(cross)
	_edge("wall", cross, Vector2i(10, 2), 0)
	_edge("wall", cross, Vector2i(11, 2), 0)
	_edge("wall", cross, Vector2i(11, 1), 3)
	_edge("wall", cross, Vector2i(11, 2), 3)
	_post(cross, Vector2i(11, 2))
	subjects["cross"] = cross
	subjects["room"] = room
	return subjects


func _plate_room() -> void:
	_beat("room")
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
	var terminal := _spawn(TERMINAL, site, Vector3(0, 0, -60), 180.0)
	terminal.name = "Terminal"
	var s := _build_room(site)
	# The male at the desk's passenger cell facing it; the female inside the scanner.
	s["male"] = _spawn(MALE, site, ROOM_NW + Vector3(1.5, 0, 2.5), 180.0)
	s["female"] = _spawn(FEMALE, site, ROOM_NW + Vector3(7.5, 0, 3.0), 180.0)
	s["cube"] = _cube(site, ROOM_NW + Vector3(-1.5, 0.5, 5.5))
	var rig: Node3D = load(CAMERA).instantiate()
	site.add_child(rig)
	await _frames(20)
	_add_colliders(site)
	await physics_frame
	await physics_frame
	var cam: Camera3D = rig.get_node("Camera3D")
	cam.make_current()
	var focus := ROOM_NW + Vector3(4, 0, 3)
	var all_kit := ["desk", "scanner", "seats", "kiosk", "screen", "door", "glass"]
	var shots := [
		["room_close_yaw0", 20.0, 0.0, all_kit + ["male", "female", "cube"]],
		["room_close_yaw46", 20.0, 0.8, all_kit + ["male"]],
		["room_near_yaw0", 12.0, 0.0, ["desk", "seats", "screen", "male"]],
		["room_distance_yaw0", 60.0, 0.0, all_kit + ["room", "cross"]],
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
			ok = _prove_in_frame(cam, tag, _corners(_aabb_of(s[key]))) and ok
			ok = _prove_visible(cam, tag, s[key]) and ok
		var term_tag := "%s/terminal_centre" % shot[0]
		var term_centre: Array[Vector3] = [_aabb_of(terminal).get_center()]
		if shot[1] >= 60.0:
			ok = _prove_in_frame(cam, term_tag, term_centre) and ok
		if ok:
			_save(await _grab(), shot[0] + ".png")
	site.queue_free()
	await _frames(2)
