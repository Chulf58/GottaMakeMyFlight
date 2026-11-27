class_name TestTactileCleaningLoop
extends GdUnitTestSuite
## End-to-end tests for decision
## tactile-cleaning-loop-cleaner-poses-bag-to-bin-proactive-bin-empty-and-passenger-bin-use:
## bag-to-bin carry after cleaning, bin capacity 6 + >= 50% proactive emptying,
## forecast-safe passenger bin detour & toss, Mode.CLEANER + TRASH_BAG visuals,
## and save/load determinism + version rejection.

const CLEANER := StaffMember.Role.CLEANER
const OPEN_WORLD_DOOR := Vector2i(2, 19)

var _world: PassengerTestWorld
var _aux: PassengerTestWorld
var _views: StaffCharacters
var _pax_views: PassengerViews
var _undo: Array[BuildEdit] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
		_views = null
	if _pax_views != null:
		_pax_views.free()
		_pax_views = null
	for w in [_world, _aux]:
		if w != null:
			w.free_all()
	_world = null
	_aux = null
	_undo.clear()


func _open_world(seed := 1) -> PassengerTestWorld:
	var w := MessTestKit.open_world(seed)
	CleanerTestKit.reset(w)
	return w


func _make_cafe_world(seed := 17) -> Dictionary:
	var grid := BuildGrid.new()
	var ids := CafeTestLayout.build(grid, true)
	var at := ReferenceTerminal.offset_on(grid)
	var w := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(1500, 4000), seed)
	MessTestKit.clear(w)
	w.run_to(10)
	return {"world": w, "ids": ids, "at": at}


func _make_kiosk_world(seed := 19) -> Dictionary:
	var grid := BuildGrid.new()
	var ids := ShopTestLayout.build(grid, ["air"], 1)
	var at := ReferenceTerminal.offset_on(grid)
	var w := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(1500, 4000), seed)
	MessTestKit.clear(w)
	w.run_to(10)
	return {"world": w, "ids": ids, "at": at}


func test_cleaner_bags_mess_to_nearest_bin_then_exit_fallback_and_mid_carry_reroute() -> void:
	_world = _open_world(1)
	var bin := PassengerTestWorld.place(_world.grid, MessSim.BIN_ID, Vector2i(14, 10), 0)
	_world.sim.messes.add(MessSim.Kind.LITTER, Vector2i(20, 10))
	var m := CleanerTestKit.cleaner_at(_world, Vector2i(19, 10))
	# Step until mess is cleaned and cleaner begins carrying bag to the nearest bin.
	(
		assert_bool(
			CleanerTestKit.step_until(
				_world,
				func() -> bool:
					return (
						_world.sim.messes.mess_count() == 0
						and m.bag_carry == StaffMember.BagCarry.TO_BIN
					),
			)
		)
		. is_true()
	)
	assert_int(m.bag_target).is_equal(bin)
	assert_int(_world.sim.messes.fill_of(bin)).is_equal(0)
	# Walks to bin, pauses to toss bag, increments fill to 1, and returns IDLE.
	(
		assert_bool(
			CleanerTestKit.step_until(
				_world, func() -> bool: return m.state == StaffMember.State.IDLE
			)
		)
		. is_true()
	)
	assert_int(m.bag_carry).is_equal(StaffMember.BagCarry.NONE)
	assert_int(m.bag_target).is_equal(0)
	assert_int(_world.sim.messes.fill_of(bin)).is_equal(1)

	# Subcase B: with no non-full bin on the grid, cleaner walks the bag out to the entrance door.
	assert_bool(_world.grid.apply(BuildEdit.remove_object(bin)).ok).is_true()
	_world.sim.messes.add(MessSim.Kind.LITTER, Vector2i(20, 10))
	(
		assert_bool(
			CleanerTestKit.step_until(
				_world, func() -> bool: return m.bag_carry == StaffMember.BagCarry.TO_EXIT
			)
		)
		. is_true()
	)
	(
		assert_bool(
			CleanerTestKit.step_until(
				_world, func() -> bool: return m.state == StaffMember.State.IDLE
			)
		)
		. is_true()
	)
	assert_that(m.at).is_equal(OPEN_WORLD_DOOR)
	assert_int(m.bag_carry).is_equal(StaffMember.BagCarry.NONE)

	# Subcase C: remove target bin mid-carry -> reroutes cleanly to backup bin and delivers bag.
	var bin_a := PassengerTestWorld.place(_world.grid, MessSim.BIN_ID, Vector2i(15, 10), 0)
	var bin_b := PassengerTestWorld.place(_world.grid, MessSim.BIN_ID, Vector2i(8, 10), 0)
	_world.sim.messes.add(MessSim.Kind.LITTER, Vector2i(22, 10))
	(
		assert_bool(
			CleanerTestKit.step_until(
				_world,
				func() -> bool:
					return (
						m.bag_carry == StaffMember.BagCarry.TO_BIN
						and m.bag_target == bin_a
						and m.state == StaffMember.State.TO_STATION
					),
			)
		)
		. is_true()
	)
	assert_bool(_world.grid.apply(BuildEdit.remove_object(bin_a)).ok).is_true()
	_world.step()
	assert_int(m.bag_carry).is_equal(StaffMember.BagCarry.TO_BIN)
	assert_int(m.bag_target).is_equal(bin_b)
	(
		assert_bool(
			CleanerTestKit.step_until(
				_world, func() -> bool: return m.state == StaffMember.State.IDLE
			)
		)
		. is_true()
	)
	assert_int(_world.sim.messes.fill_of(bin_b)).is_equal(1)


