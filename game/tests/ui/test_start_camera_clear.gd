class_name TestStartCameraClear
extends GdUnitTestSuite
## On the real main scene, the start camera frames the built area (ground and
## wall tops) clear of the bottom HUD bar, the hint card and the open build tray
## (board 9a761a26; decision start-camera-frames-the-built-area-the-flight-
## result-card-hi), and uses the room they leave instead of a small corner of it.

const SEED := 4_402_028
const SCREEN := Vector2i(1536, 864)
## Pixels the framed area keeps from the bar and the tray, so the entrance end is
## never touching them.
const CLEAR_PX := 20.0
## The least share of the free height or width the framed area fills.
const FILL := 0.8

var _main: Node
var _camera: TycoonCamera
var _hud: PassengerHud
var _menu: BuildMenu
var _mode: BuildMode


func before() -> void:
	# The game's own 16:9 size, not whatever the test runner's window is.
	var screen := SubViewport.new()
	screen.size = SCREEN
	add_child(screen)
	_main = SaveTestKit.boot(screen, SEED)
	_camera = _main.get_node("TycoonCamera")
	_hud = _main.get_node("PassengerHud")
	_menu = _main.get_node("BuildMenu")
	_mode = _main.get_node("BuildMode")


func after() -> void:
	_main.get_parent().free()


func before_test() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	await _settle()
	_camera.go_home()
	await _settle()


func _room() -> PanelRoom:
	return _hud.get_node("PanelRoom")


## A few frames so the panels lay themselves out and PanelRoom reports, then the
## camera's own easing run out.
func _settle() -> void:
	for i in 6:
		await get_tree().process_frame
	for i in 200:
		_camera._process(0.05)


## The start area's four ground corners and the wall tops above them, on screen.
func _area_bounds() -> Rect2:
	var area := StartView.area_for(_mode.grid)
	var eye: Camera3D = _camera.get_node("Camera3D")
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for x in [area.position.x, area.end.x]:
		for z in [area.position.y, area.end.y]:
			for y in [0.0, BuildView.WALL_HEIGHT]:
				var point := eye.unproject_position(Vector3(x, y, z))
				low = low.min(point)
				high = high.max(point)
	return Rect2(low, high - low)


func _view() -> Rect2:
	return Rect2(Vector2.ZERO, _main.get_viewport().get_visible_rect().size)


## The bottom bar, the hint card or banner, and the open tray stack.
func _hud_rects() -> Dictionary:
	var rects := {"bar": _menu.bar().get_global_rect()}
	var banner: Rect2 = _room().banner_rect.call()
	if banner.has_area():
		rects["banner"] = banner
	if _menu.is_tray_open():
		var tray := _menu.tray().get_global_rect()
		var top := _view().size.y - BuildMenu.tray_stack_top()
		var half := maxf(BuildMenu.COLUMN_W, tray.size.x) / 2.0
		rects["tray_stack"] = Rect2(
			_view().size.x / 2.0 - half, top, half * 2.0, _view().size.y - top
		)
	return rects


func _assert_clear(bounds: Rect2, rects: Dictionary) -> void:
	print("start camera: area %s viewport %s hud %s" % [bounds, _view(), rects])
	(
		assert_bool(_view().encloses(bounds))
		. override_failure_message("area %s is not inside the viewport %s" % [bounds, _view()])
		. is_true()
	)
	for key in rects:
		var rect: Rect2 = rects[key]
		var gap := CLEAR_PX if key == "bar" or key == "tray_stack" else 0.0
		(
			assert_bool(bounds.intersects(rect.grow(gap)))
			. override_failure_message(
				"area %s is not clear of %s %s (gap %s)" % [bounds, key, rect, gap]
			)
			. is_false()
		)


func _assert_fills_free(bounds: Rect2) -> void:
	var free := _room().free_fraction()
	var size := _view().size
	var free_px := Rect2(free.position * size, free.size * size)
	var share := maxf(bounds.size.y / free_px.size.y, bounds.size.x / free_px.size.x)
	print("start camera: fills %.2f of free %s" % [share, free_px])
	assert_float(share).is_greater_equal(FILL)


func test_at_the_start_the_area_is_clear_of_the_bar_and_the_hint_card() -> void:
	_assert_clear(_area_bounds(), _hud_rects())


func test_at_the_start_the_area_fills_the_room_the_hud_leaves() -> void:
	_assert_fills_free(_area_bounds())


func test_with_the_baggage_tray_open_the_area_is_clear_of_the_tray_and_the_card() -> void:
	var baggage := -1
	for i in BuildMenu.categories().size():
		if BuildMenu.bar_name(i) == "Baggage":
			baggage = i
	assert_int(baggage).is_greater_equal(0)
	_menu.press_category(baggage)
	await _settle()
	assert_bool(_menu.is_tray_open()).is_true()
	_assert_clear(_area_bounds(), _hud_rects())
	_assert_fills_free(_area_bounds())
	_menu.press_category(baggage)
