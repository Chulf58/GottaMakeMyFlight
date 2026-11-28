class_name TestManagerDialogueBeats
extends GdUnitTestSuite
## Two-Beat Interactive Call tests for IntroDialogue, BigFirsts, UnlockGuide,
## IncidentPanel, and GameAudio voice blips (decision b8aee2a2).

const GAME_AUDIO := preload("res://audio/game_audio.gd")

var _port: SubViewport
var _shown_before: bool


func before_test() -> void:
	_shown_before = IntroDialogue.shown_this_session
	IntroDialogue.shown_this_session = false
	_port = SubViewport.new()
	_port.size = Vector2i(1920, 1080)
	add_child(_port)


func after_test() -> void:
	var audio := get_node_or_null("/root/GameAudio")
	if audio != null and audio.has_method(&"reset_for_test"):
		audio.reset_for_test()
	_port.free()
	IntroDialogue.shown_this_session = _shown_before


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event


func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		_port.push_input(event)


func _word_count(text: String) -> int:
	var words := text.strip_edges().split(" ", false)
	return words.size()


func test_two_beat_typewriter_space_and_click_skip_before_advancing_and_dismissing() -> void:
	var dialog := IntroDialogue.new(
		"Call",
		"",
		IntroDialogue.BOX_SIZE.y,
		false,
		IntroDialogue.Speaker.TERMINAL_MANAGER,
		{"beats": ["First short beat here.", "Second short beat here."]}
	)
	var dismissed_count := [0]
	dialog.dismissed.connect(func() -> void: dismissed_count[0] += 1)
	_port.add_child(dialog)

	assert_int(dialog.beat_index()).is_equal(0)
	assert_array(dialog.beats()).is_equal(["First short beat here.", "Second short beat here."])
	assert_str(dialog.body_text()).is_equal("First short beat here.")
	assert_bool(dialog.is_revealing()).is_true()
	assert_str(dialog.beat_pill().text).is_equal("1 / 2")
	assert_str(dialog.continue_button().text).contains("Next")

	# First Space finishes beat 1 reveal without advancing or dismissing.
	_port.push_input(_key(KEY_SPACE))
	assert_bool(dialog.is_revealing()).is_false()
	assert_int(dialog.beat_index()).is_equal(0)
	assert_bool(dialog.is_dismissed()).is_false()

	# Second Space advances to beat 2.
	_port.push_input(_key(KEY_SPACE))
	assert_int(dialog.beat_index()).is_equal(1)
	assert_str(dialog.body_text()).is_equal("Second short beat here.")
	assert_str(dialog.beat_pill().text).is_equal("2 / 2")
	assert_str(dialog.continue_button().text).contains("Continue")
	assert_bool(dialog.is_dismissed()).is_false()

	# Let beat 2 finish revealing via _process, then third Space dismisses.
	var body := dialog.find_child("Body", true, false) as Label
	for _i in 60:
		dialog._process(0.05)
		if not dialog.is_revealing():
			break
	assert_bool(dialog.is_revealing()).is_false()
	assert_int(body.visible_characters).is_equal(-1)

	_port.push_input(_key(KEY_SPACE))
	assert_bool(dialog.is_dismissed()).is_true()
	assert_int(dismissed_count[0]).is_equal(1)

	# Also verify box click follows the same 3-step skip -> advance -> dismiss cadence.
	var click_dialog := IntroDialogue.new(
		"Call",
		"",
		IntroDialogue.BOX_SIZE.y,
		false,
		IntroDialogue.Speaker.TERMINAL_MANAGER,
		{"beats": ["Beat one by click.", "Beat two by click."]}
	)
	_port.add_child(click_dialog)
	var box_center: Vector2 = click_dialog.part_rects()["box"].get_center()
	assert_bool(click_dialog.is_revealing()).is_true()
	_click(box_center)
	assert_bool(click_dialog.is_revealing()).is_false()
	assert_int(click_dialog.beat_index()).is_equal(0)
	_click(box_center)
	assert_int(click_dialog.beat_index()).is_equal(1)
	click_dialog.finish_reveal()
	_click(box_center)
	assert_bool(click_dialog.is_dismissed()).is_true()

	# Continue/Next button pressed during reveal skips reveal first, then advances/dismisses.
	var btn_dialog := IntroDialogue.new(
		"Call",
		"",
		IntroDialogue.BOX_SIZE.y,
		false,
		IntroDialogue.Speaker.TERMINAL_MANAGER,
		{"beats": ["Beat one by button.", "Beat two by button."]}
	)
	_port.add_child(btn_dialog)
	assert_bool(btn_dialog.is_revealing()).is_true()
	btn_dialog.continue_button().pressed.emit()
	assert_bool(btn_dialog.is_revealing()).is_false()
	assert_int(btn_dialog.beat_index()).is_equal(0)
	btn_dialog.continue_button().pressed.emit()
	assert_int(btn_dialog.beat_index()).is_equal(1)
	assert_bool(btn_dialog.is_revealing()).is_true()
	btn_dialog.continue_button().pressed.emit()
	assert_bool(btn_dialog.is_revealing()).is_false()
	assert_bool(btn_dialog.is_dismissed()).is_false()
	btn_dialog.continue_button().pressed.emit()
	assert_bool(btn_dialog.is_dismissed()).is_true()