func test_bin_capacity_6_and_proactive_half_full_bins_after_messes() -> void:
	assert_int(MessSim.BIN_CAPACITY).is_equal(6)
	assert_int(MessSim.BIN_EMPTY_MIN).is_equal(3)
	_world = _open_world(2)
	var half_bin := PassengerTestWorld.place(_world.grid, MessSim.BIN_ID, Vector2i(14, 10), 0)
	var full_bin := PassengerTestWorld.place(_world.grid, MessSim.BIN_ID, Vector2i(8, 10), 0)
	var messes := _world.sim.messes
	var snap := messes.to_snapshot()
	snap["bins"][str(half_bin)] = 2
	assert_bool(messes.from_snapshot(snap)).is_true()
	var m := CleanerTestKit.cleaner_at(_world, Vector2i(16, 10))
	for i in 25:
		_world.step()
	# Below 50% (2/6), idle cleaner leaves bin untouched.
	assert_int(m.job).is_equal(0)

	# Raise half_bin to 3/6 (>= 50%), ALSO add an active floor mess and a full bin 6/6.
	snap = messes.to_snapshot()
	snap["bins"][str(half_bin)] = MessSim.BIN_EMPTY_MIN
	snap["bins"][str(full_bin)] = MessSim.BIN_CAPACITY
	assert_bool(messes.from_snapshot(snap)).is_true()
	var mess_id := messes.add(MessSim.Kind.LITTER, Vector2i(20, 10))
	_world.step()
	# Priority order: active mess first.
	assert_int(m.job).is_equal(mess_id)
	assert_bool(m.job_bin).is_false()
	(
		assert_bool(
			CleanerTestKit.step_until(
				_world, func() -> bool: return m.state == StaffMember.State.IDLE
			)
		)
		. is_true()
	)
	# Bagged mess went into half_bin (now 4/6); next urgent job is full_bin (6/6).
	_world.step()
	assert_int(m.job).is_equal(full_bin)
	assert_bool(m.job_bin).is_true()
	(
		assert_bool(
			CleanerTestKit.step_until(
				_world,
				func() -> bool:
					return messes.fill_of(full_bin) == 0 and m.state == StaffMember.State.IDLE,
			)
		)
		. is_true()
	)
	# Now only proactive half_bin (>= 50%) remains: idle cleaner empties it & carries bag to exit.
	(
		assert_bool(
			CleanerTestKit.step_until(
				_world, func() -> bool: return m.job == half_bin and m.job_bin
			)
		)
		. is_true()
	)
	(
		assert_bool(
			CleanerTestKit.step_until(
				_world,
				func() -> bool:
					return (
						messes.fill_of(half_bin) == 0
						and m.bag_carry == StaffMember.BagCarry.TO_EXIT
					),
			)
		)
		. is_true()
	)
	(
		assert_bool(
			CleanerTestKit.step_until(
				_world, func() -> bool: return m.state == StaffMember.State.IDLE
			)
		)
		. is_true()
	)
	assert_int(messes.fill_of(half_bin)).is_equal(0)


