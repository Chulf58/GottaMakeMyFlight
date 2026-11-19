class_name TestDemoScope
extends GdUnitTestSuite
## Demo scope & cut line (board D1b, decision
## demo-scope-and-cut-line-d1-cap-playable-unlocks-at-tier-2-1):
##   1. Full-game default (DemoMode.is_demo() == false) leaves Tiers 1-4, all
##      land plots, all 6 incidents, and Day 6+ freeplay untouched.
##   2. Demo mode caps BuildUnlocks at Tier 2, labels Tier 3 tools + large
##      runway "In the full game", and hides Tier 4 cards and empty pages in
##      BuildMenu.
##   3. Demo mode allows 1 extra land plot and refuses the 2nd extra plot.
##   4. Demo mode filters IncidentCatalogue rolls to SPILL, FAULT, and RUSH,
##      excluding INSPECTOR, VIP, and FAVOUR.
##   5. Demo mode triggers DemoEndCard when Day 5 rolls into Day 6 (pausing
##      synchronously at 3x, showing stats + ruled copy, invoking Wishlist and
##      Back to Title handlers, writing the Day-6 morning autosave, and
##      re-showing DemoEndCard paused on load when past Day 5).

const SITE := preload("res://build/terminal_site.tres")
const FIRST_EXTRA_PLOT := Vector2i(6, 4)
const SECOND_EXTRA_PLOT := Vector2i(6, 3)

var _save_paths: Array[String] = []
var _slots_dir := SaveTestKit.run_dir("test_demo_scope_slots")
var _slots_dir_before := ""


func before_test() -> void:
	_slots_dir_before = SaveSlots.dir
	DemoMode.clear_override()


func after_test() -> void:
	DemoMode.clear_override()
	PseudoLocale.disable()
	GameBoot.load_path = ""
	GameBoot.refusal = ""
	GameBoot.clear_new_airport()
	for path in _save_paths:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")
	_save_paths.clear()
	if SaveSlots.dir == _slots_dir:
		for path in SaveSlots.all_paths():
			DirAccess.remove_absolute(path)
			DirAccess.remove_absolute(path + ".tmp")
		DirAccess.remove_absolute(_slots_dir)
	SaveSlots.dir = _slots_dir_before


func _temp_save(tag: String) -> String:
	var path := SaveTestKit.run_path(tag)
	_save_paths.append(path)
	return path


func _plot_middle(mode: BuildMode, plot: Vector2i) -> Vector3:
	var cells := mode.land_tool.land.plot_cells(plot)
	return mode.grid.cell_to_world(cells.position + cells.size / 2)


func _card_last_line(card: Button) -> String:
	var labels := card.find_children("*", "Label", true, false)
	return (labels[labels.size() - 1] as Label).text


func _make_unlocks_pair(stars_passengers: int, made_count: int) -> Dictionary:
	var rating: AirportRating = auto_free(AirportRating.new())
	var pax: PassengerSim = auto_free(PassengerSim.new())
	var unlocks: BuildUnlocks = auto_free(BuildUnlocks.new())
	unlocks.rating = rating
	unlocks.passengers = pax
	unlocks.manual = true
	add_child(unlocks)
	for i in stars_passengers:
		rating.record_passenger(0, true, PassengerSim.MOOD_MAX)
	for i in made_count:
		pax.outcome.emit(i, true)
	unlocks.check()
	return {"rating": rating, "pax": pax, "unlocks": unlocks}


