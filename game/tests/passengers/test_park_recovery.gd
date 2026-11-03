class_name TestParkRecovery
extends GdUnitTestSuite
## A walker whose gate seat is removed while its roller parks to go onto the
## floor stands collecting the bag before it walks on (ParkRecovery, decision
## roller-park-interrupted-by-a-lost-seat-the-passenger-collect, board
## d425a825), timed by the sim clock alone and kept through a save. A seat lost
## after the park, sitting down or seated, holds it the same (decision seat-
## lost-after-a-roller-park-a-seated-passenger-still-stand, board 6981b7ac).
## The normal sit-down and stand-up keep their timing, and a walker with no
## roller, or late as it sat down, is sent on at once.

var _world: PassengerTestWorld


## Every world a test makes is freed with the test (auto_free).
func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


## A walker by the reference terminal's first gate chair, a roller among its
## bags when `roller`, standing at its front; sat down at it (SITTING_DOWN from
## this tick) when `sit`.
func _walker(roller: bool, sit := true) -> Passenger:
	_world = PassengerTestWorld.reference_world()
	_world.run_to(10)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while (SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER) != roller:
		ToiletTestLayout.calm(p)
		p.carry_on = 0
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 1
	p.cleared = true
	var seat: Dictionary = _world.sim.layout.seats[0]
	p.seat_object = seat["object_id"]
	p.seat_cell = seat["cell"]
	p.seat_front = seat["front"]
	p.at = seat["front"]
	p.clear_path()
	p.boarding_tick = _world.sim.tick + 100000
	p.stage = Passenger.Stage.SITTING_DOWN if sit else Passenger.Stage.SEATED
	p.stage_tick = _world.sim.tick
	return p


## Removes the walker's chair by a build edit; the sim settles it on its next
## tick (PassengerSim._reconcile()).
func _seat_goes() -> void:
	var seat: int = _world.sim.layout.seats[0]["object_id"]
	assert_bool(_world.sim.grid.apply(BuildEdit.remove_object(seat)).ok).is_true()


## Steps until `p` has a path or `limit` ticks went by: the ticks it took.
func _ticks_to_route(p: Passenger, limit: int) -> int:
	for n in limit:
		if p.path.size() >= 2:
			return n
		_world.step()
	return -1


## Its chair removed in the lift (2 ticks in) or the park (5 ticks in), the
## walker is sent on to the gate but stands on its cell with no route until
## ParkRecovery.collect_of() of the tick it sat down, and plans its way on that
## tick. Control: it does get a route then.
func test_a_seat_lost_mid_park_holds_the_walker_until_the_roller_is_collected() -> void:
	for into: int in [2, 5]:
		var p := _walker(true)
		var sat := _world.sim.tick
		var cell := p.at
		for n in into:
			_world.step()
		_seat_goes()
		_world.step()
		var until := ParkRecovery.collect_of(sat)
		print("seat gone %d ticks in at tick %d: collect to %d" % [into, _world.sim.tick, until])
		assert_int(until).is_equal(sat + ceili(RollerPark.TICKS_DOWN) + ParkRecovery.COLLECT_TICKS)
		assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
		assert_int(p.collect_tick).is_equal(until)
		assert_int(p.seat_object).is_equal(0)
		while _world.sim.tick < until:
			# No route: its path only the cell it stands on (Passenger.clear_path()).
			assert_int(p.path.size()).is_equal(1)
			assert_that(p.at).is_equal(cell)
			assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
			_world.step()
		assert_int(p.collect_tick).is_equal(0)
		assert_int(p.stage_tick).is_equal(until)
		assert_int(p.path.size()).is_greater_equal(2)


## The normal path: a roller walker sitting down is seated SIT_DOWN_TICKS after,
## never held to collect anything. Standing up it is fully up before the
## roller's floor>pull starts (STAND_UP_TICKS in, no longer
## RollerPark.UP_LEAD_TICKS before), and it stands UP_HOLD_TICKS more at the
## chair front picking it up before it walks on (decision standing-up-with-a-
## roller-stand-up-then-pick-up-then-walk): the stage lasts
## ParkRecovery.stand_up_ticks(), which the journey forecast counts too.
func test_the_normal_sit_down_and_stand_up_keep_their_timing() -> void:
	var p := _walker(true)
	var sat := _world.sim.tick
	while p.stage == Passenger.Stage.SITTING_DOWN:
		assert_int(p.collect_tick).is_equal(0)
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SEATED)
	assert_int(p.stage_tick - sat).is_equal(PassengerSim.SIT_DOWN_TICKS)
	p.boarding_tick = _world.sim.tick + 3
	while p.stage == Passenger.Stage.SEATED:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.STANDING_UP)
	var up := p.stage_tick
	# The forecast counts the hold: the same walker forecast with no bag
	# reaches its exit door UP_HOLD_TICKS sooner.
	var with_bag: int = JourneyForecast.own_times(_world.sim, p, up, false)["door_tick"]
	p.carry_on = 0
	var no_bag: int = JourneyForecast.own_times(_world.sim, p, up, false)["door_tick"]
	p.carry_on = 1
	var homes := []
	while p.stage == Passenger.Stage.STANDING_UP:
		homes.append(SecurityLooks.bag_homes(_world.sim, p)[0])
		assert_int(p.collect_tick).is_equal(0)
		_world.step()
	var held := PassengerSim.STAND_UP_TICKS + ParkRecovery.UP_HOLD_TICKS
	print(
		(
			"stand-up %d ticks, forecast door %d with the roller, %d without"
			% [p.stage_tick - up, with_bag, no_bag]
		)
	)
	assert_int(p.stage_tick - up).is_equal(held)
	assert_int(with_bag - no_bag).is_equal(ParkRecovery.UP_HOLD_TICKS)
	assert_int(p.collect_tick).is_equal(0)
	# Into the hand once the stand-up is over: the floor>pull.
	assert_int(homes.find(SecurityLooks.Home.HAND)).is_equal(PassengerSim.STAND_UP_TICKS)


