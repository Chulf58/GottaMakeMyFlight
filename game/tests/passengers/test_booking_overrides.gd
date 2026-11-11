class_name TestBookingOverrides
extends GdUnitTestSuite
## Extra passengers saved against a flight occurrence (BookingOverrides, board
## c6c13a5a, decision daily-incidents-technical-design-incidentdirector-shared-
## clo): set before the occurrence is scheduled, added once when it is, capped by
## the plane class maximum, kept by a save and never applied twice.

## A small contract (8 to 16 passengers) booked for 8, so 8 extra fit. Its
## first occurrence departs at tick 5200, is issued at tick 140 and has its
## passengers scheduled then.
const CONTRACT := "OVR"
const OCCURRENCE := "OVR-d0"
const MINUTE := 620
const FIRST := 2540
const ISSUED := 140
const BOOKED := 8
const HEADROOM := 8
## A second contract on the same gate, late enough to clear the first one's hold.
const OTHER_CONTRACT := "OTH"
const OTHER_OCCURRENCE := "OTH-d0"
const OTHER_MINUTE := 900
const OTHER_FIRST := 8140

var _a: PassengerTestWorld
var _b: PassengerTestWorld
var _spawned := {}


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
	_spawned.clear()


## An open airport with a contract accepted at each minute (OVR, then OTH), so
## the first occurrences are not issued yet.
func _world(minutes: Array[int]) -> PassengerTestWorld:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(100000), 3)
	world.flights.open_airport()
	var ids: Array[String] = [CONTRACT, OTHER_CONTRACT]
	for i in minutes.size():
		var terms := TestFlightContracts.terms(ids[i], minutes[i])
		terms["plane_size"] = "small"
		terms["booked_passengers"] = BOOKED
		assert_bool(world.flights.accept_contract(terms)).is_true()
	return world


## Passengers spawned or still to come, over every flight.
func _scheduled_total(world: PassengerTestWorld) -> int:
	return world.sim.passenger_ids().size() + world.sim.pending_spawns()


func _on_spawned(id: int) -> void:
	var flight := _a.passenger(id).flight_id
	_spawned[flight] = int(_spawned.get(flight, 0)) + 1


func _save(world: PassengerTestWorld) -> Dictionary:
	return (
		JSON
		. parse_string(
			(
				JSON
				. stringify(
					{
						"clock": world.clock.to_snapshot(),
						"flights": world.flights.to_snapshot(),
						"grid": world.grid.to_snapshot(),
						"passengers": world.sim.to_snapshot(),
					}
				)
			)
		)
	)


