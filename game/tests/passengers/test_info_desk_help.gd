class_name TestInfoDeskHelp
extends GdUnitTestSuite
## A staffed info desk helps stuck passengers (decision info-desk-helps-stuck-
## passengers-a-short-help-visit-with-a-m, "Calm and re-route"). The guest is a
## cleared passenger walking to the exit from the south side of a wall that
## cuts it off (InfoDeskTestLayout), so it is stuck with no route until the
## wall opens.

const SPOT := Vector2i(9, 10)
const BEAT := PassengerSim.BEAT_TICKS

var _world: PassengerTestWorld
## Every InfoDesk.helped emission: {"id", "tick", "mood", "mood_before"}, where
## mood_before is the passenger's mood at the end of the tick before.
var _helped: Array[Dictionary] = []
var _last_mood := {}


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null
	_helped.clear()
	_last_mood.clear()


func _make(with_desk := true, staff_roles: Array[StaffMember.Role] = []) -> void:
	_world = InfoDeskTestLayout.world(with_desk, staff_roles)
	_world.sim.info_desks.helped.connect(
		func(id: int, _desk: int) -> void:
			(
				_helped
				. append(
					{
						"id": id,
						"tick": _world.clock.tick,
						"mood": _world.passenger(id).mood,
						"mood_before": _last_mood.get(id, -1),
					}
				)
			)
	)
	# After the sim's own handler: the mood each passenger ended the tick with.
	_world.clock.ticked.connect(
		func(_tick: int) -> void:
			for id in _world.sim.passenger_ids():
				_last_mood[id] = _world.passenger(id).mood
	)


func _guest(cell := SPOT, mood := 50) -> Passenger:
	return InfoDeskTestLayout.guest(_world, cell, mood)


func _run(ticks: int) -> void:
	_world.run_to(_world.clock.tick + ticks)


## Runs until `p` is on a help visit, at most `limit` ticks; whether it is.
func _until_visit(p: Passenger, limit := 4 * BEAT) -> bool:
	var end := _world.clock.tick + limit
	while _world.clock.tick < end and not _world.sim.info_desks.holds(p):
		_world.step()
	return _world.sim.info_desks.holds(p)


func test_a_stuck_passenger_is_helped_and_re_plans_and_reaches_its_flight() -> void:
	_make()
	var p := _guest()
	assert_bool(_until_visit(p)).is_true()
	assert_int(p.stuck).is_equal(Passenger.Stuck.NO_ROUTE)
	assert_int(_world.sim.info_desks.desk_of(p)).is_not_equal(0)
	# A route appears while it is at the desk; the help still ends first.
	InfoDeskTestLayout.open_wall(_world.grid)
	var end := _world.clock.tick + 300
	while _world.clock.tick < end and _helped.is_empty():
		_world.step()
	assert_int(_helped.size()).is_equal(1)
	var event := _helped[0]
	print(
		(
			"helped at tick %d: mood %d before, %d after (boost %d)"
			% [event["tick"], event["mood_before"], event["mood"], InfoDesk.BOOST]
		)
	)
	assert_int(event["mood"]).is_equal(event["mood_before"] + InfoDesk.BOOST)
	assert_vector(p.at).is_equal(InfoDeskTestLayout.DESK_FRONT)
	assert_int(p.stuck).is_equal(Passenger.Stuck.NONE)
	assert_bool(_world.sim.info_desks.holds(p)).is_false()
	_run(1500)
	print(
		"after the help it made its flight: stage %d, made %d" % [p.stage, _world.sim.made_count()]
	)
	assert_int(_world.sim.made_count()).is_equal(1)
	assert_int(_world.sim.missed_count()).is_equal(0)


