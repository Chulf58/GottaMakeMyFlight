extends SceneTree
## Windowed plates of the hand-built terminal (HandBuiltTerminal) in the real
## main scene: a glass wall, a door wall, the entrance door and the exit door,
## once with the wall cutaway down and once with it off (walls up).
##
## Run (one windowed Godot run project-wide; take the slot lock first):
##   timeout 600 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/door_glass_plates_probe.gd
##
## The sim clock is paused, so no passenger spawns, and the passenger HUD is
## hidden; the build toolbar stays. Each subject must project inside the
## frame (below the toolbar) and be hit first by at least half of the camera
## rays aimed at it, with every drawn wall, post, floor tile and visible
## object as an occluder (glass panes left out), or the probe prints
## PROBE_INVALID and exits 1. A guard thread calls OS.crash() on a stall.
## Plates go to tools/blender/out/door_glass/.

const OUT_REL := "res://../tools/blender/out/door_glass"
const GLASS := "res://assets/materials/tp_glass.tres"
const MARGIN_PX := 8.0
## The build toolbar's strip at the top of the window.
const TOOLBAR_PX := 80.0
const FOCUS_CELL := Vector2i(16, 10)
const YAW := 0.6
const DISTANCES := [18.0, 21.0, 24.0, 27.0, 30.0, 34.0]
const HANG_MS := 60000

var _out_dir := ""
var _failed := false
var _guard := Thread.new()
var _lock := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _stop := false


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_beat("boot")
	_guard.start(_watch)
	_run.call_deferred()


