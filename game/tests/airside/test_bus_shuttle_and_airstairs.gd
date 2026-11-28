class_name TestBusShuttleAndAirstairs
extends GdUnitTestSuite
## Slice B3: AirstairsPose alignment & docking (04a-07a, 03a omitted),
## coarse apron BFS routing around terminal & north StandEnvelopes, 120-pax
## Large flight boarding in 3 trips inside BOARDING=1200 with -6 mood nudge,
## DOORS_CLOSED unload grace, JourneyForecast bus_cycle_margin, and SaveGame v43.

const SEED := 7_204_319
const SITE := preload("res://build/terminal_site.tres")
const AIRSTAIRS_SCENE := preload("res://assets/airside/props/airstairs.glb")

var _main: Node
var _save: SaveGame
var _mode: BuildMode
var _flights: FlightSim
var _pax: PassengerSim
var _staff: StaffSim
var _airside: Airside
var _apron: ApronStand
var _bus_sim: BusShuttleSim
var _bus_view: BusView
var _bus_gate := ""
var _bus_exit_id := 0
var _base_snap := {}
var _o := Vector2i.ZERO


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_save = SaveTestKit.save_game(_main)
	_mode = _main.get_node("BuildMode")
	_flights = _main.get_node("FlightSim")
	_pax = _main.get_node("PassengerSim")
	_staff = _main.get_node("Staff")
	_airside = _main.get_node("Airside")
	_apron = _main.get_node("ApronStand")
	_bus_sim = _main.get_node("BusShuttleSim")
	_bus_view = _main.get_node("BusView")
	_o = ReferenceTerminal.offset_on(_mode.grid)

	_mode.require_unlocks = false
	_mode.land_tool.land.gated = false
	_flights.runway.size = PlaneClasses.LARGE
	SaveTestKit.start_airport(_main)
	for i in 4000:
		if _flights.opened_tick >= 0:
			break
		SaveTestKit.step(_main)
	assert_int(_flights.opened_tick).is_greater_equal(0)

	_expand_terminal_and_remote_stand()
	_hire_extra_staff()
	for i in 1800:
		SaveTestKit.step(_main)
		if (
			_staff.on_duty_count(StaffMember.Role.CHECKIN) >= 12
			and _staff.on_duty_count(StaffMember.Role.SECURITY) >= 12
			and _staff.on_duty_count(StaffMember.Role.GATE) >= 2
		):
			break
	SaveTestKit.step(_main)
	_base_snap = _save.snapshot()
	assert_bool(_base_snap.is_empty()).is_false()


func before_test() -> void:
	assert_bool(_save.load_world(_base_snap.duplicate(true))).is_true()
	_pax.auto_schedule = true
	_pax.landside = _main.get_node("LandsideSim")


func after() -> void:
	_main.free()


func _buy_plot_area(cell: Vector2i) -> void:
	for dy in [-36, -18, 0, 18, 36]:
		for dx in [-36, -18, 0, 18, 36]:
			var target := cell + Vector2i(dx, dy)
			var plot := _mode.land_tool.land.plot_of(target)
			if _mode.land_tool.land.in_site(plot) and not _mode.land_tool.land.is_owned(plot):
				LandKit.buy_to(_mode.land_tool.land, plot)


