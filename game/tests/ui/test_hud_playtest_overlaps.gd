class_name TestHudPlaytestOverlaps
extends GdUnitTestSuite
## Regression tests for the 4 HUD layout/rendering bugs from the 1.0 playtest:
## 1. CertificationDrawer height overflow & PlannerToggle horizontal overlap.
## 2. StaffCard vertical stretch & Runway overlap.
## 3. RoomPanel covered by LeftColumn / PlannerToggle / StaffHintCard.
## 4a. RatingBadge StarRow gold fill visibility at 4.5 rating.
## 4b. OfferPanel bottom clearance above CategoryBar & horizontal clearance of PlannerToggle.

const SEED := 4_070_093
const LAYOUTS := [Vector2i(1536, 864), Vector2i(1280, 720)]

var _port: SubViewport
var _main: Node
var _departures: Button
var _departures_text := ""
var _alert_path := SaveTestKit.run_path("hud_playtest_overlaps_alerts")
var _departures_path := SaveTestKit.run_path("hud_playtest_overlaps_departures")
var _mood_path := SaveTestKit.run_path("hud_playtest_overlaps_mood")


func before() -> void:
	_port = SubViewport.new()
	_port.size = LAYOUTS[0]
	add_child(_port)
	_main = load(SaveTestKit.MAIN).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(SEED)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	(_main.get_node("PassengerHud") as PassengerHud).alert_settings_path = _alert_path
	(_main.get_node("PassengerHud") as PassengerHud).departures_settings_path = _departures_path
	(_main.get_node("MoodOverlay") as MoodOverlay).settings_path = _mood_path
	_port.add_child(_main)
	_departures = _main.find_child("DeparturesToggle", true, false) as Button
	_departures_text = _departures.text
	await _settle()


