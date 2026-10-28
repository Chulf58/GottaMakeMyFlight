extends SceneTree
## Windowed plate probe for the security lane parts as the build view draws
## them (Security 3/8; decisions proper-security-is-a-full-security-lane-tray-
## table-carry-on and security-lane-parts-are-placed-separately-tray-table-x-ray-b).
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/security_lane_plates_probe.gd
##
## Stages: six orthographic
## views at true scale beside a 1 m cube of each lane part, drawn by
## BuildView.make_object_node (so a placeholder box would show); then one whole
## lane (arch, tray table, X-ray belt, pickup table at the cells
## SecurityLanes.geometry names, facing 0, RIGHT) next to a basic scanner on a
## real BuildGrid, recognised COMPLETE, seen through the real TycoonCamera
## from three headings close up and at 30 m; then the build menu with the
## Lane tray open, each card holding its rendered thumbnail. Every plate
## proves each subject is in frame (projected bounds inside the viewport with
## a margin) and big enough; each subject must be seen (at least half of the
## camera rays aimed at its camera-facing opaque triangles hit it first, with
## every floor tile and object as an occluder) in a six-axis view, in at least
## one close lane shot and in the 30 m shot. Grey trays sit on the three tray
## mounts with a carry-on bag in the X-ray and pickup trays (props for Security
## 7/8, placed by this probe only), and the bag in the tunnel must clear the
## curtain strips and belt lips. Any failure prints PROBE_INVALID and exits 1. Plates go to
## tools/blender/out/security-lane/godot/.

const OUT_REL := "res://../tools/blender/out/security-lane/godot"
const CAMERA := "res://camera/tycoon_camera.tscn"
const GLASS := "res://assets/materials/tp_glass.tres"
const PARTS: Array[StringName] = [
	SecurityLanes.ARCH,
	SecurityLanes.TRAY_TABLE,
	SecurityLanes.XRAY_BELT,
	SecurityLanes.PICKUP_TABLE
]
const MARGIN_PX := 8.0
const STAGE_LIMIT_MS := 120000
const SIX_AXIS := {
	"front": Vector3(0, 0, 1),
	"back": Vector3(0, 0, -1),
	"left": Vector3(-1, 0, 0),
	"right": Vector3(1, 0, 0),
	"top": Vector3(0, 1, 0),
	"bottom": Vector3(0, -1, 0),
}
const GRID := Vector2i(12, 10)
const ARCH_CELL := Vector2i(6, 5)
const SCANNER_CELL := Vector2i(3, 4)

var _out_dir := ""
var _failed := false
var _stage := "init"
var _stage_started_ms := 0


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _stage_started_ms > STAGE_LIMIT_MS:
		print("PROBE_INVALID hang stage=%s" % _stage)
		quit(1)
	return false


func _beat(stage: String) -> void:
	_stage = stage
	_stage_started_ms = Time.get_ticks_msec()


func _run() -> void:
	_beat("start")
	for id in PARTS:
		var sheet := Image.create(1920, 720, false, Image.FORMAT_RGBA8)
		await _plate_six_axis(id, sheet)
		_save(sheet, "six_axis_%s_sheet.png" % id)
	await _plate_lane()
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


func _add_colliders(node: Node) -> void:
	for mi in _meshes(node):
		if mi.find_children("*", "StaticBody3D", false, false).size() > 0:
			continue
		var faces := _opaque_faces(mi.mesh)
		if not faces.is_empty():
			mi.add_child(_body(faces))


## Static bodies for every floor tile the view's multimeshes draw, read back
## from the renderer, plus a body per object mesh.
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


## [rays that hit the subject first, rays cast]. Godot front faces wind
## clockwise, so a triangle faces the camera when its (b - a) x (c - a) normal
## points away from it.
func _ray_hits(cam: Camera3D, subject: Node3D) -> Array:
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
	return [hits, targets.size()]


