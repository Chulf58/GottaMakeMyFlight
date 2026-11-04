extends SceneTree
## Windowed plates of the camera making room for open panels (decision camera-
## makes-room-for-open-panels-the-build-tray-banner-and) and of the wall-gap
## line on the banner (board 0d5bf317). Boots the real main scene with a new
## random sim seed (printed). The new game stands on the starter shell, and
## for each state the probe waits for the camera to settle, then checks that
## the start area's four ground corners are inside the viewport, inside the
## free share PanelRoom reports and clear of every open panel's rectangle:
##   start        the banner only (the airport is closed)
##   tray         a build category open, the tray under the terminal
##   staff        the Staff card open
##   offers       the Offers sheet open
##   gap_banner   one outer wall edge removed: the banner must name the gap,
##                and the line must go once the wall is put back
## Each check prints the values it compared. A failed check prints
## PROBE_INVALID and the probe exits 1.
##
## Run (one windowed Godot run project-wide; this probe holds the slot):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/panel_room_plates_probe.gd
##
## Plates go to tools/blender/out/panel-room/.

const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/panel-room"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 4.0
const SETTLE_FRAMES := 420

var _out_dir := ""
var _failed := false
var _main: Node
var _camera: TycoonCamera
var _hud: PassengerHud
var _menu: BuildMenu
var _staff: StaffPanel
var _offers: OfferPanel
var _mode: BuildMode
var _room: PanelRoom


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
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
	_staff = _main.get_node("StaffPanel")
	_offers = _main.get_node("OfferPanel")
	_mode = _main.get_node("BuildMode")
	_room = _hud.get_node("PanelRoom")
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	await _frames(10)
	await _state("start")
	if not _failed:
		_menu.press_category(0)
		await _state("tray")
		_mode.set_tool(BuildMode.Tool.NONE)
	if not _failed:
		_menu.press_staff()
		await _state("staff")
		_menu.press_staff()
	if not _failed:
		_offers.open()
		await _state("offers")
		_offers.close()
	if not _failed:
		await _gap_banner()
	_main.queue_free()
	await _frames(3)
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


## Waits for the room and the distance to settle, checks the start area is
## clear of the open panels and saves the plate.
func _state(name: String) -> void:
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
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for x in [area.position.x, area.end.x]:
		for z in [area.position.y, area.end.y]:
			var world := Vector3(x, 0.0, z)
			if eye.is_position_behind(world):
				_invalid("%s: corner %s is behind the camera" % [name, world])
				return
			var point := eye.unproject_position(world)
			low = low.min(point)
			high = high.max(point)
	var shown := Rect2(low, high - low)
	var free := _room.free_fraction()
	var free_px := Rect2(free.position * view, free.size * view)
	var clashes := []
	for rect in _room.open_rects():
		if shown.intersects(rect):
			clashes.append(rect)
	print(
		(
			"STATE %s viewport=%s area_on_screen=%s free_px=%s open_panels=%d dist=%.2f room=%s"
			% [
				name,
				view,
				shown,
				free_px,
				_room.open_rects().size(),
				_camera.distance,
				_camera.room
			]
		)
	)
	if not Rect2(Vector2.ZERO, view).grow(-MARGIN_PX).encloses(shown):
		_invalid("%s: the start area is not wholly in the viewport" % name)
	elif not free_px.grow(2.0).encloses(shown):
		_invalid("%s: the start area leaves the free share" % name)
	elif not clashes.is_empty():
		_invalid("%s: the start area meets open panels %s" % [name, clashes])
	elif shown.size.x < 150.0 or shown.size.y < 80.0:
		_invalid("%s: the start area is only %s on screen" % [name, shown.size])
	else:
		await _save_plate(name)


## One outer wall edge of the shell taken out: the banner must say so, and put
## back, must not.
func _gap_banner() -> void:
	var edit := _outer_wall_edit()
	if edit == null:
		_invalid("gap_banner: no outer wall edge found to remove")
		return
	print("PROBE gap edge cell=%s side=%d" % [edit.cell, edit.side])
	var before := _staff.hint_text()
	var result := _mode.grid.apply(edit)
	if not result.ok:
		_invalid("gap_banner: removing the wall was refused: %s" % result.reason_text())
		return
	await _frames(10)
	var text := _staff.hint_text()
	print("BANNER before=[%s]" % before.replace("\n", " | "))
	print("BANNER with_gap=[%s]" % text.replace("\n", " | "))
	if before.contains("Wall gap") or not text.contains("Wall gap"):
		_invalid("gap_banner: the banner did not start without the gap and gain it")
		return
	var rows := _staff.checklist().row_texts()
	if not _staff.hint_card().is_visible_in_tree() or not rows.has(StaffPanel.GAP_HINT):
		_invalid("gap_banner: the banner card does not show the line in a row: %s" % [rows])
		return
	var card := _staff.hint_card().get_global_rect()
	if not Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(card):
		_invalid("gap_banner: the banner card %s is off screen" % card)
		return
	await _state("gap_banner")
	var back := _mode.grid.apply(
		BuildEdit.place_wall(edit.cell, edit.side, BuildGrid.WallKind.PLAIN)
	)
	await _frames(5)
	print("BANNER closed=[%s]" % _staff.hint_text().replace("\n", " | "))
	if not back.ok or _staff.hint_text().contains("Wall gap"):
		_invalid("gap_banner: the line stayed after the wall was put back")


## A remove-wall edit for a plain wall on the shell's outer edge, or null.
func _outer_wall_edit() -> BuildEdit:
	var grid := _mode.grid
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			if grid.floor_at(cell) == BuildGrid.FLOOR_NONE:
				continue
			for side in 4:
				var beyond: Vector2i = cell + BuildGrid.SIDE_STEP[side]
				if grid.has_wall(cell, side) and grid.floor_at(beyond) == BuildGrid.FLOOR_NONE:
					if grid.wall_kind(cell, side) == BuildGrid.WallKind.PLAIN:
						return BuildEdit.remove_wall(cell, side)
	return null


func _save_plate(name: String) -> void:
	var img: Image = await PlateSight.grab(self)
	var path := _out_dir.path_join(name + ".png")
	var err := img.save_png(path)
	if err != OK:
		_invalid("could not save %s (error %d)" % [path, err])
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