func test_passenger_bin_detour_makes_flight_and_skips_when_tight() -> void:
	# Subcase A: Cafe visitor detours to bin within <= 6 cells, tosses, increments bin, makes flight.
	var setup := _make_cafe_world(31)
	_world = setup["world"]
	var at: Vector2i = setup["at"]
	var bin_cafe := PassengerTestWorld.place(
		_world.grid, MessSim.BIN_ID, CafeTestLayout.AIR_TABLE + Vector2i(-1, 2) + at, 0
	)
	var sim := _world.sim
	var p := _world.passenger(sim.spawn_now(PassengerTestWorld.FLIGHT))
	ShopTestLayout.to_airside(_world, p, 0, CafeTestLayout.AIR_COUNTER + Vector2i(0, 1) + at)
	p.cafe_cooldown = 0
	p.hunger = CafeSim.HUNGRY_AT
	assert_int(NeedsPolicy.arbitrate(sim, p)).is_equal(NeedsPolicy.Need.HUNGER)
	assert_bool(sim.cafes.visit_of(p.id) != null).is_true()

	var started_detour := CleanerTestKit.step_until(
		_world, func() -> bool: return p.bin_detour_bin == bin_cafe
	)
	assert_bool(started_detour).is_true()
	var paused_tossing := CleanerTestKit.step_until(
		_world, func() -> bool: return p.bin_detour_bin == bin_cafe and p.bin_detour_end > sim.tick
	)
	assert_bool(paused_tossing).is_true()
	assert_int(sim.messes.fill_of(bin_cafe)).is_equal(0)

	var doors := _world.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	(
		assert_bool(
			CleanerTestKit.step_until(
				_world, func() -> bool: return p.is_done(), doors - _world.clock.tick + 10
			)
		)
		. is_true()
	)
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)
	assert_int(sim.missed_count()).is_equal(0)
	assert_int(sim.messes.fill_of(bin_cafe)).is_equal(1)
	assert_int(sim.messes.mess_count()).is_equal(0)

	# Subcase B: Kiosk visitor detours cleanly when bin is near and time is ample,
	# and SKIPS detour when doors close tightly so flight is not missed.
	var ksetup := _make_kiosk_world(32)
	_aux = ksetup["world"]
	var kat: Vector2i = ksetup["at"]
	var k_bin := PassengerTestWorld.place(_aux.grid, MessSim.BIN_ID, Vector2i(23, 6) + kat, 0)
	var ksim := _aux.sim
	var p_ample := ShopTestLayout.airside_guest(
		_aux, BoredomSim.BORED_AT, ShopTestLayout.AIRSIDE_CELL + kat
	)
	assert_int(NeedsPolicy.arbitrate(ksim, p_ample)).is_equal(NeedsPolicy.Need.BOREDOM)
	assert_bool(ksim.shops.visit_of(p_ample.id) != null).is_true()
	(
		assert_bool(
			CleanerTestKit.step_until(_aux, func() -> bool: return p_ample.bin_detour_bin == k_bin)
		)
		. is_true()
	)
	(
		assert_bool(
			CleanerTestKit.step_until(_aux, func() -> bool: return ksim.messes.fill_of(k_bin) == 1)
		)
		. is_true()
	)
	var k_doors := _aux.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	(
		assert_bool(
			CleanerTestKit.step_until(
				_aux, func() -> bool: return p_ample.is_done(), k_doors - _aux.clock.tick + 10
			)
		)
		. is_true()
	)
	assert_int(p_ample.stage).is_equal(Passenger.Stage.MADE)

	# Fresh world at early clock checks tight-time bin detour skip.
	_aux.free_all()
	var tight_setup := _make_kiosk_world(33)
	_aux = tight_setup["world"]
	var tat: Vector2i = tight_setup["at"]
	PassengerTestWorld.place(_aux.grid, MessSim.BIN_ID, Vector2i(23, 6) + tat, 0)
	var tsim := _aux.sim
	var t_doors := _aux.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	var tight := ShopTestLayout.airside_guest(_aux, 0, ShopTestLayout.AIRSIDE_CELL + tat)
	var tight_plan := BinDetour.plan_from(tsim, tight, tight.at, Passenger.Stage.TO_GATE, 0)
	var direct_to_plane := (
		VisitForecast.arrival(tsim, tight, 0, tight.at, 0, Passenger.Stage.TO_GATE)
		- tight.boarding_tick
	)
	var jump_to := maxi(
		tight.boarding_tick, t_doors - (VisitForecast.MARGIN_TICKS + 15 + direct_to_plane)
	)
	_aux.run_to(jump_to)
	var tight_late := ShopTestLayout.airside_guest(_aux, 0, ShopTestLayout.AIRSIDE_CELL + tat)
	var skipped_plan := BinDetour.plan_from(
		tsim, tight_late, tight_late.at, Passenger.Stage.TO_GATE, 0
	)
	assert_bool(tight_plan.is_empty()).is_false()
	assert_bool(skipped_plan.is_empty()).is_true()
	assert_int(tight_late.bin_detour_bin).is_equal(0)


