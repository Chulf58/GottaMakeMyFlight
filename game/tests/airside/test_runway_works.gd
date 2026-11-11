class_name TestRunwayWorks
extends GdUnitTestSuite
## Runway upgrade works (Runway R9; decision runway-upgrade-works-wait-for-a-
## timetable-gap-passengers-per-plane-class, design section 7): what they cost,
## which build tier opens them, what the card says when it refuses, and how the
## works state is kept and saved.

var _sim: FlightSim
var _unlocks: BuildUnlocks
var _wallet: Wallet
var _spent: Array[int] = []


func before_test() -> void:
	_spent.clear()
	_sim = auto_free(FlightSim.new()) as FlightSim
	_sim.runway.size = PlaneClasses.SMALL
	_sim.open_airport()
	_unlocks = auto_free(BuildUnlocks.new()) as BuildUnlocks
	_wallet = Wallet.new(100000)
	_wallet.transaction.connect(
		func(amount: int, _category: int, _claimed: Dictionary, _tick: int) -> void:
			_spent.append(amount)
	)


func _tier(tier: int) -> void:
	var need: int = BuildUnlocks.TIERS[tier - 1]["passengers"]
	(
		assert_bool(_unlocks.from_snapshot({"tier": tier, "made": need, "shown": [], "seen": []}))
		. is_true()
	)


func test_prices_ticks_and_tiers_are_the_ruled_ones() -> void:
	assert_int(PriceTable.runway_price(PlaneClasses.MEDIUM)).is_equal(15000)
	assert_int(PriceTable.runway_price(PlaneClasses.LARGE)).is_equal(40000)
	assert_int(PriceTable.runway_price(PlaneClasses.SMALL)).is_equal(PriceTable.NO_PRICE)
	assert_int(RunwayWorks.ticks(PlaneClasses.MEDIUM)).is_equal(1200)
	assert_int(RunwayWorks.ticks(PlaneClasses.LARGE)).is_equal(2400)
	assert_int(BuildUnlocks.runway_tier(PlaneClasses.MEDIUM)).is_equal(2)
	assert_int(BuildUnlocks.runway_tier(PlaneClasses.LARGE)).is_equal(3)
	assert_str(RunwayWorks.next_size(PlaneClasses.SMALL)).is_equal(PlaneClasses.MEDIUM)
	assert_str(RunwayWorks.next_size(PlaneClasses.MEDIUM)).is_equal(PlaneClasses.LARGE)
	assert_str(RunwayWorks.next_size(PlaneClasses.LARGE)).is_empty()


## Below the tier the card says what the tier asks for, in the unlock text the
## build menu uses, and nothing is charged or booked.
func test_locked_below_the_tier_with_the_requirement_text() -> void:
	var problem := RunwayWorks.problem(_sim, _unlocks, _wallet)
	print("tier 1, small runway: '%s'" % problem)
	assert_str(problem).is_equal(BuildUnlocks.requirement_text(2))
	assert_str(problem).contains("2 stars").contains("50 passengers")
	assert_str(RunwayWorks.buy(_sim, _unlocks, _wallet)).is_equal(problem)
	assert_int(_wallet.balance).is_equal(100000)
	assert_bool(_sim.runway.works.scheduled()).is_false()
	# The large step needs tier 3: tier 2 is not enough.
	_tier(2)
	assert_str(RunwayWorks.problem(_sim, _unlocks, _wallet)).is_empty()
	_sim.runway.size = PlaneClasses.MEDIUM
	assert_str(RunwayWorks.problem(_sim, _unlocks, _wallet)).is_equal(
		BuildUnlocks.requirement_text(3)
	)
	_tier(3)
	assert_str(RunwayWorks.problem(_sim, _unlocks, _wallet)).is_empty()


func test_a_wallet_short_of_the_price_refuses_and_keeps_its_money() -> void:
	_tier(2)
	_wallet = Wallet.new(14999)
	var problem := RunwayWorks.problem(_sim, _unlocks, _wallet)
	print("14999 for a 15000 upgrade: '%s'" % problem)
	assert_str(problem).is_equal("Not enough money: the medium runway works cost $15000")
	assert_str(RunwayWorks.buy(_sim, _unlocks, _wallet)).is_equal(problem)
	assert_int(_wallet.balance).is_equal(14999)
	assert_bool(_sim.runway.works.scheduled()).is_false()
	# Control: exactly the price is enough.
	_wallet = Wallet.new(15000)
	assert_str(RunwayWorks.buy(_sim, _unlocks, _wallet)).is_empty()
	assert_int(_wallet.balance).is_equal(0)


