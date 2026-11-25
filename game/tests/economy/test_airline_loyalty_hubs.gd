class_name TestAirlineLoyaltyHubs
extends GdUnitTestSuite
## Stage 2 S2-C: Multi-tier airline loyalty (Bronze 3d +5%, Silver 7d +10%,
## Gold 12d +15%, LOYAL_AIRLINE +2/day), Gold-unlocked Hub Contracts at 3.0+
## stars with +10% bonus, +1 low-rating grace day, OfferPanel & FlightPlanner
## badges, cozy 1-tier demotion on early end, and SaveGame v37 round-trip.

const LOYAL_TRAIT := {"up": "loyal_airline", "down": "rush_crowd", "level": 1}


func _accept(
	flights: FlightSim, id: String, minute: int, airline: String, traits := {}, is_hub := false
) -> void:
	var terms := TestFlightContracts.terms(id, minute)
	terms["airline"] = airline
	terms["traits"] = traits
	if is_hub:
		terms[FlightContract.IS_HUB_KEY] = true
	assert_bool(flights.accept_contract(terms)).is_true()


func _fly(flights: FlightSim, id: String, nth: int) -> void:
	var contract := flights.contract_of(id)
	var day: int = contract["first_day"] + nth
	var departs: int = FlightTimetable.starts_for(contract, day, 0)[FlightSim.State.DEPARTED]
	var at := flights.tick
	while at < departs:
		at = mini(at + GameCalendar.TICKS_PER_MINUTE * 30, departs)
		flights.on_tick(at)


func _low_day_end(rating: AirportRating, clock: SimClock, day: int) -> void:
	rating.record_passenger(GameCalendar.day_start(day - 1, 0), false, 0)
	var tick := GameCalendar.day_start(day, 0)
	clock.tick = tick
	rating.on_tick(tick)
	clock.ticked.emit(tick)


func _recovery_day_end(rating: AirportRating, clock: SimClock, day: int) -> void:
	for i in 200:
		rating.record_passenger(GameCalendar.day_start(day - 1, 0), true, PassengerSim.MOOD_MAX)
	var tick := GameCalendar.day_start(day, 0)
	clock.tick = tick
	rating.on_tick(tick)
	clock.ticked.emit(tick)


func test_all_airlines_progress_through_bronze_silver_gold_and_double_with_loyal_trait() -> void:
	var clock := auto_free(SimClock.new()) as SimClock
	clock.seed_rng(101)
	var flights := auto_free(FlightSim.new()) as FlightSim
	flights.open_airport()
	var desk := auto_free(OfferDesk.new()) as OfferDesk
	desk.runway = Runway.new(PlaneClasses.LARGE)
	desk.flights = flights
	desk.bind_clock(clock)

	_accept(flights, "STD", 600, "Blue Fjord", {})
	_accept(flights, "LOY", 900, "Sunhop", LOYAL_TRAIT)

	for nth in 12:
		_fly(flights, "LOY", nth)
	# Normal contract (+1/day): 12 days -> Gold (12).
	assert_int(desk.board.loyal_days("Blue Fjord")).is_equal(12)
	assert_int(desk.board.loyalty_tier("Blue Fjord")).is_equal(OfferBoard.LOYALTY_TIER_GOLD)
	assert_int(desk.board.loyalty_fee_percent("Blue Fjord")).is_equal(15)
	# LOYAL_AIRLINE (+2/day): reached Gold in 6 days and capped at 12.
	assert_int(desk.board.loyal_days("Sunhop")).is_equal(12)
	assert_int(desk.board.loyalty_tier("Sunhop")).is_equal(OfferBoard.LOYALTY_TIER_GOLD)

	# Verify exact tier thresholds and fee percents on a fresh board.
	var board := OfferBoard.new()
	for d in range(1, 14):
		board.note_flown("Gotta Air", d, 1)
		var expected_tier := 0
		var expected_pct := 0
		if d >= 12:
			expected_tier = OfferBoard.LOYALTY_TIER_GOLD
			expected_pct = 15
		elif d >= 7:
			expected_tier = OfferBoard.LOYALTY_TIER_SILVER
			expected_pct = 10
		elif d >= 3:
			expected_tier = OfferBoard.LOYALTY_TIER_BRONZE
			expected_pct = 5
		assert_int(board.loyalty_tier("Gotta Air")).is_equal(expected_tier)
		assert_int(board.loyalty_fee_percent("Gotta Air")).is_equal(expected_pct)


