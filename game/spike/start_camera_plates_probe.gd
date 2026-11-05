extends SceneTree
## Windowed plates of the start camera (board 9a761a26, parts a and h; decision
## start-camera-frames-the-built-area-the-flight-result-card-hi). Boots the real
## main scene on the starter shell with a new random sim seed (printed) and, for
## each state, waits for the camera to settle, prints the start area's ground
## corners on screen next to the HUD rectangles, and fails when the area meets
## one of them or leaves the viewport:
##   start      the status banner or hint card over the category bar
##   tray       the Baggage tray open
##   bag_room   a belt and a bag room built in the lower half of the terminal,
##              the Baggage tray open: both must show clear of the tray stack
## Each check prints the values it compared. A failed check prints
## PROBE_INVALID and the probe exits 1.
##
## Run (one windowed Godot run project-wide; take the slot lock first). Add
## `--resolution 1280x1024` for another aspect:
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/start_camera_plates_probe.gd
##
## Plates go to tools/blender/out/start-camera/ (a name suffix from the
## user arguments after `--`, if any).

const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/start-camera"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 4.0
const SETTLE_FRAMES := 420
## The bag room is this many cells deep, and sits this many cells in from the
## terminal's south edge; the belt runs beside it.
const ROOM_SIZE := Vector2i(3, 3)

var _out_dir := ""
var _suffix := ""
var _failed := false
var _main: Node
var _camera: TycoonCamera
var _hud: PassengerHud
var _menu: BuildMenu
var _mode: BuildMode
var _room: PanelRoom
var _baggage := -1


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var args := OS.get_cmdline_user_args()
	_suffix = "" if args.is_empty() else "-" + args[0]
	print("PROBE out_dir=", _out_dir, " suffix=", _suffix)
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	var world_seed := randi()
	print("PROBE world_seed=%d" % world_seed)
	_main = load(MAIN_SCENE).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(world_seed)
	root.add_child(_main)
	_camera = _main.get_node("TycoonCamera")
	_hud = _main.get_node("PassengerHud")
	_menu = _main.get_node("BuildMenu")
	_mode = _main.get_node("BuildMode")
	_room = _hud.get_node("PanelRoom")
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	for i in BuildMenu.categories().size():
		if BuildMenu.bar_name(i) == "Baggage":
			_baggage = i
	if _baggage < 0:
		_invalid("no Baggage category found")
	await _frames(10)
	await _state("start", [])
	if not _failed:
		_menu.press_category(_baggage)
		await _state("tray", [])
	if not _failed:
		var built := _build_bag_room()
		await _state("bag_room", built)
	_main.queue_free()
	await _frames(3)
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


## Builds a bag room and a belt into it in the lower half of the start area,
## returns their ground corners (world points) for the visibility check.
func _build_bag_room() -> Array[Vector3]:
	var grid := _mode.grid
	var area := StartView.area_for(grid)
	var low := Vector2i(int(area.position.x - grid.origin.x), int(area.position.y - grid.origin.z))
	var high := Vector2i(int(area.end.x - grid.origin.x), int(area.end.y - grid.origin.z))
	print("PROBE area cells %s to %s" % [low, high])
	var out: Array[Vector3] = []
	var rect := Rect2i(Vector2i(high.x - 1 - ROOM_SIZE.x, high.y - 1 - ROOM_SIZE.y - 1), ROOM_SIZE)
	var result := RoomTool.mark(grid, rect, &"bag_room", _mode.wallet())
	print("BUILD bag_room %s ok=%s reason=%s" % [rect, result.ok, result.reason_text()])
	if not result.ok:
		_invalid("the bag room was refused")
		return out
	(_mode.get_node("BuildView") as BuildView).refresh(grid)
	var belt_from := Vector2i(rect.position.x - 4, rect.position.y)
	var belt_to := Vector2i(rect.position.x - 1, rect.position.y)
	_mode.set_tool(BuildMode.Tool.BELT)
	var belt := _mode.lay_belt(belt_from, belt_to)
	_mode.set_tool(BuildMode.Tool.NONE)
	print("BUILD belt %s to %s ok=%s reason=%s" % [belt_from, belt_to, belt.ok, belt.reason_text()])
	if not belt.ok:
		_invalid("the belt was refused")
		return out
	var cells: Array[Vector2i] = [rect.position, rect.end, belt_from]
	for cell in cells:
		out.append(grid.origin + Vector3(cell.x, 0.0, cell.y))
	_menu.press_category(_baggage)
	return out


## Waits for the room and distance to settle, prints the area on screen next
## to every HUD rectangle, checks it, and saves the plate.
func _state(name: String, extra: Array[Vector3]) -> void:
	for i in SETTLE_FRAMES:
		await process_frame
		var want := _room.free_fraction()
		if (
			_camera.room.is_equal_approx(want)
			and absf(_camera.distance - _camera.target_distance) < 0.02
		):
			break
	await _frames(3)
	var view := root.get_visible_rect().size
	var eye := _camera.get_node("Camera3D") as Camera3D
	var area := StartView.area_for(_mode.grid)
	var corners: Array[Vector3] = []
	for x in [area.position.x, area.end.x]:
		for z in [area.position.y, area.end.y]:
			corners.append(Vector3(x, 0.0, z))
	var shown := _bounds(eye, corners, name)
	var extra_shown := _bounds(eye, extra, name) if not extra.is_empty() else Rect2()
	var hud := _hud_rects()
	var free := _room.free_fraction()
	var free_px := Rect2(free.position * view, free.size * view)
	print(
		(
			"STATE %s viewport=%s area_on_screen=%s built_on_screen=%s free_px=%s dist=%.2f"
			% [name, view, shown, extra_shown, free_px, _camera.distance]
		)
	)
	print("HUD %s %s" % [name, hud])
	if not Rect2(Vector2.ZERO, view).grow(-MARGIN_PX).encloses(shown):
		_invalid("%s: the start area is not wholly in the viewport" % name)
	for key in hud:
		var rect: Rect2 = hud[key]
		if rect.has_area() and shown.intersects(rect):
			_invalid("%s: the start area meets %s %s" % [name, key, rect])
		if extra_shown.has_area() and rect.has_area() and extra_shown.intersects(rect):
			_invalid("%s: the built room and belt meet %s %s" % [name, key, rect])
	await _save_plate(name)


## The HUD rectangles the framed area must clear: the category bar, the open
## tray stack, the banner or hint card.
func _hud_rects() -> Dictionary:
	var rects := {"bar": _menu.bar().get_global_rect()}
	if _menu.is_tray_open():
		var size := root.get_visible_rect().size
		var tray := _menu.tray().get_global_rect()
		var top := size.y - BuildMenu.tray_stack_top()
		var half := maxf(BuildMenu.COLUMN_W, tray.size.x) / 2.0
		rects["tray_stack"] = Rect2(size.x / 2.0 - half, top, half * 2.0, size.y - top)
	var banner: Rect2 = _room.banner_rect.call()
	rects["banner_or_hint"] = banner
	return rects


func _bounds(eye: Camera3D, points: Array[Vector3], name: String) -> Rect2:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for world in points:
		if eye.is_position_behind(world):
			_invalid("%s: point %s is behind the camera" % [name, world])
			return Rect2()
		var point := eye.unproject_position(world)
		low = low.min(point)
		high = high.max(point)
	return Rect2(low, high - low)


func _save_plate(name: String) -> void:
	var img: Image = await PlateSight.grab(self)
	var path := _out_dir.path_join(name + _suffix + ".png")
	var err := img.save_png(path)
	if err != OK:
		_invalid("could not save %s (error %d)" % [path, err])
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