func test_cleaner_mode_poses_and_trash_bag_prop_attach_with_zero_orphans() -> void:
	_world = _open_world(3)
	var bin := PassengerTestWorld.place(_world.grid, MessSim.BIN_ID, Vector2i(14, 10), 0)
	var litter := _world.sim.messes.add(MessSim.Kind.LITTER, Vector2i(20, 10))
	var m := CleanerTestKit.cleaner_at(_world, Vector2i(19, 10))

	_views = StaffCharacters.new()
	_views.staff = _world.staff
	_views.clock = _world.clock
	add_child(_views)

	# 1) Sweeping LITTER -> Mode.CLEANER + SubMode.CLEANER_SWEEP + PropKind.BROOM.
	(
		assert_bool(
			CleanerTestKit.step_until(
				_world,
				func() -> bool: return m.state == StaffMember.State.ON_DUTY and m.job == litter
			)
		)
		. is_true()
	)
	_world.step()
	_views.draw()
	var node := _views.node_for(m.id)
	assert_object(node).is_not_null()
	var mod := node.find_children("*", "StaffStationPose", true, false)[0] as StaffStationPose
	assert_int(mod.mode).is_equal(StaffStationPose.Mode.CLEANER)
	assert_int(mod.sub_mode).is_equal(StaffStationPose.SubMode.CLEANER_SWEEP)
	assert_int(StaffHandProps.active_prop(node)).is_equal(StaffHandProps.PropKind.BROOM)

	# 2) Carrying bag TO_BIN -> Mode.CLEANER + CLEANER_BAG_CARRY + TRASH_BAG + bag_carry_arm active.
	(
		assert_bool(
			CleanerTestKit.step_until(
				_world,
				func() -> bool:
					return (
						m.bag_carry == StaffMember.BagCarry.TO_BIN
						and m.state == StaffMember.State.TO_STATION
					),
			)
		)
		. is_true()
	)
	_world.step()
	_views.draw()
	assert_int(mod.mode).is_equal(StaffStationPose.Mode.CLEANER)
	assert_int(mod.sub_mode).is_equal(StaffStationPose.SubMode.CLEANER_BAG_CARRY)
	assert_int(StaffHandProps.active_prop(node)).is_equal(StaffHandProps.PropKind.TRASH_BAG)
	var bag_arm := node.get_meta(StaffHandProps.BAG_CARRY_META) as CarryArm
	assert_object(bag_arm).is_not_null()
	assert_bool(bag_arm.active).is_true()
	if node.has_meta(StaffHandProps.BROOM_CARRY_META):
		assert_bool((node.get_meta(StaffHandProps.BROOM_CARRY_META) as CarryArm).active).is_false()

	# 3) Tossing bag at bin -> Mode.CLEANER + CLEANER_BAG_TOSS + TRASH_BAG + bag_carry_arm off.
	(
		assert_bool(
			CleanerTestKit.step_until(
				_world,
				func() -> bool:
					return (
						m.bag_carry == StaffMember.BagCarry.TO_BIN
						and m.state == StaffMember.State.ON_DUTY
					),
			)
		)
		. is_true()
	)
	_world.step()
	_views.draw()
	assert_int(mod.mode).is_equal(StaffStationPose.Mode.CLEANER)
	assert_int(mod.sub_mode).is_equal(StaffStationPose.SubMode.CLEANER_BAG_TOSS)
	assert_int(StaffHandProps.active_prop(node)).is_equal(StaffHandProps.PropKind.TRASH_BAG)
	assert_bool(bag_arm.active).is_false()

	# 4) Emptying a full bin -> Mode.CLEANER + CLEANER_BIN + PropKind.RAG.
	(
		assert_bool(
			CleanerTestKit.step_until(
				_world, func() -> bool: return m.state == StaffMember.State.IDLE
			)
		)
		. is_true()
	)
	var snap := _world.sim.messes.to_snapshot()
	snap["bins"][str(bin)] = MessSim.BIN_CAPACITY
	assert_bool(_world.sim.messes.from_snapshot(snap)).is_true()
	(
		assert_bool(
			CleanerTestKit.step_until(
				_world, func() -> bool: return m.state == StaffMember.State.ON_DUTY and m.job_bin
			)
		)
		. is_true()
	)
	_world.step()
	_views.draw()
	assert_int(mod.mode).is_equal(StaffStationPose.Mode.CLEANER)
	assert_int(mod.sub_mode).is_equal(StaffStationPose.SubMode.CLEANER_BIN)
	assert_int(StaffHandProps.active_prop(node)).is_equal(StaffHandProps.PropKind.RAG)

	# 5) PassengerViews + PassengerFidgetPose Mode.BIN_TOSS on passenger bin toss.
	var pbin := PassengerTestWorld.place(_world.grid, MessSim.BIN_ID, Vector2i(10, 10), 0)
	_pax_views = PassengerViews.new()
	_pax_views.sim = _world.sim
	_pax_views.clock = _world.clock
	add_child(_pax_views)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.at = _world.sim.messes.bin_approach(pbin)
	p.clear_path()
	p.bin_detour_bin = pbin
	p.bin_detour_end = _world.clock.tick + MessSim.BIN_TOSS_TICKS
	_world.step()
	_world.step()
	_world.step()
	_world.step()
	_pax_views.draw()
	var pnode := _pax_views.node_for(p.id)
	assert_object(pnode).is_not_null()
	var fmod := (
		pnode.find_children("*", "PassengerFidgetPose", true, false)[0] as PassengerFidgetPose
	)
	assert_bool(fmod.active).is_true()
	assert_int(fmod.mode).is_equal(PassengerFidgetPose.Mode.BIN_TOSS)

	_views.free()
	_views = null
	_pax_views.free()
	_pax_views = null


