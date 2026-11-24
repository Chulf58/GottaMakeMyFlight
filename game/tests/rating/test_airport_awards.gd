class_name TestAirportAwards
extends GdUnitTestSuite
## Stage 3 Pillar 3: Annual Airport Awards Ceremony (decision d5e50843).
## Verifies GameCalendar 10-day year boundaries, 5 award category evaluations,
## single-payout cash grants, DemoMode skipping, ClockHolds ceremony modal +
## PseudoLocale retranslation, $0 Award Trophy placement & RoomPrestige (+30),
## and SaveGame v40 round-trip + corrupt "awards" rollback.

var _save_paths: Array[String] = []


func after_test() -> void:
	DemoMode.clear_override()
	PseudoLocale.disable()
	TranslationServer.pseudolocalization_enabled = false
	TranslationServer.reload_pseudolocalization()
	for path in _save_paths:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")
	_save_paths.clear()


func _temp_save(tag: String) -> String:
	var path := SaveTestKit.run_path(tag)
	_save_paths.append(path)
	return path


func test_game_calendar_days_per_year_and_year_of_boundaries() -> void:
	assert_int(GameCalendar.DAYS_PER_YEAR).is_equal(10)
	assert_int(GameCalendar.year_of(0)).is_equal(0)
	assert_int(GameCalendar.year_of(9)).is_equal(0)
	assert_int(GameCalendar.year_of(10)).is_equal(1)
	assert_int(GameCalendar.year_of(19)).is_equal(1)
	assert_int(GameCalendar.year_of(20)).is_equal(2)
	assert_int(GameCalendar.year_of(-1)).is_equal(-1)
	assert_int(GameCalendar.day_of_year(0)).is_equal(0)
	assert_int(GameCalendar.day_of_year(9)).is_equal(9)
	assert_int(GameCalendar.day_of_year(10)).is_equal(0)
	assert_int(GameCalendar.day_of_year(15)).is_equal(5)


func test_year_one_rollover_evaluates_all_five_categories_pays_once_and_resets() -> void:
	var clock: SimClock = auto_free(SimClock.new())
	var rating: AirportRating = auto_free(AirportRating.new())
	var finances: Finances = auto_free(Finances.new())
	add_child(clock)
	add_child(rating)
	add_child(finances)
	finances.wallet.clock = clock
	var start_bal := finances.wallet.balance

	# High rating >= 3.5 stars.
	for i in 25:
		rating.record_passenger(0, true, PassengerSim.MOOD_MAX)
	assert_float(rating.stars()).is_greater_equal(3.5)

	var awards: AirportAwards = auto_free(AirportAwards.new())
	add_child(awards)
	awards.bind(clock, null, null, rating, finances)

	var reports: Array[Dictionary] = []
	awards.ceremony_due.connect(func(r: Dictionary) -> void: reports.append(r))

	# Accumulate metrics meeting all 4 sub-categories + Airport of the Year.
	for i in 20:
		awards.record_passenger(true, 80)
	awards.record_messes_left(5)
	finances.wallet.credit(500, Wallet.Category.SHOP)
	var after_shop_bal := finances.wallet.balance
	assert_int(after_shop_bal).is_equal(start_bal + 500)
	assert_int(int(awards.current_metrics()["year_hospitality_earned"])).is_equal(500)

	# Day 9 does not trigger a ceremony.
	clock.tick = GameCalendar.day_start(9, 0)
	awards.on_tick(clock.tick)
	assert_int(reports.size()).is_equal(0)
	assert_int(awards.last_ceremony_year()).is_equal(0)

	# Day 10 triggers Year 1 ceremony.
	clock.tick = GameCalendar.day_start(10, 0)
	awards.on_tick(clock.tick)
	assert_int(reports.size()).is_equal(1)
	var r := reports[0]
	assert_int(int(r["year"])).is_equal(1)
	assert_int(int(r["won_count"])).is_equal(5)
	assert_int(int(r["trophies_won"])).is_equal(5)
	var expected_cash := (
		AirportAwards.PRIZE_ON_TIME
		+ AirportAwards.PRIZE_SPOTLESS
		+ AirportAwards.PRIZE_HAPPIEST
		+ AirportAwards.PRIZE_HOSPITALITY
		+ AirportAwards.PRIZE_AIRPORT_OF_YEAR
	)
	assert_int(expected_cash).is_equal(13000)
	assert_int(int(r["total_cash"])).is_equal(expected_cash)
	assert_int(finances.wallet.balance).is_equal(after_shop_bal + expected_cash)
	assert_int(awards.trophies_earned()).is_equal(5)
	assert_int(awards.last_ceremony_year()).is_equal(1)

	# Year counters reset cleanly for Year 2.
	var year2 := awards.current_metrics()
	assert_int(int(year2["year_made"])).is_equal(0)
	assert_int(int(year2["year_missed"])).is_equal(0)
	assert_int(int(year2["year_mood_sum"])).is_equal(0)
	assert_int(int(year2["year_messes_left"])).is_equal(0)
	assert_int(int(year2["year_hospitality_earned"])).is_equal(0)

	# Re-ticking Day 10 or Day 15 never double-fires or double-pays.
	awards.on_tick(clock.tick + 1)
	clock.tick = GameCalendar.day_start(15, 0)
	awards.on_tick(clock.tick)
	assert_int(reports.size()).is_equal(1)
	assert_int(finances.wallet.balance).is_equal(after_shop_bal + expected_cash)

	# Day 20 triggers Year 2 (with 0 wins because counters were reset).
	clock.tick = GameCalendar.day_start(20, 0)
	awards.on_tick(clock.tick)
	assert_int(reports.size()).is_equal(2)
	assert_int(int(reports[1]["year"])).is_equal(2)
	assert_int(int(reports[1]["won_count"])).is_equal(0)
	assert_int(int(reports[1]["total_cash"])).is_equal(0)
	assert_int(awards.trophies_earned()).is_equal(5)


