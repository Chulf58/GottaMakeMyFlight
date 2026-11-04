class_name TestBuiltOutline
extends GdUnitTestSuite
## The gold floor frame (BuiltOutline.frame_mesh): drawn outside an object's
## rectangle, inside a room's or car park's, flat at y = 0, in the ring's gold.

const RECT := Rect2(2.0, 3.0, 4.0, 2.0)


func test_an_outside_frame_grows_out_from_the_rectangle() -> void:
	var box := BuiltOutline.frame_mesh(RECT, 0.12, true).get_aabb()
	print("outside frame %s around %s" % [box, RECT])
	assert_float(box.position.x).is_equal_approx(1.88, 0.0001)
	assert_float(box.position.z).is_equal_approx(2.88, 0.0001)
	assert_float(box.size.x).is_equal_approx(4.24, 0.0001)
	assert_float(box.size.z).is_equal_approx(2.24, 0.0001)
	assert_float(box.size.y).is_equal_approx(0.0, 0.0001)


func test_an_inside_frame_stays_within_the_rectangle() -> void:
	var box := BuiltOutline.frame_mesh(RECT, 0.12, false).get_aabb()
	print("inside frame %s within %s" % [box, RECT])
	assert_float(box.position.x).is_equal_approx(2.0, 0.0001)
	assert_float(box.position.z).is_equal_approx(3.0, 0.0001)
	assert_float(box.size.x).is_equal_approx(4.0, 0.0001)
	assert_float(box.size.z).is_equal_approx(2.0, 0.0001)


func test_the_frame_is_a_hollow_ring_of_four_strips() -> void:
	var mesh := BuiltOutline.frame_mesh(RECT, 0.12, false)
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	print("frame vertices %d" % vertices.size())
	# Four strips of two triangles each; every corner is on the outer rectangle
	# or on the inner one, so nothing covers the middle.
	assert_int(vertices.size()).is_equal(24)
	var inner := RECT.grow(-0.12)
	for v in vertices:
		var at := Vector2(v.x, v.z)
		assert_bool(_on_corner(RECT, at) or _on_corner(inner, at)).is_true()


static func _on_corner(rect: Rect2, at: Vector2) -> bool:
	for corner in [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y)
	]:
		if at.is_equal_approx(corner):
			return true
	return false


func test_the_outline_is_the_passenger_rings_gold() -> void:
	assert_object(BuiltOutline.GOLD).is_equal(Color(1.0, 0.85, 0.3))
