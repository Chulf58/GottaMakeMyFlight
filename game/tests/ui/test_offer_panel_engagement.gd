class_name TestOfferPanelEngagement
extends GdUnitTestSuite
## Engaging airline offers (ruling 68bb7f80):
## - Subtle "Airline offers available" AlertStack card posts on airport open and
##   on fresh daily/refill draws, opens OfferPanel on click, and clears on open.
## - Works alongside the CHARTER_GAP chip (459ea9b3).
## - OffersButton gently pulses and plays GameAudio's soft offer_chime on open /
##   fresh offers, stopping immediately on OfferPanel.open() and silent while
##   closed or on save load.
## - Pulse tween cleans up cleanly on _exit_tree().

const GAME_AUDIO := preload("res://audio/game_audio.gd")

var _port: SubViewport
var _clock: SimClock
var _sim: FlightSim
var _pax: PassengerSim
var _desk: OfferDesk
var _save: SaveGame
var _panel: OfferPanel
var _hud: PassengerHud
var _audio: GAME_AUDIO
var _alerts_path: String
var _deps_path: String
var _audio_path: String
var _hints_path: String


func before_test() -> void:
	_audio = get_node("/root/GameAudio") as GAME_AUDIO
	_audio_path = SaveTestKit.run_path("offer_engage_audio").replace(".json", ".cfg")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_audio_path))
	_audio.reset_for_test()
	_audio.set_settings_path(_audio_path)

	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_clock = SimClock.new()
	_clock.seed_rng(77)
	_sim = FlightSim.new()
	_sim.clock = _clock
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	_pax = PassengerSim.new()
	_pax.bind(_clock, _sim, grid)
	_desk = OfferDesk.new()
	_desk.runway = Runway.new(PlaneClasses.LARGE)
	_desk.flights = _sim
	_desk.bind_clock(_clock)
	_save = SaveGame.new()
	_port.add_child(_clock)
	_port.add_child(_sim)
	_port.add_child(_pax)
	_port.add_child(_desk)
	_port.add_child(_save)

	_panel = OfferPanel.new()
	_panel.desk = _desk
	_panel.flights = _sim
	_panel.clock = _clock
	_panel.save_game = _save
	_port.add_child(_panel)

	_alerts_path = SaveTestKit.run_path("offer_engage_alerts")
	_deps_path = SaveTestKit.run_path("offer_engage_deps")
	_hints_path = SaveTestKit.run_path("offer_engage_hints")
	DirAccess.remove_absolute(_hints_path)
	_hud = PassengerHud.new()
	_hud.debug_tools = false
	_hud.clock = _clock
	_hud.flights = _sim
	_hud.sim = _pax
	_hud.offer_desk = _desk
	_hud.offer_panel = _panel
	_hud.save_game = _save
	_hud.alert_settings_path = _alerts_path
	_hud.departures_settings_path = _deps_path
	_port.add_child(_hud)


func after_test() -> void:
	PseudoLocale.disable()
	_port.free()
	if _audio != null:
		_audio.reset_for_test()
	for p in [_alerts_path, _deps_path, _audio_path, _hints_path, _hints_path + ".tmp"]:
		DirAccess.remove_absolute(p)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _stack() -> AlertStack:
	return _hud.find_child("AlertStack", false, false) as AlertStack


