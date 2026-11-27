class_name TestArrivalsLandsidePickup
extends GdUnitTestSuite
## Arrivals Slice A2: parked-car claimant pickup (4.8h oldest-first, ~30% share,
## leave_tick hold, surface_lot & multi_storey walk-to-stall, mid-walk fallback),
## DROP-protected curb PICKUP taxis (cap, DWELL_TICKS=0 unmatched, patience timeout),
## and SaveGame v47 round-trip + v46 refusal + SaveLinks validation.

var _lands: Array[LandsideTestWorld] = []
var _main: Node
var _loaded: Node
var _save_path := SaveTestKit.run_path("test_arrivals_landside_pickup")


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for land in _lands:
		land.free_all()
	_lands.clear()
	if _main != null:
		_main.free()
		_main = null
	if _loaded != null:
		_loaded.free()
		_loaded = null
	DirAccess.remove_absolute(_save_path)
	DirAccess.remove_absolute(_save_path + ".tmp")


func _make_world(seed := 17, starts: Array[int] = []) -> LandsideTestWorld:
	var land := LandsideTestWorld.make(null, starts, seed)
	_lands.append(land)
	return land


func _park_car_at_tick(land: LandsideTestWorld, spot: int, parked_tick: int) -> LandsideVehicle:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42 + parked_tick
	var bookings: Array[int] = [9000 + land.landside.vehicle_ids().size() + 1]
	var vid := land.landside.add_vehicle(
		LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK, bookings
	)
	var t := land.landside.tick
	while true:
		t += 1
		land.landside.step(t, true, rng)
		var v := land.landside.get_vehicle(vid)
		if v.stage == LandsideVehicle.Stage.PARKED and v.bookings.is_empty():
			v.stage_tick = parked_tick
			v.leave_tick = parked_tick + LandsideSim.STAY_MIN_TICKS
			break
	assert_int(land.landside.get_vehicle(vid).lot).is_equal(spot)
	return land.landside.get_vehicle(vid)


func _spawn_landside_arriving(
	land: LandsideTestWorld, wants_car: bool, flight := PassengerTestWorld.FLIGHT
) -> Passenger:
	var door := land.sim.layout.passenger_entrances[0]
	var p := PassengerArrivals.spawn(land.sim, flight, 0)
	p.apron.clear()
	p.apron_mm = 0
	p.cleared = false
	p.at = land.sim.layout.door_cell(land.sim.grid, door)
	p.clear_path()
	p.arrival_stop_cap = 0
	p.wants_parked_car = wants_car
	land.sim._set_stage(p, Passenger.Stage.TO_ROAD_EXIT)
	return p


func test_parked_car_eligibility_oldest_first_share_and_leave_tick_hold() -> void:
	var land := _make_world(19)
	assert_bool(land.landside.build_lot(0, 0, LandsideLotSpot.Kind.SURFACE)).is_true()

	# Park two cars and rewind stage_tick so car A is older than car B.
	var v_b := _park_car_at_tick(land, 0, 200)
	var v_a := _park_car_at_tick(land, 0, 100)
	var v_unclaimed := _park_car_at_tick(land, 0, 300)

	# Before PARK_CLAIM_MIN_TICKS (5760): neither is eligible.
	land.landside.tick = 100 + LandsideSim.PARK_CLAIM_MIN_TICKS - 1
	assert_object(land.landside.eligible_parked_car()).is_null()

	# Exactly at PARK_CLAIM_MIN_TICKS for v_a: v_a becomes eligible first.
	land.landside.tick = 100 + LandsideSim.PARK_CLAIM_MIN_TICKS
	assert_object(land.landside.eligible_parked_car()).is_equal(v_a)

	# Both v_a and v_b past window: oldest stage_tick (v_a) wins, then v_b.
	land.landside.tick = 200 + LandsideSim.PARK_CLAIM_MIN_TICKS
	assert_object(land.landside.claim_parked_car(501)).is_equal(v_a)
	assert_object(land.landside.claim_parked_car(502)).is_equal(v_b)
	assert_array(v_a.claimants).is_equal([501])
	assert_array(v_b.claimants).is_equal([502])

	# Set v_a's and v_unclaimed's leave_tick to now: v_a MUST stay PARKED while
	# claimant 501 walks to it, while unclaimed v_unclaimed departs on leave_tick!
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var now := land.landside.tick + 1
	v_a.leave_tick = now
	v_unclaimed.leave_tick = now
	for _i in 30:
		now += 1
		land.landside.step(now, true, rng)
	assert_int(land.landside.get_vehicle(v_a.id).stage).is_equal(LandsideVehicle.Stage.PARKED)
	var unc := land.landside.get_vehicle(v_unclaimed.id)
	assert_bool(unc == null or unc.stage != LandsideVehicle.Stage.PARKED).is_true()

	# Deterministic ~30% parked-car share across a batch of arriving spawns.
	var want_count := 0
	var total := 100
	for _i in total:
		var sp := PassengerArrivals.spawn(land.sim, PassengerTestWorld.FLIGHT, 0)
		want_count += int(sp.wants_parked_car)
	assert_int(want_count).is_between(15, 45)


