class_name TestInteractionSfx
extends GdUnitTestSuite
## Station interaction micro-SFX (decision staff-and-passenger-interaction-variety-
## package-b-procedural): WAV loading, generous calm-view cooldowns, quiet dB trim,
## read-only sim wiring for checkin_stamp, security_alarm vs security_clear
## (preserving security_beep backwards compatibility), gate_chirp, and cafe_clink,
## plus fast-forward and load suppression.

const GAME_AUDIO := preload("res://audio/game_audio.gd")

var _audio: GAME_AUDIO
var _cfg_path := ""


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_audio = get_node("/root/GameAudio") as GAME_AUDIO
	_cfg_path = SaveTestKit.run_path("interaction_sfx_settings").replace(".json", ".cfg")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_cfg_path))
	_audio.reset_for_test()
	_audio.set_settings_path(_cfg_path)


func after_test() -> void:
	if _audio != null:
		_audio.reset_for_test()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_cfg_path))


func test_all_five_interaction_wavs_load_play_with_quiet_trim_and_cooldowns() -> void:
	var cues: Array[StringName] = [
		&"checkin_stamp",
		&"security_alarm",
		&"security_clear",
		&"gate_chirp",
		&"cafe_clink",
	]
	var fake_now := [10000]
	_audio._clock_ms = func() -> int: return fake_now[0]

	for cue_id in cues:
		assert_bool(GAME_AUDIO.SFX_PATHS.has(cue_id)).is_true()
		var stream := load(GAME_AUDIO.SFX_PATHS[cue_id]) as AudioStreamWAV
		assert_object(stream).override_failure_message("Missing stream %s" % cue_id).is_not_null()
		assert_float(stream.get_length()).is_greater(0.05)

		var cooldown := int(GAME_AUDIO.SFX_COOLDOWN_MS.get(cue_id, 0))
		assert_int(cooldown).is_between(1500, 3000)
		var trim_db := float(GAME_AUDIO.SFX_VOLUME_DB.get(cue_id, 0.0))
		assert_float(trim_db).is_less(0.0)

		assert_bool(_audio.play_sfx(cue_id)).is_true()
		assert_str(String(_audio.last_sfx())).is_equal(String(cue_id))
		assert_int(_audio.sfx_count(cue_id)).is_equal(1)

		var last_idx := (_audio._sfx_cursor + GAME_AUDIO.POOL_SIZE - 1) % GAME_AUDIO.POOL_SIZE
		var player := _audio._sfx_players[last_idx]
		assert_str(String(player.bus)).is_equal("SFX")
		assert_float(player.volume_db).is_equal_approx(trim_db, 0.01)

		# Immediate repeat inside cooldown is gated.
		fake_now[0] += cooldown - 100
		assert_bool(_audio.play_sfx(cue_id)).is_false()
		assert_int(_audio.sfx_count(cue_id)).is_equal(1)

		# Once cooldown elapses, cue plays again.
		fake_now[0] += 150
		assert_bool(_audio.play_sfx(cue_id)).is_true()
		assert_int(_audio.sfx_count(cue_id)).is_equal(2)
		fake_now[0] += 5000