func test_offers_rail_card_pulse_and_chime_wait_for_opening_then_clear_on_click() -> void:
	var fake_now := [1000]
	_audio._clock_ms = func() -> int: return fake_now[0]
	_hud.refresh()
	var stack := _stack()
	# Closed airport: hidden button, no rail card, no pulse, no chime.
	assert_bool(_panel.toggle_button().visible).is_false()
	assert_bool(_panel.pulsing).is_false()
	assert_bool(_panel.has_unseen_offers()).is_false()
	assert_object(stack.card_node(AlertSources.OFFERS_AVAILABLE)).is_null()
	assert_int(_audio.sfx_count(&"offer_chime")).is_equal(0)

	# Opening the airport posts the subtle card, starts the pulse, and plays offer_chime.
	_sim.open_airport()
	_panel._process(0.0)
	_hud.refresh()
	assert_bool(_panel.toggle_button().visible).is_true()
	assert_bool(_panel.pulsing).is_true()
	assert_bool(_panel.has_unseen_offers()).is_true()
	assert_int(_audio.sfx_count(&"offer_chime")).is_equal(1)
	var card := stack.card_node(AlertSources.OFFERS_AVAILABLE)
	assert_object(card).is_not_null()
	assert_str(card.theme_type_variation).is_equal("HudTopCard")
	assert_str(stack.card_text(AlertSources.OFFERS_AVAILABLE)).contains("Airline offers available")

	# Clicking the rail card opens OfferPanel, clears the card, and stops the pulse.
	assert_bool(stack.press_card(AlertSources.OFFERS_AVAILABLE)).is_true()
	assert_bool(_panel.is_open()).is_true()
	assert_bool(_panel.pulsing).is_false()
	assert_bool(_panel.has_unseen_offers()).is_false()
	assert_object(stack.card_node(AlertSources.OFFERS_AVAILABLE)).is_null()


func test_direct_open_clears_card_until_fresh_daily_and_refill_batches_arrive() -> void:
	var fake_now := [1000]
	_audio._clock_ms = func() -> int: return fake_now[0]
	_sim.open_airport()
	_panel._process(0.0)
	_hud.refresh()
	var stack := _stack()
	assert_object(stack.card_node(AlertSources.OFFERS_AVAILABLE)).is_not_null()
	assert_bool(_panel.pulsing).is_true()

	# Opening OfferPanel directly clears the rail card and stops the pulse.
	_panel.open()
	assert_bool(_panel.pulsing).is_false()
	assert_object(stack.card_node(AlertSources.OFFERS_AVAILABLE)).is_null()
	_panel.close()
	_hud.refresh()
	assert_object(stack.card_node(AlertSources.OFFERS_AVAILABLE)).is_null()

	# Fresh Day-1 offers bring back the subtle card, pulse, and chime.
	fake_now[0] += 5000
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var day1_ids := _desk.board.ensure_day(1, rng)
	assert_int(day1_ids.size()).is_equal(OfferBoard.OFFERS_PER_DAY)
	_hud.refresh()
	assert_bool(_panel.pulsing).is_true()
	assert_int(_audio.sfx_count(&"offer_chime")).is_equal(2)
	assert_object(stack.card_node(AlertSources.OFFERS_AVAILABLE)).is_not_null()

	# Mid-day refill while closed also triggers the cue when fresh offers arrive.
	_panel.open()
	_panel.close()
	assert_bool(_panel.pulsing).is_false()
	fake_now[0] += 5000
	var refill_ids := _desk.board.refill_day(1, 99, 0, PlaneClasses.LARGE, _sim)
	assert_int(refill_ids.size()).is_equal(OfferBoard.OFFERS_PER_DAY)
	_hud.refresh()
	assert_bool(_panel.pulsing).is_true()
	assert_int(_audio.sfx_count(&"offer_chime")).is_equal(3)
	assert_object(stack.card_node(AlertSources.OFFERS_AVAILABLE)).is_not_null()


func test_charter_gap_and_offers_available_chips_coexist_on_rail() -> void:
	_sim.open_airport()
	_panel._process(0.0)
	var cid := _desk.board.ensure_charter_for_gap(0, 300, 0, 77, PlaneClasses.LARGE, _sim)
	assert_str(cid).is_not_empty()
	_hud.refresh()
	var stack := _stack()
	assert_object(stack.card_node(AlertSources.OFFERS_AVAILABLE)).is_not_null()
	assert_object(stack.card_node(AlertSources.CHARTER_GAP)).is_not_null()