func test_tier_fee_bonuses_and_gold_hub_contracts_draw_at_3_stars_plus_only() -> void:
	var base_board := OfferBoard.new()
	var bronze_board := OfferBoard.new()
	var gold_board := OfferBoard.new()
	for d in 3:
		bronze_board.note_flown("Gotta Air", d, 1)
	for d in 12:
		gold_board.note_flown("Gotta Air", d, 1)
	assert_bool(gold_board.is_hub_eligible("Gotta Air", 2.5)).is_false()
	assert_bool(gold_board.is_hub_eligible("Gotta Air", 3.0)).is_true()

	# Below 3.0 stars (tier 0, stars=2.5): Bronze gets +5%, Gold gets +15%, never Hub.
	var rng_base := RandomNumberGenerator.new()
	var rng_bronze := RandomNumberGenerator.new()
	var rng_low := RandomNumberGenerator.new()
	var rng_high := RandomNumberGenerator.new()
	for rng in [rng_base, rng_bronze, rng_low, rng_high]:
		rng.seed = 4242
	var bronze_checked := 0
	var gold_checked := 0
	for day in range(12, 30):
		base_board.ensure_day(day, rng_base, 0, PlaneClasses.LARGE, null, {}, -1, 2.5)
		bronze_board.ensure_day(day, rng_bronze, 0, PlaneClasses.LARGE, null, {}, -1, 2.5)
		gold_board.ensure_day(day, rng_low, 0, PlaneClasses.LARGE, null, {}, -1, 2.5)
		for offer in bronze_board.open_offers():
			if offer["airline"] == "Gotta Air":
				bronze_checked += 1
				assert_int(offer["loyalty_tier"]).is_equal(OfferBoard.LOYALTY_TIER_BRONZE)
				var plain := base_board.offer_of(offer["id"])
				var traited_base := OfferBoard._base_fee_before_peak(
					int(plain["fee_per_passenger"]), int(plain["departure_minute"])
				)
				var expected := OfferBoard.apply_peak_bonus(
					OfferTraits.fee_with_bonus(traited_base, 5), int(offer["departure_minute"])
				)
				assert_int(int(offer["fee_per_passenger"])).is_equal(expected)
		for offer in gold_board.open_offers():
			assert_bool(offer["is_hub"]).is_false()
			if offer["airline"] == "Gotta Air":
				gold_checked += 1
				assert_int(offer["loyalty_tier"]).is_equal(OfferBoard.LOYALTY_TIER_GOLD)
				var plain := base_board.offer_of(offer["id"])
				var traited_base := OfferBoard._base_fee_before_peak(
					int(plain["fee_per_passenger"]), int(plain["departure_minute"])
				)
				var expected := OfferBoard.apply_peak_bonus(
					OfferTraits.fee_with_bonus(traited_base, 15), int(offer["departure_minute"])
				)
				assert_int(int(offer["fee_per_passenger"])).is_equal(expected)
	assert_int(bronze_checked).is_greater(0)
	assert_int(gold_checked).is_greater(0)

	# At 3.0+ stars (tier 1, stars=3.0): Gold airline draws both Hub (+25%) and regular Gold (+15%).
	var hub_board := OfferBoard.new()
	for d in 12:
		hub_board.note_flown("Gotta Air", d, 1)
	var hub_offers: Array[Dictionary] = []
	var non_hub_gold := 0
	for day in range(12, 60):
		base_board.ensure_day(day, rng_high, 1, PlaneClasses.LARGE, null, {}, -1, 3.0)
	rng_high.seed = 4242
	var flights := auto_free(FlightSim.new()) as FlightSim
	flights.open_airport()
	var hub_offer := {}
	for day in range(12, 60):
		hub_board.ensure_day(day, rng_high, 1, PlaneClasses.LARGE, null, {}, -1, 3.0)
		for offer in hub_board.open_offers():
			if offer["airline"] == "Gotta Air":
				if offer["is_hub"]:
					hub_offers.append(offer)
					if hub_offer.is_empty():
						hub_offer = offer
						assert_bool(hub_board.accept(hub_offer["id"], flights)).is_true()
				else:
					non_hub_gold += 1
			else:
				assert_bool(offer["is_hub"]).is_false()
	assert_int(hub_offers.size()).is_greater(0)
	assert_int(non_hub_gold).is_greater(0)

	# Hub contract propagates is_hub=true and +25% (Gold +15% + Hub +10%) to FlightContract.
	var base_offer := base_board.offer_of(hub_offer["id"])
	var minute := int(hub_offer["departure_minute"])
	var base_without_peak := OfferBoard._base_fee_before_peak(
		int(base_offer["fee_per_passenger"]), minute
	)
	var expected_hub_fee := OfferBoard.apply_peak_bonus(
		OfferTraits.fee_with_bonus(base_without_peak, 25), minute
	)
	assert_int(int(hub_offer["fee_per_passenger"])).is_equal(expected_hub_fee)
	var contract := flights.contract_of(hub_offer["id"])
	assert_bool(FlightContract.is_hub(contract)).is_true()
	assert_int(int(contract["fee_per_passenger"])).is_equal(expected_hub_fee)


