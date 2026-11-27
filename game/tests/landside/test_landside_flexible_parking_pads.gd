class_name TestLandsideFlexibleParkingPads
extends GdUnitTestSuite
## Regression tests for decision landside-parking-full-south-street-row-of-kind-flexible-pads
## (aef8e716): full south-street row of evenly spaced, kind-flexible parking pads
## accepting either Surface Lot or Multi-Storey on every pad.

const STARTER := preload("res://landside/starter_landside.tres")
const SURFACE_WIDTH := 24.0
const MIN_CENTRE_SPACING := 28.0
const STEP_M := LandsideSim.SPEED_MM / 1000.0 + 0.001

var _rng := RandomNumberGenerator.new()


func before_test() -> void:
	_rng.seed = 42


func _make_sim() -> LandsideSim:
	var sim: LandsideSim = auto_free(LandsideSim.new())
	assert_bool(sim.use_definition(STARTER)).is_true()
	sim.wallet = Wallet.new(500000)
	return sim


func _make_placement(sim: LandsideSim) -> LandsidePlacement:
	var p := LandsidePlacement.new()
	p.sim = sim
	p.wallet = sim.wallet
	return p


func _sorted_xs() -> Array[float]:
	var xs: Array[float] = []
	for lot in STARTER.lots:
		xs.append(lot.centre.x)
	xs.sort()
	return xs


func _westmost_index() -> int:
	var best := 0
	for i in STARTER.lots.size():
		if STARTER.lots[i].centre.x < STARTER.lots[best].centre.x:
			best = i
	return best


func _eastmost_index() -> int:
	var best := 0
	for i in STARTER.lots.size():
		if STARTER.lots[i].centre.x > STARTER.lots[best].centre.x:
			best = i
	return best


func _build_kind(p: LandsidePlacement, kind: LandsidePlacement.Kind, spot: int) -> BuildResult:
	var at := STARTER.lots[spot].centre
	var plan := p.plan_build(kind, Vector3(at.x, 0.0, -21.65))
	return p.apply(plan, null)


func test_south_street_has_full_row_of_non_overlapping_pads_west_to_east() -> void:
	assert_int(STARTER.lots.size()).is_greater_equal(7)
	assert_float(STARTER.lots[0].centre.x).is_equal_approx(31.7, 0.01)
	assert_float(STARTER.lots[1].centre.x).is_equal_approx(0.0, 0.01)
	var xs := _sorted_xs()
	assert_float(xs[0]).is_less_equal(-80.0)
	assert_float(xs[xs.size() - 1]).is_greater_equal(80.0)
	for i in range(1, xs.size()):
		var spacing := xs[i] - xs[i - 1]
		(
			assert_float(spacing)
			. override_failure_message("spacing between %.2f and %.2f" % [xs[i - 1], xs[i]])
			. is_greater_equal(MIN_CENTRE_SPACING)
		)
	for i in STARTER.lots.size():
		assert_float(STARTER.lots[i].footprint.x).is_equal_approx(SURFACE_WIDTH, 0.01)
		assert_int(STARTER.lots[i].branch_mm).is_greater(0)
		assert_int(STARTER.lots[i].branch_mm).is_less(STARTER.curb.stop_mm)