func _expand_terminal_and_remote_stand() -> void:
	# Extend starter terminal west along y in [2..17] (landside + airside) so
	# Bus Gate sits well clear of Gate A's LARGE StandEnvelope (x = -28 vs 20).
	var edits: Array[BuildEdit] = []
	for x in range(-36, ReferenceTerminal.FLOOR_MIN.x):
		for y in range(2, 18):
			var c := _o + Vector2i(x, y)
			_buy_plot_area(c)
			edits.append(BuildEdit.paint_floor(c, BuildGrid.FLOOR_TILE, 1))
	for y in range(2, 18):
		edits.append(
			BuildEdit.remove_wall(
				_o + Vector2i(ReferenceTerminal.FLOOR_MIN.x, y), BuildGrid.Side.WEST
			)
		)
	for x in range(-36, ReferenceTerminal.FLOOR_MIN.x):
		if x != -20:
			edits.append(BuildEdit.place_wall(_o + Vector2i(x, 2), BuildGrid.Side.NORTH))
		edits.append(BuildEdit.place_wall(_o + Vector2i(x, 17), BuildGrid.Side.SOUTH))
		if not [-22, -19, -16, -13, -10, -7, -4, -1, 2, 5].has(x):
			edits.append(BuildEdit.place_wall(_o + Vector2i(x, 9), BuildGrid.Side.NORTH))
	for y in range(2, 18):
		edits.append(BuildEdit.place_wall(_o + Vector2i(-36, y), BuildGrid.Side.WEST))
	assert_bool(_mode.grid.apply_sequence(edits, Callable()).ok).is_true()

	for eid in _pax.layout.passenger_entrances.duplicate():
		var old_cell := _pax.layout.door_cell(_mode.grid, eid)
		assert_bool(_mode.grid.apply(BuildEdit.remove_object(eid)).ok).is_true()
		(
			assert_bool(_mode.grid.apply(BuildEdit.place_wall(old_cell, BuildGrid.Side.SOUTH)).ok)
			. is_true()
		)
	(
		assert_bool(
			_mode.grid.apply(BuildEdit.place_object(&"entrance_door", _o + Vector2i(-14, 17), 2)).ok
		)
		. is_true()
	)

	# Add 10 west check-in desks + 10 west security scanners (12 each total), x-disjoint.
	for dx in [-24, -21, -18, -15, -12, -9, -6, -3, 0, 3]:
		(
			assert_bool(
				(
					_mode
					. grid
					. apply(BuildEdit.place_object(&"checkin_desk", _o + Vector2i(dx, 11), 0))
					. ok
				)
			)
			. is_true()
		)
	for sx in [-22, -19, -16, -13, -10, -7, -4, -1, 2, 5]:
		(
			assert_bool(
				(
					_mode
					. grid
					. apply(BuildEdit.place_object(&"security_scanner", _o + Vector2i(sx, 8), 0))
					. ok
				)
			)
			. is_true()
		)

	# Bus Gate exit + desk on the west wing, clear of Gate A's LARGE StandEnvelope.
	var exit_res := _mode.grid.apply(BuildEdit.place_object(&"exit_door", _o + Vector2i(-20, 2), 0))
	assert_bool(exit_res.ok).is_true()
	_bus_exit_id = exit_res.object_id
	var desk_res := _mode.grid.apply(
		BuildEdit.place_object(GateDesks.BUS_DESK, _o + Vector2i(-20, 5), 0)
	)
	assert_bool(desk_res.ok).is_true()
	_bus_gate = _flights.bus_gate_ids()[0]

	# Remote Stand R1 on owned apron north-west of west wing, clear of Gate A LARGE envelope.
	var r1_cell := _o + Vector2i(-34, -42)
	_buy_plot_area(r1_cell)
	var rs := _mode.grid.apply(BuildEdit.place_object(RemoteStands.STAND_ID, r1_cell, 0))
	assert_bool(rs.ok).is_true()
	assert_str(_flights.remote_stand_grounds()["R1"]["max_class"]).is_equal(PlaneClasses.LARGE)


func _hire_extra_staff() -> void:
	for _i in 12:
		_staff.hire(StaffMember.Role.CHECKIN)
		_staff.hire(StaffMember.Role.SECURITY)
	_staff.hire(StaffMember.Role.GATE)


func _medium_terms(id: String, minute: int, pax := 24) -> Dictionary:
	return {
		"id": id,
		"airline": "Gotta Air",
		"destination": "Oslo",
		"departure_minute": minute,
		"plane_size": PlaneClasses.MEDIUM,
		"booked_passengers": pax,
		"fee_per_passenger": 20,
		FlightContract.TRAITS_KEY: {},
	}


func _airline_for_07a() -> String:
	for candidate in ["Gotta Air", "Nordic Air", "JetStar", "AirZero", "SkyWay"]:
		if PlaneClasses.model_for(candidate, PlaneClasses.LARGE) == "tp_plane_07a":
			return candidate
	return "Nordic Air"


func _large_remote_terms(id: String, minute: int, pax := 120) -> Dictionary:
	return {
		"id": id,
		"airline": _airline_for_07a(),
		"destination": "Reykjavik",
		"departure_minute": minute,
		"plane_size": PlaneClasses.LARGE,
		"booked_passengers": pax,
		"fee_per_passenger": 25,
		FlightContract.TRAITS_KEY: {},
	}


func _accept_offer(
	offer_index: int, minute: int, size: String, pax: int, airline := "", fee := 25
) -> Dictionary:
	var desk := _main.get_node("OfferDesk") as OfferDesk
	var board := desk.board
	if board.open_offers().is_empty():
		var clock := _main.get_node("SimClock") as SimClock
		var day_now := GameCalendar.day_of(clock.tick, clock.epoch)
		(
			assert_array(
				board.refill_day(day_now, clock.rng.seed, 0, _flights.runway.size, _flights)
			)
			. is_not_empty()
		)
	var snap := board.to_snapshot()
	var open := board.open_offers()
	assert_int(open.size()).is_greater(offer_index)
	var target_id := String(open[offer_index]["id"])
	for entry: Dictionary in snap["offers"]:
		if String(entry["id"]) == target_id:
			if airline != "":
				entry["airline"] = airline
			entry["departure_minute"] = minute
			entry["plane_size"] = size
			entry["booked_passengers"] = pax
			entry["fee_per_passenger"] = fee
			entry[OfferBoard.LOYAL_KEY] = false
			entry[OfferBoard.LOYAL_TIER_KEY] = OfferBoard.LOYALTY_TIER_NONE
			entry[OfferBoard.HUB_KEY] = false
			entry[FlightContract.TRAITS_KEY] = OfferTraits.frozen({})
			break
	assert_bool(board.from_snapshot(snap)).is_true()
	assert_bool(board.accept(target_id, _flights)).is_true()
	return _flights.contract_of(target_id)


func _accept_remote(id: String, start_min: int, pax := 120) -> Dictionary:
	var a_max := String(_flights.gate_grounds().get("A", {}).get("max_class", ""))
	if a_max == PlaneClasses.LARGE:
		if not _flights.accept_contract(_medium_terms("BLK" + id, start_min - 45, 24)):
			return {}
	if not _flights.accept_contract(_large_remote_terms(id, start_min, pax)):
		return {}
	return _flights.contract_of(id)


