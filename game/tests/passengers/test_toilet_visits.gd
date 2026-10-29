class_name TestToiletVisits
extends GdUnitTestSuite
## Toilet visits (decision toilet-design-queue-free-reservable-stalls-per-
## stall-daily-u, point 1): a visit reserves its stall when it is committed,
## so a walker holds it; with every stall reserved a passenger carries on and
## tries again after ToiletSim.RETRY_TICKS; the visit walks to the approach
## cell, steps in, sits, uses the stall, stands up and steps out, resets the
## need and goes on where it left off. A stall that goes ends the visit.

var _world: PassengerTestWorld
var _ids: Dictionary
## Passenger id -> [[stage, tick], ...] in the order the stages were entered.
var _stages: Dictionary = {}


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null
	_stages.clear()


func _toilet_world(stalls := 2) -> PassengerTestWorld:
	var grid := BuildGrid.new()
	_ids = ToiletTestLayout.build(grid, stalls)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var sim := _world.sim
	sim.stage_changed.connect(
		func(id: int, stage: Passenger.Stage) -> void:
			if not _stages.has(id):
				_stages[id] = []
			_stages[id].append([stage, sim.tick])
	)
	# Staff come on duty on the first ticks; until then security is closed and
	# no journey after a visit can be forecast.
	_world.run_to(10)
	return _world


## A calm, checked-in passenger with no bags heading for security from free
## floor between the scanner lanes and the east wall.
func _landside() -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.stage = Passenger.Stage.TO_SECURITY
	p.stage_tick = _world.clock.tick
	p.at = Vector2i(20, 14)
	p.clear_path()
	return p


func _run_until(p: Passenger, stage: Passenger.Stage, limit := 3000) -> void:
	var until := _world.clock.tick + limit
	while p.stage != stage and _world.clock.tick < until:
		_world.step()


func _stage_names(id: int) -> Array:
	var out: Array = []
	for entry: Array in _stages.get(id, []):
		out.append(Passenger.Stage.keys()[entry[0]])
	return out


func test_a_visit_walks_in_sits_uses_the_stall_and_goes_on_with_the_need_reset() -> void:
	_toilet_world()
	var p := _landside()
	p.toilet_need = 90
	_stages.erase(p.id)
	assert_bool(_world.sim.toilets.try_visit(p)).is_true()
	var visit := _world.sim.toilets.visit_of(p.id)
	assert_bool((_ids["land_stalls"] as Array).has(visit.stall_id)).is_true()
	assert_int(visit.resume_stage).is_equal(Passenger.Stage.TO_SECURITY)
	var need_at_stand := [-1]
	_world.sim.stage_changed.connect(
		func(id: int, stage: Passenger.Stage) -> void:
			if id == p.id and stage == Passenger.Stage.TOILET_STANDING_UP:
				need_at_stand[0] = p.toilet_need
	)
	var used := [false]
	while _world.sim.toilets.visit_of(p.id) != null and _world.clock.tick < 3000:
		_world.step()
		if p.stage == Passenger.Stage.TOILET_USE:
			used[0] = true
			assert_that(_world.sim.world_position(p)).is_equal(visit.stall["use"])
			assert_that(_world.sim.toilets.use_facing(p)).is_equal(Vector2i(0, 1))
	var names := _stage_names(p.id)
	print("stages %s, need at stand-up %d" % [names, need_at_stand[0]])
	(
		assert_array(names.slice(0, 7))
		. is_equal(
			[
				"TOILET_WALK",
				"TOILET_ENTER",
				"TOILET_SITTING_DOWN",
				"TOILET_USE",
				"TOILET_STANDING_UP",
				"TOILET_EXIT",
				"TO_SECURITY",
			]
		)
	)
	assert_bool(used[0]).is_true()
	assert_int(need_at_stand[0]).is_equal(0)
	# Each timed phase lasted its own length.
	var ticks: Array = []
	for entry: Array in _stages[p.id]:
		ticks.append(entry[1])
	assert_int(ticks[2] - ticks[1]).is_equal(ToiletSim.ENTER_TICKS)
	assert_int(ticks[3] - ticks[2]).is_equal(PassengerSim.SIT_DOWN_TICKS)
	assert_int(ticks[4] - ticks[3]).is_equal(ToiletSim.USE_TICKS)
	assert_int(ticks[5] - ticks[4]).is_equal(PassengerSim.STAND_UP_TICKS)
	assert_int(ticks[6] - ticks[5]).is_equal(ToiletSim.EXIT_TICKS)
	assert_int(_world.sim.toilets.stall_holder(visit.stall_id)).is_equal(0)
	assert_that(p.at).is_equal(visit.stall["approach"])
	_world.run_to(_world.flights.doors_close_tick(PassengerTestWorld.FLIGHT) + 1)
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)


