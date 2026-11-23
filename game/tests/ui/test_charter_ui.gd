class_name TestCharterUi
extends GdUnitTestSuite
## OfferPanel charter cards ("One-off charter — flies today only") and the
## subtle clickable AlertStack gap chip wired through PassengerHud.

var _port: SubViewport
var _clock: SimClock
var _sim: FlightSim
var _pax: PassengerSim
var _desk: OfferDesk
var _panel: OfferPanel
var _hud: PassengerHud
var _settings_path: String
var _dep_path: String


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_clock = SimClock.new()
	_clock.seed_rng(77)
	_sim = FlightSim.new()
	_sim.bind_clock(_clock)
	_sim.open_airport()
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	_pax = PassengerSim.new()
	_pax.bind(_clock, _sim, grid)
	_desk = OfferDesk.new()
	_desk.runway = Runway.new(PlaneClasses.LARGE)
	_desk.flights = _sim
	_desk.bind_clock(_clock)
	_port.add_child(_clock)
	_port.add_child(_sim)
	_port.add_child(_pax)
	_port.add_child(_desk)
	_panel = OfferPanel.new()
	_panel.desk = _desk
	_panel.flights = _sim
	_port.add_child(_panel)
	_settings_path = SaveTestKit.run_path("charter_ui_alerts")
	_dep_path = SaveTestKit.run_path("charter_ui_deps")
	_hud = PassengerHud.new()
	_hud.debug_tools = false
	_hud.clock = _clock
	_hud.flights = _sim
	_hud.sim = _pax
	_hud.offer_desk = _desk
	_hud.offer_panel = _panel
	_hud.alert_settings_path = _settings_path
	_hud.departures_settings_path = _dep_path
	_port.add_child(_hud)


func after_test() -> void:
	_port.free()
	DirAccess.remove_absolute(_settings_path)
	DirAccess.remove_absolute(_dep_path)


func _stack() -> AlertStack:
	return _hud.find_child("AlertStack", false, false) as AlertStack


func test_offer_panel_renders_badged_charter_and_accept_flow() -> void:
	var cid := _desk.board.ensure_charter_for_gap(0, 300, 0, 77, PlaneClasses.LARGE, _sim)
	assert_str(cid).is_not_empty()
	var charter := _desk.board.charter_of(cid)
	var regular_count := _desk.board.open_offers().size()
	assert_str(_panel.toggle_button().text).is_equal("Offers (%d)" % (regular_count + 1))

	_panel.open()
	assert_array(_panel.card_ids()).contains([cid])
	assert_str(_panel.card_ids()[0]).is_equal(cid)
	var text := _panel.card_text(cid)
	assert_str(text).contains(OfferPanel.CHARTER_BADGE_TEXT)
	assert_str(text).contains(charter["airline"])
	assert_str(text).contains(charter["destination"])
	assert_str(text).contains("today")
	assert_str(text).contains("payout")
	assert_str(text).contains("No exit fee")
	assert_str(_panel.fit_text(cid)).is_equal(OfferPanel.FITS_TEXT)

	_panel.accept_button(cid).pressed.emit()
	assert_bool(_sim.contract_of(cid).is_empty()).is_false()
	assert_array(_desk.board.open_charters()).is_empty()
	assert_array(_panel.card_ids()).not_contains([cid])
	assert_str(_panel.toggle_button().text).is_equal("Offers (%d)" % regular_count)


func test_gap_chip_appears_opens_offer_panel_and_clears_on_accept_expire_or_clash() -> void:
	_hud.refresh()
	var stack := _stack()
	assert_object(stack.card_node(AlertSources.CHARTER_GAP)).is_null()

	# Opening a charter surfaces the subtle non-blocking chip at once.
	var cid := _desk.board.ensure_charter_for_gap(0, 300, 0, 77, PlaneClasses.LARGE, _sim)
	assert_str(cid).is_not_empty()
	_hud.refresh()
	var chip := stack.card_node(AlertSources.CHARTER_GAP)
	assert_object(chip).is_not_null()
	assert_str(chip.theme_type_variation).is_equal("HudTopCard")
	assert_str(stack.card_text(AlertSources.CHARTER_GAP)).contains("Charter available")

	# Clicking the chip opens OfferPanel.
	assert_bool(_panel.is_open()).is_false()
	assert_bool(stack.press_card(AlertSources.CHARTER_GAP)).is_true()
	assert_bool(_panel.is_open()).is_true()

	# Accepting the charter clears the chip immediately.
	_panel.accept_button(cid).pressed.emit()
	_hud.refresh()
	assert_object(stack.card_node(AlertSources.CHARTER_GAP)).is_null()
	_panel.close()

	# Gap closed by another flight also clears an open chip immediately.
	_clock.tick = GameCalendar.tick_at(0, 12 * 60, 0)
	var cid2 := _desk.board.ensure_charter_for_gap(0, _clock.tick, 0, 88, PlaneClasses.LARGE, _sim)
	assert_str(cid2).is_not_empty()
	_hud.refresh()
	assert_object(stack.card_node(AlertSources.CHARTER_GAP)).is_not_null()
	var c2 := _desk.board.charter_of(cid2)
	var blocker := TestFlightFit.terms("BLK", int(c2["departure_minute"]), PlaneClasses.SMALL)
	assert_bool(_sim.accept_contract(blocker)).is_true()
	_hud.refresh()
	assert_object(stack.card_node(AlertSources.CHARTER_GAP)).is_null()

	# Cutoff expiry removes the card from OfferPanel and chip from AlertStack.
	assert_bool(_desk.board.expire_charters(int(c2["cutoff_tick"]) + 1, 0)).is_true()
	assert_array(_panel.card_ids()).not_contains([cid2])

	# Fresh un-clashed charter on Day 1: cutoff expiry transitions CHARTER_GAP from non-null to null.
	_clock.tick = GameCalendar.tick_at(1, 375, 0)
	_desk.on_tick(_clock.tick)
	var late_gap := ""
	if not _desk.board.open_charters().is_empty():
		late_gap = _desk.board.open_charters()[0]["id"]
	else:
		late_gap = _desk.board.ensure_charter_for_gap(
			1, _clock.tick, 0, 91, PlaneClasses.LARGE, _sim
		)
	assert_str(late_gap).is_not_empty()
	_hud.refresh()
	assert_object(stack.card_node(AlertSources.CHARTER_GAP)).is_not_null()
	var c3 := _desk.board.charter_of(late_gap)
	_clock.tick = int(c3["cutoff_tick"]) + 1
	assert_bool(_desk.board.expire_charters(_clock.tick, 1)).is_true()
	_hud.refresh()
	assert_object(stack.card_node(AlertSources.CHARTER_GAP)).is_null()


func test_offer_panel_with_charter_and_three_daily_offers_fits_inside_1280x720() -> void:
	var cid := _desk.board.ensure_charter_for_gap(0, 300, 0, 77, PlaneClasses.LARGE, _sim)
	assert_str(cid).is_not_empty()
	assert_int(_desk.board.open_offers().size()).is_equal(3)
	_panel.open()
	await await_idle_frame()
	await await_idle_frame()
	assert_int(_panel.card_ids().size()).is_equal(4)
	var sheet_rect := _panel.sheet().get_global_rect()
	assert_bool(Rect2(Vector2.ZERO, Vector2(1280.0, 720.0)).encloses(sheet_rect)).is_true()
