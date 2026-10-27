extends SceneTree
## Windowed plate probe for the baggage pieces as the build view draws them
## (decision baggage-rides-a-player-built-belt-from-check-in-to-a-bag-roo).
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/baggage_kit_plates_probe.gd
##
## Stages: six-axis orthographic plates at true scale beside a 1 m cube of each
## baggage piece and the check-in desk, each drawn by BuildView.make_object_node
## (so a placeholder box would show); then a chain placed through BuildMode on a
## real BuildGrid: check-in desk, feed behind it, three straight belts, a corner
## and a belt end inside a walled 4 x 4 bag room with a cart, seen through the
## real TycoonCamera at two headings close up, at 30 m and at 80 m, plus a close
## shot of the desk-to-feed join. Every plate proves each subject is in frame
## (projected bounds inside the viewport with a margin) and that at least half
## of the camera rays aimed at its camera-facing opaque triangles hit it first,
## with every wall, post, floor tile and object as an occluder; otherwise it
## prints PROBE_INVALID and exits 1. Plates go to tools/blender/out/baggage-kit/.

const OUT_REL := "res://../tools/blender/out/baggage-kit"
const CAMERA := "res://camera/tycoon_camera.tscn"
const GLASS := "res://assets/materials/tp_glass.tres"
const PIECES: Array[StringName] = [
	&"baggage_belt",
	&"baggage_belt_corner",
	&"baggage_belt_feed",
	&"baggage_belt_end",
	&"baggage_cart",
	&"checkin_desk",
]
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 90000
## No stage (one piece's six views, one chain shot) takes this long when it works.
const STAGE_LIMIT_MS := 120000
const SIX_AXIS := {
	"front": Vector3(0, 0, 1),
	"back": Vector3(0, 0, -1),
	"left": Vector3(-1, 0, 0),
	"right": Vector3(1, 0, 0),
	"top": Vector3(0, 1, 0),
	"bottom": Vector3(0, -1, 0),
}
const GRID := Vector2i(16, 12)
## The bag room's cells: x 10..13, y 2..5. Its south side is open at x 10 (the
## belt comes in) and x 11 (the way in).
const ROOM := Rect2i(10, 2, 4, 4)
const ROOM_GAPS := [10, 11]
## [def, anchor, facing]: the chain of test_baggage_pieces, moved to this grid.
const CHAIN := [
	[&"checkin_desk", Vector2i(5, 8), 0],
	[&"baggage_belt_feed", Vector2i(6, 7), 0],
	[&"baggage_belt", Vector2i(7, 7), 1],
	[&"baggage_belt", Vector2i(8, 7), 1],
	[&"baggage_belt", Vector2i(9, 7), 1],
	[&"baggage_belt_corner", Vector2i(10, 7), 2],
	[&"baggage_belt", Vector2i(10, 6), 0],
	[&"baggage_belt_end", Vector2i(10, 5), 0],
	[&"baggage_cart", Vector2i(12, 3), 0],
]

var _out_dir := ""
var _failed := false
var _stage := "init"
var _heartbeat_ms := 0
var _stage_started_ms := 0
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
	if stage != _stage:
		_stage_started_ms = Time.get_ticks_msec()
	_stage = stage
	_heartbeat_ms = Time.get_ticks_msec()
	_guard_mutex.unlock()


## Guard thread: a frozen main thread never reaches _process, and a stage stuck
## on a signal that never comes keeps beating, so check both from here.
func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_guard_mutex.lock()
		var stop := _guard_stop
		var now := Time.get_ticks_msec()
		var idle_ms := now - _heartbeat_ms
		var stage_ms := now - _stage_started_ms
		var stage := _stage
		_guard_mutex.unlock()
		if stop:
			return
		if idle_ms > HANG_LIMIT_MS or stage_ms > STAGE_LIMIT_MS:
			print(
				(
					"PROBE_INVALID hang stage=%s no heartbeat for %d ms, in stage for %d ms"
					% [stage, idle_ms, stage_ms]
				)
			)
			OS.crash("baggage kit probe hung")