func test_arriving_passenger_walks_to_surface_and_multi_storey_and_drives_out() -> void:
	for case_pair in [
		[0, LandsideLotSpot.Kind.SURFACE],
		[1, LandsideLotSpot.Kind.MULTI_STOREY],
	]:
		var spot: int = case_pair[0]
		var kind: LandsideLotSpot.Kind = case_pair[1]
		var land := _make_world(31 + spot)
		assert_bool(land.landside.build_lot(spot, 0, kind)).is_true()
		var v := _park_car_at_tick(land, spot, 10)
		# Put the car on an upper deck stall for Multi-Storey to verify ramp walk.
		if kind == LandsideLotSpot.Kind.MULTI_STOREY:
			v.stop = 20
			land.landside._rederive()
		var target_pos: Vector3 = land.landside.lot_spot(spot).slots[v.stop]
		assert_int(land.landside.lot_occupied(spot)).is_equal(1)

		var advance_to := v.stage_tick + LandsideSim.PARK_CLAIM_MIN_TICKS
		land.sim.clock.tick = advance_to
		land.sim.tick = advance_to
		land.landside.tick = advance_to

		var finished := []
		land.sim.arrival_finished.connect(func(id: int) -> void: finished.append(id))
		var p := _spawn_landside_arriving(land, true)

		var saw_to_car := false
		var crossed_x_minus_2 := false
		var max_dist_to_stall := INF
		for _i in 4500:
			land.step()
			if p.stage == Passenger.Stage.TO_PARKED_CAR and not p.arrival_done:
				saw_to_car = true
				assert_int(p.pickup_vehicle).is_equal(v.id)
				var pos := land.sim.world_position(p)
				max_dist_to_stall = minf(max_dist_to_stall, pos.distance_to(target_pos))
				if kind == LandsideLotSpot.Kind.MULTI_STOREY and absf(pos.x + 2.0) < 0.25:
					crossed_x_minus_2 = true
			if land.sim.get_passenger(p.id) == null and land.landside.get_vehicle(v.id) == null:
				break

		assert_bool(saw_to_car).is_true()
		if kind == LandsideLotSpot.Kind.MULTI_STOREY:
			assert_bool(crossed_x_minus_2).is_true()
		assert_float(max_dist_to_stall).is_less(0.35)
		assert_array(finished).is_equal([p.id])
		assert_object(land.sim.get_passenger(p.id)).is_null()
		assert_object(land.landside.get_vehicle(v.id)).is_null()
		assert_int(land.landside.lot_occupied(spot)).is_equal(0)


