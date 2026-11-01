class_name TestPassengerEligibility
extends GdUnitTestSuite
## Every passenger service uses one eligibility rule,
## BuildGrid.is_passenger_cell(): walkable floor that walls close in (decision
## player-built-terminal-technical-design-site-plot-indoor-mask-passenger-
## eligibility, point 4). Each case builds a walled layout, checks the service
## is in it, opens one outer wall so the outside floods the floor, checks the
## service is gone, and closes the wall again.

## A west wall of the reference terminal's landside hall.
const TERMINAL_WALL := Vector2i(10, 12)
## An east wall of the test layouts' floor east of the terminal (x 22-27),
## which openings in the terminal's east wall join to the terminal.
const ANNEX_WALL := Vector2i(27, 5)


func _set_wall(grid: BuildGrid, cell: Vector2i, side: int, standing: bool) -> void:
	var edit := BuildEdit.place_wall(cell, side) if standing else BuildEdit.remove_wall(cell, side)
	var result := grid.apply(edit)
	assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	assert_bool(grid.is_indoor(cell)).is_equal(standing)


func _terminal(grid: BuildGrid) -> TerminalLayout:
	var layout := TerminalLayout.new()
	layout.rebuild(grid)
	return layout


func test_desk_lane_head_scanner_seats_and_exit_need_closed_floor() -> void:
	var grid := BuildGrid.new()
	assert_bool(ReferenceTerminal.build(grid)).is_true()
	var ids := ReferenceTerminal.object_ids(grid)
	var desk: int = ids["desks"][0]
	var scanner: int = ids["scanners"][0]
	var exit: int = ids["exits"][0]
	var layout := _terminal(grid)
	print(
		(
			"closed: desk lane %d, passage %d, seats %d"
			% [
				(layout.lanes[desk] as Array).size(),
				(layout.passages[scanner] as Array).size(),
				layout.seats.size()
			]
		)
	)
	assert_bool(layout.is_usable(desk)).is_true()
	assert_bool(layout.is_usable(scanner)).is_true()
	var seats := layout.seats.size()
	assert_int(seats).is_greater(0)
	assert_bool(layout.is_exit_open(grid, exit)).is_true()
	assert_bool(grid.is_passenger_cell(grid.interaction_cell(desk))).is_true()
	_set_wall(grid, TERMINAL_WALL, BuildGrid.Side.WEST, false)
	layout = _terminal(grid)
	assert_bool(grid.is_passenger_cell(grid.interaction_cell(desk))).is_false()
	assert_array(layout.lanes[desk]).is_empty()
	assert_bool(layout.is_usable(desk)).is_false()
	assert_array(layout.passages[scanner]).is_empty()
	assert_bool(layout.is_usable(scanner)).is_false()
	assert_int(layout.seats.size()).is_equal(0)
	assert_bool(layout.is_exit_open(grid, exit)).is_false()
	# Staff still reach the desk's spot: staff access is physical.
	var staff_path := grid.find_staff_path(Vector2i(18, 17), StaffSpots.spot_of(grid, desk))
	assert_bool(staff_path.size() > 1).is_true()
	_set_wall(grid, TERMINAL_WALL, BuildGrid.Side.WEST, true)
	layout = _terminal(grid)
	assert_bool(layout.is_usable(desk)).is_true()
	assert_bool(layout.is_usable(scanner)).is_true()
	assert_int(layout.seats.size()).is_equal(seats)


func test_a_cafe_seat_and_counter_lane_need_closed_floor() -> void:
	var grid := BuildGrid.new()
	var ids := CafeTestLayout.build(grid)
	var cafes := CafeLayout.new()
	cafes.rebuild(grid, _terminal(grid))
	var cafe := cafes.cafe(ids["air_room"])
	assert_int((cafe.get("seats", []) as Array).size()).is_equal(2)
	assert_bool(cafes.counter(ids["air_room"], ids["air_counter"]).is_empty()).is_false()
	_set_wall(grid, ANNEX_WALL, BuildGrid.Side.EAST, false)
	cafes.rebuild(grid, _terminal(grid))
	assert_dict(cafes.cafe(ids["air_room"])).is_empty()
	assert_int(cafes.cafes.size()).is_equal(0)
	_set_wall(grid, ANNEX_WALL, BuildGrid.Side.EAST, true)
	cafes.rebuild(grid, _terminal(grid))
	assert_int((cafes.cafe(ids["air_room"]).get("seats", []) as Array).size()).is_equal(2)


