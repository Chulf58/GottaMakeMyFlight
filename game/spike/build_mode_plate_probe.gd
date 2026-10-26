extends SceneTree
## Windowed plate probe for slice e (grid build mode): a small room painted through the
## BuildMode API, then the ghost over one valid and one invalid placement at the default
## camera, with the toolbar on screen. It also casts rays from the camera to every room
## cell and object, against the 2 m wall boxes, to answer whether the walls hide the room.
##
## Run (one windowed Godot run project-wide; hold game/.godot/windowed.lock):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game -s res://spike/build_mode_plate_probe.gd
##
## Plates go to tools/blender/out/build_mode/. A subject that is not in frame prints
## PROBE_INVALID and the probe exits 1.

const OUT_REL := "res://../tools/blender/out/build_mode"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 60000
const ROOM_MIN := Vector2i(28, 28)
const ROOM_MAX := Vector2i(35, 33)
const DOOR_X := 31
const WALL_THICKNESS := BuildView.WALL_THICKNESS

var _out_dir := ""
var _failed := false
var _stage := "init"
var _heartbeat_ms := 0
var _guard_mutex := Mutex.new()
var _guard_stop := false
var _guard: Thread
var _build: BuildMode
var _cam: Camera3D


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
			OS.crash("build mode plate probe hung")


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _save(img: Image, name: String) -> void:
	var path := _out_dir.path_join(name)
	var err := img.save_png(path)
	if err != OK:
		_invalid("could not save %s (error %d)" % [path, err])
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _run() -> void:
	var main: Node3D = load(MAIN_SCENE).instantiate()
	root.add_child(main)
	_cam = main.get_node("TycoonCamera/Camera3D")
	_build = main.get_node("BuildMode")
	await _frames(10)
	_paint_room()
	await _frames(4)
	_report_room()
	var shots := [
		["valid", BuildMode.Tool.DESK, Vector2i(33, 32)],
		["invalid", BuildMode.Tool.DESK, Vector2i(37, 29)],
	]
	for shot in shots:
		await _ghost_plate(shot[0], shot[1], shot[2])
	var rig: Node3D = main.get_node("TycoonCamera")
	rig.position = Vector3(0.0, 0.0, -1.0)
	rig.distance = 22.0
	rig.zoom(1.0)
	await _frames(4)
	print("CLOSE camera distance=", rig.distance)
	_report_room()
	for shot in shots:
		await _ghost_plate(shot[0] + "_close", shot[1], shot[2])
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _cell_point(cell: Vector2i, toward := Vector2.ZERO) -> Vector3:
	return _build.grid.cell_to_world(cell) + Vector3(toward.x, 0.0, toward.y) * 0.45


func _apply(tool: BuildMode.Tool, point: Vector3) -> void:
	_build.set_tool(tool)
	var result := _build.apply_at(point)
	if result == null or not result.ok:
		_invalid("apply tool %d at %s refused" % [tool, point])


## Floor, perimeter walls with one door gap on the south side, then a desk, a scanner and
## a seat row, all through BuildMode.apply_at.
func _paint_room() -> void:
	for y in range(ROOM_MIN.y, ROOM_MAX.y + 1):
		for x in range(ROOM_MIN.x, ROOM_MAX.x + 1):
			_apply(BuildMode.Tool.FLOOR, _cell_point(Vector2i(x, y)))
	for x in range(ROOM_MIN.x, ROOM_MAX.x + 1):
		_apply(BuildMode.Tool.WALL, _cell_point(Vector2i(x, ROOM_MIN.y), Vector2(0, -1)))
		if x != DOOR_X:
			_apply(BuildMode.Tool.WALL, _cell_point(Vector2i(x, ROOM_MAX.y), Vector2(0, 1)))
	for y in range(ROOM_MIN.y, ROOM_MAX.y + 1):
		_apply(BuildMode.Tool.WALL, _cell_point(Vector2i(ROOM_MIN.x, y), Vector2(-1, 0)))
		_apply(BuildMode.Tool.WALL, _cell_point(Vector2i(ROOM_MAX.x, y), Vector2(1, 0)))
	_apply(BuildMode.Tool.DESK, _cell_point(Vector2i(29, 29)))
	_apply(BuildMode.Tool.SCANNER, _cell_point(Vector2i(33, 29)))
	_apply(BuildMode.Tool.SEATS, _cell_point(Vector2i(29, 32)))
	print("ROOM objects=", _build.grid.object_ids().size())