func test_full_game_default_leaves_tiers_land_incidents_and_day6_untouched() -> void:
	assert_bool(DemoMode.is_demo()).is_false()
	var pair := _make_unlocks_pair(700, 600)
	var unlocks: BuildUnlocks = pair["unlocks"]
	assert_int(unlocks.tier()).is_equal(4)
	assert_bool(unlocks.allows(BuildMode.Tool.TREE)).is_true()
	assert_bool(unlocks.allows(BuildMode.Tool.MULTI_STOREY)).is_true()
	assert_str(BuildUnlocks.requirement_text(3)).is_equal("Unlocks at 3 stars and 200 passengers")
	assert_str(BuildUnlocks.requirement_text(4)).is_equal("Unlocks at 4 stars and 600 passengers")

	var port: SubViewport = auto_free(SubViewport.new())
	port.size = Vector2i(1536, 864)
	add_child(port)
	var finances: Finances = auto_free(Finances.new())
	finances.wallet.credit(100000, Wallet.Category.FEES)
	port.add_child(finances)
	var mode: BuildMode = auto_free(BuildMode.new())
	mode.site = SITE
	mode.finances = finances
	mode.unlocks = unlocks
	mode.require_unlocks = true
	port.add_child(mode)
	mode.set_process(false)
	var menu: BuildMenu = auto_free(BuildMenu.new())
	menu.build_mode = mode
	port.add_child(menu)
	assert_bool(menu.card(BuildMode.Tool.MULTI_STOREY).visible).is_true()
	assert_bool(menu.card(BuildMode.Tool.DUTY_FREE_ROOM).visible).is_true()

	mode.set_tool(BuildMode.Tool.BUY_LAND)
	assert_bool(mode.apply_at(_plot_middle(mode, FIRST_EXTRA_PLOT)).ok).is_true()
	assert_bool(mode.apply_at(_plot_middle(mode, SECOND_EXTRA_PLOT)).ok).is_true()
	assert_int(mode.land_tool.land.bought).is_equal(2)

	var candidates := IncidentCatalogue.candidates(
		{"tier": 3, "places": 4, "faults": 2, "contracts": 2}
	)
	var kinds := candidates.map(func(c: Dictionary) -> String: return c["kind"])
	assert_array(kinds).contains_exactly(IncidentCatalogue.ORDER)

	var clock: SimClock = auto_free(SimClock.new())
	port.add_child(clock)
	var end_card: DemoEndCard = auto_free(DemoEndCard.new())
	end_card.clock = clock
	port.add_child(end_card)
	clock.tick = GameCalendar.day_start(DemoMode.MAX_DEMO_DAY, 0) - 1
	clock.set_speed(3)
	clock.advance(SimClock.STEP * 2.0)
	assert_bool(end_card.is_open()).is_false()
	assert_bool(clock.paused).is_false()


func test_demo_caps_build_unlocks_at_tier_2_and_refuses_tier3_tier4_and_large_runway() -> void:
	DemoMode.set_override_for_test(true)
	var pair := _make_unlocks_pair(1000, 1000)
	var rating: AirportRating = pair["rating"]
	var unlocks: BuildUnlocks = pair["unlocks"]
	assert_float(rating.stars()).is_equal(5.0)
	assert_int(unlocks.made_total()).is_equal(1000)
	assert_int(unlocks.tier()).is_equal(DemoMode.MAX_PLAYABLE_TIER)
	assert_bool(unlocks.allows(BuildMode.Tool.CAFE_ROOM)).is_true()
	assert_bool(unlocks.allows(BuildMode.Tool.TREE)).is_false()
	assert_bool(unlocks.allows(BuildMode.Tool.MULTI_STOREY)).is_false()

	assert_str(BuildUnlocks.lock_text(unlocks, true, BuildMode.Tool.TREE)).is_equal(
		"In the full game"
	)
	assert_str(BuildUnlocks.lock_text(unlocks, true, BuildMode.Tool.MULTI_STOREY)).is_equal(
		"In the full game"
	)
	var edits: Array[BuildEdit] = [
		BuildEdit.place_room(Rect2i(Vector2i.ZERO, Vector2i(4, 4)), &"restaurant")
	]
	assert_str(BuildUnlocks.edits_lock_text(unlocks, true, edits)).is_equal("In the full game")

	var flights: FlightSim = auto_free(FlightSim.new())
	flights.runway.size = PlaneClasses.MEDIUM
	var wallet := Wallet.new(500000)
	assert_str(RunwayWorks.problem(flights, unlocks, wallet)).is_equal("In the full game")

	var loaded: BuildUnlocks = auto_free(BuildUnlocks.new())
	var ok := loaded.from_snapshot(
		{"tier": 4, "made": 600, "shown": [2, 3, 4], "seen": ["CAFE_ROOM", "TREE"], "firsts": []}
	)
	assert_bool(ok).is_true()
	assert_int(loaded.tier()).is_equal(DemoMode.MAX_PLAYABLE_TIER)
	assert_bool(loaded.from_snapshot(loaded.to_snapshot())).is_true()