func test_mid_walk_fallback_when_claimed_parked_car_is_invalidated() -> void:
	var land := _make_world(43)
	assert_bool(land.landside.build_lot(1, 0, LandsideLotSpot.Kind.MULTI_STOREY)).is_true()
	var v := _park_car_at_tick(land, 1, 10)
	v.stop = 18
	land.landside._rederive()

	var advance_to := v.stage_tick + LandsideSim.PARK_CLAIM_MIN_TICKS
	land.sim.clock.tick = advance_to
	land.sim.tick = advance_to
	land.landside.tick = advance_to

	var p := _spawn_landside_arriving(land, true)
	# Step until passenger is past the sidewalk and inside the multi-storey walk (z > -50).
	for _i in 2200:
		land.step()
		if p.stage == Passenger.Stage.TO_PARKED_CAR and p.apron_position().z > -50.0:
			break
	assert_int(p.stage).is_equal(Passenger.Stage.TO_PARKED_CAR)
	assert_float(p.apron_position().z).is_greater(-50.0)

	# Invalidate the parked car mid-walk by removing it from the lot.
	land.landside._slots[1][v.stop] = 0
	land.landside._remove(v)
	assert_object(land.landside.get_vehicle(v.id)).is_null()

	# Passenger must immediately reroute (curb pickup -> sidewalk/taxi) and retire cleanly.
	var saw_curb_or_exit := false
	for _i in 1500:
		land.step()
		if (
			p.stage
			in [
				Passenger.Stage.TO_CURB_PICKUP,
				Passenger.Stage.WAIT_CURB_PICKUP,
				Passenger.Stage.TO_ROAD_EXIT,
			]
		):
			saw_curb_or_exit = true
			assert_int(p.pickup_vehicle).is_equal(0)
		if land.sim.get_passenger(p.id) == null:
			break
	assert_bool(saw_curb_or_exit).is_true()
	assert_object(land.sim.get_passenger(p.id)).is_null()