func _wall_boxes() -> Array[AABB]:
	var boxes: Array[AABB] = []
	var local := AABB(
		Vector3(-0.5, 0.0, -WALL_THICKNESS / 2.0),
		Vector3(1.0, BuildView.WALL_HEIGHT, WALL_THICKNESS)
	)
	for y in range(ROOM_MIN.y, ROOM_MAX.y + 1):
		for x in range(ROOM_MIN.x, ROOM_MAX.x + 1):
			for side in [BuildGrid.Side.NORTH, BuildGrid.Side.WEST]:
				if _build.grid.has_wall(Vector2i(x, y), side):
					boxes.append(
						BuildView.wall_transform(_build.grid, Vector2i(x, y), side) * local
					)
	for x in range(ROOM_MIN.x, ROOM_MAX.x + 1):
		if _build.grid.has_wall(Vector2i(x, ROOM_MAX.y), BuildGrid.Side.SOUTH):
			var at := Vector2i(x, ROOM_MAX.y)
			boxes.append(BuildView.wall_transform(_build.grid, at, BuildGrid.Side.SOUTH) * local)
	for y in range(ROOM_MIN.y, ROOM_MAX.y + 1):
		if _build.grid.has_wall(Vector2i(ROOM_MAX.x, y), BuildGrid.Side.EAST):
			var at := Vector2i(ROOM_MAX.x, y)
			boxes.append(BuildView.wall_transform(_build.grid, at, BuildGrid.Side.EAST) * local)
	return boxes


func _hidden_by_walls(point: Vector3, boxes: Array[AABB]) -> bool:
	for box in boxes:
		if box.intersects_segment(_cam.global_position, point) != null:
			return true
	return false


## Prints which room cells and which object centres a wall box blocks from the camera.
func _report_room() -> void:
	var boxes := _wall_boxes()
	print("WALLS boxes=%d height_m=%.1f" % [boxes.size(), BuildView.WALL_HEIGHT])
	var hidden_floor := 0
	var rows := {}
	for y in range(ROOM_MIN.y, ROOM_MAX.y + 1):
		var hidden_in_row := 0
		for x in range(ROOM_MIN.x, ROOM_MAX.x + 1):
			if _hidden_by_walls(_cell_point(Vector2i(x, y)) + Vector3(0, 0.05, 0), boxes):
				hidden_in_row += 1
		rows[y] = hidden_in_row
		hidden_floor += hidden_in_row
	var total := (ROOM_MAX.x - ROOM_MIN.x + 1) * (ROOM_MAX.y - ROOM_MIN.y + 1)
	print("HIDDEN floor_cells=%d of %d, per row (y: hidden)=%s" % [hidden_floor, total, rows])
	for id in _build.grid.object_ids():
		var record := _build.grid.get_object(id)
		var def := BuildCatalog.get_def(record["def"])
		var top := _cell_point(record["anchor"]) + Vector3(0, def.height, 0)
		var base := _cell_point(record["anchor"]) + Vector3(0, 0.05, 0)
		print(
			(
				"HIDDEN object=%s anchor=%s base_hidden=%s top_hidden=%s"
				% [
					record["def"],
					record["anchor"],
					_hidden_by_walls(base, boxes),
					_hidden_by_walls(top, boxes)
				]
			)
		)


func _ghost_plate(label: String, tool: BuildMode.Tool, cell: Vector2i) -> void:
	_beat("ghost_" + label)
	_build.set_tool(tool)
	var target := _build.grid.cell_to_world(cell)
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	var corners: Array[Vector3] = [
		_build.grid.cell_to_world(ROOM_MIN) + Vector3(-0.5, 0, -0.5),
		_build.grid.cell_to_world(ROOM_MAX) + Vector3(0.5, BuildView.WALL_HEIGHT, 0.5),
		target,
	]
	for p in corners:
		var s := _cam.unproject_position(p)
		print(
			"INFRAME %s point=%s screen=(%.0f,%.0f) ok=%s" % [label, p, s.x, s.y, rect.has_point(s)]
		)
		if _cam.is_position_behind(p) or not rect.has_point(s):
			_invalid("%s: %s is outside the frame" % [label, p])
			return
	root.warp_mouse(_cam.unproject_position(target + Vector3(0, 0.05, 0)))
	await _frames(6)
	var verdict := _build.grid.validate(_build.edit_at(target))
	print(
		(
			"GHOST %s cell=%s ok=%s status='%s' ghost_visible=%s mouse=%s"
			% [
				label,
				cell,
				verdict.ok,
				_build.status_text(),
				_build.get_node("Ghost").visible,
				root.get_mouse_position()
			]
		)
	)
	if verdict.ok != label.begins_with("valid") or not _build.get_node("Ghost").visible:
		_invalid("%s: ghost is not showing the expected verdict" % label)
		return
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	_save(img, "room_ghost_%s.png" % label)
