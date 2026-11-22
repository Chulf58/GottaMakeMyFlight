class_name TestStartCameraClear
extends GdUnitTestSuite
## On the real main scene, the start camera frames the built area (ground and
## wall tops) inside the viewport clear of the bottom HUD bar and the hint
## card at WHOLE_VIEW, and stays steady when the build tray opens (decision
## panel-room-camera-shifting-disabled-camera-stays-steady-for-panels-and-
## alerts, 66acd8b0, overriding PanelRoom shifting from 9a761a26/7451f197).

const SEED := 4_402_028
const SCREEN := Vector2i(1536, 864)
const SIZES: Array[Vector2i] = [
	Vector2i(1536, 864),
	Vector2i(1280, 720),
	Vector2i(1280, 1024),
]
## Pixels the framed area keeps from the bottom bar, so the entrance end never
## touches or sits tight against it.
const CLEAR_PX := 20.0
## The least share of the viewport height or width the framed area fills.
const FILL := 0.6

var _screen: SubViewport
var _main: Node
var _camera: TycoonCamera
var _eye: Camera3D
var _hud: PassengerHud
var _menu: BuildMenu
var _mode: BuildMode


func before() -> void:
	# The game's own 16:9 size, not whatever the test runner's window is.
	_screen = SubViewport.new()
	_screen.size = SCREEN
	add_child(_screen)
	_main = SaveTestKit.boot(_screen, SEED)
	_camera = _main.get_node("TycoonCamera")
	_eye = _camera.get_node("Camera3D")
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


## The bottom bar and the hint card or banner.
func _hud_rects() -> Dictionary:
	var rects := {"bar": _menu.bar().get_global_rect()}
	var banner: Rect2 = _room().banner_rect.call()
	if banner.has_area():
		rects["banner"] = banner
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
		var gap := CLEAR_PX if key == "bar" else 0.0
		(
			assert_bool(bounds.intersects(rect.grow(gap)))
			. override_failure_message(
				"area %s is not clear of %s %s (gap %s)" % [bounds, key, rect, gap]
			)
			. is_false()
		)


func _assert_fills_viewport(bounds: Rect2) -> void:
	var size := _view().size
	var share := maxf(bounds.size.y / size.y, bounds.size.x / size.x)
	print("start camera: fills %.2f of viewport %s" % [share, size])
	assert_float(share).is_greater_equal(FILL)


func test_at_the_start_the_area_is_clear_of_the_bar_and_the_hint_card() -> void:
	assert_bool(_camera.room.is_equal_approx(TycoonCamera.WHOLE_VIEW)).is_true()
	_assert_clear(_area_bounds(), _hud_rects())


func test_the_start_area_clears_the_bar_and_hint_across_supported_sizes() -> void:
	for size in SIZES:
		_screen.size = size
		await _settle()
		_camera.frame_start_view(StartView.area_for(_mode.grid))
		await _settle()
		assert_bool(_camera.room.is_equal_approx(TycoonCamera.WHOLE_VIEW)).is_true()
		_assert_clear(_area_bounds(), _hud_rects())
	_screen.size = SCREEN
	await _settle()
	_camera.frame_start_view(StartView.area_for(_mode.grid))


func test_at_the_start_the_area_fills_the_viewport() -> void:
	assert_bool(_camera.room.is_equal_approx(TycoonCamera.WHOLE_VIEW)).is_true()
	_assert_fills_viewport(_area_bounds())


func test_with_the_operations_tray_open_the_camera_stays_steady() -> void:
	var operations := BuildMenu.category_index("operations")
	assert_int(operations).is_greater_equal(0)
	var before_bounds := _area_bounds()
	var before_pos := _camera.position
	var before_eye := _eye.global_position
	var before_dist := _camera.distance
	_menu.press_category(operations)
	await _settle()
	assert_bool(_menu.is_tray_open()).is_true()
	assert_bool(_camera.room.is_equal_approx(TycoonCamera.WHOLE_VIEW)).is_true()
	assert_vector(_camera.position).is_equal_approx(before_pos, Vector3.ONE * 0.001)
	assert_vector(_eye.global_position).is_equal_approx(before_eye, Vector3.ONE * 0.001)
	assert_float(_camera.distance).is_equal_approx(before_dist, 0.001)
	var after_bounds := _area_bounds()
	assert_vector(after_bounds.position).is_equal_approx(before_bounds.position, Vector2.ONE * 0.1)
	assert_vector(after_bounds.size).is_equal_approx(before_bounds.size, Vector2.ONE * 0.1)
	_menu.press_category(operations)