func test_a_walker_holds_its_stall_and_a_second_passenger_is_refused() -> void:
	_toilet_world(1)
	var first := _landside()
	var second := _landside()
	var stall: int = _ids["land_stalls"][0]
	assert_bool(_world.sim.toilets.try_visit(first)).is_true()
	_world.step()
	# Still walking to the stall, and the stall is held for it.
	assert_int(first.stage).is_equal(Passenger.Stage.TOILET_WALK)
	assert_bool(first.is_moving()).is_true()
	assert_int(_world.sim.toilets.stall_holder(stall)).is_equal(first.id)
	print("first %d walking holds stall %d" % [first.id, stall])
	# The airside stall cannot be reached before security, so nothing is free.
	assert_bool(_world.sim.toilets.try_visit(second)).is_false()
	assert_object(_world.sim.toilets.visit_of(second.id)).is_null()
	assert_int(second.stage).is_equal(Passenger.Stage.TO_SECURITY)
	# Once the first is done the stall is free again.
	while _world.sim.toilets.visit_of(first.id) != null and _world.clock.tick < 3000:
		_world.step()
	assert_int(_world.sim.toilets.stall_holder(stall)).is_equal(0)
	var third := _landside()
	assert_bool(_world.sim.toilets.try_visit(third)).is_true()
	assert_int(_world.sim.toilets.stall_holder(stall)).is_equal(third.id)


func test_with_every_stall_reserved_a_passenger_carries_on_and_retries_later() -> void:
	_toilet_world(1)
	var first := _landside()
	var waiting := _landside()
	assert_bool(_world.sim.toilets.try_visit(first)).is_true()
	waiting.toilet_need = 95
	waiting.toilet_cooldown = 0
	var mood := waiting.mood
	# Its next beat: refused, it keeps walking and gets a cooldown.
	var beat := _world.clock.tick + 1
	while posmod(beat, PassengerSim.BEAT_TICKS) != posmod(waiting.id, PassengerSim.BEAT_TICKS):
		beat += 1
	_world.run_to(beat)
	print("refused at %d, cooldown %d" % [beat, waiting.toilet_cooldown])
	assert_int(waiting.toilet_cooldown).is_equal(beat + ToiletSim.RETRY_TICKS)
	assert_object(_world.sim.toilets.visit_of(waiting.id)).is_null()
	assert_bool(StageKinds.in_visit(waiting.stage)).is_false()
	# It goes once the stall is free and its cooldown has passed, on its own.
	var went := -1
	while went < 0 and _world.clock.tick < beat + 3000:
		_world.step()
		if _world.sim.toilets.visit_of(waiting.id) != null:
			went = _world.clock.tick
	print("first done, waiting went at %d, mood %d -> %d" % [went, mood, waiting.mood])
	assert_int(went).is_greater_equal(beat + ToiletSim.RETRY_TICKS)
	# A high need with no visit cost mood while it waited.
	assert_int(waiting.mood).is_less(mood)