func test_checkin_stamp_and_gate_chirp_wire_to_sim_with_cooldown_and_ff_gate() -> void:
	var clock := SimClock.new()
	clock.set_paused(false)
	add_child(clock)
	var sim := PassengerSim.new()
	sim.clock = clock
	add_child(sim)

	var fake_now := [10000]
	_audio._clock_ms = func() -> int: return fake_now[0]

	# Check-in completion signal fires checkin_stamp once per cooldown window.
	sim.checked_in.emit(1, 10)
	assert_int(_audio.sfx_count(&"checkin_stamp")).is_equal(1)
	assert_str(String(_audio.last_sfx())).is_equal("checkin_stamp")
	fake_now[0] = 10500
	sim.checked_in.emit(2, 10)
	assert_int(_audio.sfx_count(&"checkin_stamp")).is_equal(1)
	fake_now[0] = 12000
	sim.checked_in.emit(3, 11)
	assert_int(_audio.sfx_count(&"checkin_stamp")).is_equal(2)

	# Gate pass transition to APRON fires gate_chirp once per cooldown window;
	# walking to exit (TO_EXIT) does not fire gate_chirp.
	sim.stage_changed.emit(1, Passenger.Stage.TO_EXIT)
	assert_int(_audio.sfx_count(&"gate_chirp")).is_equal(0)
	sim.stage_changed.emit(1, Passenger.Stage.APRON)
	assert_int(_audio.sfx_count(&"gate_chirp")).is_equal(1)
	assert_str(String(_audio.last_sfx())).is_equal("gate_chirp")

	fake_now[0] = 12500
	sim.stage_changed.emit(2, Passenger.Stage.TO_EXIT)
	sim.stage_changed.emit(2, Passenger.Stage.APRON)
	assert_int(_audio.sfx_count(&"gate_chirp")).is_equal(1)

	fake_now[0] = 14000
	sim.stage_changed.emit(3, Passenger.Stage.TO_EXIT)
	sim.stage_changed.emit(3, Passenger.Stage.APRON)
	assert_int(_audio.sfx_count(&"gate_chirp")).is_equal(2)

	# Fast-forward suppresses sim micro-SFX.
	clock.fast_forward_source = func() -> int: return 500
	clock.advance(SimClock.STEP)
	assert_bool(clock.is_fast_forwarding()).is_true()
	fake_now[0] = 20000
	sim.checked_in.emit(4, 10)
	sim.stage_changed.emit(4, Passenger.Stage.APRON)
	assert_int(_audio.sfx_count(&"checkin_stamp")).is_equal(2)
	assert_int(_audio.sfx_count(&"gate_chirp")).is_equal(2)

	sim.free()
	clock.free()


func test_security_alarm_vs_security_clear_and_backwards_compat_security_beep() -> void:
	var clock := SimClock.new()
	clock.set_paused(false)
	add_child(clock)
	var sim := PassengerSim.new()
	sim.clock = clock
	add_child(sim)

	var fake_now := [10000]
	_audio._clock_ms = func() -> int: return fake_now[0]

	# Clean passenger clearing SECURITY -> TO_GATE triggers security_clear (not alarm/beep).
	var clean_p := Passenger.new()
	clean_p.id = 1
	clean_p.alarm = false
	clean_p.liquids = false
	sim._passengers.append(clean_p)
	sim._by_id[clean_p.id] = clean_p
	sim.stage_changed.emit(clean_p.id, Passenger.Stage.SECURITY)
	sim.stage_changed.emit(clean_p.id, Passenger.Stage.TO_GATE)
	assert_int(_audio.sfx_count(&"security_clear")).is_equal(1)
	assert_int(_audio.sfx_count(&"security_alarm")).is_equal(0)
	assert_int(_audio.sfx_count(&"security_beep")).is_equal(0)

	# Liquids-only passenger also clears with security_clear, not security_alarm.
	fake_now[0] = 13000
	var liquids_p := Passenger.new()
	liquids_p.id = 2
	liquids_p.alarm = false
	liquids_p.liquids = true
	sim._passengers.append(liquids_p)
	sim._by_id[liquids_p.id] = liquids_p
	sim.stage_changed.emit(liquids_p.id, Passenger.Stage.SECURITY)
	sim.stage_changed.emit(liquids_p.id, Passenger.Stage.TO_GATE)
	assert_int(_audio.sfx_count(&"security_clear")).is_equal(2)
	assert_int(_audio.sfx_count(&"security_alarm")).is_equal(0)

	# Alarm passenger triggers security_alarm immediately on entering TO_BERTH/REPACK,
	# then once repacked and cleared through SECURITY -> TO_GATE plays security_clear
	# without repeating security_alarm.
	fake_now[0] = 16000
	var alarm_p := Passenger.new()
	alarm_p.id = 3
	alarm_p.alarm = true
	alarm_p.stage = Passenger.Stage.SECURITY
	alarm_p.security_phase = SecurityRuntime.Phase.TO_BERTH
	sim._passengers.append(alarm_p)
	sim._by_id[alarm_p.id] = alarm_p
	sim.security.records[7] = {"admitted": [alarm_p.id], "returns": [], "main": 0, "berth": 3}
	sim.stage_changed.emit(alarm_p.id, Passenger.Stage.SECURITY)
	clock.ticked.emit(1)
	assert_int(_audio.sfx_count(&"security_alarm")).is_equal(1)
	assert_int(_audio.sfx_count(&"security_clear")).is_equal(2)

	# Subsequent ticks in REPACK do not re-trigger alarm for the same passenger.
	fake_now[0] = 20000
	alarm_p.security_phase = SecurityRuntime.Phase.REPACK
	clock.ticked.emit(2)
	assert_int(_audio.sfx_count(&"security_alarm")).is_equal(1)

	# After repack resolves and passenger clears security, clear chime plays cleanly.
	alarm_p.incident_resolved = true
	alarm_p.security_phase = SecurityRuntime.Phase.NONE
	sim.security.records.erase(7)
	sim.stage_changed.emit(alarm_p.id, Passenger.Stage.TO_GATE)
	assert_int(_audio.sfx_count(&"security_alarm")).is_equal(1)
	assert_int(_audio.sfx_count(&"security_clear")).is_equal(3)

	# Backwards-compatible fallback: unknown id (p == null) keeps firing security_beep.
	fake_now[0] = 25000
	sim.stage_changed.emit(999, Passenger.Stage.SECURITY)
	sim.stage_changed.emit(999, Passenger.Stage.TO_GATE)
	assert_int(_audio.sfx_count(&"security_beep")).is_equal(1)

	sim.free()
	clock.free()


