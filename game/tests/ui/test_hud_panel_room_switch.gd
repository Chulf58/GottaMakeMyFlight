class_name TestHudPanelRoomSwitch
extends GdUnitTestSuite
## On the real main scene, the camera makes room once when build mode opens a
## tray, stays put while the player switches between build menus, and gives the
## room back when the tray closes (decision camera-makes-room-once-per-build-
## mode-open-not-on-every-menu-switch).

const SEED := 4_402_028
## Trays with different card counts: Structure (four cards), Check-in (one),
## Lane (four), Cafe (three) and Toilets (a tray of its own). Every tray is
## narrower than BuildMenu.COLUMN_W (the widest, at 568 px, is below its 640), and
## PanelRoom cuts a stack of that fixed width, so the tray's own size cannot move
## the room; the case that does is the banner (the yield case below).
const CATEGORIES := [0, 2, 4, 6, 7]

var _main: Node
var _camera: TycoonCamera
var _eye: Camera3D
var _hud: PassengerHud
var _menu: BuildMenu
var _mode: BuildMode
var _staff: StaffPanel


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_camera = _main.get_node("TycoonCamera")
	_eye = _camera.get_node("Camera3D")
	_hud = _main.get_node("PassengerHud")
	_menu = _main.get_node("BuildMenu")
	_mode = _main.get_node("BuildMode")
	_staff = _main.get_node("StaffPanel")


func after() -> void:
	_main.free()


func before_test() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	if _menu.is_tray_open():
		_menu.press_category(_menu.open_category())
	_staff.set_hint_yielded(false)
	await _settle()
	_camera.frame_start_view(StartView.area_for(_mode.grid), _room().free_fraction())
	_room().mark_sent()


func _room() -> PanelRoom:
	return _hud.get_node("PanelRoom")


## Frames enough for the panels to lay themselves out and PanelRoom to keep the
## build stack (PanelRoom.REFIT_FRAMES), then
## the camera's own easing run out.
func _settle() -> void:
	for i in PanelRoom.REFIT_FRAMES + 2:
		await get_tree().process_frame
	for i in 200:
		_camera._process(0.05)


## What the player sees: where the eye is and how far out, not only the focus.
func _view() -> String:
	return (
		"eye %s focus %s distance %.3f room %s"
		% [_eye.global_position, _camera.position, _camera.distance, _camera.room]
	)


func _assert_same_view(eye: Vector3, distance: float, room: Rect2) -> void:
	assert_vector(_eye.global_position).is_equal_approx(eye, Vector3.ONE * 0.001)
	assert_float(_camera.distance).is_equal_approx(distance, 0.001)
	assert_bool(_camera.room.is_equal_approx(room)).is_true()


func test_opening_build_mode_reframes_once() -> void:
	var eye_before := _eye.global_position
	var distance_before := _camera.distance
	var room_before := _camera.room
	print("closed: ", _view())
	_menu.press_category(CATEGORIES[0])
	await _settle()
	print("opened: ", _view())
	assert_bool(_menu.is_tray_open()).is_true()
	assert_bool(_camera.room.is_equal_approx(room_before)).is_false()
	assert_bool(_eye.global_position.is_equal_approx(eye_before)).is_false()
	assert_float(_camera.distance).is_not_equal(distance_before)


func test_switching_between_build_menus_moves_and_zooms_nothing() -> void:
	_menu.press_category(CATEGORIES[0])
	await _settle()
	var eye := _eye.global_position
	var distance := _camera.distance
	var room := _camera.room
	print("opened on %d: %s" % [CATEGORIES[0], _view()])
	for category in CATEGORIES.slice(1):
		_menu.press_category(category)
		await _settle()
		print("switched to %d (tray %s): %s" % [category, _menu.tray().get_global_rect(), _view()])
		assert_int(_menu.open_category()).is_equal(category)
		_assert_same_view(eye, distance, room)


func test_a_hint_taking_the_banner_slot_on_a_switch_moves_nothing() -> void:
	_menu.press_category(CATEGORIES[0])
	await _settle()
	var eye := _eye.global_position
	var distance := _camera.distance
	var room := _camera.room
	assert_bool(_staff.hint_card().is_visible_in_tree()).is_true()
	# Hints hides the banner while a first-time hint holds its slot.
	_menu.press_category(CATEGORIES[1])
	_staff.set_hint_yielded(true)
	await _settle()
	print("banner yielded: ", _view())
	assert_bool(_staff.hint_card().is_visible_in_tree()).is_false()
	_assert_same_view(eye, distance, room)
	_menu.press_category(CATEGORIES[2])
	_staff.set_hint_yielded(false)
	await _settle()
	print("banner back: ", _view())
	_assert_same_view(eye, distance, room)


func test_closing_the_tray_after_switching_gives_the_screen_back() -> void:
	var eye_before := _eye.global_position
	var distance_before := _camera.distance
	var room_before := _camera.room
	_menu.press_category(CATEGORIES[0])
	await _settle()
	for category in CATEGORIES.slice(1):
		_menu.press_category(category)
		await _settle()
	_menu.press_category(CATEGORIES[-1])
	await _settle()
	print("closed again: ", _view())
	assert_bool(_menu.is_tray_open()).is_false()
	_assert_same_view(eye_before, distance_before, room_before)