## With no roller the stand-up keeps its STAND_UP_TICKS and is not held.
func test_a_walker_with_no_roller_stands_up_and_walks_on_at_once() -> void:
	var p := _walker(false, false)
	p.boarding_tick = _world.sim.tick + 3
	while p.stage == Passenger.Stage.SEATED:
		_world.step()
	var up := p.stage_tick
	while p.stage == Passenger.Stage.STANDING_UP:
		_world.step()
	assert_int(p.stage_tick - up).is_equal(PassengerSim.STAND_UP_TICKS)


## A walker with no roller has nothing to collect: its seat lost, it is sent on
## with no hold and plans its way on the tick it was sent (stage_tick).
func test_a_seat_lost_by_a_walker_with_no_roller_sends_it_on_at_once() -> void:
	for sit: bool in [true, false]:
		var p := _walker(false, sit)
		for n in 2:
			_world.step()
		_seat_goes()
		_world.step()
		var sent := _world.sim.tick
		print("no roller, sitting %s: collect %d" % [sit, p.collect_tick])
		assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
		assert_int(p.collect_tick).is_equal(0)
		assert_int(p.stage_tick).is_equal(sent)
		assert_int(_ticks_to_route(p, 3)).is_between(0, 1)


## A seat lost once the roller's park is over (still sitting down past
## RollerPark.TICKS_DOWN, or seated) holds the walker too (decision seat-lost-
## after-a-roller-park-a-seated-passenger-still-stand, board 6981b7ac): it
## stands on its cell with no route for COLLECT_TICKS from the tick the seat
## went, to pick the parked roller up, and plans its way on that tick.
func test_a_seat_lost_after_the_park_holds_the_walker_until_the_roller_is_collected() -> void:
	# [sitting down, ticks in, stage expected when the seat goes]: the park over
	# but still sitting down (the first tick past it, a late one), and seated.
	var park := ceili(RollerPark.TICKS_DOWN)
	var cases := [
		[true, park, Passenger.Stage.SITTING_DOWN],
		[true, PassengerSim.SIT_DOWN_TICKS - 2, Passenger.Stage.SITTING_DOWN],
		[false, 2, Passenger.Stage.SEATED],
		[false, 30, Passenger.Stage.SEATED],
	]
	for c: Array in cases:
		var p := _walker(true, c[0])
		var cell := p.at
		for n: int in c[1]:
			_world.step()
		assert_int(p.stage).is_equal(c[2])
		_seat_goes()
		_world.step()
		var until := _world.sim.tick + ParkRecovery.COLLECT_TICKS
		print(
			(
				"sitting %s, %d ticks in: lost at tick %d, collect %d"
				% [c[0], c[1], _world.sim.tick, p.collect_tick]
			)
		)
		assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
		assert_int(p.collect_tick).is_equal(until)
		assert_int(p.seat_object).is_equal(0)
		while _world.sim.tick < until:
			assert_int(p.path.size()).is_equal(1)
			assert_that(p.at).is_equal(cell)
			assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
			_world.step()
		assert_int(p.collect_tick).is_equal(0)
		assert_int(p.stage_tick).is_equal(until)
		assert_int(p.path.size()).is_greater_equal(2)


## A save taken while a walker whose seat went after the park collects its
## roller carries its collect_tick and loads (valid() accepts it); the load
## sets it off at once, as for a mid-park loss (on_load()).
func test_a_save_mid_collect_after_the_park_loads() -> void:
	var p := _walker(true, false)
	_world.step()
	_seat_goes()
	_world.step()
	var until := p.collect_tick
	assert_int(until).is_equal(_world.sim.tick + ParkRecovery.COLLECT_TICKS)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_world.sim.to_snapshot()))
	assert_int(int(_record_of(saved, p.id)["collect_tick"])).is_equal(until)
	assert_bool(_world.sim.from_snapshot(saved)).is_true()
	var loaded := _world.passenger(p.id)
	assert_int(loaded.collect_tick).is_equal(0)
	assert_int(loaded.stage_tick).is_equal(_world.sim.tick + 1)
	assert_int(_ticks_to_route(loaded, 3)).is_between(0, 2)