func test_save_load_never_pulses_chimes_or_reposts_offers_card() -> void:
	var fake_now := [1000]
	_audio._clock_ms = func() -> int: return fake_now[0]
	_sim.open_airport()
	_panel._process(0.0)
	_panel.open()
	_panel.close()
	assert_int(_audio.sfx_count(&"offer_chime")).is_equal(1)

	# Simulate SaveGame load (board.from_snapshot + flights.snapshot_loaded + save_game.loaded).
	fake_now[0] += 5000
	var snap := _desk.board.to_snapshot()
	_sim.snapshot_loaded.emit()
	assert_bool(_desk.board.from_snapshot(snap)).is_true()
	_save.loaded.emit(true)
	_hud.refresh()
	assert_bool(_panel.pulsing).is_false()
	assert_bool(_panel.has_unseen_offers()).is_false()
	assert_int(_audio.sfx_count(&"offer_chime")).is_equal(1)
	assert_object(_stack().card_node(AlertSources.OFFERS_AVAILABLE)).is_null()


func test_pulse_tween_cleans_up_on_exit_tree() -> void:
	_sim.open_airport()
	_panel._process(0.0)
	assert_bool(_panel.pulsing).is_true()
	_port.remove_child(_panel)
	assert_bool(_panel.pulsing).is_false()
	_panel.free()


func test_hud_hints_nudge_fires_after_opening_and_clears_when_opened() -> void:
	var staff_panel := StaffPanel.new()
	staff_panel.staff = _pax.staff
	_port.add_child(staff_panel)
	var hints := Hints.new()
	hints.forced_mode = Hints.Mode.PROFILE
	hints.settings_path = _hints_path
	hints.hud = _hud
	hints.scene_root = _port
	hints.staff_panel = staff_panel
	hints.reads_world = false
	_hud.add_child(hints)
	# Closed world: no OFFERS hint.
	var closed_world := {
		"desks": 1,
		"scanners": 1,
		"arches": 0,
		"shortage_roles": [],
		"hiring_roles": [],
		"max_toilet_need": 0,
		"max_hunger": 0,
		"stalls": 1,
		"cafes": 1,
		"airport_open": false,
		"offers_waiting": true,
		"offers_opened": false,
	}
	hints.advance(Hints.GRACE_S + 0.1, closed_world, [])
	hints.advance(0.25, closed_world, [])
	assert_bool(hints.is_showing()).is_false()

	# Open airport: OFFERS hint fires after HOLD_S.
	_sim.open_airport()
	var open_world := closed_world.duplicate()
	open_world["airport_open"] = true
	var left := HintRules.HOLD_S + 0.5
	while left > 0.0:
		hints.advance(0.25, open_world, [])
		left -= 0.25
	assert_str(String(hints.shown_id())).is_equal(String(HintRules.OFFERS))
	assert_bool(hints.is_seen(HintRules.OFFERS)).is_true()

	# Opening OfferPanel marks offers_opened true -> hint clears immediately.
	_panel.open()
	var reviewed_world := open_world.duplicate()
	reviewed_world["offers_opened"] = _panel.has_been_opened
	hints.advance(0.25, reviewed_world, [])
	assert_bool(hints.is_showing()).is_false()
	hints.free()


