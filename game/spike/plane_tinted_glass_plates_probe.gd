extends SceneTree
## Windowed Vulkan plate probe for dark-tinted plane glass (ruling c46a5df8):
## renders close-up cockpit/cabin plates of all 5 planes (demo 03a, 04a, 05a
## plus 06a, 07a) via PlaneView plus a control plate showing PlaneView's tinted
## 05a beside transparent terminal wall_glass.glb.
##
## Run (one windowed Godot run project-wide; take the slot lock first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/plane_tinted_glass_plates_probe.gd

const DEFAULT_OUT_REL := "res://../tools/blender/out/plane_tinted_glass"
const MAIN_SCENE := "res://main/main.tscn"
const WALL_GLASS := "res://assets/interior/wall_glass.glb"
const APRON_POS := Vector3(21.5, 0.2, -135.0)
const WINDOW := Vector2i(1600, 900)
const MARGIN_PX := 8.0
const HANG_MS := 60000

const SHOTS := [
	{
		"file": "cockpit_03a.png",
		"model": "tp_plane_03a",
		"focus": Vector3(0.0, 1.35, 0.4),
		"cam_offset": Vector3(8.0, 3.0, 8.0),
		"cube_offset": Vector3(2.8, 0.5, 1.4),
	},
	{
		"file": "cockpit_04a.png",
		"model": "tp_plane_04a",
		"focus": Vector3(0.0, 1.9, 1.8),
		"cam_offset": Vector3(11.5, 3.8, 10.5),
		"cube_offset": Vector3(3.4, 0.5, 5.2),
	},
	{
		"file": "cockpit_05a.png",
		"model": "tp_plane_05a",
		"focus": Vector3(0.0, 2.0, 6.2),
		"cam_offset": Vector3(9.5, 3.4, 9.8),
		"cube_offset": Vector3(4.6, 0.5, 8.5),
	},
	{
		"file": "cockpit_06a.png",
		"model": "tp_plane_06a",
		"focus": Vector3(0.0, 2.5, 10.5),
		"cam_offset": Vector3(18.0, 5.2, 17.5),
		"cube_offset": Vector3(4.2, 0.5, 14.0),
	},
	{
		"file": "cockpit_07a.png",
		"model": "tp_plane_07a",
		"focus": Vector3(0.0, 3.0, 11.5),
		"cam_offset": Vector3(23.5, 6.4, 21.5),
		"cube_offset": Vector3(5.0, 0.5, 16.5),
	},
]

var _out_dir := ""
var _failed := false
var _main: Node3D
var _cam: Camera3D
var _view: PlaneView
var _stage := "boot"
var _beat_ms := 0
var _stop := false
var _lock := Mutex.new()
var _guard := Thread.new()
var _plates: Array[String] = []


func _initialize() -> void:
	var env_dir := OS.get_environment("PROBE_OUT_DIR").strip_edges()
	_out_dir = (
		env_dir
		if not env_dir.is_empty()
		else ProjectSettings.globalize_path(DEFAULT_OUT_REL).simplify_path()
	)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	DisplayServer.window_set_size(WINDOW)
	root.size = WINDOW
	_beat("boot")
	_guard.start(_watch)
	_run.call_deferred()


func _run() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(_main)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	for existing in _main.find_children("*", "PlaneView", true, false):
		(existing as PlaneView).set_process(false)
		(existing as PlaneView).visible = false

	_view = PlaneView.new()
	_view.name = "ProbePlaneView"
	_view.position = APRON_POS
	_main.add_child(_view)
	_view.set_process(false)
	_view.visible = true

	_cam = Camera3D.new()
	_cam.fov = 38.0
	_main.add_child(_cam)
	_cam.make_current()

	await _frames(8)
	for spec: Dictionary in SHOTS:
		await _shoot_cockpit(spec)
	await _shoot_control_wall_glass()
	_contact_sheet()
	print("PROBE done plates=%d failed=%s" % [_plates.size(), _failed])
	_finish()
	quit(1 if _failed else 0)


func _shoot_cockpit(spec: Dictionary) -> void:
	var model_name: String = spec["model"]
	_stage = model_name
	_view.show_model(model_name)
	var inst := _view.get_node("Pivot").get_child(0) as Node3D
	var colliders := _build_colliders(inst)
	var cube := _cube(APRON_POS + (spec["cube_offset"] as Vector3))
	await _frames(4)
	await physics_frame
	await physics_frame

	var focus: Vector3 = inst.global_position + (spec["focus"] as Vector3)
	_cam.global_position = focus + (spec["cam_offset"] as Vector3)
	_cam.look_at(focus, Vector3.UP)
	await _frames(4)

	var glass_targets := _glass_targets(inst)
	var subject_box := _subject_box(glass_targets, cube.global_position)
	var ok := _in_frame(model_name, subject_box)
	ok = _prove_visible(model_name, inst, glass_targets) and ok
	if ok:
		await _save(spec["file"])
	cube.free()
	colliders.free()
	await physics_frame