func test_category_thresholds_and_airport_of_the_year_requirements() -> void:
	var awards: AirportAwards = auto_free(AirportAwards.new())
	# Only 2 sub-awards won (Spotless + Hospitality) -> NOT Airport of the Year.
	var two_wins := (
		awards
		. evaluate_year(
			{
				"year": 1,
				"year_made": 20,
				"year_missed": 5,  # 20/25 = 80% < 85%
				"year_mood_sum": 20 * 70,  # avg 70 < 72
				"year_messes_left": 10,  # <= 10 (won)
				"year_hospitality_earned": 500,  # >= 500 (won)
				"rating_stars": 4.5,
			}
		)
	)
	assert_int(int(two_wins["sub_won"])).is_equal(2)
	assert_int(int(two_wins["won_count"])).is_equal(2)
	assert_int(int(two_wins["total_cash"])).is_equal(
		AirportAwards.PRIZE_SPOTLESS + AirportAwards.PRIZE_HOSPITALITY
	)

	# 3 sub-awards won, but rating 3.0 < 3.5 -> NOT Airport of the Year.
	var low_rating := (
		awards
		. evaluate_year(
			{
				"year": 1,
				"year_made": 20,
				"year_missed": 3,  # 20/23 = 86.9% >= 85% (won)
				"year_mood_sum": 20 * 72,  # avg 72 >= 72 (won)
				"year_messes_left": 10,  # <= 10 (won)
				"year_hospitality_earned": 499,  # < 500
				"rating_stars": 3.0,
			}
		)
	)
	assert_int(int(low_rating["sub_won"])).is_equal(3)
	assert_int(int(low_rating["won_count"])).is_equal(3)

	# 3 sub-awards won AND rating 3.5 -> wins Airport of the Year too (4 total).
	var three_plus_rating := (
		awards
		. evaluate_year(
			{
				"year": 1,
				"year_made": 20,
				"year_missed": 3,
				"year_mood_sum": 20 * 72,
				"year_messes_left": 10,
				"year_hospitality_earned": 499,
				"rating_stars": 3.5,
			}
		)
	)
	assert_int(int(three_plus_rating["sub_won"])).is_equal(3)
	assert_int(int(three_plus_rating["won_count"])).is_equal(4)
	assert_int(int(three_plus_rating["total_cash"])).is_equal(
		(
			AirportAwards.PRIZE_ON_TIME
			+ AirportAwards.PRIZE_SPOTLESS
			+ AirportAwards.PRIZE_HAPPIEST
			+ AirportAwards.PRIZE_AIRPORT_OF_YEAR
		)
	)