func test_airstairs_pose_alignment_and_03a_omitted() -> void:
	assert_bool(AirstairsPose.docks("tp_plane_03a")).is_false()
	var stand: Dictionary = _flights.remote_stand_grounds()["R1"]["stand"]
	var ground := AirstairsPose.ground_y(stand)
	var inst := auto_free(AIRSTAIRS_SCENE.instantiate()) as Node3D
	add_child(inst)
	var joints := AirstairsPose.joints_of(inst)
	assert_dict(joints).is_not_empty()
	var mount_top := inst.find_child("Mount_TopDoor", true, false) as Node3D
	assert_object(mount_top).is_not_null()

	for model in ["tp_plane_04a", "tp_plane_05a", "tp_plane_06a", "tp_plane_07a"]:
		assert_bool(AirstairsPose.docks(model)).is_true()
		var pose := AirstairsPose.pose_for(stand, model, ground)
		assert_bool(bool(pose["docks"])).is_true()
		assert_bool(bool(pose["ok"])).is_true()
		assert_int((pose["waypoints"] as PackedVector3Array).size()).is_equal(4)
		inst.transform = pose["root"]
		AirstairsPose.apply(joints, pose)
		var expected_door: Vector3 = JetBridgePose.plane_door(stand, model, ground)["door"]
		var actual_door := mount_top.global_position
		assert_float(actual_door.distance_to(expected_door)).is_less(0.01)


func _assert_route_clear(
	route: PackedVector3Array, swing_rects: Array[Rect2], nose_gap_rects: Array[Rect2]
) -> void:
	for i in range(1, route.size()):
		var a := route[i - 1]
		var b := route[i]
		var dist := Vector2(b.x - a.x, b.z - a.z).length()
		var steps := maxi(1, int(ceil(dist / 0.5)))
		for s in range(1, steps):
			var pt3 := a.lerp(b, float(s) / float(steps))
			var pt2 := Vector2(pt3.x, pt3.z)
			for rect: Rect2 in swing_rects + nose_gap_rects:
				assert_bool(rect.has_point(pt2)).is_false()
			var cell := _mode.grid.world_to_cell(pt3)
			if _mode.grid.in_bounds(cell):
				assert_int(_mode.grid.floor_at(cell)).is_equal(BuildGrid.FLOOR_NONE)


func test_coarse_apron_bfs_avoids_terminal_and_north_stand_envelopes() -> void:
	# Place a second remote stand R2 east of Gate A so Gate A sits directly across
	# the straight chord from the west-wing Bus Gate, AND build a north-jutting
	# terminal pier directly across the chord to R1.
	var r2_cell := _o + Vector2i(68, -40)
	_buy_plot_area(r2_cell)
	var r2_res := _mode.grid.apply(BuildEdit.place_object(RemoteStands.STAND_ID, r2_cell, 0))
	assert_bool(r2_res.ok).is_true()

	var pier_edits: Array[BuildEdit] = []
	for px in range(-26, -17):
		for py in range(-20, -9):
			var c := _o + Vector2i(px, py)
			_buy_plot_area(c)
			pier_edits.append(BuildEdit.paint_floor(c, BuildGrid.FLOOR_TILE, 1))
	assert_bool(_mode.grid.apply_sequence(pier_edits, Callable()).ok).is_true()

	var bus_grounds := _flights.bus_gate_grounds()
	var rem_grounds := _flights.remote_stand_grounds()
	var reg_stands: Array[Dictionary] = []
	for g: Dictionary in _flights.gate_grounds().values():
		reg_stands.append(g["stand"])
	var gate_stand := StandPlacement.for_exit(_mode.grid, int(bus_grounds[_bus_gate]["exit"]))
	var bay_pose := BusShuttleRoutes.bay_pose_for(gate_stand, SITE)
	var rem_stands := {}
	for sid: String in rem_grounds:
		rem_stands[sid] = rem_grounds[sid]["stand"]

	var swing_rects: Array[Rect2] = []
	var nose_gap_rects: Array[Rect2] = []
	for st: Dictionary in reg_stands:
		var env := StandEnvelope.rects(st, PlaneClasses.LARGE)
		swing_rects.append(env[0])
		var twin := StandPlacement.north_twin(st)
		var at := StandPlacement.stand_point(twin)
		var swing := StandEnvelope.radius(PlaneClasses.LARGE)
		var gap := Rect2(
			at.x - swing, at.z + StandPlacement.NOSE_M, 2.0 * swing, StandPlacement.NOSE_GAP_M
		)
		for r: Rect2 in StandPlacement.rects_to_world(st, [gap]):
			nose_gap_rects.append(r)

	var all_models := [
		"tp_plane_03a", "tp_plane_04a", "tp_plane_05a", "tp_plane_06a", "tp_plane_07a"
	]
	for sid: String in ["R1", "R2"]:
		var rem_stand: Dictionary = rem_grounds[sid]["stand"]
		var gy := AirstairsPose.ground_y(rem_stand)
		for model: String in all_models:
			var stop_pose := BusShuttleRoutes.stop_pose_for(rem_stand, model, gy)
			if AirstairsPose.docks(model):
				var stair := AirstairsPose.pose_for(rem_stand, model, gy)
				var entry_z := float((stair["bottom_entry"] as Vector3).z)
				var door_z := BusShuttleRoutes.bus_door_world(stop_pose, 0).z
				assert_float(door_z - entry_z).is_between(2.65, 2.95)
			var route := BusShuttleRoutes.plan_route(
				_mode.grid,
				bay_pose["origin"],
				stop_pose["origin"],
				reg_stands,
				rem_stands,
				sid,
				model
			)
			assert_int(route.size()).override_failure_message("%s %s" % [sid, model]).is_greater(2)
			assert_float(BusShuttleRoutes.route_length(route)).is_greater(10.0)
			_assert_route_clear(route, swing_rects, nose_gap_rects)


