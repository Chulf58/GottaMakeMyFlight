class_name TestGameAudio
extends GdUnitTestSuite
## The D5 demo audio floor: Master/Ambience/SFX bus creation and routing,
## linear-to-dB volume and mute state on AudioServer, isolated ConfigFile
## persistence and script-run shielding, gameplay ambience loop start/stop,
## UI/build/cash SFX triggers without per-passenger spam or leaks, and live
## slider/mute two-way sync (including drag_ended single-write) in both
## GameMenu and TitleScreen.

const GAME_AUDIO := preload("res://audio/game_audio.gd")

var _audio: GAME_AUDIO
var _cfg_path := ""
var _shield_path := ""
var _title_dir := ""
var _dir_before := ""


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_audio = get_node("/root/GameAudio") as GAME_AUDIO
	_cfg_path = SaveTestKit.run_path("audio_settings").replace(".json", ".cfg")
	_shield_path = SaveTestKit.run_path("audio_shielded").replace(".json", ".cfg")
	_title_dir = SaveTestKit.run_dir("test_audio_title")
	_dir_before = SaveSlots.dir
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_cfg_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_shield_path))
	_audio.reset_for_test()
	_audio.set_settings_path(_cfg_path)


func after_test() -> void:
	if _audio != null:
		_audio.reset_for_test()
	SaveSlots.dir = _dir_before
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_cfg_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_shield_path))
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_title_dir)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_title_dir))


func test_buses_exist_and_route_to_master() -> void:
	var master_idx := AudioServer.get_bus_index(&"Master")
	var amb_idx := AudioServer.get_bus_index(&"Ambience")
	var sfx_idx := AudioServer.get_bus_index(&"SFX")
	assert_int(master_idx).is_equal(0)
	assert_int(amb_idx).is_greater(0)
	assert_int(sfx_idx).is_greater(0)
	assert_str(String(AudioServer.get_bus_send(amb_idx))).is_equal("Master")
	assert_str(String(AudioServer.get_bus_send(sfx_idx))).is_equal("Master")


func test_linear_volume_and_mute_drive_audio_server_buses() -> void:
	var master_idx := AudioServer.get_bus_index(&"Master")
	var amb_idx := AudioServer.get_bus_index(&"Ambience")
	var sfx_idx := AudioServer.get_bus_index(&"SFX")

	_audio.set_master_volume(0.5)
	_audio.set_ambience_volume(0.25)
	_audio.set_sfx_volume(0.0)
	assert_float(AudioServer.get_bus_volume_db(master_idx)).is_equal_approx(linear_to_db(0.5), 0.05)
	assert_float(AudioServer.get_bus_volume_db(amb_idx)).is_equal_approx(linear_to_db(0.25), 0.05)
	assert_bool(AudioServer.is_bus_mute(master_idx)).is_false()
	assert_bool(AudioServer.is_bus_mute(amb_idx)).is_false()
	assert_bool(AudioServer.is_bus_mute(sfx_idx)).is_true()

	_audio.set_muted(true)
	assert_bool(AudioServer.is_bus_mute(master_idx)).is_true()
	assert_float(_audio.master_volume).is_equal_approx(0.5, 0.001)
	_audio.set_muted(false)
	assert_bool(AudioServer.is_bus_mute(master_idx)).is_false()


func test_settings_persist_to_isolated_config_and_shield_protected_path() -> void:
	_audio.set_master_volume(0.42)
	_audio.set_ambience_volume(0.35)
	_audio.set_sfx_volume(0.64)
	_audio.set_muted(true)
	assert_bool(FileAccess.file_exists(_cfg_path)).is_true()

	_audio.master_volume = 1.0
	_audio.ambience_volume = 1.0
	_audio.sfx_volume = 1.0
	_audio.muted = false
	_audio.load_settings(_cfg_path)
	assert_float(_audio.master_volume).is_equal_approx(0.42, 0.001)
	assert_float(_audio.ambience_volume).is_equal_approx(0.35, 0.001)
	assert_float(_audio.sfx_volume).is_equal_approx(0.64, 0.001)
	assert_bool(_audio.muted).is_true()

	# Shield check: pointing protected_path + settings_path at _shield_path drops writes in -s runs.
	_audio.protected_path = _shield_path
	_audio.set_settings_path(_shield_path)
	_audio.set_master_volume(0.15)
	assert_bool(FileAccess.file_exists(_shield_path)).is_false()


