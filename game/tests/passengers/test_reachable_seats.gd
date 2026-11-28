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


## A door between a seat and floor outside the enclosure: a guest may not
## stand there (BuildGrid.is_passenger_cell), so the room and the venue both
## drop the seat. Built on its own grid, since it opens the enclosure.
func test_a_door_to_floor_outside_the_enclosure_drops_the_seats_behind_it() -> void:
	var grid := BuildGrid.new()
	var ids := CafeTestLayout.build(grid, false, &"restaurant", false)
	var at := ReferenceTerminal.offset_on(grid)
	var booth := grid.apply(BuildEdit.place_object(&"restaurant_booth", WALLED_BOOTH + at, 0))
	assert_bool(booth.ok).override_failure_message(booth.reason_text()).is_true()
	var seat_cells: Array[Vector2i] = [WALLED_BOOTH + Vector2i(1, 0), WALLED_BOOTH + Vector2i(1, 2)]
	for seat_cell in seat_cells:
		var cell := seat_cell + at
		var edits: Array[BuildEdit] = [
			BuildEdit.remove_wall(cell, BuildGrid.Side.EAST),
			BuildEdit.place_wall(cell, BuildGrid.Side.EAST, BuildGrid.WallKind.DOOR),
			BuildEdit.paint_floor(cell + Vector2i.RIGHT, BuildGrid.FLOOR_TILE, 1),
		]
		for result in grid.apply_batch(edits):
			assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	# The controls: a door, and walkable floor beyond it that is not indoor.
	for seat_cell in seat_cells:
		var beyond := seat_cell + at + Vector2i.RIGHT
		print(
			(
				"door at %s: kind %d, beyond walkable %s, indoor %s"
				% [
					seat_cell + at,
					grid.wall_kind(seat_cell + at, BuildGrid.Side.EAST),
					grid.is_walkable(beyond),
					grid.is_indoor(beyond),
				]
			)
		)
		assert_int(grid.wall_kind(seat_cell + at, BuildGrid.Side.EAST)).is_equal(
			BuildGrid.WallKind.DOOR
		)
		assert_bool(grid.is_walkable(beyond)).is_true()
		assert_bool(grid.is_indoor(beyond)).is_false()
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	world.sim.cafes.refresh()
	var reachable := RoomRules.reachable_seats(grid, booth.object_id).size()
	var room := RoomRules.status(grid, ids["air_room"]).seats
	var venue: int = world.sim.cafes.layout.cafe(ids["air_room"])["seats"].size()
	var counts := [reachable, room, venue]
	print("booth by doors to outdoor floor: reachable %d, room %d, venue %d" % counts)
	assert_int(reachable).is_equal(2)
	assert_int(room).is_equal(2)
	assert_int(venue).is_equal(2)


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


func _card_seats_text(sim: PassengerSim, mode: BuildMode, object_id: int) -> String:
	var card := BuiltItemCard.new()
	card.sim = sim
	card.build_mode = mode
	card.selection = BuiltSelection.new()
	card.selection.kind = BuiltSelection.Kind.OBJECT
	card.selection.id = object_id
	add_child(card)
	card.refresh()
	var text := card.field_text("seats")
	card.free()
	return text


func _build_5x5_cafe_beside_counter() -> Dictionary:
	var grid := BuildGrid.new()
	assert(ReferenceTerminal.build(grid), "reference terminal refused")
	var at := ReferenceTerminal.offset_on(grid)
	var room_rect := Rect2i(Vector2i(22, 3) + at, Vector2i(5, 5))
	var edits: Array[BuildEdit] = []
	for y in range(room_rect.position.y, room_rect.end.y):
		for x in range(room_rect.position.x, room_rect.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for y in range(4, 8):
		edits.append(BuildEdit.remove_wall(Vector2i(21, y) + at, BuildGrid.Side.EAST))
	for res in grid.apply_batch(edits):
		assert_bool(res.ok).override_failure_message(res.reason_text()).is_true()
	EnclosureKit.close_floor(grid)
	var room := grid.apply(BuildEdit.place_room(room_rect, &"cafe"))
	assert_bool(room.ok).override_failure_message(room.reason_text()).is_true()
	var counter := grid.apply(BuildEdit.place_object(&"cafe_counter", Vector2i(23, 4) + at, 0))
	assert_bool(counter.ok).override_failure_message(counter.reason_text()).is_true()
	var table := grid.apply(BuildEdit.place_object(&"cafe_table", Vector2i(25, 4) + at, 1))
	assert_bool(table.ok).override_failure_message(table.reason_text()).is_true()
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(1500, 4000))
	world.sim.cafes.refresh()
	return {
		"grid": grid,
		"world": world,
		"room": room.room_id,
		"counter": counter.object_id,
		"table": table.object_id,
		"at": at,
	}


