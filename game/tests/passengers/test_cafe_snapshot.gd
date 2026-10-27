class_name TestCafeSnapshot
extends GdUnitTestSuite
## Save version 4 (decision cafe-visit-design-forecast-the-whole-itinerary-
## abandon-by-a, point 8): the cafe state that cannot be rebuilt (queue order,
## reserved seats, where each journey resumes, service and dwell progress,
## settlement, hunger and cooldowns) is saved, so a load in the middle of
## visits plays out exactly like continuous play, and a settled visit is never
## paid twice.

const HUNGRY := 59

var _a: PassengerTestWorld
var _b: PassengerTestWorld
var _paid_b := 0


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in [_a, _b]:
		if world != null:
			world.free_all()
	_a = null
	_b = null
	_paid_b = 0


func _cafe_world() -> PassengerTestWorld:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid, true)
	return PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 4242)


func _save(world: PassengerTestWorld) -> String:
	return (
		JSON
		. stringify(
			{
				"clock": world.clock.to_snapshot(),
				"flights": world.flights.to_snapshot(),
				"grid": world.grid.to_snapshot(),
				"passengers": world.sim.to_snapshot(),
				"wallet": world.sim.wallet.to_snapshot(),
			}
		)
	)


func _load(text: String) -> PassengerTestWorld:
	var data: Dictionary = JSON.parse_string(text)
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	assert_bool(world.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(world.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(world.sim.from_snapshot(data["passengers"])).is_true()
	assert_bool(world.sim.wallet.from_snapshot(data["wallet"])).is_true()
	return world


## The passenger signature plus every cafe visit, queue and the wallet.
func _signature(world: PassengerTestWorld) -> String:
	var cafes := world.sim.cafes
	var parts := PackedStringArray([world.signature(), str(world.sim.wallet.balance)])
	for id in cafes.visit_ids():
		var v := cafes.visit_of(id)
		(
			parts
			. append(
				(
					"%d|%d|%d|%s|%d|%d|%d|%d|%s|%d|%s|%d|%d|%d"
					% [
						id,
						v.room,
						v.counter,
						v.seat_key,
						v.resume_stage,
						v.deadline,
						v.service_end,
						v.dwell_end,
						v.served,
						v.outcome,
						v.settled,
						v.amount,
						world.passenger(id).hunger,
						world.passenger(id).cafe_cooldown,
					]
				)
			)
		)
	for counter in [1, 2, 3, 4, 100]:
		parts.append("%s>%d" % [cafes.queue_of(counter), cafes.serving_at(counter)])
	return ";".join(parts)


func _stages_in_cafe(world: PassengerTestWorld) -> Dictionary:
	var out := {}
	for id in world.sim.cafes.visit_ids():
		out[world.passenger(id).stage] = int(out.get(world.passenger(id).stage, 0)) + 1
	return out


func test_a_save_in_the_middle_of_visits_plays_out_identically_through_doors_close() -> void:
	_a = _cafe_world()
	for i in 10:
		_a.passenger(_a.sim.spawn_now(PassengerTestWorld.FLIGHT)).hunger = HUNGRY
	# Run until one guest sits and another is still queuing or ordering.
	var waiting := [Passenger.Stage.CAFE_QUEUE, Passenger.Stage.CAFE_ORDER]
	while _a.clock.tick < 900:
		_a.step()
		var stages := _stages_in_cafe(_a)
		var queued: int = stages.get(waiting[0], 0) + stages.get(waiting[1], 0)
		if stages.has(Passenger.Stage.CAFE_SEATED) and queued > 0:
			break
	print("saved at %d with %s" % [_a.clock.tick, _stages_in_cafe(_a)])
	assert_int(_a.clock.tick).is_less(900)
	_b = _load(_save(_a))
	assert_str(_signature(_b)).is_equal(_signature(_a))
	var first_bad := -1
	while _a.clock.tick <= _a.flights.doors_close_tick(PassengerTestWorld.FLIGHT):
		_a.step()
		_b.step()
		if first_bad < 0 and _signature(_a) != _signature(_b):
			first_bad = _a.clock.tick
	assert_int(first_bad).override_failure_message("first differing tick %d" % first_bad).is_equal(
		-1
	)
	print("wallet %d made %d" % [_a.sim.wallet.balance, _a.sim.made_count()])
	assert_int(_a.sim.wallet.balance).is_greater(0)
	assert_int(_b.sim.wallet.balance).is_equal(_a.sim.wallet.balance)


func test_a_visit_saved_after_it_was_paid_is_not_paid_again() -> void:
	_a = _cafe_world()
	var p := _a.passenger(_a.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = HUNGRY
	while p.stage != Passenger.Stage.CAFE_STANDING_UP and _a.clock.tick < 1400:
		_a.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_STANDING_UP)
	assert_bool(_a.sim.cafes.visit_of(p.id).settled).is_true()
	var balance := _a.sim.wallet.balance
	_b = _load(_save(_a))
	_b.sim.cafes.paid.connect(func(_id: int, _room: int, _amount: int) -> void: _paid_b += 1)
	assert_bool(_b.sim.cafes.visit_of(p.id).settled).is_true()
	assert_int(_b.sim.wallet.balance).is_equal(balance)
	_b.run_to(_b.clock.tick + 2 * PassengerSim.STAND_UP_TICKS)
	assert_object(_b.sim.cafes.visit_of(p.id)).is_null()
	assert_int(_b.sim.wallet.balance).is_equal(balance)
	assert_int(_paid_b).is_equal(0)


func test_bad_cafe_state_is_rejected_whole() -> void:
	_a = _cafe_world()
	for i in 4:
		_a.passenger(_a.sim.spawn_now(PassengerTestWorld.FLIGHT)).hunger = HUNGRY
	while _a.sim.cafes.visit_ids().size() < 2 and _a.clock.tick < 900:
		_a.step()
	_a.step()
	var good: Dictionary = JSON.parse_string(JSON.stringify(_a.sim.to_snapshot()))
	var visits: Array = good["cafe"]["visits"]
	assert_int(visits.size()).is_greater_equal(2)
	var guest := int(visits[0]["passenger"])
	var bad_cases: Array = []
	var no_cafe := good.duplicate(true)
	no_cafe.erase("cafe")
	bad_cases.append(["no cafe key", no_cafe])
	for key: String in visits[0]:
		var missing := good.duplicate(true)
		missing["cafe"]["visits"][0].erase(key)
		bad_cases.append(["visit without " + key, missing])
	for change in [
		["passenger", 12345],
		["resume_stage", Passenger.Stage.APRON],
		["outcome", 9],
		["amount", -1],
		["served", 1],
		["seat_key", 7],
		["deadline", 1.5],
	]:
		var bad := good.duplicate(true)
		bad["cafe"]["visits"][0][change[0]] = change[1]
		bad_cases.append([str(change), bad])
	var settled_unserved := good.duplicate(true)
	settled_unserved["cafe"]["visits"][0]["settled"] = true
	settled_unserved["cafe"]["visits"][0]["outcome"] = CafeVisit.Outcome.NONE
	bad_cases.append(["settled with no outcome", settled_unserved])
	var same_seat := good.duplicate(true)
	same_seat["cafe"]["visits"][1]["seat_key"] = visits[0]["seat_key"]
	bad_cases.append(["two guests on one seat", same_seat])
	var repeated := good.duplicate(true)
	repeated["cafe"]["visits"].append(repeated["cafe"]["visits"][0].duplicate())
	bad_cases.append(["repeated visit", repeated])
	var ghost := good.duplicate(true)
	ghost["cafe"]["queues"].append({"counter": 999, "room": 1, "lane": [54321], "serving": 0})
	bad_cases.append(["queue of an unknown guest", ghost])
	var twice := good.duplicate(true)
	twice["cafe"]["queues"].append({"counter": 998, "room": 1, "lane": [guest], "serving": 0})
	bad_cases.append(["guest in two queues", twice])
	var lost := good.duplicate(true)
	lost["cafe"]["visits"].remove_at(0)
	bad_cases.append(["guest in a cafe stage with no visit", lost])
	var stray := good.duplicate(true)
	for record in stray["passengers"]:
		if int(record["id"]) == guest:
			record["stage"] = Passenger.Stage.TO_CHECKIN
	bad_cases.append(["visit of a passenger not at the cafe", stray])
	var hunger := good.duplicate(true)
	hunger["passengers"][0]["hunger"] = CafeSim.HUNGER_MAX + 1
	bad_cases.append(["hunger above the cap", hunger])
	_b = _cafe_world()
	var before := _signature(_b)
	for case in bad_cases:
		var loaded := _b.sim.from_snapshot(case[1])
		assert_bool(loaded).override_failure_message(case[0]).is_false()
		assert_str(_signature(_b)).is_equal(before)
	assert_bool(_b.sim.from_snapshot(good)).is_true()
	assert_str(_b.signature()).is_equal(_a.signature())
	assert_array(_b.sim.cafes.visit_ids()).is_equal(_a.sim.cafes.visit_ids())
