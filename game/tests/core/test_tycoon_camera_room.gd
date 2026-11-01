class_name TestTycoonCameraRoom
extends GdUnitTestSuite
## The camera frames the start area inside the screen share the open HUD
## panels leave free (decision camera-makes-room-for-open-panels-the-build-
## tray-banner-and), and eases its focus there when a panel opens.

## A 12 by 16 m area, the size of the starter shell's floor.
const AREA := Rect2(Vector2(-6.0, -88.0), Vector2(12.0, 16.0))
## The share left when a side panel covers the right 40% of the screen.
const BESIDE_PANEL := Rect2(0.0, 0.0, 0.6, 1.0)
## The share left when a tray covers the bottom 40%.
const ABOVE_TRAY := Rect2(0.0, 0.0, 1.0, 0.6)

var _rig: TycoonCamera
var _cam: Camera3D


func before_test() -> void:
	var scene: PackedScene = load("res://camera/tycoon_camera.tscn")
	_rig = auto_free(scene.instantiate()) as TycoonCamera
	add_child(_rig)
	_cam = _rig.get_node("Camera3D")


## Where the area's four ground corners are on screen, as fractions of the
## viewport.
func _corners() -> Array[Vector2]:
	var size := _rig.get_viewport().get_visible_rect().size
	var out: Array[Vector2] = []
	for x in [AREA.position.x, AREA.end.x]:
		for z in [AREA.position.y, AREA.end.y]:
			var world := Vector3(x, 0.0, z)
			assert_bool(_cam.is_position_behind(world)).is_false()
			out.append(_cam.unproject_position(world) / size)
	return out


## How tall the area is on screen, as a fraction of the viewport height.
func _span() -> float:
	var ys: Array[float] = []
	for corner in _corners():
		ys.append(corner.y)
	return ys.max() - ys.min()


func _assert_inside(free: Rect2) -> void:
	for corner in _corners():
		(
			assert_bool(free.grow(0.001).has_point(corner))
			. override_failure_message("corner %s is outside the free share %s" % [corner, free])
			. is_true()
		)


func test_with_a_side_panel_open_the_area_stays_beside_it() -> void:
	_rig.frame_start_view(AREA, BESIDE_PANEL)
	_assert_inside(BESIDE_PANEL)


func test_with_the_tray_open_the_area_stays_above_it() -> void:
	_rig.frame_start_view(AREA, ABOVE_TRAY)
	_assert_inside(ABOVE_TRAY)


func test_with_a_panel_in_a_corner_the_area_stays_in_the_free_share() -> void:
	var free := Rect2(0.1, 0.05, 0.5, 0.55)
	_rig.frame_start_view(AREA, free)
	_assert_inside(free)


func test_a_side_panel_backs_the_camera_off_further() -> void:
	var whole := _rig.framing_for(AREA)
	var beside := _rig.framing_for(AREA, BESIDE_PANEL)
	assert_float(beside["distance"]).is_greater(whole["distance"])


func test_less_room_shows_the_area_smaller() -> void:
	_rig.frame_start_view(AREA)
	var span_whole := _span()
	_rig.frame_start_view(AREA, ABOVE_TRAY)
	assert_float(_span()).is_less(span_whole)


func test_the_whole_view_is_the_framing_it_always_was() -> void:
	var view := _rig.framing_for(AREA)
	assert_vector(view["position"]).is_equal_approx(Vector3(0.0, 0.0, -80.0), Vector3.ONE * 0.001)
	assert_float(view["distance"]).is_equal_approx(
		_rig.framing_for(AREA, TycoonCamera.WHOLE_VIEW)["distance"], 0.0001
	)


func test_the_framed_position_is_the_areas_middle_whatever_is_open() -> void:
	var view := _rig.framing_for(AREA, ABOVE_TRAY)
	assert_vector(view["position"]).is_equal_approx(Vector3(0.0, 0.0, -80.0), Vector3.ONE * 0.001)


func test_opening_a_panel_on_the_start_view_refits_the_distance() -> void:
	_rig.frame_start_view(AREA)
	var before_distance := _rig.target_distance
	_rig.set_room(ABOVE_TRAY)
	assert_float(_rig.target_distance).is_not_equal(before_distance)
	assert_float(_rig.home_distance).is_equal_approx(_rig.target_distance, 0.0001)
	for i in 200:
		_rig._process(0.05)
	_assert_inside(ABOVE_TRAY)


func test_closing_the_panel_gives_the_view_back() -> void:
	_rig.frame_start_view(AREA)
	var whole := _rig.target_distance
	_rig.set_room(ABOVE_TRAY)
	_rig.set_room(TycoonCamera.WHOLE_VIEW)
	assert_float(_rig.target_distance).is_equal_approx(whole, 0.0001)
	for i in 200:
		_rig._process(0.05)
	assert_bool(_rig.room.is_equal_approx(TycoonCamera.WHOLE_VIEW)).is_true()
	_assert_inside(TycoonCamera.WHOLE_VIEW)


func test_a_panel_does_not_move_the_focus_point_only_the_view() -> void:
	_rig.frame_start_view(AREA)
	var focus := _rig.position
	_rig.set_room(ABOVE_TRAY)
	for i in 200:
		_rig._process(0.05)
	assert_vector(_rig.position).is_equal_approx(focus, Vector3.ONE * 0.001)
	# The focus is at the middle of the free share, not of the screen.
	var size := _rig.get_viewport().get_visible_rect().size
	var on_screen := _cam.unproject_position(focus) / size
	assert_float(on_screen.y).is_equal_approx(0.3, 0.01)
	assert_float(on_screen.x).is_equal_approx(0.5, 0.01)


func test_after_the_player_zooms_a_panel_only_shifts_the_view() -> void:
	_rig.frame_start_view(AREA)
	_rig.zoom(2.0)
	var wanted := _rig.target_distance
	_rig.set_room(ABOVE_TRAY)
	assert_float(_rig.target_distance).is_equal(wanted)
	for i in 200:
		_rig._process(0.05)
	var size := _rig.get_viewport().get_visible_rect().size
	assert_float((_cam.unproject_position(_rig.position) / size).y).is_equal_approx(0.3, 0.01)


func test_a_panel_resizing_moves_the_view_without_zooming_it() -> void:
	_rig.frame_start_view(AREA, ABOVE_TRAY)
	var wanted := _rig.target_distance
	_rig.set_room(Rect2(0.0, 0.0, 1.0, 0.55), false)
	assert_float(_rig.target_distance).is_equal(wanted)
	assert_bool(_rig.is_gliding()).is_false()


func test_home_fits_the_area_to_the_panels_open_now() -> void:
	_rig.frame_start_view(AREA)
	_rig.glide_to(Vector3(100.0, 0.0, 100.0), 150.0)
	_rig.set_room(ABOVE_TRAY, false)
	_rig.go_home()
	assert_float(_rig.home_distance).is_equal_approx(
		_rig.framing_for(AREA, ABOVE_TRAY)["distance"], 0.0001
	)
	for i in 600:
		_rig._process(0.05)
	_assert_inside(ABOVE_TRAY)