func test_save_load_mid_bag_and_bin_detour_determinism_and_old_reject() -> void:
	var setup := _make_cafe_world(44)
	_world = setup["world"]
	var at: Vector2i = setup["at"]
	var bin := PassengerTestWorld.place(
		_world.grid, MessSim.BIN_ID, CafeTestLayout.AIR_TABLE + Vector2i(-1, 2) + at, 0
	)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ShopTestLayout.to_airside(_world, p, 0, CafeTestLayout.AIR_COUNTER + Vector2i(0, 1) + at)
	p.cafe_cooldown = 0
	p.hunger = CafeSim.HUNGRY_AT
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.HUNGER)
	(
		assert_bool(
			CleanerTestKit.step_until(
				_world, func() -> bool: return p.stage == Passenger.Stage.CAFE_STANDING_UP
			)
		)
		. is_true()
	)
	var mess_spot := Vector2i(18, 6) + at
	_world.sim.messes.add(MessSim.Kind.LITTER, mess_spot)
	var cleaner := CleanerTestKit.cleaner_at(_world, mess_spot)
	(
		assert_bool(
			CleanerTestKit.step_until(
				_world,
				func() -> bool:
					return (
						cleaner.bag_carry == StaffMember.BagCarry.TO_BIN and p.bin_detour_bin == bin
					),
			)
		)
		. is_true()
	)

	var saved_clock: Dictionary = JSON.parse_string(JSON.stringify(_world.clock.to_snapshot()))
	var saved_flights: Dictionary = JSON.parse_string(JSON.stringify(_world.flights.to_snapshot()))
	var saved_grid: Dictionary = JSON.parse_string(JSON.stringify(_world.grid.to_snapshot()))
	var saved_messes := MessTestKit.through_json(_world.sim.messes.to_snapshot())
	var saved_pax: Dictionary = JSON.parse_string(JSON.stringify(_world.sim.to_snapshot()))
	var saved_staff := MessTestKit.through_json(_world.staff.to_snapshot())

	# Reject previous save versions cleanly (stripping v11/v42/v45 fields too).
	var old_staff: Dictionary = saved_staff.duplicate(true)
	old_staff["save_version"] = StaffSim.SAVE_VERSION - 1
	for rec: Dictionary in old_staff["members"]:
		rec.erase("bag_carry")
		rec.erase("bag_target")
	assert_bool(_world.staff.from_snapshot(old_staff)).is_false()
	var old_pax: Dictionary = saved_pax.duplicate(true)
	old_pax["save_version"] = PassengerSim.SAVE_VERSION - 1
	for rec: Dictionary in old_pax["passengers"]:
		rec.erase("bin_detour_bin")
		rec.erase("bin_detour_end")
	assert_bool(_world.sim.from_snapshot(old_pax)).is_false()
	assert_int(SaveGame.SAVE_VERSION).is_equal(49)

	# Load into second world and verify deterministic tick-by-tick replay.
	var grid_b := BuildGrid.new()
	assert_bool(grid_b.from_snapshot(saved_grid)).is_true()
	_aux = PassengerTestWorld.make(grid_b, PassengerTestWorld.starts_with(1500, 4000), 44)
	assert_bool(_aux.clock.from_snapshot(saved_clock)).is_true()
	assert_bool(_aux.flights.from_snapshot(saved_flights)).is_true()
	assert_bool(_aux.sim.messes.from_snapshot(saved_messes)).is_true()
	assert_bool(_aux.sim.from_snapshot(saved_pax)).is_true()
	assert_bool(_aux.staff.from_snapshot(saved_staff)).is_true()
	assert_str(_aux.signature()).is_equal(_world.signature())
	assert_str(MessTestKit.text_of(_aux.staff.to_snapshot())).is_equal(
		MessTestKit.text_of(_world.staff.to_snapshot())
	)

	var first_diff := -1
	for i in 120:
		_world.step()
		_aux.step()
		var eq := (
			_world.signature() == _aux.signature()
			and (
				MessTestKit.text_of(_world.staff.to_snapshot())
				== MessTestKit.text_of(_aux.staff.to_snapshot())
			)
			and (
				MessTestKit.text_of(_world.sim.messes.to_snapshot())
				== MessTestKit.text_of(_aux.sim.messes.to_snapshot())
			)
		)
		if not eq and first_diff < 0:
			first_diff = _world.clock.tick
	assert_int(first_diff).is_equal(-1)
	assert_int(_world.sim.messes.fill_of(bin)).is_greater_equal(2)