func test_hub_contract_gets_one_extra_low_rating_grace_day_and_survives_snapshot() -> void:
	var clock := auto_free(SimClock.new()) as SimClock
	clock.seed_rng(777)
	var rating := auto_free(AirportRating.new()) as AirportRating
	var flights := auto_free(FlightSim.new()) as FlightSim
	flights.open_airport()
	var left: Array[Dictionary] = []
	var desk := auto_free(OfferDesk.new()) as OfferDesk
	desk.runway = Runway.new(PlaneClasses.LARGE)
	desk.rating = rating
	desk.flights = flights
	desk.contract_ended.connect(func(c: Dictionary) -> void: left.append(c))
	desk.bind_clock(clock)

	_accept(flights, "HUB1", 480, "Gotta Air", {}, true)
	_accept(flights, "STD1", 840, "Sunhop", {}, false)

	# Low days 1..2: warning only.
	for day in range(1, RatingFormula.LOW_DAYS_TO_END):
		_low_day_end(rating, clock, day)
		assert_array(left).is_empty()

	# Low day 3 (first cancellation day): HUB1 is oldest and uses its +1 grace day -> nothing ends!
	var grace_day := RatingFormula.LOW_DAYS_TO_END
	_low_day_end(rating, clock, grace_day)
	assert_array(left).is_empty()
	assert_bool(desk.board.has_hub_grace_used("HUB1")).is_true()
	assert_array(flights.active_contract_ids()).is_equal(["HUB1", "STD1"])

	# Snapshot round-trip preserves hub_grace_used so loading does not re-grant the grace day.
	var snap: Dictionary = JSON.parse_string(JSON.stringify(desk.board.to_snapshot()))
	var restored_board := OfferBoard.new()
	assert_bool(restored_board.from_snapshot(snap)).is_true()
	assert_bool(restored_board.has_hub_grace_used("HUB1")).is_true()

	# Recovery while HUB1 is still live resets rating.low_days() and clears hub_grace_used.
	_recovery_day_end(rating, clock, grace_day + 1)
	assert_int(rating.low_days()).is_equal(0)
	assert_bool(desk.board.has_hub_grace_used("HUB1")).is_false()
	assert_array(flights.active_contract_ids()).is_equal(["HUB1", "STD1"])

	# Subsequent low-rating cycle (past the 3-day rolling window) grants HUB1 its +1 grace day again.
	var cycle2_start := grace_day + RatingFormula.WINDOW_DAYS + 2
	for offset in RatingFormula.LOW_DAYS_TO_END - 1:
		_low_day_end(rating, clock, cycle2_start + offset)
		assert_array(left).is_empty()
	_low_day_end(rating, clock, cycle2_start + RatingFormula.LOW_DAYS_TO_END - 1)
	assert_array(left).is_empty()
	assert_bool(desk.board.has_hub_grace_used("HUB1")).is_true()
	assert_array(flights.active_contract_ids()).is_equal(["HUB1", "STD1"])

	# One more low day: HUB1 has spent its grace day in this cycle, so HUB1 ends now.
	_low_day_end(rating, clock, cycle2_start + RatingFormula.LOW_DAYS_TO_END)
	assert_int(left.size()).is_equal(1)
	assert_str(left[0]["id"]).is_equal("HUB1")
	assert_bool(desk.board.has_hub_grace_used("HUB1")).is_false()
	assert_array(flights.active_contract_ids()).is_equal(["STD1"])


