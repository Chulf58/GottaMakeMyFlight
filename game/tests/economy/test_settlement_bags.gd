class_name TestSettlementBags
extends GdUnitTestSuite
## Baggage B4 (decision baggage-rides-a-player-built-belt-from-check-in-to-a-
## bag-roo): a passenger who makes the flight with a missed bag still pays, but
## PriceTable.fee_after_missed_bag of the fee. A bag whose passenger missed the
## flight changes nothing (a missed passenger pays no fee). The bag may settle
## before or after the passenger's outcome: a made passenger whose bag is still
## on its way waits, fee and all, for the bag's verdict.

const CONTRACT := "OCC"
const OCCURRENCE := "OCC-d0"
const MINUTE := 518
const FEE := 100
const BOOKED := 4
const SETTLED := 4000

var _world: PassengerTestWorld
var _settlement: Settlement
var _bags: BaggageSim


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null
	_settlement = null
	_bags = null


## The reference terminal with a ready bag room but no belt to it, so a bag the
## BaggageSim checks in itself always misses (without `with_room` there is no bag
## room, so none is checked in). With `hooked` the BaggageSim hears the
## passengers' check-ins; without, a test drives its bags by hand.
func _make(hooked := false, with_settlement_bags := true, with_room := true) -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	if with_room:
		BagRoomKit.add(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(100000))
	_world.flights.open_airport()
	_bags = auto_free(BaggageSim.new())
	_bags.bind(_world.clock, _world.flights, _world.grid, _world.sim if hooked else null)
	_settlement = auto_free(Settlement.new())
	if with_settlement_bags:
		_settlement.baggage = _bags
	_settlement.bind(_world.sim, _world.sim.wallet)
	var terms := TestFlightContracts.terms(CONTRACT, MINUTE)
	terms["booked_passengers"] = BOOKED
	terms["fee_per_passenger"] = FEE
	assert_bool(_world.flights.accept_contract(terms)).is_true()


func _cut() -> int:
	return PriceTable.fee_after_missed_bag(FEE)


func _spawn() -> Passenger:
	return _world.passenger(_world.sim.spawn_now(OCCURRENCE))


## The passenger boards: set the way PassengerSim leaves one, then its outcome.
func _make_it(p: Passenger) -> void:
	p.stage = Passenger.Stage.MADE
	_world.sim.outcome.emit(p.id, true)


func _miss_it(p: Passenger) -> void:
	p.stage = Passenger.Stage.MISSED
	_world.sim.outcome.emit(p.id, false)


func _settle_bag(p: Passenger, loaded: bool) -> void:
	_bags.bag_settled.emit(1, p.id, OCCURRENCE, loaded)


## A real bag of `p`, checked in well before its cutoff.
func _check_in(p: Passenger) -> Bag:
	var bag := _bags.check_in(p.id, OCCURRENCE, 1)
	assert_object(bag).is_not_null()
	assert_int(bag.cutoff_tick).is_greater(_world.clock.tick)
	assert_bool(bag.is_settled()).is_false()
	return bag


func test_a_passenger_who_made_it_with_a_bag_missed_earlier_pays_the_cut_fee() -> void:
	_make()
	var p := _spawn()
	_settle_bag(p, false)
	_make_it(p)
	assert_int(_world.sim.wallet.balance).is_equal(_cut())
	assert_int(_cut()).is_less(FEE)
	assert_array(_settlement.to_snapshot()["bag_missed"]).is_empty()


func test_a_passenger_who_made_it_with_a_loaded_bag_pays_the_whole_fee() -> void:
	_make()
	var p := _spawn()
	_settle_bag(p, true)
	_make_it(p)
	assert_int(_world.sim.wallet.balance).is_equal(FEE)


func test_a_passenger_who_never_checked_a_bag_in_pays_the_whole_fee() -> void:
	_make()
	var p := _spawn()
	_make_it(p)
	assert_int(_world.sim.wallet.balance).is_equal(FEE)