func test_cafe_table_beside_counter_uses_opposite_open_side_and_serves_guests() -> void:
	var built := _build_5x5_cafe_beside_counter()
	var grid: BuildGrid = built["grid"]
	var world: PassengerTestWorld = built["world"]
	var table_id: int = built["table"]
	var at: Vector2i = built["at"]
	var seats := RoomRules.reachable_seats(grid, table_id)
	assert_int(seats.size()).is_equal(2)
	assert_int(RoomRules.status(grid, built["room"]).seats).is_equal(2)
	assert_vector(Vector2(seats[0]["approach"])).is_equal(Vector2(Vector2i(26, 4) + at))
	assert_str(_card_seats_text(world.sim, _mode, table_id)).is_empty()

	# Two guests use both seats; the second takes seat 0 via its alternate approach (26, 4).
	world.sim.cafes.hunger_enabled = true
	var waiting: Array[Passenger] = []
	for i in 2:
		var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		p.hunger = 0
		p.cafe_cooldown = 1000000
		waiting.append(p)
	var guests: Array[Passenger] = []
	while not waiting.is_empty() and world.clock.tick < 900:
		world.step()
		for p in waiting.duplicate():
			if p.stage == Passenger.Stage.TO_GATE:
				waiting.erase(p)
				assert_bool(world.sim.cafes.try_visit(p)).is_true()
				guests.append(p)
	assert_int(guests.size()).is_equal(2)
	var seen_stages := {}
	var alt_guest: Passenger = null
	for p in guests:
		var v := world.sim.cafes.visit_of(p.id)
		if v != null and v.seat.get("index", -1) == 0:
			alt_guest = p
			seen_stages[p.id] = []
	assert_object(alt_guest).is_not_null()
	var alt_visit := world.sim.cafes.visit_of(alt_guest.id)
	assert_vector(Vector2(alt_visit.seat["approach"])).is_equal(Vector2(Vector2i(26, 4) + at))
	while world.sim.cafes.visit_of(alt_guest.id) != null and world.clock.tick < 3000:
		(seen_stages[alt_guest.id] as Array).append(alt_guest.stage)
		world.step()
	(
		assert_array(seen_stages[alt_guest.id])
		. contains(
			[
				Passenger.Stage.CAFE_TO_SEAT,
				Passenger.Stage.CAFE_SITTING_DOWN,
				Passenger.Stage.CAFE_SEATED,
				Passenger.Stage.CAFE_STANDING_UP,
			]
		)
	)
	assert_int(alt_visit.outcome).is_equal(CafeVisit.Outcome.COMPLETE)
	assert_int(alt_guest.stage).is_equal(Passenger.Stage.TO_GATE)
	world.free_all()


func test_cafe_table_wedged_on_both_sides_reports_unreachable_seats() -> void:
	var built := _build_5x5_cafe_beside_counter()
	var grid: BuildGrid = built["grid"]
	var world: PassengerTestWorld = built["world"]
	var table_id: int = built["table"]
	var at: Vector2i = built["at"]
	var north_chair := Vector2i(25, 4) + at
	assert_bool(grid.apply(BuildEdit.place_wall(north_chair, BuildGrid.Side.EAST)).ok).is_true()
	assert_int(RoomRules.reachable_seats(grid, table_id).size()).is_equal(1)
	assert_str(_card_seats_text(world.sim, _mode, table_id)).is_equal("1 of 2 seats reachable")
	var south_chair := Vector2i(25, 6) + at
	assert_bool(grid.apply(BuildEdit.place_wall(south_chair, BuildGrid.Side.WEST)).ok).is_true()
	assert_bool(grid.apply(BuildEdit.place_wall(south_chair, BuildGrid.Side.EAST)).ok).is_true()
	assert_int(RoomRules.reachable_seats(grid, table_id).size()).is_equal(0)
	assert_str(_card_seats_text(world.sim, _mode, table_id)).is_equal("0 of 2 seats reachable")
	world.free_all()


func test_restaurant_table_against_north_wall_uses_outer_sides_and_booth_keeps_open_end() -> void:
	var grid := BuildGrid.new()
	var edits: Array[BuildEdit] = []
	for y in range(1, 9):
		for x in range(1, 9):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for res in grid.apply_batch(edits):
		assert_bool(res.ok).override_failure_message(res.reason_text()).is_true()
	EnclosureKit.close_floor(grid)
	var room := grid.apply(BuildEdit.place_room(Rect2i(1, 1, 6, 6), &"restaurant"))
	assert_bool(room.ok).override_failure_message(room.reason_text()).is_true()
	# Anchor at (3, 1) puts row 0 chairs (3, 1) and (4, 1) flush against the north wall.
	var table := grid.apply(BuildEdit.place_object(&"restaurant_table", Vector2i(3, 1), 0))
	assert_bool(table.ok).override_failure_message(table.reason_text()).is_true()
	var seats := RoomRules.reachable_seats(grid, table.object_id)
	assert_int(seats.size()).is_equal(4)
	assert_vector(Vector2(seats[0]["approach"])).is_equal(Vector2(Vector2i(2, 1)))
	assert_vector(Vector2(seats[1]["approach"])).is_equal(Vector2(Vector2i(5, 1)))
	# Blocking one north chair's outer side drops that seat (3 of 4 reachable).
	var block := Vector2i(3, 1)
	assert_bool(grid.apply(BuildEdit.place_wall(block, BuildGrid.Side.WEST)).ok).is_true()
	assert_int(RoomRules.reachable_seats(grid, table.object_id).size()).is_equal(3)
	assert_bool(grid.apply(BuildEdit.remove_wall(block, BuildGrid.Side.WEST)).ok).is_true()
	assert_bool(grid.apply(BuildEdit.remove_object(table.object_id)).ok).is_true()
	# A booth in a corner (north + west wall) never routes through its solid back panel.
	var booth := grid.apply(BuildEdit.place_object(&"restaurant_booth", Vector2i(1, 1), 0))
	assert_bool(booth.ok).override_failure_message(booth.reason_text()).is_true()
	var booth_seats := RoomRules.reachable_seats(grid, booth.object_id)
	assert_int(booth_seats.size()).is_equal(2)
	for seat in booth_seats:
		assert_int(seat["approach"].x).is_equal(3)


func _texts(control: Control) -> Array:
	var out := []
	for label in control.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out
