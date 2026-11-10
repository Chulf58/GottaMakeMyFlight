class_name TestBannerTopCentre
extends GdUnitTestSuite
## On the real main scene, the status banner and the first-time hint sit in the
## top-left column (decision checklist-card-moves-to-the-top-left-column-slim-
## at-304-px-t, which moved them from the top centre): on the margin, LIST_W
## wide, under the toggles, clear of the top HUD controls, and the alert rail
## never meets them. (The file keeps its name; the column's own layout is in
## test_left_column.) A 1920x1080 and a 1280x720 window have the
## same layout: canvas_items stretch over a 1920x1080 base at scale 1.25 gives
## 1536x864 layout pixels for any 16:9 window, and aspect expand never goes
## narrower than 1536 across. So the layout is checked once, at that size.

const SEED := 6_103_311
## The layout width of a 16:9 window (the headless test window is not 16:9, so
## only the width is held).
const LAYOUT_W := 1536.0
## Controls the banner must clear. A name that is not showing is skipped.
const TOP_CONTROLS: Array[String] = [
	"MoneySlot",
	"RatingCard",
	"OffersButton",
	"FlightPanel",
	"AlertHistoryButton",
	"MoodToggle",
	"DeparturesToggle",
	"BuildModeSign",
]
## The top band: the banner's top edge is within this share of a 16:9 screen's
## height (the headless window is not 16:9, so the width gives the height).
const TOP_BAND := 0.35

var _settings_path := SaveTestKit.run_path("banner_top_alerts")
var _hints_path := SaveTestKit.run_path("banner_top_hints")

var _main: Node
var _hud: PassengerHud
var _menu: BuildMenu
var _staff: StaffPanel
var _stack: AlertStack
var _sim: PassengerSim


func before() -> void:
	_main = load(SaveTestKit.MAIN).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(SEED)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	(_main.get_node("PassengerHud") as PassengerHud).alert_settings_path = _settings_path
	add_child(_main)
	_hud = _main.get_node("PassengerHud")
	_menu = _main.get_node("BuildMenu")
	_staff = _main.get_node("StaffPanel")
	_sim = _main.get_node("PassengerSim")
	_stack = _hud.find_child("AlertStack", false, false) as AlertStack


func after() -> void:
	_main.free()
	DirAccess.remove_absolute(_settings_path)
	DirAccess.remove_absolute(_hints_path)
	DirAccess.remove_absolute(_hints_path + ".tmp")


func before_test() -> void:
	if _menu.is_tray_open():
		_menu.press_category(_menu.open_category())
	_staff.set_hint_yielded(false)
	for id in _sim.messes.mess_ids():
		_sim.messes.clean(id)


## Waits for the HUD to lay out.
func _settle() -> void:
	for i in 4:
		await get_tree().process_frame
	_hud.refresh()
	await get_tree().process_frame


func _view() -> Vector2:
	return get_viewport().get_visible_rect().size


func _control(node_name: String) -> Control:
	return _main.find_child(node_name, true, false) as Control


## Asserts `banner` is in the top-left column slot and clear of every top
## control and alert card that shows; prints the rectangles it compared.
func _assert_in_column(label: String, banner: Rect2) -> void:
	var view := _view()
	print("BANNER %s view=%s rect=%s" % [label, view, banner])
	assert_bool(banner.has_area()).is_true()
	assert_float(banner.position.x).is_equal_approx(HudLayout.MARGIN, 1.0)
	assert_float(banner.size.x).is_equal_approx(HudLayout.LIST_W, 1.0)
	assert_float(banner.position.y).is_greater_equal(LeftColumn.LIST_TOP - 1.0)
	# Changed for HUD 7/7 (board 3bd42402): the Reset hints row joined the column,
	# so the card starts 48 px lower, past the old top-centre band (TOP_BAND, a
	# 302 px line). The ruling (checklist-card-moves-to-the-top-left-column-slim-
	# at-304-px-t) puts the card under the column, so this pins that exact slot.
	assert_float(banner.position.y).is_equal_approx(LeftColumn.card_top(_main.get_tree()), 1.0)
	assert_bool(Rect2(Vector2.ZERO, view).encloses(banner)).is_true()
	var others: Array[Control] = []
	for node_name in TOP_CONTROLS:
		others.append(_control(node_name))
	for key in _stack.card_keys():
		others.append(_stack.card_node(key))
	for other in others:
		if other == null or not other.is_visible_in_tree():
			continue
		var rect := other.get_global_rect()
		print("  vs %s %s" % [other.name, rect])
		(
			assert_bool(banner.intersects(rect))
			. override_failure_message("%s %s overlaps %s %s" % [label, banner, other.name, rect])
			. is_false()
		)