func test_new_game_intro_and_gotta_air_calls_are_crisp_two_beat_copy() -> void:
	var intro := IntroDialogue.new()
	_port.add_child(intro)
	var intro_beats: Array[String] = intro.beats()
	assert_int(intro_beats.size()).is_equal(2)
	for beat in intro_beats:
		assert_int(_word_count(beat)).is_less_equal(18)
	assert_int(intro.chips_row().get_child_count()).is_equal(3)

	var opening_beats: Array[String] = BigFirsts.beats_for([BigFirsts.OPENING], "08:13")
	assert_int(opening_beats.size()).is_equal(2)
	for beat in opening_beats:
		assert_int(_word_count(beat)).is_less_equal(18)

	var runway_beats: Array[String] = BigFirsts.beats_for([BigFirsts.RUNWAY])
	assert_int(runway_beats.size()).is_equal(1)
	assert_int(_word_count(runway_beats[0])).is_less_equal(18)

	var incident_beats: Array[String] = BigFirsts.beats_for([BigFirsts.INCIDENT])
	assert_int(incident_beats.size()).is_equal(1)
	assert_int(_word_count(incident_beats[0])).is_less_equal(18)


func test_icon_chips_render_and_action_button_fires_callback_and_dismisses() -> void:
	var fired := [0]
	var chips: Array[Dictionary] = [
		{
			"icon": load("res://assets/ui/icons/gates.svg"),
			"label": "1st Flight",
			"tint": Color(0.24, 0.56, 0.72, 1.0),
		},
		{
			"icon": load("res://assets/ui/icons/coin.svg"),
			"label": "Offers",
			"tint": Color(0.84, 0.58, 0.16, 1.0),
		},
	]
	var dialog := IntroDialogue.new(
		"Station manager",
		"",
		IntroDialogue.BOX_SIZE.y,
		false,
		IntroDialogue.Speaker.GOTTA_AIR,
		{
			"beats": BigFirsts.beats_for([BigFirsts.OPENING], "08:13"),
			"chips": chips,
			"action_label": "Open Offers",
			"action_callback": func() -> void: fired[0] += 1,
		}
	)
	_port.add_child(dialog)
	await get_tree().process_frame

	var row := dialog.chips_row()
	assert_bool(row.is_visible_in_tree()).is_true()
	assert_int(row.get_child_count()).is_equal(2)
	var box: Rect2 = dialog.part_rects()["box"]
	assert_bool(box.encloses(row.get_global_rect())).is_true()

	var action_btn := dialog.action_button()
	assert_object(action_btn).is_not_null()
	assert_bool(action_btn.is_visible_in_tree()).is_true()
	assert_str(action_btn.text).is_equal("Open Offers")
	assert_bool(box.encloses(action_btn.get_global_rect())).is_true()

	action_btn.pressed.emit()
	assert_int(fired[0]).is_equal(1)
	assert_bool(dialog.is_dismissed()).is_true()


func test_portrait_bob_activates_while_revealing_and_settles_to_one_on_finish() -> void:
	var dialog := IntroDialogue.new(
		"Manager",
		"",
		IntroDialogue.BOX_SIZE.y,
		false,
		IntroDialogue.Speaker.TERMINAL_MANAGER,
		{"beats": ["Short line for bob check."]}
	)
	_port.add_child(dialog)
	var portrait := dialog.find_child("Portrait", true, false) as TextureRect
	assert_object(portrait).is_not_null()
	assert_bool(dialog.is_revealing()).is_true()

	dialog._process(0.05)
	assert_bool(portrait.scale != Vector2.ONE or portrait.position.y != 0.0).is_true()

	dialog.finish_reveal()
	assert_bool(dialog.is_revealing()).is_false()
	assert_vector(portrait.scale).is_equal(Vector2.ONE)
	assert_vector(portrait.position).is_equal(Vector2.ZERO)