func test_buying_charges_the_price_once_and_books_the_works() -> void:
	_tier(2)
	assert_str(RunwayWorks.buy(_sim, _unlocks, _wallet)).is_empty()
	assert_int(_wallet.balance).is_equal(100000 - 15000)
	assert_array(_spent).is_equal([-15000])
	var works := _sim.runway.works
	assert_bool(works.scheduled()).is_true()
	assert_str(works.target).is_equal(PlaneClasses.MEDIUM)
	assert_int(works.finish - works.start).is_equal(1200)
	# Booked, not built: the runway stays small until the works end.
	assert_str(_sim.runway.size).is_equal(PlaneClasses.SMALL)
	assert_str(RunwayWorks.problem(_sim, _unlocks, _wallet)).is_equal(RunwayWorks.BOOKED_TEXT)
	assert_str(RunwayWorks.buy(_sim, _unlocks, _wallet)).is_equal(RunwayWorks.BOOKED_TEXT)
	assert_int(_wallet.balance).is_equal(100000 - 15000)


func test_the_largest_runway_has_no_upgrade() -> void:
	_tier(3)
	_sim.runway.size = PlaneClasses.LARGE
	assert_str(RunwayWorks.problem(_sim, _unlocks, _wallet)).is_equal(RunwayWorks.LARGEST_TEXT)


func test_a_missing_unlock_gate_refuses_loudly() -> void:
	assert_str(RunwayWorks.problem(_sim, null, _wallet)).is_equal(BuildUnlocks.NOT_WIRED_TEXT)


func test_the_works_state_round_trips_and_refuses_bad_data() -> void:
	var works := RunwayWorks.new()
	assert_dict(works.to_snapshot()).is_equal({"target": "", "start": -1, "finish": -1})
	works.begin(PlaneClasses.LARGE, 5000)
	var data := JSON.parse_string(JSON.stringify(works.to_snapshot())) as Dictionary
	var again := RunwayWorks.new()
	assert_bool(again.from_snapshot(data)).is_true()
	assert_str(again.target).is_equal(PlaneClasses.LARGE)
	assert_int(again.start).is_equal(5000)
	assert_int(again.finish).is_equal(7400)
	var bad := [
		{"target": "huge", "start": 1, "finish": 2},
		{"target": "medium", "start": 5, "finish": 5},
		{"target": "medium", "start": -1, "finish": -1},
		{"target": "", "start": 3, "finish": -1},
		{"target": "medium", "start": 1},
		{"target": "medium", "start": 1, "finish": 2, "extra": 1},
	]
	for one: Dictionary in bad:
		(
			assert_str(RunwayWorks.new().snapshot_problem(one))
			. override_failure_message(str(one))
			. is_not_empty()
		)
	var refuse := func() -> void: assert_bool(RunwayWorks.new().from_snapshot(bad[0])).is_false()
	assert_error(refuse).is_push_error(
		"RunwayWorks.from_snapshot: target must be one of %s or empty" % [RunwayWorks.TICKS.keys()]
	)
	# The hold covers a whole flight, first state to DEPARTED.
	assert_int(RunwayWorks.HOLD_TICKS).is_equal(
		FlightSim.schedule_starts(0)[FlightSim.STATE_COUNT - 1]
	)


## The runway switches size on the tick the works end; the works' booking is
## held a flight's length longer (so no plan of a plane that met it changes)
## and then dropped.
func test_settle_switches_the_size_at_the_end_and_drops_the_booking_later() -> void:
	var runway := Runway.new(PlaneClasses.SMALL)
	var seen: Array[String] = []
	runway.size_changed.connect(func(size: String) -> void: seen.append(size))
	runway.works.begin(PlaneClasses.MEDIUM, 1000)
	assert_bool(runway.settle(2199)).is_false()
	assert_str(runway.size).is_equal(PlaneClasses.SMALL)
	assert_bool(runway.settle(2200)).is_true()
	assert_str(runway.size).is_equal(PlaneClasses.MEDIUM)
	assert_array(seen).is_equal([PlaneClasses.MEDIUM])
	assert_bool(runway.works.scheduled()).is_false()
	assert_int(runway.works.fixed_bookings().size()).is_equal(1)
	assert_bool(runway.settle(2200 + RunwayWorks.HOLD_TICKS - 1)).is_false()
	assert_bool(runway.settle(2200 + RunwayWorks.HOLD_TICKS)).is_true()
	assert_int(runway.works.fixed_bookings().size()).is_equal(0)
	assert_array(seen).is_equal([PlaneClasses.MEDIUM])


## After the works end their booking is held, and the card refuses another
## upgrade with its own text, without taking the price.
func test_the_card_refuses_an_upgrade_while_the_last_works_are_held() -> void:
	_tier(3)
	assert_str(RunwayWorks.buy(_sim, _unlocks, _wallet)).is_empty()
	_sim.on_tick(_sim.runway.works.finish)
	assert_str(_sim.runway.size).is_equal(PlaneClasses.MEDIUM)
	assert_str(RunwayWorks.problem(_sim, _unlocks, _wallet)).is_equal(RunwayWorks.HELD_TEXT)
	assert_str(RunwayWorks.buy(_sim, _unlocks, _wallet)).is_equal(RunwayWorks.HELD_TEXT)
	assert_int(_wallet.balance).is_equal(100000 - 15000)
