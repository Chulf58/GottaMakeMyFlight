class_name TestSandboxMode
extends GdUnitTestSuite
## Stage 3 Pillar 1: Free-Build Sandbox Mode (decision 26d799a0).
## Tests GameRules schema/validation, Wallet/Finances/RescueGrant unlimited
## funds behavior, BuildUnlocks/BuildMode/LandPlots all-unlocked behavior,
## TitleScreen Career vs Sandbox picker & DemoMode guard, and real main.tscn
## persistence, HUD Sandbox pill non-overlap, and Career/Sandbox load switching.

const SITE := preload("res://build/terminal_site.tres")
const HUD_SCALES := {
	1.0: Vector2i(1920, 1080),
	1.25: Vector2i(1536, 864),
	1.4: Vector2i(1371, 771),
	1.5: Vector2i(1280, 720),
}

var _main: Node
var _save_paths: Array[String] = []
var _slots_dir := SaveTestKit.run_dir("test_sandbox_slots")
var _slots_dir_before := ""


func before() -> void:
	_slots_dir_before = SaveSlots.dir
	DemoMode.clear_override()
	GameBoot.pending_rules = GameRules.make_sandbox(true, true)
	GameBoot.load_path = ""
	var port: SubViewport = SubViewport.new()
	port.name = "SandboxViewport"
	port.size = HUD_SCALES[1.25]
	add_child(port)
	_main = SaveTestKit.boot(port, 3_030_303)


func after() -> void:
	var port := get_node_or_null("SandboxViewport")
	if port != null:
		port.free()
	_main = null
	_cleanup_files()


func before_test() -> void:
	DemoMode.clear_override()
	GameBoot.load_path = ""
	GameBoot.pending_rules = null
	GameBoot.refusal = ""


func after_test() -> void:
	DemoMode.clear_override()
	PseudoLocale.disable()
	GameBoot.load_path = ""
	GameBoot.pending_rules = null
	GameBoot.refusal = ""
	GameBoot.clear_new_airport()
	SaveSlots.dir = _slots_dir_before


func _cleanup_files() -> void:
	for path in _save_paths:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")
	_save_paths.clear()
	if DirAccess.dir_exists_absolute(_slots_dir):
		SaveSlots.dir = _slots_dir
		for path in SaveSlots.all_paths():
			DirAccess.remove_absolute(path)
			DirAccess.remove_absolute(path + ".tmp")
		DirAccess.remove_absolute(_slots_dir)
	SaveSlots.dir = _slots_dir_before


func _temp_save(tag: String) -> String:
	var path := SaveTestKit.run_path(tag)
	_save_paths.append(path)
	return path


func test_game_rules_factories_budget_and_validation() -> void:
	var career := GameRules.career()
	assert_bool(career.is_career_mode()).is_true()
	assert_bool(career.is_sandbox()).is_false()
	assert_int(career.starting_budget()).is_equal(PriceTable.STARTING_BUDGET)

	var unlimited := GameRules.make_sandbox(true, true)
	assert_bool(unlimited.is_sandbox()).is_true()
	assert_bool(unlimited.is_career_mode()).is_false()
	assert_bool(unlimited.unlimited_funds).is_true()
	assert_bool(unlimited.unlock_all).is_true()
	assert_int(unlimited.starting_budget()).is_equal(GameRules.UNLIMITED_BUDGET)

	var budgeted := GameRules.make_sandbox(false, true)
	assert_bool(budgeted.is_sandbox()).is_true()
	assert_bool(budgeted.unlimited_funds).is_false()
	assert_int(budgeted.starting_budget()).is_equal(GameRules.SANDBOX_BUDGET)
	assert_int(budgeted.starting_budget()).is_equal(250_000)

	var round_tripped := GameRules.new()
	assert_bool(round_tripped.from_save_dict(budgeted.to_save_dict())).is_true()
	assert_bool(round_tripped.is_sandbox()).is_true()
	assert_bool(round_tripped.unlimited_funds).is_false()
	assert_bool(round_tripped.unlock_all).is_true()

	for bad in [
		"not a dict",
		{},
		{"save_version": 2, "sandbox": false, "unlimited_funds": false, "unlock_all": false},
		{
			"save_version": 1,
			"sandbox": false,
			"unlimited_funds": false,
			"unlock_all": false,
			"extra": 1,
		},
		{"save_version": 1, "sandbox": "yes", "unlimited_funds": false, "unlock_all": false},
		{"save_version": 1, "sandbox": false, "unlimited_funds": true, "unlock_all": false},
		{"save_version": 1, "sandbox": false, "unlimited_funds": false, "unlock_all": true},
	]:
		assert_str(GameRules.validation_problem(bad)).is_not_empty()