func test_every_pad_accepts_both_surface_lot_and_multi_storey() -> void:
	var sim_s := _make_sim()
	var p_s := _make_placement(sim_s)
	var sim_m := _make_sim()
	var p_m := _make_placement(sim_m)
	for spot in STARTER.lots.size():
		var res_s := _build_kind(p_s, LandsidePlacement.Kind.SURFACE_LOT, spot)
		assert_bool(res_s.ok).override_failure_message("surface on pad %d" % spot).is_true()
		assert_int(sim_s.free_slots(spot)).is_equal(12)
		assert_int(sim_s.parking_fee(spot)).is_equal(LandsideSim.SURFACE_LOT_FEE)
		assert_int(sim_s.lot_kind(spot)).is_equal(LandsideLotSpot.Kind.SURFACE)

		var res_m := _build_kind(p_m, LandsidePlacement.Kind.MULTI_STOREY, spot)
		assert_bool(res_m.ok).override_failure_message("multi on pad %d" % spot).is_true()
		assert_int(sim_m.free_slots(spot)).is_equal(31)
		assert_int(sim_m.parking_fee(spot)).is_equal(LandsideSim.MULTI_STOREY_FEE)
		assert_int(sim_m.lot_kind(spot)).is_equal(LandsideLotSpot.Kind.MULTI_STOREY)

		for kind in [LandsideLotSpot.Kind.SURFACE, LandsideLotSpot.Kind.MULTI_STOREY]:
			var lot := STARTER.lot_for_kind(spot, kind)
			var tag := "pad %d kind %d" % [spot, kind]
			assert_int(lot.kind).override_failure_message(tag).is_equal(kind)
			assert_float(lot.centre.x).override_failure_message(tag).is_equal_approx(
				STARTER.lots[spot].centre.x, 0.01
			)
			assert_int(lot.branch_mm).override_failure_message(tag).is_greater(0)
			assert_int(lot.branch_mm).override_failure_message(tag).is_less(STARTER.curb.stop_mm)
			assert_bool(lot.access.is_empty()).override_failure_message(tag).is_false()
			assert_bool(lot.exit.is_empty()).override_failure_message(tag).is_false()
			assert_bool(lot.crossing.is_empty()).override_failure_message(tag).is_false()
			for lane in [lot.access, lot.exit, lot.crossing]:
				for pt in lane:
					assert_float(pt.x).override_failure_message(tag).is_between(-156.0, 156.0)
					assert_float(pt.z).override_failure_message(tag).is_between(-61.0, 20.0)
			# Right-hand traffic: access gate sits west of exit lane; exit leaves eastbound.
			assert_float(lot.access[lot.access.size() - 1].x).override_failure_message(tag).is_less(
				lot.exit[0].x
			)
			(
				assert_float(lot.exit[lot.exit.size() - 1].x)
				. override_failure_message(tag)
				. is_equal_approx(LandsideLotSpot.ROAD_END_EAST_X, 0.01)
			)
			(
				assert_float(lot.exit[lot.exit.size() - 1].z)
				. override_failure_message(tag)
				. is_equal_approx(LandsideLotSpot.ROAD_THROUGH_EAST_Z, 0.01)
			)
			(
				assert_float(lot.crossing[lot.crossing.size() - 1].z)
				. override_failure_message(tag)
				. is_less_equal(-60.0)
			)


func test_cars_drive_park_unload_and_exit_cleanly_on_west_east_and_swapped_pads() -> void:
	var west := _westmost_index()
	var east := _eastmost_index()
	for case_pair in [
		[1, LandsidePlacement.Kind.SURFACE_LOT, LandsideSim.SURFACE_LOT_FEE],
		[west, LandsidePlacement.Kind.MULTI_STOREY, LandsideSim.MULTI_STOREY_FEE],
		[east, LandsidePlacement.Kind.SURFACE_LOT, LandsideSim.SURFACE_LOT_FEE],
	]:
		var spot: int = case_pair[0]
		var kind: LandsidePlacement.Kind = case_pair[1]
		var fee: int = case_pair[2]
		var sim := _make_sim()
		var p := _make_placement(sim)
		assert_bool(_build_kind(p, kind, spot).ok).is_true()
		var start_bal := sim.wallet.balance
		var bookings: Array[int] = [1]
		var vid := sim.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK, bookings)
		var track: Array[Vector3] = []
		var walks: Array = []
		var seen_lanes := {}
		var parked := false
		for t in range(1, 5000):
			for ev in sim.step(t, true, _rng):
				if ev["vehicle"] == vid:
					walks.append(ev["walk"])
			var v := sim.get_vehicle(vid)
			if v == null:
				break
			seen_lanes[v.lane] = true
			if v.stage == LandsideVehicle.Stage.PARKED:
				parked = true
				assert_int(v.lot).is_equal(spot)
				if v.leave_tick > t + 10:
					v.leave_tick = t + 10
			if not (v.lane == LandsideVehicle.Lane.ROAD_IN and v.pos_mm < 0):
				track.append(sim.world_position(v))
		assert_bool(parked).override_failure_message("pad %d parked" % spot).is_true()
		(
			assert_object(sim.get_vehicle(vid))
			. override_failure_message("pad %d exited" % spot)
			. is_null()
		)
		assert_int(sim.lot_cars(spot)).is_equal(0)
		assert_int(sim.wallet.balance).is_equal(start_bal + fee)
		assert_bool(seen_lanes.has(LandsideVehicle.Lane.ACCESS)).is_true()
		assert_bool(seen_lanes.has(LandsideVehicle.Lane.SLOT)).is_true()
		assert_bool(seen_lanes.has(LandsideVehicle.Lane.LOT_EXIT)).is_true()
		assert_int(walks.size()).is_equal(1)
		var walk: Array = walks[0]
		assert_float((walk[walk.size() - 1] as Vector3).z).is_less_equal(-51.0)
		var largest := 0.0
		for i in range(1, track.size()):
			largest = maxf(largest, track[i].distance_to(track[i - 1]))
		assert_float(largest).is_less_equal(STEP_M)