func test_demo_mode_skips_annual_ceremony() -> void:
	DemoMode.set_override_for_test(true)
	var clock: SimClock = auto_free(SimClock.new())
	var finances: Finances = auto_free(Finances.new())
	add_child(clock)
	add_child(finances)
	var before_bal := finances.wallet.balance
	var awards: AirportAwards = auto_free(AirportAwards.new())
	add_child(awards)
	awards.bind(clock, null, null, null, finances)
	for i in 25:
		awards.record_passenger(true, 100)
	awards.record_hospitality(1000)
	var fired := 0
	awards.ceremony_due.connect(func(_r: Dictionary) -> void: fired += 1)
	clock.tick = GameCalendar.day_start(10, 0)
	awards.on_tick(clock.tick)
	assert_int(fired).is_equal(0)
	assert_int(awards.last_ceremony_year()).is_equal(0)
	assert_int(awards.trophies_earned()).is_equal(0)
	assert_int(finances.wallet.balance).is_equal(before_bal)


func test_ceremony_modal_holds_clock_releases_on_continue_and_esc_and_retranslates() -> void:
	var port: SubViewport = auto_free(SubViewport.new())
	port.size = Vector2i(1536, 864)
	add_child(port)
	var clock: SimClock = auto_free(SimClock.new())
	port.add_child(clock)
	var awards: AirportAwards = auto_free(AirportAwards.new())
	port.add_child(awards)
	var ceremony: AwardsCeremony = auto_free(AwardsCeremony.new())
	ceremony.awards = awards
	ceremony.clock = clock
	port.add_child(ceremony)

	var report := (
		awards
		. evaluate_year(
			{
				"year": 1,
				"year_made": 20,
				"year_missed": 0,
				"year_mood_sum": 20 * 80,
				"year_messes_left": 0,
				"year_hospitality_earned": 600,
				"rating_stars": 4.0,
			}
		)
	)
	ceremony.present(report)
	assert_bool(ceremony.is_open()).is_true()
	assert_bool(clock.paused).is_true()
	assert_bool(clock.holds.is_holding()).is_true()

	var panel := ceremony.panel()
	var texts := _labels_text(panel)
	(
		assert_array(texts)
		. contains(
			[
				"Year 1 Airport Awards",
				"On-Time Champion",
				"Spotless Terminal",
				"Happiest Passengers",
				"Best Hospitality",
				"Airport of the Year",
				"Place your Award Trophy from the Decor tab for +30 Room Prestige!",
			]
		)
	)
	assert_str(ceremony.continue_button().text).is_equal("Continue")

	# Pseudolocalization updates live while open.
	PseudoLocale.enable(0.4)
	ceremony.notification(Node.NOTIFICATION_TRANSLATION_CHANGED)
	assert_str(ceremony.continue_button().text).starts_with("[")
	PseudoLocale.disable()
	ceremony.notification(Node.NOTIFICATION_TRANSLATION_CHANGED)
	assert_str(ceremony.continue_button().text).is_equal("Continue")

	# Clicking Continue closes modal and releases ClockHolds hold.
	ceremony.continue_button().pressed.emit()
	assert_bool(ceremony.is_open()).is_false()
	assert_bool(clock.holds.is_holding()).is_false()
	assert_bool(clock.paused).is_false()

	# Re-open and close with Esc (KEY_ESCAPE).
	ceremony.present(report)
	assert_bool(ceremony.is_open()).is_true()
	assert_bool(clock.holds.is_holding()).is_true()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	port.push_input(esc)
	assert_bool(ceremony.is_open()).is_false()
	assert_bool(clock.holds.is_holding()).is_false()


