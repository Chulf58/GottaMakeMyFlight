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
	"TemplatesButton",
	"DebugToggle",
]
const IN_BUILD_MODE := ["BuildModeSign", "DebugPanel"]
## Where the rating card ends at most (16 + 224 + 8 + 240).
const RATING_END := 488.0
## The bar leaves room for the docks beside it from this layout width up
## (the 1104 px bar, its 4 px margins included, plus 144 px each side).
const WIDE_FROM := 1392.0

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


func after_test() -> void:
	if _port != null:
		_port.free()
		_port = null


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


func _enter_build_mode() -> void:
	(_main.get_node("BuildMenu") as BuildMenu).press_category(0)
	var frame := _main.find_child("BuildModeFrame", true, false) as BuildModeFrame
	assert_object(frame).is_not_null()
	frame.set_building(true)
	(_main.get_node("PassengerHud") as PassengerHud).set_debug_open(true)
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
	# The rail: RAIL_W wide on the right margin.
	assert_float(clock.size.x).is_equal_approx(float(HudLayout.RAIL_W), 0.5)
	assert_float(layout.x - clock.end.x).is_equal_approx(float(HudLayout.MARGIN), 0.5)
	# The bottom docks.
	var bar := (_main.get_node("BuildMenu") as BuildMenu).bar().get_global_rect()
	var dock := _find("TemplatesButton").get_parent_control().get_global_rect()
	var debug: Rect2 = rects["DebugToggle"]
	assert_float(dock.position.x).is_equal_approx(float(HudLayout.MARGIN), 0.5)
	assert_float(dock.size.y).is_equal_approx(float(HudLayout.BAR_H), 0.5)
	assert_float(layout.x - debug.end.x).is_equal_approx(float(HudLayout.MARGIN), 0.5)
	if layout.x >= WIDE_FROM:
		assert_float(dock.end.y).is_equal_approx(bar.end.y, 0.5)
		assert_float(layout.y - debug.end.y).is_equal_approx(float(HudLayout.MARGIN), 0.5)
	else:
		assert_float(dock.end.y).is_equal_approx(bar.position.y - HudLayout.GAP, 0.5)
		assert_float(debug.end.y).is_equal_approx(bar.position.y - HudLayout.GAP, 0.5)


## Each sheet, opened from the row, ends left of the clock panel and starts right
## of the top-left toggles.
func _assert_sheets_clear_the_clock(layout: Vector2) -> void:
	var clock := _rect(_find("FlightPanel"))
	var toggles := _rect(_find("MoodToggle"))
	for pair in [["RunwayCard", "RunwaySheet"], ["OfferPanel", "OfferSheet"]]:
		var owner_node := _main.get_node(pair[0])
		owner_node.open()
		await await_idle_frame()
		var control := _find(pair[1])
		assert_bool(control.is_visible_in_tree()).is_true()
		var sheet := _rect(control)
		owner_node.close()
		print("%s %s vs FlightPanel %s" % [pair[1], sheet, clock])
		assert_float(sheet.size.x).is_equal_approx(560.0, 0.5)
		assert_float(sheet.size.y).is_greater(0.0)
		assert_bool(Rect2(Vector2.ZERO, layout).encloses(sheet)).is_true()
		assert_float(clock.position.x - sheet.end.x).is_greater_equal(float(HudLayout.GAP) - 0.5)
		assert_float(sheet.position.x).is_greater(toggles.end.x)


func test_no_two_resting_hud_windows_overlap_at_any_ui_scale() -> void:
	for ui_scale in LAYOUTS:
		await _boot(LAYOUTS[ui_scale])
		var rects := _rects(RESTING, Vector2(LAYOUTS[ui_scale]))
		var found := _overlaps(rects)
		print("ui scale %.2f layout %s overlaps %s" % [ui_scale, LAYOUTS[ui_scale], found])
		assert_array(found).is_empty()
		_port.free()
		_port = null


