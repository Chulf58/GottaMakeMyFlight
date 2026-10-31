extends SceneTree
## Windowed plate probe for room templates (decision room-templates-store-
## rooms-with-their-pieces-kept-in-each-sa), in the real main scene with a new
## random seed (printed). A cafe with a counter and a table is built on a strip
## of floor through the BuildMode API and saved from the Templates page, then
## its card is pressed and the pointer (BuildMode.pointer_override) is put on:
##   1. free floor: the Templates page with its Save room and template cards,
##      the green paste ghost (room slab and both pieces), "Cafe 5x3: click to
##      place, R turns it" on the status line and the cost on the cost line;
##   2. the saved cafe: the red ghost and "Cafe 5x3  Overlaps another room";
##   3. free floor after R: the turned 3x5 ghost, green;
##   4. after the click: the pasted, turned cafe with its pieces built.
## Every plate proves its subject is in frame (the rectangle's corners and
## centre are projected and printed, and the page's screen rectangle is inside
## the window) and not hidden (sight lines against every visible mesh outside
## BuildMode above the floor). A plate that fails prints PROBE_INVALID and the
## probe exits 1. A guard thread calls OS.crash() on a stall.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/room_templates_plate_probe.gd
##
## Plates go to tools/blender/out/room_templates/ (gitignored).

const OUT_REL := "res://../tools/blender/out/room_templates"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 60000
## The strip of floor under the default camera: columns 26 to 39, rows 12 to 16.
const FLOOR_MIN := Vector2i(26, 12)
const FLOOR_MAX := Vector2i(39, 16)
const CAFE := Rect2i(27, 13, 5, 3)
const COUNTER_AT := Vector2i(28, 13)
const TABLE_AT := Vector2i(28, 15)
## Paste centres: free floor east of the cafe, and over the cafe.
const FREE_CENTRE := Vector2i(36, 14)
const OVER_CAFE := Vector2i(31, 14)
const GROUND_TOP_M := 0.2
## Where the camera glides before the plates, and how far it stands: the strip
## sits above the screen centre, clear of the Airport closed hint card.
const VIEW_CELL := Vector2i(33, 19)
const VIEW_DISTANCE := 24.0

var _out_dir := ""
var _failed := false
var _stage := "init"
var _heartbeat_ms := 0
var _guard_mutex := Mutex.new()
var _guard_stop := false
var _guard: Thread
var _build: BuildMode
var _menu: BuildMenu
var _paste: TemplatePaste
var _cam: Camera3D
var _main: Node3D


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
			OS.crash("room templates plate probe hung")


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
	_menu = _main.get_node("BuildMenu")
	_paste = _build.templates
	await _frames(10)
	var tycoon: TycoonCamera = _main.get_node("TycoonCamera")
	tycoon.glide_to(_at(VIEW_CELL), VIEW_DISTANCE)
	for i in 600:
		if not tycoon.is_gliding():
			break
		await process_frame
	print("CAMERA gliding=%s distance=%.1f" % [tycoon.is_gliding(), tycoon.distance])
	_build_cafe()
	if not _failed:
		await _frames(4)
		await _plates()
	_finish()


func _at(cell: Vector2i) -> Vector3:
	return _build.grid.cell_to_world(cell)


func _commit(edit: BuildEdit) -> bool:
	var plan: Array[BuildEdit] = [edit]
	var result := BuildTransaction.commit_plan(_build.grid, plan, _build.wallet())
	if not result.ok:
		_invalid("setup edit refused: %s" % result.reason_text())
	return result.ok


## Floor over the strip and a furnished cafe, saved from the Templates page.
func _build_cafe() -> void:
	_build.set_tool(BuildMode.Tool.FLOOR)
	_build.begin_area(_at(FLOOR_MIN))
	_build.move_area(_at(FLOOR_MAX))
	_build.finish_area()
	_build.set_tool(BuildMode.Tool.NONE)
	var room := BuildEdit.place_room(CAFE, &"cafe")
	if not (_commit(room) and _commit(BuildEdit.place_object(&"cafe_counter", COUNTER_AT, 0))):
		return
	if not _commit(BuildEdit.place_object(&"cafe_table", TABLE_AT, 0)):
		return
	_menu.press_category(BuildMenu.TEMPLATES_PAGE)
	_menu.templates_page.save_card().pressed.emit()
	var saved := _paste.click(COUNTER_AT)
	print(
		(
			"SAVED library=%d status='%s' saved=%s"
			% [_paste.library.size(), _paste.status_text(), saved]
		)
	)
	if _paste.library.size() != 1:
		_invalid("the cafe was not saved")
		return
	_menu.templates_page.card(0).pressed.emit()
	if _paste.armed != 0:
		_invalid("the card did not arm the paste")


func _point_at(cell: Vector2i) -> void:
	_build.pointer_override = _cam.unproject_position(_at(cell))
	root.warp_mouse(_build.pointer_override)


