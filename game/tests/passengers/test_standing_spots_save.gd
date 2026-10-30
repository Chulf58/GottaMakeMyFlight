class_name TestStandingSpotsSave
extends GdUnitTestSuite
## Standing spot claims in a save (PassengerSim version 14, kept in 15): a
## save taken while passengers stand loads into a world that plays out exactly
## like the one that never stopped, claims are restored as saved rather than
## allocated again, a version 14 save is refused and bad claims are refused.

var _a: PassengerTestWorld
var _b: PassengerTestWorld


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


func _save(world: PassengerTestWorld) -> Dictionary:
	return {
		"clock": world.clock.to_snapshot(),
		"flights": world.flights.to_snapshot(),
		"grid": world.grid.to_snapshot(),
		"passengers": world.sim.to_snapshot(),
	}


func _load(data: Dictionary) -> PassengerTestWorld:
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	assert_bool(world.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(world.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(world.sim.from_snapshot(data["passengers"])).is_true()
	return world


## The world's signature plus every standing claim.
func _signature(world: PassengerTestWorld) -> String:
	return "%s#%s" % [world.signature(), JSON.stringify(world.sim.standing.to_list())]


func _standing(world: PassengerTestWorld) -> int:
	var count := 0
	for id in world.sim.passenger_ids():
		count += int(world.passenger(id).stage == Passenger.Stage.STANDING)
	return count


## The reference world with scheduled passengers under way and more cleared
## passengers at the gate than it has seats: saved once three stand on spots
## and one more is walking to its spot.
func _crowded_world() -> PassengerTestWorld:
	var world := PassengerTestWorld.reference_world(4242)
	world.sim.schedule_flight(PassengerTestWorld.FLIGHT, 24)
	world.run_to(200)
	for i in world.sim.layout.seats.size() + 3:
		TestStandingSpotClaims.cleared(world)
	for i in 400:
		world.step()
		if _standing(world) >= 3:
			break
	TestStandingSpotClaims.cleared(world)
	world.step()
	world.step()
	return world


func test_a_save_while_standing_plays_out_identically_through_doors_close() -> void:
	_a = _crowded_world()
	var standing := _standing(_a)
	var claims := _a.sim.standing.claim_count()
	print("save at tick %d: standing %d, claims %d" % [_a.clock.tick, standing, claims])
	assert_int(standing).is_greater_equal(3)
	assert_int(claims).is_greater(standing)
	_b = _load(JSON.parse_string(JSON.stringify(_save(_a))))
	assert_str(_signature(_b)).is_equal(_signature(_a))
	var doors := _a.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	var differing := 0
	var first_bad := -1
	var most_claims := 0
	while _a.clock.tick <= doors:
		_a.step()
		_b.step()
		most_claims = maxi(most_claims, _a.sim.standing.claim_count())
		if _signature(_a) != _signature(_b):
			differing += 1
			if first_bad < 0:
				first_bad = _a.clock.tick
	print("first differing tick %d, most claims %d" % [first_bad, most_claims])
	assert_int(first_bad).override_failure_message("first differing tick %d" % first_bad).is_equal(
		-1
	)
	assert_int(differing).is_equal(0)
	assert_int(most_claims).is_greater_equal(claims)


func test_claims_load_as_saved_not_allocated_again() -> void:
	_a = _crowded_world()
	var data := _save(_a)
	var list: Array = data["passengers"]["standing"]
	var walker: Dictionary = {}
	for entry: Dictionary in list:
		if _a.passenger(entry["passenger"]).stage == Passenger.Stage.TO_GATE:
			walker = entry
	assert_bool(walker.is_empty()).is_false()
	# The walker's claim is moved, in the save, to the free spot farthest from
	# it: a fresh allocation would pick the nearest, a restore keeps this one.
	var p := _a.passenger(walker["passenger"])
	var far: int = _a.sim.standing.free_nearest(p.at).back()
	walker["spot"] = far
	print("walker %d now claims %d; claims %s" % [p.id, far, list])
	_b = _load(JSON.parse_string(JSON.stringify(data)))
	for e: Dictionary in list:
		assert_int(_b.sim.standing.spot_of(e["passenger"])).is_equal(e["spot"])
	assert_int(_b.sim.standing.holder_of(far)).is_equal(p.id)


func test_a_version_14_save_is_refused() -> void:
	_a = _crowded_world()
	var data := _save(_a)
	assert_int(int(data["passengers"]["save_version"])).is_equal(15)
	data["passengers"]["save_version"] = 14
	_b = PassengerTestWorld.reference_world()
	var before := _b.signature()
	assert_bool(_b.sim.from_snapshot(data["passengers"])).is_false()
	assert_str(_b.signature()).is_equal(before)


func test_bad_standing_claims_are_refused_whole() -> void:
	_a = _crowded_world()
	var good := _save(_a)
	var list: Array = good["passengers"]["standing"]
	var first: Dictionary = list[0]
	var stander := -1
	for i in list.size():
		if _a.passenger(list[i]["passenger"]).stage == Passenger.Stage.STANDING:
			stander = i
	assert_int(stander).is_greater_equal(0)
	var cases := {
		"standing without its claim":
		func(d: Dictionary) -> void: (d["standing"] as Array).remove_at(stander),
		"missing": func(d: Dictionary) -> void: d.erase("standing"),
		"not a list": func(d: Dictionary) -> void: d["standing"] = {},
		"unknown spot": func(d: Dictionary) -> void: d["standing"][0]["spot"] = -5,
		"unknown passenger": func(d: Dictionary) -> void: d["standing"][0]["passenger"] = 99999,
		"spot twice": func(d: Dictionary) -> void: d["standing"][1]["spot"] = first["spot"],
		"passenger twice": func(d: Dictionary) -> void: d["standing"].append(first.duplicate()),
		"extra key": func(d: Dictionary) -> void: d["standing"][0]["x"] = 1,
	}
	for name: String in cases:
		var data: Dictionary = good["passengers"].duplicate(true)
		(cases[name] as Callable).call(data)
		_b = PassengerTestWorld.reference_world()
		var before := _b.signature()
		assert_bool(_b.sim.from_snapshot(data)).override_failure_message(name).is_false()
		assert_str(_b.signature()).is_equal(before)
		_b.free_all()
	_b = null


func test_a_room_placed_over_a_claimed_spot_drops_the_claim_and_saves_cleanly() -> void:
	_a = TestStandingSpotClaims.seatless_world()
	var p := TestStandingSpotClaims.cleared(_a)
	for i in 300:
		_a.step()
		if p.stage == Passenger.Stage.STANDING:
			break
	assert_int(p.stage).is_equal(Passenger.Stage.STANDING)
	var cell := _a.sim.standing.cell_of(_a.sim.standing.spot_of(p.id))
	# A room edit relinks nothing, so it fires edit_applied but no graph_changed.
	var room := _a.grid.apply(BuildEdit.place_room(Rect2i(cell, Vector2i.ONE), &"kiosk"))
	assert_bool(room.ok).override_failure_message(room.reason_text()).is_true()
	_a.step()
	var spot := _a.sim.standing.spot_of(p.id)
	print("room over %s: claim now %d, stage %s" % [cell, spot, Passenger.Stage.keys()[p.stage]])
	if spot != StandingSpots.NO_SPOT:
		assert_that(_a.sim.standing.cell_of(spot)).is_not_equal(cell)
	_b = _load(JSON.parse_string(JSON.stringify(_save(_a))))
	assert_str(_signature(_b)).is_equal(_signature(_a))