func test_large_120_pax_07a_boards_in_three_trips_with_mood_nudge() -> void:
	_pax.landside = null
	for sid: int in _pax.layout.desks + _pax.layout.scanners:
		if (_mode.grid.get_object(sid)["anchor"] as Vector2i).x >= _o.x + 10:
			_staff.closures.set_closed(sid, true)
	var start_min := 755
	var rem_contract := _accept_remote("BUS120", start_min, 120)
	assert_bool(rem_contract.is_empty()).is_false()
	assert_str(String(rem_contract["stand"])).is_equal("R1")
	assert_str(String(rem_contract["gate"])).is_equal(_bus_gate)
	var day := int(rem_contract["first_day"])
	var occ := FlightTimetable.occurrence_id("BUS120", day)
	var starts := FlightTimetable.starts_for(rem_contract, day, _flights.epoch)

	var departures: Array[int] = []
	var depart_ticks: Array[int] = []
	_bus_sim.bus_departed.connect(
		func(gate: String, fid: String, count: int) -> void:
			if gate == _bus_gate and fid == occ:
				departures.append(count)
				depart_ticks.append(_flights.tick)
	)
	var nudged_ids := {}
	var missed_info: Array[String] = []
	_pax.outcome.connect(
		func(pid: int, made: bool) -> void:
			var p := _pax.get_passenger(pid)
			if p == null or p.flight_id != occ:
				return
			if not made:
				(
					missed_info
					. append(
						(
							"id=%d arr=%d spawn=%d at=%s stage=%d"
							% [
								pid,
								p.arrival_type,
								p.spawn_tick,
								str(p.at - _o),
								p.missed_stage,
							]
						)
					)
				)
				return
			assert_bool(p.bus_nudged).is_true()
			var bus_thoughts := 0
			for e in PassengerThoughts.entries(p):
				if int(e["kind"]) == PassengerThoughts.Kind.BUS_RIDE:
					bus_thoughts += 1
					assert_str(String(e["text"])).is_equal("Shuttle ride to the plane")
			assert_int(bus_thoughts).is_equal(1)
			nudged_ids[pid] = true
	)

	var target_pushback := int(starts[FlightSim.State.PUSHBACK])
	var checked_dock := false
	var fleet := _main.get_node("PlaneFleet") as PlaneFleet
	for _s in 12000:
		if _flights.tick >= target_pushback:
			break
		SaveTestKit.step(_main)
		if _flights.state_of(occ) == FlightSim.State.BOARDING and not checked_dock:
			assert_str(PlaneClasses.flight_model(_flights, occ)).is_equal("tp_plane_07a")
			fleet._process(0.016)
			for v in fleet.views:
				v._process(0.016)
			assert_bool(bool(_airside.props.airstairs_nodes["R1"]["docked"])).is_true()
			assert_bool(_airside.props.airstairs_nodes.has("A")).is_false()
			checked_dock = true
	assert_bool(checked_dock).is_true()
	assert_int(departures.size()).is_greater_equal(3)

	var res: Dictionary = _pax.flight_results.get(occ, {})
	(
		assert_int(int(res.get("made", 0)))
		. override_failure_message(
			(
				"departures=%s at=%s close=%d final=%d results=%s missed=%s"
				% [
					str(departures),
					str(depart_ticks),
					_flights.doors_close_tick(occ),
					_bus_sim.final_call_tick_for(occ),
					str(res),
					str(missed_info),
				]
			)
		)
		. is_equal(120)
	)
	assert_int(int(res.get("missed", 0))).is_equal(0)
	assert_int(nudged_ids.size()).is_equal(120)