func _shoot_control_wall_glass() -> void:
	_stage = "control_wall_glass"
	_view.show_model("tp_plane_05a")
	var inst := _view.get_node("Pivot").get_child(0) as Node3D

	var holder := Node3D.new()
	holder.name = "ControlHolder"
	_main.add_child(holder)

	var wall_pos := APRON_POS + Vector3(6.0, 0.0, 12.5)
	for dx in [-0.5, 0.5, 1.5]:
		var wg := (load(WALL_GLASS) as PackedScene).instantiate() as Node3D
		wg.position = wall_pos + Vector3(dx, 0.0, 0.0)
		holder.add_child(wg)

	# Bright orange pillar behind the terminal glass wall proves tp_glass.tres stays clear.
	var pillar := MeshInstance3D.new()
	var pillar_mesh := BoxMesh.new()
	pillar_mesh.size = Vector3(1.2, 2.0, 0.5)
	pillar.mesh = pillar_mesh
	pillar.material_override = _unshaded(Color(1.0, 0.35, 0.08))
	pillar.position = wall_pos + Vector3(0.5, 1.1, -1.2)
	holder.add_child(pillar)

	var cube := _cube(wall_pos + Vector3(2.8, 0.5, 0.0))
	var colliders := _build_colliders(inst)
	await _frames(4)
	await physics_frame
	await physics_frame

	var focus := APRON_POS + Vector3(3.0, 1.7, 8.2)
	_cam.global_position = focus + Vector3(11.0, 4.0, 17.5)
	_cam.look_at(focus, Vector3.UP)
	await _frames(4)

	var glass_targets := _glass_targets(inst)
	var box := _subject_box(glass_targets, cube.global_position)
	box = box.merge(AABB(wall_pos + Vector3(-1.0, 0.0, -1.5), Vector3(4.0, 2.6, 2.0)))
	var ok := _in_frame("control_05a_wall_glass", box)
	ok = _prove_visible("control_05a_wall_glass", inst, glass_targets) and ok
	if ok:
		await _save("control_05a_and_wall_glass.png")
	holder.free()
	cube.free()
	colliders.free()
	await physics_frame


func _glass_targets(inst: Node3D) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for child in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat == null or mat.resource_path != PlaneView.TINTED_GLASS_MATERIAL.resource_path:
				continue
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			var mid := Vector3.ZERO
			for v in verts:
				mid += mi.global_transform * v
			mid /= float(verts.size())
			var best := mi.global_transform * verts[0]
			var best_d := INF
			for v in verts:
				var wp := mi.global_transform * v
				if wp.x >= -0.05 and wp.distance_to(mid) < best_d:
					best_d = wp.distance_to(mid)
					best = wp
			pts.append(best)
	return pts


func _subject_box(pts: Array[Vector3], cube_pos: Vector3) -> AABB:
	var box := AABB(cube_pos - Vector3.ONE * 0.5, Vector3.ONE)
	for p in pts:
		box = box.expand(p)
	return box.grow(0.4)


func _build_colliders(inst: Node3D) -> Node3D:
	var holder := Node3D.new()
	holder.name = "ProbeColliders"
	root.add_child(holder)
	for child in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		var faces := PackedVector3Array()
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if index.is_empty():
				faces.append_array(verts)
			else:
				for idx in index:
					faces.append(verts[idx])
		if faces.is_empty():
			continue
		var xf_faces := PackedVector3Array()
		for v in faces:
			xf_faces.append(mi.global_transform * v)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(xf_faces)
		var cshape := CollisionShape3D.new()
		cshape.shape = shape
		var body := StaticBody3D.new()
		body.add_child(cshape)
		holder.add_child(body)
	return holder


func _in_frame(label: String, box: AABB) -> bool:
	var rect := Rect2(Vector2.ZERO, Vector2(root.size)).grow(-MARGIN_PX)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var p := box.get_endpoint(i)
		if _cam.is_position_behind(p):
			_invalid("%s: %s behind camera" % [label, p])
			return false
		var s := _cam.unproject_position(p)
		lo = lo.min(s)
		hi = hi.max(s)
	var ok := rect.has_point(lo) and rect.has_point(hi)
	print("INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) ok=%s" % [label, lo.x, lo.y, hi.x, hi.y, ok])
	if not ok:
		_invalid("%s: bounds leave viewport" % label)
	return ok


func _prove_visible(label: String, inst: Node3D, targets: Array[Vector3]) -> bool:
	if targets.is_empty():
		_invalid("%s: no tinted glass targets found" % label)
		return false
	var space := _cam.get_world_3d().direct_space_state
	var hits := 0
	for target in targets:
		var from := _cam.global_position
		var q := PhysicsRayQueryParameters3D.create(
			from, target + (target - from).normalized() * 0.4
		)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and (hit["position"] as Vector3).distance_to(target) < 1.2:
			hits += 1
	var ok := hits > 0
	print("VISIBLE %s ray_hits=%d/%d ok=%s" % [label, hits, targets.size(), ok])
	if not ok:
		_invalid("%s: no ray hit tinted glass targets (inst=%s)" % [label, inst.name])
	return ok


func _cube(at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.material_override = _unshaded(Color(0.95, 0.95, 0.95))
	mi.position = at
	_main.add_child(mi)
	return mi


func _unshaded(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat


func _save(file: String) -> void:
	await _frames(4)
	var img := root.get_texture().get_image()
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	_plates.append(path)
	print("PLATE saved %s size=%s" % [path, img.get_size()])


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


func _frames(count: int) -> void:
	for i in count:
		await process_frame
		_beat(_stage)
	await RenderingServer.frame_post_draw


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _beat(stage: String) -> void:
	_lock.lock()
	_stage = stage
	_beat_ms = Time.get_ticks_msec()
	_lock.unlock()


func _finish() -> void:
	_lock.lock()
	_stop = true
	_lock.unlock()
	_guard.wait_to_finish()


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_lock.lock()
		var stop := _stop
		var stage := _stage
		var silent := Time.get_ticks_msec() - _beat_ms
		_lock.unlock()
		if stop:
			return
		if silent > HANG_MS:
			print("PROBE_INVALID hang: stage=%s silent_ms=%d" % [stage, silent])
			OS.crash("plane_tinted_glass_plates_probe stalled in %s" % stage)