func test_award_trophy_placement_count_gating_demolish_sandbox_and_prestige() -> void:
	var finances: Finances = auto_free(Finances.new())
	var clock: SimClock = auto_free(SimClock.new())
	var rating: AirportRating = auto_free(AirportRating.new())
	var pax: PassengerSim = auto_free(PassengerSim.new())
	var awards: AirportAwards = auto_free(AirportAwards.new())
	var unlocks: BuildUnlocks = auto_free(BuildUnlocks.new())
	unlocks.rating = rating
	unlocks.passengers = pax
	unlocks.manual = true
	var mode: BuildMode = auto_free(BuildMode.new())
	mode.grid_size = Vector2i(14, 14)
	mode.finances = finances
	mode.unlocks = unlocks
	mode.require_unlocks = true
	mode.awards = awards
	add_child(clock)
	add_child(finances)
	add_child(awards)
	add_child(unlocks)
	add_child(mode)
	awards.bind(clock, null, null, null, finances)

	# Paint a 4x4 floor + mark a Cafe room (min 3x3).
	mode.set_tool(BuildMode.Tool.FLOOR)
	mode.begin_area(mode.grid.cell_to_world(Vector2i(1, 1)))
	mode.move_area(mode.grid.cell_to_world(Vector2i(4, 4)))
	mode.finish_area()
	assert_bool(mode.grid.apply(BuildEdit.place_room(Rect2i(1, 1, 4, 4), &"cafe")).ok).is_true()
	var room_id := mode.grid.room_at(Vector2i(1, 1))
	var base_prestige := RoomPrestige.evaluate_room(mode.grid, room_id)
	assert_int(int(base_prestige["trophy_points"])).is_equal(0)

	# Before winning any award trophy: tool selection & placement are refused in Career.
	mode.set_tool(BuildMode.Tool.AWARD_TROPHY)
	assert_int(mode.tool).is_not_equal(BuildMode.Tool.AWARD_TROPHY)
	var before_earned := mode.apply_edit(BuildEdit.place_object(&"award_trophy", Vector2i(2, 2), 0))
	assert_bool(before_earned.ok).is_false()
	assert_int(before_earned.reason).is_equal(BuildResult.Reason.LOCKED)

	# Earn 1 trophy via Year 1 hospitality award.
	awards.record_hospitality(600)
	clock.tick = GameCalendar.day_start(10, 0)
	awards.on_tick(clock.tick)
	assert_int(awards.trophies_earned()).is_equal(1)
	assert_int(awards.trophies_available(mode.grid)).is_equal(1)

	# Place 1 trophy inside the room for $0 (even at Tier 1!).
	var bal_before := finances.wallet.balance
	mode.set_tool(BuildMode.Tool.AWARD_TROPHY)
	assert_int(mode.tool).is_equal(BuildMode.Tool.AWARD_TROPHY)
	var first := mode.apply_at(mode.grid.cell_to_world(Vector2i(2, 2)))
	assert_bool(first.ok).is_true()
	assert_int(finances.wallet.balance).is_equal(bal_before)
	assert_int(mode.grid.count_objects(&"award_trophy")).is_equal(1)
	assert_int(awards.trophies_available(mode.grid)).is_equal(0)

	# RoomPrestige gains +30 trophy points!
	var with_trophy := RoomPrestige.evaluate_room(mode.grid, room_id)
	assert_int(int(with_trophy["trophy_points"])).is_equal(30)
	assert_int(int(with_trophy["score"])).is_equal(int(base_prestige["score"]) + 30)

	# Second placement refused in Career when trophy count is exhausted.
	var second := mode.apply_at(mode.grid.cell_to_world(Vector2i(3, 2)))
	assert_bool(second.ok).is_false()
	assert_int(second.reason).is_equal(BuildResult.Reason.LOCKED)
	assert_int(mode.grid.count_objects(&"award_trophy")).is_equal(1)

	# Demolishing the placed trophy refunds $0 and frees the trophy count back up.
	mode.set_tool(BuildMode.Tool.REMOVE)
	var removed := mode.apply_at(mode.grid.cell_to_world(Vector2i(2, 2)))
	assert_bool(removed.ok).is_true()
	assert_int(finances.wallet.balance).is_equal(bal_before)
	assert_int(mode.grid.count_objects(&"award_trophy")).is_equal(0)
	assert_int(awards.trophies_available(mode.grid)).is_equal(1)

	# Can place again after demolishing.
	mode.set_tool(BuildMode.Tool.AWARD_TROPHY)
	assert_bool(mode.apply_at(mode.grid.cell_to_world(Vector2i(3, 2))).ok).is_true()
	assert_int(awards.trophies_available(mode.grid)).is_equal(0)

	# Sandbox (require_unlocks = false) bypasses trophies_available cap.
	mode.require_unlocks = false
	assert_bool(mode.apply_at(mode.grid.cell_to_world(Vector2i(2, 2))).ok).is_true()
	assert_int(mode.grid.count_objects(&"award_trophy")).is_equal(2)