func test_cozy_one_tier_demotion_on_player_early_contract_end() -> void:
	var clock := auto_free(SimClock.new()) as SimClock
	clock.seed_rng(555)
	var rating := auto_free(AirportRating.new()) as AirportRating
	var flights := auto_free(FlightSim.new()) as FlightSim
	flights.open_airport()
	var desk := auto_free(OfferDesk.new()) as OfferDesk
	desk.runway = Runway.new(PlaneClasses.LARGE)
	desk.rating = rating
	desk.flights = flights
	desk.bind_clock(clock)

	for d in 12:
		desk.board.note_flown("Gotta Air", d, 1)
	assert_int(desk.board.loyalty_tier("Gotta Air")).is_equal(OfferBoard.LOYALTY_TIER_GOLD)

	_accept(flights, "C1", 420, "Gotta Air")
	assert_bool(flights.end_contract_by_player("C1")).is_true()
	assert_int(desk.board.loyal_days("Gotta Air")).is_equal(OfferBoard.LOYALTY_SILVER_DAYS)
	assert_int(desk.board.loyalty_tier("Gotta Air")).is_equal(OfferBoard.LOYALTY_TIER_SILVER)

	_accept(flights, "C2", 660, "Gotta Air")
	assert_bool(flights.end_contract_by_player("C2")).is_true()
	assert_int(desk.board.loyal_days("Gotta Air")).is_equal(OfferBoard.LOYALTY_BRONZE_DAYS)
	assert_int(desk.board.loyalty_tier("Gotta Air")).is_equal(OfferBoard.LOYALTY_TIER_BRONZE)

	_accept(flights, "C3", 900, "Gotta Air")
	assert_bool(flights.end_contract_by_player("C3")).is_true()
	assert_int(desk.board.loyal_days("Gotta Air")).is_equal(0)
	assert_int(desk.board.loyalty_tier("Gotta Air")).is_equal(OfferBoard.LOYALTY_TIER_NONE)

	# Ending at None stays at 0 cleanly; low-rating end_contract does not demote loyalty.
	desk.board.note_flown("Sunhop", 0, 1)
	desk.board.note_flown("Sunhop", 1, 1)
	desk.board.note_flown("Sunhop", 2, 1)
	_accept(flights, "S1", 1140, "Sunhop")
	assert_bool(flights.end_contract("S1")).is_true()
	assert_int(desk.board.loyal_days("Sunhop")).is_equal(3)


func test_offer_panel_and_flight_planner_show_tier_and_hub_badges() -> void:
	var port := SubViewport.new()
	port.size = Vector2i(1280, 720)
	add_child(port)

	var clock := SimClock.new()
	var desk := OfferDesk.new()
	desk.clock = clock
	desk.runway = Runway.new(PlaneClasses.LARGE)
	var sim := FlightSim.new()
	sim.open_airport()
	port.add_child(clock)
	port.add_child(sim)
	port.add_child(desk)

	var records := TestOfferBoard.day_records(12, [600, 960, 1200])
	# O12N1: Gold Hub Contract at Morning Peak.
	records[0]["loyal"] = true
	records[0]["loyalty_tier"] = OfferBoard.LOYALTY_TIER_GOLD
	records[0]["is_hub"] = true
	records[0]["fee_per_passenger"] = OfferBoard.apply_peak_bonus(
		OfferTraits.fee_with_bonus(50, 25), 600
	)
	# O12N2: Silver airline.
	records[1]["airline"] = "Sunhop"
	records[1]["loyal"] = true
	records[1]["loyalty_tier"] = OfferBoard.LOYALTY_TIER_SILVER
	records[1]["fee_per_passenger"] = OfferTraits.fee_with_bonus(50, 10)
	# O12N3: Bronze airline.
	records[2]["airline"] = "Blue Fjord"
	records[2]["loyal"] = true
	records[2]["loyalty_tier"] = OfferBoard.LOYALTY_TIER_BRONZE
	records[2]["fee_per_passenger"] = OfferTraits.fee_with_bonus(50, 5)
	var data := TestOfferBoard.save_of(records)
	data["loyalty"] = {
		"Gotta Air": {"days": 12, "last_day": 11},
		"Sunhop": {"days": 7, "last_day": 11},
		"Blue Fjord": {"days": 3, "last_day": 11},
	}
	assert_bool(desk.board.from_snapshot(data)).is_true()

	var panel := OfferPanel.new()
	panel.desk = desk
	panel.flights = sim
	port.add_child(panel)
	panel.open()

	var hub_badge := panel.card("O12N1").find_child("HubBadge_O12N1", true, false) as PanelContainer
	assert_object(hub_badge).is_not_null()
	assert_str((hub_badge.find_child("HubLabel", true, false) as Label).text).is_equal(
		"Hub Contract"
	)
	assert_object(panel.card("O12N2").find_child("HubBadge_O12N2", true, false)).is_null()
	assert_str((panel.trait_row("O12N1").get_node("Loyal") as Label).text).is_equal("Gold +15%")
	assert_str((panel.trait_row("O12N2").get_node("Loyal") as Label).text).is_equal("Silver +10%")
	assert_str((panel.trait_row("O12N3").get_node("Loyal") as Label).text).is_equal("Bronze +5%")

	# Accept O12N1 (Hub) and O12N2 (non-Hub) and verify FlightPlanner HubTag.
	assert_bool(desk.board.accept("O12N1", sim)).is_true()
	assert_bool(desk.board.accept("O12N2", sim)).is_true()
	var planner := FlightPlanner.new()
	planner.flights = sim
	planner.clock = clock
	port.add_child(planner)
	planner.open()
	await await_idle_frame()
	await await_idle_frame()

	var hub_bar := planner.bar_button("O12N1", 0)
	var std_bar := planner.bar_button("O12N2", 0)
	assert_object(hub_bar).is_not_null()
	assert_object(std_bar).is_not_null()
	var hub_tag := hub_bar.find_child("HubTag", false, false) as PanelContainer
	assert_object(hub_tag).is_not_null()
	assert_str((hub_tag.find_child("HubTagLabel", false, false) as Label).text).is_equal("Hub")
	assert_str(hub_bar.tooltip_text).contains("Hub Contract")
	assert_object(std_bar.find_child("HubTag", false, false)).is_null()
	port.free()


