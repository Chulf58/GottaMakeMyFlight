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
	# A FlightSim starts closed; these contracts fly from an open airport.
	_world.flights.open_airport()
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


## Fills the wallet so that `room` more fits, no more.
func _fill_to_room(room: int) -> void:
	var wallet := _world.sim.wallet
	var fill := Wallet.MAX_BALANCE - room - wallet.balance
	assert_bool(wallet.credit(fill, Wallet.Category.FEES)).is_true()


func test_a_fee_the_wallet_cannot_hold_is_owed_and_paid_once_room_is_made() -> void:
	_make()
	_accept()
	_fill_to_room(10)
	var p := _run_one(OCCURRENCE)
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)
	var made := _world.sim.made_count()
	assert_int(made).is_greater(0)
	print("made %d owed %s balance %d" % [made, _settlement.owed(), _world.sim.wallet.balance])
	assert_int(_world.sim.wallet.balance).is_equal(Wallet.MAX_BALANCE - 10)
	assert_int(_settlement.owed().size()).is_equal(made)
	assert_bool(_world.sim.wallet.spend(1000, Wallet.Category.BUILD)).is_true()
	_world.step()
	_world.step()
	assert_int(_world.sim.wallet.balance).is_equal(Wallet.MAX_BALANCE - 10 - 1000 + made * FEE)
	assert_array(_settlement.owed()).is_empty()


func test_owed_fees_survive_a_save_round_trip() -> void:
	_make()
	_accept()
	_fill_to_room(10)
	_run_one(OCCURRENCE)
	var made := _world.sim.made_count()
	assert_int(made).is_greater(0)
	var data := JSON.parse_string(JSON.stringify(_settlement.to_snapshot())) as Dictionary
	var saved := _world
	_make()
	saved.free_all()
	assert_bool(_settlement.from_snapshot(data)).is_true()
	assert_int(_world.sim.wallet.balance).is_equal(0)
	_world.step()
	print("owed after load paid: balance %d" % _world.sim.wallet.balance)
	assert_int(_world.sim.wallet.balance).is_equal(made * FEE)
	_world.step()
	assert_int(_world.sim.wallet.balance).is_equal(made * FEE)


func test_a_malformed_settlement_snapshot_is_refused_and_changes_nothing() -> void:
	_make()
	assert_bool(_settlement.from_snapshot({})).is_false()
	assert_bool(_settlement.from_snapshot({"owed": [37]})).is_false()
	assert_bool(_settlement.from_snapshot({"owed": ["-5"]})).is_false()
	assert_bool(_settlement.from_snapshot({"owed": ["0"]})).is_false()
	assert_bool(_settlement.from_snapshot({"owed": [], "extra": 1})).is_false()
	assert_array(_settlement.owed()).is_empty()
	assert_bool(_settlement.from_snapshot({"owed": ["37"]})).is_true()
	assert_array(_settlement.owed()).is_equal([37])


## A save loaded into the same session rewinds it: the passenger ids the save
## holds come back, and their fees are paid when they make the flight again.
func test_rewinding_to_an_earlier_save_pays_the_replayed_fees() -> void:
	_make()
	_accept()
	var p := _world.passenger(_world.sim.spawn_now(OCCURRENCE))
	var clock_save := JSON.parse_string(JSON.stringify(_world.clock.to_snapshot())) as Dictionary
	var flights_save := (
		JSON.parse_string(JSON.stringify(_world.flights.to_snapshot())) as Dictionary
	)
	var sim_save := JSON.parse_string(JSON.stringify(_world.sim.to_snapshot())) as Dictionary
	var wallet_save := _world.sim.wallet.to_snapshot()
	var settle_save := JSON.parse_string(JSON.stringify(_settlement.to_snapshot())) as Dictionary
	while not p.is_done() and _world.clock.tick < SETTLED:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)
	var first := _world.sim.wallet.balance
	assert_int(first).is_equal(_world.sim.made_count() * FEE)
	assert_bool(_world.clock.from_snapshot(clock_save)).is_true()
	assert_bool(_world.flights.from_snapshot(flights_save)).is_true()
	assert_bool(_world.sim.from_snapshot(sim_save)).is_true()
	assert_bool(_world.sim.wallet.from_snapshot(wallet_save)).is_true()
	assert_bool(_settlement.from_snapshot(settle_save)).is_true()
	var again := _world.passenger(p.id)
	assert_object(again).is_not_null()
	while not again.is_done() and _world.clock.tick < SETTLED * 2:
		_world.step()
	print("first %d after rewind %d stage %d" % [first, _world.sim.wallet.balance, again.stage])
	assert_int(again.stage).is_equal(Passenger.Stage.MADE)
	assert_int(_world.sim.wallet.balance).is_equal(_world.sim.made_count() * FEE)