func test_cafe_clink_fires_on_served_order_and_walkon_paid_not_relocation_or_repay() -> void:
	var sim := PassengerSim.new()
	add_child(sim)
	var fake_now := [10000]
	_audio._clock_ms = func() -> int: return fake_now[0]

	# Seated order served: CAFE_ORDER -> CAFE_TO_SEAT fires cafe_clink.
	var p1 := Passenger.new()
	p1.id = 1
	p1.stage = Passenger.Stage.CAFE_ORDER
	sim._passengers.append(p1)
	sim._by_id[p1.id] = p1
	sim.stage_changed.emit(p1.id, Passenger.Stage.CAFE_ORDER)
	p1.stage = Passenger.Stage.CAFE_TO_SEAT
	sim.stage_changed.emit(p1.id, Passenger.Stage.CAFE_TO_SEAT)
	assert_int(_audio.sfx_count(&"cafe_clink")).is_equal(1)

	# Table relocation (CAFE_STANDING_UP -> CAFE_TO_SEAT) must NOT fire cafe_clink.
	fake_now[0] = 15000
	var p2 := Passenger.new()
	p2.id = 2
	p2.stage = Passenger.Stage.CAFE_STANDING_UP
	sim._passengers.append(p2)
	sim._by_id[p2.id] = p2
	sim.stage_changed.emit(p2.id, Passenger.Stage.CAFE_STANDING_UP)
	p2.stage = Passenger.Stage.CAFE_TO_SEAT
	sim.stage_changed.emit(p2.id, Passenger.Stage.CAFE_TO_SEAT)
	assert_int(_audio.sfx_count(&"cafe_clink")).is_equal(1)

	# Walk-on stall served & paid while still in CAFE_ORDER fires cafe_clink.
	var p3 := Passenger.new()
	p3.id = 3
	p3.stage = Passenger.Stage.CAFE_ORDER
	sim._passengers.append(p3)
	sim._by_id[p3.id] = p3
	sim.cafes.paid.emit(p3.id, 10, 12)
	assert_int(_audio.sfx_count(&"cafe_clink")).is_equal(2)

	# Seated guest paying later when standing up from CAFE_SEATED must NOT double-fire.
	fake_now[0] = 20000
	p1.stage = Passenger.Stage.CAFE_SEATED
	sim.cafes.paid.emit(p1.id, 10, 18)
	assert_int(_audio.sfx_count(&"cafe_clink")).is_equal(2)

	sim.free()


