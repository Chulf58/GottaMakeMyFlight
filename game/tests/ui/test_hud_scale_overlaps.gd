class_name TestHudScaleOverlaps
extends GdUnitTestSuite
## Board 8d9a8f13: at UI scale 1.5 the Templates button covered the first build
## bar button, Debug sat on the bar's right end and Offers overlapped the clock
## panel. The real main scene is laid out at each supported UI scale (a 1920x1080
## window divided by the scale, as the canvas_items stretch does), and again
## after a live viewport resize, and no pair of HUD buttons or panels may
## intersect, resting and in build mode with the tray and the Debug panel open
## (decision hud-grid-and-rails-one-spacing-grid-centred-top-row-right-ra).
## The geometry asserted is the ruling's, written out here and not read from
## TopRow or BottomDocks: a centred row of three equal grid-sized slots a GAP
## apart that clears the rating card and ends a GAP before the clock rail,
## the rail on the right margin, and the Templates dock and Debug toggle on the
## bar's baseline, or a GAP above the bar when it leaves no room beside it.

## UI scale 1.0, the project's 1.25 and 1.5, on a 1920x1080 window.
const LAYOUTS := {1.0: Vector2i(1920, 1080), 1.25: Vector2i(1536, 864), 1.5: Vector2i(1280, 720)}
const RESTING := [
	"MoneySlot",
	"RatingCard",
	"RunwayButton",
	"OffersButton",
	"FlightPanel",
	"MoodToggle",
	"DeparturesToggle",
	"PlannerToggle",
	"DebugToggle",
]
const IN_BUILD_MODE := ["BuildModeSign", "DebugPanel"]
## Where the rating card ends at most (16 + 136 + 8 + 200).
const RATING_END := 360.0
## Room each side of the centred bar needs for the 112 px Templates dock between
## the 16 px screen margin and the 16 px group gap (16 + 112 + 16 = 144).
const DOCK_SIDE_ROOM := 144.0

## The lines of the first checklist a new game shows (plate offer_cards_s150.png).
## Ticks the starter airport gets to open (staff walk to their stations).
const OPEN_LIMIT_TICKS := 5000
const CHECKLIST_LINES := [
	"Entrance with a way through check-in and security to an exit",
	"Check-in desk and an agent: place a desk",
	"Security scanner and an officer: place a scanner",
	"Gate desk by an exit that faces the planes",
	"Seats near the gate",
]

## The offers drawn for day 0 come from this seed, so two of them always fit.
const SEED := 4_070_093

var _port: SubViewport
var _main: Node
var _in_build_mode := false
var _clean_snap := {}
var _opened_snap := {}


func before() -> void:
	await _boot(LAYOUTS[1.0])
	var save := _main.get_node("SaveGame") as SaveGame
	_clean_snap = JSON.parse_string(JSON.stringify(save.snapshot(), "", true, true))


func after() -> void:
	if _port != null:
		_port.free()
		_port = null


func after_test() -> void:
	if _main == null or not is_instance_valid(_main):
		return
	var hud := _main.get_node("PassengerHud") as PassengerHud
	hud.set_process(true)
	var stack := hud.find_child("AlertStack", false, false) as AlertStack
	if stack != null:
		for i in 4:
			stack.drop_notice(StringName("n%d" % i))
	var follow_label := hud.find_child("FollowText", true, false) as Label
	if follow_label != null:
		follow_label.text = ""
	var follow_card := hud.find_child("FollowCard", true, false) as Control
	if follow_card != null:
		follow_card.visible = false


func _ensure_clean_world(open_airport := false) -> void:
	var flights := _main.get_node("FlightSim") as FlightSim
	if flights.opened_tick >= 0:
		var save := _main.get_node("SaveGame") as SaveGame
		assert_bool(save.load_world(_clean_snap)).is_true()
		_in_build_mode = false
		await await_idle_frame()
		await await_idle_frame()
	if open_airport and flights.opened_tick < 0:
		flights.open_airport()
		await await_idle_frame()