func test_mid_toss_bin_fill_reroutes_cleaner_and_cancels_passenger_cleanly() -> void:
	# Part A: cleaner mid-toss into bin_a when bin_a fills -> reroutes to bin_b without losing bag.
	_world = _open_world(51)
	var bin_a := PassengerTestWorld.place(_world.grid, MessSim.BIN_ID, Vector2i(14, 10), 0)
	var bin_b := PassengerTestWorld.place(_world.grid, MessSim.BIN_ID, Vector2i(8, 10), 0)
	var snap := _world.sim.messes.to_snapshot()
	snap["bins"][str(bin_a)] = MessSim.BIN_CAPACITY - 1
	assert_bool(_world.sim.messes.from_snapshot(snap)).is_true()
	_world.sim.messes.add(MessSim.Kind.LITTER, Vector2i(20, 10))
	var m := CleanerTestKit.cleaner_at(_world, Vector2i(19, 10))
	(
		assert_bool(
			CleanerTestKit.step_until(
				_world,
				func() -> bool:
					return (
						m.bag_carry == StaffMember.BagCarry.TO_BIN
						and m.bag_target == bin_a
						and m.state == StaffMember.State.ON_DUTY
						and m.work_left == 2
					),
			)
		)
		. is_true()
	)
	# Fill bin_a while cleaner is mid-toss -> reconcile/finish reroutes bag to bin_b cleanly.
	assert_bool(_world.sim.messes.add_to_bin(bin_a)).is_true()
	assert_int(_world.sim.messes.fill_of(bin_a)).is_equal(MessSim.BIN_CAPACITY)
	_world.step()
	assert_int(m.bag_carry).is_equal(StaffMember.BagCarry.TO_BIN)
	assert_int(m.bag_target).is_equal(bin_b)
	(
		assert_bool(
			CleanerTestKit.step_until(
				_world, func() -> bool: return m.state == StaffMember.State.IDLE
			)
		)
		. is_true()
	)
	assert_int(m.bag_carry).is_equal(StaffMember.BagCarry.NONE)
	assert_int(_world.sim.messes.fill_of(bin_b)).is_equal(1)

	# Part B: passenger mid-toss at bin when bin fills -> cancels detour cleanly and makes flight.
	var setup := _make_cafe_world(52)
	_aux = setup["world"]
	var at: Vector2i = setup["at"]
	var pbin := PassengerTestWorld.place(
		_aux.grid, MessSim.BIN_ID, CafeTestLayout.AIR_TABLE + Vector2i(-1, 2) + at, 0
	)
	var psnap := _aux.sim.messes.to_snapshot()
	psnap["bins"][str(pbin)] = MessSim.BIN_CAPACITY - 1
	assert_bool(_aux.sim.messes.from_snapshot(psnap)).is_true()
	var p := _aux.passenger(_aux.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ShopTestLayout.to_airside(_aux, p, 0, CafeTestLayout.AIR_COUNTER + Vector2i(0, 1) + at)
	p.cafe_cooldown = 0
	p.hunger = CafeSim.HUNGRY_AT
	assert_int(NeedsPolicy.arbitrate(_aux.sim, p)).is_equal(NeedsPolicy.Need.HUNGER)
	(
		assert_bool(
			CleanerTestKit.step_until(
				_aux, func() -> bool: return p.bin_detour_bin == pbin and p.bin_detour_end > 0
			)
		)
		. is_true()
	)
	assert_bool(_aux.sim.messes.add_to_bin(pbin)).is_true()
	var caught_before := _aux.sim.messes.caught
	_aux.step()
	assert_int(p.bin_detour_bin).is_equal(0)
	assert_int(p.bin_detour_end).is_equal(0)
	assert_int(_aux.sim.messes.fill_of(pbin)).is_equal(MessSim.BIN_CAPACITY)
	assert_int(_aux.sim.messes.caught).is_equal(caught_before)
	var doors := _aux.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	(
		assert_bool(
			CleanerTestKit.step_until(
				_aux, func() -> bool: return p.is_done(), doors - _aux.clock.tick + 10
			)
		)
		. is_true()
	)
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)


func test_live_bin_detour_cancels_on_tight_forecast_while_walking_and_tossing() -> void:
	# Wall edit after detour starts lengthens airside exit route past safe margin -> cancels detour.
	var setup := _make_cafe_world(55)
	_world = setup["world"]
	var at: Vector2i = setup["at"]
	var bin_cell := CafeTestLayout.AIR_TABLE + Vector2i(-1, 2) + at
	var bin := PassengerTestWorld.place(_world.grid, MessSim.BIN_ID, bin_cell, 0)
	var doors := _world.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	_world.run_to(1600)
	var spot := _world.sim.messes.bin_approach(bin)
	var start_cell := CafeTestLayout.AIR_COUNTER + Vector2i(0, 1) + at
	var probe := Passenger.new()
	probe.flight_id = PassengerTestWorld.FLIGHT
	probe.boarding_tick = 1500
	probe.cleared = true
	probe.stage = Passenger.Stage.TO_GATE
	probe.at = spot
	var walk_to_spot := JourneyForecast.walk_ticks(
		Passenger.path_mm(_world.grid.find_path(start_cell, spot))
	)
	var exit_from_spot := (
		VisitForecast.arrival(_world.sim, probe, 0, spot, 0, Passenger.Stage.TO_GATE)
		- _world.clock.tick
	)
	var tighten_to := (
		doors
		- (
			walk_to_spot
			+ MessSim.BIN_TOSS_TICKS
			+ exit_from_spot
			+ VisitForecast.MARGIN_TICKS
			+ MessSim.BIN_DETOUR_SLACK_TICKS
			+ 10
		)
	)
	_world.run_to(tighten_to)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ShopTestLayout.to_airside(_world, p, 0, start_cell)
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	assert_bool(BinDetour.try_start(_world.sim, p)).is_true()
	assert_int(p.bin_detour_bin).is_equal(bin)
	assert_int(p.bin_detour_end).is_equal(-1)
	# Tighten forecast by blocking direct east-west passage into the terminal gate hall.
	var wall_edits: Array[BuildEdit] = []
	for y in [4, 5, 6, 7]:
		wall_edits.append(BuildEdit.place_wall(Vector2i(21, y) + at, BuildGrid.Side.EAST))
	for res in _world.grid.apply_batch(wall_edits):
		assert_bool(res.ok).is_true()
	_world.step()
	assert_int(p.bin_detour_bin).is_equal(0)

	# Second passenger already tossing at bin cancels immediately when forecast tightens past margin.
	var wall_undo: Array[BuildEdit] = []
	for y in [4, 5, 6, 7]:
		wall_undo.append(BuildEdit.remove_wall(Vector2i(21, y) + at, BuildGrid.Side.EAST))
	for res in _world.grid.apply_batch(wall_undo):
		assert_bool(res.ok).is_true()
	var p2 := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ShopTestLayout.to_airside(_world, p2, 0, spot)
	p2.cleared = true
	p2.stage = Passenger.Stage.TO_GATE
	assert_bool(BinDetour.try_start(_world.sim, p2)).is_true()
	assert_int(p2.bin_detour_end).is_greater(_world.clock.tick)
	for res in _world.grid.apply_batch(wall_edits):
		assert_bool(res.ok).is_true()
	_world.step()
	assert_int(p2.bin_detour_bin).is_equal(0)
	assert_int(p2.bin_detour_end).is_equal(0)