func test_snapshot_round_trip_preserves_mixed_lot_kinds_on_arbitrary_pads() -> void:
	var west := _westmost_index()
	var east := _eastmost_index()
	var sim := _make_sim()
	var p := _make_placement(sim)
	# Swap pad 0 to Multi-Storey, pad 1 to Surface, west to Multi-Storey, east to Surface.
	assert_bool(_build_kind(p, LandsidePlacement.Kind.MULTI_STOREY, 0).ok).is_true()
	assert_bool(_build_kind(p, LandsidePlacement.Kind.SURFACE_LOT, 1).ok).is_true()
	assert_bool(_build_kind(p, LandsidePlacement.Kind.MULTI_STOREY, west).ok).is_true()
	assert_bool(_build_kind(p, LandsidePlacement.Kind.SURFACE_LOT, east).ok).is_true()
	for i in 4:
		var b: Array[int] = [i + 1]
		sim.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK, b)
	for t in range(1, 1200):
		sim.step(t, true, _rng)
	var snap := sim.to_snapshot(ArrivalBookings.new(), 1200)
	var text := JSON.stringify(snap)
	var parsed: Dictionary = JSON.parse_string(text)

	var restored := _make_sim()
	assert_bool(restored.from_snapshot(parsed, ArrivalBookings.new())).is_true()
	assert_int(restored.parking_fee(0)).is_equal(LandsideSim.MULTI_STOREY_FEE)
	assert_int(restored.parking_fee(1)).is_equal(LandsideSim.SURFACE_LOT_FEE)
	assert_int(restored.parking_fee(west)).is_equal(LandsideSim.MULTI_STOREY_FEE)
	assert_int(restored.parking_fee(east)).is_equal(LandsideSim.SURFACE_LOT_FEE)
	assert_int(restored.free_slots(0) + restored.lot_occupied(0)).is_equal(31)
	assert_int(restored.free_slots(1) + restored.lot_occupied(1)).is_equal(12)
	assert_int(restored.free_slots(west) + restored.lot_occupied(west)).is_equal(31)
	assert_int(restored.free_slots(east) + restored.lot_occupied(east)).is_equal(12)
	assert_str(JSON.stringify(restored.to_snapshot(ArrivalBookings.new(), 1200))).is_equal(text)