func _boot(size: Vector2i) -> void:
	_port = SubViewport.new()
	_port.size = size
	add_child(_port)
	_main = load(SaveTestKit.MAIN).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(SEED)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	_port.add_child(_main)
	await await_idle_frame()
	await await_idle_frame()


func _resize(size: Vector2i) -> void:
	_port.size = size
	await await_idle_frame()
	await await_idle_frame()


func _set_build_mode(active: bool) -> void:
	if active == _in_build_mode:
		return
	var menu := _main.get_node("BuildMenu") as BuildMenu
	var frame := _main.find_child("BuildModeFrame", true, false) as BuildModeFrame
	assert_object(frame).is_not_null()
	var hud := _main.get_node("PassengerHud") as PassengerHud
	if active:
		menu.press_category(0)
		frame.set_building(true)
		hud.set_debug_open(true)
	else:
		if menu.tray().is_visible_in_tree():
			menu.press_category(menu.open_category())
		frame.set_building(false)
		hud.set_debug_open(false)
	_in_build_mode = active
	await await_idle_frame()
	await await_idle_frame()


func _rect(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


func _find(node_name: String) -> Control:
	var control := _main.find_child(node_name, true, false) as Control
	assert_object(control).is_not_null()
	return control


## The rects of the named windows, the open tray and every bar button; each one
## has an area and lies inside the viewport.
func _rects(names: Array, layout: Vector2) -> Dictionary:
	var rects := {}
	for node_name in names:
		var control := _find(node_name)
		(
			assert_bool(control.is_visible_in_tree())
			. override_failure_message("%s hidden" % node_name)
			. is_true()
		)
		rects[node_name] = _rect(control)
	var menu := _main.get_node("BuildMenu") as BuildMenu
	if menu.tray().is_visible_in_tree():
		rects["Tray"] = _rect(menu.tray())
	var index := 0
	for node in menu.bar().find_children("*", "Button", true, false):
		var button := node as Button
		if button.is_visible_in_tree():
			rects["bar_button_%d" % index] = _rect(button)
			index += 1
	assert_int(index).is_greater(3)
	for key in rects:
		var rect: Rect2 = rects[key]
		assert_float(rect.size.x).is_greater(0.0)
		assert_float(rect.size.y).is_greater(0.0)
		(
			assert_bool(Rect2(Vector2.ZERO, layout).encloses(rect))
			. override_failure_message("%s %s leaves the viewport %s" % [key, rect, layout])
			. is_true()
		)
	return rects


func _overlaps(rects: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var keys := rects.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			if (rects[keys[i]] as Rect2).intersects(rects[keys[j]]):
				found.append("%s %s x %s %s" % [keys[i], rects[keys[i]], keys[j], rects[keys[j]]])
	return found


## The ruling's geometry for the rects of the build-mode state at `layout`.
func _assert_geometry(rects: Dictionary, layout: Vector2) -> void:
	var sign_r: Rect2 = rects["BuildModeSign"]
	var runway: Rect2 = rects["RunwayButton"]
	var offers: Rect2 = rects["OffersButton"]
	var rating: Rect2 = rects["RatingCard"]
	var clock: Rect2 = rects["FlightPanel"]
	# The row: three equal grid-sized slots a GAP apart, centred on the viewport.
	assert_float(sign_r.size.x).is_equal_approx(runway.size.x, 0.5)
	assert_float(offers.size.x).is_equal_approx(runway.size.x, 0.5)
	assert_float(fposmod(runway.size.x, float(HudLayout.UNIT))).is_equal_approx(0.0, 0.01)
	assert_float(runway.position.x - sign_r.end.x).is_equal_approx(float(HudLayout.GAP), 0.5)
	assert_float(offers.position.x - runway.end.x).is_equal_approx(float(HudLayout.GAP), 0.5)
	assert_float((sign_r.position.x + offers.end.x) / 2.0).is_equal_approx(layout.x / 2.0, 1.0)
	# It clears the rating card and ends a GAP before the clock panel's rail.
	assert_float(rating.end.x).is_less_equal(RATING_END)
	assert_float(sign_r.position.x - rating.end.x).is_greater_equal(float(HudLayout.GAP) - 0.5)
	assert_float(clock.position.x - offers.end.x).is_greater_equal(float(HudLayout.GAP) - 0.5)
	# At 1280, 1536 and 1920 the compact top corners leave the full TOGGLE_W (176 px)
	# per slot without squeezing down to 88 px.
	assert_float(runway.size.x).is_equal_approx(float(HudLayout.TOGGLE_W), 0.5)
	# The rail: 320 px (RAIL_W) wide on the right margin.
	assert_float(clock.size.x).is_equal_approx(320.0, 0.5)
	assert_float(clock.size.x).is_equal_approx(float(HudLayout.RAIL_W), 0.5)
	assert_float(layout.x - clock.end.x).is_equal_approx(float(HudLayout.MARGIN), 0.5)
	# The bottom docks (no TemplatesDock; Templates lives inside CategoryBar).
	assert_object(_main.find_child("TemplatesDock", true, false)).is_null()
	var bar := (_main.get_node("BuildMenu") as BuildMenu).bar().get_global_rect()
	var tbtn := _find("TemplatesButton").get_global_rect()
	assert_bool(bar.encloses(tbtn)).is_true()
	var debug: Rect2 = rects["DebugToggle"]
	assert_float(layout.x - debug.end.x).is_equal_approx(float(HudLayout.MARGIN), 0.5)
	if bar.size.x + 2.0 * DOCK_SIDE_ROOM <= layout.x:
		assert_float(debug.end.y).is_equal_approx(bar.end.y, 0.5)
		assert_float(layout.y - debug.end.y).is_equal_approx(float(HudLayout.MARGIN), 0.5)
	else:
		assert_float(debug.end.y).is_equal_approx(bar.position.y - HudLayout.GAP, 0.5)


## Each sheet, opened from the row, ends left of the clock panel and starts right
## of the entire top-left column (toggles, Planner, DeparturesPanel, StaffHintCard).
func _assert_sheets_clear_the_clock(layout: Vector2) -> void:
	var clock := _rect(_find("FlightPanel"))
	var left_end := _rect(_find("MoodToggle")).end.x
	for left_name in ["PlannerToggle", "DeparturesPanel", "StaffHintCard"]:
		var node := _main.find_child(left_name, true, false) as Control
		if node != null and node.is_visible_in_tree():
			left_end = maxf(left_end, _rect(node).end.x)
	for pair in [["RunwayCard", "RunwaySheet"], ["OfferPanel", "OfferSheet"]]:
		var owner_node := _main.get_node(pair[0])
		owner_node.open()
		await await_idle_frame()
		var control := _find(pair[1])
		assert_bool(control.is_visible_in_tree()).is_true()
		var sheet := _rect(control)
		owner_node.close()
		print("%s %s vs FlightPanel %s left_end=%.1f" % [pair[1], sheet, clock, left_end])
		if pair[1] == "RunwaySheet":
			assert_float(sheet.size.x).is_equal_approx(560.0, 0.5)
		else:
			assert_float(sheet.size.x).is_greater_equal(560.0 - 0.5)
			assert_float(sheet.size.x).is_less_equal(OfferPanel.WIDE_SHEET_W + 0.5)
		assert_float(sheet.size.y).is_greater(0.0)
		assert_bool(Rect2(Vector2.ZERO, layout).encloses(sheet)).is_true()
		assert_float(clock.position.x - sheet.end.x).is_greater_equal(float(HudLayout.GAP) - 0.5)
		assert_float(sheet.position.x).is_greater_equal(left_end + float(HudLayout.GAP) - 0.5)


func test_no_two_resting_hud_windows_overlap_at_any_ui_scale() -> void:
	await _ensure_clean_world(false)
	assert_bool(_find("OffersButton").visible).is_false()
	await _ensure_clean_world(true)
	await _set_build_mode(false)
	for ui_scale in LAYOUTS:
		await _resize(LAYOUTS[ui_scale])
		var rects := _rects(RESTING, Vector2(LAYOUTS[ui_scale]))
		var found := _overlaps(rects)
		print("ui scale %.2f layout %s overlaps %s" % [ui_scale, LAYOUTS[ui_scale], found])
		assert_array(found).is_empty()


func test_an_open_sheet_ends_left_of_the_clock_panel_at_any_ui_scale() -> void:
	await _ensure_clean_world(true)
	await _set_build_mode(false)
	for ui_scale in LAYOUTS:
		await _resize(LAYOUTS[ui_scale])
		await _assert_sheets_clear_the_clock(Vector2(LAYOUTS[ui_scale]))


func test_build_mode_keeps_the_ruled_geometry_and_overlaps_nothing_at_any_ui_scale() -> void:
	await _ensure_clean_world(true)
	await _set_build_mode(true)
	for ui_scale in LAYOUTS:
		await _resize(LAYOUTS[ui_scale])
		var layout := Vector2(LAYOUTS[ui_scale])
		var rects := _rects(RESTING + IN_BUILD_MODE, layout)
		var found := _overlaps(rects)
		print("ui scale %.2f layout %s build overlaps %s" % [ui_scale, layout, found])
		assert_array(found).is_empty()
		_assert_geometry(rects, layout)


## The size_changed connections: one world, resized through every layout and back.
func test_a_live_viewport_resize_relays_the_hud_out() -> void:
	await _ensure_clean_world(true)
	await _resize(Vector2i(1920, 1080))
	await _set_build_mode(true)
	for size in [
		Vector2i(1280, 720), Vector2i(1536, 864), Vector2i(1920, 1080), Vector2i(1280, 720)
	]:
		await _resize(size)
		var layout := Vector2(size)
		var rects := _rects(RESTING + IN_BUILD_MODE, layout)
		var found := _overlaps(rects)
		print("resized to %s overlaps %s" % [size, found])
		assert_array(found).is_empty()
		_assert_geometry(rects, layout)
		await _assert_sheets_clear_the_clock(layout)


## At 1280x720 with DebugPanel open and FollowCard showing, AlertStack clears
## DebugPanel, FollowCard has its HudTopCard cream backing, and LeftColumn
## cards clear FollowCard and CategoryBar.
func test_alert_stack_clears_debug_panel_and_follow_card_has_cream_backing() -> void:
	await _ensure_clean_world()
	await _resize(LAYOUTS[1.5])
	await _set_build_mode(true)
	var hud := _main.get_node("PassengerHud") as PassengerHud
	var stack := hud.find_child("AlertStack", false, false) as AlertStack
	for i in 4:
		var card := OfferPanel.coral_card(
			StringName("n%d" % i), "Alert %d" % i, "Detail line %d" % i
		)
		stack.post_notice(StringName("n%d" % i), card, 0.0, "Alert %d" % i, "Detail")
	var follow_label := hud.find_child("FollowText", true, false) as Label
	var follow_card := hud.find_child("FollowCard", true, false) as PanelContainer
	hud.set_process(false)
	follow_label.text = (
		"Taxi 10   Queuing for the curb   2 passengers\n" + "Flight Gotta Air Oslo   On time"
	)
	await await_idle_frame()
	await await_idle_frame()
	var debug_r := _rect(_find("DebugPanel"))
	var rail_r := stack.room_rect()
	var follow_r := _rect(follow_card)
	var menu := _main.get_node("BuildMenu") as BuildMenu
	var bar_r := menu.bar().get_global_rect()
	var tray_r := menu.tray().get_global_rect()
	var style := follow_card.get_theme_stylebox("panel") as StyleBoxFlat
	print("1280 RAIL=%s DEBUG=%s FOLLOW=%s BAR=%s" % [rail_r, debug_r, follow_r, bar_r])
	assert_object(_main.find_child("TemplatesDock", true, false)).is_null()
	assert_bool(follow_card.is_visible_in_tree()).is_true()
	assert_float(follow_r.size.x).is_less_equal(288.0 + 0.5)
	assert_float(follow_r.end.y).is_equal_approx(720.0 - float(HudLayout.MARGIN), 0.5)
	assert_float(bar_r.position.x - follow_r.end.x).is_greater_equal(
		float(HudLayout.GROUP_GAP) - 0.5
	)
	assert_float(tray_r.position.x - follow_r.end.x).is_greater_equal(
		float(HudLayout.GROUP_GAP) - 0.5
	)
	assert_object(style).is_not_null()
	assert_bool(style.bg_color.is_equal_approx(Color(0.96, 0.93, 0.86, 1.0))).is_true()
	assert_bool(rail_r.intersects(debug_r)).is_false()
	assert_float(rail_r.end.y).is_less_equal(debug_r.position.y - float(HudLayout.GROUP_GAP) + 0.5)
	assert_bool(follow_r.intersects(bar_r)).is_false()
	assert_bool(follow_r.intersects(tray_r)).is_false()
	var staff_hint := _main.find_child("StaffHintCard", true, false) as Control
	if staff_hint != null and staff_hint.is_visible_in_tree():
		var hint_r := _rect(staff_hint)
		assert_bool(hint_r.intersects(follow_r)).is_false()
		assert_float(hint_r.end.y).is_less_equal(follow_r.position.y - float(HudLayout.GAP) + 0.5)
	for i in 4:
		stack.drop_notice(StringName("n%d" % i))
	follow_label.text = ""
	follow_card.visible = false
	hud.set_process(true)
	await _set_build_mode(false)


## A layout too narrow for a sheet beside the rail never gets a negative width.
func test_the_sheet_extent_is_never_negative_in_a_degraded_layout() -> void:
	for width in [640.0, 664.0, 700.0, 1280.0, 1536.0]:
		var extent := TopRow.sheet_extent(width)
		assert_float(extent.y).is_greater_equal(0.0)
		assert_float(extent.x).is_greater_equal(TopRow.SHEET_MIN_LEFT)
	assert_float(TopRow.sheet_extent(640.0).y).is_equal(0.0)
	assert_float(TopRow.sheet_extent(1280.0).y).is_equal(560.0)


## Without TemplatesDock, bottom-left floor cards rest at MARGIN when CategoryBar
## stays clear horizontally, and lift above CategoryBar when bar width intrudes.
func test_lifted_floor_clears_bar_when_narrow_and_rests_at_margin_when_clear() -> void:
	var bar_w := 1020.0
	var layout_w := 1280.0
	# Inline ruled threshold: side = (1280 - 1020) / 2 = 130 < MARGIN + GROUP_GAP + 288 -> lifted.
	var expected_lifted := float(HudLayout.MARGIN + HudLayout.BAR_H + HudLayout.GAP)
	assert_float(BottomDocks.left_floor_bottom(layout_w, bar_w)).is_equal(expected_lifted)
	assert_float(BottomDocks.left_floor_bottom(layout_w, 500.0)).is_equal(float(HudLayout.MARGIN))


## Board 0faf2ef4: the status card grows with Today and Tomorrow rows and pushed
## the "To open the airport" checklist down over the bar's left end and the
## Templates dock at UI scale 1.5. Two contracts are scheduled, so the departures
## list is long, and the opening checklist is still full.
func _schedule_two_contracts(contract_count: int = 2, long_airline := false) -> void:
	var flights := _main.get_node("FlightSim") as FlightSim
	if flights.opened_tick < 0:
		SaveTestKit.start_airport(_main)
		var clock := _main.get_node("SimClock") as SimClock
		while flights.opened_tick < 0 and clock.tick < OPEN_LIMIT_TICKS:
			SaveTestKit.step(_main)
	assert_bool(flights.opened_tick >= 0).is_true()
	if _opened_snap.is_empty() and flights.contract_ids().is_empty():
		var save := _main.get_node("SaveGame") as SaveGame
		_opened_snap = JSON.parse_string(JSON.stringify(save.snapshot(), "", true, true))
	if (
		not _opened_snap.is_empty()
		and (
			flights.contract_ids().size() > contract_count
			or (long_airline and flights.contract_ids().size() != contract_count)
		)
	):
		var save := _main.get_node("SaveGame") as SaveGame
		assert_bool(save.load_world(_opened_snap)).is_true()
		_in_build_mode = false
		await await_idle_frame()
		await await_idle_frame()
	# Contracts the test builds, at the first quarter hours they fit, so the
	# case does not hang on which of the seed's offers happen to fit.
	var window := FlightContract.window({})
	for minute in range(window[0], window[1] + 1, OfferBoard.DEPARTURE_STEP):
		var terms := TestFlightContracts.terms("HS%d" % minute, minute)
		# A new game's runway takes small planes only (Runway R9).
		terms["plane_size"] = PlaneClasses.SMALL
		terms["booked_passengers"] = PlaneClasses.passenger_range(PlaneClasses.SMALL)[0]
		if long_airline:
			var is_last := flights.contract_ids().size() == contract_count - 1
			var suffix := " Ventures Corporation" if is_last else ""
			terms["airline"] = (
				"Trans Continental Regional Horizon International "
				+ "Intercontinental Express Airways Charter Line Global"
				+ suffix
			)
		if flights.contract_ids().size() < contract_count and flights.accept_problem(terms) == "":
			assert_bool(flights.accept_contract(terms)).is_true()
	assert_int(flights.contract_ids().size()).is_equal(contract_count)
	var board := _find("DeparturesBoard") as DeparturesBoard
	board.set_shown(true)
	board.refresh()
	await await_idle_frame()
	# The checklist as a new game shows it: the contracts need an open airport, which
	# ticks every line, so the card is given one line per need.
	var lines: Array[Dictionary] = []
	for text in CHECKLIST_LINES:
		lines.append(Checklist.line(text, false))
	(_main.get_node("StaffPanel") as StaffPanel).checklist().show_lines(
		"To open the airport", lines
	)
	await await_idle_frame()
	await await_idle_frame()


## Both StaffHintCard and HintCard stay visible below DeparturesPanel, stacking a
## GAP apart without overlapping each other, DeparturesPanel, or the bottom dock.
func test_a_first_time_hint_card_clears_the_bar_and_the_dock_with_a_full_list() -> void:
	await _set_build_mode(false)
	await _schedule_two_contracts()
	var memory := SaveTestKit.run_path("leftcol_hint_memory.cfg")
	var hints := Hints.new()
	hints.forced_mode = Hints.Mode.PROFILE
	hints.settings_path = memory
	hints.hud = _main.get_node("PassengerHud") as PassengerHud
	hints.scene_root = _main
	hints.reads_world = false
	hints.hud.add_child(hints)
	# The rules show a hint only on a bare floor, so the card is shown directly.
	hints._show(HintRules.TOILET)
	for ui_scale in [1.0, 1.25]:
		await _resize(LAYOUTS[ui_scale])
		assert_bool(hints.is_showing()).is_true()
		var layout := Vector2(LAYOUTS[ui_scale])
		var rects := _rects(RESTING + ["DeparturesPanel", "StaffHintCard"], layout)
		assert_bool(hints.card().is_visible_in_tree()).is_true()
		rects["HintCard"] = _rect(hints.card())
		var found := _overlaps(rects)
		var bar := (_main.get_node("BuildMenu") as BuildMenu).bar().get_global_rect()
		var floor_y := (
			layout.y - BottomDocks.left_floor_bottom(layout.x, bar.size.x, HudLayout.LIST_W)
		)
		var panel: Rect2 = rects["DeparturesPanel"]
		var staff: Rect2 = rects["StaffHintCard"]
		var card: Rect2 = rects["HintCard"]
		print(
			(
				"ui scale %.2f hint: list %s staff %s card %s floor_y %.1f overlaps %s"
				% [ui_scale, panel, staff, card, floor_y, found]
			)
		)
		assert_array(found).is_empty()
		assert_float(panel.size.y).is_greater(60.0)
		assert_float(staff.position.y - panel.end.y).is_greater_equal(float(HudLayout.GAP) - 0.5)
		assert_float(card.position.y - staff.end.y).is_greater_equal(float(HudLayout.GAP) - 0.5)
		assert_float(card.end.y).is_less_equal(floor_y - HudLayout.GAP + 0.5)
	hints.free()
	await await_idle_frame()
	DirAccess.remove_absolute(memory)


## Nothing in the left column reaches the Templates dock or the bar: each card
## ends a GAP above the dock, at every layout.
func test_the_left_column_cards_clear_the_bar_and_the_dock_with_flights_scheduled() -> void:
	await _set_build_mode(false)
	# Four wrapped today rows exceed the 1.5x room to exercise scrolling and folding.
	await _schedule_two_contracts(4, true)
	for ui_scale in LAYOUTS:
		await _resize(LAYOUTS[ui_scale])
		var layout := Vector2(LAYOUTS[ui_scale])
		var names: Array = RESTING + ["DeparturesPanel", "StaffHintCard"]
		var rects := _rects(names, layout)
		var found := _overlaps(rects)
		var bar := (_main.get_node("BuildMenu") as BuildMenu).bar().get_global_rect()
		var floor_y := (
			layout.y - BottomDocks.left_floor_bottom(layout.x, bar.size.x, HudLayout.LIST_W)
		)
		var panel: Rect2 = rects["DeparturesPanel"]
		var card: Rect2 = rects["StaffHintCard"]
		var staff := _main.get_node("StaffPanel") as StaffPanel
		var more := _find("ChecklistMore")
		print(
			"rows ",
			staff.checklist().rows().size(),
			(
				" ui scale %.2f list %s card %s floor_y %.1f more %s %s overlaps %s"
				% [ui_scale, panel, card, floor_y, more.visible, (more as Label).text, found]
			)
		)
		assert_array(found).is_empty()
		# The list is long: two contracts, a row each for today and tomorrow.
		assert_float(panel.size.y).is_greater(100.0)
		var rows := (_find("Rows") as Control).get_combined_minimum_size().y
		var shown := (_find("RowsScroll") as Control).size.y
		assert_float(card.position.y - panel.end.y).is_greater_equal(float(HudLayout.GAP) - 0.5)
		assert_float(card.end.y).is_less_equal(floor_y - HudLayout.GAP + 0.5)
		assert_float(panel.end.y).is_less_equal(floor_y - HudLayout.GAP + 0.5)
		# The card is on show with at least one line and its title; a short layout
		# folds the rest into "+N more", a tall one shows every line.
		assert_bool(staff.checklist().rows().size() > 0).is_true()
		assert_bool(_visible_rows(staff.checklist()) > 0).is_true()
		var folded := _visible_rows(staff.checklist()) < staff.checklist().rows().size()
		assert_bool(more.visible).is_equal(folded)
		print("rows content %.0f shown %.0f" % [rows, shown])
		if ui_scale == 1.5:
			assert_bool(folded).is_true()
			assert_float(shown).is_less(rows)
		if ui_scale == 1.0:
			assert_bool(folded).is_false()
			assert_float(shown).is_equal_approx(rows, 0.5)


func _visible_rows(card: ChecklistCard) -> int:
	var count := 0
	for row in card.rows():
		if (row as Control).visible:
			count += 1
	return count


## The column's fits measure once and then wait for a change: an unchanged frame
## does not measure the checklist again or touch the list's scroll height.
func test_the_column_fits_are_not_recomputed_on_an_unchanged_frame() -> void:
	await _set_build_mode(false)
	await _resize(LAYOUTS[1.5])
	await _schedule_two_contracts(4, true)
	var checklist := (_main.get_node("StaffPanel") as StaffPanel).checklist()
	var board := _find("DeparturesBoard") as DeparturesBoard
	await await_idle_frame()
	var runs := checklist.fit_runs()
	var sets := board.scroll_sets()
	assert_int(runs).is_greater(0)
	assert_int(sets).is_greater(0)
	for i in 3:
		await await_idle_frame()
	assert_int(checklist.fit_runs()).is_equal(runs)
	assert_int(board.scroll_sets()).is_equal(sets)
	# A change of layout is a change: both fit again.
	await _resize(Vector2i(1536, 864))
	assert_int(checklist.fit_runs()).is_greater(runs)
	assert_int(board.scroll_sets()).is_greater(sets)
