class_name TestVisitForecast
extends GdUnitTestSuite
## The shared visit forecast on real route lengths (decision
## toilet-design-queue-free-reservable-stalls-per-stall-daily-u, point 3). On
## a winding layout, where a long wall puts the way out far beyond the
## straight-line (octile) estimate, the walk after a visit is the grid's path:
## a cafe visit the octile estimate would admit is refused, the deadline comes
## earlier, and a guest who left at the old deadline misses the flight while
## one who leaves at the new one makes it.

## The winding layout: a floored grid with the exit on the north edge west of
## a wall that runs down the east side of column WALL_X from the north edge to
## WALL_END_Y, and a cafe east of the wall. Every way from the cafe to the exit
## goes round the wall's south end.
const SIZE := Vector2i(30, 40)
const WALL_X := 12
const WALL_END_Y := 35
const EXIT_CELL := Vector2i(2, 0)
const ENTRANCE_CELL := Vector2i(2, 39)
const CAFE_ROOM := Rect2i(16, 2, 6, 6)
const COUNTER := Vector2i(17, 2)
const TABLE := Vector2i(18, 5)
## Where the guest stands when it thinks of the cafe: airside, east of the wall.
const GUEST_CELL := Vector2i(20, 10)
const BOARDING := 30
const DOORS := 6000

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


func _winding_world() -> PassengerTestWorld:
	var grid := PassengerTestWorld.floored(SIZE)
	for y in range(0, WALL_END_Y + 1):
		_apply(grid, BuildEdit.place_wall(Vector2i(WALL_X, y), BuildGrid.Side.EAST))
	PassengerTestWorld.place(grid, &"exit_door", EXIT_CELL, 0)
	PassengerTestWorld.place(grid, &"entrance_door", ENTRANCE_CELL, 2)
	_apply(grid, BuildEdit.place_room(CAFE_ROOM, &"cafe"))
	PassengerTestWorld.place(grid, &"cafe_counter", COUNTER, 0)
	PassengerTestWorld.place(grid, &"cafe_table", TABLE, 0)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(BOARDING, DOORS))
	# The plane stands just outside the exit, so the walk inside decides.
	_world.sim.apron_waypoints = PackedVector3Array()
	_world.run_to(BOARDING + 1)
	return _world


func _apply(grid: BuildGrid, edit: BuildEdit) -> void:
	var result := grid.apply(edit)
	assert(result.ok, "winding layout edit refused: %s" % result.reason_text())


func _remove_wall(grid: BuildGrid) -> void:
	for y in range(0, WALL_END_Y + 1):
		_apply(grid, BuildEdit.remove_wall(Vector2i(WALL_X, y), BuildGrid.Side.EAST))


## A cleared passenger standing at `cell`, heading for the gate, that never
## thinks of the cafe on its own.
func _airside_at(cell: Vector2i) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 0
	p.cafe_cooldown = 1000000
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _world.clock.tick
	p.at = cell
	p.clear_path()
	return p


## The cafe's counter lane and the approach of the seat nearest its order
## spot, as CafeSim chooses them for an empty cafe.
func _cafe() -> Dictionary:
	_world.sim.cafes.refresh()
	var cafe: Dictionary = _world.sim.cafes.layout.cafes[0]
	var lane: Array = cafe["counters"][0]["lane"]
	var best: Dictionary = {}
	for seat in cafe["seats"]:
		var mm := Passenger.octile_mm(lane[0], seat["approach"])
		if best.is_empty() or mm < Passenger.octile_mm(lane[0], best["approach"]):
			best = seat
	return {"lane": lane, "approach": best["approach"]}


## The visit legs CafeSim plans for `cell` at an empty cafe.
func _legs(cell: Vector2i, cafe: Dictionary) -> Dictionary:
	var grid := _world.grid
	var lane: Array = cafe["lane"]
	return {
		"pre_ticks": 0,
		"to_queue_mm": Passenger.path_mm(grid.find_path(cell, lane[0])),
		"order_ticks": CafeSim.ORDER_TICKS,
		"to_seat_mm": Passenger.path_mm(grid.find_path(lane[0], cafe["approach"])),
		"dwell_ticks": CafeSim.DWELL_TICKS,
		"leave_cell": cafe["approach"],
		"resume_stage": Passenger.Stage.TO_GATE,
	}