func test_demo_build_menu_greys_tier3_teasers_hides_tier4_and_prunes_empty_pages() -> void:
	DemoMode.set_override_for_test(true)
	var pair := _make_unlocks_pair(100, 100)
	var unlocks: BuildUnlocks = pair["unlocks"]
	var port: SubViewport = auto_free(SubViewport.new())
	port.size = Vector2i(1536, 864)
	add_child(port)
	var mode: BuildMode = auto_free(BuildMode.new())
	mode.grid_size = Vector2i(20, 20)
	mode.initial_tool = BuildMode.Tool.NONE
	mode.unlocks = unlocks
	mode.require_unlocks = true
	port.add_child(mode)
	mode.set_process(false)
	var menu: BuildMenu = auto_free(BuildMenu.new())
	menu.build_mode = mode
	port.add_child(menu)

	# Tier 2 unlocked, Tier 3 greyed with "In the full game", Tier 4 hidden.
	assert_object(menu.card(BuildMode.Tool.CAFE_ROOM).modulate).is_equal(Color.WHITE)
	var tree_card := menu.card(BuildMode.Tool.TREE)
	assert_bool(tree_card.visible).is_true()
	assert_object(tree_card.modulate).is_equal(BuildMenu.LOCKED_TINT)
	assert_str(_card_last_line(tree_card)).is_equal("In the full game")
	assert_str(tree_card._get_tooltip(Vector2.ZERO)).contains("In the full game")
	assert_str(tree_card._get_tooltip(Vector2.ZERO)).not_contains("Unlocks at")
	menu.press_card(BuildMode.Tool.TREE)
	assert_int(mode.tool).is_not_equal(BuildMode.Tool.TREE)
	assert_str(menu.status_label().text).is_equal("In the full game")

	for tool: BuildMode.Tool in BuildMode.Tool.values():
		if BuildUnlocks.tier_of(tool) >= DemoMode.HIDDEN_MIN_TIER:
			var hidden := menu.card(tool)
			if hidden != null:
				assert_bool(hidden.visible).is_false()

	# Shops has only Pharmacy (Tier 3) left after Duty free and Fashion (Tier 4) hide:
	# its Next card hides, and Services / Leisure skip Care / Fun so no empty tray opens.
	var shops := BuildMenu.group_index("Shops")
	menu.press_category(shops)
	var shops_next := (
		menu.card(BuildMode.Tool.PHARMACY_ROOM).get_parent().find_child("CardNext", true, false)
		as Button
	)
	assert_bool(shops_next.visible).is_false()

	for group_name in ["Decor", "Food", "Services", "Leisure", "Shops"]:
		var start := BuildMenu.group_index(group_name)
		menu.press_category(start)
		for _step in 6:
			var open_page := menu.open_category()
			var visible_count := 0
			for tool in BuildMenu.categories()[open_page]["tools"]:
				if menu.card(tool).is_visible_in_tree():
					visible_count += 1
			assert_int(visible_count).is_greater(0)
			var row := menu.card(BuildMenu.categories()[open_page]["tools"][0]).get_parent()
			var next_btn := row.find_child("CardNext", true, false) as Button
			if next_btn == null or not next_btn.visible:
				break
			next_btn.pressed.emit()
			if menu.open_category() == start:
				break

	# Every visible category button on the bottom bar opens a non-empty tray.
	var checked_buttons := 0
	for i in BuildMenu.categories().size():
		if i == BuildMenu.remove_category():
			continue
		var bar_btn := menu.category_button(i)
		if not bar_btn.visible:
			continue
		bar_btn.pressed.emit()
		assert_bool(menu.is_tray_open()).is_true()
		var open_cat := menu.open_category()
		var cards_shown := 0
		for tool in BuildMenu.categories()[open_cat]["tools"]:
			if menu.card(tool).is_visible_in_tree():
				assert_int(BuildUnlocks.tier_of(tool)).is_less(DemoMode.HIDDEN_MIN_TIER)
				cards_shown += 1
		assert_int(cards_shown).is_greater(0)
		checked_buttons += 1
		menu.close_for_modal()
	assert_int(checked_buttons).is_greater_equal(17)