## A first-time hint showing on the HUD, holding the banner's slot.
func _showing_hint() -> Hints:
	var hints := Hints.new()
	hints.forced_mode = Hints.Mode.PROFILE
	hints.settings_path = _hints_path
	hints.hud = _hud
	hints.scene_root = _main
	_hud.add_child(hints)
	auto_free(hints)
	hints._process(0.0)
	hints.advance(Hints.GRACE_S + 0.1, HintRules.read_world(_sim, []), [])
	for i in 8:
		hints.advance(0.25, HintRules.read_world(_sim, []), ["Check-in"])
	assert_bool(hints.is_showing()).is_true()
	return hints


func test_the_layout_is_the_one_both_window_sizes_get() -> void:
	await _settle()
	assert_float(_view().x).is_equal(LAYOUT_W)


func test_the_banner_sits_in_the_left_column() -> void:
	await _settle()
	assert_bool(_staff.hint_card().is_visible_in_tree()).is_true()
	print("BANNER_TEXT rows=%d" % _staff.checklist().rows().size())
	_assert_in_column("banner", _staff.hint_card().get_global_rect())


func test_the_banner_stays_put_when_a_build_tray_opens() -> void:
	await _settle()
	var closed := _staff.hint_card().get_global_rect()
	_menu.press_category(0)
	await get_tree().process_frame
	await get_tree().process_frame
	var open := _staff.hint_card().get_global_rect()
	_assert_in_column("banner over tray", open)
	assert_bool(open.is_equal_approx(closed)).is_true()
	_menu.press_category(_menu.open_category())


func test_the_hint_card_sits_in_the_left_column() -> void:
	var hints := _showing_hint()
	_menu.press_category(0)
	await _settle()
	assert_bool(_staff.hint_card().is_visible_in_tree()).is_false()
	_assert_in_column("hint", hints.card().get_global_rect())


func test_the_alert_rail_never_meets_the_banner() -> void:
	_spills()
	await _settle()
	assert_array(_stack.card_keys()).is_equal([DirtyAlert.KEY])
	var banner := _staff.hint_card().get_global_rect()
	var cards := _stack.room_rect()
	print("ALERTS view=%s banner=%s cards=%s" % [_view(), banner, cards])
	assert_bool(cards.has_area()).is_true()
	assert_bool(banner.intersects(cards)).is_false()
	_assert_in_column("banner with alerts", banner)


## PanelRoom reads the card in the banner slot, whichever it is: with a first-time
## hint showing (the status banner yielded), the camera's free room leaves the
## hint's area out, with the tray closed and with it open.
func test_the_camera_room_leaves_out_a_showing_hint() -> void:
	var hints := _hud.find_child("Hints", false, false) as Hints
	hints.card().visible = true
	_staff.set_hint_yielded(true)
	var room := _hud.get_node("PanelRoom") as PanelRoom
	for tray in [false, true]:
		if tray:
			_menu.press_category(0)
		for i in PanelRoom.REFIT_FRAMES + 4:
			await get_tree().process_frame
		var card := hints.card().get_global_rect()
		var view := _view()
		var free := room.free_fraction()
		var free_px := Rect2(free.position * view, free.size * view)
		print(
			"HINT_ROOM tray=%s card=%s free=%s rects=%s" % [tray, card, free_px, room.open_rects()]
		)
		assert_bool(card.has_area()).is_true()
		assert_float(card.position.y).is_less(view.x * 9.0 / 16.0 * TOP_BAND)
		assert_bool(room.open_rects().has(card)).is_true()
		assert_bool(free_px.intersects(card)).is_false()
	hints.card().visible = false
	_staff.set_hint_yielded(false)


## DirtyAlert.SHOW_AT spills on floored, object-free cells three apart.
func _spills() -> void:
	var grid := _sim.grid
	var placed: Array[Vector2i] = []
	for y in grid.size.y:
		for x in grid.size.x:
			var c := Vector2i(x, y)
			if placed.size() == DirtyAlert.SHOW_AT:
				return
			if grid.floor_at(c) == BuildGrid.FLOOR_NONE or grid.object_at(c) != 0:
				continue
			if placed.any(func(p: Vector2i) -> bool: return maxi(absi(p.x - x), absi(p.y - y)) < 3):
				continue
			if _sim.messes.add(MessSim.Kind.SPILL, c) != 0:
				placed.append(c)