func test_ambience_loops_only_while_gameplay_is_in_tree() -> void:
	assert_bool(_audio.is_ambience_playing()).is_false()
	var mode := BuildMode.new()
	add_child(mode)
	assert_bool(_audio.is_ambience_playing()).is_true()
	var amb_player := _audio.get_node("AmbiencePlayer") as AudioStreamPlayer
	assert_str(String(amb_player.bus)).is_equal("Ambience")
	var ogg := amb_player.stream as AudioStreamOggVorbis
	assert_object(ogg).is_not_null()
	assert_bool(ogg.loop).is_true()
	assert_bool(ogg.has_loop()).is_true()
	assert_float(ogg.get_length()).is_between(55.0, 95.0)
	mode.free()
	assert_bool(_audio.is_ambience_playing()).is_false()


func test_prepare_ambience_stream_supports_ogg_and_wav_loops() -> void:
	var raw_ogg := AudioStreamOggVorbis.new()
	raw_ogg.loop = false
	var prepared_ogg := _audio._prepare_ambience_stream(raw_ogg) as AudioStreamOggVorbis
	assert_object(prepared_ogg).is_not_null()
	assert_bool(prepared_ogg != raw_ogg).is_true()
	assert_bool(prepared_ogg.loop).is_true()

	var raw_wav := AudioStreamWAV.new()
	raw_wav.mix_rate = 44100
	raw_wav.format = AudioStreamWAV.FORMAT_16_BITS
	raw_wav.data = PackedByteArray([0, 0, 0, 0])
	raw_wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	var prepared_wav := _audio._prepare_ambience_stream(raw_wav) as AudioStreamWAV
	assert_object(prepared_wav).is_not_null()
	assert_bool(prepared_wav != raw_wav).is_true()
	assert_int(prepared_wav.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	assert_int(prepared_wav.loop_begin).is_equal(0)
	assert_int(prepared_wav.loop_end).is_greater(0)


func test_ui_button_build_flight_departure_and_lump_cash_events_trigger_sfx() -> void:
	var btn := Button.new()
	add_child(btn)
	btn.pressed.emit()
	assert_str(String(_audio.last_sfx())).is_equal("ui_click")
	assert_int(_audio.sfx_count(&"ui_click")).is_equal(1)
	btn.free()

	var mode := BuildMode.new()
	add_child(mode)
	var place_edit := BuildEdit.paint_floor(Vector2i(2, 2), BuildGrid.FLOOR_TILE, 1)
	mode.grid.edit_applied.emit(place_edit, BuildResult.new())
	assert_str(String(_audio.last_sfx())).is_equal("build_place")
	var remove_edit := BuildEdit.remove_floor(Vector2i(2, 2))
	mode.grid.edit_applied.emit(remove_edit, BuildResult.new())
	assert_str(String(_audio.last_sfx())).is_equal("build_remove")
	mode.grid.edit_refused.emit(place_edit, BuildResult.new())
	assert_str(String(_audio.last_sfx())).is_equal("build_refuse")
	mode.free()

	var finances := Finances.new()
	add_child(finances)
	# Opening budget, per-passenger boarding FEES and cafe SHOP ticks must not chime.
	finances.wallet.credit(25, Wallet.Category.FEES)
	finances.wallet.credit(8, Wallet.Category.SHOP)
	assert_int(_audio.sfx_count(&"cash_chime")).is_equal(0)
	# Lump-sum signing bonus rings cash_chime once.
	finances.wallet.credit(250, Wallet.Category.SIGNING_BONUS)
	assert_str(String(_audio.last_sfx())).is_equal("cash_chime")
	assert_int(_audio.sfx_count(&"cash_chime")).is_equal(1)
	finances.free()

	# Flight departure completion also rings cash_chime (when off cooldown).
	_audio.reset_for_test()
	_audio.set_settings_path(_cfg_path)
	var flights := FlightSim.new()
	add_child(flights)
	flights.state_changed.emit("GMF101", FlightSim.State.BOARDING)
	assert_int(_audio.sfx_count(&"cash_chime")).is_equal(0)
	flights.state_changed.emit("GMF101", FlightSim.State.DEPARTED)
	assert_int(_audio.sfx_count(&"cash_chime")).is_equal(1)
	flights.free()


func test_game_menu_settings_sliders_init_from_saved_state_and_save_once_on_drag_end() -> void:
	_audio.set_master_volume(0.30)
	_audio.set_ambience_volume(0.45)
	_audio.set_sfx_volume(0.65)
	_audio.set_muted(true)
	var saves_before := _audio.save_count

	var kit := IncidentPanelKit.new()
	kit.build(self)
	var menu := GameMenu.new()
	menu.director = kit.director
	menu.clock = kit.clock
	menu.save_game = kit.save
	kit.port.add_child(menu)
	assert_bool(menu.open()).is_true()
	assert_bool(menu.audio_card.visible).is_false()
	menu.press_settings()
	assert_bool(menu.audio_card.visible).is_true()

	# Reverse sync: controls initialize to the pre-existing non-default values.
	assert_float(menu.audio_card.master_slider().value).is_equal_approx(30.0, 0.01)
	assert_float(menu.audio_card.ambience_slider().value).is_equal_approx(45.0, 0.01)
	assert_float(menu.audio_card.sfx_slider().value).is_equal_approx(65.0, 0.01)
	assert_bool(menu.audio_card.mute_switch().button_pressed).is_true()
	assert_int(_audio.save_count).is_equal(saves_before)

	# Dragging updates AudioServer live without writing disk until drag_ended.
	var master_idx := AudioServer.get_bus_index(&"Master")
	var slider := menu.audio_card.master_slider()
	slider.drag_started.emit()
	slider.value = 40.0
	slider.value = 55.0
	slider.value = 70.0
	assert_float(AudioServer.get_bus_volume_db(master_idx)).is_equal_approx(
		linear_to_db(0.70), 0.05
	)
	assert_int(_audio.save_count).is_equal(saves_before)
	slider.drag_ended.emit(true)
	assert_int(_audio.save_count).is_equal(saves_before + 1)

	menu.audio_card.ambience_slider().value = 50.0
	menu.audio_card.sfx_slider().value = 90.0
	menu.audio_card.mute_switch().button_pressed = false
	menu.press_back()
	assert_bool(menu.audio_card.visible).is_false()
	kit.port.free()

	_audio.load_settings(_cfg_path)
	assert_float(_audio.master_volume).is_equal_approx(0.70, 0.001)
	assert_float(_audio.ambience_volume).is_equal_approx(0.50, 0.001)
	assert_float(_audio.sfx_volume).is_equal_approx(0.90, 0.001)
	assert_bool(_audio.muted).is_false()


func test_title_screen_audio_card_inits_from_saved_state_toggles_and_syncs() -> void:
	_audio.set_master_volume(0.25)
	_audio.set_ambience_volume(0.55)
	_audio.set_sfx_volume(0.85)
	_audio.set_muted(true)

	SaveSlots.dir = _title_dir
	DirAccess.make_dir_recursive_absolute(_title_dir)
	var port := SubViewport.new()
	port.size = Vector2i(1920, 1080)
	add_child(port)
	var title := TitleScreen.new()
	title.change_scene = func(_scene: String) -> Error: return OK
	title.quit_game = func() -> void: pass
	port.add_child(title)

	assert_object(title.button("Audio")).is_not_null()
	assert_bool(title.audio_card.visible).is_false()
	title.button("Audio").pressed.emit()
	assert_bool(title.audio_card.visible).is_true()

	# Reverse sync: sliders and mute reflect pre-existing GameAudio state on open.
	assert_float(title.audio_card.master_slider().value).is_equal_approx(25.0, 0.01)
	assert_float(title.audio_card.ambience_slider().value).is_equal_approx(55.0, 0.01)
	assert_float(title.audio_card.sfx_slider().value).is_equal_approx(85.0, 0.01)
	assert_bool(title.audio_card.mute_switch().button_pressed).is_true()

	title.audio_card.master_slider().value = 60.0
	title.audio_card.ambience_slider().value = 20.0
	title.audio_card.sfx_slider().value = 75.0
	title.audio_card.mute_switch().button_pressed = false
	assert_float(_audio.master_volume).is_equal_approx(0.60, 0.001)
	assert_float(_audio.ambience_volume).is_equal_approx(0.20, 0.001)
	assert_float(_audio.sfx_volume).is_equal_approx(0.75, 0.001)
	assert_bool(_audio.muted).is_false()

	title.press_load()
	assert_bool(title.audio_card.visible).is_false()
	assert_bool(title.button("Audio").is_visible_in_tree()).is_false()
	title.press_back()
	assert_bool(title.button("Audio").is_visible_in_tree()).is_true()
	port.free()


func test_all_eight_new_wav_cues_load_and_pa_player_routes_to_sfx() -> void:
	assert_int(GAME_AUDIO.POOL_SIZE).is_equal(8)
	var pa_player := _audio.get_node_or_null("PAPlayer") as AudioStreamPlayer
	assert_object(pa_player).is_not_null()
	assert_str(String(pa_player.bus)).is_equal("SFX")
	var expected := [
		&"security_beep",
		&"pa_chime",
		&"pa_final_call",
		&"close_call_save",
		&"joke_spill",
		&"joke_fault",
		&"joke_queue_horn",
		&"star_up",
	]
	for cue_id: StringName in expected:
		var stream := load(GAME_AUDIO.SFX_PATHS[cue_id]) as AudioStreamWAV
		assert_object(stream).override_failure_message("Missing stream %s" % cue_id).is_not_null()
		assert_float(stream.get_length()).is_greater(0.05)
		assert_bool(_audio.play_sfx(cue_id)).is_true()
		assert_int(_audio.sfx_count(cue_id)).is_equal(1)


func test_security_beep_fires_only_on_security_to_gate_with_cooldown() -> void:
	var sim := PassengerSim.new()
	add_child(sim)
	# Non-security transitions do not trigger security_beep.
	sim.stage_changed.emit(1, Passenger.Stage.SPAWNED)
	sim.stage_changed.emit(1, Passenger.Stage.TO_CHECKIN)
	sim.stage_changed.emit(1, Passenger.Stage.CHECKIN)
	sim.stage_changed.emit(1, Passenger.Stage.TO_SECURITY)
	sim.stage_changed.emit(1, Passenger.Stage.SECURITY)
	assert_int(_audio.sfx_count(&"security_beep")).is_equal(0)

	# Leaving SECURITY for TO_GATE fires security_beep once; second passenger hits 1400 ms cooldown.
	sim.stage_changed.emit(1, Passenger.Stage.TO_GATE)
	assert_int(_audio.sfx_count(&"security_beep")).is_equal(1)
	assert_str(String(_audio.last_sfx())).is_equal("security_beep")

	sim.stage_changed.emit(2, Passenger.Stage.SECURITY)
	sim.stage_changed.emit(2, Passenger.Stage.TO_GATE)
	assert_int(_audio.sfx_count(&"security_beep")).is_equal(1)
	sim.free()


func test_boarding_final_call_dedupe_and_suppression_gates() -> void:
	var clock := SimClock.new()
	clock.set_paused(false)
	add_child(clock)
	var flights := FlightSim.new()
	flights.clock = clock
	flights.add_flight("TEST1", PassengerTestWorld.starts_with(10, 1000), "C")
	add_child(flights)
	var announced: Array[String] = []
	var on_pa := func(text: String) -> void: announced.append(text)
	_audio.pa_announced.connect(on_pa)

	# First BOARDING state emits boarding PA once; duplicate emit is ignored.
	flights.state_changed.emit("TEST1", FlightSim.State.BOARDING)
	assert_int(_audio.sfx_count(&"pa_chime")).is_equal(1)
	assert_int(announced.size()).is_equal(1)
	assert_str(announced[0]).contains("TEST1")
	flights.state_changed.emit("TEST1", FlightSim.State.BOARDING)
	assert_int(announced.size()).is_equal(1)

	# Paused clock suppresses PA announcement.
	_audio.reset_for_test()
	_audio.set_settings_path(_cfg_path)
	clock.set_paused(true)
	flights.state_changed.emit("TEST1", FlightSim.State.BOARDING)
	assert_int(_audio.sfx_count(&"pa_chime")).is_equal(0)
	assert_int(announced.size()).is_equal(1)

	# Fast-forward suppresses PA announcement.
	clock.set_paused(false)
	clock.fast_forward_source = func() -> int: return 500
	clock.advance(SimClock.STEP)
	assert_bool(clock.is_fast_forwarding()).is_true()
	_audio.reset_for_test()
	_audio.set_settings_path(_cfg_path)
	flights.state_changed.emit("TEST1", FlightSim.State.BOARDING)
	assert_int(_audio.sfx_count(&"pa_chime")).is_equal(0)
	assert_int(announced.size()).is_equal(1)
	clock.fast_forward_source = Callable()
	clock.fast_forward_until = -1

	# Muted / zero-volume suppresses PA announcement.
	_audio.reset_for_test()
	_audio.set_settings_path(_cfg_path)
	_audio.set_muted(true)
	flights.state_changed.emit("TEST1", FlightSim.State.BOARDING)
	assert_int(_audio.sfx_count(&"pa_chime")).is_equal(0)
	_audio.set_muted(false)
	_audio.reset_for_test()
	_audio.set_sfx_volume(0.0, false)
	flights.state_changed.emit("TEST1", FlightSim.State.BOARDING)
	assert_int(_audio.sfx_count(&"pa_chime")).is_equal(0)
	_audio.set_sfx_volume(GAME_AUDIO.DEFAULT_SFX, false)

	# Final-call check fires once per flight when doors close within 300 ticks.
	_audio.reset_for_test()
	var b_win := flights.boarding_window("TEST1")
	var snap := flights.to_snapshot()
	clock.tick = b_win.y - 250
	flights.tick = clock.tick
	# Snapshot load seeds already-boarding and already-final-call flights with zero retroactive PA.
	assert_bool(flights.from_snapshot(snap)).is_true()
	clock.ticked.emit(clock.tick)
	assert_int(_audio.sfx_count(&"pa_chime")).is_equal(0)
	assert_int(_audio.sfx_count(&"pa_final_call")).is_equal(0)
	assert_int(announced.size()).is_equal(1)

	# A fresh flight in BOARDING with >300 ticks left triggers final call once tick crosses window.
	_audio.reset_for_test()
	var fake_now := [10000]
	_audio._clock_ms = func() -> int: return fake_now[0]
	var flights2 := FlightSim.new()
	flights2.clock = clock
	clock.tick = 0
	flights2.add_flight("TEST2", PassengerTestWorld.starts_with(10, 1500), "C")
	flights2.add_flight("TEST3", PassengerTestWorld.starts_with(10, 1500), "C")
	add_child(flights2)
	var win2 := flights2.boarding_window("TEST2")
	while flights2.tick < win2.x:
		flights2.tick += 1
		flights2.on_tick(flights2.tick)
	assert_int(flights2.state_of("TEST2")).is_equal(FlightSim.State.BOARDING)
	assert_int(flights2.state_of("TEST3")).is_equal(FlightSim.State.BOARDING)
	# First boarding PA fired at fake_now=10000; advance past priority cooldown (+3000 ms).
	fake_now[0] = 13000
	var fc_tick := win2.y - 200
	clock.tick = fc_tick
	flights2.tick = fc_tick
	# TEST2 fires final call at 13000; TEST3 hits priority cooldown on the same tick (not lost).
	clock.ticked.emit(fc_tick)
	assert_int(_audio.sfx_count(&"pa_final_call")).is_equal(1)
	assert_int(announced.size()).is_equal(3)
	# +1000 ms later (14000): still within 2500 ms priority cooldown, TEST3 still deferred.
	fake_now[0] = 14000
	clock.ticked.emit(fc_tick + 10)
	assert_int(_audio.sfx_count(&"pa_final_call")).is_equal(1)
	# +3000 ms after TEST2's final call (16000) without clearing _last_played_ms: TEST3 retries.
	fake_now[0] = 16000
	clock.ticked.emit(fc_tick + 20)
	assert_int(_audio.sfx_count(&"pa_final_call")).is_equal(2)
	assert_int(announced.size()).is_equal(4)
	# Subsequent poll ticks do not re-announce either flight.
	fake_now[0] = 25000
	clock.ticked.emit(fc_tick + 30)
	assert_int(_audio.sfx_count(&"pa_final_call")).is_equal(2)

	# Deferred unsuppression after snapshot_loaded lets subsequent normal events play again.
	flights2.snapshot_loaded.emit()
	flights2.state_changed.emit("TEST4", FlightSim.State.DEPARTED)
	assert_int(_audio.sfx_count(&"cash_chime")).is_equal(0)
	await await_idle_frame()
	flights2.state_changed.emit("TEST4", FlightSim.State.DEPARTED)
	assert_int(_audio.sfx_count(&"cash_chime")).is_equal(1)

	_audio.pa_announced.disconnect(on_pa)
	flights2.free()
	flights.free()
	clock.free()


func test_close_call_save_fires_once_per_flight_and_skips_ontime_or_late_check() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 1200))
	world.clock.ticked.disconnect(world.flights.on_tick)
	add_child(world.flights)
	add_child(world.sim)
	var win := world.flights.boarding_window(PassengerTestWorld.FLIGHT)

	# Negative case: normal on-time boarding far before CLOSE_CALL_TICKS does NOT play close_call_save.
	world.run_to(win.x + 10)
	var on_time := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	on_time.late = false
	PassengerLifecycle.finish(world.sim, on_time, true)
	assert_int(_audio.sfx_count(&"close_call_save")).is_equal(0)

	# Positive cc > prev_cc case: p.late == true even well before doors_close - CLOSE_CALL_TICKS.
	var late_saver := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	late_saver.late = true
	PassengerLifecycle.finish(world.sim, late_saver, true)
	assert_int(_audio.sfx_count(&"close_call_save")).is_equal(1)

	# Second close-call on same flight (within CLOSE_CALL_TICKS) is deduped per flight.
	world.run_to(win.y - 20)
	var late_saver2 := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	PassengerLifecycle.finish(world.sim, late_saver2, true)
	assert_int(_audio.sfx_count(&"close_call_save")).is_equal(1)
	world.free_all()