func test_snapshot_load_seeds_security_alarms_and_suppresses_retroactive_sfx() -> void:
	var clock := SimClock.new()
	clock.set_paused(false)
	add_child(clock)
	var flights := FlightSim.new()
	flights.clock = clock
	add_child(flights)
	var sim := PassengerSim.new()
	sim.clock = clock
	add_child(sim)

	var p := Passenger.new()
	p.id = 5
	p.alarm = true
	p.stage = Passenger.Stage.SECURITY
	p.security_phase = SecurityRuntime.Phase.REPACK
	sim._passengers.append(p)
	sim._by_id[p.id] = p
	sim.security.records[1] = {"admitted": [p.id], "returns": [], "main": p.id, "berth": 0}

	flights.snapshot_loaded.emit()
	clock.ticked.emit(1)
	sim.checked_in.emit(5, 1)
	sim.stage_changed.emit(5, Passenger.Stage.APRON)
	assert_int(_audio.sfx_count(&"security_alarm")).is_equal(0)
	assert_int(_audio.sfx_count(&"checkin_stamp")).is_equal(0)
	assert_int(_audio.sfx_count(&"gate_chirp")).is_equal(0)

	await await_idle_frame()
	# After unsuppression, the already-repacking passenger still does not retroactively alarm,
	# while a fresh check-in plays normally.
	clock.ticked.emit(2)
	assert_int(_audio.sfx_count(&"security_alarm")).is_equal(0)
	sim.checked_in.emit(6, 1)
	assert_int(_audio.sfx_count(&"checkin_stamp")).is_equal(1)

	sim.free()
	flights.free()
	clock.free()


func test_fast_forward_security_alarm_does_not_fire_retroactively_on_resume() -> void:
	var clock := SimClock.new()
	clock.set_paused(false)
	add_child(clock)
	var sim := PassengerSim.new()
	sim.clock = clock
	add_child(sim)

	var fake_now := [10000]
	_audio._clock_ms = func() -> int: return fake_now[0]

	clock.fast_forward_source = func() -> int: return 500
	clock.advance(SimClock.STEP)
	assert_bool(clock.is_fast_forwarding()).is_true()

	var ff_p := Passenger.new()
	ff_p.id = 10
	ff_p.alarm = true
	ff_p.stage = Passenger.Stage.SECURITY
	ff_p.security_phase = SecurityRuntime.Phase.REPACK
	sim._passengers.append(ff_p)
	sim._by_id[ff_p.id] = ff_p
	sim.security.records[1] = {"admitted": [ff_p.id], "returns": [], "main": 0, "berth": ff_p.id}
	clock.ticked.emit(clock.tick + 1)
	assert_int(_audio.sfx_count(&"security_alarm")).is_equal(0)

	# Exiting fast-forward while ff_p is still in REPACK must not trigger a delayed alarm.
	fake_now[0] = 15000
	clock.fast_forward_source = func() -> int: return -1
	clock.advance(SimClock.STEP)
	assert_bool(clock.is_fast_forwarding()).is_false()
	clock.ticked.emit(clock.tick + 1)
	assert_int(_audio.sfx_count(&"security_alarm")).is_equal(0)

	# A fresh alarm passenger entering REPACK at normal speed still plays security_alarm.
	var normal_p := Passenger.new()
	normal_p.id = 11
	normal_p.alarm = true
	normal_p.stage = Passenger.Stage.SECURITY
	normal_p.security_phase = SecurityRuntime.Phase.REPACK
	sim._passengers.append(normal_p)
	sim._by_id[normal_p.id] = normal_p
	sim.security.records[2] = {
		"admitted": [normal_p.id],
		"returns": [],
		"main": 0,
		"berth": normal_p.id,
	}
	clock.ticked.emit(clock.tick + 1)
	assert_int(_audio.sfx_count(&"security_alarm")).is_equal(1)

	sim.free()
	clock.free()


