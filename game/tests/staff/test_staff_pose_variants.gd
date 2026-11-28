class_name TestStaffPoseVariants
extends GdUnitTestSuite
## Pure unit regression tests for multi-variant StaffStationPose cycle
## selection, idle fidget buckets, backward-tick reset (6d949060), and
## StaffHandProps.desired_prop() gating.


func test_checkin_cycles_all_three_variants_and_prop_window() -> void:
	var seen := {}
	var prop_on := 0
	var prop_off := 0
	for step in 12:
		var tick := float(step) * StaffStationPose.CHECKIN_CYCLE_SEC * float(SimClock.TICK_RATE)
		var v := StaffStationPose.checkin_variant(tick + 40.0, 3)
		seen[v] = true
		for phase_tick in [10.0, 62.0]:
			if StaffStationPose.checkin_prop_active(tick + phase_tick, 3):
				prop_on += 1
			else:
				prop_off += 1
	assert_int(seen.size()).is_equal(3)
	assert_int(prop_on).is_greater(0)
	assert_int(prop_off).is_greater(0)


func test_different_seeds_start_on_distinct_checkin_and_fidget_variants() -> void:
	var checkin_variants := {}
	var fidget_variants := {}
	var elapsed := float(StaffStationPose.IDLE_SETTLE_TICKS + 20)
	for sid in range(1, 10):
		checkin_variants[StaffStationPose.checkin_variant(20.0, sid)] = true
		fidget_variants[StaffStationPose.idle_fidget_variant(sid, elapsed)] = true
	assert_int(checkin_variants.size()).is_equal(3)
	assert_int(fidget_variants.size()).is_equal(4)


func test_cafe_cup_active_alternates_between_pour_and_wipe_beats() -> void:
	var saw_on := false
	var saw_off := false
	for step in 6:
		var tick := float(step) * StaffStationPose.SHOP_CYCLE_SEC * float(SimClock.TICK_RATE) + 20.0
		if StaffStationPose.cafe_cup_active(tick, 5):
			saw_on = true
		else:
			saw_off = true
	assert_bool(saw_on).is_true()
	assert_bool(saw_off).is_true()


func test_idle_fidget_record_respects_settle_pauses_and_backward_tick_load_reset() -> void:
	var rec := {}
	# First sync on tick 100 starts idle_since = 100, settled at Mode.NONE.
	StaffStationPose.update(
		rec, StaffStationPose.Mode.NONE, Vector2.ZERO, 100.0, StaffStationPose.SubMode.NONE, true, 1
	)
	assert_int(StaffStationPose.mode_of(rec)).is_equal(StaffStationPose.Mode.NONE)
	assert_float(StaffStationPose.weight_of(rec, 100.0)).is_equal(0.0)

	# Before IDLE_SETTLE_TICKS elapses, stays Mode.NONE.
	StaffStationPose.update(
		rec, StaffStationPose.Mode.NONE, Vector2.ZERO, 115.0, StaffStationPose.SubMode.NONE, true, 1
	)
	assert_int(StaffStationPose.mode_of(rec)).is_equal(StaffStationPose.Mode.NONE)

	# Later in an active fidget window, enters IDLE_FIDGET.
	var entered := false
	for tick in range(180, 420):
		(
			StaffStationPose
			. update(
				rec,
				StaffStationPose.Mode.NONE,
				Vector2.ZERO,
				float(tick),
				StaffStationPose.SubMode.NONE,
				true,
				1,
			)
		)
		if StaffStationPose.mode_of(rec) == StaffStationPose.Mode.IDLE_FIDGET:
			entered = true
			break
	assert_bool(entered).is_true()

	# Walking / arch tuck (can_fidget = false) eases fidget out and resets idle_since.
	var pause_tick := float(rec["idle_since"]) + 300.0
	StaffStationPose.update(
		rec,
		StaffStationPose.Mode.NONE,
		Vector2.ZERO,
		pause_tick,
		StaffStationPose.SubMode.NONE,
		false,
		1
	)
	assert_bool(bool(rec["active"])).is_false()
	assert_float(float(rec["idle_since"])).is_equal(pause_tick)
	StaffStationPose.update(
		rec,
		StaffStationPose.Mode.NONE,
		Vector2.ZERO,
		pause_tick + StaffStationPose.EASE_TICKS,
		StaffStationPose.SubMode.NONE,
		false,
		1
	)
	assert_int(StaffStationPose.mode_of(rec)).is_equal(StaffStationPose.Mode.NONE)

	# Backward tick (e.g. save load to tick 50 before record's since/idle_since) reads settled
	# and restarts idle_since cleanly without stale future-tick clamping (6d949060).
	assert_float(StaffStationPose.weight_of(rec, 50.0)).is_equal(0.0)
	StaffStationPose.update(
		rec, StaffStationPose.Mode.NONE, Vector2.ZERO, 50.0, StaffStationPose.SubMode.NONE, true, 1
	)
	assert_float(float(rec["idle_since"])).is_equal(50.0)
	assert_int(StaffStationPose.mode_of(rec)).is_equal(StaffStationPose.Mode.NONE)