func test_demo_allows_one_extra_land_plot_and_refuses_second_extra_plot() -> void:
	DemoMode.set_override_for_test(true)
	var finances: Finances = auto_free(Finances.new())
	finances.wallet.credit(100000, Wallet.Category.FEES)
	add_child(finances)
	var unlocks: BuildUnlocks = auto_free(BuildUnlocks.new())
	unlocks.manual = true
	var mode: BuildMode = auto_free(BuildMode.new())
	mode.site = SITE
	mode.finances = finances
	mode.unlocks = unlocks
	mode.require_unlocks = true
	add_child(mode)
	mode.set_process(false)

	var land := mode.land_tool.land
	var start_owned := land.owned_plots().size()
	mode.set_tool(BuildMode.Tool.BUY_LAND)
	assert_int(land.buyable_plots().size()).is_greater(0)
	assert_object(mode.land_tool.fill_mesh()).is_not_null()

	var first := mode.apply_at(_plot_middle(mode, FIRST_EXTRA_PLOT))
	assert_bool(first.ok).is_true()
	assert_int(land.bought).is_equal(1)
	assert_int(land.owned_plots().size()).is_equal(start_owned + 1)

	# Now at start + 1 extra plot: no buyable fills, red hover, demo limit text, click refused.
	assert_array(land.buyable_plots()).is_empty()
	assert_object(mode.land_tool.fill_mesh()).is_null()
	var hover_status := mode.land_tool.hover(_plot_middle(mode, SECOND_EXTRA_PLOT))
	assert_str(hover_status).is_equal(LandPlots.DEMO_LIMIT_TEXT)
	assert_bool(mode.land_tool.price_label().visible).is_true()
	assert_str(mode.land_tool.price_label().text).is_equal("In the full game")
	assert_vector(mode.land_tool.preview_price()).is_equal(Vector2i.ZERO)
	var hover_mesh := mode.land_tool.get_node("HoverPlot") as MeshInstance3D
	assert_bool(hover_mesh.visible).is_true()
	assert_object((hover_mesh.material_override as StandardMaterial3D).albedo_color).is_equal(
		BuildMode.INVALID_TINT
	)

	var balance_before := finances.wallet.balance
	var second := mode.apply_at(_plot_middle(mode, SECOND_EXTRA_PLOT))
	assert_bool(second.ok).is_false()
	assert_int(second.reason).is_equal(BuildResult.Reason.LOCKED)
	assert_bool(land.is_owned(SECOND_EXTRA_PLOT)).is_false()
	assert_int(land.bought).is_equal(1)
	assert_int(finances.wallet.balance).is_equal(balance_before)


func test_demo_incident_catalogue_permits_spill_fault_and_rush_only() -> void:
	DemoMode.set_override_for_test(true)
	var world := {"tier": 3, "places": 4, "faults": 2, "contracts": 2}
	var candidates := IncidentCatalogue.candidates(world)
	var kinds := candidates.map(func(c: Dictionary) -> String: return c["kind"])
	(
		assert_array(kinds)
		. contains_exactly(
			[
				IncidentCatalogue.NONE,
				IncidentCatalogue.SPILL,
				IncidentCatalogue.RUSH,
				IncidentCatalogue.FAULT,
			]
		)
	)

	var counts := {}
	var window := Vector2i(1000, 5000)
	for day in range(1, 201):
		var draws := IncidentRoll.stream(424242, day, IncidentCatalogue.VERSION, "roll")
		var rolled := IncidentRoll.roll(draws, candidates, day, 0, window)
		var kind: String = rolled["kind"]
		counts[kind] = int(counts.get(kind, 0)) + 1
	assert_int(int(counts.get(IncidentCatalogue.SPILL, 0))).is_greater(0)
	assert_int(int(counts.get(IncidentCatalogue.FAULT, 0))).is_greater(0)
	assert_int(int(counts.get(IncidentCatalogue.RUSH, 0))).is_greater(0)
	assert_int(int(counts.get(IncidentCatalogue.INSPECTOR, 0))).is_equal(0)
	assert_int(int(counts.get(IncidentCatalogue.VIP, 0))).is_equal(0)
	assert_int(int(counts.get(IncidentCatalogue.FAVOUR, 0))).is_equal(0)


