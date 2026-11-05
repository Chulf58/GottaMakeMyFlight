class_name TestGateCapacitySave
extends GdUnitTestSuite
## The gate places in the forecast and in a save (decision gate-full-design-
## passengers-reserve-a-gate-seat-or-standing, point 5; PassengerSim save
## version 25): a front blocked by a full gate forecasts NEVER, and once a
## place frees its forecast equals its measured clearance; a save taken at a
## tick boundary while the gate is full, with a reservation held inside
## security, plays on exactly through JSON; a malformed "gate_places" is
## refused whole.

var _gate: GateFullWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	_gate = null


func _json(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))


## A full gate with SPOTS standers and a front stuck GATE_FULL behind which
## one more passenger waits; returns [front, behind].
func _full_gate() -> Array[Passenger]:
	_gate = GateFullWorld.make()
	_gate.send_many(GateFullWorld.SPOTS + 2)
	var full := func() -> bool:
		var f := _gate.front()
		var lane := _gate.world.sim.queue_of(_gate.station)
		return f != null and f.stuck == Passenger.Stuck.GATE_FULL and lane.size() == 2
	assert_bool(_gate.run_until(full)).is_true()
	var lane := _gate.world.sim.queue_of(_gate.station)
	return [_gate.world.passenger(lane[0]), _gate.world.passenger(lane[1])]


## Lets the first stander go: its spot is free from now on.
func _free_one_place() -> void:
	var sim := _gate.world.sim
	for id in sim.passenger_ids():
		if _gate.world.passenger(id).stage == Passenger.Stage.STANDING:
			sim._finish(_gate.world.passenger(id), true)
			return


func test_the_forecast_waits_for_a_free_place_then_equals_the_clearance() -> void:
	var held := _full_gate()
	var sim := _gate.world.sim
	var blocked := SecurityForecast.eta(sim, held[0])
	_free_one_place()
	var forecast := sim.tick + SecurityForecast.eta(sim, held[0])
	var behind := SecurityForecast.eta(sim, held[1])
	var cleared := func() -> bool: return held[0].cleared
	assert_bool(_gate.run_until(cleared, 600)).is_true()
	var measured := sim.tick
	_gate.world.run_to(sim.tick + 400)
	print(
		(
			"blocked %d, after a place frees forecast %d measured %d; behind %d, cleared %s"
			% [blocked, forecast, measured, behind, held[1].cleared]
		)
	)
	assert_int(blocked).is_equal(JourneyForecast.NEVER)
	assert_int(forecast).is_equal(measured)
	assert_int(behind).is_equal(JourneyForecast.NEVER)
	assert_bool(held[1].cleared).is_false()
	assert_int(held[1].stuck).is_equal(Passenger.Stuck.GATE_FULL)


## Saves on the tick boundaries of a hold: the gate full, a place freed by a
## stander whose boarding opens early, the front admitted with a reservation,
## then cleared; each load plays on as continuous play did.
func test_a_save_mid_hold_plays_on_exactly() -> void:
	var held := _full_gate()
	var a := _gate
	var sim := a.world.sim
	var saves := []
	var trace := {}
	var reserved_saved := 0
	var stop := sim.tick + 500
	# A stander boards early, inside the sim, so a load replays it too: its spot
	# frees once it has stepped off it.
	for id in sim.passenger_ids():
		if a.world.passenger(id).stage == Passenger.Stage.STANDING:
			a.world.passenger(id).boarding_tick = sim.tick + 50
			break
	while sim.tick < stop:
		var data := _json(sim.to_snapshot())
		var places: Array = data["gate_places"]
		if sim.tick % 40 == 0 or (not places.is_empty() and sim.tick % 5 == 0):
			reserved_saved += int(not places.is_empty())
			(
				saves
				. append(
					[
						sim.tick,
						_json(a.world.clock.to_snapshot()),
						_json(a.world.flights.to_snapshot()),
						data,
					]
				)
			)
		a.world.step()
		trace[sim.tick] = a.world.signature()
	assert_bool(held[0].cleared).is_true()
	var bad := []
	for save: Array in saves:
		var b := GateFullWorld.make()
		assert_bool(b.world.clock.from_snapshot(save[1])).is_true()
		assert_bool(b.world.flights.from_snapshot(save[2])).is_true()
		assert_bool(b.world.sim.from_snapshot(save[3])).is_true()
		while b.world.clock.tick < stop:
			b.world.step()
			if b.world.signature() != trace[b.world.sim.tick]:
				bad.append([save[0], b.world.sim.tick])
				_print_difference(trace[b.world.sim.tick], b.world.signature())
				break
	print("%d saves, %d holding a reservation" % [saves.size(), reserved_saved])
	(
		assert_array(bad)
		. override_failure_message("[saved at, first differing tick] %s" % [bad])
		. is_empty()
	)
	assert_int(reserved_saved).is_greater(0)


## Prints the passenger lines of two signatures that differ.
func _print_difference(want: String, got: String) -> void:
	var a := want.split(";")
	var b := got.split(";")
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			print("continuous %s, loaded %s" % [a[i], b[i]])


func test_malformed_gate_places_are_refused() -> void:
	var held := _full_gate()
	var sim := _gate.world.sim
	_free_one_place()
	var reserved := func() -> bool: return held[0].stage == Passenger.Stage.SECURITY
	assert_bool(_gate.run_until(reserved, 100)).is_true()
	var good := _json(sim.to_snapshot())
	var places: Array = good["gate_places"]
	assert_int(places.size()).is_equal(1)
	var spot := int(places[0]["spot"])
	var stander := 0
	for id in sim.passenger_ids():
		if sim.standing.spot_of(id) != StandingSpots.NO_SPOT:
			stander = id
	var cases := {
		"not a list": {"passenger": held[0].id, "spot": spot},
		"an extra field": [{"passenger": held[0].id, "spot": spot, "x": 1}],
		"no place": [{"passenger": held[0].id, "y": 1}],
		"a passenger outside security": [{"passenger": held[1].id, "spot": spot}],
		"an unknown passenger": [{"passenger": 999999, "spot": spot}],
		"an unknown spot": [{"passenger": held[0].id, "spot": 999999}],
		"a claimed spot": [{"passenger": held[0].id, "spot": sim.standing.spot_of(stander)}],
		"an unknown seat": [{"passenger": held[0].id, "seat": "1:0"}],
		"twice": [{"passenger": held[0].id, "spot": spot}, {"passenger": held[0].id, "spot": spot}],
	}
	var accepted := []
	for name: String in cases:
		var bad: Dictionary = good.duplicate(true)
		bad["gate_places"] = cases[name]
		var b := GateFullWorld.make()
		var before := b.world.signature()
		if b.world.sim.from_snapshot(bad):
			accepted.append(name)
		assert_str(b.world.signature()).is_equal(before)
	var missing: Dictionary = good.duplicate(true)
	missing.erase("gate_places")
	var c := GateFullWorld.make()
	print("refused %d of %d malformed cases" % [cases.size() - accepted.size(), cases.size()])
	assert_array(accepted).is_empty()
	assert_bool(c.world.sim.from_snapshot(missing)).is_false()
	var d := GateFullWorld.make()
	assert_bool(d.world.sim.from_snapshot(good)).is_true()
