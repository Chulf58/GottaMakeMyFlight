class_name TestHudPanelRoom
extends GdUnitTestSuite
## On the real main scene, opening the build tray, the Staff card or the Offers
## sheet gives the camera a smaller free share of the screen, and the start
## area stays inside it (decision camera-makes-room-for-open-panels-the-build-
## tray-banner-and). Closing the panel gives the screen back; a build edit
## moves nothing.

const SEED := 4_402_027

var _main: Node
var _camera: TycoonCamera
var _hud: PassengerHud
var _menu: BuildMenu
var _staff: StaffPanel
var _offers: OfferPanel
var _mode: BuildMode


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_camera = _main.get_node("TycoonCamera")
	_hud = _main.get_node("PassengerHud")
	_menu = _main.get_node("BuildMenu")
	_staff = _main.get_node("StaffPanel")
	_offers = _main.get_node("OfferPanel")
	_mode = _main.get_node("BuildMode")


func after() -> void:
	_main.free()


func before_test() -> void:
	_offers.close()
	_mode.set_tool(BuildMode.Tool.NONE)
	if _menu.staff_open:
		_menu.press_staff()
	await _settle()
	_camera.frame_start_view(StartView.area_for(_mode.grid), _room().free_fraction())
	_room().mark_sent()


func _room() -> PanelRoom:
	return _hud.get_node("PanelRoom")


## A few frames, so the panels lay themselves out and PanelRoom reports.
func _settle() -> void:
	for i in 4:
		await get_tree().process_frame
	for i in 200:
		_camera._process(0.05)


func _area_corners() -> Array[Vector2]:
	var area := StartView.area_for(_mode.grid)
	var eye: Camera3D = _camera.get_node("Camera3D")
	var out: Array[Vector2] = []
	for x in [area.position.x, area.end.x]:
		for z in [area.position.y, area.end.y]:
			out.append(eye.unproject_position(Vector3(x, 0.0, z)))
	return out


func _assert_corners_inside(pixels: Rect2) -> void:
	for corner in _area_corners():
		(
			assert_bool(pixels.grow(2.0).has_point(corner))
			. override_failure_message("corner %s is outside the free area %s" % [corner, pixels])
			. is_true()
		)


func _free_pixels() -> Rect2:
	var size := get_viewport().get_visible_rect().size
	var free := _room().free_fraction()
	return Rect2(free.position * size, free.size * size)


func test_with_the_tray_open_the_terminal_is_above_it() -> void:
	_menu.press_category(0)
	await _settle()
	assert_bool(_menu.is_tray_open()).is_true()
	var tray_top := _menu.tray().get_global_rect().position.y
	assert_float(_free_pixels().end.y).is_less_equal(tray_top)
	_assert_corners_inside(_free_pixels())
	for corner in _area_corners():
		assert_float(corner.y).is_less(tray_top)


func test_with_the_staff_card_open_the_terminal_is_above_it() -> void:
	_menu.press_staff()
	await _settle()
	var card_top := _staff.card().get_global_rect().position.y
	assert_float(_free_pixels().end.y).is_less_equal(card_top)
	_assert_corners_inside(_free_pixels())


func test_with_the_offers_sheet_open_the_terminal_is_beside_it() -> void:
	_offers.open()
	await _settle()
	var sheet := _offers.sheet().get_global_rect()
	var free := _free_pixels()
	assert_bool(free.intersects(sheet)).is_false()
	_assert_corners_inside(free)


func test_closing_the_tray_gives_the_screen_back() -> void:
	var before_room := _camera.room
	_menu.press_category(0)
	await _settle()
	assert_bool(_camera.room.is_equal_approx(before_room)).is_false()
	_menu.press_category(0)
	await _settle()
	assert_bool(_camera.room.is_equal_approx(before_room)).is_true()


func test_a_build_edit_moves_nothing() -> void:
	_menu.press_category(0)
	await _settle()
	var home := _camera.home_position
	var at := _camera.position
	var distance := _camera.home_distance
	var result := _mode.grid.apply(BuildEdit.paint_floor(Vector2i(3, 3), BuildGrid.FLOOR_TILE, 1))
	assert_bool(result.ok).is_true()
	await _settle()
	assert_vector(_camera.home_position).is_equal(home)
	assert_vector(_camera.position).is_equal(at)
	assert_float(_camera.home_distance).is_equal(distance)