## Prints the ray count and whether at least half hit the subject first.
func _seen(cam: Camera3D, label: String, subject: Node3D) -> bool:
	var counted := _ray_hits(cam, subject)
	var ok: bool = counted[0] * 2 >= counted[1] and counted[0] > 0
	print("VISIBLE %s ray_hits=%d/%d seen=%s" % [label, counted[0], counted[1], ok])
	return ok


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
	# The main scene's sun (main.tscn).
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
			"MEASURE %s scene=%s size_m=(%.3f, %.3f, %.3f) min=%s meshes=%d"
			% [
				id,
				subject.scene_file_path,
				box.size.x,
				box.size.y,
				box.size.z,
				box.position,
				_meshes(subject).size()
			]
		)
	)
	_report_materials(id, subject)
	_add_colliders(studio)
	await physics_frame
	await physics_frame
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.far = 1000.0
	studio.add_child(cam)
	cam.make_current()
	var slot := 0
	for view in SIX_AXIS:
		var dir: Vector3 = SIX_AXIS[view]
		var up := Vector3.FORWARD if absf(dir.y) > 0.5 else Vector3.UP
		cam.look_at_from_position(whole.get_center() + dir * 200.0, whole.get_center(), up)
		cam.size = _ortho_size(cam, whole)
		var tag := "%s_%s" % [id, view]
		await _frames(3)
		var ok := _prove_in_frame(cam, tag, _corners(whole))
		if not _seen(cam, tag, subject):
			_invalid("%s: occluded or not hit" % tag)
			ok = false
		if ok:
			var img := await _grab()
			_save(img, "six_axis_%s.png" % tag)
			_blit(sheet, img, slot, Vector2i(640, 360))
		slot += 1
	studio.queue_free()
	await _frames(2)


func _must(result: BuildResult, what: String) -> void:
	if not result.ok:
		_invalid("%s refused: %s" % [what, result.reason_text()])


## The lane and a basic scanner on a floored grid; returns subject tag -> node.
func _build_lane(mode: BuildMode) -> Dictionary:
	var grid := mode.grid
	var edits: Array[BuildEdit] = []
	for y in GRID.y:
		for x in GRID.x:
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(edits)
	var lane := SecurityLanes.geometry(ARCH_CELL, 0, SecurityLanes.RIGHT)
	_must(grid.apply(BuildEdit.place_object(SecurityLanes.ARCH, ARCH_CELL, 0)), "arch")
	for part in [SecurityLanes.TRAY_TABLE, SecurityLanes.XRAY_BELT, SecurityLanes.PICKUP_TABLE]:
		_must(grid.apply(BuildEdit.place_object(part, lane[part], 0)), str(part))
	_must(grid.apply(BuildEdit.place_object(&"security_scanner", SCANNER_CELL, 0)), "scanner")
	var lanes := SecurityLanes.new()
	lanes.rebuild(grid)
	var arch_id := grid.object_at(ARCH_CELL)
	print("LANE arch_id=%d status=%s parts=%s" % [arch_id, lanes.status_text(arch_id), lane])
	if lanes.status(arch_id) != SecurityLanes.Status.COMPLETE:
		_invalid("the lane is not recognised whole: %s" % lanes.status_text(arch_id))
	var view: BuildView = mode.get_node("BuildView")
	view.refresh(grid)
	var subjects := {}
	for child in view.get_children():
		if child.has_meta("record"):
			subjects[StringName(child.get_meta("record")["def"])] = child
	return subjects


## Grey trays on the three tray mounts and a carry-on bag in the X-ray and
## pickup trays, as Security 7/8 will show them.
func _place_props(site: Node3D, subjects: Dictionary) -> Dictionary:
	var props := {}
	var mounts := {
		SecurityLanes.TRAY_TABLE: "Mount_TrayIn",
		SecurityLanes.XRAY_BELT: "Mount_TrayScan",
		SecurityLanes.PICKUP_TABLE: "Mount_TrayOut",
	}
	for id in mounts:
		var mount := (subjects[id] as Node3D).find_child(mounts[id], true, false) as Node3D
		if mount == null:
			_invalid("%s has no %s" % [id, mounts[id]])
			continue
		var tray := InteriorKit.instantiate("security_tray")
		site.add_child(tray)
		tray.global_transform = mount.global_transform
		props["tray@%s" % id] = tray
		if id == SecurityLanes.TRAY_TABLE:
			continue
		var bag := InteriorKit.instantiate("carry_on_bag")
		site.add_child(bag)
		bag.global_transform = mount.global_transform.translated(Vector3(0, 0.012, 0))
		props["bag@%s" % id] = bag
	for key in props:
		_add_colliders(props[key])
	return props