func test_hand_prop_gating_rules_across_modes_walking_and_tuck() -> void:
	var sec_wand := (
		StaffHandProps
		. desired_prop(
			StaffStationPose.Mode.SECURITY_SCAN,
			StaffStationPose.SubMode.SEC_ALARM,
			1.0,
			20.0,
			1,
			false,
			false,
		)
	)
	assert_int(sec_wand).is_equal(StaffHandProps.PropKind.WAND)

	var gate_pass := StaffHandProps.desired_prop(
		StaffStationPose.Mode.GATE, StaffStationPose.SubMode.NONE, 1.0, 20.0, 1, false, false
	)
	assert_int(gate_pass).is_equal(StaffHandProps.PropKind.BOARDING_PASS)

	var info_board := (
		StaffHandProps
		. desired_prop(
			StaffStationPose.Mode.SHOP,
			StaffStationPose.SubMode.SHOP_INFO_DESK,
			1.0,
			20.0,
			1,
			false,
			false,
		)
	)
	assert_int(info_board).is_equal(StaffHandProps.PropKind.CLIPBOARD)

	var retail_none := (
		StaffHandProps
		. desired_prop(
			StaffStationPose.Mode.SHOP,
			StaffStationPose.SubMode.SHOP_RETAIL,
			1.0,
			20.0,
			1,
			false,
			false,
		)
	)
	assert_int(retail_none).is_equal(StaffHandProps.PropKind.NONE)

	# Hidden while walking, tucked, idle fidget, or low weight.
	(
		assert_int(
			(
				StaffHandProps
				. desired_prop(
					StaffStationPose.Mode.SECURITY_SCAN,
					StaffStationPose.SubMode.SEC_CLEAN,
					1.0,
					20.0,
					1,
					true,
					false,
				)
			)
		)
		. is_equal(StaffHandProps.PropKind.NONE)
	)
	(
		assert_int(
			(
				StaffHandProps
				. desired_prop(
					StaffStationPose.Mode.SECURITY_SCAN,
					StaffStationPose.SubMode.SEC_CLEAN,
					1.0,
					20.0,
					1,
					false,
					true,
				)
			)
		)
		. is_equal(StaffHandProps.PropKind.NONE)
	)
	(
		assert_int(
			(
				StaffHandProps
				. desired_prop(
					StaffStationPose.Mode.IDLE_FIDGET,
					StaffStationPose.SubMode.NONE,
					1.0,
					20.0,
					1,
					false,
					false,
				)
			)
		)
		. is_equal(StaffHandProps.PropKind.NONE)
	)
	(
		assert_int(
			StaffHandProps.desired_prop(
				StaffStationPose.Mode.GATE,
				StaffStationPose.SubMode.NONE,
				0.2,
				20.0,
				1,
				false,
				false
			)
		)
		. is_equal(StaffHandProps.PropKind.NONE)
	)