## Ticks from standing up at `cell` to the plane door by the straight-line
## estimate the forecast used before (JourneyForecast unrouted).
func _octile_leave(p: Passenger, cell: Vector2i) -> int:
	var ghost := Passenger.new()
	ghost.id = p.id
	ghost.flight_id = p.flight_id
	ghost.cleared = true
	ghost.stage = Passenger.Stage.TO_GATE
	ghost.at = cell
	ghost.clear_path()
	return JourneyForecast.arrival_from(_world.sim, ghost, 0) + PassengerSim.STAND_UP_TICKS


## Ticks from `cell` to the plane door along the grid's path, at a walk.
func _routed_walk(cell: Vector2i) -> int:
	var exit: int = _world.sim.layout.exits[0]
	var path := _world.grid.find_path(cell, _world.sim.layout.door_cell(_world.grid, exit))
	return JourneyForecast.walk_ticks(Passenger.path_mm(path) + _world.sim.apron_length_mm(exit))


func test_the_walk_out_after_a_visit_is_the_grids_path_not_the_straight_line() -> void:
	_winding_world()
	var cafe := _cafe()
	var approach: Vector2i = cafe["approach"]
	var p := _airside_at(GUEST_CELL)
	var resume := Passenger.Stage.TO_GATE
	var stand := PassengerSim.STAND_UP_TICKS
	var leave := VisitForecast.leave_ticks(_world.sim, p, approach, stand, resume)
	var octile := _octile_leave(p, approach)
	var routed := _routed_walk(approach)
	print("approach %s leave %d routed walk %d octile leave %d" % [approach, leave, routed, octile])
	assert_int(leave).is_equal(stand + routed)
	# The layout is winding: the path is far longer than the straight line.
	assert_int(leave - octile).is_greater(400)
	assert_int(CafeForecast.leave_ticks(_world.sim, p, approach, resume)).is_equal(leave)
	var doors := _world.flights.doors_close_tick(p.flight_id)
	assert_int(VisitForecast.deadline(_world.sim, p, approach, stand, resume)).is_equal(
		doors - VisitForecast.MARGIN_TICKS - leave
	)
	# Leaving from where it stands now is a walk with no stand-up; the live
	# deadline is the earlier of that and leaving from the seat.
	var here := VisitForecast.deadline(_world.sim, p, GUEST_CELL, 0, resume)
	assert_int(here).is_equal(doors - VisitForecast.MARGIN_TICKS - _routed_walk(GUEST_CELL))
	assert_int(VisitForecast.live_deadline(_world.sim, p, approach, stand, resume)).is_equal(
		mini(here, doors - VisitForecast.MARGIN_TICKS - leave)
	)
	# With the wall gone the forecast follows the new, short path.
	_remove_wall(_world.grid)
	var open := VisitForecast.leave_ticks(_world.sim, p, approach, stand, resume)
	print("leave with the wall gone %d (octile %d)" % [open, _octile_leave(p, approach)])
	assert_int(open).is_equal(stand + _routed_walk(approach))
	assert_int(leave - open).is_greater(400)


func test_a_visit_the_straight_line_admits_is_refused_on_the_winding_route() -> void:
	_winding_world()
	var cafe := _cafe()
	var probe := _airside_at(GUEST_CELL)
	var legs := _legs(GUEST_CELL, cafe)
	var duration := CafeForecast.visit_end(_world.sim, legs) - _world.clock.tick
	var old_leave := _octile_leave(probe, cafe["approach"])
	var new_leave := CafeForecast.leave_ticks(
		_world.sim, probe, cafe["approach"], legs["resume_stage"]
	)
	# The tick halfway between the last one the octile forecast admits the
	# visit at and the last one the routed forecast does, so neither estimate
	# needs to match CafeSim's plan to the tick.
	var margin := VisitForecast.MARGIN_TICKS
	@warning_ignore("integer_division")
	var start := DOORS - margin - duration - (old_leave + new_leave) / 2
	print(
		"duration %d old leave %d new leave %d start %d" % [duration, old_leave, new_leave, start]
	)
	assert_int(start).is_greater(_world.clock.tick)
	_world.run_to(start)
	var p := _airside_at(GUEST_CELL)
	legs = _legs(GUEST_CELL, cafe)
	var old_arrival := CafeForecast.visit_end(_world.sim, legs) + old_leave
	var new_arrival := CafeForecast.visit_arrival(_world.sim, p, legs)
	print("at %d old arrival %d new arrival %d doors %d" % [start, old_arrival, new_arrival, DOORS])
	# The old forecast admits it, the new one refuses it, and so does CafeSim.
	assert_bool(CafeForecast.admits(_world.sim, p, old_arrival)).is_true()
	assert_bool(CafeForecast.admits(_world.sim, p, new_arrival)).is_false()
	assert_bool(_world.sim.cafes.try_visit(p)).is_false()
	assert_object(_world.sim.cafes.visit_of(p.id)).is_null()
	# Control: with the wall gone the same visit at the same tick is admitted.
	_remove_wall(_world.grid)
	assert_bool(_world.sim.cafes.try_visit(p)).is_true()
	assert_object(_world.sim.cafes.visit_of(p.id)).is_not_null()