## A save taken while a walker collects its roller (a JSON round trip) loads,
## and the load sets it off at once: the view draws the bag in the pull after a
## load (PassengerViews releases every carry record), so its collect_tick is
## cleared and it plans its way on the next tick. A version 16 save, which has
## none, is refused.
func test_a_load_mid_collect_sets_the_walker_off_at_once() -> void:
	var p := _walker(true)
	_world.step()
	_world.step()
	_seat_goes()
	_world.step()
	var until := p.collect_tick
	assert_int(until).is_greater(_world.sim.tick + 2)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_world.sim.to_snapshot()))
	assert_int(int(saved["save_version"])).is_equal(PassengerSim.SAVE_VERSION)
	assert_int(int(_record_of(saved, p.id)["collect_tick"])).is_equal(until)
	var old := saved.duplicate(true)
	old["save_version"] = 16
	for record: Dictionary in old["passengers"]:
		record.erase("collect_tick")
	assert_bool(_world.sim.from_snapshot(old)).is_false()
	assert_bool(_world.sim.from_snapshot(saved)).is_true()
	var loaded := _world.passenger(p.id)
	var at := _world.sim.tick
	print(
		"loaded at tick %d: collect %d stage_tick %d" % [at, loaded.collect_tick, loaded.stage_tick]
	)
	assert_int(loaded.collect_tick).is_equal(0)
	assert_int(loaded.stage_tick).is_equal(at + 1)
	assert_int(_ticks_to_route(loaded, 3)).is_between(0, 2)


## A saved collect_tick the sim could not have written is refused: too far
## ahead of the save's tick, already past, on a walker not on its way to the
## gate, or on one with no roller. Control: the save as written loads.
func test_an_impossible_collect_tick_is_refused() -> void:
	var p := _walker(true)
	_world.step()
	_seat_goes()
	_world.step()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_world.sim.to_snapshot()))
	var tick := _world.sim.tick
	var bad := [
		["collect_tick", tick + ceili(RollerPark.TICKS_DOWN) + ParkRecovery.COLLECT_TICKS + 1],
		["collect_tick", tick],
		["collect_tick", -5],
		["stage", Passenger.Stage.SEATED],
		["carry_on", 0],
	]
	for c: Array in bad:
		var data: Dictionary = saved.duplicate(true)
		_record_of(data, p.id)[c[0]] = c[1]
		print("%s = %s" % [c[0], c[1]])
		assert_bool(_world.sim.from_snapshot(data)).is_false()
	assert_bool(_world.sim.from_snapshot(saved)).is_true()


## A walker late as it began sitting down is not held when its seat goes: it
## carried its roller lifted and set it down with no park (CarryOnProps.
## _lifted()), and it must not miss its flight waiting for nothing. Noted on
## the tick after the sit-down began (ParkRecovery.note_sitting()).
func test_a_walker_late_as_it_sat_down_is_not_held() -> void:
	var p := _walker(true)
	p.late = true
	_world.step()
	assert_bool(p.sat_late).is_true()
	_seat_goes()
	_world.step()
	var sent := _world.sim.tick
	print("late as it sat: collect %d" % p.collect_tick)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
	assert_int(p.collect_tick).is_equal(0)
	assert_int(p.stage_tick).is_equal(sent)


## Seated after a park it did not make, the same walker is not held either.
func test_a_walker_late_as_it_sat_down_is_not_held_seated_either() -> void:
	var p := _walker(true)
	p.late = true
	_world.step()
	assert_bool(p.sat_late).is_true()
	for n in PassengerSim.SIT_DOWN_TICKS:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SEATED)
	_seat_goes()
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
	assert_int(p.collect_tick).is_equal(0)


## A walker on time as it began sitting down that turns late in the park keeps
## the park (RollerPark.holds_lift()), so when its seat goes it is held to
## collect the roller like any other. Control: it was noted on time.
func test_a_walker_turning_late_in_the_park_is_still_held() -> void:
	var p := _walker(true)
	var sat := _world.sim.tick
	_world.step()
	assert_bool(p.sat_late).is_false()
	p.late = true
	_world.step()
	_seat_goes()
	_world.step()
	print("turned late in the park: late %s collect %d" % [p.late, p.collect_tick])
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
	assert_int(p.collect_tick).is_equal(ParkRecovery.collect_of(sat))


## The record of passenger `id` in a passenger save `data`.
func _record_of(data: Dictionary, id: int) -> Dictionary:
	for record: Dictionary in data["passengers"]:
		if int(record["id"]) == id:
			return record
	assert_bool(false).override_failure_message("no record of passenger %d" % id).is_true()
	return {}