func test_the_help_takes_the_walk_plus_the_help_ticks() -> void:
	_make()
	var p := _guest()
	assert_bool(_until_visit(p)).is_true()
	var start := _world.clock.tick
	var walk := Passenger.path_mm(_world.grid.find_path(p.at, InfoDeskTestLayout.DESK_FRONT))
	var end := start + 400
	while _world.clock.tick < end and _helped.is_empty():
		_world.step()
	var took: int = _helped[0]["tick"] - start
	var walk_ticks := ceili(walk / float(PassengerSim.WALK_MM))
	print(
		(
			"walk %d mm = %d ticks, help %d ticks, took %d"
			% [walk, walk_ticks, InfoDesk.HELP_TICKS, took]
		)
	)
	assert_int(took).is_greater_equal(walk_ticks + InfoDesk.HELP_TICKS)
	assert_int(took).is_less_equal(walk_ticks + InfoDesk.HELP_TICKS + 4)


func test_with_no_route_the_mood_drops_more_slowly_than_without_the_desk() -> void:
	# After the one help visit the wait goes on within its cooldown, so each beat
	# costs the calmed loss; the control world has no desk at all.
	_make()
	var p := _guest(SPOT, 90)
	assert_bool(_until_visit(p)).is_true()
	while _helped.is_empty():
		_world.step()
	assert_int(p.stuck).is_equal(Passenger.Stuck.NONE)
	# Back to waiting: the next tick it plans again and finds no route.
	_run(2)
	assert_int(p.stuck).is_equal(Passenger.Stuck.NO_ROUTE)
	var beats := 10
	var with_desk_start := p.mood
	_run(beats * BEAT)
	var with_desk_drop := with_desk_start - p.mood
	var helped_before := _helped.size()
	_world.free_all()
	_world = null
	_make(false)
	var control := _guest(SPOT, with_desk_start)
	_run(2)
	assert_int(control.stuck).is_equal(Passenger.Stuck.NO_ROUTE)
	var control_start := control.mood
	_run(beats * BEAT)
	var control_drop := control_start - control.mood
	print(
		(
			"mood lost over %d beats with no route: with a desk %d, control with no desk %d"
			% [beats, with_desk_drop, control_drop]
		)
	)
	assert_int(helped_before).is_equal(1)
	assert_int(with_desk_drop).is_equal(beats * InfoDesk.CALM_STUCK_LOSS)
	assert_int(control_drop).is_equal(beats * InfoDesk.STUCK_LOSS)
	assert_int(with_desk_drop).is_less(control_drop)


func test_an_unstaffed_desk_does_nothing_until_a_server_is_on_duty() -> void:
	_make(true, [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY])
	var p := _guest()
	_run(3 * BEAT)
	assert_bool(_world.sim.info_desks.open_desks().is_empty()).is_true()
	assert_bool(_world.sim.info_desks.holds(p)).is_false()
	assert_int(p.stuck).is_equal(Passenger.Stuck.NO_ROUTE)
	var start := p.mood
	_run(5 * BEAT)
	print("unstaffed desk: mood %d to %d over 5 beats" % [start, p.mood])
	assert_int(start - p.mood).is_equal(5 * InfoDesk.STUCK_LOSS)
	assert_array(_helped).is_empty()
	StaffTestKit.seat_server(_world.staff, _desk())
	assert_bool(_until_visit(p)).is_true()


func test_a_passenger_out_of_range_is_not_helped_and_one_in_range_is() -> void:
	_make()
	var edge := InfoDeskTestLayout.DESK_FRONT + Vector2i(InfoDesk.RANGE_CELLS, 0)
	var inside := _guest(edge)
	var outside := _guest(edge + Vector2i(1, 0))
	_run(3 * BEAT)
	assert_bool(_world.sim.info_desks.holds(inside)).is_true()
	assert_bool(_world.sim.info_desks.holds(outside)).is_false()
	var start := outside.mood
	_run(5 * BEAT)
	print(
		(
			"out of range (%d cells): mood %d to %d, lost %d a beat"
			% [InfoDesk.RANGE_CELLS + 1, start, outside.mood, InfoDesk.STUCK_LOSS]
		)
	)
	assert_int(start - outside.mood).is_equal(5 * InfoDesk.STUCK_LOSS)
	(
		assert_array(_helped.filter(func(e: Dictionary) -> bool: return e["id"] == outside.id))
		. is_empty()
	)


