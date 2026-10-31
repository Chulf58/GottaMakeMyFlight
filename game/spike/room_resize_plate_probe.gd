extends SceneTree
## Windowed plate probe for room resizing (decision
## resize-rooms-first-drag-a-room-s-edge-to-grow-or-shrink-it-f), in the real
## main scene with a new random seed (printed). A cafe and a toilet room are
## marked on a strip of floor through the BuildMode API, then the Cafe tool
## grabs the cafe's east edge and:
##   1. drags it outward into free floor: the valid (green) ghost over the new
##      rectangle, "Cafe 5 x 3" on the status line;
##   2. drags it on into the toilet room: the refused (red) ghost with the
##      reason "Overlaps another room" on the status line;
##   3. drags back out to the free floor and releases: the cafe has its new
##      size, the room view shows it, and the status line says "Cafe resized".
## Every plate proves its subject is in frame (the rectangle's corners and
## centre are projected and printed) and not hidden (a sight line from the
## camera to the slab centre against every visible mesh of the scene outside
## BuildMode that stands higher than the floor). A plate that fails prints
## PROBE_INVALID and the probe exits 1. A guard thread calls OS.crash() on a
## stall.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/room_resize_plate_probe.gd
##
## Plates go to tools/blender/out/room_resize/ (gitignored).

const OUT_REL := "res://../tools/blender/out/room_resize"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 60000
## The strip of floor, in the middle of the 66 x 30 grid under the default camera:
## columns 26 to 39, rows 12 to 16. The grid starts with no floor.
const FLOOR_MIN := Vector2i(26, 12)
const FLOOR_MAX := Vector2i(39, 16)
const CAFE := Rect2i(27, 13, 4, 3)
const TOILET := Rect2i(34, 13, 3, 3)
## The row the edge is grabbed and dragged in: the cafe's middle row.
const ROW := 14
## Grid lines (x) the east edge is dragged to.
const LINE_FREE := 32
const LINE_INTO_TOILET := 35
## A mesh whose top is below this height is ground, not a blocker.
const GROUND_TOP_M := 0.2

var _out_dir := ""
var _failed := false
var _stage := "init"
var _heartbeat_ms := 0
var _guard_mutex := Mutex.new()
var _guard_stop := false
var _guard: Thread
var _build: BuildMode
var _cam: Camera3D
var _main: Node3D
var _cafe_id := 0


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
			OS.crash("room resize plate probe hung")


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _finish() -> void:
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _run() -> void:
	var world_seed := randi()
	seed(world_seed)
	print("PROBE world_seed=", world_seed)
	_main = load(MAIN_SCENE).instantiate()
	var clock := _main.get_node_or_null("SimClock") as SimClock
	if clock != null:
		clock.seed_rng(world_seed)
	root.add_child(_main)
	_cam = _main.get_node("TycoonCamera/Camera3D")
	_build = _main.get_node("BuildMode")
	await _frames(10)
	_build_strip()
	if _failed:
		_finish()
		return
	await _frames(4)
	await _drag_plates()
	_finish()


func _at(cell: Vector2i) -> Vector3:
	return _build.grid.cell_to_world(cell)


## A ground point on grid line `line` of the x axis, in the middle of row `row`.
func _on_line(line: int, row: int) -> Vector3:
	return _at(Vector2i(line, row)) - Vector3(0.5, 0.0, 0.0)


## A ground point 0.1 m past grid line `line` in row ROW: the edge snaps to the
## line, and the point stays in one cell when the mouse is warped onto it.
func _drag_point(line: int) -> Vector3:
	return _on_line(line, ROW) + Vector3(0.1, 0.0, 0.0)


func _drag_room(tool: BuildMode.Tool, rect: Rect2i) -> int:
	_build.set_tool(tool)
	_build.begin_area(_at(rect.position))
	_build.move_area(_at(rect.end - Vector2i.ONE))
	_build.finish_area()
	return _build.grid.room_at(rect.position)


## Floor over the strip, one cafe and one toilet room with a free gap between.
func _build_strip() -> void:
	_build.set_tool(BuildMode.Tool.FLOOR)
	_build.begin_area(_at(FLOOR_MIN))
	_build.move_area(_at(FLOOR_MAX))
	_build.finish_area()
	if _build.grid.floor_at(FLOOR_MAX) == BuildGrid.FLOOR_NONE:
		_invalid("the floor strip was not laid: %s" % _build.status_text())
		return
	_cafe_id = _drag_room(BuildMode.Tool.CAFE_ROOM, CAFE)
	var toilet_id := _drag_room(BuildMode.Tool.TOILET_ROOM, TOILET)
	print("ROOMS cafe=%d %s toilet=%d %s" % [_cafe_id, CAFE, toilet_id, TOILET])
	if _cafe_id == 0 or toilet_id == 0:
		_invalid("a room was not marked: %s" % _build.status_text())