func test_a_missed_bag_is_held_until_its_passenger_finishes() -> void:
	_make()
	var p := _spawn()
	_settle_bag(p, false)
	assert_array(_settlement.to_snapshot()["bag_missed"]).is_equal([str(p.id)])
	assert_int(_world.sim.wallet.balance).is_equal(0)


func test_a_missed_bag_of_a_passenger_who_missed_the_flight_changes_nothing() -> void:
	_make()
	var p := _spawn()
	_settle_bag(p, false)
	_miss_it(p)
	assert_array(_settlement.to_snapshot()["bag_missed"]).is_empty()
	assert_int(_world.sim.wallet.balance).is_equal(0)
	var late := _spawn()
	_miss_it(late)
	_settle_bag(late, false)
	assert_array(_settlement.to_snapshot()["bag_missed"]).is_empty()
	assert_int(_world.sim.wallet.balance).is_equal(0)


func test_a_made_passenger_whose_bag_is_still_on_its_way_waits_for_the_verdict() -> void:
	_make()
	var p := _spawn()
	_check_in(p)
	_make_it(p)
	assert_int(_world.sim.wallet.balance).is_equal(0)
	var awaited: Array = _settlement.to_snapshot()["bags_awaited"]
	assert_array(awaited).is_equal([{"passenger": str(p.id), "fee": str(FEE)}])
	assert_array(_settlement.owed()).is_empty()


func test_the_waiting_fee_is_cut_when_the_bag_misses_its_cutoff() -> void:
	_make()
	var p := _spawn()
	var bag := _check_in(p)
	_make_it(p)
	_world.run_to(bag.cutoff_tick)
	assert_int(bag.state).is_equal(Bag.State.MISSED)
	# Running to the cutoff also lets the booked passengers fly, with no bag
	# in this unhooked sim, so each pays the whole fee.
	var others := _world.sim.made_count()
	assert_int(others).is_greater(0)
	assert_int(_world.sim.wallet.balance).is_equal(_cut() + others * FEE)
	assert_array(_settlement.to_snapshot()["bags_awaited"]).is_empty()


func test_the_waiting_fee_is_paid_whole_when_the_bag_is_loaded() -> void:
	_make()
	var p := _spawn()
	_check_in(p)
	_make_it(p)
	_settle_bag(p, true)
	assert_int(_world.sim.wallet.balance).is_equal(FEE)
	assert_array(_settlement.to_snapshot()["bags_awaited"]).is_empty()


func test_a_verdict_arrives_once_and_pays_once() -> void:
	_make()
	var p := _spawn()
	_check_in(p)
	_make_it(p)
	_settle_bag(p, false)
	_settle_bag(p, false)
	_world.sim.outcome.emit(p.id, true)
	assert_int(_world.sim.wallet.balance).is_equal(_cut())


func test_end_to_end_every_passenger_with_a_missed_bag_pays_the_cut_fee() -> void:
	_make(true)
	_world.run_to(SETTLED)
	var made := _world.sim.made_count()
	print(
		"made %d bags missed %d balance %d" % [made, _bags.missed_total, _world.sim.wallet.balance]
	)
	assert_int(made).is_greater(0)
	assert_int(_bags.missed_total).is_greater(0)
	assert_int(_bags.loaded_total).is_equal(0)
	assert_int(_world.sim.wallet.balance).is_equal(made * _cut())
	assert_array(_settlement.to_snapshot()["bags_awaited"]).is_empty()
	assert_array(_settlement.to_snapshot()["bag_missed"]).is_empty()


func test_end_to_end_with_no_bag_room_nobody_has_a_bag_and_every_fee_is_whole() -> void:
	_make(true, true, false)
	assert_bool(_bags.has_ready_bag_room()).is_false()
	_world.run_to(SETTLED)
	var made := _world.sim.made_count()
	assert_int(made).is_greater(0)
	assert_array(_bags.bag_ids()).is_empty()
	assert_int(_bags.missed_total + _bags.loaded_total).is_equal(0)
	assert_int(_world.sim.wallet.balance).is_equal(made * FEE)
	assert_array(_settlement.to_snapshot()["bags_awaited"]).is_empty()
	assert_array(_settlement.to_snapshot()["bag_missed"]).is_empty()