func test_voice_blip_synthesizes_in_memory_respects_cooldown_mute_and_dummy() -> void:
	var audio := get_node_or_null("/root/GameAudio") as GAME_AUDIO
	assert_object(audio).is_not_null()
	var mgr_stream := audio._sfx_streams.get(&"voice_blip_manager") as AudioStreamWAV
	var air_stream := audio._sfx_streams.get(&"voice_blip_airline") as AudioStreamWAV
	assert_object(mgr_stream).is_not_null()
	assert_object(air_stream).is_not_null()
	assert_float(mgr_stream.get_length()).is_between(0.02, 0.12)
	assert_float(air_stream.get_length()).is_between(0.02, 0.12)

	# Baseline on non-Dummy driver passes.
	assert_bool(audio.can_play_voice_blip(&"manager", 10000, "WASAPI")).is_true()
	assert_bool(audio.can_play_voice_blip(&"airline", 10000, "WASAPI")).is_true()

	# 1. Dummy driver suppresses playback independently.
	assert_str(AudioServer.get_driver_name()).is_equal("Dummy")
	assert_bool(audio.can_play_voice_blip(&"manager", 10000, "Dummy")).is_false()
	assert_bool(audio.play_voice_blip(&"manager")).is_false()
	assert_int(audio.sfx_count(&"voice_blip_manager")).is_equal(0)

	# 2. Mute gate suppresses independently (verified against non-Dummy driver).
	audio.set_muted(true)
	assert_bool(audio.can_play_voice_blip(&"airline", 10000, "WASAPI")).is_false()
	audio.set_muted(false)
	assert_bool(audio.can_play_voice_blip(&"airline", 10000, "WASAPI")).is_true()

	# 3. Zero Master or SFX volume suppresses independently.
	audio.set_master_volume(0.0, false)
	assert_bool(audio.can_play_voice_blip(&"manager", 10000, "WASAPI")).is_false()
	audio.set_master_volume(GAME_AUDIO.DEFAULT_MASTER, false)
	audio.set_sfx_volume(0.0, false)
	assert_bool(audio.can_play_voice_blip(&"manager", 10000, "WASAPI")).is_false()
	audio.set_sfx_volume(GAME_AUDIO.DEFAULT_SFX, false)
	assert_bool(audio.can_play_voice_blip(&"manager", 10000, "WASAPI")).is_true()

	# 4. 65 ms cooldown suppresses repeat triggers until elapsed.
	audio._last_played_ms[&"voice_blip_manager"] = 10000
	assert_bool(audio.can_play_voice_blip(&"manager", 10040, "WASAPI")).is_false()
	assert_bool(audio.can_play_voice_blip(&"manager", 10065, "WASAPI")).is_true()


func test_all_real_incident_types_stay_within_two_beats_and_eighteen_words() -> void:
	var cases := [
		{
			"kind": IncidentCatalogue.INSPECTOR,
			"offer": false,
			"plan":
			{
				"window_from": 50_000,
				"window_to": 58_000,
				"visit_tick": 52_000,
				"max_messes": IncidentTuning.INSPECTOR_MAX_MESSES,
				"max_full_queue": IncidentTuning.INSPECTOR_MAX_FULL_QUEUE,
				"pass_money": IncidentTuning.INSPECTOR_PASS_MONEY,
				"fail_half_stars": IncidentTuning.INSPECTOR_FAIL_HALF_STARS,
			},
		},
		{
			"kind": IncidentCatalogue.RUSH,
			"offer": false,
			"plan":
			{
				"flights":
				[
					{"flight": "AM-d2", "extra": 4, "departs": 60_000},
					{"flight": "BM-d2", "extra": 6, "departs": 66_000},
				],
				"total": 10,
				"until": 79_200,
			},
		},
		{
			"kind": IncidentCatalogue.VIP,
			"offer": true,
			"plan":
			{
				"flight": "AM-d1",
				"departs": 60_000,
				"bonus": 500,
				"target": 0,
				"good_mood": 75,
				"miss_half_stars": 2,
			},
		},
		{
			"kind": IncidentCatalogue.FAVOUR,
			"offer": true,
			"plan": {"flight": "AM-d1", "departs": 60_000, "extra": 4, "bonus": 300},
		},
	]
	for entry: Dictionary in cases:
		var kind: String = entry["kind"]
		var offer: bool = entry["offer"]
		var filled := IncidentCopy.fill(
			IncidentCatalogue.panel_copy(kind), {"kind": kind, "plan": entry["plan"]}, 0, 0
		)
		var parts := IncidentPanel.parts_for(filled, offer)
		var beats: Array[String] = parts["beats"]
		assert_int(beats.size()).is_between(1, 2)
		for beat in beats:
			(
				assert_int(_word_count(beat))
				. override_failure_message(
					"%s beat too long (%d): %s" % [kind, _word_count(beat), beat]
				)
				. is_less_equal(18)
			)
		assert_int((parts["chips"] as Array).size()).is_equal(2)
		assert_str(str(parts["footer"])).is_not_empty()