func test_doors_closed_grace_lets_on_bus_make_it_and_misses_terminal_stragglers() -> void:
	_pax.auto_schedule = false
	var start_min := 755
	var rem_contract := _accept_remote("BUSGRACE", start_min, 48)
	assert_bool(rem_contract.is_empty()).is_false()
	assert_str(String(rem_contract["stand"])).is_equal("R1")
	var day := int(rem_contract["first_day"])
	var occ := FlightTimetable.occurrence_id("BUSGRACE", day)
	var starts := FlightTimetable.starts_for(rem_contract, day, _flights.epoch)

	var boarding_tick := int(starts[FlightSim.State.BOARDING])
	for _s in 12000:
		if _flights.tick >= boarding_tick:
			break
		SaveTestKit.step(_main)
	assert_int(_flights.state_of(occ)).is_equal(FlightSim.State.BOARDING)

	# Step to right before final-call bus departure, then place one rider at the
	# door (who catches the last bus) and one straggler back in the terminal.
	var final_call := _bus_sim.final_call_tick_for(occ)
	for _s in 2000:
		if _flights.tick >= final_call - 5:
			break
		SaveTestKit.step(_main)

	var rider := _pax.get_passenger(_pax.spawn_now(occ))
	rider.cleared = true
	rider.at = _pax.layout.door_cell(_mode.grid, _bus_exit_id)
	rider.clear_path()
	_pax._set_stage(rider, Passenger.Stage.TO_EXIT)
	rider.exit_object = _bus_exit_id

	var straggler := _pax.get_passenger(_pax.spawn_now(occ))
	straggler.cleared = true
	straggler.at = _o + Vector2i(18, 8)
	straggler.clear_path()
	_pax._set_stage(straggler, Passenger.Stage.TO_GATE)

	var doors_close_tick := int(starts[FlightSim.State.DOORS_CLOSED])
	for _s in 200:
		if _flights.tick >= doors_close_tick + 1:
			break
		SaveTestKit.step(_main)

	# On the tick DOORS_CLOSED starts: straggler inside terminal is MISSED immediately,
	# while the ON_BUS rider survives DOORS_CLOSED and finishes MADE before PUSHBACK.
	assert_int(_flights.state_of(occ)).is_equal(FlightSim.State.DOORS_CLOSED)
	assert_int(straggler.stage).is_equal(Passenger.Stage.MISSED)
	assert_bool(rider.is_done()).is_false()
	(
		assert_bool(
			(
				_bus_sim.bus_state(_bus_gate)["aboard"].has(rider.id)
				or rider.stage == Passenger.Stage.APRON
			)
		)
		. is_true()
	)

	for _s in 120:
		if _flights.state_of(occ) != FlightSim.State.DOORS_CLOSED:
			break
		SaveTestKit.step(_main)
	assert_int(rider.stage).is_equal(Passenger.Stage.MADE)


func test_journey_forecast_bus_cycle_margin_triggers_earlier_lateness() -> void:
	_pax.auto_schedule = false
	var start_min := 755
	assert_bool(_flights.accept_contract(_medium_terms("REGCMP", start_min - 45, 24))).is_true()
	assert_bool(_flights.accept_contract(_large_remote_terms("REMCMP", start_min, 48))).is_true()
	var reg_c := _flights.contract_of("REGCMP")
	var rem_c := _flights.contract_of("REMCMP")
	assert_str(String(reg_c["stand"])).is_equal("A")
	assert_str(String(rem_c["stand"])).is_equal("R1")
	var reg_occ := FlightTimetable.occurrence_id("REGCMP", int(reg_c["first_day"]))
	var rem_occ := FlightTimetable.occurrence_id("REMCMP", int(rem_c["first_day"]))
	for _s in 12000:
		if _flights.state_of(rem_occ) == FlightSim.State.BOARDING:
			break
		SaveTestKit.step(_main)
	assert_int(_flights.state_of(rem_occ)).is_equal(FlightSim.State.BOARDING)

	assert_int(JourneyForecast.bus_cycle_margin(_pax, reg_occ)).is_equal(0)
	var margin := JourneyForecast.bus_cycle_margin(_pax, rem_occ)
	assert_int(margin).is_greater(40)

	var target := _flights.doors_close_tick(rem_occ) - margin + 10
	for _s in 1500:
		if _flights.tick >= target - 25:
			break
		SaveTestKit.step(_main)

	var p_reg := _pax.get_passenger(_pax.spawn_now(reg_occ))
	var p_rem := _pax.get_passenger(_pax.spawn_now(rem_occ))
	p_reg.cleared = true
	p_reg.at = _o + Vector2i(15, 5)
	p_reg.clear_path()
	_pax._set_stage(p_reg, Passenger.Stage.TO_EXIT)

	p_rem.cleared = true
	p_rem.at = _o + Vector2i(-15, 5)
	p_rem.clear_path()
	_pax._set_stage(p_rem, Passenger.Stage.TO_EXIT)

	var eta_reg := JourneyForecast.arrival_tick(_pax, p_reg)
	var eta_rem := JourneyForecast.arrival_tick(_pax, p_rem)
	assert_int(eta_rem).is_greater(eta_reg)

	for _s in 40:
		if _flights.tick >= target:
			break
		SaveTestKit.step(_main)
	assert_bool(p_rem.late).is_true()
	assert_bool(p_reg.late).is_false()