func test_save_game_v40_round_trip_and_corrupt_awards_refusal() -> void:
	var main: Node = SaveTestKit.boot(self, 40_2026)
	var save := SaveTestKit.save_game(main)
	var flights: FlightSim = main.get_node("FlightSim")
	flights.open_airport()
	SaveTestKit.step(main)
	var awards := save.ensure_awards()
	assert_int(SaveGame.SAVE_VERSION).is_greater_equal(40)

	# Accumulate Year 1 metrics & trigger Year 1 ceremony evaluation.
	awards.record_hospitality(800)
	for i in 20:
		awards.record_passenger(true, 90)
	var report := awards.evaluate_live_ceremony(1)
	assert_int(int(report["year"])).is_equal(1)
	assert_int(awards.last_ceremony_year()).is_equal(1)
	assert_int(awards.trophies_earned()).is_greater_equal(2)
	if save.awards_ceremony != null and save.awards_ceremony.is_open():
		save.awards_ceremony.close()
	var expected_snap := awards.to_save_dict()
	var expected_bal := (main.get_node("Finances") as Finances).wallet.balance

	# Save to file, mutate live state, reload, and verify exact restoration without double-pay.
	var path := _temp_save("awards_v40")
	assert_bool(save.save_to_file(path)).is_true()
	awards.reset()
	assert_int(awards.trophies_earned()).is_equal(0)
	assert_bool(save.load_from_file(path)).is_true()
	assert_dict(awards.to_save_dict()).is_equal(expected_snap)
	assert_int((main.get_node("Finances") as Finances).wallet.balance).is_equal(expected_bal)

	# Corrupt "awards" cases are refused whole without changing live state.
	var baseline_checksum := SaveTestKit.checksum(main)
	var corrupt_cases: Array[Dictionary] = [
		{"key": "trophies_earned", "val": -1},
		{"key": "save_version", "val": 99},
		{"key": "year_mood_sum", "val": 999999},
		{"key": "unknown_field", "val": 1},
	]
	for case: Dictionary in corrupt_cases:
		var bad := save.snapshot()
		(bad["awards"] as Dictionary)[case["key"]] = case["val"]
		assert_bool(save.load_world(bad)).is_false()
		assert_str(save.message_text()).starts_with("Load failed")
		assert_str(SaveTestKit.checksum(main)).is_equal(baseline_checksum)
	main.free()


func test_trophies_changed_signal_only_emits_when_trophy_count_changes() -> void:
	var clock: SimClock = auto_free(SimClock.new())
	var rating: AirportRating = auto_free(AirportRating.new())
	var finances: Finances = auto_free(Finances.new())
	add_child(clock)
	add_child(rating)
	add_child(finances)
	finances.wallet.clock = clock

	var awards: AirportAwards = auto_free(AirportAwards.new())
	add_child(awards)
	awards.bind(clock, null, null, rating, finances)

	var changed_hits := [0]
	var trophy_hits := [0]
	awards.changed.connect(func() -> void: changed_hits[0] += 1)
	awards.trophies_changed.connect(func() -> void: trophy_hits[0] += 1)

	awards.record_passenger(true, 85)
	awards.record_hospitality(200)
	awards.record_messes_left(1)
	assert_int(changed_hits[0]).is_equal(3)
	assert_int(trophy_hits[0]).is_equal(0)

	# Evaluation with 0 earned trophies should not emit trophies_changed.
	awards.evaluate_live_ceremony(1)
	assert_int(awards.trophies_earned()).is_equal(0)
	assert_int(trophy_hits[0]).is_equal(0)

	# Winning categories emits trophies_changed once.
	for i in 20:
		awards.record_passenger(true, 90)
	awards.evaluate_live_ceremony(2)
	assert_int(awards.trophies_earned()).is_greater(0)
	assert_int(trophy_hits[0]).is_equal(1)

	# Resetting emits trophies_changed; loading matching count skips it, differing count emits it.
	awards.reset()
	assert_int(trophy_hits[0]).is_equal(2)
	var snap := awards.to_save_dict()
	assert_bool(awards.from_save_dict(snap)).is_true()
	assert_int(trophy_hits[0]).is_equal(2)
	snap["trophies_earned"] = 2
	assert_bool(awards.from_save_dict(snap)).is_true()
	assert_int(trophy_hits[0]).is_equal(3)