func test_curb_pickup_taxi_cap_drop_protection_unmatched_dwell_zero_and_patience_fallback() -> void:
	# (a) Unmatched PICKUP taxi pulls straight through with DWELL_TICKS = 0.
	var sim_u: LandsideSim = auto_free(LandsideSim.new())
	assert_bool(sim_u.use_definition(LandsideTestWorld.STARTER)).is_true()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var empty_id := sim_u.add_vehicle(
		LandsideVehicle.Kind.TAXI, LandsideVehicle.Intent.PICKUP, [] as Array[int]
	)
	var dwell_ticks := 0
	var pulled_out := false
	for t in range(1, 1000):
		sim_u.step(t, true, rng)
		var v := sim_u.get_vehicle(empty_id)
		if v == null:
			break
		assert_int(v.intent).is_equal(LandsideVehicle.Intent.PICKUP)
		if v.stage == LandsideVehicle.Stage.DWELL:
			dwell_ticks += 1
		if v.stage == LandsideVehicle.Stage.LEAVE:
			pulled_out = true
	assert_bool(pulled_out).is_true()
	assert_int(dwell_ticks).is_equal(1)

	# (b) Starter 2-berth curb: 3 waiters spawn at most max(1, 2 - 1) = 1 PICKUP taxi,
	# leaving the 2nd berth open for a DROP departure car!
	var land := _make_world(59)
	var waiters: Array[Passenger] = []
	for _i in 3:
		var p := _spawn_landside_arriving(land, false)
		waiters.append(p)
	while waiters.any(
		func(p: Passenger) -> bool:
			return p.stage in [Passenger.Stage.TO_ROAD_EXIT, Passenger.Stage.TO_CURB_PICKUP]
	):
		land.step()
	for p in waiters:
		assert_int(p.stage).is_equal(Passenger.Stage.WAIT_CURB_PICKUP)

	# Step once so ArrivalBookings spawns PICKUP taxi; verify cap = 1 on 2-berth curb.
	land.step()
	assert_int(land.landside.active_pickup_taxis()).is_equal(1)
	assert_bool(land.landside.can_spawn_pickup_taxi()).is_false()

	# Also verify built_berths = 4 allows max(1, 4 - 1) = 3 active PICKUP taxis.
	var sim4: LandsideSim = auto_free(LandsideSim.new())
	assert_bool(sim4.use_definition(LandsideTestWorld.STARTER)).is_true()
	assert_bool(sim4.build_curb(0)).is_true()
	assert_int(sim4.built_berth_count()).is_equal(4)
	for _i in 3:
		assert_bool(sim4.can_spawn_pickup_taxi()).is_true()
		sim4.add_vehicle(LandsideVehicle.Kind.TAXI, LandsideVehicle.Intent.PICKUP, [] as Array[int])
	assert_bool(sim4.can_spawn_pickup_taxi()).is_false()

	# Inject a departing DROP vehicle right behind the PICKUP taxi on road_in.
	var drop_booking := ArrivalBooking.new()
	drop_booking.id = 1
	drop_booking.party = 1
	drop_booking.flight_id = PassengerTestWorld.FLIGHT
	drop_booking.unload_tick = land.sim.tick + 400
	land.sim.arrivals._bookings.append(drop_booking)
	land.sim.arrivals._by_id[1] = drop_booking
	var drop_vid := land.landside.add_vehicle(
		LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.DROP, [1] as Array[int]
	)
	drop_booking.state = ArrivalBooking.State.IN_VEHICLE
	drop_booking.vehicle = drop_vid

	var drop_released_ids := []
	var pickups_retired := 0
	land.sim.arrivals.released.connect(
		func(bid: int, _pid: int) -> void:
			if bid == 1:
				drop_released_ids.append(bid)
	)
	for _i in 1200:
		land.step()
		if land.landside.get_vehicle(drop_vid) == null and not drop_released_ids.is_empty():
			var done_count := 0
			for p in waiters:
				if land.sim.get_passenger(p.id) == null:
					done_count += 1
			pickups_retired = done_count
			if done_count == waiters.size():
				break
	assert_bool(not drop_released_ids.is_empty()).is_true()
	assert_int(pickups_retired).is_equal(waiters.size())

	# (c) Patience timeout fallback when curb is jammed by DROP cars holding both berths.
	var jammed := _make_world(61)
	# Occupy both starter berths permanently (no entrance -> DROP cars never unload!).
	var no_door_grid := BuildGrid.new(
		LandsideTestWorld.SITE.grid_size, LandsideTestWorld.SITE.grid_origin
	)
	for edit in ReferenceTerminal.edits(LandKit.FIRST_SITE):
		if edit.kind != BuildEdit.Kind.PLACE_OBJECT or edit.def_id != &"entrance_door":
			assert_bool(no_door_grid.apply(edit).ok).is_true()
	jammed.sim.grid = no_door_grid
	jammed.sim.layout.rebuild(no_door_grid)
	for b_idx in 2:
		var bid := 80 + b_idx
		var b := ArrivalBooking.new()
		b.id = bid
		b.party = bid
		b.flight_id = PassengerTestWorld.FLIGHT
		b.unload_tick = 100
		jammed.sim.arrivals._bookings.append(b)
		jammed.sim.arrivals._by_id[bid] = b
		var b_vid := jammed.landside.add_vehicle(
			LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.DROP, [bid] as Array[int]
		)
		b.state = ArrivalBooking.State.IN_VEHICLE
		b.vehicle = b_vid
	# Drive DROP cars into both berths.
	for _i in 350:
		jammed.step()
	var pt := jammed.landside.definition.berth_get_out(0)
	var impatient := PassengerArrivals.spawn(jammed.sim, PassengerTestWorld.FLIGHT, 0)
	impatient.apron = [pt] as Array[Vector3]
	impatient.apron_mm = 0
	impatient.cleared = false
	impatient.at = ReferenceTerminal.ENTRANCE_CELL + LandsideTestWorld.SITE.starter_offset
	impatient.pickup_berth = 0
	jammed.sim._set_stage(impatient, Passenger.Stage.WAIT_CURB_PICKUP)

	var fell_back_to_road := false
	for _i in PassengerArrivals.CURB_PICKUP_PATIENCE_TICKS + 120:
		jammed.step()
		if impatient.stage == Passenger.Stage.TO_ROAD_EXIT:
			fell_back_to_road = true
		if jammed.sim.get_passenger(impatient.id) == null:
			break
	assert_bool(fell_back_to_road).is_true()
	assert_object(jammed.sim.get_passenger(impatient.id)).is_null()