func test_build_mode_keeps_the_ruled_geometry_and_overlaps_nothing_at_any_ui_scale() -> void:
	for ui_scale in LAYOUTS:
		await _boot(LAYOUTS[ui_scale])
		await _enter_build_mode()
		var layout := Vector2(LAYOUTS[ui_scale])
		var rects := _rects(RESTING + IN_BUILD_MODE, layout)
		var found := _overlaps(rects)
		print("ui scale %.2f layout %s build overlaps %s" % [ui_scale, layout, found])
		assert_array(found).is_empty()
		_assert_geometry(rects, layout)
		_port.free()
		_port = null


func test_an_open_sheet_ends_left_of_the_clock_panel_at_any_ui_scale() -> void:
	for ui_scale in LAYOUTS:
		await _boot(LAYOUTS[ui_scale])
		await _assert_sheets_clear_the_clock(Vector2(LAYOUTS[ui_scale]))
		_port.free()
		_port = null


## The size_changed connections: one world, resized through every layout and back.
func test_a_live_viewport_resize_relays_the_hud_out() -> void:
	await _boot(Vector2i(1920, 1080))
	await _enter_build_mode()
	for size in [
		Vector2i(1280, 720), Vector2i(1536, 864), Vector2i(1920, 1080), Vector2i(1280, 720)
	]:
		_port.size = size
		await await_idle_frame()
		await await_idle_frame()
		var layout := Vector2(size)
		var rects := _rects(RESTING + IN_BUILD_MODE, layout)
		var found := _overlaps(rects)
		print("resized to %s overlaps %s" % [size, found])
		assert_array(found).is_empty()
		_assert_geometry(rects, layout)
		await _assert_sheets_clear_the_clock(layout)


## A layout too narrow for a sheet beside the rail never gets a negative width.
func test_the_sheet_extent_is_never_negative_in_a_degraded_layout() -> void:
	for width in [640.0, 664.0, 700.0, 1280.0, 1536.0]:
		var extent := TopRow.sheet_extent(width)
		assert_float(extent.y).is_greater_equal(0.0)
		assert_float(extent.x).is_greater_equal(TopRow.SHEET_MIN_LEFT)
	assert_float(TopRow.sheet_extent(640.0).y).is_equal(0.0)
	assert_float(TopRow.sheet_extent(1280.0).y).is_equal(560.0)


## Board 0faf2ef4: the status card grows with Today and Tomorrow rows and pushed
## the "To open the airport" checklist down over the bar's left end and the
## Templates dock at UI scale 1.5. Two contracts are scheduled, so the departures
## list is long, and the opening checklist is still full.
func _schedule_two_contracts() -> void:
	var flights := _main.get_node("FlightSim") as FlightSim
	var board := (_main.get_node("OfferDesk") as OfferDesk).board
	SaveTestKit.start_airport(_main)
	var clock := _main.get_node("SimClock") as SimClock
	while flights.opened_tick < 0 and clock.tick < OPEN_LIMIT_TICKS:
		SaveTestKit.step(_main)
	assert_bool(flights.opened_tick >= 0).is_true()
	for offer in board.open_offers():
		if flights.contract_ids().size() < 2:
			if flights.accept_problem(OfferBoard.terms_of(offer)) == "":
				board.accept(offer["id"], flights)
	assert_int(flights.contract_ids().size()).is_equal(2)
	(_find("DeparturesBoard") as DeparturesBoard).refresh()
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