func test_wallet_and_finances_enforce_unlimited_and_budgeted_sandbox() -> void:
	var w: Wallet = auto_free(Wallet.new(0))
	w.unlimited_funds = true
	var unpaid: Array[int] = []
	w.unpaid.connect(func(amt: int, _cat: int, _tick: int) -> void: unpaid.append(amt))
	assert_bool(w.can_afford(500_000)).is_true()
	assert_bool(w.spend(500_000, Wallet.Category.BUILD)).is_true()
	assert_int(w.balance).is_equal(0)
	assert_int(w.charge(90_000, Wallet.Category.FINES)).is_equal(90_000)
	assert_array(unpaid).is_empty()
	assert_bool(w.credit(25_000, Wallet.Category.FEES)).is_true()
	assert_int(w.balance).is_equal(0)

	var f_career: Finances = auto_free(Finances.new())
	assert_bool(f_career.start_new_game(GameRules.career())).is_true()
	assert_int(f_career.wallet.balance).is_equal(PriceTable.STARTING_BUDGET)
	assert_bool(f_career.wallet.unlimited_funds).is_false()

	var f_budget: Finances = auto_free(Finances.new())
	assert_bool(f_budget.start_new_game(GameRules.make_sandbox(false, true))).is_true()
	assert_int(f_budget.wallet.balance).is_equal(250_000)
	assert_bool(f_budget.wallet.unlimited_funds).is_false()

	var f_unlimited: Finances = auto_free(Finances.new())
	assert_bool(f_unlimited.start_new_game(GameRules.make_sandbox(true, true))).is_true()
	assert_bool(f_unlimited.wallet.unlimited_funds).is_true()
	assert_int(f_unlimited.wallet.balance).is_equal(GameRules.UNLIMITED_BUDGET)


func test_rescue_grant_skipped_under_unlimited_funds() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	var ids := ReferenceTerminal.object_ids(grid)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(100_000))
	world.sim.wallet.unlimited_funds = true
	var grant: RescueGrant = auto_free(RescueGrant.new())
	grant.bind(world.clock, world.sim, world.sim.wallet)
	var granted := []
	grant.granted.connect(func(amt: int, msg: String) -> void: granted.append([amt, msg]))

	for id in ids["scanners"]:
		assert_bool(world.grid.apply(BuildEdit.remove_object(id)).ok).is_true()
	assert_bool(grant.is_disabled()).is_true()
	assert_bool(grant.evaluate()).is_false()
	world.run_to(40)
	assert_array(granted).is_empty()
	assert_int(grant.plans_made).is_equal(0)
	world.free_all()


func test_unlock_all_opens_all_tiers_runway_and_land_plots() -> void:
	var rating: AirportRating = auto_free(AirportRating.new())
	var pax: PassengerSim = auto_free(PassengerSim.new())
	var unlocks: BuildUnlocks = auto_free(BuildUnlocks.new())
	unlocks.rating = rating
	unlocks.passengers = pax
	unlocks.manual = true
	add_child(unlocks)
	unlocks.set_unlock_all(true)

	assert_int(unlocks.tier()).is_equal(BuildUnlocks.TIERS.size())
	assert_bool(unlocks.cafe_open()).is_true()
	assert_bool(pax.cafes.hunger_enabled).is_true()
	assert_bool(unlocks.allows(BuildMode.Tool.MULTI_STOREY)).is_true()
	assert_bool(unlocks.tool_seen(BuildMode.Tool.MULTI_STOREY)).is_true()
	assert_bool(unlocks.dialog_shown(2)).is_true()

	var flights: FlightSim = auto_free(FlightSim.new())
	flights.runway.size = PlaneClasses.SMALL
	var wallet: Wallet = auto_free(Wallet.new(500_000))
	assert_str(RunwayWorks.problem(flights, unlocks, wallet)).is_empty()

	var land := LandPlots.for_site(SITE)
	land.own_all()
	assert_int(land.owned_plots().size()).is_equal(land.plots.x * land.plots.y)
	assert_int(land.bought).is_equal(0)
	assert_str(LandPlots.problem(land.to_snapshot(), SITE, true)).is_empty()