func test_rebinding_passenger_sim_disconnects_previous_live_instance() -> void:
	var clock := SimClock.new()
	clock.set_paused(false)
	add_child(clock)
	var sim_a := PassengerSim.new()
	sim_a.clock = clock
	add_child(sim_a)
	var sim_b := PassengerSim.new()
	sim_b.clock = clock
	add_child(sim_b)

	var fake_now := [10000]
	_audio._clock_ms = func() -> int: return fake_now[0]

	assert_object(_audio._passengers).is_same(sim_b)
	(
		assert_bool(sim_a.tree_exiting.is_connected(_audio._on_passenger_sim_exited.bind(sim_a)))
		. is_false()
	)

	var p_a := Passenger.new()
	p_a.id = 52
	p_a.alarm = true
	p_a.stage = Passenger.Stage.SECURITY
	sim_a._passengers.append(p_a)
	sim_a._by_id[p_a.id] = p_a

	var p_a_cafe := Passenger.new()
	p_a_cafe.id = 53
	p_a_cafe.stage = Passenger.Stage.CAFE_ORDER
	sim_a._passengers.append(p_a_cafe)
	sim_a._by_id[p_a_cafe.id] = p_a_cafe

	var p_b := Passenger.new()
	p_b.id = 50
	p_b.alarm = true
	p_b.stage = Passenger.Stage.SECURITY
	sim_b._passengers.append(p_b)
	sim_b._by_id[p_b.id] = p_b
	sim_b.stage_changed.emit(p_b.id, Passenger.Stage.SECURITY)
	assert_int(_audio._prev_stage.get(p_b.id, -1)).is_equal(Passenger.Stage.SECURITY)

	# Events on still-alive sim_a must neither play SFX nor mutate GameAudio tracking state.
	sim_a.checked_in.emit(p_a.id, 1)
	sim_a.stage_changed.emit(p_a.id, Passenger.Stage.SECURITY)
	sim_a.stage_changed.emit(p_a.id, Passenger.Stage.TO_GATE)
	sim_a.stage_changed.emit(p_a.id, Passenger.Stage.APRON)
	sim_a.cafes.paid.emit(p_a_cafe.id, 10, 12)
	sim_a.outcome.emit(p_b.id, true)

	assert_int(_audio.sfx_count(&"checkin_stamp")).is_equal(0)
	assert_int(_audio.sfx_count(&"security_alarm")).is_equal(0)
	assert_int(_audio.sfx_count(&"security_clear")).is_equal(0)
	assert_int(_audio.sfx_count(&"security_beep")).is_equal(0)
	assert_int(_audio.sfx_count(&"gate_chirp")).is_equal(0)
	assert_int(_audio.sfx_count(&"cafe_clink")).is_equal(0)
	assert_bool(_audio._prev_stage.has(p_a.id)).is_false()
	assert_bool(_audio._security_alarmed.has(p_a.id)).is_false()
	assert_int(_audio._prev_stage.get(p_b.id, -1)).is_equal(Passenger.Stage.SECURITY)

	# Events on sim_b continue playing and updating tracking state normally.
	var p_b_cafe := Passenger.new()
	p_b_cafe.id = 54
	p_b_cafe.stage = Passenger.Stage.CAFE_ORDER
	sim_b._passengers.append(p_b_cafe)
	sim_b._by_id[p_b_cafe.id] = p_b_cafe

	sim_b.checked_in.emit(p_b.id, 2)
	sim_b.stage_changed.emit(p_b.id, Passenger.Stage.TO_GATE)
	sim_b.stage_changed.emit(p_b.id, Passenger.Stage.APRON)
	sim_b.cafes.paid.emit(p_b_cafe.id, 10, 12)
	assert_int(_audio.sfx_count(&"checkin_stamp")).is_equal(1)
	assert_int(_audio.sfx_count(&"security_alarm")).is_equal(1)
	assert_int(_audio.sfx_count(&"gate_chirp")).is_equal(1)
	assert_int(_audio.sfx_count(&"cafe_clink")).is_equal(1)
	assert_bool(_audio._security_alarmed.has(p_b.id)).is_true()

	sim_b.outcome.emit(p_b.id, false)
	assert_bool(_audio._prev_stage.has(p_b.id)).is_false()
	assert_bool(_audio._security_alarmed.has(p_b.id)).is_false()

	sim_a.free()
	sim_b.free()
	clock.free()