func _plates() -> void:
	var template := _paste.library.get_template(0)
	_point_at(FREE_CENTRE)
	await _frames(6)
	var hint := TemplatePaste.PLACE_HINT % template.name
	await _ghost_plate("valid", template.rect_at(FREE_CENTRE, 0), true, hint, true)
	_point_at(OVER_CAFE)
	await _frames(6)
	var refused := "%s  %s" % [template.name, "Overlaps another room"]
	await _ghost_plate("refused", template.rect_at(OVER_CAFE, 0), false, refused, false)
	_paste.rotate_turns()
	_point_at(FREE_CENTRE)
	await _frames(6)
	await _ghost_plate("turned", template.rect_at(FREE_CENTRE, 1), true, hint, false)
	var result := _paste.paste_at(FREE_CENTRE)
	await _frames(8)
	var rect := template.rect_at(FREE_CENTRE, 1)
	var pasted := _build.grid.room_at(rect.position)
	print(
		(
			"PASTED ok=%s room=%d rect=%s objects=%d status='%s'"
			% [
				result.ok,
				pasted,
				_build.grid.get_room(pasted).get("rect"),
				_build.grid.object_ids().size(),
				_paste.status_text()
			]
		)
	)
	if not _paste.status_text().begins_with("Placed %s for " % template.name):
		_invalid("pasted: status %s" % _paste.status_text())
		return
	if not result.ok or _build.grid.get_room(pasted).get("rect") != rect:
		_invalid("pasted: no room on %s" % rect)
		return
	_beat("pasted")
	_build.pointer_override = Vector2(-1.0, -1.0)
	_paste.disarm()
	await _frames(6)
	_plate("pasted", rect, false)


func _ghost() -> Node3D:
	return _paste.get_node("TemplateGhost")


## Saves a plate of the paste ghost, which must cover `expected` with the
## right colour and both pieces, with `status` on the menu's status line.
func _ghost_plate(label: String, expected: Rect2i, fits: bool, status: String, page: bool) -> void:
	_beat("ghost_" + label)
	var slab: MeshInstance3D = null
	var pieces := 0
	for child in _ghost().get_children():
		if child is MeshInstance3D and slab == null:
			slab = child
		else:
			pieces += 1
	var material: Material = _paste.get("_valid_material" if fits else "_invalid_material")
	var slab_at := Vector3.ZERO if slab == null else slab.global_position
	print(
		(
			"GHOST %s slab_at=%s expected_centre=%s pieces=%d status='%s' cost='%s'"
			% [
				label,
				slab_at,
				_centre(expected),
				pieces,
				_menu.status_label().text,
				_menu.preview_label().text
			]
		)
	)
	if slab == null or slab_at.distance_to(_centre(expected) - Vector3(0.0, 0.04, 0.0)) > 0.05:
		_invalid("%s: the ghost slab is not over %s" % [label, expected])
		return
	if slab.material_override != material or pieces != 2:
		_invalid("%s: wrong colour or %d pieces (fits=%s)" % [label, pieces, fits])
		return
	if _menu.status_label().text != status:
		_invalid("%s: status '%s', expected '%s'" % [label, _menu.status_label().text, status])
		return
	if fits and not _menu.preview_label().text.begins_with("Cost "):
		_invalid("%s: cost line '%s'" % [label, _menu.preview_label().text])
		return
	_plate(label, expected, page)


func _centre(area: Rect2i) -> Vector3:
	var low := _at(area.position)
	var high := _at(area.end - Vector2i.ONE)
	return (low + high) / 2.0 + Vector3(0.0, 0.1, 0.0)


## The rectangle's four corners and centre must project inside the viewport
## with a margin, and with `page` the Templates page must be on screen; all printed.
func _in_frame(label: String, area: Rect2i, page: bool) -> bool:
	var frame := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	var low := _at(area.position) - Vector3(0.5, -0.1, 0.5)
	var high := _at(area.end - Vector2i.ONE) + Vector3(0.5, 0.1, 0.5)
	var points: Array[Vector3] = [
		low, Vector3(high.x, low.y, low.z), high, Vector3(low.x, low.y, high.z), _centre(area)
	]
	for p in points:
		var s := _cam.unproject_position(p)
		var inside := frame.has_point(s) and not _cam.is_position_behind(p)
		print("INFRAME %s point=%s screen=(%.0f,%.0f) ok=%s" % [label, p, s.x, s.y, inside])
		if not inside:
			_invalid("%s: %s is outside the frame" % [label, p])
			return false
	if page:
		var box := _menu.templates_page.get_global_rect()
		var shown := _menu.templates_page.is_visible_in_tree() and frame.encloses(box)
		print(
			(
				"INFRAME %s page=%s cards=%d ok=%s"
				% [label, box, _menu.templates_page.card_count(), shown]
			)
		)
		if not shown:
			_invalid("%s: the Templates page is not on screen" % label)
			return false
	return true


## Sight lines from the camera to the rectangle's centre and its west and east
## columns against every visible mesh outside BuildMode above the floor,
## except a mesh whose box holds the target (the ground). Prints the blockers.
func _clear_sight(label: String, area: Rect2i) -> bool:
	var targets: Array[Vector3] = [
		_centre(area),
		_centre(Rect2i(area.position, Vector2i(1, area.size.y))),
		_centre(Rect2i(area.end.x - 1, area.position.y, 1, area.size.y)),
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
			if box.has_point(p):
				break
			if box.intersects_segment(_cam.global_position, p) != null:
				blockers[mesh.get_path()] = true
	print("SIGHT %s blockers=%s" % [label, blockers.keys()])
	if not blockers.is_empty():
		_invalid("%s: the rectangle is hidden by %s" % [label, blockers.keys()])
		return false
	return true


func _plate(label: String, area: Rect2i, page: bool) -> void:
	if not _in_frame(label, area, page) or not _clear_sight(label, area):
		return
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := _out_dir.path_join("room_templates_%s.png" % label)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