func test_incident_director_sound_jokes_rush_and_restore_unsuppression() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 1200))
	world.clock.set_paused(false)
	add_child(world.clock)
	var director := IncidentDirector.new()
	director.clock = world.clock
	director.flights = world.flights
	director.passengers = world.sim
	add_child(director)
	var announced: Array[String] = []
	var on_pa := func(text: String) -> void: announced.append(text)
	_audio.pa_announced.connect(on_pa)

	var fake_now := [10000]
	_audio._clock_ms = func() -> int: return fake_now[0]

	director.started.emit({"kind": IncidentCatalogue.SPILL})
	assert_int(_audio.sfx_count(&"joke_spill")).is_equal(1)
	assert_int(announced.size()).is_equal(1)

	fake_now[0] = 13000
	director.started.emit({"kind": IncidentCatalogue.FAULT})
	assert_int(_audio.sfx_count(&"joke_fault")).is_equal(1)
	assert_int(announced.size()).is_equal(2)

	# major_presented does NOT fire RUSH PA synchronously (avoids modal wipe).
	fake_now[0] = 20000
	director.major_presented.emit({"id": 7, "kind": IncidentCatalogue.RUSH})
	assert_int(_audio.sfx_count(&"pa_chime")).is_equal(0)
	assert_int(announced.size()).is_equal(2)

	# Announced RUSH for day 1 fires once when unpaused clock enters the rush day.
	var rush_start := GameCalendar.day_start(1, 0)
	var rush_until := GameCalendar.day_start(2, 0)
	var snap := {
		"save_version": IncidentSnapshot.SAVE_VERSION,
		"enabled": true,
		"last_rolled_day": 0,
		"next_major_day": 3,
		"next_id": 2,
		"incidents":
		[
			{
				"id": 1,
				"kind": IncidentCatalogue.RUSH,
				"roll_day": 0,
				"state": IncidentCatalogue.ANNOUNCED,
				"fire_tick": 100,
				"cell": [-1, -1],
				"mess_id": 0,
				"place": "",
				"outcome": "",
				"shown": true,
				"plan":
				{
					"flights": [{"flight": "TEST-d1", "extra": 6, "departs": rush_start + 100}],
					"total": 6,
					"until": rush_until,
				},
			}
		],
	}
	assert_bool(director.from_snapshot(snap)).is_true()
	# Restored suppresses synchronous sounds, then unsuppresses after deferred idle frame.
	director.started.emit({"kind": IncidentCatalogue.SPILL})
	assert_int(_audio.sfx_count(&"joke_spill")).is_equal(1)
	await await_idle_frame()
	fake_now[0] = 25000
	director.started.emit({"kind": IncidentCatalogue.SPILL})
	assert_int(_audio.sfx_count(&"joke_spill")).is_equal(2)
	assert_int(announced.size()).is_equal(3)

	fake_now[0] = 30000
	world.clock.tick = rush_start
	world.clock.ticked.emit(rush_start)
	assert_int(_audio.sfx_count(&"pa_chime")).is_equal(1)
	assert_int(announced.size()).is_equal(4)
	assert_str(announced[3]).is_equal(PaWords.rush())
	# Subsequent ticks on the rush day do not repeat the rush PA.
	fake_now[0] = 40000
	world.clock.tick = rush_start + 10
	world.clock.ticked.emit(rush_start + 10)
	assert_int(_audio.sfx_count(&"pa_chime")).is_equal(1)

	_audio.pa_announced.disconnect(on_pa)
	director.free()
	world.free_all()