func test_a_toilet_stall_approach_needs_closed_floor() -> void:
	var grid := BuildGrid.new()
	var ids := ToiletTestLayout.build(grid)
	var toilets := ToiletLayout.new()
	toilets.rebuild(grid)
	var stall: int = ids["air_stalls"][0]
	assert_bool(toilets.stall(stall).is_empty()).is_false()
	var count := toilets.stalls.size()
	assert_int(count).is_greater(0)
	_set_wall(grid, ANNEX_WALL, BuildGrid.Side.EAST, false)
	toilets.rebuild(grid)
	assert_dict(toilets.stall(stall)).is_empty()
	assert_int(toilets.stalls.size()).is_equal(0)
	_set_wall(grid, ANNEX_WALL, BuildGrid.Side.EAST, true)
	toilets.rebuild(grid)
	assert_int(toilets.stalls.size()).is_equal(count)


func test_a_shop_slot_needs_closed_floor() -> void:
	var grid := BuildGrid.new()
	var ids := ShopTestLayout.build(grid, ["air"])
	var shops := ShopLayout.new()
	shops.rebuild(grid)
	var display: int = ids["air_displays"][0]
	assert_bool(shops.slot(display, 0).is_empty()).is_false()
	_set_wall(grid, ANNEX_WALL, BuildGrid.Side.EAST, false)
	shops.rebuild(grid)
	assert_dict(shops.slot(display, 0)).is_empty()
	assert_int(shops.shops.size()).is_equal(0)
	_set_wall(grid, ANNEX_WALL, BuildGrid.Side.EAST, true)
	shops.rebuild(grid)
	assert_bool(shops.slot(display, 0).is_empty()).is_false()


## Passengers come in only through an entrance on closed floor; staff still
## use every entrance.
func test_an_entrance_needs_closed_floor() -> void:
	var grid := BuildGrid.new()
	assert_bool(ReferenceTerminal.build(grid)).is_true()
	var entrance: int = ReferenceTerminal.object_ids(grid)["entrances"][0]
	var layout := _terminal(grid)
	assert_array(layout.passenger_entrances).contains_exactly([entrance])
	_set_wall(grid, TERMINAL_WALL, BuildGrid.Side.WEST, false)
	layout = _terminal(grid)
	assert_array(layout.passenger_entrances).is_empty()
	assert_array(layout.entrances).contains_exactly([entrance])
	_set_wall(grid, TERMINAL_WALL, BuildGrid.Side.WEST, true)
	layout = _terminal(grid)
	assert_array(layout.passenger_entrances).contains_exactly([entrance])


## An info desk on floor that is not walled in helps nobody, and a saved visit
## to one is refused. The test floor is walled along the grid border
## (PassengerTestWorld.floored()), so taking one border wall down opens the
## whole floor.
func test_an_info_desk_needs_closed_floor() -> void:
	var world := InfoDeskTestLayout.world()
	world.step()
	var desk := world.grid.object_at(InfoDeskTestLayout.DESK_ANCHOR)
	var desks := world.sim.info_desks
	assert_array(desks.open_desks()).contains_exactly([desk])
	var p := InfoDeskTestLayout.guest(world, Vector2i(9, 10), 50)
	p.stuck = Passenger.Stuck.NO_ROUTE
	var saved := {"visits": [[p.id, desk, InfoDesk.WALKING]], "cooldowns": []}
	var tick := world.sim.tick
	assert_dict(InfoDesk.checked(saved, {p.id: p}, tick, world.grid)).not_contains_keys(["error"])
	var border_wall := BuildEdit.remove_wall(Vector2i(0, 10), BuildGrid.Side.WEST)
	assert_bool(world.grid.apply(border_wall).ok).is_true()
	assert_bool(world.grid.is_passenger_cell(InfoDeskTestLayout.DESK_FRONT)).is_false()
	assert_array(desks.open_desks()).is_empty()
	var refused := InfoDesk.checked(saved, {p.id: p}, tick, world.grid)
	print("refused visit: %s" % refused)
	assert_dict(refused).contains_keys(["error"])
	var wall_back := BuildEdit.place_wall(Vector2i(0, 10), BuildGrid.Side.WEST)
	assert_bool(world.grid.apply(wall_back).ok).is_true()
	assert_array(desks.open_desks()).contains_exactly([desk])
	world.free_all()