func _run() -> void:
	# `-- --layout-only` builds the chain and checks its joins and room, with no
	# plates, so the layout can be checked headless.
	if OS.get_cmdline_user_args().has("--layout-only"):
		var site := Node3D.new()
		root.add_child(site)
		var mode := BuildMode.new()
		mode.grid_size = GRID
		mode.tool = BuildMode.Tool.NONE
		site.add_child(mode)
		var subjects := _build_chain(mode)
		print("CHAIN subjects=%s" % [subjects.keys()])
		if subjects.size() != CHAIN.size():
			_invalid("view drew %d of %d chain objects" % [subjects.size(), CHAIN.size()])
		for id in PIECES:
			var node := BuildView.make_object_node(BuildCatalog.get_def(id), null)
			_report_materials(id, node)
			node.free()
		site.free()
		_finish()
		return
	for id in PIECES:
		var sheet := Image.create(1920, 720, false, Image.FORMAT_RGBA8)
		await _plate_six_axis(id, sheet)
		_save(sheet, "six_axis_%s_sheet.png" % id)
	await _plate_chain()
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


## Local triangles of a mesh's opaque surfaces (glass is left out).
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
		var faces := _opaque_faces(mi.mesh)
		if not faces.is_empty():
			mi.add_child(_body(faces))


## Static bodies for every instance the view's multimeshes draw (walls, posts,
## floor tiles), read back from the renderer, plus a body per object mesh.
func _view_colliders(view: BuildView, site: Node3D) -> Node3D:
	var holder := Node3D.new()
	holder.name = "ViewColliders"
	site.add_child(holder)
	for child in view.get_children():
		if child is MultiMeshInstance3D:
			var multimesh := (child as MultiMeshInstance3D).multimesh
			var local_faces := _opaque_faces(multimesh.mesh)
			if local_faces.is_empty():
				continue
			for i in multimesh.instance_count:
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
			"INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) size_px=(%.0f,%.0f) ok=%s"
			% [label, lo.x, lo.y, hi.x, hi.y, hi.x - lo.x, hi.y - lo.y, ok]
		)
	)
	if not ok:
		_invalid("%s: projected bounds leave the viewport" % label)
	return ok


## The subject's projected bounds are at least `min_px` on their longer side,
## so a plate cannot pass on a subject too small to judge.
func _prove_size(cam: Camera3D, label: String, points: Array[Vector3], min_px: float) -> bool:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		var s := cam.unproject_position(p)
		lo = lo.min(s)
		hi = hi.max(s)
	var size := maxf(hi.x - lo.x, hi.y - lo.y)
	var ok := size >= min_px
	print("SIZE %s longest_px=%.1f min_px=%.1f ok=%s" % [label, size, min_px, ok])
	if not ok:
		_invalid("%s: %.1f px is under the %.1f px floor" % [label, size, min_px])
	return ok


## Rays from the camera to points on the subject's opaque, camera-facing triangles;
## at least half must hit the subject first. Godot front faces wind clockwise, so a
## triangle faces the camera when its (b - a) x (c - a) normal points away from it.
func _prove_visible(cam: Camera3D, label: String, subject: Node3D) -> bool:
	var targets: Array[Vector3] = []
	var ortho := cam.projection == Camera3D.PROJECTION_ORTHOGONAL
	for mi in _meshes(subject):
		var faces := _opaque_faces(mi.mesh)
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


## The shader and outline of each surface: the toon look the importer binds.
func _report_materials(id: StringName, node: Node3D) -> void:
	var shaders := {}
	for mi in _meshes(node):
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			var shader := "none"
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null:
				shader = (mat as ShaderMaterial).shader.resource_path
			elif mat != null:
				shader = mat.get_class()
			var outline := "none"
			if mat != null and mat.next_pass is ShaderMaterial:
				outline = ((mat.next_pass as ShaderMaterial).shader as Shader).resource_path
			shaders["%s|%s" % [shader, outline]] = true
	print("TOON %s surfaces shader|outline=%s" % [id, shaders.keys()])
	if shaders.has("none|none"):
		_invalid("%s has a surface with no material" % id)


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


