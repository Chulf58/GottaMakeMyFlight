class_name TestEnclosureJourney
extends GdUnitTestSuite
## Opening an outer wall mid-journey lets the outside into the reference
## terminal: passengers stop (no route on floor that is not walled in) and
## queues on it end, and closing the wall again restores service (decision
## player-built-terminal-technical-design-site-plot-indoor-mask-passenger-
## eligibility, point 5).

## A west wall of the landside hall, away from every passenger's path.
const GAP := Vector2i(10, 12)
const SITE := preload("res://build/terminal_site.tres")

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_world = PassengerTestWorld.reference_world()


func after_test() -> void:
	_world.free_all()
	_world = null


func _set_gap(open: bool) -> void:
	var side := BuildGrid.Side.WEST
	var edit := BuildEdit.remove_wall(GAP, side) if open else BuildEdit.place_wall(GAP, side)
	var result := _world.grid.apply(edit)
	assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()


## Steps until `done` holds for `p` or `limit` ticks pass; returns the ticks.
func _step_until(p: Passenger, done: Callable, limit: int) -> int:
	for i in limit:
		if done.call(p):
			return i
		_world.step()
	return limit


func test_a_walker_stops_when_a_wall_opens_and_checks_in_once_it_closes() -> void:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	var walking := func(q: Passenger) -> bool:
		return q.stage == Passenger.Stage.TO_CHECKIN and q.is_moving()
	assert_int(_step_until(p, walking, 200)).is_less(200)
	var from := p.at
	_set_gap(true)
	# One step to finish or turn back from the step it is on, then it stands.
	_step_until(p, func(q: Passenger) -> bool: return not q.is_moving(), 20)
	var stood := p.at
	for i in 40:
		_world.step()
	print(
		(
			"walker %d from %s stood at %s, stage %s, moving %s"
			% [p.id, from, stood, Passenger.Stage.keys()[p.stage], p.is_moving()]
		)
	)
	assert_bool(p.is_moving()).is_false()
	assert_vector(Vector2(p.at)).is_equal(Vector2(stood))
	assert_int(p.stage).is_equal(Passenger.Stage.TO_CHECKIN)
	var desk: int = ReferenceTerminal.object_ids(_world.grid)["desks"][0]
	assert_bool(_world.sim.layout.is_usable(desk)).is_false()
	_set_gap(false)
	var served := func(q: Passenger) -> bool: return q.stage >= Passenger.Stage.CHECKIN
	var ticks := _step_until(p, served, 600)
	print("walker %d reached %s after %d ticks" % [p.id, Passenger.Stage.keys()[p.stage], ticks])
	assert_int(ticks).is_less(600)


func test_a_queue_on_floor_that_opens_ends_and_forms_again_once_it_closes() -> void:
	var ids: Array[int] = []
	for i in 6:
		ids.append(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	var p := _world.passenger(ids[ids.size() - 1])
	var queued := func(q: Passenger) -> bool: return q.stage == Passenger.Stage.CHECKIN_QUEUE
	assert_int(_step_until(p, queued, 400)).is_less(400)
	_set_gap(true)
	_world.step()
	var queuing := 0
	for id in ids:
		if _world.passenger(id).stage == Passenger.Stage.CHECKIN_QUEUE:
			queuing += 1
	print(
		(
			"queuing one tick after the wall opened: %d, last passenger %s"
			% [queuing, Passenger.Stage.keys()[p.stage]]
		)
	)
	assert_int(queuing).is_equal(0)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_CHECKIN)
	_set_gap(false)
	var back := func(q: Passenger) -> bool: return q.stage >= Passenger.Stage.CHECKIN_QUEUE
	assert_int(_step_until(p, back, 400)).is_less(400)


## On the airport site, a passenger walking in from the road (OutsideWalks)
## whose only entrance stops being walled in stops on the road with no route,
## out of the terminal, and walks on and comes in once the wall is back.
func test_a_walker_from_the_road_stops_while_its_terminal_is_open() -> void:
	var grid := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	assert_bool(ReferenceTerminal.build(grid)).is_true()
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.sim.site = SITE
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	assert_int(p.apron_total_mm()).is_greater(0)
	var started := func(q: Passenger) -> bool: return q.apron_mm > 2000
	assert_int(_step_until(p, started, 200)).is_less(200)
	_set_gap(true)
	assert_array(_world.sim.layout.passenger_entrances).is_empty()
	_world.step()
	var stopped_at := p.apron_mm
	for i in 30:
		_world.step()
	print(
		(
			"road walker %d: walked %d of %d mm, then %d mm; stage %s, stuck %s"
			% [
				p.id,
				stopped_at,
				p.apron_total_mm(),
				p.apron_mm,
				Passenger.Stage.keys()[p.stage],
				Passenger.Stuck.keys()[p.stuck]
			]
		)
	)
	assert_int(p.stage).is_equal(Passenger.Stage.SPAWNED)
	assert_int(p.stuck).is_equal(Passenger.Stuck.NO_ROUTE)
	assert_int(p.apron_mm).is_equal(stopped_at)
	assert_int(p.apron_mm).is_less(p.apron_total_mm())
	_set_gap(false)
	assert_int(_world.sim.layout.passenger_entrances.size()).is_equal(1)
	var inside := func(q: Passenger) -> bool: return q.stage >= Passenger.Stage.TO_CHECKIN
	assert_int(_step_until(p, inside, 3000)).is_less(3000)
	assert_int(p.stuck).is_not_equal(Passenger.Stuck.NO_ROUTE)


## A help visit ends when walls stop closing its info desk in. The test floor
## is walled along the grid border (PassengerTestWorld.floored()), so taking
## one border wall down opens the whole floor.
func test_a_help_visit_ends_when_its_desk_loses_closed_floor() -> void:
	_world = InfoDeskTestLayout.world()
	var p := InfoDeskTestLayout.guest(_world, Vector2i(9, 10), 50)
	var held := func(q: Passenger) -> bool: return _world.sim.info_desks.holds(q)
	assert_int(_step_until(p, held, 200)).is_less(200)
	var border_wall := BuildEdit.remove_wall(Vector2i(0, 10), BuildGrid.Side.WEST)
	assert_bool(_world.grid.apply(border_wall).ok).is_true()
	_world.step()
	assert_bool(_world.sim.info_desks.holds(p)).is_false()