func _run() -> void:
	var main: Node3D = (load("res://main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	(main.get_node("SimClock") as SimClock).set_paused(true)
	(main.get_node("PassengerHud") as CanvasLayer).visible = false
	var mode := main.get_node("BuildMode") as BuildMode
	var view := mode.get_node("BuildView") as BuildView
	await _frames(3)
	_beat("build")
	var builder := HandBuiltTerminal.new(mode)
	builder.on_edit = func() -> void: _beat("build")
	builder.build()
	print("PROBE built applied=%d refused=%d" % [builder.applied, builder.refused.size()])
	for line in builder.refused:
		_invalid("tool use refused: %s" % line)
	var subjects := _subjects(mode.grid)
	var rig := main.get_node("TycoonCamera") as TycoonCamera
	var cam := rig.get_node("Camera3D") as Camera3D
	cam.make_current()
	print("PROBE viewport=%s" % root.get_visible_rect().size)
	for shot in [["cutaway_down", true], ["cutaway_up", false]]:
		_beat(shot[0])
		view.cutaway_enabled = shot[1]
		var framed := false
		for d in DISTANCES:
			rig.position = mode.grid.cell_to_world(FOCUS_CELL)
			rig.yaw = YAW
			rig.distance = d
			rig.zoom(1.0)
			await _frames(6)
			if _all_in_frame(cam, subjects, false):
				framed = true
				break
		print(
			(
				"CAMERA %s pos=%s distance=%.1f pitch_deg=%.1f cut_edges=%d"
				% [
					shot[0],
					cam.global_position,
					rig.distance,
					-cam.rotation_degrees.x,
					view.cut_edges().size()
				]
			)
		)
		if not framed:
			_invalid("%s: no distance frames every subject" % shot[0])
		var ok := _all_in_frame(cam, subjects, true)
		var cut := view.cut_edges()
		var occluders := _colliders(view)
		await physics_frame
		await physics_frame
		for key in subjects:
			ok = _prove_visible(cam, "%s/%s" % [shot[0], key], subjects[key], cut) and ok
		occluders.free()
		var img := await _grab()
		if ok:
			_save(img, shot[0] + ".png")
	print("PROBE done failed=%s" % _failed)
	_finish()
	quit(1 if _failed else 0)


## Each subject: {box, edge (wall_edges form), along, kind}.
func _subjects(grid: BuildGrid) -> Dictionary:
	var t := HandBuiltTerminal
	var west := BuildGrid.Side.WEST
	var north := BuildGrid.Side.NORTH
	var out := {}
	var glass := []
	for y in t.GLASS_YS:
		glass.append(Vector3i(t.FLOOR_MIN.x, y, west))
	out["glass_wall"] = _subject(grid, glass, "glass")
	out["door_wall"] = _subject(grid, [Vector3i(t.DOOR_X, t.LOBBY_Y, north)], "door")
	# The entrance's back edge is the south edge of its cell: north of the row below.
	var entrance := Vector3i(t.ENTRANCE_CELL.x, t.ENTRANCE_CELL.y + 1, north)
	out["entrance_door"] = _subject(grid, [entrance], "door")
	out["exit_door"] = _subject(grid, [Vector3i(t.EXIT_CELL.x, t.EXIT_CELL.y, north)], "door")
	return out


func _subject(grid: BuildGrid, edges: Array, kind: String) -> Dictionary:
	var box := AABB()
	var frames: Array[Transform3D] = []
	for i in edges.size():
		var frame := BuildView.wall_transform(grid, Vector2i(edges[i].x, edges[i].y), edges[i].z)
		frames.append(frame)
		var piece := AABB(frame * Vector3(-0.5, 0.02, -0.1), Vector3.ZERO)
		for corner in [Vector3(0.5, 0.02, 0.1), Vector3(-0.5, 2.5, 0.1), Vector3(0.5, 2.5, -0.1)]:
			piece = piece.expand(frame * corner)
		box = piece if i == 0 else box.merge(piece)
	return {"box": box, "edges": edges, "frames": frames, "kind": kind}


func _all_in_frame(cam: Camera3D, subjects: Dictionary, report: bool) -> bool:
	var size := root.get_visible_rect().size
	var rect := Rect2(Vector2(MARGIN_PX, TOOLBAR_PX), size - Vector2(MARGIN_PX * 2, TOOLBAR_PX))
	var all_ok := true
	for key in subjects:
		var box: AABB = subjects[key]["box"]
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var behind := false
		for i in 8:
			var p := box.get_endpoint(i)
			behind = behind or cam.is_position_behind(p)
			var s := cam.unproject_position(p)
			lo = lo.min(s)
			hi = hi.max(s)
		var ok := not behind and rect.has_point(lo) and rect.has_point(hi)
		if report:
			print(
				(
					"INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) size_px=(%.0f,%.0f) ok=%s"
					% [key, lo.x, lo.y, hi.x, hi.y, hi.x - lo.x, hi.y - lo.y, ok]
				)
			)
			if not ok:
				_invalid("%s leaves the frame" % key)
		all_ok = all_ok and ok
	return all_ok


## Rays from the camera to points on the subject's drawn parts: the jambs of a
## door (its middle is an opening), the kerb and top of a glass wall (its
## panes are no occluder), only the stub height where the edge is cut. At
## least half must first hit inside the subject's box.
func _prove_visible(cam: Camera3D, label: String, subject: Dictionary, cut: Array) -> bool:
	var targets: Array[Vector3] = []
	var edges: Array = subject["edges"]
	for i in edges.size():
		var is_cut := cut.has(edges[i])
		var heights := [0.12] if is_cut else [0.4, 1.2, 2.0]
		var alongs := [-0.45, 0.45]
		if subject["kind"] == "glass":
			heights = [0.1] if is_cut else [0.1, 2.42]
			alongs = [-0.3, 0.0, 0.3]
		for h in heights:
			for a in alongs:
				targets.append((subject["frames"][i] as Transform3D) * Vector3(a, h, 0.0))
	var box: AABB = (subject["box"] as AABB).grow(0.05)
	var space := cam.get_world_3d().direct_space_state
	var hits := 0
	for target in targets:
		var from := cam.global_position
		var q := PhysicsRayQueryParameters3D.create(
			from, target + (target - from).normalized() * 0.3
		)
		var hit := space.intersect_ray(q)
		if hit and box.has_point(hit.position):
			hits += 1
	var ok := hits > 0 and hits * 2 >= targets.size()
	print("VISIBLE %s ray_hits=%d/%d ok=%s" % [label, hits, targets.size(), ok])
	if not ok:
		_invalid("%s: occluded or not hit (%d of %d rays)" % [label, hits, targets.size()])
	return ok


## One static body per drawn multimesh instance (read back from the renderer)
## and per mesh of a visible object node, glass panes left out.
func _colliders(view: BuildView) -> Node3D:
	var holder := Node3D.new()
	holder.name = "ProbeColliders"
	root.add_child(holder)
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
				holder.add_child(_body(at, local_faces))
		elif child.has_meta("record") and (child as Node3D).is_visible_in_tree():
			for mi in child.find_children("*", "MeshInstance3D", true, false):
				var faces := _opaque_faces((mi as MeshInstance3D).mesh)
				if not faces.is_empty():
					holder.add_child(_body((mi as MeshInstance3D).global_transform, faces))
	return holder


func _body(at: Transform3D, local_faces: PackedVector3Array) -> StaticBody3D:
	var faces := PackedVector3Array()
	for p in local_faces:
		faces.append(at * p)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var shape_node := CollisionShape3D.new()
	shape_node.shape = shape
	var body := StaticBody3D.new()
	body.add_child(shape_node)
	return body


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


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
		_beat(_stage)
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
			OS.crash("door_glass_plates_probe: main thread stalled in %s" % stage)