func test_snapshot_rejects_malformed_lots_kind_and_previous_save_version() -> void:
	var sim := _make_sim()
	var p := _make_placement(sim)
	assert_bool(_build_kind(p, LandsidePlacement.Kind.MULTI_STOREY, 0).ok).is_true()
	var bookings := ArrivalBookings.new()
	sim.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK, [1])
	for t in range(1, 50):
		sim.step(t, true, _rng)
	var before := JSON.stringify(sim.to_snapshot(bookings, 50))
	var valid: Dictionary = JSON.parse_string(before)

	var v11: Dictionary = valid.duplicate(true)
	v11["save_version"] = 11
	var v11_loaded := LandsideSnapshot.load(v11, STARTER)
	assert_str(str(v11_loaded.get("error", ""))).is_equal(
		"save_version must be %d" % LandsideSnapshot.SAVE_VERSION
	)
	assert_bool(sim.from_snapshot(v11, bookings)).is_false()
	assert_str(JSON.stringify(sim.to_snapshot(bookings, 50))).is_equal(before)

	var bad_cases: Array[Array] = [
		["wrong length", func(d: Dictionary) -> void: d["lots_kind"] = [0, 1]],
		["invalid negative", func(d: Dictionary) -> void: d["lots_kind"][0] = -1],
		["invalid high", func(d: Dictionary) -> void: d["lots_kind"][0] = 2],
		[
			"non-default on unbuilt pad 2",
			func(d: Dictionary) -> void: d["lots_kind"][2] = LandsideLotSpot.Kind.MULTI_STOREY,
		],
		[
			"non-default on unbuilt pad 1",
			func(d: Dictionary) -> void: d["lots_kind"][1] = LandsideLotSpot.Kind.SURFACE,
		],
	]
	for entry in bad_cases:
		var label: String = entry[0]
		var mutator: Callable = entry[1]
		var bad: Dictionary = valid.duplicate(true)
		mutator.call(bad)
		var loaded := LandsideSnapshot.load(bad, STARTER)
		assert_bool(loaded.has("error")).override_failure_message(label).is_true()
		assert_bool(sim.from_snapshot(bad, bookings)).override_failure_message(label).is_false()
		assert_str(JSON.stringify(sim.to_snapshot(bookings, 50))).is_equal(before)


func test_opposite_kind_rebuild_and_undo_restores_exact_kind_and_balance() -> void:
	var sim := _make_sim()
	var p := _make_placement(sim)
	var spot := 3
	var start_bal := sim.wallet.balance
	var at := Vector3(STARTER.lots[spot].centre.x, 0.0, -21.65)
	var surf_price := PriceTable.price_of_landside(&"surface_lot")
	var multi_price := PriceTable.price_of_landside(&"multi_storey")

	assert_bool(_build_kind(p, LandsidePlacement.Kind.SURFACE_LOT, spot).ok).is_true()
	assert_bool(sim.lots_built[spot]).is_true()
	assert_int(sim.lot_kind(spot)).is_equal(LandsideLotSpot.Kind.SURFACE)
	assert_int(sim.free_slots(spot)).is_equal(12)
	assert_int(sim.wallet.balance).is_equal(start_bal - surf_price)

	var rem_plan := p.plan_remove(at)
	assert_object(rem_plan).is_not_null()
	assert_bool(p.apply(rem_plan, null).ok).is_true()
	assert_bool(sim.lots_built[spot]).is_false()
	var after_rem_bal := sim.wallet.balance

	assert_bool(_build_kind(p, LandsidePlacement.Kind.MULTI_STOREY, spot).ok).is_true()
	assert_bool(sim.lots_built[spot]).is_true()
	assert_int(sim.lot_kind(spot)).is_equal(LandsideLotSpot.Kind.MULTI_STOREY)
	assert_int(sim.free_slots(spot)).is_equal(31)
	assert_int(sim.wallet.balance).is_equal(after_rem_bal - multi_price)

	# Undo Multi-Storey build -> empty pad, full Multi-Storey price refunded.
	assert_bool(p.undo().ok).is_true()
	assert_bool(sim.lots_built[spot]).is_false()
	assert_int(sim.wallet.balance).is_equal(after_rem_bal)

	# Undo Remove -> Surface lot restored with 12 stalls and prior balance.
	assert_bool(p.undo().ok).is_true()
	assert_bool(sim.lots_built[spot]).is_true()
	assert_int(sim.lot_kind(spot)).is_equal(LandsideLotSpot.Kind.SURFACE)
	assert_int(sim.free_slots(spot)).is_equal(12)
	assert_int(sim.wallet.balance).is_equal(start_bal - surf_price)

	# Undo Surface build -> empty pad, full starting balance restored.
	assert_bool(p.undo().ok).is_true()
	assert_bool(sim.lots_built[spot]).is_false()
	assert_int(sim.wallet.balance).is_equal(start_bal)