func test_alert_stack_rising_edge_and_queue_horn_cooldown() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(10, 5))
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(2, 1), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 4), 3)
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	world.step()
	for i in 12:
		world.sim.spawn_now(PassengerTestWorld.FLIGHT)
		world.run_to(world.clock.tick + 12)
	world.run_to(world.clock.tick + 25)
	var path := SaveTestKit.run_path("audio_alert_rising_edge")
	var stack := AlertStack.new()
	stack.settings_path = path
	stack.sim = world.sim
	add_child(stack)
	var raised: Array[StringName] = []
	stack.alert_raised.connect(func(key: StringName) -> void: raised.append(key))

	var fake_now := [10000]
	_audio._clock_ms = func() -> int: return fake_now[0]

	stack.refresh()
	assert_array(raised).is_empty()
	world.run_to(world.clock.tick + AlertSources.QUEUE_HOLD_TICKS)
	stack.refresh()
	assert_array(raised).is_equal([AlertSources.QUEUE_CHECKIN])
	assert_int(_audio.sfx_count(&"joke_queue_horn")).is_equal(1)

	# Repeated refresh while active must not re-emit alert_raised or horn.
	stack.refresh()
	stack.refresh()
	assert_int(raised.size()).is_equal(1)
	assert_int(_audio.sfx_count(&"joke_queue_horn")).is_equal(1)

	# 15 s cooldown suppresses a second queue horn at +10 s, then allows it at +16 s.
	fake_now[0] = 20000
	stack.alert_raised.emit(AlertSources.QUEUE_SECURITY)
	assert_int(_audio.sfx_count(&"joke_queue_horn")).is_equal(1)
	fake_now[0] = 26000
	stack.alert_raised.emit(AlertSources.QUEUE_SECURITY)
	assert_int(_audio.sfx_count(&"joke_queue_horn")).is_equal(2)

	# Reset must not emit alert_raised.
	var before_reset := raised.size()
	stack.reset()
	assert_int(raised.size()).is_equal(before_reset)

	stack.free()
	DirAccess.remove_absolute(path)
	world.free_all()