func test_savegame_v47_round_trip_v46_refusal_and_savelinks_pickup_checks() -> void:
	_main = SaveTestKit.boot(self, 202612)
	SaveTestKit.start_airport(_main)
	var clock: SimClock = _main.get_node("SimClock")
	var flights: FlightSim = _main.get_node("FlightSim")
	var sim: PassengerSim = _main.get_node("PassengerSim")
	var landside: LandsideSim = _main.get_node("LandsideSim")
	var offset: Vector2i = sim.site.starter_offset

	for _i in 300:
		SaveTestKit.step(_main)
		if flights.opened_tick >= 0:
			break
	assert_bool(landside.build_lot(0, 0, LandsideLotSpot.Kind.SURFACE)).is_true()

	# Place a PARKED car past PARK_CLAIM_MIN_TICKS directly in LandsideSim.
	var starter_id := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var park_vid := landside.add_vehicle(
		LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK, [999] as Array[int]
	)
	var v_park := landside.get_vehicle(park_vid)
	v_park.lane = LandsideVehicle.Lane.SLOT
	v_park.lot = 0
	v_park.stop = 0
	v_park.pos_mm = landside.paths.slot_stand[0][0]
	v_park.stage = LandsideVehicle.Stage.PARKED
	v_park.bookings.clear()
	v_park.stage_tick = clock.tick
	v_park.leave_tick = clock.tick + LandsideSim.STAY_MIN_TICKS
	landside._rederive()

	# Advance past PARK_CLAIM_MIN_TICKS while keeping SaveGame at a clean tick boundary.
	var target_t := clock.tick + LandsideSim.PARK_CLAIM_MIN_TICKS
	clock.tick = target_t
	sim.tick = target_t
	landside.tick = target_t
	v_park.leave_tick = target_t + LandsideSim.STAY_MIN_TICKS

	# Passenger 1: walking TO_PARKED_CAR claiming v_park.
	var p_car := PassengerArrivals.spawn(sim, starter_id, 0)
	p_car.apron.clear()
	p_car.apron_mm = 0
	p_car.cleared = false
	p_car.at = ReferenceTerminal.ENTRANCE_CELL + offset
	p_car.clear_path()
	p_car.wants_parked_car = true
	p_car.arrival_stop_cap = 0
	sim._set_stage(p_car, Passenger.Stage.TO_ROAD_EXIT)
	PassengerArrivals.advance(sim, p_car)
	assert_int(p_car.stage).is_equal(Passenger.Stage.TO_PARKED_CAR)
	assert_int(p_car.pickup_vehicle).is_equal(v_park.id)
	assert_array(v_park.claimants).is_equal([p_car.id])

	# Passenger 2: waiting at curb WAIT_CURB_PICKUP with an active PICKUP taxi on ROAD_IN.
	var p_curb := PassengerArrivals.spawn(sim, starter_id, 1)
	p_curb.cleared = false
	p_curb.at = ReferenceTerminal.ENTRANCE_CELL + offset
	p_curb.clear_path()
	p_curb.wants_parked_car = false
	p_curb.pickup_berth = 0
	p_curb.apron = [landside.definition.berth_get_out(0)] as Array[Vector3]
	p_curb.apron_mm = 0
	sim._set_stage(p_curb, Passenger.Stage.WAIT_CURB_PICKUP)
	SaveTestKit.step(_main)
	assert_int(landside.active_pickup_taxis()).is_equal(1)

	assert_bool(SaveTestKit.save_game(_main).save_to_file(_save_path)).is_true()

	# Load into a fresh world and verify exact restoration.
	_loaded = SaveTestKit.boot(self, 1234)
	assert_bool(SaveTestKit.save_game(_loaded).load_from_file(_save_path)).is_true()
	var l_sim: PassengerSim = _loaded.get_node("PassengerSim")
	var l_land: LandsideSim = _loaded.get_node("LandsideSim")
	var lp_car := l_sim.get_passenger(p_car.id)
	var lp_curb := l_sim.get_passenger(p_curb.id)
	assert_object(lp_car).is_not_null()
	assert_int(lp_car.stage).is_equal(Passenger.Stage.TO_PARKED_CAR)
	assert_int(lp_car.pickup_vehicle).is_equal(park_vid)
	assert_bool(lp_car.wants_parked_car).is_true()
	assert_object(lp_curb).is_not_null()
	assert_int(lp_curb.stage).is_equal(Passenger.Stage.WAIT_CURB_PICKUP)
	assert_int(lp_curb.pickup_berth).is_equal(0)
	var lv_park := l_land.get_vehicle(park_vid)
	assert_array(lv_park.claimants).is_equal([p_car.id])
	assert_int(l_land.active_pickup_taxis()).is_equal(1)

	# Run loaded world forward: both passengers finish cleanly and car pulls out.
	for _i in 1500:
		SaveTestKit.step(_loaded)
		if (
			l_sim.get_passenger(p_car.id) == null
			and l_sim.get_passenger(p_curb.id) == null
			and l_land.get_vehicle(park_vid) == null
		):
			break
	assert_object(l_sim.get_passenger(p_car.id)).is_null()
	assert_object(l_sim.get_passenger(p_curb.id)).is_null()
	assert_object(l_land.get_vehicle(park_vid)).is_null()

	# Version 46 refusal check + SaveLinks broken claimant link refusal check.
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_save_path))
	assert_int(int(raw["save_version"])).is_equal(SaveGame.SAVE_VERSION)
	var v46: Dictionary = raw.duplicate(true)
	v46["save_version"] = 46
	FileAccess.open(_save_path, FileAccess.WRITE).store_string(JSON.stringify(v46))
	var reject_v46 := SaveTestKit.boot(self, 555)
	assert_bool(SaveTestKit.save_game(reject_v46).load_from_file(_save_path)).is_false()
	reject_v46.free()

	# Break SaveLinks claimant symmetry: vehicle lists claimant that does not exist.
	var broken: Dictionary = raw.duplicate(true)
	for v_rec: Dictionary in broken["landside"]["vehicles"]:
		if int(v_rec["id"]) == park_vid:
			v_rec["claimants"] = [99999]
	FileAccess.open(_save_path, FileAccess.WRITE).store_string(JSON.stringify(broken))
	var reject_link := SaveTestKit.boot(self, 556)
	assert_bool(SaveTestKit.save_game(reject_link).load_from_file(_save_path)).is_false()
	reject_link.free()


