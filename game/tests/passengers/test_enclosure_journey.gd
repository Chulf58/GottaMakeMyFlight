class_name TestEnclosureJourney
extends GdUnitTestSuite
## Opening an outer wall mid-journey lets the outside into the reference
## terminal: passengers stop (no route on floor that is not walled in) and
## queues on it end, and closing the wall again restores service (decision
## player-built-terminal-technical-design-site-plot-indoor-mask-passenger-
## eligibility, point 5).

## A west wall of the landside hall, away from every passenger's path.
const GAP := Vector2i(10, 12)

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