func test_save_game_round_trip_mid_bus_trip_and_prev_version_rejected() -> void:
	_pax.auto_schedule = false
	assert_int(SaveGame.SAVE_VERSION).is_greater_equal(44)
	assert_int(PassengerSim.SAVE_VERSION).is_greater_equal(41)

	var start_min := 765
	var a_max := String(_flights.gate_grounds().get("A", {}).get("max_class", ""))
	if a_max == PlaneClasses.LARGE:
		_accept_offer(0, start_min - 45, PlaneClasses.MEDIUM, 24, "Gotta Air", 25)
	var rem_contract := _accept_offer(
		1 if a_max == PlaneClasses.LARGE else 0, start_min, PlaneClasses.LARGE, 48, "Polar Jet", 30
	)
	assert_bool(rem_contract.is_empty()).is_false()
	assert_str(String(rem_contract["stand"])).is_equal("R1")
	var cid := String(rem_contract["id"])
	var occ := FlightTimetable.occurrence_id(cid, int(rem_contract["first_day"]))
	for _s in 12000:
		if _flights.state_of(occ) == FlightSim.State.BOARDING:
			break
		SaveTestKit.step(_main)
	assert_int(_flights.state_of(occ)).is_equal(FlightSim.State.BOARDING)

	var rider := _pax.get_passenger(_pax.spawn_now(occ))
	var mood_before := rider.mood
	rider.cleared = true
	rider.at = _pax.layout.door_cell(_mode.grid, _bus_exit_id)
	rider.exit_object = _bus_exit_id
	rider.clear_path()
	_pax._set_stage(rider, Passenger.Stage.TO_EXIT)

	for _s in 1200:
		if _bus_sim.bus_state(_bus_gate)["state"] == BusShuttleSim.State.DRIVING_OUT:
			break
		SaveTestKit.step(_main)
	assert_int(_bus_sim.bus_state(_bus_gate)["state"]).is_equal(BusShuttleSim.State.DRIVING_OUT)
	assert_int(rider.stage).is_equal(Passenger.Stage.ON_BUS)
	assert_bool(rider.bus_nudged).is_true()
	assert_int(rider.mood).is_less_equal(maxi(mood_before - BusShuttleSim.BUS_RIDE_MOOD_PENALTY, 0))

	var snap := _save.snapshot()
	# Direct check of exact -6 comfort delta and single thought emission on board_bus.
	var probe := _pax.get_passenger(_pax.spawn_now(occ))
	probe.at = _pax.layout.door_cell(_mode.grid, _bus_exit_id)
	var probe_mood := probe.mood
	PassengerGates.board_bus(_pax, probe, BusShuttleSim.BUS_RIDE_MOOD_PENALTY)
	assert_int(probe.mood).is_equal(maxi(probe_mood - BusShuttleSim.BUS_RIDE_MOOD_PENALTY, 0))
	PassengerGates.board_bus(_pax, probe, BusShuttleSim.BUS_RIDE_MOOD_PENALTY)
	assert_int(probe.mood).is_equal(maxi(probe_mood - BusShuttleSim.BUS_RIDE_MOOD_PENALTY, 0))
	var json_copy: Dictionary = JSON.parse_string(JSON.stringify(snap, "", true, true))
	assert_int(int(json_copy["save_version"])).is_equal(SaveGame.SAVE_VERSION)
	assert_bool(json_copy.has("buses")).is_true()

	var prev := json_copy.duplicate(true)
	prev["save_version"] = SaveGame.SAVE_VERSION - 1
	assert_bool(_save.load_world(prev)).is_false()

	assert_bool(_save.load_world(_base_snap.duplicate(true))).is_true()
	assert_bool(_save.load_world(json_copy)).is_true()
	var reloaded_rider := _pax.get_passenger(rider.id)
	assert_int(reloaded_rider.stage).is_equal(Passenger.Stage.ON_BUS)
	assert_int(_bus_sim.bus_state(_bus_gate)["state"]).is_equal(BusShuttleSim.State.DRIVING_OUT)
	assert_int(_bus_view.active_count()).is_greater_equal(1)

	for _s in 1400:
		var st := _flights.state_of(occ)
		if st == -1 or st >= FlightSim.State.PUSHBACK:
			break
		SaveTestKit.step(_main)
	assert_int(reloaded_rider.stage).is_equal(Passenger.Stage.MADE)