func test_proactive_bin_never_beats_untested_urgent_jobs_past_max_path_tries() -> void:
	_world = _open_world(58)
	var door := _world.sim.layout.entrances[0]
	var door_rec := _world.grid.get_object(door)
	assert_bool(_world.grid.apply(BuildEdit.remove_object(door)).ok).is_true()
	var box := Rect2i(16, 8, 5, 4)
	var walls: Array[BuildEdit] = []
	for x in range(box.position.x, box.end.x):
		walls.append(BuildEdit.place_wall(Vector2i(x, box.position.y), BuildGrid.Side.NORTH))
		walls.append(BuildEdit.place_wall(Vector2i(x, box.end.y - 1), BuildGrid.Side.SOUTH))
	for y in range(box.position.y, box.end.y):
		walls.append(BuildEdit.place_wall(Vector2i(box.position.x, y), BuildGrid.Side.WEST))
		walls.append(BuildEdit.place_wall(Vector2i(box.end.x - 1, y), BuildGrid.Side.EAST))
	for res in _world.grid.apply_batch(walls):
		assert_bool(res.ok).is_true()
	var walled := 0
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			walled += int(_world.sim.messes.add(MessSim.Kind.LITTER, Vector2i(x, y)) != 0)
	assert_int(walled).is_greater(CleanerJobs.MAX_PATH_TRIES)
	# Place a reachable >=50% proactive bin nearby: must NOT be claimed while >MAX_PATH_TRIES
	# untested urgent messes remain.
	var pbin := PassengerTestWorld.place(_world.grid, MessSim.BIN_ID, Vector2i(8, 10), 0)
	var snap := _world.sim.messes.to_snapshot()
	snap["bins"][str(pbin)] = MessSim.BIN_EMPTY_MIN
	assert_bool(_world.sim.messes.from_snapshot(snap)).is_true()
	var m := CleanerTestKit.cleaner_at(_world, Vector2i(10, 10))
	var before_calls := CleanerJobs.path_calls
	_world.step()
	assert_int(CleanerJobs.path_calls - before_calls).is_equal(CleanerJobs.MAX_PATH_TRIES)
	assert_int(m.job).is_equal(0)
	assert_bool(m.search_failed).is_true()
	(
		assert_bool(
			(
				_world
				. grid
				. apply(
					BuildEdit.place_object(door_rec["def"], door_rec["anchor"], door_rec["facing"])
				)
				. ok
			)
		)
		. is_true()
	)