func _drag_plates() -> void:
	_build.set_tool(BuildMode.Tool.CAFE_ROOM)
	# A press 0.1 m inside the cafe's east edge, in its middle row.
	var press := _on_line(CAFE.end.x, ROW) - Vector3(0.1, 0.0, 0.0)
	_build.begin_area(press)
	if not _build.is_dragging():
		_invalid("the press did not start a drag")
		return
	await _drag_plate("valid", LINE_FREE, Rect2i(27, 13, 5, 3), true, "Cafe 5 x 3")
	await _drag_plate(
		"refused",
		LINE_INTO_TOILET,
		Rect2i(27, 13, 8, 3),
		false,
		"Cafe 8 x 3  Overlaps another room"
	)
	var back := _drag_point(LINE_FREE)
	root.warp_mouse(_cam.unproject_position(back))
	_build.move_area(back)
	await _frames(4)
	_build.finish_area()
	await _frames(6)
	await _released_plate()


## Drags the grabbed edge to grid line `line` and saves a plate of the ghost,
## which must be over `expected` and green when `fits`, red otherwise.
func _drag_plate(label: String, line: int, expected: Rect2i, fits: bool, status: String) -> void:
	_beat("drag_" + label)
	var target := _drag_point(line)
	if not _in_frame(label, expected):
		return
	root.warp_mouse(_cam.unproject_position(target))
	_build.move_area(target)
	await _frames(6)
	var slab := _slab()
	var material: Material = (
		_build.get("_valid_material") if fits else _build.get("_invalid_material")
	)
	print(
		(
			"GHOST %s dragged=%s ghost_visible=%s slabs=%d status='%s' mouse=%s"
			% [
				label,
				_build.get("_resize").rect(),
				_build.get_node("Ghost").visible,
				_build.get_node("Ghost").get_child_count(),
				_build.status_text(),
				root.get_mouse_position()
			]
		)
	)
	if _build.get("_resize").rect() != expected or slab == null:
		_invalid("%s: the ghost is not over %s" % [label, expected])
		return
	if slab.material_override != material:
		_invalid("%s: the ghost is the wrong colour (expected fits=%s)" % [label, fits])
		return
	if _build.status_text() != status:
		_invalid("%s: status '%s', expected '%s'" % [label, _build.status_text(), status])
		return
	_plate(label, expected)


func _released_plate() -> void:
	_beat("released")
	var room := _build.grid.get_room(_cafe_id)
	var expected := Rect2i(27, 13, 5, 3)
	print(
		(
			"RELEASED room_id=%d rect=%s ghost_slabs=%d status='%s'"
			% [
				_cafe_id,
				room.get("rect"),
				_build.get_node("Ghost").get_child_count(),
				_build.status_text()
			]
		)
	)
	if room.get("rect") != expected:
		_invalid("released: the cafe is %s, expected %s" % [room.get("rect"), expected])
		return
	if not _build.status_text().begins_with("Cafe resized to 5 x 3: "):
		_invalid("released: status '%s'" % _build.status_text())
		return
	if _build.is_dragging():
		_invalid("released: the drag is still on")
		return
	_plate("released", expected)


func _slab() -> MeshInstance3D:
	for child in _build.get_node("Ghost").get_children():
		if child is MeshInstance3D:
			return child
	return null


func _slab_centre(area: Rect2i) -> Vector3:
	var low := _at(area.position)
	var high := _at(area.end - Vector2i.ONE)
	return (low + high) / 2.0 + Vector3(0.0, 0.1, 0.0)


## The rectangle's four corners and centre must project inside the viewport
## with a margin; they are printed.
func _in_frame(label: String, area: Rect2i) -> bool:
	var frame := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	var low := _at(area.position) - Vector3(0.5, -0.1, 0.5)
	var high := _at(area.end - Vector2i.ONE) + Vector3(0.5, 0.1, 0.5)
	var points: Array[Vector3] = [
		low, Vector3(high.x, low.y, low.z), high, Vector3(low.x, low.y, high.z), _slab_centre(area)
	]
	for p in points:
		var s := _cam.unproject_position(p)
		var inside := frame.has_point(s) and not _cam.is_position_behind(p)
		print("INFRAME %s point=%s screen=(%.0f,%.0f) ok=%s" % [label, p, s.x, s.y, inside])
		if not inside:
			_invalid("%s: %s is outside the frame" % [label, p])
			return false
	return true


## Sight lines from the camera to the slab centre and the middle of each side
## against the AABB of every visible mesh outside BuildMode whose top is above
## the floor. Prints the blockers.
func _clear_sight(label: String, area: Rect2i) -> bool:
	var targets: Array[Vector3] = [
		_slab_centre(area),
		_slab_centre(Rect2i(area.position, Vector2i(1, area.size.y))),
		_slab_centre(Rect2i(area.end.x - 1, area.position.y, 1, area.size.y)),
	]
	var blockers := {}
	for node in _main.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if _build.is_ancestor_of(mesh) or not mesh.is_visible_in_tree():
			continue
		var box := mesh.global_transform * mesh.get_aabb()
		if box.end.y < GROUND_TOP_M:
			continue
		for p in targets:
			if box.intersects_segment(_cam.global_position, p) != null:
				blockers[mesh.get_path()] = true
	print("SIGHT %s blockers=%s" % [label, blockers.keys()])
	if not blockers.is_empty():
		_invalid("%s: the rectangle is hidden by %s" % [label, blockers.keys()])
		return false
	return true


func _plate(label: String, area: Rect2i) -> void:
	if not _in_frame(label, area) or not _clear_sight(label, area):
		return
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := _out_dir.path_join("room_resize_%s.png" % label)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