func test_coalesced_unlock_guide_batch_stays_within_two_beats_and_keeps_chips_and_action() -> void:
	var clock := SimClock.new()
	_port.add_child(clock)
	var rating: AirportRating = auto_free(AirportRating.new())
	var unlocks := BuildUnlocks.new()
	unlocks.rating = rating
	unlocks.passengers = auto_free(PassengerSim.new())
	unlocks.manual = true
	_port.add_child(unlocks)
	var guide := UnlockGuide.new()
	guide.mode = UnlockGuide.Mode.PROFILE
	guide.unlocks = unlocks
	guide.clock = clock
	_port.add_child(guide)

	guide.open_dialog([2], [BigFirsts.RUNWAY, BigFirsts.INCIDENT])
	guide.answer_ring()
	var dlg := guide.dialog()
	assert_object(dlg).is_not_null()
	assert_int(dlg.beats().size()).is_between(1, 2)
	for beat in dlg.beats():
		assert_int(_word_count(beat)).is_less_equal(18)
	var chips := Array(dlg.chip_texts())
	assert_array(chips).contains(["Food", "Larger planes", "Major event"])
	assert_object(dlg.action_button()).is_not_null()
	assert_str(dlg.action_button().text).is_equal("Open Runway")
	assert_str(dlg.footer_text()).contains("The clock goes on")


func test_unlock_guide_opening_call_and_incident_panel_wire_chips_and_actions() -> void:
	var clock := SimClock.new()
	_port.add_child(clock)
	var flights := FlightSim.new()
	flights.clock = clock
	flights.open_airport()
	_port.add_child(flights)
	var rating: AirportRating = auto_free(AirportRating.new())
	var desk := OfferDesk.new()
	desk.clock = clock
	desk.rating = rating
	_port.add_child(desk)
	var offer_panel := OfferPanel.new()
	offer_panel.desk = desk
	offer_panel.flights = flights
	offer_panel.clock = clock
	_port.add_child(offer_panel)

	var unlocks := BuildUnlocks.new()
	unlocks.rating = rating
	unlocks.passengers = auto_free(PassengerSim.new())
	unlocks.manual = true
	_port.add_child(unlocks)

	var guide := UnlockGuide.new()
	guide.mode = UnlockGuide.Mode.PROFILE
	guide.unlocks = unlocks
	guide.clock = clock
	guide.flights = flights
	guide.offer_panel = offer_panel
	_port.add_child(guide)

	guide.open_dialog([], [BigFirsts.OPENING])
	guide.answer_ring()
	var dlg := guide.dialog()
	assert_object(dlg).is_not_null()
	assert_array(Array(dlg.chip_texts())).is_equal(["1st Flight", "Offers"])
	assert_bool(offer_panel.is_open()).is_false()
	dlg.action_button().pressed.emit()
	assert_bool(guide.is_open()).is_false()
	assert_bool(offer_panel.is_open()).is_true()

	# IncidentPanel splits offer reward/failure into scannable chips.
	var parts := (
		IncidentPanel
		. parts_for(
			{
				"title": "VIP",
				"body": "VIP arrives today.",
				"reward": "Reward: 500 money.",
				"failure": "If it fails: -1 star.",
			},
			true
		)
	)
	assert_array(parts["beats"]).is_equal(["VIP arrives today."])
	assert_int((parts["chips"] as Array).size()).is_equal(2)
	assert_str((parts["chips"][0] as Dictionary)["label"]).is_equal("Reward: 500 money.")
	assert_str((parts["chips"][1] as Dictionary)["label"]).is_equal("If it fails: -1 star.")


func _chip_buttons(dialog: IntroDialogue) -> Array[Button]:
	var out: Array[Button] = []
	for child in dialog.chips_row().get_children():
		var btn := child as Button
		if btn != null:
			out.append(btn)
	return out


func _chip_tip(dialog: IntroDialogue) -> PanelContainer:
	return dialog.find_child("ChipTip", true, false) as PanelContainer