func test_late_straggler_after_final_call_never_boards_and_misses_at_doors_closed() -> void:
	_pax.auto_schedule = false
	var start_min := 755
	var rem_contract := _accept_remote("BUSFCALL", start_min, 48)
	assert_bool(rem_contract.is_empty()).is_false()
	var day := int(rem_contract["first_day"])
	var occ := FlightTimetable.occurrence_id("BUSFCALL", day)
	var starts := FlightTimetable.starts_for(rem_contract, day, _flights.epoch)
	var boarding_tick := int(starts[FlightSim.State.BOARDING])
	for _s in 12000:
		if _flights.tick >= boarding_tick:
			break
		SaveTestKit.step(_main)
	assert_int(_flights.state_of(occ)).is_equal(FlightSim.State.BOARDING)

	var final_call := _bus_sim.final_call_tick_for(occ)
	for _s in 2000:
		if _flights.tick >= final_call - 5:
			break
		SaveTestKit.step(_main)

	var early_rider := _pax.get_passenger(_pax.spawn_now(occ))
	early_rider.cleared = true
	early_rider.at = _pax.layout.door_cell(_mode.grid, _bus_exit_id)
	early_rider.exit_object = _bus_exit_id
	early_rider.clear_path()
	_pax._set_stage(early_rider, Passenger.Stage.TO_EXIT)

	for _s in 20:
		if _flights.tick >= final_call:
			break
		SaveTestKit.step(_main)
	assert_int(_bus_sim.bus_state(_bus_gate)["state"]).is_equal(BusShuttleSim.State.DRIVING_OUT)
	assert_int(early_rider.stage).is_equal(Passenger.Stage.ON_BUS)

	# Straggler arrives at the bus door strictly between final_call and doors_close.
	var straggler := _pax.get_passenger(_pax.spawn_now(occ))
	straggler.cleared = true
	straggler.at = _pax.layout.door_cell(_mode.grid, _bus_exit_id)
	straggler.exit_object = _bus_exit_id
	straggler.clear_path()
	_pax._set_stage(straggler, Passenger.Stage.TO_EXIT)

	var missed_on_bus := 0
	var on_outcome := func(pid: int, made: bool) -> void:
		var p := _pax.get_passenger(pid)
		if (
			p != null
			and p.flight_id == occ
			and not made
			and p.missed_stage == Passenger.Stage.ON_BUS
		):
			missed_on_bus += 1
	_pax.outcome.connect(on_outcome)

	var doors_close := int(starts[FlightSim.State.DOORS_CLOSED])
	for _s in 100:
		if _flights.tick >= doors_close:
			break
		SaveTestKit.step(_main)
		if _flights.tick < doors_close:
			assert_int(straggler.stage).is_equal(Passenger.Stage.TO_EXIT)
			assert_bool(straggler.bus_nudged).is_false()

	SaveTestKit.step(_main)
	assert_int(straggler.stage).is_equal(Passenger.Stage.MISSED)
	assert_int(straggler.missed_stage).is_equal(Passenger.Stage.TO_EXIT)
	assert_bool(straggler.bus_nudged).is_false()

	for _s in 120:
		if _flights.state_of(occ) >= FlightSim.State.PUSHBACK:
			break
		SaveTestKit.step(_main)
	_pax.outcome.disconnect(on_outcome)
	assert_int(early_rider.stage).is_equal(Passenger.Stage.MADE)
	assert_int(missed_on_bus).is_equal(0)

	# Guard: if an active bus flight disappears during LOADING, _step_loading resets to IDLE_AT_BAY.
	var fake_bus := _bus_sim._buses[_bus_gate] as Dictionary
	fake_bus["state"] = BusShuttleSim.State.LOADING
	fake_bus["flight_id"] = "MISSING_FLIGHT"
	_bus_sim._step_loading(fake_bus)
	assert_int(int(fake_bus["state"])).is_equal(BusShuttleSim.State.IDLE_AT_BAY)


func test_unload_settle_smooth_yaw_spacing_and_clock_fallback() -> void:
	_pax.auto_schedule = false
	var start_min := 755
	var rem_contract := _accept_remote("BUSVIS", start_min, 48)
	assert_bool(rem_contract.is_empty()).is_false()
	var day := int(rem_contract["first_day"])
	var occ := FlightTimetable.occurrence_id("BUSVIS", day)
	var starts := FlightTimetable.starts_for(rem_contract, day, _flights.epoch)
	var boarding_tick := int(starts[FlightSim.State.BOARDING])
	for _s in 12000:
		if _flights.tick >= boarding_tick:
			break
		SaveTestKit.step(_main)

	var riders: Array[Passenger] = []
	for _i in 8:
		var r := _pax.get_passenger(_pax.spawn_now(occ))
		r.cleared = true
		r.at = _pax.layout.door_cell(_mode.grid, _bus_exit_id)
		r.exit_object = _bus_exit_id
		r.clear_path()
		_pax._set_stage(r, Passenger.Stage.TO_EXIT)
		riders.append(r)

	for _s in 150:
		if _bus_sim.bus_state(_bus_gate)["state"] == BusShuttleSim.State.DRIVING_OUT:
			break
		SaveTestKit.step(_main)
	assert_int(_bus_sim.bus_state(_bus_gate)["state"]).is_equal(BusShuttleSim.State.DRIVING_OUT)

	# clock == null fallback in bus_position_for_passenger and WALK_MM vs BRISK_APRON_MM forecast.
	var saved_clock := _bus_sim.clock
	_bus_sim.clock = null
	var fallback_pos := _bus_sim.bus_position_for_passenger(riders[0].id)
	assert_bool(fallback_pos != Vector3.ZERO).is_true()
	_bus_sim.clock = saved_clock
	var close_tick := _flights.doors_close_tick(occ)
	var rem_before := _bus_sim.remaining_ticks_for_passenger(riders[0], _flights.tick)
	var rem_after := _bus_sim.remaining_ticks_for_passenger(riders[0], close_tick)
	assert_int(rem_before).is_greater(rem_after)

	# Smooth yaw at start of DRIVING_OUT.
	var out_start := float(_bus_sim.bus_state(_bus_gate)["start_tick"])
	var drive_pose0 := _bus_sim.pose_at(_bus_gate, out_start)
	var bay_yaw := float(_bus_sim.bus_state(_bus_gate)["bay_pose"]["yaw"])
	assert_float(absf(angle_difference(float(drive_pose0["yaw"]), bay_yaw))).is_less(0.01)

	for _s in 300:
		if _bus_sim.bus_state(_bus_gate)["state"] == BusShuttleSim.State.UNLOADING:
			break
		SaveTestKit.step(_main)
	assert_int(_bus_sim.bus_state(_bus_gate)["state"]).is_equal(BusShuttleSim.State.UNLOADING)

	# Spread across 4 doors and enroll unloaded riders into BoardingFiles apron lanes.
	var saw_filed := false
	for _s in 30:
		SaveTestKit.step(_main)
		for r in riders:
			if r.stage == Passenger.Stage.APRON and not _pax.files.plane_file_of(r.id).is_empty():
				saw_filed = true
		if (_bus_sim.bus_state(_bus_gate)["aboard"] as Array).is_empty():
			break
	assert_bool(saw_filed).is_true()

	# Bus stays in UNLOADING during UNLOAD_SETTLE_TICKS, then eases yaw on DRIVING_BACK.
	assert_int(_bus_sim.bus_state(_bus_gate)["state"]).is_equal(BusShuttleSim.State.UNLOADING)
	for _s in BusShuttleSim.UNLOAD_SETTLE_TICKS + 2:
		if _bus_sim.bus_state(_bus_gate)["state"] == BusShuttleSim.State.DRIVING_BACK:
			break
		SaveTestKit.step(_main)
	assert_int(_bus_sim.bus_state(_bus_gate)["state"]).is_equal(BusShuttleSim.State.DRIVING_BACK)
	var stop_yaw := float(_bus_sim.bus_state(_bus_gate)["stop_pose"]["yaw"])
	var back_start := float(_bus_sim.bus_state(_bus_gate)["start_tick"])
	var back_pose0 := _bus_sim.pose_at(_bus_gate, back_start)
	assert_float(absf(angle_difference(float(back_pose0["yaw"]), stop_yaw))).is_less(0.01)


