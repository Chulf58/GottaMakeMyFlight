class_name TestSelectReveal
extends GdUnitTestSuite
## SelectReveal: a selected built item keeps the camera still while it is on
## screen and clear of the panels, and pans just enough to show it otherwise
## (decision clicking-a-built-desk-outside-build-mode-moves-the-camera-on).

const VIEW := Rect2(0.0, 0.0, 1920.0, 1080.0)
## The inspect window at the bottom left.
const WINDOW := Rect2(16.0, 700.0, 420.0, 260.0)
## A desk-sized footprint on the floor, in world metres (x, z).
const DESK := Rect2(-0.5, -0.5, 1.0, 1.0)

var _eye: Camera3D


func before_test() -> void:
	_eye = auto_free(Camera3D.new())
	add_child(_eye)
	_eye.make_current()
	_look_at(Vector3.ZERO)


func _look_at(target: Vector3) -> void:
	_eye.look_at_from_position(target + Vector3(0.0, 30.0, 4.0), target)


func _viewport() -> Rect2:
	return get_viewport().get_visible_rect()


## The screen box of the desk seen from the eye, as the reveal measures it.
func _box() -> Rect2:
	return SelectReveal.screen_box(_eye, DESK, 0.0)


## Moves the eye by the ground shift a target asks for, as the camera glide ends.
func _apply(focus: Vector3, target: Vector3) -> void:
	_eye.global_position += target - focus


func _middle_window() -> Rect2:
	return Rect2(_viewport().size / 2.0 - Vector2(200.0, 120.0), Vector2(400.0, 240.0))


func test_a_box_in_view_and_clear_needs_no_shift() -> void:
	var box := Rect2(900.0, 400.0, 100.0, 100.0)
	assert_that(SelectReveal.shift_for(box, VIEW, [WINDOW])).is_equal(Vector2.ZERO)


func test_a_box_off_the_left_edge_is_pulled_in() -> void:
	var box := Rect2(-80.0, 400.0, 100.0, 100.0)
	var shift := SelectReveal.shift_for(box, VIEW, [])
	assert_float(shift.x).is_greater_equal(80.0)
	assert_float(shift.y).is_equal(0.0)
	assert_bool(VIEW.encloses(Rect2(box.position + shift, box.size))).is_true()


func test_a_box_under_the_window_is_moved_clear_of_it() -> void:
	var box := Rect2(100.0, 760.0, 100.0, 100.0)
	var shift := SelectReveal.shift_for(box, VIEW, [WINDOW])
	assert_bool(shift != Vector2.ZERO).is_true()
	var moved := Rect2(box.position + shift, box.size)
	assert_bool(moved.intersects(WINDOW)).is_false()
	assert_bool(VIEW.encloses(moved)).is_true()


func test_a_box_larger_than_the_free_space_is_centred_in_it() -> void:
	var box := Rect2(-400.0, -400.0, 3000.0, 1800.0)
	var free := PanelRoom.free_rect(VIEW, [WINDOW]).grow(-SelectReveal.MARGIN)
	var shift := SelectReveal.shift_for(box, VIEW, [WINDOW])
	var centre_gap := (box.get_center() + shift) - free.get_center()
	assert_float(centre_gap.length()).is_less(0.01)


func test_an_item_in_view_and_clear_does_not_move_the_camera() -> void:
	var target: Variant = SelectReveal.focus_target(_eye, Vector3.ZERO, DESK, 0.0, _viewport(), [])
	assert_bool(target == null).is_true()


func test_an_item_off_screen_pans_so_it_is_on_screen_and_clear() -> void:
	var focus := Vector3(60.0, 0.0, 0.0)
	_look_at(focus)
	var target: Variant = SelectReveal.focus_target(_eye, focus, DESK, 0.0, _viewport(), [])
	assert_bool(target != null).is_true()
	_apply(focus, target)
	var box := _box()
	print("off screen item box after the pan %s in %s" % [box, _viewport()])
	assert_bool(_viewport().encloses(box)).is_true()


func test_an_item_under_the_window_pans_clear_of_it() -> void:
	var window := _middle_window()
	var panels: Array[Rect2] = [window]
	var target: Variant = SelectReveal.focus_target(
		_eye, Vector3.ZERO, DESK, 0.0, _viewport(), panels
	)
	assert_bool(target != null).is_true()
	_apply(Vector3.ZERO, target)
	var box := _box()
	print("under window item box after the pan %s, window %s" % [box, window])
	assert_bool(box.intersects(window)).is_false()
	assert_bool(_viewport().encloses(box)).is_true()


func test_a_pan_stays_on_the_ground_plane() -> void:
	var panels: Array[Rect2] = [_middle_window()]
	var target: Variant = SelectReveal.focus_target(
		_eye, Vector3.ZERO, DESK, 0.0, _viewport(), panels
	)
	assert_bool(target != null).is_true()
	assert_float((target as Vector3).y).is_equal(0.0)