func test_save_game_v37_round_trips_loyalty_hub_contracts_and_rejects_corrupt() -> void:
	var main := SaveTestKit.boot(self, 8_812_026)
	var save := SaveTestKit.save_game(main)
	SaveTestKit.start_airport(main)
	var flights := main.get_node("FlightSim") as FlightSim
	var desk := main.get_node("OfferDesk") as OfferDesk
	for i in 2700:
		SaveTestKit.step(main)
		if flights.opened_tick > 0:
			break
	assert_int(flights.opened_tick).is_greater(0)

	# Build a saved board state with Gold loyalty on Gotta Air and an accepted Hub Contract
	# on an open non-clashing slot so SaveLinks cross-part validation is satisfied.
	var records := TestOfferBoard.day_records(12, [600, 720, 960])
	records[0]["airline"] = "Sunhop"
	records[1]["airline"] = "Blue Fjord"
	records[2]["loyal"] = true
	records[2]["loyalty_tier"] = OfferBoard.LOYALTY_TIER_GOLD
	records[2]["is_hub"] = true
	records[2]["fee_per_passenger"] = OfferTraits.fee_with_bonus(50, 25)
	var board_data := TestOfferBoard.save_of(records)
	board_data["loyalty"] = {"Gotta Air": {"days": 12, "last_day": 11}}
	assert_bool(desk.board.from_snapshot(board_data)).is_true()
	assert_bool(desk.board.accept("O12N3", flights)).is_true()
	desk.board.note_hub_grace_used("O12N3")

	var snap: Dictionary = JSON.parse_string(JSON.stringify(save.snapshot(), "", true, true))
	assert_int(int(snap["save_version"])).is_greater_equal(38)
	assert_int(int(snap["offers"]["save_version"])).is_equal(10)
	assert_int(int(snap["flights"]["save_version"])).is_equal(FlightSim.SAVE_VERSION)
	assert_int(FlightSim.SAVE_VERSION).is_greater_equal(14)

	# Corrupt hub_grace_used or contract is_hub type is rejected cleanly.
	var bad := snap.duplicate(true)
	bad["offers"]["hub_grace_used"] = ["O12N3", "O12N3"]
	assert_bool(save.load_world(bad)).is_false()

	var bad_hub := snap.duplicate(true)
	for c: Dictionary in bad_hub["flights"]["contracts"]:
		if c["id"] == "O12N3":
			c["is_hub"] = "yes"
	assert_bool(save.load_world(bad_hub)).is_false()

	# SaveLinks refuses an offer-vs-contract mismatch on is_hub.
	var bad_link := snap.duplicate(true)
	for c: Dictionary in bad_link["flights"]["contracts"]:
		if c["id"] == "O12N3":
			c["is_hub"] = false
	assert_bool(save.load_world(bad_link)).is_false()

	# Valid round-trip restores loyalty, is_hub, and hub_grace_used.
	for i in 10:
		SaveTestKit.step(main)
	assert_bool(save.load_world(snap)).is_true()
	assert_int(desk.board.loyalty_tier("Gotta Air")).is_equal(OfferBoard.LOYALTY_TIER_GOLD)
	assert_bool(desk.board.has_hub_grace_used("O12N3")).is_true()
	assert_bool(FlightContract.is_hub(flights.contract_of("O12N3"))).is_true()
	main.free()