func test_malformed_bin_detour_and_bag_carry_snapshots_are_rejected() -> void:
	var setup := _make_cafe_world(61)
	_world = setup["world"]
	var at: Vector2i = setup["at"]
	var bin := PassengerTestWorld.place(
		_world.grid, MessSim.BIN_ID, CafeTestLayout.AIR_TABLE + Vector2i(-1, 2) + at, 0
	)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ShopTestLayout.to_airside(_world, p, 0, CafeTestLayout.AIR_COUNTER + Vector2i(0, 1) + at)
	p.cafe_cooldown = 0
	p.hunger = CafeSim.HUNGRY_AT
	NeedsPolicy.arbitrate(_world.sim, p)
	(
		assert_bool(
			CleanerTestKit.step_until(
				_world, func() -> bool: return p.stage == Passenger.Stage.CAFE_STANDING_UP
			)
		)
		. is_true()
	)
	var mess_id := _world.sim.messes.add(MessSim.Kind.LITTER, Vector2i(18, 6) + at)
	assert_int(mess_id).is_greater(0)
	var m := CleanerTestKit.cleaner_at(_world, Vector2i(18, 6) + at)
	(
		assert_bool(
			CleanerTestKit.step_until(
				_world,
				func() -> bool:
					return (
						p.bin_detour_bin == bin
						and p.bin_detour_end == -1
						and m.bag_carry == StaffMember.BagCarry.TO_BIN
						and m.state == StaffMember.State.TO_STATION
					),
			)
		)
		. is_true()
	)
	var good_messes := MessTestKit.through_json(_world.sim.messes.to_snapshot())
	var good_pax: Dictionary = JSON.parse_string(JSON.stringify(_world.sim.to_snapshot()))
	var good_staff := MessTestKit.through_json(_world.staff.to_snapshot())

	# Passenger walking detour path invariants: empty path, single-cell stop, wrong path end.
	for bad_path in [[], [[p.at.x, p.at.y]], [[p.at.x, p.at.y], [p.at.x, p.at.y]]]:
		var bad_p: Dictionary = good_pax.duplicate(true)
		for rec: Dictionary in bad_p["passengers"]:
			if int(rec["id"]) == p.id:
				rec["path"] = bad_path
				rec["path_index"] = 0
				rec["seg_mm"] = 0
		assert_str(str(PassengerSnapshot.load(bad_p, _world.grid).get("error", ""))).is_not_empty()

	# Staff TO_STATION bag-carry path invariants: single-cell non-moving, wrong destination cell.
	var mess_state := MessSim.checked(good_messes, _world.grid)
	for s_path in [[[m.at.x, m.at.y]], [[m.at.x, m.at.y], [m.at.x + 1, m.at.y]]]:
		var bad_s: Dictionary = good_staff.duplicate(true)
		for rec: Dictionary in bad_s["members"]:
			if int(rec["id"]) == m.id:
				rec["path"] = s_path
				rec["path_index"] = 0
				rec["seg_mm"] = 0
		(
			assert_str(str(StaffSnapshot.load(bad_s, _world.sim, mess_state).get("error", "")))
			. is_not_empty()
		)


func test_cleaner_finishes_bag_carry_before_taking_break_or_leaving_shift() -> void:
	# Part A: break-skip while carrying a bag even when tired below BREAK_SEEK_THRESHOLD.
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	var rect := Rect2i(11, 13, 5, 4)
	var edits: Array[BuildEdit] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if grid.floor_at(Vector2i(x, y)) == BuildGrid.FLOOR_NONE:
				edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	edits.append(BuildEdit.place_room(rect, &"break_room"))
	for res in grid.apply_batch(edits):
		assert_bool(res.ok).is_true()
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 65)
	_world.auto_staff = false
	assert_bool(_world.flights.open_airport()).is_true()
	var bin := PassengerTestWorld.place(grid, MessSim.BIN_ID, Vector2i(20, 12), 0)
	_world.sim.messes.add(MessSim.Kind.LITTER, Vector2i(20, 15))
	var m := CleanerTestKit.cleaner_at(_world, Vector2i(20, 14))
	m.energy = StaffMember.BREAK_SEEK_THRESHOLD - 1
	(
		assert_bool(
			CleanerTestKit.step_until(
				_world, func() -> bool: return m.bag_carry == StaffMember.BagCarry.TO_BIN
			)
		)
		. is_true()
	)
	for i in 80:
		_world.step()
		if m.bag_carry != StaffMember.BagCarry.NONE:
			assert_int(m.state).is_not_equal(StaffMember.State.TO_BREAK)
			assert_int(m.state).is_not_equal(StaffMember.State.ON_BREAK)
		else:
			break
	assert_int(_world.sim.messes.fill_of(bin)).is_equal(1)

	# Part B: quiet overnight shift-end waits until bag disposal clears before LEAVING_SHIFT.
	var grid_s := BuildGrid.new()
	ReferenceTerminal.build(grid_s)
	_aux = PassengerTestWorld.make(grid_s, FlightSim.schedule_starts(20000), 66)
	_aux.auto_staff = false
	assert_bool(_aux.flights.open_airport()).is_true()
	var sbin := PassengerTestWorld.place(grid_s, MessSim.BIN_ID, Vector2i(20, 12), 0)
	_aux.sim.messes.add(MessSim.Kind.LITTER, Vector2i(20, 15))
	var sm := CleanerTestKit.cleaner_at(_aux, Vector2i(20, 14))
	StaffTestKit.staff_all(_aux.staff, [StaffMember.Role.CHECKIN])
	(
		assert_bool(
			CleanerTestKit.step_until(
				_aux, func() -> bool: return sm.bag_carry == StaffMember.BagCarry.TO_BIN
			)
		)
		. is_true()
	)
	assert_bool(_aux.staff.is_off_shift()).is_true()
	assert_int(sm.state).is_not_equal(StaffMember.State.LEAVING_SHIFT)
	(
		assert_bool(
			CleanerTestKit.step_until(
				_aux, func() -> bool: return _aux.sim.messes.fill_of(sbin) == 1
			)
		)
		. is_true()
	)
	(
		assert_bool(
			CleanerTestKit.step_until(
				_aux,
				func() -> bool:
					return (
						sm.state == StaffMember.State.LEAVING_SHIFT
						or sm.state == StaffMember.State.OFF_SHIFT
					),
			)
		)
		. is_true()
	)