func test_title_screen_mode_picker_and_demo_guard() -> void:
	var port: SubViewport = auto_free(SubViewport.new())
	port.size = Vector2i(1920, 1080)
	add_child(port)
	var scenes: Array[String] = []
	var title := TitleScreen.new()
	title.change_scene = func(scene: String) -> Error:
		scenes.append(scene)
		return OK
	port.add_child(title)

	title.button("NewAirport").pressed.emit()
	assert_bool(title.mode_page().visible).is_true()
	assert_bool(title.selected_rules().is_career_mode()).is_true()
	assert_bool(title.button("SandboxMode").disabled).is_false()

	title.button("SandboxMode").pressed.emit()
	assert_bool(title.selected_rules().is_sandbox()).is_true()
	assert_bool(title.selected_rules().unlimited_funds).is_true()
	assert_bool(title.selected_rules().unlock_all).is_true()

	var unlimited_check := (
		title.mode_page().find_child("UnlimitedFunds", true, false) as CheckButton
	)
	unlimited_check.button_pressed = false
	var rules := title.selected_rules()
	assert_bool(rules.is_sandbox()).is_true()
	assert_bool(rules.unlimited_funds).is_false()
	assert_int(rules.starting_budget()).is_equal(250_000)
	assert_str((title.mode_page().find_child("BudgetNote", true, false) as Label).text).contains(
		"$250,000"
	)

	title.button("StartAirport").pressed.emit()
	assert_array(scenes).is_equal([GameBoot.MAIN_SCENE])
	assert_bool(GameBoot.pending_rules.is_sandbox()).is_true()
	assert_bool(GameBoot.pending_rules.unlimited_funds).is_false()

	DemoMode.set_override_for_test(true)
	title.refresh()
	var sandbox_btn := title.button("SandboxMode")
	assert_bool(sandbox_btn.disabled).is_true()
	assert_str(sandbox_btn.tooltip_text).is_equal("In the full game")
	var demo_note := title.mode_page().find_child("SandboxDemoNote", true, false) as Label
	assert_bool(demo_note.visible).is_true()
	assert_str(demo_note.text).is_equal("In the full game")
	title.select_sandbox()
	assert_bool(title.selected_rules().is_career_mode()).is_true()
	assert_bool(GameRules.effective(GameRules.make_sandbox(true, true)).is_career_mode()).is_true()


