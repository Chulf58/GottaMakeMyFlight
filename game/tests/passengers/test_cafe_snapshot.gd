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
## The ids CafeTestLayout.build() gave the last cafe world's pieces.
var _ids: Dictionary


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
	_ids = CafeTestLayout.build(grid, true)
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


## The index in a save's cafe visits of the first guest in `stage`, or -1.
func _visit_index(save: Dictionary, stage: Passenger.Stage) -> int:
	var stages := {}
	for record in save["passengers"]:
		stages[int(record["id"])] = int(record["stage"])
	var visits: Array = save["cafe"]["visits"]
	for i in visits.size():
		if stages[int(visits[i]["passenger"])] == stage:
			return i
	return -1


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


func test_a_save_between_an_edit_and_the_next_tick_loads_and_plays_on_alike() -> void:
	_a = _cafe_world()
	var p := _a.passenger(_a.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = HUNGRY
	while p.stage != Passenger.Stage.CAFE_SEATED and _a.clock.tick < 1400:
		_a.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_SEATED)
	# The guest's table goes while the game is paused, and the game is saved.
	var visit := _a.sim.cafes.visit_of(p.id)
	var table := int(visit.seat_key.split(":")[0])
	assert_bool(_a.grid.apply(BuildEdit.remove_object(table)).ok).is_true()
	assert_bool(_a.sim.cafes.deadlines_stale).is_true()
	var balance := _a.sim.wallet.balance
	_b = _load(_save(_a))
	# The save brought the cafe in line with the grid first: the guest's seat
	# is gone, so it pays the short share and goes on, in the saved game too.
	assert_bool(_a.sim.cafes.deadlines_stale).is_false()
	var airside := visit.resume_stage == Passenger.Stage.TO_GATE
	var base := RoomTypes.get_type(&"cafe").base_spend
	var short := CafeSim.spend(base, p.mood, airside, CafeVisit.Outcome.SHORT)
	assert_int(visit.outcome).is_equal(CafeVisit.Outcome.SHORT)
	for world in [_a, _b]:
		assert_object(world.sim.cafes.visit_of(p.id)).is_null()
		assert_int(world.passenger(p.id).stage).is_equal(visit.resume_stage)
		assert_int(world.sim.wallet.balance).is_equal(balance + short)
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
	assert_object(_b.sim.cafes.visit_of(p.id)).is_null()
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)


func test_bad_cafe_state_is_rejected_whole() -> void:
	_a = _cafe_world()
	for i in 10:
		_a.passenger(_a.sim.spawn_now(PassengerTestWorld.FLIGHT)).hunger = HUNGRY
	# A moment with one guest seated (served) and one still queuing.
	while _a.clock.tick < 900:
		_a.step()
		var stages := _stages_in_cafe(_a)
		if stages.has(Passenger.Stage.CAFE_SEATED) and stages.has(Passenger.Stage.CAFE_QUEUE):
			break
	var good: Dictionary = JSON.parse_string(JSON.stringify(_a.sim.to_snapshot()))
	var visits: Array = good["cafe"]["visits"]
	assert_int(visits.size()).is_greater_equal(2)
	var guest := int(visits[0]["passenger"])
	var queuing := _visit_index(good, Passenger.Stage.CAFE_QUEUE)
	var seated := _visit_index(good, Passenger.Stage.CAFE_SEATED)
	assert_int(queuing).is_greater_equal(0)
	assert_int(seated).is_greater_equal(0)
	var bad_cases: Array = []
	var queued_visit: Dictionary = visits[queuing]
	# The other cafe's room and counter, from the built layout.
	var airside := int(queued_visit["room"]) == int(_ids["air_room"])
	var other_room: int = _ids["land_room"] if airside else _ids["air_room"]
	var other_counter: int = _ids["land_counter"] if airside else _ids["air_counter"]
	assert_int(other_room).is_not_equal(int(queued_visit["room"]))
	assert_int(other_room).is_greater(0)
	assert_int(other_counter).is_greater(0)
	for change in [
		["room", -1],
		["room", 999],
		["counter", 0],
		["counter", 999],
		["seat_key", ""],
		["seat_key", "999:0"],
	]:
		var bad := good.duplicate(true)
		bad["cafe"]["visits"][queuing][change[0]] = change[1]
		bad_cases.append(["queuing guest " + str(change), bad])
	var settled_queuing := good.duplicate(true)
	settled_queuing["cafe"]["visits"][queuing]["settled"] = true
	settled_queuing["cafe"]["visits"][queuing]["outcome"] = CafeVisit.Outcome.COMPLETE
	settled_queuing["cafe"]["visits"][queuing]["amount"] = 15
	bad_cases.append(["unserved queuing guest settled COMPLETE", settled_queuing])
	var short_queuing := good.duplicate(true)
	short_queuing["cafe"]["visits"][queuing]["outcome"] = CafeVisit.Outcome.SHORT
	bad_cases.append(["unserved queuing guest with an outcome", short_queuing])
	var unpaid_amount := good.duplicate(true)
	unpaid_amount["cafe"]["visits"][seated]["amount"] = 12
	bad_cases.append(["an amount on a visit not settled", unpaid_amount])
	var seated_done := good.duplicate(true)
	seated_done["cafe"]["visits"][seated]["outcome"] = CafeVisit.Outcome.COMPLETE
	seated_done["cafe"]["visits"][seated]["settled"] = true
	bad_cases.append(["seated guest already settled", seated_done])
	var wrong_side := good.duplicate(true)
	var side: int = wrong_side["cafe"]["visits"][queuing]["resume_stage"]
	wrong_side["cafe"]["visits"][queuing]["resume_stage"] = (
		Passenger.Stage.TO_GATE
		if side == Passenger.Stage.TO_SECURITY
		else Passenger.Stage.TO_SECURITY
	)
	bad_cases.append(["resumes on the wrong side of security", wrong_side])
	for entry_change in [["room", 999], ["room", other_room], ["counter", -3]]:
		var bad := good.duplicate(true)
		for entry in bad["cafe"]["queues"]:
			if (entry["lane"] as Array).has(queued_visit["passenger"]):
				entry[entry_change[0]] = entry_change[1]
		bad_cases.append(["queue " + str(entry_change), bad])
	# The queue and every guest in it moved to the other cafe's counter, so
	# only the counter's room disagrees.
	var swapped := good.duplicate(true)
	for entry in swapped["cafe"]["queues"]:
		if (entry["lane"] as Array).has(queued_visit["passenger"]):
			entry["counter"] = other_counter
			for visit: Dictionary in swapped["cafe"]["visits"]:
				if (entry["lane"] as Array).has(visit["passenger"]):
					visit["counter"] = other_counter
	bad_cases.append(["queuing at the other cafe's counter", swapped])
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