func _load(data: Dictionary) -> PassengerTestWorld:
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	assert_bool(world.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(world.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(world.sim.from_snapshot(data["passengers"])).is_true()
	return world


func test_an_override_adds_exactly_its_extra_passengers_to_that_occurrence_only() -> void:
	_a = _world([MINUTE, OTHER_MINUTE])
	_a.sim.passenger_spawned.connect(_on_spawned)
	var result := _a.sim.set_booking_override(OCCURRENCE, 5)
	assert_bool(result["ok"]).is_true()
	assert_int(_a.sim.booking_override_of(OCCURRENCE)).is_equal(5)
	_a.run_to(OTHER_FIRST + PassengerTestWorld.doors_tick() - PassengerSim.LAST_SPAWN_LEAD_TICKS)
	print("spawned per flight: %s" % [_spawned])
	assert_int(int(_spawned.get(OCCURRENCE, 0))).is_equal(BOOKED + 5)
	assert_int(int(_spawned.get(OTHER_OCCURRENCE, 0))).is_equal(BOOKED)
	# Scheduled once: the override is gone, and a later flight starts clean.
	assert_int(_a.sim.booking_override_of(OCCURRENCE)).is_equal(0)


func test_an_override_for_a_scheduled_occurrence_is_refused() -> void:
	_a = _world([MINUTE])
	_a.run_to(ISSUED + 60)
	assert_array(_a.flights.flight_ids()).contains([OCCURRENCE])
	var before := _scheduled_total(_a)
	var result := _a.sim.set_booking_override(OCCURRENCE, 3)
	print("late override: %s; scheduled %d" % [result, before])
	assert_bool(result["ok"]).is_false()
	assert_str(result["reason"]).is_equal(BookingOverrides.SCHEDULED)
	assert_int(_a.sim.booking_override_of(OCCURRENCE)).is_equal(0)
	assert_int(before).is_equal(BOOKED)
	_a.run_to(ISSUED + 200)
	assert_int(_scheduled_total(_a)).is_equal(BOOKED)


func test_an_override_for_a_departed_occurrence_is_refused() -> void:
	_a = _world([MINUTE])
	_a.run_to(FIRST + PassengerTestWorld.doors_tick() + 1)
	assert_bool(_a.flights.is_doors_closed(OCCURRENCE)).is_true()
	var result := _a.sim.set_booking_override(OCCURRENCE, 3)
	assert_bool(result["ok"]).is_false()
	assert_str(result["reason"]).is_equal(BookingOverrides.DEPARTED)


func test_an_override_is_capped_at_the_class_maximum_and_reports_the_headroom() -> void:
	_a = _world([MINUTE])
	assert_int(_a.sim.booking_headroom(OCCURRENCE)).is_equal(HEADROOM)
	var over := _a.sim.set_booking_override(OCCURRENCE, HEADROOM + 1)
	print("over the cap: %s" % [over])
	assert_bool(over["ok"]).is_false()
	assert_str(over["reason"]).is_equal(BookingOverrides.OVER_MAX)
	assert_int(over["headroom"]).is_equal(HEADROOM)
	assert_int(_a.sim.booking_override_of(OCCURRENCE)).is_equal(0)
	# The reported headroom is exactly what is accepted, and a later set replaces.
	assert_bool(_a.sim.set_booking_override(OCCURRENCE, 3)["ok"]).is_true()
	var exact := _a.sim.set_booking_override(OCCURRENCE, over["headroom"])
	assert_bool(exact["ok"]).is_true()
	assert_int(_a.sim.booking_override_of(OCCURRENCE)).is_equal(HEADROOM)
	_a.run_to(ISSUED + 200)
	assert_int(_scheduled_total(_a)).is_equal(BOOKED + HEADROOM)


func test_an_override_under_one_or_without_a_contract_is_refused() -> void:
	_a = _world([MINUTE])
	for extra in [0, -4]:
		var result := _a.sim.set_booking_override(OCCURRENCE, extra)
		assert_bool(result["ok"]).is_false()
		assert_str(result["reason"]).is_equal(BookingOverrides.TOO_FEW)
	var one_off := _a.sim.set_booking_override(PassengerTestWorld.FLIGHT, 2)
	assert_bool(one_off["ok"]).is_false()
	assert_str(one_off["reason"]).is_equal(BookingOverrides.NO_CONTRACT)
	assert_int(one_off["headroom"]).is_equal(0)
	var unknown := _a.sim.set_booking_override("NONE-d0", 2)
	assert_str(unknown["reason"]).is_equal(BookingOverrides.NO_CONTRACT)
	assert_int(_a.sim.booking_headroom("NONE-d0")).is_equal(0)


func test_an_override_survives_a_save_and_load_before_scheduling() -> void:
	_a = _world([MINUTE])
	assert_bool(_a.sim.set_booking_override(OCCURRENCE, 6)["ok"]).is_true()
	_a.run_to(ISSUED - 40)
	var data := _save(_a)
	var saved: Array = data["passengers"]["booking_overrides"]
	assert_int(saved.size()).is_equal(1)
	assert_str(saved[0]["flight"]).is_equal(OCCURRENCE)
	assert_int(int(saved[0]["extra"])).is_equal(6)
	_b = _load(data)
	assert_int(_b.sim.booking_override_of(OCCURRENCE)).is_equal(6)
	_a.run_to(ISSUED + 200)
	_b.run_to(ISSUED + 200)
	print("scheduled: unbroken %d, loaded %d" % [_scheduled_total(_a), _scheduled_total(_b)])
	assert_int(_scheduled_total(_a)).is_equal(BOOKED + 6)
	assert_int(_scheduled_total(_b)).is_equal(BOOKED + 6)
	assert_str(_b.signature()).is_equal(_a.signature())
	assert_int(_b.sim.booking_override_of(OCCURRENCE)).is_equal(0)


func test_a_load_after_scheduling_does_not_apply_the_override_again() -> void:
	_a = _world([MINUTE])
	assert_bool(_a.sim.set_booking_override(OCCURRENCE, 6)["ok"]).is_true()
	_a.run_to(ISSUED + 100)
	var data := _save(_a)
	assert_array(data["passengers"]["booking_overrides"]).is_empty()
	assert_array(data["passengers"]["scheduled"]).is_equal([OCCURRENCE])
	_b = _load(data)
	assert_int(_b.sim.booking_override_of(OCCURRENCE)).is_equal(0)
	assert_int(_scheduled_total(_b)).is_equal(_scheduled_total(_a))
	assert_int(_scheduled_total(_b)).is_equal(BOOKED + 6)
	_b.run_to(ISSUED + 400)
	assert_int(_scheduled_total(_b)).is_equal(BOOKED + 6)


func test_a_bad_saved_override_is_refused_whole() -> void:
	_a = _world([MINUTE])
	assert_bool(_a.sim.set_booking_override(OCCURRENCE, 2)["ok"]).is_true()
	var good: Dictionary = _save(_a)["passengers"]
	var entry := {"flight": OCCURRENCE, "extra": 2}
	var cases := {
		"zero extra": [entry.merged({"extra": 0}, true)],
		"negative extra": [entry.merged({"extra": -1}, true)],
		"fractional extra": [entry.merged({"extra": 1.5}, true)],
		"text extra": [entry.merged({"extra": "2"}, true)],
		"over the class maximum": [entry.merged({"extra": HEADROOM + 1}, true)],
		"over every class maximum": [entry.merged({"extra": 500}, true)],
		"not an occurrence": [entry.merged({"flight": "OVR"}, true)],
		"flight not text": [entry.merged({"flight": 7}, true)],
		"repeated": [entry, entry.duplicate()],
		"extra key": [entry.merged({"day": 1}, true)],
		"missing extra": [{"flight": OCCURRENCE}],
		"not a record": [5],
		"not a list": {"flight": OCCURRENCE},
	}
	var missing := good.duplicate(true)
	missing.erase("booking_overrides")
	_b = _world([MINUTE])
	assert_bool(_b.sim.from_snapshot(missing)).is_false()
	for label: String in cases:
		var bad := good.duplicate(true)
		bad["booking_overrides"] = cases[label]
		assert_bool(_b.sim.from_snapshot(bad)).override_failure_message(label).is_false()
		assert_int(_b.sim.booking_override_of(OCCURRENCE)).override_failure_message(label).is_equal(
			0
		)
	var scheduled := good.duplicate(true)
	scheduled["scheduled"] = [OCCURRENCE]
	assert_bool(_b.sim.from_snapshot(scheduled)).is_false()
	assert_int(_b.sim.booking_override_of(OCCURRENCE)).is_equal(0)
	assert_bool(_b.sim.from_snapshot(good)).is_true()
	assert_int(_b.sim.booking_override_of(OCCURRENCE)).is_equal(2)
