class_name TestHudPanelRoom
extends GdUnitTestSuite
## On the real main scene, opening or closing the build tray, the Staff card or
## the Offers sheet, or applying a build edit, leaves TycoonCamera completely
## steady at WHOLE_VIEW (decision panel-room-camera-shifting-disabled-camera-
## stays-steady-for-panels-and-alerts, superseding 7451f197/77fa8631).

const SEED := 4_402_027

var _main: Node
var _camera: TycoonCamera
var _eye: Camera3D
var _hud: PassengerHud
var _menu: BuildMenu
var _staff: StaffPanel
var _offers: OfferPanel
var _mode: BuildMode


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_camera = _main.get_node("TycoonCamera")
	_eye = _camera.get_node("Camera3D")
	_hud = _main.get_node("PassengerHud")
	_menu = _main.get_node("BuildMenu")
	_staff = _main.get_node("StaffPanel")
	_offers = _main.get_node("OfferPanel")
	_mode = _main.get_node("BuildMode")
	# The build edit here paints floor off a new game's land, and building on land
	# the player does not own is refused (LandPlots), so the whole site is owned.
	LandKit.own_all(_mode.land_tool.land)


func after() -> void:
	_main.free()


func before_test() -> void:
	_offers.close()
	_mode.set_tool(BuildMode.Tool.NONE)
	if _menu.staff_open:
		_menu.press_staff()
	await _settle()
	_camera.frame_start_view(StartView.area_for(_mode.grid))
	_room().mark_sent()


func _room() -> PanelRoom:
	return _hud.get_node("PanelRoom")


## A few frames, so the panels lay themselves out and any camera easing runs out.
func _settle() -> void:
	for i in 4:
		await get_tree().process_frame
	for i in 200:
		_camera._process(0.05)


func _assert_steady(before_pos: Vector3, before_eye: Vector3, before_dist: float) -> void:
	assert_bool(_camera.room.is_equal_approx(TycoonCamera.WHOLE_VIEW)).is_true()
	assert_vector(_camera.position).is_equal_approx(before_pos, Vector3.ONE * 0.001)
	assert_vector(_eye.global_position).is_equal_approx(before_eye, Vector3.ONE * 0.001)
	assert_float(_camera.distance).is_equal_approx(before_dist, 0.001)
	assert_float(_camera.target_distance).is_equal_approx(before_dist, 0.001)


func test_with_the_tray_open_the_camera_stays_steady() -> void:
	var before_pos := _camera.position
	var before_eye := _eye.global_position
	var before_dist := _camera.distance
	_menu.press_category(0)
	await _settle()
	assert_bool(_menu.is_tray_open()).is_true()
	_assert_steady(before_pos, before_eye, before_dist)


func test_with_the_staff_card_open_the_camera_stays_steady() -> void:
	var before_pos := _camera.position
	var before_eye := _eye.global_position
	var before_dist := _camera.distance
	_menu.press_staff()
	await _settle()
	assert_bool(_staff.card().is_visible_in_tree()).is_true()
	_assert_steady(before_pos, before_eye, before_dist)


func test_with_the_offers_sheet_open_the_camera_stays_steady() -> void:
	var flights := _main.get_node("FlightSim") as FlightSim
	if flights.opened_tick < 0:
		flights.open_airport()
		await await_idle_frame()
	var before_pos := _camera.position
	var before_eye := _eye.global_position
	var before_dist := _camera.distance
	_offers.open()
	await _settle()
	assert_bool(_offers.is_open()).is_true()
	_assert_steady(before_pos, before_eye, before_dist)


func test_opening_and_closing_the_tray_keeps_the_whole_view() -> void:
	var before_pos := _camera.position
	var before_eye := _eye.global_position
	var before_dist := _camera.distance
	_menu.press_category(0)
	await _settle()
	assert_bool(_menu.is_tray_open()).is_true()
	_assert_steady(before_pos, before_eye, before_dist)
	_menu.press_category(0)
	await _settle()
	assert_bool(_menu.is_tray_open()).is_false()
	_assert_steady(before_pos, before_eye, before_dist)


func test_a_build_edit_moves_nothing() -> void:
	_menu.press_category(0)
	await _settle()
	var home := _camera.home_position
	var at := _camera.position
	var eye := _eye.global_position
	var distance := _camera.home_distance
	var result := _mode.grid.apply(BuildEdit.paint_floor(Vector2i(3, 3), BuildGrid.FLOOR_TILE, 1))
	assert_bool(result.ok).is_true()
	await _settle()
	assert_bool(_camera.room.is_equal_approx(TycoonCamera.WHOLE_VIEW)).is_true()
	assert_vector(_camera.home_position).is_equal(home)
	assert_vector(_camera.position).is_equal(at)
	assert_vector(_eye.global_position).is_equal_approx(eye, Vector3.ONE * 0.001)
	assert_float(_camera.home_distance).is_equal(distance)
