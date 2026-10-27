class_name TestSettlement
extends GdUnitTestSuite
## Fee settlement (decision flights-and-economy-design-tick-derived-calendar-
## timetable-o, point 5): a passenger who makes an occurrence's flight pays the
## fee captured in the contract, exactly once, and loading a save never pays it
## again.

const CONTRACT := "OCC"
const OCCURRENCE := "OCC-d0"
const MINUTE := 518
const FEE := 37
const BOOKED := 4
## Past the occurrence's departure, so every booked passenger has settled.
const SETTLED := 4000

var _world: PassengerTestWorld
var _settlement: Settlement


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


## The reference terminal (everything passengers need) or, without `working`,
## a room with an entrance only, so everyone misses. The one-off flight GMF101
## starts at `flight_start`, far away unless a case flies it.
func _make(working := true, flight_start := 100000) -> void:
	var grid: BuildGrid
	if working:
		grid = BuildGrid.new()
		ReferenceTerminal.build(grid)
	else:
		grid = PassengerTestWorld.floored(Vector2i(8, 6))
		PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(flight_start))
	_settlement = auto_free(Settlement.new())
	_settlement.bind(_world.sim, _world.sim.wallet)


func _accept() -> void:
	var terms := TestFlightContracts.terms(CONTRACT, MINUTE)
	terms["booked_passengers"] = BOOKED
	terms["fee_per_passenger"] = FEE
	assert_bool(_world.flights.accept_contract(terms)).is_true()


## A passenger of `flight`, run until it settles.
func _run_one(flight: String) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(flight))
	while not p.is_done() and _world.clock.tick < SETTLED:
		_world.step()
	return p


func test_each_passenger_who_makes_the_flight_pays_the_captured_fee() -> void:
	_make()
	_accept()
	_world.run_to(SETTLED)
	var made := _world.sim.made_count()
	var balance := _world.sim.wallet.balance
	print("made %d missed %d balance %d" % [made, _world.sim.missed_count(), balance])
	assert_int(made).is_greater(0)
	assert_int(_world.sim.wallet.balance).is_equal(made * FEE)


func test_the_fee_is_the_one_captured_in_the_contract() -> void:
	_make()
	_accept()
	var p := _run_one(OCCURRENCE)
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)
	assert_int(_world.sim.wallet.balance).is_equal(_world.sim.made_count() * FEE)


func test_missed_passengers_pay_nothing() -> void:
	_make(false)
	_accept()
	_world.run_to(SETTLED)
	print("made %d missed %d" % [_world.sim.made_count(), _world.sim.missed_count()])
	assert_int(_world.sim.missed_count()).is_equal(BOOKED)
	assert_int(_world.sim.wallet.balance).is_equal(0)


func test_a_one_off_flight_has_no_contract_and_pays_nothing() -> void:
	_make(true, 0)
	var p := _run_one(PassengerTestWorld.FLIGHT)
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)
	assert_int(_world.sim.wallet.balance).is_equal(0)


func test_a_replayed_outcome_for_the_same_passenger_pays_nothing_more() -> void:
	_make()
	_accept()
	var p := _run_one(OCCURRENCE)
	assert_int(_world.sim.wallet.balance).is_equal(_world.sim.made_count() * FEE)
	_world.sim.outcome.emit(p.id, true)
	_world.sim.outcome.emit(p.id, true)
	assert_int(_world.sim.wallet.balance).is_equal(_world.sim.made_count() * FEE)


func test_an_outcome_for_a_passenger_who_is_not_made_pays_nothing() -> void:
	_make()
	_accept()
	var p := _world.passenger(_world.sim.spawn_now(OCCURRENCE))
	_world.sim.outcome.emit(p.id, true)
	assert_int(_world.sim.wallet.balance).is_equal(0)


func test_loading_settled_passengers_never_replays_their_fee() -> void:
	_make()
	_accept()
	var p := _run_one(OCCURRENCE)
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)
	var paid := _world.sim.wallet.balance
	assert_int(paid).is_equal(_world.sim.made_count() * FEE)
	assert_int(_world.sim.made_count()).is_greater(0)
	var data := JSON.parse_string(JSON.stringify(_world.sim.to_snapshot())) as Dictionary
	assert_bool(_world.sim.passenger_ids().has(p.id)).is_true()
	assert_bool(_world.sim.from_snapshot(data)).is_true()
	assert_bool(_world.sim.passenger_ids().has(p.id)).is_true()
	assert_int(_world.sim.wallet.balance).is_equal(paid)
	_world.step()
	assert_int(_world.sim.wallet.balance).is_equal(paid)


func test_binding_twice_pays_each_fee_once() -> void:
	_make()
	_settlement.bind(_world.sim, _world.sim.wallet)
	_accept()
	_run_one(OCCURRENCE)
	assert_int(_world.sim.wallet.balance).is_equal(_world.sim.made_count() * FEE)