func after() -> void:
	if _port != null:
		_port.free()
		_port = null
	_main = null
	for path in [_alert_path, _departures_path, _mood_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		if FileAccess.file_exists(path + ".tmp"):
			DirAccess.remove_absolute(path + ".tmp")


func after_test() -> void:
	if _departures != null:
		_departures.text = _departures_text
	var badge := _main.get_node("RatingBadge") as RatingBadge
	badge.close()
	var offers := _main.get_node("OfferPanel") as OfferPanel
	offers.close()
	var menu := _main.get_node("BuildMenu") as BuildMenu
	if menu.staff_open:
		menu.press_staff()
	menu.room_panel().show_room(0)
	(_main.get_node("MoodOverlay") as MoodOverlay).set_shown(false)
	_port.size = LAYOUTS[0]
	await _settle()


func _settle(frames := 4) -> void:
	for i in frames:
		await get_tree().process_frame


func test_certification_drawer_scrolls_above_category_bar_and_clears_planner() -> void:
	_departures.text = "Departures (B) · 1 today"
	var badge := _main.get_node("RatingBadge") as RatingBadge
	var planner := _main.find_child("PlannerToggle", true, false) as Control
	var bar := (_main.get_node("BuildMenu") as BuildMenu).bar()
	for layout: Vector2i in LAYOUTS:
		_port.size = layout
		badge.open()
		await _settle()
		var drawer := badge.drawer()
		assert_bool(drawer.is_visible_in_tree()).is_true()
		var scroll := drawer.find_child("CertRowsScroll", true, false) as ScrollContainer
		assert_object(scroll).is_not_null()
		var drawer_rect := drawer.get_global_rect()
		var planner_rect := planner.get_global_rect()
		var bar_rect := bar.get_global_rect()
		assert_float(drawer_rect.position.x).is_greater_equal(
			planner_rect.end.x + float(HudLayout.GAP) - 0.5
		)
		assert_bool(drawer_rect.intersects(planner_rect)).is_false()
		assert_float(drawer_rect.end.y).is_less_equal(bar_rect.position.y - BuildMenu.GAP + 0.5)
		assert_float(drawer_rect.end.y).is_less(float(layout.y))
		badge.close()
		await _settle(2)


func test_staff_card_stays_compact_and_clear_of_runway_after_hiring_and_firing() -> void:
	var menu := _main.get_node("BuildMenu") as BuildMenu
	var mode := _main.get_node("BuildMode") as BuildMode
	var sp := _main.get_node("StaffPanel") as StaffPanel
	var staff := _main.get_node("Staff") as StaffSim
	var runway := _main.find_child("RunwayButton", true, false) as Control
	var bar := menu.bar()
	var prev_unlocks := mode.require_unlocks
	mode.require_unlocks = false
	menu.press_staff()
	await _settle()
	for role in StaffPanel.ROLES:
		staff.hire(role)
	staff.hire(StaffMember.Role.CHECKIN)
	staff.hire(StaffMember.Role.CHECKIN)
	staff.hire(StaffMember.Role.SECURITY)
	for id in staff.member_ids():
		var m := staff.get_member(id)
		if m != null and StaffSim.is_role_trainable(m.role):
			staff.train(id, null)
			break
	await _settle()
	staff.fire(StaffMember.Role.CHECKIN)
	await _settle()

	for layout: Vector2i in LAYOUTS:
		_port.size = layout
		await _settle()
		var card := sp.card()
		var card_rect := card.get_global_rect()
		var runway_rect := runway.get_global_rect()
		var bar_rect := bar.get_global_rect()
		assert_bool(card.is_visible_in_tree()).is_true()
		assert_bool(card_rect.intersects(runway_rect)).is_false()
		assert_float(card_rect.position.y).is_greater_equal(TopRow.SHEET_TOP - 0.5)
		assert_float(card_rect.end.y).is_less_equal(bar_rect.position.y - BuildMenu.GAP + 0.5)
		assert_float(card_rect.size.y).is_less_equal(card.get_combined_minimum_size().y + 1.0)
		for role in StaffPanel.ROLES:
			var counts := (
				card.find_child("%sCounts" % StaffPanel.ROLE_KEYS[role], true, false) as Label
			)
			assert_object(counts).is_not_null()
			assert_float(counts.size.y).is_less(60.0)
	mode.require_unlocks = prev_unlocks


func test_room_panel_clears_left_column_planner_hint_and_mood_legend() -> void:
	var mode := _main.get_node("BuildMode") as BuildMode
	var menu := _main.get_node("BuildMenu") as BuildMenu
	var grid := mode.grid
	LandKit.own_all(grid.land)
	var edits: Array[BuildEdit] = []
	for y in range(2, 8):
		for x in range(2, 8):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(edits)
	var room_res := grid.apply(BuildEdit.place_room(Rect2i(3, 3, 4, 3), &"toilet"))
	assert_bool(room_res.ok).is_true()

	_departures.text = "Departures (B) · 1 today"
	(_main.get_node("MoodOverlay") as MoodOverlay).set_shown(true)
	mode.set_tool(BuildMode.Tool.NONE)
	menu.room_panel().show_room(room_res.room_id)
	await _settle()

	var panel := menu.room_panel()
	assert_bool(panel.is_visible_in_tree()).is_true()
	var rect := panel.get_global_rect()
	var blockers := [
		"MoneySlot",
		"RatingCard",
		"MoodToggle",
		"DeparturesToggle",
		"PlannerToggle",
		"StaffHintCard",
		"MoodLegendCard",
		"BuildModeSign",
		"RunwayButton",
		"CategoryBar",
	]
	for node_name: String in blockers:
		var ctrl := _main.find_child(node_name, true, false) as Control
		if ctrl == null or not ctrl.is_visible_in_tree():
			continue
		(
			assert_bool(rect.intersects(ctrl.get_global_rect()))
			. override_failure_message(
				"RoomPanel %s overlaps %s %s" % [rect, node_name, ctrl.get_global_rect()]
			)
			. is_false()
		)


func test_rating_badge_stars_render_4_5_with_unclipped_gold_interior() -> void:
	var rating := _main.get_node("AirportRating") as AirportRating
	var badge := _main.get_node("RatingBadge") as RatingBadge
	for i in 9:
		rating.record_passenger(10, true, 90)
	rating.record_passenger(10, false, 0)
	await _settle()
	assert_str(badge.label().text).is_equal("4.5")
	assert_array(badge.star_row().fills).is_equal([1.0, 1.0, 1.0, 1.0, 0.5])
	var shape := RatingBadge.StarRow._star(Vector2(8.0, 8.0))
	assert_int(Geometry2D.triangulate_polygon(shape).size()).is_equal(24)
	# Outer radius leaves >= 1 px margin on all sides inside STAR_SIZE so the 2 px
	# outline drawn behind the polygon frames it without swallowing the star interior.
	for pt in shape:
		assert_float(pt.x).is_greater_equal(1.0 - 0.01)
		assert_float(pt.x).is_less_equal(RatingBadge.STAR_SIZE - 1.0 + 0.01)
		assert_float(pt.y).is_greater_equal(1.0 - 0.01)
		assert_float(pt.y).is_less_equal(RatingBadge.STAR_SIZE - 1.0 + 0.01)
	var half := PackedVector2Array(
		[
			Vector2(shape[0].x - RatingBadge.STAR_SIZE, -RatingBadge.STAR_SIZE),
			Vector2(shape[0].x, -RatingBadge.STAR_SIZE),
			Vector2(shape[0].x, RatingBadge.STAR_SIZE * 2.0),
			Vector2(shape[0].x - RatingBadge.STAR_SIZE, RatingBadge.STAR_SIZE * 2.0),
		]
	)
	var pieces := Geometry2D.intersect_polygons(shape, half)
	assert_int(pieces.size()).is_equal(1)
	assert_int(Geometry2D.triangulate_polygon(pieces[0]).size()).is_greater(0)


func test_offer_panel_clears_category_bar_and_wide_planner_toggle() -> void:
	var flights := _main.get_node("FlightSim") as FlightSim
	if flights.opened_tick < 0:
		flights.open_airport()
	var desk := _main.get_node("OfferDesk") as OfferDesk
	var snap := TestOfferBoard.save_of(TestOfferBoard.day_records(0, [480, 600, 720]))
	snap["charters"] = [
		{
			"id": "CH0N1",
			"day": 0,
			FlightContract.ONE_OFF_DAY_KEY: 0,
			"cutoff_tick": 99999,
			"airline": "Sunhop",
			"destination": "Athens",
			"departure_minute": 750,
			"plane_size": PlaneClasses.SMALL,
			"booked_passengers": 6,
			"fee_per_passenger": 44,
			FlightContract.TRAITS_KEY: OfferTraits.frozen({}),
			OfferBoard.LOYAL_KEY: false,
			"status": OfferBoard.OPEN,
		}
	]
	assert_bool(desk.board.from_snapshot(snap)).is_true()

	_departures.text = "Departures (B) · 10 today · widened"
	var offer_panel := _main.get_node("OfferPanel") as OfferPanel
	var planner := _main.find_child("PlannerToggle", true, false) as Control
	var bar := (_main.get_node("BuildMenu") as BuildMenu).bar()

	for layout: Vector2i in LAYOUTS:
		_port.size = layout
		offer_panel.open()
		await _settle()
		var sheet := offer_panel.sheet()
		assert_bool(sheet.is_visible_in_tree()).is_true()
		var sheet_rect := sheet.get_global_rect()
		var bar_rect := bar.get_global_rect()
		var planner_rect := planner.get_global_rect()
		assert_float(sheet_rect.end.y).is_less_equal(bar_rect.position.y - BuildMenu.GAP + 0.5)
		assert_bool(sheet_rect.intersects(bar_rect)).is_false()
		assert_float(sheet_rect.position.x).is_greater_equal(
			planner_rect.end.x + float(HudLayout.GAP) - 0.5
		)
		assert_bool(sheet_rect.intersects(planner_rect)).is_false()
		offer_panel.close()
		await _settle(2)