func test_the_free_stall_nearest_by_path_is_chosen() -> void:
	_toilet_world()
	var p := _landside()
	var stalls: Array = _ids["land_stalls"]
	var layout := _world.sim.toilets.layout
	_world.sim.toilets.refresh()
	var lengths: Array = []
	for id: int in stalls:
		lengths.append(VisitRoute.plan(_world.grid, p, layout.stall(id)["approach"])["mm"])
	assert_bool(_world.sim.toilets.try_visit(p)).is_true()
	var chosen := _world.sim.toilets.visit_of(p.id).stall_id
	print("walks %s to stalls %s, chose %d" % [lengths, stalls, chosen])
	var best: int = stalls[0] if int(lengths[0]) <= int(lengths[1]) else stalls[1]
	assert_int(chosen).is_equal(best)
	# With the nearest held, the other one is taken.
	var other := _landside()
	assert_bool(_world.sim.toilets.try_visit(other)).is_true()
	assert_int(_world.sim.toilets.visit_of(other.id).stall_id).is_not_equal(chosen)


func test_a_seated_gate_passenger_stands_up_first_and_goes_back_airside() -> void:
	_toilet_world()
	var p := _landside()
	_run_until(p, Passenger.Stage.SEATED)
	assert_int(p.stage).is_equal(Passenger.Stage.SEATED)
	_stages.erase(p.id)
	assert_bool(_world.sim.toilets.try_visit(p)).is_true()
	assert_int(p.stage).is_equal(Passenger.Stage.STANDING_UP)
	var stall := _world.sim.toilets.visit_of(p.id).stall_id
	assert_bool((_ids["air_stalls"] as Array).has(stall)).is_true()
	_run_until(p, Passenger.Stage.TOILET_WALK)
	# Up from the gate seat, which it no longer holds.
	assert_int(p.seat_object).is_equal(0)
	while _world.sim.toilets.visit_of(p.id) != null and _world.clock.tick < 3000:
		_world.step()
	var names := _stage_names(p.id)
	print("stages %s" % [names])
	assert_str(names[0]).is_equal("STANDING_UP")
	assert_str(names[1]).is_equal("TOILET_WALK")
	assert_str(names[7]).is_equal("TO_GATE")
	assert_int(_world.sim.toilets.stall_holder(stall)).is_equal(0)


func test_a_stall_removed_during_use_ends_the_visit_at_once_with_the_need_reset() -> void:
	_toilet_world()
	var p := _landside()
	p.toilet_need = 80
	assert_bool(_world.sim.toilets.try_visit(p)).is_true()
	var stall := _world.sim.toilets.visit_of(p.id).stall_id
	_run_until(p, Passenger.Stage.TOILET_USE)
	assert_int(p.stage).is_equal(Passenger.Stage.TOILET_USE)
	assert_bool(_world.grid.apply(BuildEdit.remove_object(stall)).ok).is_true()
	_world.step()
	print("after removal: stage %s need %d" % [Passenger.Stage.keys()[p.stage], p.toilet_need])
	assert_object(_world.sim.toilets.visit_of(p.id)).is_null()
	assert_int(_world.sim.toilets.stall_holder(stall)).is_equal(0)
	assert_bool(StageKinds.in_visit(p.stage)).is_false()
	assert_int(p.toilet_need).is_less_equal(ToiletSim.NEED_RISE)


func test_a_stall_removed_while_walking_there_is_given_up_with_the_need_kept() -> void:
	_toilet_world()
	var p := _landside()
	p.toilet_need = 80
	assert_bool(_world.sim.toilets.try_visit(p)).is_true()
	var stall := _world.sim.toilets.visit_of(p.id).stall_id
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.TOILET_WALK)
	assert_bool(_world.grid.apply(BuildEdit.remove_object(stall)).ok).is_true()
	_world.step()
	print("after removal: stage %s need %d" % [Passenger.Stage.keys()[p.stage], p.toilet_need])
	assert_object(_world.sim.toilets.visit_of(p.id)).is_null()
	assert_int(p.stage).is_equal(Passenger.Stage.TO_SECURITY)
	assert_int(p.toilet_need).is_greater_equal(80)
	assert_int(p.toilet_cooldown).is_greater(_world.clock.tick)
