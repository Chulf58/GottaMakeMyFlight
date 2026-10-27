class_name TestPassengerOccurrences
extends GdUnitTestSuite
## Passengers are planned per flight occurrence (decision
## flights-and-economy-design-tick-derived-calendar-timetable-o, point 4):
## arrivals sit inside the occurrence's own window, each occurrence is
## scheduled once, a closed flight's pending arrivals expire, and what a
## flight left behind is dropped when the flight itself is pruned.

const CONTRACT := "OCC"
const OCCURRENCE := "OCC-d0"
## 07:38 plus an hour: the occurrence's first state is at tick 1200, its doors
## close at 3100 and it is pruned at 4980.
const MINUTE := 518
const FIRST := 1200
const DOORS := 3100
const PRUNED := 4980
const BOOKED := 12

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


## A room with (or without) an entrance and no desk, so every arrival ends up
## missing the flight. The one-off GMF101 is parked far from the contract.
func _room(with_entrance := true) -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	if with_entrance:
		PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(100000))


func _accept() -> void:
	var terms := TestFlightContracts.terms(CONTRACT, MINUTE)
	terms["booked_passengers"] = BOOKED
	assert_bool(_world.flights.accept_contract(terms)).is_true()


func test_accepting_a_contract_schedules_its_booked_passengers_once() -> void:
	_room()
	_accept()
	assert_array(_world.flights.flight_ids()).contains([OCCURRENCE])
	assert_int(_world.sim.pending_spawns()).is_equal(BOOKED)
	assert_bool(_world.sim._scheduled.has(OCCURRENCE)).is_true()
	assert_bool(_world.sim.schedule_flight(OCCURRENCE, 5)).is_false()
	assert_int(_world.sim.pending_spawns()).is_equal(BOOKED)


func test_arrivals_fall_inside_the_occurrence_window() -> void:
	_room()
	_accept()
	var last := DOORS - PassengerSim.LAST_SPAWN_LEAD_TICKS
	_world.run_to(DOORS - 1)
	assert_int(_world.sim.passenger_ids().size()).is_equal(BOOKED)
	var earliest := 1 << 40
	var latest := 0
	for id in _world.sim.passenger_ids():
		var spawned := _world.passenger(id).spawn_tick
		earliest = mini(earliest, spawned)
		latest = maxi(latest, spawned)
	# Relaxed passengers may come before the first state, up to two game hours
	# before departure (ArrivalTypes); the departure is 1960 ticks after FIRST.
	assert_int(earliest).is_greater_equal(FIRST + 1960 - ArrivalTypes.RELAXED_LEAD_TICKS)
	assert_int(latest).is_less_equal(last)


func test_a_closed_flight_cannot_be_scheduled() -> void:
	_room()
	_accept()
	_world.run_to(DOORS + 1)
	assert_bool(_world.sim._scheduled.has(OCCURRENCE)).is_false()
	assert_bool(_world.sim.schedule_flight(OCCURRENCE, 5)).is_false()
	assert_int(_world.sim.pending_spawns()).is_equal(0)


func test_pending_arrivals_expire_when_the_occurrence_closes_with_no_entrance() -> void:
	_room(false)
	_accept()
	_world.run_to(DOORS - 1)
	assert_int(_world.sim.pending_spawns()).is_equal(BOOKED)
	_world.run_to(DOORS + 1)
	assert_int(_world.sim.pending_spawns()).is_equal(0)
	assert_int(_world.sim.passenger_ids().size()).is_equal(0)
	var counts: Dictionary = _world.sim.no_shows[OCCURRENCE]
	assert_int(counts["no_entrance"]).is_equal(BOOKED)
	assert_int(counts["late"]).is_equal(0)


func test_a_pruned_occurrence_drops_its_results_but_the_totals_stay() -> void:
	_room()
	_accept()
	_world.run_to(DOORS + 1)
	assert_bool(_world.sim.flight_results.has(OCCURRENCE)).is_true()
	assert_int(_world.sim.missed_count()).is_equal(BOOKED)
	_world.run_to(PRUNED + 1)
	assert_array(_world.flights.flight_ids()).not_contains([OCCURRENCE])
	assert_bool(_world.sim.flight_results.has(OCCURRENCE)).is_false()
	assert_bool(_world.sim.no_shows.has(OCCURRENCE)).is_false()
	assert_int(_world.sim.passenger_ids().size()).is_equal(0)
	assert_int(_world.sim.missed_count()).is_equal(BOOKED)
	assert_int(_world.sim.made_count()).is_equal(0)
	assert_int(_world.sim.active_count()).is_equal(0)