func _chip_tip_text(dialog: IntroDialogue) -> String:
	var tip := _chip_tip(dialog)
	if tip == null or not tip.visible:
		return ""
	var lbl := tip.find_child("ChipTipLabel", true, false) as Label
	return lbl.text if lbl != null else ""


func test_clicking_chip_consumes_click_and_toggles_inline_tip_without_advancing() -> void:
	var dialog := (
		IntroDialogue
		. new(
			BigFirsts.opening_title_text(),
			"",
			IntroDialogue.BOX_SIZE.y,
			false,
			IntroDialogue.Speaker.GOTTA_AIR,
			{
				"beats": ["First beat.", "Second beat."],
				"chips": BigFirsts.chips_for([BigFirsts.OPENING], "08:13"),
			}
		)
	)
	_port.add_child(dialog)
	dialog.finish_reveal()
	await get_tree().process_frame
	await get_tree().process_frame

	var chips := _chip_buttons(dialog)
	assert_int(chips.size()).is_equal(2)
	for chip in chips:
		assert_int(chip.focus_mode).is_equal(Control.FOCUS_NONE)
		assert_int(chip.mouse_default_cursor_shape).is_equal(Control.CURSOR_POINTING_HAND)
		assert_str(chip.tooltip_text).is_not_empty()
	assert_bool(_chip_tip(dialog).visible).is_false()

	# Clicking first chip opens inline tip and does NOT advance or dismiss.
	_click(chips[0].get_global_rect().get_center())
	await get_tree().process_frame
	assert_int(dialog.beat_index()).is_equal(0)
	assert_bool(dialog.is_dismissed()).is_false()
	assert_bool(_chip_tip(dialog).visible).is_true()
	assert_str(_chip_tip_text(dialog)).is_equal(chips[0].tooltip_text)
	assert_bool(chips[0].button_pressed).is_true()
	assert_bool(dialog.part_rects()["box"].encloses(_chip_tip(dialog).get_global_rect())).is_true()

	# Clicking second chip switches active chip and tip without advancing.
	_click(chips[1].get_global_rect().get_center())
	await get_tree().process_frame
	assert_int(dialog.beat_index()).is_equal(0)
	assert_bool(dialog.is_dismissed()).is_false()
	assert_bool(chips[0].button_pressed).is_false()
	assert_bool(chips[1].button_pressed).is_true()
	assert_str(_chip_tip_text(dialog)).is_equal(chips[1].tooltip_text)

	# Clicking active chip again hides the callout without advancing.
	_click(chips[1].get_global_rect().get_center())
	await get_tree().process_frame
	assert_int(dialog.beat_index()).is_equal(0)
	assert_bool(dialog.is_dismissed()).is_false()
	assert_bool(chips[1].button_pressed).is_false()
	assert_bool(_chip_tip(dialog).visible).is_false()

	# Advancing beats clears any open chip tip.
	_click(chips[0].get_global_rect().get_center())
	assert_bool(_chip_tip(dialog).visible).is_true()
	dialog.continue_button().pressed.emit()
	assert_int(dialog.beat_index()).is_equal(1)
	assert_bool(_chip_tip(dialog).visible).is_false()


func test_all_big_firsts_and_intro_chips_have_non_empty_tips_and_pointing_hand() -> void:
	var intro := IntroDialogue.new()
	_port.add_child(intro)
	assert_int(_chip_buttons(intro).size()).is_equal(3)
	for chip in _chip_buttons(intro):
		assert_str(chip.tooltip_text).is_not_empty()
		assert_int(chip.mouse_default_cursor_shape).is_equal(Control.CURSOR_POINTING_HAND)
	intro.free()

	for kind in [BigFirsts.OPENING, BigFirsts.RUNWAY, BigFirsts.INCIDENT]:
		var chips := BigFirsts.chips_for([kind], "08:13")
		assert_array(chips).is_not_empty()
		for entry in chips:
			assert_str(str(entry.get("tooltip", ""))).is_not_empty()
		var dlg := IntroDialogue.new(
			"Test",
			"Body",
			IntroDialogue.BOX_SIZE.y,
			false,
			IntroDialogue.Speaker.TERMINAL_MANAGER,
			{"chips": chips}
		)
		_port.add_child(dlg)
		for chip in _chip_buttons(dlg):
			assert_str(chip.tooltip_text).is_not_empty()
			assert_int(chip.mouse_default_cursor_shape).is_equal(Control.CURSOR_POINTING_HAND)
		dlg.free()