func test_idle_fidget_interruption_preserves_clock_and_backward_look_clears() -> void:
	var rec := {}
	StaffStationPose.update(
		rec, StaffStationPose.Mode.NONE, Vector2.ZERO, 100.0, StaffStationPose.SubMode.NONE, true, 1
	)
	var entered_tick := -1.0
	for tick in range(180, 420):
		(
			StaffStationPose
			. update(
				rec,
				StaffStationPose.Mode.NONE,
				Vector2.ZERO,
				float(tick),
				StaffStationPose.SubMode.NONE,
				true,
				1,
			)
		)
		if StaffStationPose.mode_of(rec) == StaffStationPose.Mode.IDLE_FIDGET:
			entered_tick = float(tick)
			break
	assert_float(entered_tick).is_greater(0.0)

	# 1. Interruption by can_fidget = false preserves original idle_since for ease-out.
	var pause_tick := entered_tick + 24.0
	(
		StaffStationPose
		. update(
			rec,
			StaffStationPose.Mode.NONE,
			Vector2.ZERO,
			pause_tick,
			StaffStationPose.SubMode.NONE,
			false,
			1,
		)
	)
	assert_int(StaffStationPose.mode_of(rec)).is_equal(StaffStationPose.Mode.IDLE_FIDGET)
	assert_float(float(rec["idle_since"])).is_equal(pause_tick)
	assert_float(StaffStationPose.idle_since_of(rec, pause_tick + 2.0)).is_equal(100.0)
	var mid_w := StaffStationPose.weight_of(rec, pause_tick + 2.0)
	assert_float(mid_w).is_greater(0.0)
	assert_float(mid_w).is_less(1.0)
	(
		StaffStationPose
		. update(
			rec,
			StaffStationPose.Mode.NONE,
			Vector2.ZERO,
			pause_tick + StaffStationPose.EASE_TICKS,
			StaffStationPose.SubMode.NONE,
			false,
			1,
		)
	)
	assert_int(StaffStationPose.mode_of(rec)).is_equal(StaffStationPose.Mode.NONE)
	assert_bool(rec.has("xfade_idle_since")).is_false()

	# 2. Interruption by station mode preserves fidget clock through xfade_mode == IDLE_FIDGET.
	rec.clear()
	StaffStationPose.update(
		rec, StaffStationPose.Mode.NONE, Vector2.ZERO, 100.0, StaffStationPose.SubMode.NONE, true, 1
	)
	var work_tick := entered_tick + 24.0
	(
		StaffStationPose
		. update(
			rec,
			StaffStationPose.Mode.NONE,
			Vector2.ZERO,
			entered_tick,
			StaffStationPose.SubMode.NONE,
			true,
			1,
		)
	)
	(
		StaffStationPose
		. update(
			rec,
			StaffStationPose.Mode.CHECKIN,
			Vector2(20.0, 4.0),
			work_tick,
			StaffStationPose.SubMode.NONE,
			false,
			1,
		)
	)
	assert_bool(rec.has("idle_since")).is_false()
	assert_int(StaffStationPose.xfade_mode_of(rec)).is_equal(StaffStationPose.Mode.IDLE_FIDGET)
	assert_float(StaffStationPose.idle_since_of(rec, work_tick + 2.0)).is_equal(100.0)
	assert_float(StaffStationPose.crossfade_out(rec, work_tick + 2.0)).is_greater(0.0)
	(
		StaffStationPose
		. update(
			rec,
			StaffStationPose.Mode.CHECKIN,
			Vector2(20.0, 4.0),
			work_tick + StaffStationPose.TRANSITION_TICKS,
			StaffStationPose.SubMode.NONE,
			false,
			1,
		)
	)
	assert_int(StaffStationPose.xfade_mode_of(rec)).is_equal(StaffStationPose.Mode.NONE)
	assert_bool(rec.has("xfade_idle_since")).is_false()

	# 3. Backward tick clears look_since and look_from even when look_target matches (6d949060).
	assert_bool(rec.has("look_since")).is_true()
	assert_bool(rec.has("look_from")).is_true()
	(
		StaffStationPose
		. update(
			rec,
			StaffStationPose.Mode.CHECKIN,
			Vector2(20.0, 4.0),
			50.0,
			StaffStationPose.SubMode.NONE,
			false,
			1,
		)
	)
	assert_bool(rec.has("look_since")).is_false()
	assert_bool(rec.has("look_from")).is_false()

	# 4. Alarm inspect modes cycle WAND, PATDOWN, BOTH and hide wand during SEC_PATDOWN.
	var kinds := {}
	for pid in [1, 2, 3]:
		kinds[StaffStationPose.alarm_inspect_kind(pid)] = true
	assert_int(kinds.size()).is_equal(3)
	(
		assert_int(
			StaffHandProps.desired_prop(
				StaffStationPose.Mode.SECURITY_SCAN,
				StaffStationPose.SubMode.SEC_PATDOWN,
				1.0,
				10.0,
				1,
				false,
				false
			)
		)
		. is_equal(StaffHandProps.PropKind.NONE)
	)
	(
		assert_int(
			StaffHandProps.desired_prop(
				StaffStationPose.Mode.SECURITY_REPACK,
				StaffStationPose.SubMode.SEC_ALARM,
				1.0,
				10.0,
				1,
				false,
				false
			)
		)
		. is_equal(StaffHandProps.PropKind.WAND)
	)