func test_arrival_done_snapshot_and_inset_entrance_fallback_via_to_road_from() -> void:
	# (a) arrival_done passengers in TO_PARKED_CAR / WAIT_CURB_PICKUP with cleared pickup fields
	# remain snapshot-valid between finish() and retire_settled().
	var land := _make_world(73)
	for stage in [Passenger.Stage.TO_PARKED_CAR, Passenger.Stage.WAIT_CURB_PICKUP]:
		var p := PassengerArrivals.spawn(land.sim, PassengerTestWorld.FLIGHT, 0)
		p.cleared = false
		p.wants_parked_car = stage == Passenger.Stage.TO_PARKED_CAR
		p.pickup_vehicle = 5 if stage == Passenger.Stage.TO_PARKED_CAR else 0
		p.pickup_berth = 0 if stage == Passenger.Stage.WAIT_CURB_PICKUP else -1
		land.sim._set_stage(p, stage)
		PassengerArrivals.finish(land.sim, p)
		assert_bool(p.arrival_done).is_true()
		assert_int(p.pickup_vehicle).is_equal(0)
		assert_int(p.pickup_berth).is_equal(-1)
	var snap: Dictionary = JSON.parse_string(JSON.stringify(land.sim.to_snapshot()))
	var restored := _make_world(74)
	assert_bool(restored.sim.from_snapshot(snap)).is_true()

	# (b) Inset entrance behind a building wing: both _fallback_from_invalid_car and
	# _reroute_curb_pickup_or_exit route around walls via OutsideWalks.to_road_from
	# without cutting through the wing or stepping out onto road_z.
	var site := LandsideTestWorld.SITE
	var grid := BuildGrid.new(site.grid_size, site.grid_origin)
	ReferenceTerminal.build(grid, LandKit.FIRST_SITE)
	var wing := Rect2i(100, 135, 8, 8)
	var wing_edits: Array[BuildEdit] = []
	for y in range(wing.position.y, wing.end.y):
		for x in range(wing.position.x, wing.end.x):
			wing_edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for res in grid.apply_batch(wing_edits):
		assert_bool(res.ok).is_true()
	EnclosureKit.close_floor(grid)

	var inset := LandsideTestWorld.make(null, [], 77, grid)
	_lands.append(inset)
	assert_bool(inset.landside.build_lot(0, 0, LandsideLotSpot.Kind.SURFACE)).is_true()
	var parked := _park_car_at_tick(inset, 0, 10)
	var here_world := grid.cell_to_world(Vector2i(103, 130))
	var road_z := site.road_z

	# Case 1: parked car invalidated while walking north of wing (here.z <= sidewalk_limit_z).
	var p_car := _spawn_landside_arriving(inset, true)
	p_car.pickup_vehicle = parked.id
	parked.claimants.append(p_car.id)
	p_car.apron = [here_world, _parked_slot_world(inset, parked)] as Array[Vector3]
	p_car.apron_mm = 0
	inset.sim._set_stage(p_car, Passenger.Stage.TO_PARKED_CAR)
	inset.landside._slots[0][parked.stop] = 0
	inset.landside._remove(parked)
	PassengerArrivals.advance(inset.sim, p_car)
	assert_int(p_car.stage).is_equal(Passenger.Stage.TO_CURB_PICKUP)
	assert_bool(inset.landside.is_berth_built(p_car.pickup_berth)).is_true()
	_assert_walk_avoids_wing_and_road_z(
		grid, wing, road_z, inset.landside.definition.berth_get_out(p_car.pickup_berth), p_car.apron
	)

	# Case 2: curb berth unbuilt while walking north of wing (here.z <= sidewalk_limit_z).
	var p_curb := _spawn_landside_arriving(inset, false)
	p_curb.pickup_berth = 2
	p_curb.apron = [here_world, inset.landside.definition.berth_get_out(0)] as Array[Vector3]
	p_curb.apron_mm = 0
	inset.sim._set_stage(p_curb, Passenger.Stage.TO_CURB_PICKUP)
	PassengerArrivals.advance(inset.sim, p_curb)
	assert_int(p_curb.stage).is_equal(Passenger.Stage.TO_CURB_PICKUP)
	assert_int(p_curb.pickup_berth).is_equal(1)
	assert_bool(inset.landside.is_berth_built(p_curb.pickup_berth)).is_true()
	_assert_walk_avoids_wing_and_road_z(
		grid,
		wing,
		road_z,
		inset.landside.definition.berth_get_out(p_curb.pickup_berth) + Vector3(-0.75, 0.0, 0.0),
		p_curb.apron
	)