func test_demo_end_card_pauses_synchronously_on_day5_rollover_and_handles_buttons() -> void:
	DemoMode.set_override_for_test(true)
	var port: SubViewport = auto_free(SubViewport.new())
	port.size = Vector2i(1920, 1080)
	add_child(port)
	var clock: SimClock = auto_free(SimClock.new())
	port.add_child(clock)
	var finances: Finances = auto_free(Finances.new())
	finances.clock = clock
	port.add_child(finances)
	var rating: AirportRating = auto_free(AirportRating.new())
	port.add_child(rating)
	var pax: PassengerSim = auto_free(PassengerSim.new())
	var unlocks: BuildUnlocks = auto_free(BuildUnlocks.new())
	unlocks.rating = rating
	unlocks.passengers = pax
	unlocks.manual = true
	port.add_child(unlocks)
	var mode: BuildMode = auto_free(BuildMode.new())
	mode.grid_size = Vector2i(20, 20)
	mode.initial_tool = BuildMode.Tool.NONE
	mode.unlocks = unlocks
	mode.require_unlocks = true
	port.add_child(mode)
	mode.set_process(false)
	var menu: BuildMenu = auto_free(BuildMenu.new())
	menu.build_mode = mode
	menu.clock = clock
	port.add_child(menu)

	var end_card: DemoEndCard = auto_free(DemoEndCard.new())
	end_card.clock = clock
	end_card.rating = rating
	end_card.unlocks = unlocks
	end_card.finances = finances
	end_card.build_mode = mode
	end_card.build_menu = menu
	var opened_urls: Array[String] = []
	var title_returns := [0]
	end_card.url_opener = func(url: String) -> void: opened_urls.append(url)
	end_card.back_to_title = func() -> void: title_returns[0] += 1
	port.add_child(end_card)

	for i in 80:
		rating.record_passenger(0, true, PassengerSim.MOOD_MAX)
	for i in 125:
		pax.outcome.emit(i, true)
	finances.wallet.credit(4200, Wallet.Category.FEES)

	# Open a build tray, then yield to player at 3x across the Day 5 -> Day 6 boundary.
	menu.press_category(0)
	assert_bool(menu.is_tray_open()).is_true()
	var rollover := GameCalendar.day_start(DemoMode.MAX_DEMO_DAY, clock.epoch)
	clock.tick = rollover - 3
	clock.set_speed(3)
	clock.set_paused(false)
	# Owes 9 ticks at 3x, but must stop synchronously on step 3 (rollover) per 6cee6cfb.
	clock.advance(SimClock.STEP * 3.0)
	assert_bool(end_card.is_open()).is_true()
	assert_int(clock.tick).is_equal(rollover)
	assert_bool(clock.paused).is_true()
	assert_bool(menu.is_tray_open()).is_false()
	assert_int(mode.tool).is_equal(BuildMode.Tool.NONE)

	# Player unpause cannot override the non-yielding hold.
	clock.set_paused(false)
	assert_bool(clock.paused).is_true()
	clock.advance(SimClock.STEP * 5.0)
	assert_int(clock.tick).is_equal(rollover)

	var stats := end_card.summary_stats()
	assert_int(stats["passengers_made"]).is_equal(125)
	assert_float(stats["stars"]).is_greater_equal(4.5)
	assert_int(stats["cash_earned"]).is_equal(4200)
	assert_int(stats["balance"]).is_equal(PriceTable.STARTING_BUDGET + 4200)
	var title := end_card.panel().find_child("Title", true, false) as Label
	var body := end_card.panel().find_child("Body", true, false) as Label
	assert_str(title.text).is_equal(DemoEndCard.TITLE_TEXT)
	assert_str(body.text).is_equal(DemoEndCard.BODY_TEXT)

	end_card.wishlist_button().pressed.emit()
	assert_array(opened_urls).is_equal([DemoMode.STEAM_STORE_URL])
	assert_bool(end_card.is_open()).is_true()

	end_card.back_button().pressed.emit()
	await await_idle_frame()
	assert_int(title_returns[0]).is_equal(1)
	assert_bool(end_card.is_open()).is_false()
	assert_bool(clock.holds.is_holding()).is_false()


func test_main_scene_day6_autosave_and_reload_re_shows_demo_end_card_paused() -> void:
	DemoMode.set_override_for_test(true)
	SaveSlots.dir = _slots_dir
	var main: Node = auto_free(SaveTestKit.boot(self, 424242))
	var clock := main.get_node("SimClock") as SimClock
	var flights := main.get_node("FlightSim") as FlightSim
	var hud := main.get_node("PassengerHud") as PassengerHud
	var unlocks := main.get_node("BuildUnlocks") as BuildUnlocks
	var save_game := SaveTestKit.save_game(main)

	hud.press_starter_terminal()
	flights.opened_tick = clock.tick
	clock.start_calendar()
	SaveTestKit.step(main)
	for _i in 40:
		unlocks.note_made()
	var day1_path := _temp_save("day1_save")
	assert_bool(save_game.save_to_file(day1_path)).is_true()

	var rollover := GameCalendar.day_start(DemoMode.MAX_DEMO_DAY, clock.epoch)
	clock.tick = rollover - 2
	clock.set_speed(3)
	clock.set_paused(false)
	clock.advance(SimClock.STEP * 2.0)

	assert_bool(hud.demo_end_card.is_open()).is_true()
	assert_int(clock.tick).is_equal(rollover)
	assert_bool(clock.paused).is_true()
	assert_str(save_game.autosave_pending).is_not_empty()
	var autosave_path := save_game.autosave_pending
	assert_bool(save_game.retry_autosave()).is_true()
	assert_bool(FileAccess.file_exists(autosave_path)).is_true()

	# Loading Day 1 closes DemoEndCard; loading the Day-6 autosave re-shows it paused.
	assert_bool(save_game.load_from_file(day1_path)).is_true()
	assert_bool(hud.demo_end_card.is_open()).is_false()

	assert_bool(save_game.load_from_file(autosave_path)).is_true()
	assert_bool(hud.demo_end_card.is_open()).is_true()
	assert_bool(clock.paused).is_true()
	assert_int(hud.demo_end_card.summary_stats()["passengers_made"]).is_greater_equal(40)
	clock.set_paused(false)
	clock.advance(SimClock.STEP * 4.0)
	assert_int(clock.tick).is_equal(rollover)