func test_airport_rating_milestone_chime_only_on_upward_crossing() -> void:
	var rating := AirportRating.new()
	add_child(rating)

	# Initial passengers bring has_data() from false -> true: no chime on initial data.
	rating.record_passenger(0, false, PassengerSim.MOOD_MAX)
	rating.record_passenger(0, false, PassengerSim.MOOD_MAX)
	assert_bool(rating.has_data()).is_true()
	assert_float(rating.stars()).is_less(3.0)
	assert_int(_audio.sfx_count(&"star_up")).is_equal(0)

	# Adding made passengers raises stars past 3.0 -> triggers star_up once.
	for i in 3:
		rating.record_passenger(0, true, PassengerSim.MOOD_MAX)
	assert_float(rating.stars()).is_greater_equal(3.0)
	assert_int(_audio.sfx_count(&"star_up")).is_equal(1)

	# Dropping below 3.0 must NOT trigger star_up.
	for i in 12:
		rating.record_passenger(0, false, PassengerSim.MOOD_MAX)
	assert_float(rating.stars()).is_less(3.0)
	assert_int(_audio.sfx_count(&"star_up")).is_equal(1)
	rating.free()


func test_phone_ring_wav_loads_plays_on_sfx_bus_and_respects_cooldown() -> void:
	var stream := load(GAME_AUDIO.SFX_PATHS[&"phone_ring"]) as AudioStreamWAV
	assert_object(stream).is_not_null()
	assert_float(stream.get_length()).is_between(1.8, 2.4)

	var fake_now := [10000]
	_audio._clock_ms = func() -> int: return fake_now[0]
	assert_bool(_audio.play_sfx(&"phone_ring")).is_true()
	assert_str(String(_audio.last_sfx())).is_equal("phone_ring")
	assert_int(_audio.sfx_count(&"phone_ring")).is_equal(1)

	# stop_sfx silences the active phone_ring player without altering sfx_count.
	_audio.stop_sfx(&"phone_ring")
	for player in _audio._sfx_players:
		if player.stream == stream:
			assert_bool(player.playing).is_false()
	assert_int(_audio.sfx_count(&"phone_ring")).is_equal(1)

	# Within cooldown (200 ms) a duplicate trigger is suppressed.
	fake_now[0] = 10050
	assert_bool(_audio.play_sfx(&"phone_ring")).is_false()
	assert_int(_audio.sfx_count(&"phone_ring")).is_equal(1)

	# After cooldown elapses it plays again.
	fake_now[0] = 10300
	assert_bool(_audio.play_sfx(&"phone_ring")).is_true()
	assert_int(_audio.sfx_count(&"phone_ring")).is_equal(2)