func test_a_passenger_who_is_not_stuck_is_not_sent_to_the_desk() -> void:
	_make()
	InfoDeskTestLayout.open_wall(_world.grid)
	var p := _guest()
	_run(3 * BEAT)
	assert_int(p.stuck).is_equal(Passenger.Stuck.NONE)
	assert_bool(_world.sim.info_desks.holds(p)).is_false()
	assert_array(_helped).is_empty()


func test_help_is_given_again_only_after_the_cooldown() -> void:
	_make()
	var p := _guest(SPOT, 100)
	_run(2 * InfoDesk.COOLDOWN_TICKS + 4 * BEAT)
	var ticks: Array = _helped.map(func(e: Dictionary) -> int: return e["tick"])
	print("help ticks with no route: %s (cooldown %d)" % [ticks, InfoDesk.COOLDOWN_TICKS])
	assert_int(ticks.size()).is_greater_equal(2)
	for i in range(1, ticks.size()):
		assert_int(ticks[i] - ticks[i - 1]).is_greater_equal(InfoDesk.COOLDOWN_TICKS)
	assert_bool(p.mood < 100).is_true()


func test_a_desk_that_closes_under_a_walker_ends_the_visit_with_no_boost() -> void:
	_make()
	var p := _guest()
	assert_bool(_until_visit(p)).is_true()
	# Nobody is hired back by the test kit once the only server is fired.
	_world.auto_staff = false
	assert_bool(_world.staff.fire(StaffMember.Role.SHOP)).is_true()
	assert_bool(_world.staff.is_open(_desk())).is_false()
	_run(2 * BEAT)
	assert_bool(_world.sim.info_desks.holds(p)).is_false()
	assert_array(_helped).is_empty()
	assert_int(p.stuck).is_equal(Passenger.Stuck.NO_ROUTE)


func test_a_server_fired_during_the_help_stays_until_the_help_ends() -> void:
	# A service under way ends first (decision firing-a-staff-member-mid-service-
	# takes-effect-when-the-serv): the help is the desk's service, the walk is not.
	_make()
	var p := _guest()
	assert_bool(_until_visit(p)).is_true()
	var limit := _world.clock.tick + 200
	while _world.clock.tick < limit and not _world.sim.info_desks.helping_at(_desk()):
		_world.step()
	assert_bool(_world.sim.info_desks.helping_at(_desk())).is_true()
	assert_bool(ShopCounters.in_service(_world.sim, _desk())).is_true()
	_world.auto_staff = false
	assert_bool(_world.staff.fire(StaffMember.Role.SHOP)).is_true()
	# Marked leaving and closed to newcomers, but still there.
	assert_int(_world.staff.leaving_count(StaffMember.Role.SHOP)).is_equal(1)
	assert_int(_world.staff.on_duty_count(StaffMember.Role.SHOP)).is_equal(1)
	assert_bool(_world.staff.is_open(_desk())).is_false()
	_run(10)
	assert_bool(_world.sim.info_desks.holds(p)).is_true()
	assert_int(_world.staff.on_duty_count(StaffMember.Role.SHOP)).is_equal(1)
	limit = _world.clock.tick + 200
	while _world.clock.tick < limit and _helped.is_empty():
		_world.step()
	assert_int(_helped.size()).is_equal(1)
	assert_int(_helped[0]["mood"]).is_equal(_helped[0]["mood_before"] + InfoDesk.BOOST)
	# The help is over, so the server walks out.
	_run(3)
	assert_int(_world.staff.count(StaffMember.Role.SHOP)).is_equal(0)


func test_a_desk_nobody_is_being_helped_at_is_not_in_service() -> void:
	_make()
	_run(2)
	assert_bool(ShopCounters.in_service(_world.sim, _desk())).is_false()
	var p := _guest()
	assert_bool(_until_visit(p)).is_true()
	# Still walking: not a service, so a fired server would leave at once.
	assert_bool(_world.sim.info_desks.helping_at(_desk())).is_false()
	assert_bool(ShopCounters.in_service(_world.sim, _desk())).is_false()


func _desk() -> int:
	return _world.staff.stations_of(StaffMember.Role.SHOP)[0]