func test_cards_show_airline_badge_monogram_and_tailored_route_pitch() -> void:
	_sim.open_airport()
	_panel._process(0.0)
	_panel.open()
	var ids := _panel.card_ids()
	assert_int(ids.size()).is_greater(0)
	var first_id := ids[0]
	var offer := _desk.board.offer_of(first_id)
	var card := _panel.card(first_id)
	var badge := card.find_child("AirlineBadge_%s" % first_id, true, false) as PanelContainer
	assert_object(badge).is_not_null()
	assert_bool(badge.visible).is_true()
	var monogram := badge.find_child("Monogram", true, false) as Label
	assert_object(monogram).is_not_null()
	assert_str(monogram.text).is_equal(OfferPanel.airline_code(offer["airline"]))
	var style := badge.get_theme_stylebox("panel") as StyleBoxFlat
	assert_object(style).is_not_null()
	(
		assert_bool(style.bg_color.is_equal_approx(OfferPanel.airline_color(offer["airline"])))
		. is_true()
	)
	assert_str(OfferPanel.airline_code("Gotta Air")).is_equal("GA")
	assert_str(OfferPanel.airline_code("Blue Fjord")).is_equal("BF")
	assert_str(OfferPanel.airline_code("Meridian Air")).is_equal("MA")
	assert_str(OfferPanel.airline_code("Alpha")).is_equal("AL")
	(
		assert_bool(
			OfferPanel.airline_color("Gotta Air").is_equal_approx(
				OfferPanel.airline_color("Nordic Wing")
			)
		)
		. is_false()
	)
	var pitch := card.find_child("Pitch_%s" % first_id, true, false) as Label
	assert_object(pitch).is_not_null()
	assert_bool(pitch.visible).is_true()
	assert_str(pitch.text).is_equal(OfferPanel.route_pitch(offer))
	assert_str(pitch.text).is_not_empty()
	var charter := TestOfferBoard.record("CH01", 0, 720)
	charter[FlightContract.ONE_OFF_DAY_KEY] = 0
	assert_str(OfferPanel.route_pitch(charter)).contains("charter hop")
	var top_fare := TestOfferBoard.record("O0N8", 0, 720)
	top_fare[FlightContract.TRAITS_KEY] = {
		"up": OfferTraits.TOP_FARE, "down": "miss_fine", "level": 1
	}
	assert_str(OfferPanel.route_pitch(top_fare)).contains("top fare")


func test_new_offer_and_hint_msgids_are_translated_and_in_messages_pot() -> void:
	PseudoLocale.enable(0.4)
	for up_trait in [
		"",
		OfferTraits.TOP_FARE,
		OfferTraits.SHOPPERS,
		OfferTraits.BAG_COVER,
		OfferTraits.FULL_FLIGHT,
		OfferTraits.SIGNING_BONUS,
		OfferTraits.LOYAL_AIRLINE,
	]:
		for dest in OfferBoard.DESTINATIONS + ["Customville"]:
			var offer := TestOfferBoard.record("T1", 0, 600)
			offer["destination"] = dest
			if up_trait != "":
				offer[FlightContract.TRAITS_KEY] = {"up": up_trait, "down": "miss_fine", "level": 1}
			assert_str(OfferPanel.route_pitch(offer)).starts_with("[")
	var charter := TestOfferBoard.record("CH1", 0, 600)
	charter[FlightContract.ONE_OFF_DAY_KEY] = 0
	assert_str(OfferPanel.route_pitch(charter)).starts_with("[")
	PseudoLocale.disable()

	var entries := PotEntries.parse(FileAccess.get_file_as_string("res://locale/messages.pot"))
	var expected := [
		["", "Airline offers available"],
		["", "Airlines are ready with new flights — click Offers at the top to review contracts."],
		["", "Last-minute charter hop to {destination} — light bags, quick turnaround."],
		["", "Premium cabin demand to {destination} — passengers pay top fare."],
		["", "Holiday crowd bound for {destination} — plenty of time to shop."],
		["", "Smooth bag handling to {destination} — {airline} covers missed bags."],
		["", "Busy route to {destination} — almost every seat is spoken for."],
		["", "{airline} brings a welcome bonus on your first flight to {destination}."],
		["", "Steady partner route to {destination} — fly often for higher fares."],
		["", "Crisp northern hop with {airline} — steady fjord and business flyers."],
		["", "Quick city-break run to Berlin — easygoing weekend flyers."],
		["", "Warm coastal route to Lisbon — sunlit travelers heading south."],
		["", "Classic Mediterranean hop to Rome — sightseeing crowds all day."],
		["", "Friendly island link to Dublin — reliable regional commuters."],
		["", "Sunny Aegean flight to Athens — leisure flyers ready to board."],
		["", "Reliable daily link to {destination} with {airline}."],
	]
	for pair: Array in expected:
		(
			assert_int(PotEntries.complete(entries, pair[0], pair[1]))
			. override_failure_message("Missing POT entry: %s" % pair[1])
			. is_equal(1)
		)
	(
		assert_int(
			PotEntries.complete(
				entries,
				"",
				"{count} new contract waiting · click to review",
				"{count} new contracts waiting · click to review"
			)
		)
		. is_equal(1)
	)
