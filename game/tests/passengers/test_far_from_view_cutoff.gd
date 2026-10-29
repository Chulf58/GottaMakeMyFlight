class_name TestFarFromViewCutoff
extends GdUnitTestSuite
## MissMarkers._far_from_view: a lane hint's sign point is far when it is MORE
## than one caption width outside the view. A point exactly one width out is
## still near, on all four edges alike (Rect2.has_point was inclusive on the
## left and top and exclusive on the right and bottom).

const TEXT := "Needs a scanner"
const VIEW := Vector2(1920.0, 1080.0)
const MIDDLE := Vector2(960.0, 540.0)

var _w := 0.0


func before() -> void:
	_w = MissMarkers.caption_size(TEXT).x


func _far(point: Vector2) -> bool:
	return MissMarkers._far_from_view(point, TEXT, VIEW)


func test_the_cutoff_width_is_a_real_distance() -> void:
	assert_float(_w).is_greater(1.0)


func test_a_point_in_the_view_is_near() -> void:
	assert_bool(_far(MIDDLE)).is_false()


func test_a_point_exactly_one_width_past_each_edge_is_near() -> void:
	for point: Vector2 in [
		Vector2(-_w, MIDDLE.y),
		Vector2(VIEW.x + _w, MIDDLE.y),
		Vector2(MIDDLE.x, -_w),
		Vector2(MIDDLE.x, VIEW.y + _w),
	]:
		print("on the edge %s far %s" % [point, _far(point)])
		assert_bool(_far(point)).is_false()


func test_a_point_one_unit_inside_each_cutoff_is_near() -> void:
	for point: Vector2 in [
		Vector2(-_w + 1.0, MIDDLE.y),
		Vector2(VIEW.x + _w - 1.0, MIDDLE.y),
		Vector2(MIDDLE.x, -_w + 1.0),
		Vector2(MIDDLE.x, VIEW.y + _w - 1.0),
	]:
		assert_bool(_far(point)).is_false()


func test_a_point_one_unit_outside_each_cutoff_is_far() -> void:
	for point: Vector2 in [
		Vector2(-_w - 1.0, MIDDLE.y),
		Vector2(VIEW.x + _w + 1.0, MIDDLE.y),
		Vector2(MIDDLE.x, -_w - 1.0),
		Vector2(MIDDLE.x, VIEW.y + _w + 1.0),
	]:
		print("outside %s far %s" % [point, _far(point)])
		assert_bool(_far(point)).is_true()


func test_a_corner_is_far_when_either_axis_is_past_its_cutoff() -> void:
	assert_bool(_far(Vector2(VIEW.x + _w + 1.0, VIEW.y + _w))).is_true()
	assert_bool(_far(Vector2(VIEW.x + _w, VIEW.y + _w + 1.0))).is_true()
	assert_bool(_far(Vector2(VIEW.x + _w, VIEW.y + _w))).is_false()
	assert_bool(_far(Vector2(-_w, -_w))).is_false()