## Nothing in the left column reaches the Templates dock or the bar: each card
## ends a GAP above the dock, at every layout.
func test_the_left_column_cards_clear_the_bar_and_the_dock_with_flights_scheduled() -> void:
	for ui_scale in LAYOUTS:
		await _boot(LAYOUTS[ui_scale])
		await _schedule_two_contracts()
		var layout := Vector2(LAYOUTS[ui_scale])
		var names: Array = RESTING + ["DeparturesPanel", "StaffHintCard"]
		var rects := _rects(names, layout)
		var found := _overlaps(rects)
		var dock := _find("TemplatesButton").get_parent_control().get_global_rect()
		var panel: Rect2 = rects["DeparturesPanel"]
		var card: Rect2 = rects["StaffHintCard"]
		var staff := _main.get_node("StaffPanel") as StaffPanel
		var more := _find("ChecklistMore")
		print(
			"rows ",
			staff.checklist().rows().size(),
			(
				" ui scale %.2f list %s card %s dock %s more %s %s overlaps %s"
				% [ui_scale, panel, card, dock, more.visible, (more as Label).text, found]
			)
		)
		assert_array(found).is_empty()
		# The list is long: two contracts, a row each for today and tomorrow.
		assert_float(panel.size.y).is_greater(100.0)
		var rows := (_find("Rows") as Control).get_combined_minimum_size().y
		var shown := (_find("RowsScroll") as Control).size.y
		assert_float(card.position.y - panel.end.y).is_greater_equal(float(HudLayout.GAP) - 0.5)
		assert_float(card.end.y).is_less_equal(dock.position.y - HudLayout.GAP + 0.5)
		assert_float(panel.end.y).is_less_equal(dock.position.y - HudLayout.GAP + 0.5)
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
		_port.free()
		_port = null


func _visible_rows(card: ChecklistCard) -> int:
	var count := 0
	for row in card.rows():
		if (row as Control).visible:
			count += 1
	return count


## The first-time hint card takes the checklist card's slot (the checklist yields
## to it), so the list leaves it its own height and it ends a GAP above the dock.
func test_a_first_time_hint_card_clears_the_bar_and_the_dock_with_a_full_list() -> void:
	var memory := SaveTestKit.run_path("leftcol_hint_memory.cfg")
	for ui_scale in LAYOUTS:
		await _boot(LAYOUTS[ui_scale])
		await _schedule_two_contracts()
		var hints := Hints.new()
		hints.forced_mode = Hints.Mode.PROFILE
		hints.settings_path = memory
		hints.hud = _main.get_node("PassengerHud") as PassengerHud
		hints.scene_root = _main
		hints.reads_world = false
		hints.hud.add_child(hints)
		# The rules show a hint only on a bare floor, so the card is shown directly.
		hints._show(HintRules.TOILET)
		await await_idle_frame()
		await await_idle_frame()
		assert_bool(hints.is_showing()).is_true()
		var layout := Vector2(LAYOUTS[ui_scale])
		var rects := _rects(RESTING + ["DeparturesPanel"], layout)
		assert_bool(hints.card().is_visible_in_tree()).is_true()
		rects["HintCard"] = _rect(hints.card())
		var found := _overlaps(rects)
		var dock := _find("TemplatesButton").get_parent_control().get_global_rect()
		var panel: Rect2 = rects["DeparturesPanel"]
		var card: Rect2 = rects["HintCard"]
		print(
			(
				"ui scale %.2f hint: list %s card %s dock %s overlaps %s"
				% [ui_scale, panel, card, dock, found]
			)
		)
		assert_array(found).is_empty()
		assert_float(panel.size.y).is_greater(60.0)
		assert_float(card.position.y - panel.end.y).is_greater_equal(float(HudLayout.GAP) - 0.5)
		assert_float(card.end.y).is_less_equal(dock.position.y - HudLayout.GAP + 0.5)
		_port.free()
		_port = null
	DirAccess.remove_absolute(memory)


## The column's fits measure once and then wait for a change: an unchanged frame
## does not measure the checklist again or touch the list's scroll height.
func test_the_column_fits_are_not_recomputed_on_an_unchanged_frame() -> void:
	await _boot(LAYOUTS[1.5])
	await _schedule_two_contracts()
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
	_port.size = Vector2i(1536, 864)
	await await_idle_frame()
	await await_idle_frame()
	assert_int(checklist.fit_runs()).is_greater(runs)
	assert_int(board.scroll_sets()).is_greater(sets)