## The loaded tray in the tunnel (tray and bag bounds, shrunk 2 mm so resting
## on the belt is not contact) must not touch the X-ray's exported geometry.
## Control: the same box raised 0.25 m must hit the tunnel ceiling and roof (the
## tray spans z +-0.298, just inside the curtain strips at +-0.300).
func _check_clearance(subjects: Dictionary, props: Dictionary) -> void:
	var xray: Node3D = subjects[SecurityLanes.XRAY_BELT]
	var tray: Node3D = props.get("tray@%s" % SecurityLanes.XRAY_BELT)
	var bag: Node3D = props.get("bag@%s" % SecurityLanes.XRAY_BELT)
	if tray == null or bag == null:
		_invalid("no loaded tray in the tunnel")
		return
	_add_colliders(xray)
	await physics_frame
	await physics_frame
	var load_box := _aabb_of(tray).merge(_aabb_of(bag)).grow(-0.002)
	var hits := _xray_hits(xray, load_box)
	var control := _xray_hits(xray, AABB(load_box.position + Vector3(0, 0.25, 0), load_box.size))
	print(
		(
			"CLEARANCE tunnel load=%s xray_contacts=%d control_raised_0.25_contacts=%d"
			% [load_box, hits, control]
		)
	)
	if hits > 0 or control == 0:
		_invalid("the loaded tray does not clear the X-ray tunnel (or the control missed)")


## Shape contacts between a box and the X-ray's own colliders.
func _xray_hits(xray: Node3D, box: AABB) -> int:
	var shape := BoxShape3D.new()
	shape.size = box.size
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, box.get_center())
	var count := 0
	for hit in xray.get_world_3d().direct_space_state.intersect_shape(query, 64):
		if xray.is_ancestor_of(hit.collider):
			count += 1
	return count