func test_main_scene_sandbox_hud_systems_save_round_trip_and_save_list() -> void:
	var save_game := SaveTestKit.save_game(_main)
	var finances := _main.get_node("Finances") as Finances
	var mode := _main.get_node("BuildMode") as BuildMode
	var menu := _main.get_node("BuildMenu") as BuildMenu
	var unlocks := _main.get_node("BuildUnlocks") as BuildUnlocks
	var settlement := _main.get_node("Settlement") as Settlement
	var rating := _main.get_node("AirportRating") as AirportRating
	var offer_desk := _main.get_node("OfferDesk") as OfferDesk
	var staff := _main.get_node("Staff") as StaffSim
	var clock := _main.get_node("SimClock") as SimClock

	assert_bool(save_game.is_sandbox()).is_true()
	assert_bool(save_game.is_career_mode()).is_false()
	assert_bool(finances.wallet.unlimited_funds).is_true()
	assert_str(menu.money_label().text).is_equal("∞")
	assert_bool(mode.require_unlocks).is_false()
	assert_int(mode.land_tool.land.owned_plots().size()).is_equal(
		mode.land_tool.land.plots.x * mode.land_tool.land.plots.y
	)
	mode.set_tool(BuildMode.Tool.MULTI_STOREY)
	assert_int(mode.tool).is_equal(BuildMode.Tool.MULTI_STOREY)
	mode.set_tool(BuildMode.Tool.NONE)

	var pill := save_game.sandbox_pill()
	assert_object(pill).is_not_null()
	assert_bool(pill.visible).is_true()
	assert_str((pill.find_child("SandboxLabel", true, false) as Label).text).is_equal("Sandbox")

	# Verify SandboxPill clears every resting/build HUD element across 1.0/1.25/1.4/1.5 scales.
	var port := _main.get_parent() as SubViewport
	for ui_scale in HUD_SCALES:
		port.size = HUD_SCALES[ui_scale]
		await await_idle_frame()
		await await_idle_frame()
		var pill_rect := pill.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, pill.size)
		assert_bool(Rect2(Vector2.ZERO, Vector2(port.size)).encloses(pill_rect)).is_true()
		for hud_name in [
			"MoneySlot",
			"RatingCard",
			"RunwayButton",
			"FlightPanel",
			"MoodToggle",
			"DeparturesToggle",
			"PlannerToggle",
			"DebugToggle",
		]:
			var ctrl := _main.find_child(hud_name, true, false) as Control
			var ctrl_rect := (
				ctrl.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, ctrl.size)
			)
			(
				assert_bool(pill_rect.intersects(ctrl_rect))
				. override_failure_message(
					(
						"SandboxPill %s overlaps %s %s at scale %s"
						% [pill_rect, hud_name, ctrl_rect, ui_scale]
					)
				)
				. is_false()
			)

	# Rating and OfferBoard stay active in Sandbox; midnight wages leave 0 owed debt.
	assert_int(offer_desk.board.open_offers().size()).is_greater(0)
	rating.record_passenger(0, true, PassengerSim.MOOD_MAX)
	assert_bool(rating.has_data()).is_true()
	staff.hire(StaffMember.Role.CHECKIN)
	clock.tick = GameCalendar.day_start(1, clock.epoch) - 2
	SaveTestKit.step(_main)
	SaveTestKit.step(_main)
	assert_int(settlement.wages_owed()).is_equal(0)
	assert_int(settlement.upkeep_owed()).is_equal(0)

	# Save v37 round-trip + SaveList "(Sandbox)" tagging + Career/Sandbox switch + corrupt rejection.
	SaveSlots.dir = _slots_dir
	DirAccess.make_dir_recursive_absolute(_slots_dir)
	var sandbox_path := SaveSlots.manual_path()
	assert_bool(save_game.save_to_file(sandbox_path)).is_true()
	assert_bool(GameRules.save_is_sandbox(sandbox_path)).is_true()

	var list := auto_free(SaveList.new()) as SaveList
	list.fill(SaveSlots.all_paths(), SaveSlots.manual_path())
	assert_str(list.button_for(sandbox_path).text).contains("(Sandbox)")

	# Corrupt "rules" is rejected whole and changes nothing.
	var bad_snap: Dictionary = JSON.parse_string(
		JSON.stringify(save_game.snapshot(), "", true, true)
	)
	bad_snap["rules"]["sandbox"] = false
	bad_snap["rules"]["unlimited_funds"] = true
	assert_bool(save_game.load_world(bad_snap)).is_false()
	assert_bool(save_game.is_sandbox()).is_true()

	# DemoMode refuses loading a Sandbox save.
	DemoMode.set_override_for_test(true)
	assert_bool(save_game.load_from_file(sandbox_path)).is_false()
	DemoMode.clear_override()

	# Switching to Career rules and loading back into Sandbox restores every flag cleanly.
	save_game.apply_rules(GameRules.career(), false)
	assert_bool(save_game.is_career_mode()).is_true()
	assert_bool(mode.require_unlocks).is_true()
	assert_bool(finances.wallet.unlimited_funds).is_false()
	assert_bool(pill.visible).is_false()
	assert_str(menu.money_label().text).is_not_equal("∞")
	assert_int(unlocks.tier()).is_equal(1)

	assert_bool(save_game.load_from_file(sandbox_path)).is_true()
	assert_bool(save_game.is_sandbox()).is_true()
	assert_bool(mode.require_unlocks).is_false()
	assert_bool(finances.wallet.unlimited_funds).is_true()
	assert_bool(pill.visible).is_true()
	assert_str(menu.money_label().text).is_equal("∞")
