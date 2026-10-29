class_name TestToiletLayout
extends GdUnitTestSuite
## ToiletLayout (decision toilet-design-queue-free-reservable-stalls-per-
## stall-daily-u, point 1; kit decision toilet-stall-kit-piece-1x2-footprint-
## side-partitions-out-to): the usable stalls are the toilet_stall pieces of
## ready toilet rooms, each with its approach cell in front, the turn spot
## (Mount_Turn, 0.35 m out from the footprint centre) in the front cell and
## the use spot (Mount_Use, 0.05 m back from it) just inside the rear cell.


func _turned_world() -> BuildGrid:
	var grid := PassengerTestWorld.floored(Vector2i(10, 10))
	_apply(grid, BuildEdit.place_room(Rect2i(2, 2, 5, 4), &"toilet"))
	# Facing 1 turns the stall's front from +y to -x: footprint (5, 3) and
	# (4, 3), approach (3, 3).
	PassengerTestWorld.place(grid, &"toilet_stall", Vector2i(5, 3), 1)
	PassengerTestWorld.place(grid, &"toilet_sink", Vector2i(2, 2), 0)
	return grid


func _apply(grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	var result := grid.apply(edit)
	assert(result.ok, "toilet layout edit refused: %s" % result.reason_text())
	return result


func test_a_ready_room_lists_each_stall_with_its_cells_and_spots() -> void:
	var grid := BuildGrid.new()
	var ids := ToiletTestLayout.build(grid)
	var layout := ToiletLayout.new()
	layout.rebuild(grid)
	print("stalls %s" % [layout.stalls])
	assert_int(layout.stalls.size()).is_equal(4)
	var air: Array = ids["air_stalls"]
	var first := layout.stall(air[0])
	assert_int(first["room"]).is_equal(ids["air_room"])
	assert_that(first["use_cell"]).is_equal(Vector2i(23, 3))
	assert_that(first["turn_cell"]).is_equal(Vector2i(23, 4))
	assert_that(first["approach"]).is_equal(Vector2i(23, 5))
	assert_that(first["front"]).is_equal(Vector2i(0, 1))
	# The footprint centre is the edge between y 3 and y 4, 4.0 m from the
	# origin along z, 23.5 m along x.
	var centre := grid.origin + Vector3(23.5, 0.0, 4.0)
	assert_float(first["turn"].distance_to(centre + Vector3(0.0, 0.0, 0.35))).is_less(0.0001)
	assert_float(first["use"].distance_to(centre + Vector3(0.0, 0.0, -0.05))).is_less(0.0001)
	# In room id order, then object id order.
	var order: Array = []
	for stall in layout.stalls:
		order.append(stall["id"])
	assert_array(order).is_equal(air + ids["land_stalls"])


func test_a_room_that_is_not_ready_has_no_usable_stalls() -> void:
	var grid := BuildGrid.new()
	var ids := ToiletTestLayout.build(grid)
	_apply(grid, BuildEdit.remove_object(ids["air_sink"]))
	var layout := ToiletLayout.new()
	layout.rebuild(grid)
	var rooms: Array = []
	for stall in layout.stalls:
		rooms.append(stall["room"])
	print("rooms with stalls %s" % [rooms])
	assert_int(layout.stalls.size()).is_equal(2)
	assert_array(rooms).is_equal([ids["land_room"], ids["land_room"]])
	assert_dict(layout.stall(ids["air_stalls"][0])).is_empty()


func test_a_turned_stall_turns_its_cells_and_spots() -> void:
	var grid := _turned_world()
	var layout := ToiletLayout.new()
	layout.rebuild(grid)
	assert_int(layout.stalls.size()).is_equal(1)
	var stall: Dictionary = layout.stalls[0]
	print("turned stall %s" % [stall])
	assert_that(stall["front"]).is_equal(Vector2i(-1, 0))
	assert_that(stall["use_cell"]).is_equal(Vector2i(5, 3))
	assert_that(stall["turn_cell"]).is_equal(Vector2i(4, 3))
	assert_that(stall["approach"]).is_equal(Vector2i(3, 3))
	var centre := grid.origin + Vector3(5.0, 0.0, 3.5)
	assert_float(stall["turn"].distance_to(centre + Vector3(-0.35, 0.0, 0.0))).is_less(0.0001)
	assert_float(stall["use"].distance_to(centre + Vector3(0.05, 0.0, 0.0))).is_less(0.0001)