func test_snapshot_links_rescue_grant_and_late_count_on_bus_guards() -> void:
	_pax.auto_schedule = false
	var start_min := 765
	var a_max := String(_flights.gate_grounds().get("A", {}).get("max_class", ""))
	if a_max == PlaneClasses.LARGE:
		_accept_offer(0, start_min - 45, PlaneClasses.MEDIUM, 24, "Gotta Air", 25)
	var rem_contract := _accept_offer(
		1 if a_max == PlaneClasses.LARGE else 0, start_min, PlaneClasses.LARGE, 48, "Polar Jet", 30
	)
	assert_bool(rem_contract.is_empty()).is_false()
	var cid := String(rem_contract["id"])
	var occ := FlightTimetable.occurrence_id(cid, int(rem_contract["first_day"]))
	for _s in 12000:
		if _flights.state_of(occ) == FlightSim.State.BOARDING:
			break
		SaveTestKit.step(_main)

	var rider := _pax.get_passenger(_pax.spawn_now(occ))
	rider.cleared = true
	rider.at = _pax.layout.door_cell(_mode.grid, _bus_exit_id)
	rider.exit_object = _bus_exit_id
	rider.clear_path()
	_pax._set_stage(rider, Passenger.Stage.TO_EXIT)

	for _s in 1200:
		if _bus_sim.bus_state(_bus_gate)["state"] == BusShuttleSim.State.DRIVING_OUT:
			break
		SaveTestKit.step(_main)
	assert_int(rider.stage).is_equal(Passenger.Stage.ON_BUS)

	# LateCount.tightest_passenger skips ON_BUS riders.
	rider.late = true
	assert_int(LateCount.tightest_passenger(_pax, occ)).is_equal(0)
	var visible_late := _pax.get_passenger(_pax.spawn_now(occ))
	visible_late.late = true
	assert_int(LateCount.tightest_passenger(_pax, occ)).is_equal(visible_late.id)

	# SaveGame / BusShuttleSnapshot / SaveLinks validation for model and stand_id.
	var snap: Dictionary = JSON.parse_string(JSON.stringify(_save.snapshot(), "", true, true))
	var bad_type: Dictionary = snap.duplicate(true)
	bad_type["buses"]["buses"][0]["model"] = 123
	assert_bool(_save.load_world(bad_type)).is_false()

	var bad_model: Dictionary = snap.duplicate(true)
	bad_model["buses"]["buses"][0]["model"] = "tp_plane_99z"
	assert_bool(_save.load_world(bad_model)).is_false()

	var bad_stand: Dictionary = snap.duplicate(true)
	bad_stand["buses"]["buses"][0]["stand_id"] = "R99"
	assert_bool(_save.load_world(bad_stand)).is_false()

	var bad_link_model: Dictionary = snap.duplicate(true)
	bad_link_model["buses"]["buses"][0]["model"] = "tp_plane_05a"
	assert_bool(_save.load_world(bad_link_model)).is_false()
	assert_str(_save.message_text()).contains("model")

	# RescueGrant treats ON_BUS identically to APRON (can still finish without terminal exits).
	var grant := _main.get_node("RescueGrant") as RescueGrant
	for oid in _mode.grid.object_ids():
		var def := StringName(_mode.grid.get_object(oid)["def"])
		if def == &"exit_door":
			_mode.grid.apply(BuildEdit.remove_object(oid))
	_pax._passengers.erase(visible_late)
	_pax._by_id.erase(visible_late.id)
	assert_bool(grant._someone_can_make_a_flight()).is_true()