## Six orthographic views of one piece, as BuildView draws it, beside a 1 m cube.
func _plate_six_axis(id: StringName, sheet: Image) -> void:
	_beat("six_axis_" + id)
	var studio := _studio()
	var subject := BuildView.make_object_node(BuildCatalog.get_def(id), null)
	studio.add_child(subject)
	var box := _aabb_of(subject)
	var cube := _cube(studio, Vector3(box.end.x + 1.0, 0.5, box.end.z + 1.0))
	var whole := box.merge(_aabb_of(cube))
	print(
		(
			"MEASURE %s size_m=(%.3f, %.3f, %.3f) min=%s meshes=%d"
			% [id, box.size.x, box.size.y, box.size.z, box.position, _meshes(subject).size()]
		)
	)
	_report_materials(id, subject)
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
		var tag := "%s_%s" % [id, view]
		await _frames(3)
		if _prove_in_frame(cam, tag, _corners(whole)) and _prove_visible(cam, tag, subject):
			var img := await _grab()
			_save(img, "six_axis_%s.png" % tag)
			_blit(sheet, img, slot, Vector2i(640, 360))
		slot += 1
	studio.queue_free()
	await _frames(2)


func _must(result: BuildResult, what: String) -> void:
	if not result.ok:
		_invalid("%s refused: %s" % [what, result.reason_text()])


## The chain and the bag room on a floored grid; returns subject tag -> node.
func _build_chain(mode: BuildMode) -> Dictionary:
	var grid := mode.grid
	for y in GRID.y:
		for x in GRID.x:
			_must(
				grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1)), "floor"
			)
	for x in range(ROOM.position.x, ROOM.end.x):
		_must(
			grid.apply(BuildEdit.place_wall(Vector2i(x, ROOM.position.y), BuildGrid.Side.NORTH)),
			"wall"
		)
		if not ROOM_GAPS.has(x):
			var south := Vector2i(x, ROOM.end.y - 1)
			_must(grid.apply(BuildEdit.place_wall(south, BuildGrid.Side.SOUTH)), "wall")
	for y in range(ROOM.position.y, ROOM.end.y):
		_must(
			grid.apply(BuildEdit.place_wall(Vector2i(ROOM.position.x, y), BuildGrid.Side.WEST)),
			"wall"
		)
		_must(
			grid.apply(BuildEdit.place_wall(Vector2i(ROOM.end.x - 1, y), BuildGrid.Side.EAST)),
			"wall"
		)
	_must(grid.apply(BuildEdit.place_room(ROOM, &"bag_room")), "bag room")
	var ids := {}
	for entry in CHAIN:
		var result := grid.apply(BuildEdit.place_object(entry[0], entry[1], entry[2]))
		_must(result, "%s at %s" % [entry[0], entry[1]])
		ids[result.object_id] = "%s@%d,%d" % [entry[0], entry[1].x, entry[1].y]
	# Each neighbouring pair of the line (desk to end) joins port to port.
	var line: Array = ids.keys().slice(0, 8)
	for i in line.size() - 1:
		var joined := false
		for mine in _ports(grid, line[i]):
			for theirs in _ports(grid, line[i + 1]):
				joined = joined or BuildCatalog.belt_ports_join(mine, theirs)
		print("JOIN %s -> %s joined=%s" % [ids[line[i]], ids[line[i + 1]], joined])
		if not joined:
			_invalid("chain breaks between %s and %s" % [ids[line[i]], ids[line[i + 1]]])
	var room_id := grid.room_at(Vector2i(11, 3))
	var status := RoomRules.status(grid, room_id)
	print("ROOM bag_room id=%d headline=%s" % [room_id, status.headline()])
	if room_id == 0 or status.headline() != "Ready":
		_invalid("the bag room is not ready: %s" % status.headline())
	var view: BuildView = mode.get_node("BuildView")
	view.refresh(grid)
	var subjects := {}
	for child in view.get_children():
		if child.has_meta("record"):
			var record: Dictionary = child.get_meta("record")
			var anchor: Vector2i = record["anchor"]
			subjects["%s@%d,%d" % [record["def"], anchor.x, anchor.y]] = child
	return subjects


