class_name TestReachableSeats
extends GdUnitTestSuite
## A restaurant booth with an end against a wall counts only the seats a guest
## can reach (user-ruled 2026-11-04, decision restaurant-booth-against-a-wall-
## counts-only-reachable-seats): the room panel and the venue's seat capacity
## count 2, and the booth's info says "2 of 4 seats reachable". The control is
## the landside booth, open at both ends, which counts all 4 and shows no line.

## The airside booth's anchor: its east end on the room's east edge, so the two
## end cells a guest steps in from at that end are off the floor.
const WALLED_BOOTH := Vector2i(26, 4)
## The landside booth stands where CafeTestLayout puts a 2x3 table.
const OPEN_BOOTH := Vector2i(25, 11)

var _mode: BuildMode
var _world: PassengerTestWorld
var _ids := {}


func before() -> void:
	PassengerTestWorld.tracker = self
	_mode = BuildMode.new()
	add_child(_mode)
	_mode.set_process(false)
	var grid := _mode.grid
	_ids = CafeTestLayout.build(grid, false, &"restaurant", false)
	var at := ReferenceTerminal.offset_on(grid)
	for entry in [["walled", WALLED_BOOTH], ["open", OPEN_BOOTH]]:
		var result := grid.apply(BuildEdit.place_object(&"restaurant_booth", entry[1] + at, 0))
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
		_ids[entry[0]] = result.object_id
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.sim.cafes.refresh()


func after() -> void:
	PassengerTestWorld.tracker = null
	_mode.free()


func test_a_booth_against_a_wall_has_two_reachable_seats_and_the_open_one_four() -> void:
	var walled := RoomRules.reachable_seats(_mode.grid, _ids["walled"])
	var open := RoomRules.reachable_seats(_mode.grid, _ids["open"])
	print("reachable seats: walled booth %d, open booth %d" % [walled.size(), open.size()])
	assert_int(walled.size()).is_equal(2)
	assert_int(open.size()).is_equal(4)
	for seat in walled + open:
		assert_bool(_mode.grid.is_passenger_cell(seat["approach"])).is_true()


## A wall between a seat and its approach cell drops the seat even when the
## cell beyond the wall is indoor floor a guest could stand on.
func test_a_wall_with_floor_beyond_it_still_drops_the_seats_behind_it() -> void:
	var grid := _mode.grid
	var at := ReferenceTerminal.offset_on(grid)
	var cells: Array[Vector2i] = [OPEN_BOOTH + at, OPEN_BOOTH + Vector2i(0, 2) + at]
	for cell in cells:
		var result := grid.apply(BuildEdit.place_wall(cell, BuildGrid.Side.WEST))
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
		# The control: the cell beyond the wall is one a guest may stand on.
		assert_bool(grid.is_passenger_cell(cell + Vector2i.LEFT)).is_true()
	_world.sim.cafes.refresh()
	var reachable := RoomRules.reachable_seats(grid, _ids["open"]).size()
	var room := RoomRules.status(grid, _ids["land_room"]).seats
	var venue: int = _world.sim.cafes.layout.cafe(_ids["land_room"])["seats"].size()
	for cell in cells:
		assert_bool(grid.apply(BuildEdit.remove_wall(cell, BuildGrid.Side.WEST)).ok).is_true()
	_world.sim.cafes.refresh()
	print("walled-off open booth: reachable %d, room %d, venue %d" % [reachable, room, venue])
	assert_int(reachable).is_equal(2)
	assert_int(room).is_equal(2)
	assert_int(venue).is_equal(2)
	assert_int(RoomRules.reachable_seats(grid, _ids["open"]).size()).is_equal(4)


func test_the_room_and_the_venue_count_only_the_reachable_seats() -> void:
	var air := RoomRules.status(_mode.grid, _ids["air_room"])
	var land := RoomRules.status(_mode.grid, _ids["land_room"])
	var air_cafe := _world.sim.cafes.layout.cafe(_ids["air_room"])
	var land_cafe := _world.sim.cafes.layout.cafe(_ids["land_room"])
	print(
		(
			"seats: airside room %d, venue %d; landside room %d, venue %d"
			% [air.seats, air_cafe["seats"].size(), land.seats, land_cafe["seats"].size()]
		)
	)
	assert_bool(air.ok).is_true()
	assert_int(air.seats).is_equal(2)
	assert_int(air_cafe["seats"].size()).is_equal(2)
	assert_int(land.seats).is_equal(4)
	assert_int(land_cafe["seats"].size()).is_equal(4)


func test_the_room_panel_shows_the_reachable_seat_count() -> void:
	var panel := RoomPanel.new()
	add_child(panel)
	panel.watch(_mode)
	panel.show_room(_ids["air_room"])
	var air := _texts(panel)
	panel.show_room(_ids["land_room"])
	var land := _texts(panel)
	print("panel: airside %s, landside %s" % [air, land])
	assert_array(air).contains(["Seats 2"])
	assert_array(land).contains(["Seats 4"])
	panel.free()


func test_the_walled_booths_info_says_two_of_four_seats_reachable() -> void:
	var card := BuiltItemCard.new()
	card.sim = _world.sim
	card.build_mode = _mode
	card.selection = BuiltSelection.new()
	card.selection.kind = BuiltSelection.Kind.OBJECT
	add_child(card)
	card.selection.id = _ids["walled"]
	card.refresh()
	var walled := card.field_text("seats")
	card.selection.id = _ids["open"]
	card.refresh()
	var open := card.field_text("seats")
	print("booth info: walled '%s' (%s), open '%s'" % [walled, card.name_text(), open])
	assert_str(walled).is_equal("2 of 4 seats reachable")
	# The control: every seat of the open booth can be reached, so no line.
	assert_str(card.name_text()).is_equal("Restaurant booth")
	assert_str(open).is_empty()
	card.free()


func _texts(control: Control) -> Array:
	var out := []
	for label in control.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out