func test_template_paste_enforces_career_trophy_cap() -> void:
	var clock: SimClock = auto_free(SimClock.new())
	var finances: Finances = auto_free(Finances.new())
	var unlocks: BuildUnlocks = auto_free(BuildUnlocks.new())
	unlocks.rating = auto_free(AirportRating.new())
	unlocks.passengers = auto_free(PassengerSim.new())
	unlocks.manual = true
	var awards: AirportAwards = auto_free(AirportAwards.new())
	add_child(clock)
	add_child(finances)
	add_child(unlocks)
	add_child(awards)
	finances.wallet.clock = clock
	awards.bind(clock, null, null, unlocks.rating, finances)

	var site := SiteDefinition.new()
	site.grid_size = Vector2i(20, 20)
	site.plot_columns = PackedInt32Array([20])
	site.plot_rows = 1
	site.centre_columns = Vector2i(0, 1)
	site.obstacles = [] as Array[Vector2i]

	var mode: BuildMode = auto_free(BuildMode.new())
	mode.site = site
	mode.finances = finances
	mode.unlocks = unlocks
	mode.awards = awards
	mode.require_unlocks = true
	add_child(mode)
	LandKit.own_all(mode.land_tool.land)
	mode.set_process(false)

	var floor_edits: Array[BuildEdit] = []
	for y in range(1, 19):
		for x in range(1, 19):
			floor_edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	mode.grid.apply_batch(floor_edits)

	var room_plan: Array[BuildEdit] = [BuildEdit.place_room(Rect2i(2, 2, 4, 4), &"toilet")]
	assert_bool(BuildTransaction.commit_plan(mode.grid, room_plan, mode.wallet()).ok).is_true()

	# Save a template containing 1 award_trophy (after temporarily earning 1 trophy).
	awards.record_hospitality(600)
	awards.evaluate_live_ceremony(1)
	assert_int(awards.trophies_earned()).is_equal(1)

	var place_trophy: Array[BuildEdit] = [
		BuildEdit.place_object(&"award_trophy", Vector2i(3, 3), 0)
	]
	var placed_res := BuildTransaction.commit_plan(mode.grid, place_trophy, mode.wallet())
	assert_bool(placed_res.ok).is_true()
	var room_id := mode.grid.room_at(Vector2i(3, 3))
	assert_object(mode.templates.save_room(room_id)).is_not_null()
	mode.templates.arm(0)

	# 1 earned and 1 placed -> available is 0 -> template paste is locked.
	assert_int(awards.trophies_available(mode.grid)).is_equal(0)
	assert_str(mode.templates.lock_text(0)).is_not_empty()
	var locked_res := mode.templates.paste_at(Vector2i(13, 13))
	assert_bool(locked_res.ok).is_false()
	assert_int(locked_res.reason).is_equal(BuildResult.Reason.LOCKED)
	assert_int(mode.grid.count_objects(&"award_trophy")).is_equal(1)

	# Demolishing the existing trophy frees the slot so the template pastes cleanly.
	var remove_plan: Array[BuildEdit] = [BuildEdit.remove_object(placed_res.object_id)]
	assert_bool(BuildTransaction.commit_plan(mode.grid, remove_plan, mode.wallet()).ok).is_true()
	assert_int(awards.trophies_available(mode.grid)).is_equal(1)
	assert_str(mode.templates.lock_text(0)).is_empty()
	var paste_res := mode.templates.paste_at(Vector2i(13, 13))
	assert_bool(paste_res.ok).is_true()
	assert_int(mode.grid.count_objects(&"award_trophy")).is_equal(1)

	# Second paste exceeds Career cap -> refused; Sandbox (require_unlocks = false) allows it.
	var over_cap := mode.templates.paste_at(Vector2i(6, 13))
	assert_bool(over_cap.ok).is_false()
	assert_int(over_cap.reason).is_equal(BuildResult.Reason.LOCKED)
	mode.require_unlocks = false
	var sandbox_res := mode.templates.paste_at(Vector2i(6, 13))
	assert_bool(sandbox_res.ok).is_true()
	assert_int(mode.grid.count_objects(&"award_trophy")).is_equal(2)


func _labels_text(node: Node) -> Array[String]:
	var out: Array[String] = []
	if node == null:
		return out
	for lbl in node.find_children("*", "Label", true, false):
		out.append((lbl as Label).text)
	return out
