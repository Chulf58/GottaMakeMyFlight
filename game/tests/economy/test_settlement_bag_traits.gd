class_name TestSettlementBagTraits
extends GdUnitTestSuite
## Bag cover and Heavy bags change what a missed bag costs (OfferTraits.
## missed_bag_paid_percent), at the one place a fee is cut. A fee held for a bag
## still on its way keeps the cut fee beside it, so a bag that misses after a
## load is cut the same.

const CONTRACT := "OCC"
const OCCURRENCE := "OCC-d0"
const MINUTE := 518
const FEE := 100
const BOOKED := 8
const COVER := {"up": "bag_cover", "down": "rush_crowd", "level": 1}
const HEAVY := {"up": "top_fare", "down": "heavy_bags", "level": 2}

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


func _make(traits: Dictionary) -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	BagRoomKit.add(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(100000))
	_world.flights.open_airport()
	_bags = auto_free(BaggageSim.new())
	_bags.bind(_world.clock, _world.flights, _world.grid, null)
	_settlement = _new_settlement()
	var terms := TestFlightContracts.terms(CONTRACT, MINUTE)
	terms["plane_size"] = "small"
	terms["booked_passengers"] = BOOKED
	terms["fee_per_passenger"] = FEE
	terms["traits"] = traits
	assert_bool(_world.flights.accept_contract(terms)).is_true()


func _new_settlement() -> Settlement:
	var settlement: Settlement = auto_free(Settlement.new())
	settlement.baggage = _bags
	settlement.bind(_world.sim, _world.sim.wallet)
	return settlement


## A passenger of the occurrence who boards with a bag missed (or still on its
## way, with `bag_first` false).
func _made_passenger(bag_first: bool) -> Passenger:
	_world.run_to(1)
	var p := _world.passenger(_world.sim.spawn_now(OCCURRENCE))
	if bag_first:
		_bags.bag_settled.emit(1, p.id, OCCURRENCE, false)
	else:
		assert_object(_bags.check_in(p.id, OCCURRENCE, 1)).is_not_null()
	p.stage = Passenger.Stage.MADE
	_world.sim.outcome.emit(p.id, true)
	return p


func test_bag_cover_cuts_a_missed_bag_less() -> void:
	_make(COVER)
	_made_passenger(true)
	assert_int(_world.sim.wallet.balance).is_equal(75)


func test_very_heavy_bags_cost_the_whole_fee() -> void:
	_make(HEAVY)
	_made_passenger(true)
	assert_int(_world.sim.wallet.balance).is_equal(0)


func test_a_plain_contract_keeps_the_usual_cut() -> void:
	_make({})
	_made_passenger(true)
	assert_int(_world.sim.wallet.balance).is_equal(PriceTable.fee_after_missed_bag(FEE))


func test_a_held_fee_keeps_its_cut_across_a_load() -> void:
	_make(COVER)
	var p := _made_passenger(false)
	assert_int(_world.sim.wallet.balance).is_equal(0)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_settlement.to_snapshot()))
	assert_array(saved["bags_awaited"]).is_equal(
		[{"passenger": str(p.id), "fee": str(FEE), "missed_fee": "75"}]
	)
	_settlement.free()
	_settlement = _new_settlement()
	var loaded := _settlement
	assert_bool(loaded.from_snapshot(saved)).is_true()
	_bags.bag_settled.emit(1, p.id, OCCURRENCE, false)
	assert_int(_world.sim.wallet.balance).is_equal(75)