func _plate_lane() -> void:
	_beat("lane")
	var site := _studio(true)
	var mode := BuildMode.new()
	mode.grid_size = GRID
	mode.tool = BuildMode.Tool.NONE
	site.add_child(mode)
	var subjects := _build_lane(mode)
	print("LANE subjects=%s" % [subjects.keys()])
	if subjects.size() != 5:
		_invalid("view drew %d of 5 objects" % subjects.size())
	for id in subjects:
		var node: Node3D = subjects[id]
		print("DRAWN %s scene=%s meshes=%d" % [id, node.scene_file_path, _meshes(node).size()])
		if node.scene_file_path != InteriorKit.PIECE_PATH % id:
			_invalid("%s is not drawn with its kit piece" % id)
	var view: BuildView = mode.get_node("BuildView")
	var grid := mode.grid
	var props := _place_props(site, subjects)
	await _check_clearance(subjects, props)
	var cube := _cube(site, grid.cell_to_world(Vector2i(9, 7)) + Vector3(0, 0.5, 0))
	_add_colliders(cube)
	var rig: Node3D = load(CAMERA).instantiate()
	site.add_child(rig)
	var cam: Camera3D = rig.get_node("Camera3D")
	cam.make_current()
	var focus := grid.cell_to_world(ARCH_CELL) + Vector3(-0.5, 0, 0)
	var shots := [
		# [name, distance m, yaw, least screen size px per subject, close]
		["lane_close_yaw40", 9.0, 0.7, 60.0, true],
		["lane_close_yaw130", 9.0, 0.7 + PI / 2.0, 60.0, true],
		["lane_close_yaw220", 9.0, 0.7 + PI, 60.0, true],
		["lane_mid_30m", 30.0, 0.7, 12.0, false],
	]
	var seen := {}
	var sheet := Image.create(1920, 720, false, Image.FORMAT_RGBA8)
	var slot := 0
	for shot in shots:
		_beat(shot[0])
		rig.position = focus
		rig.distance = shot[1]
		rig.yaw = shot[2]
		rig.zoom(1.0)
		await _frames(8)
		print(
			(
				"CAMERA %s pos=%s yaw=%.2f distance=%.1f"
				% [shot[0], cam.global_position, shot[2], shot[1]]
			)
		)
		var occluders := _view_colliders(view, site)
		await physics_frame
		await physics_frame
		var ok := _prove_in_frame(cam, "%s/cube" % shot[0], _corners(_aabb_of(cube)))
		for key in subjects:
			var tag := "%s/%s" % [shot[0], key]
			var corners := _corners(_aabb_of(subjects[key]))
			ok = _prove_in_frame(cam, tag, corners) and ok
			ok = _prove_size(cam, tag, corners, shot[3]) and ok
			var was_seen := _seen(cam, tag, subjects[key])
			if was_seen and shot[4]:
				seen[key] = true
			# At range every object must be seen in the one shot.
			if not was_seen and not shot[4]:
				_invalid("%s: occluded at range" % tag)
				ok = false
		if shot[4]:
			for key in props:
				var corners := _corners(_aabb_of(props[key]))
				ok = _prove_in_frame(cam, "%s/%s" % [shot[0], key], corners) and ok
		occluders.free()
		for child in view.get_children():
			for body in child.find_children("*", "StaticBody3D", true, false):
				body.free()
		if ok:
			var img := await _grab()
			_save(img, shot[0] + ".png")
			_blit(sheet, img, slot, Vector2i(640, 360))
		slot += 1
	for key in subjects:
		print("SEEN_CLOSE %s=%s" % [key, seen.has(key)])
		if not seen.has(key):
			_invalid("%s is never seen in a close shot" % key)
	await _plate_menu(mode, rig, focus, sheet, slot)
	_save(sheet, "lane_contact_sheet.png")
	site.queue_free()
	await _frames(2)


## The build menu with the Arch tool picked, so the Lane tray is open: each
## lane card must hold its rendered thumbnail, not the placeholder tile.
func _plate_menu(mode: BuildMode, rig: Node3D, focus: Vector3, sheet: Image, slot: int) -> void:
	_beat("menu")
	rig.position = focus
	rig.distance = 12.0
	rig.yaw = 0.7
	rig.zoom(1.0)
	var menu := BuildMenu.new()
	menu.build_mode = mode
	root.add_child(menu)
	mode.set_tool(BuildMode.Tool.ARCH)
	await _frames(8)
	var ok := true
	for tool in BuildMenu.LANE_ITEMS:
		var card := menu.card(tool)
		var picture := card.find_children("*", "TextureRect", true, false)[0] as TextureRect
		var path: String = picture.texture.resource_path if picture.texture else "none"
		var want := BuildMenu.THUMBNAIL_DIR % BuildMenu.LANE_ITEMS[tool][1]
		var tiles := picture.find_children("*", "ColorRect", true, false).size()
		print(
			(
				"MENU card %s visible=%s thumbnail=%s placeholder_tiles=%d rect=%s"
				% [
					BuildMenu.LANE_ITEMS[tool][0],
					card.is_visible_in_tree(),
					path,
					tiles,
					card.get_global_rect()
				]
			)
		)
		ok = card.is_visible_in_tree() and path == want and tiles == 0 and ok
	var screen := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	var tray := menu.tray().get_global_rect()
	print("MENU tray=%s screen=%s tray_open=%s" % [tray, screen, menu.is_tray_open()])
	ok = ok and screen.encloses(tray) and menu.is_tray_open()
	if ok:
		var img := await _grab()
		_save(img, "menu_lane_tray.png")
		_blit(sheet, img, slot, Vector2i(640, 360))
	else:
		_invalid("menu: the Lane tray or a thumbnail is not shown")
	menu.queue_free()
	mode.set_tool(BuildMode.Tool.NONE)
	await _frames(2)
