class_name TestGateCapacitySave
extends GdUnitTestSuite
## The gate places in the forecast and in a save (decision gate-full-design-
## passengers-reserve-a-gate-seat-or-standing, point 5; PassengerSim save
## version 25): a front blocked by a full gate waits until its boarding opens,
## when it needs no place, and its forecast equals that measured clearance;
## once a place frees its forecast equals its measured clearance; a save taken at a
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
	# No place frees: the front waits until its boarding opens, then needs none
	# (GateCapacity.placed()).
	var alone := _full_gate()
	var start := _gate.world.sim.tick
	var blocked := start + SecurityForecast.eta(_gate.world.sim, alone[0])
	var alone_cleared := func() -> bool: return alone[0].cleared
	assert_bool(_gate.run_until(alone_cleared)).is_true()
	var blocked_measured := _gate.world.sim.tick
	# The same world, and a place frees: the front takes it, and the one behind
	# waits until its own boarding opens.
	var held := _full_gate()
	var sim := _gate.world.sim
	_free_one_place()
	var forecast := sim.tick + SecurityForecast.eta(sim, held[0])
	var behind := sim.tick + SecurityForecast.eta(sim, held[1])
	var cleared := func() -> bool: return held[0].cleared
	assert_bool(_gate.run_until(cleared, 600)).is_true()
	var measured := sim.tick
	_gate.world.run_to(sim.tick + 400)
	var still_held := held[1].stuck
	var still_cleared := held[1].cleared
	var behind_cleared := func() -> bool: return held[1].cleared
	assert_bool(_gate.run_until(behind_cleared)).is_true()
	var behind_measured := sim.tick
	print(
		(
			(
				"blocked forecast %d measured %d (boarding %d); after a place frees forecast %d"
				+ " measured %d; behind forecast %d measured %d (boarding %d)"
			)
			% [
				blocked,
				blocked_measured,
				alone[0].boarding_tick,
				forecast,
				measured,
				behind,
				behind_measured,
				held[1].boarding_tick,
			]
		)
	)
	assert_int(blocked).is_equal(blocked_measured)
	assert_int(blocked_measured).is_greater_equal(alone[0].boarding_tick)
	assert_int(forecast).is_equal(measured)
	# Long after the front, the one behind is still held for a place.
	assert_bool(still_cleared).is_false()
	assert_int(still_held).is_equal(Passenger.Stuck.GATE_FULL)
	assert_int(behind).is_equal(behind_measured)
	assert_int(behind_measured).is_greater_equal(held[1].boarding_tick)


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


## A passenger of `world` with the given stage and, when `roller`, one bag that
## is a roller (spawned until one is), else no bag.
static func _holder(world: PassengerTestWorld, stage: Passenger.Stage, roller: bool) -> Passenger:
	for attempt in 200:
		var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		p.carry_on = 1
		if ParkRecovery.has_roller(p) == roller:
			p.carry_on = int(roller)
			p.stage = stage
			p.cleared = stage != Passenger.Stage.SECURITY
			return p
	return null


## Saved standing claims and spot reservations are checked together against
## the roller spacing (GateCapacity.checked(), the save gate
## PassengerSim.checked_standing() runs): a roller reservation next to a
## standing passenger and two reservations next to each other, one with a
## roller, are refused; two plain neighbours are not.
func test_saved_places_keep_the_roller_spacing() -> void:
	_gate = GateFullWorld.make()
	var world := _gate.world
	var sim := world.sim
	var spots := sim.standing
	spots.rebuild(sim)
	var ids: Array = spots.spots.keys()
	ids.sort()
	var a: int = ids[0]
	var b := -1
	for id: int in ids:
		var d: Vector2i = spots.spots[id]["mm"] - spots.spots[a]["mm"]
		if id != a and Vector2(d).length() < StandingSpots.ROLLER_CLEAR_MM:
			b = id
			break
	assert_int(b).is_not_equal(-1)
	var stander := _holder(world, Passenger.Stage.STANDING, false)
	var roller := _holder(world, Passenger.Stage.SECURITY, true)
	var plain := _holder(world, Passenger.Stage.SECURITY, false)
	var by_id := {stander.id: stander, roller.id: roller, plain.id: plain}
	var cases := {
		"a roller reservation next to a stander":
		[{stander.id: a}, [{"passenger": roller.id, "spot": b}]],
		"two reservations next to each other, one with a roller":
		[{}, [{"passenger": plain.id, "spot": a}, {"passenger": roller.id, "spot": b}]],
	}
	var accepted := []
	for name: String in cases:
		var result := GateCapacity.checked(cases[name][1], by_id, sim, spots, cases[name][0])
		print("%s: %s" % [name, result.get("error", "accepted")])
		if not result.has("error"):
			accepted.append(name)
	var plain_pair := GateCapacity.checked(
		[{"passenger": plain.id, "spot": b}], by_id, sim, spots, {stander.id: a}
	)
	print("two plain neighbours: %s" % plain_pair.get("error", "accepted"))
	assert_array(accepted).is_empty()
	assert_bool(plain_pair.has("error")).is_false()