func test_a_settlement_without_a_bag_sim_pays_the_whole_fee() -> void:
	_make(false, false)
	var p := _spawn()
	_settle_bag(p, false)
	_make_it(p)
	assert_int(_world.sim.wallet.balance).is_equal(FEE)


func test_bag_state_round_trips_through_json_and_still_cuts_the_fee() -> void:
	_make()
	var held := _spawn()
	var waiting := _spawn()
	_settle_bag(held, false)
	_check_in(waiting)
	_make_it(waiting)
	var text := JSON.stringify(_settlement.to_snapshot())
	var data := JSON.parse_string(text) as Dictionary
	assert_bool(_settlement.from_snapshot({"owed": []})).is_true()
	assert_array(_settlement.to_snapshot()["bag_missed"]).is_empty()
	assert_bool(_settlement.from_snapshot(data)).is_true()
	assert_str(JSON.stringify(_settlement.to_snapshot())).is_equal(text)
	_make_it(held)
	assert_int(_world.sim.wallet.balance).is_equal(_cut())
	_bags.bag_settled.emit(1, waiting.id, OCCURRENCE, false)
	assert_int(_world.sim.wallet.balance).is_equal(2 * _cut())


func test_a_save_from_before_bags_loads_with_no_bag_state() -> void:
	_make()
	assert_bool(_settlement.from_snapshot({"owed": ["37"]})).is_true()
	assert_array(_settlement.to_snapshot()["bag_missed"]).is_empty()
	assert_array(_settlement.to_snapshot()["bags_awaited"]).is_empty()


func test_bad_bag_state_in_a_snapshot_is_refused_and_changes_nothing() -> void:
	_make()
	var good := {
		"owed": [],
		"bag_missed": ["3"],
		"bags_awaited": [{"passenger": "4", "fee": "50"}],
	}
	var cases := {
		"only bag_missed": func(d): d.erase("bags_awaited"),
		"only bags_awaited": func(d): d.erase("bag_missed"),
		"bag_missed not a list": func(d): d["bag_missed"] = "3",
		"passenger not a string": func(d): d["bag_missed"] = [3],
		"passenger zero": func(d): d["bag_missed"] = ["0"],
		"passenger not decimal": func(d): d["bag_missed"] = ["x"],
		"passenger twice": func(d): d["bag_missed"] = ["3", "3"],
		"awaited entry not a dictionary": func(d): d["bags_awaited"] = ["4"],
		"awaited entry missing fee": func(d): d["bags_awaited"] = [{"passenger": "4"}],
		"awaited entry extra key": func(d): d["bags_awaited"][0]["x"] = 1,
		"awaited fee zero": func(d): d["bags_awaited"][0]["fee"] = "0",
		"awaited fee over the wallet":
		func(d): d["bags_awaited"][0]["fee"] = str(Wallet.MAX_BALANCE + 1),
		"awaited fee not a string": func(d): d["bags_awaited"][0]["fee"] = 50,
		"awaited passenger twice":
		func(d): d["bags_awaited"].append(d["bags_awaited"][0].duplicate()),
		"passenger in both lists": func(d): d["bag_missed"] = ["4"],
	}
	assert_bool(_settlement.from_snapshot(good.duplicate(true))).is_true()
	var before := JSON.stringify(_settlement.to_snapshot())
	for name in cases:
		var data: Dictionary = good.duplicate(true)
		cases[name].call(data)
		assert_bool(_settlement.from_snapshot(data)).override_failure_message(name).is_false()
		(
			assert_str(JSON.stringify(_settlement.to_snapshot()))
			. override_failure_message(name)
			. is_equal(before)
		)