func _parked_slot_world(land: LandsideTestWorld, v: LandsideVehicle) -> Vector3:
	return land.landside.lot_spot(v.lot).slots[v.stop]


func _assert_walk_avoids_wing_and_road_z(
	grid: BuildGrid, wing: Rect2i, road_z: float, target: Vector3, walk: Array[Vector3]
) -> void:
	assert_int(walk.size()).is_greater_equal(3)
	assert_vector(walk[walk.size() - 1]).is_equal_approx(target, Vector3(0.01, 0.01, 0.01))
	for pt in walk:
		assert_float(absf(pt.z - road_z)).is_greater(0.5)
	for i in range(walk.size() - 1):
		var a := walk[i]
		var b := walk[i + 1]
		var steps := maxi(ceili(a.distance_to(b) / 0.25), 1)
		for s in steps + 1:
			var pt := a.lerp(b, float(s) / float(steps))
			var cell := grid.world_to_cell(pt)
			assert_bool(wing.has_point(cell)).is_false()


func test_curb_pickup_waiters_spread_along_sidewalk_without_stacking() -> void:
	var land := _make_world(81)
	var waiters: Array[Passenger] = []
	for _i in 6:
		var p := _spawn_landside_arriving(land, false)
		PassengerArrivals.advance(land.sim, p)
		assert_int(p.stage).is_equal(Passenger.Stage.TO_CURB_PICKUP)
		waiters.append(p)
	var berth := waiters[0].pickup_berth
	var base := land.landside.definition.berth_get_out(berth)
	for p in waiters:
		assert_int(p.pickup_berth).is_equal(berth)
	var ticks := 0
	while (
		ticks < 4000
		and waiters.any(
			func(p: Passenger) -> bool: return p.stage == Passenger.Stage.TO_CURB_PICKUP
		)
	):
		land.step()
		ticks += 1
	var positions: Array[Vector3] = []
	for p in waiters:
		assert_int(p.stage).is_equal(Passenger.Stage.WAIT_CURB_PICKUP)
		positions.append(p.apron_position())
	for i in positions.size():
		for j in range(i + 1, positions.size()):
			var dist := (
				Vector2(positions[i].x - positions[j].x, positions[i].z - positions[j].z).length()
			)
			assert_float(dist).is_greater_equal(0.70)
	# Row 2 (6th waiter) steps onto the sidewalk (more negative Z), never onto the road.
	assert_float(positions[5].z).is_less_equal(base.z - 0.70)
