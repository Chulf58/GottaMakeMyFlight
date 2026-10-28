class_name TestReferenceTerminalIds
extends GdUnitTestSuite
## ReferenceTerminal.object_ids on a grid that also holds baggage belts: the
## belt pieces have their own list instead of failing the lookup by kind.


func test_belt_pieces_are_listed_apart_from_the_terminal_objects() -> void:
	var plain := BuildGrid.new()
	assert_bool(ReferenceTerminal.build(plain)).is_true()
	var expected := ReferenceTerminal.object_ids(plain)
	var grid := BuildGrid.new()
	assert_bool(ReferenceTerminal.build(grid)).is_true()
	var straight := PassengerTestWorld.place(grid, &"baggage_belt", Vector2i(20, 12), 0)
	var corner := PassengerTestWorld.place(grid, &"baggage_belt_corner", Vector2i(20, 13), 0)
	var feed := PassengerTestWorld.place(grid, &"baggage_belt_feed", Vector2i(20, 14), 0)
	var end := PassengerTestWorld.place(grid, &"baggage_belt_end", Vector2i(20, 15), 0)
	var ids := ReferenceTerminal.object_ids(grid)
	assert_array(ids["belts"]).is_equal([straight, corner, feed, end])
	for kind in ["desks", "scanners", "seats", "entrances", "exits"]:
		assert_array(ids[kind]).is_equal(expected[kind])