func test_leaving_at_the_old_deadline_misses_and_at_the_new_one_makes_it() -> void:
	_winding_world()
	var cafe := _cafe()
	var approach: Vector2i = cafe["approach"]
	var probe := _airside_at(GUEST_CELL)
	var resume := Passenger.Stage.TO_GATE
	var margin := VisitForecast.MARGIN_TICKS
	var old_deadline := DOORS - margin - _octile_leave(probe, approach)
	var new_deadline := CafeForecast.deadline(_world.sim, probe, approach, resume)
	print("old deadline %d new deadline %d" % [old_deadline, new_deadline])
	assert_int(new_deadline).is_less(old_deadline)
	# Each guest stands up from the seat at its deadline and sets off from the
	# approach cell when it is up, as a guest whose deadline passes does.
	_world.run_to(new_deadline + PassengerSim.STAND_UP_TICKS)
	var on_time := _airside_at(approach)
	_world.run_to(old_deadline + PassengerSim.STAND_UP_TICKS)
	var too_late := _airside_at(approach)
	_world.run_to(DOORS + 1)
	print(
		(
			"new deadline guest %s at %d, old deadline guest %s"
			% [
				Passenger.Stage.keys()[on_time.stage],
				on_time.outcome_tick,
				Passenger.Stage.keys()[too_late.stage]
			]
		)
	)
	assert_int(on_time.stage).is_equal(Passenger.Stage.MADE)
	# Boarded with nearly all the margin spare: the sim spends a tick or two
	# more than the forecast where one leg of the walk hands over to the next.
	@warning_ignore("integer_division")
	assert_int(on_time.outcome_tick).is_less(DOORS - margin / 2)
	assert_int(too_late.stage).is_equal(Passenger.Stage.MISSED)
	# It missed on the way to the plane, not stuck: it ran out of time.
	assert_int(too_late.missed_stuck).is_equal(Passenger.Stuck.NONE)
	assert_bool(too_late.odometer_mm > 0).is_true()


func test_a_landside_visit_walks_the_path_to_security() -> void:
	_world = PassengerTestWorld.reference_world()
	_world.run_to(10)
	# Free floor between the scanner lanes and the east wall.
	var cell := Vector2i(20, 14)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	var resume := Passenger.Stage.TO_SECURITY
	var open := VisitForecast.leave_ticks(_world.sim, p, cell, 0, resume)
	# A wall north of the cell's row from the scanners' side to the east wall:
	# the way to security now goes round its west end.
	for x in range(15, ReferenceTerminal.FLOOR_MAX.x + 1):
		_apply(_world.grid, BuildEdit.place_wall(Vector2i(x, 13), BuildGrid.Side.NORTH))
	var walled := VisitForecast.leave_ticks(_world.sim, p, cell, 0, resume)
	var octile := _landside_octile(p, cell)
	print("landside leave open %d walled %d octile %d" % [open, walled, octile])
	assert_int(open).is_less(JourneyForecast.NEVER)
	assert_int(walled).is_greater(open + 30)
	assert_int(walled).is_greater(octile + 30)
	# Shut in: no path to any scanner, so no way to the plane at all.
	for side in [
		BuildGrid.Side.NORTH, BuildGrid.Side.EAST, BuildGrid.Side.SOUTH, BuildGrid.Side.WEST
	]:
		_apply(_world.grid, BuildEdit.place_wall(cell, side))
	var shut := VisitForecast.leave_ticks(_world.sim, p, cell, 0, resume)
	print("shut in %d, octile still %d" % [shut, _landside_octile(p, cell)])
	assert_int(shut).is_equal(JourneyForecast.NEVER)
	assert_int(_landside_octile(p, cell)).is_less(JourneyForecast.NEVER)


func _landside_octile(p: Passenger, cell: Vector2i) -> int:
	var ghost := Passenger.new()
	ghost.id = p.id
	ghost.flight_id = p.flight_id
	ghost.stage = Passenger.Stage.TO_SECURITY
	ghost.at = cell
	ghost.clear_path()
	return JourneyForecast.arrival_from(_world.sim, ghost, 0)
