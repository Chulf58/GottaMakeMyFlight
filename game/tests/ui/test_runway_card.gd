class_name TestRunwayCard
extends GdUnitTestSuite
## The runway upgrade card (Runway R9): the size and the next step, what stops
## the upgrade, the Upgrade button and the works' start and end once bought.

var _sim: FlightSim
var _unlocks: BuildUnlocks
var _finances: Finances
var _card: RunwayCard


func before_test() -> void:
	_sim = auto_free(FlightSim.new()) as FlightSim
	_sim.runway.size = PlaneClasses.SMALL
	_sim.open_airport()
	_unlocks = auto_free(BuildUnlocks.new()) as BuildUnlocks
	_finances = auto_free(Finances.new()) as Finances
	_finances.wallet.credit(30000, Wallet.Category.OPENING)
	_card = auto_free(RunwayCard.new()) as RunwayCard
	_card.flights = _sim
	_card.unlocks = _unlocks
	_card.finances = _finances
	add_child(_card)


func _tier(tier: int) -> void:
	var need: int = BuildUnlocks.TIERS[tier - 1]["passengers"]
	assert_bool(_unlocks.from_snapshot({"tier": tier, "made": need})).is_true()


func test_locked_the_card_says_what_the_tier_asks_for_and_the_button_is_off() -> void:
	_card.open()
	print(_card.card_text())
	assert_str(_card.card_text()).contains("Small runway, 384 m")
	assert_str(_card.card_text()).contains("Next: Medium runway, 576 m, $15000, works take 1 hour")
	assert_str(_card.problem_text()).is_equal(BuildUnlocks.requirement_text(2))
	assert_bool(_card.upgrade_button().disabled).is_true()
	assert_str(_card.schedule_text()).is_empty()


func test_unlocked_and_funded_the_button_buys_and_the_card_shows_the_works() -> void:
	_tier(2)
	_card.open()
	assert_str(_card.problem_text()).is_empty()
	assert_bool(_card.upgrade_button().disabled).is_false()
	_card.upgrade_button().pressed.emit()
	print(_card.card_text())
	assert_int(_finances.wallet.balance).is_equal(30000 - 15000)
	assert_bool(_sim.runway.works.scheduled()).is_true()
	var works := _sim.runway.works
	assert_str(_card.schedule_text()).is_equal(
		(
			"Works on the medium runway start %s and end %s"
			% [
				"at " + GameCalendar.clock_text(works.start),
				"at " + GameCalendar.clock_text(works.finish)
			]
		)
	)
	# One upgrade at a time: the button and the next-step line are gone.
	assert_bool(_card.upgrade_button().visible).is_false()
	assert_str(_card.card_text()).not_contains("Next:")


func test_a_short_wallet_shows_the_price_and_keeps_the_button_off() -> void:
	_tier(2)
	_finances.wallet.spend(30000 - 14999, Wallet.Category.BUILD)
	_card.open()
	assert_str(_card.problem_text()).is_equal(RunwayWorks.short_text(PlaneClasses.MEDIUM))
	assert_bool(_card.upgrade_button().disabled).is_true()


func test_the_card_follows_the_size_when_the_works_end() -> void:
	_tier(2)
	_card.open()
	_card.upgrade_button().pressed.emit()
	_sim.on_tick(_sim.runway.works.finish)
	assert_str(_card.card_text()).contains("Medium runway, 576 m")
	assert_str(_card.schedule_text()).is_empty()
	assert_str(_card.card_text()).contains("Next: Large runway, 768 m, $40000, works take 2 hours")