func test_demo_end_card_preempts_open_take_turn_dialogs_and_build_tray_on_rollover() -> void:
	DemoMode.set_override_for_test(true)
	SaveSlots.dir = _slots_dir
	var main: Node = auto_free(SaveTestKit.boot(self, 777777))
	var clock := main.get_node("SimClock") as SimClock
	var flights := main.get_node("FlightSim") as FlightSim
	var hud := main.get_node("PassengerHud") as PassengerHud
	var menu := main.get_node("BuildMenu") as BuildMenu
	var offer_panel := main.get_node("OfferPanel") as OfferPanel
	var game_menu := main.get_node("GameMenu") as GameMenu
	var guide := hud.unlock_guide()
	guide.mode = UnlockGuide.Mode.PROFILE

	hud.press_starter_terminal()
	flights.opened_tick = clock.tick
	clock.start_calendar()
	var rollover := GameCalendar.day_start(DemoMode.MAX_DEMO_DAY, clock.epoch)

	# Part 1: BuildSession + OfferPanel yielding tokens yield to HUD 3x (leaving
	# OfferPanel's exclusive turn open) and SimClock.advance preempts it on rollover.
	menu.press_category(BuildMenu.category_of(BuildMode.Tool.SURFACE_LOT))
	menu.build_session.sync()
	assert_bool(clock.paused).is_true()
	hud.press_speed(3)
	menu.build_session.sync()
	assert_bool(clock.paused).is_false()
	offer_panel.open()
	assert_bool(clock.paused).is_true()
	hud.press_speed(3)
	assert_bool(offer_panel.is_open()).is_true()
	assert_bool(clock.paused).is_false()
	clock.tick = rollover - 2
	# Owes 3 steps at 3x (rollover - 1, rollover, rollover + 1); stops on rollover!
	clock.advance(SimClock.STEP)
	assert_bool(hud.demo_end_card.is_open()).is_true()
	assert_int(clock.tick).is_equal(rollover)
	assert_bool(clock.paused).is_true()
	assert_bool(offer_panel.is_open()).is_false()
	assert_bool(menu.is_tray_open()).is_false()
	hud.demo_end_card.close()
	hud.demo_end_card._triggered = false
	clock.set_paused(true)
	await await_idle_frame()

	# Part 2: UnlockGuide holds the active exclusive take_turn dialog, GameMenu is
	# queued behind it, and a BuildMenu tray is open when Day 6 rollover fires.
	guide.open_dialog([2])
	assert_bool(guide.is_open()).is_true()
	assert_bool(game_menu.open()).is_true()
	assert_bool(game_menu.has_hold()).is_true()
	menu.press_category(0)
	menu.build_session.sync()
	assert_bool(menu.is_tray_open()).is_true()
	assert_int(hud._camera_gates).is_equal(1)

	hud.demo_end_card.on_tick(rollover)
	await await_idle_frame()

	assert_bool(hud.demo_end_card.is_open()).is_true()
	assert_bool(clock.paused).is_true()
	assert_bool(guide.is_open()).is_false()
	assert_bool(game_menu.is_open()).is_false()
	assert_bool(game_menu.has_hold()).is_false()
	assert_bool(menu.is_tray_open()).is_false()
	assert_int(hud._camera_gates).is_equal(1)

	var title_returns := [0]
	hud.demo_end_card.back_to_title = func() -> void: title_returns[0] += 1
	hud.demo_end_card.back_button().pressed.emit()
	await await_idle_frame()
	assert_int(title_returns[0]).is_equal(1)
	assert_int(hud._camera_gates).is_equal(0)
	assert_bool(clock.holds.is_holding()).is_false()