func _ports(grid: BuildGrid, object_id: int) -> Array[Dictionary]:
	var record := grid.get_object(object_id)
	return BuildCatalog.belt_ports(record["def"], record["anchor"], record["facing"])


func _plate_chain() -> void:
	_beat("chain")
	var site := _studio(true)
	var mode := BuildMode.new()
	mode.grid_size = GRID
	mode.tool = BuildMode.Tool.NONE
	site.add_child(mode)
	var subjects := _build_chain(mode)
	print("CHAIN subjects=%s" % [subjects.keys()])
	if subjects.size() != CHAIN.size():
		_invalid("view drew %d of %d chain objects" % [subjects.size(), CHAIN.size()])
	var view: BuildView = mode.get_node("BuildView")
	var cube := _cube(site, mode.grid.cell_to_world(Vector2i(8, 9)) + Vector3(0, 0.5, 0))
	# The cube can hide a piece too.
	_add_colliders(cube)
	var rig: Node3D = load(CAMERA).instantiate()
	site.add_child(rig)
	var cam: Camera3D = rig.get_node("Camera3D")
	cam.make_current()
	var focus := mode.grid.cell_to_world(Vector2i(9, 5))
	var join := mode.grid.cell_to_world(Vector2i(6, 7)) + Vector3(0, 0, 0.5)
	var everything: Array = subjects.keys()
	var shots := [
		# [name, focus, distance m, yaw, subjects, least screen size px per subject]
		["chain_close_yaw40", focus, 16.0, 0.7, everything, 20.0],
		["chain_close_yaw220", focus, 16.0, 0.7 + PI, everything, 20.0],
		["chain_join_close", join, 5.0, 0.7, ["checkin_desk@5,8", "baggage_belt_feed@6,7"], 60.0],
		["chain_mid_30m", focus, 30.0, 0.7, everything, 8.0],
		["chain_distance_80m", focus, 80.0, 0.7, everything, 3.0],
	]
	var sheet := Image.create(1920, 720, false, Image.FORMAT_RGBA8)
	var slot := 0
	for shot in shots:
		_beat(shot[0])
		rig.position = shot[1]
		rig.distance = shot[2]
		rig.yaw = shot[3]
		rig.zoom(1.0)
		await _frames(8)
		print(
			(
				"CAMERA %s pos=%s yaw=%.2f distance=%.1f cut_edges=%d"
				% [shot[0], cam.global_position, shot[3], shot[2], view.cut_edges().size()]
			)
		)
		var occluders := _view_colliders(view, site)
		await physics_frame
		await physics_frame
		var ok := true
		for key in shot[4]:
			var tag := "%s/%s" % [shot[0], key]
			var corners := _corners(_aabb_of(subjects[key]))
			ok = _prove_in_frame(cam, tag, corners) and ok
			ok = _prove_size(cam, tag, corners, shot[5]) and ok
			ok = _prove_visible(cam, tag, subjects[key]) and ok
		if shot[0] == "chain_close_yaw40":
			ok = _prove_in_frame(cam, "chain_close_yaw40/cube", _corners(_aabb_of(cube))) and ok
		occluders.free()
		for child in view.get_children():
			for body in child.find_children("*", "StaticBody3D", true, false):
				body.free()
		if ok:
			var img := await _grab()
			_save(img, shot[0] + ".png")
			_blit(sheet, img, slot, Vector2i(640, 360))
		slot += 1
	_save(sheet, "chain_contact_sheet.png")
	site.queue_free()
	await _frames(2)
