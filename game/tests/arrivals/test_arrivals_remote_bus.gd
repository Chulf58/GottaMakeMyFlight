class_name TestArrivalsRemoteBus
extends GdUnitTestSuite
## Arrivals Slice A4: Tier-3 Remote Bus Deplaning (pre-position during TAXI_IN/AT_STAND,
## <= 40 cap during DEBOARDING, drive back to bus_gate_desk bay, unload into
## TO_AIRSIDE_EXIT -> full terminal exit, outbound BOARDING handoff, pose_at symmetry,
## BuiltItemCard inbound labels, ON_BUS isolation, and SaveGame v49 / SaveLinks checks).

const SEED := 7_204_409
const SITE := preload("res://build/terminal_site.tres")

var _main: Node
var _save: SaveGame
var _mode: BuildMode
var _flights: FlightSim
var _pax: PassengerSim
var _staff: StaffSim
var _bus_sim: BusShuttleSim
var _bus_view: BusView
var _hud: PassengerHud
var _inspect: PassengerInspect
var _bus_gate := ""
var _bus_exit_id := 0
var _bus_desk_id := 0
var _base_snap := {}
var _o := Vector2i.ZERO
var _save_path := SaveTestKit.run_path("test_arrivals_remote_bus")


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_save = SaveTestKit.save_game(_main)
	_mode = _main.get_node("BuildMode")
	_flights = _main.get_node("FlightSim")
	_pax = _main.get_node("PassengerSim")
	_staff = _main.get_node("Staff")
	_bus_sim = _main.get_node("BusShuttleSim")
	_bus_view = _main.get_node("BusView")
	_hud = _main.get_node("PassengerHud")
	_inspect = _hud.find_child("PassengerInspect", true, false) as PassengerInspect
	_o = ReferenceTerminal.offset_on(_mode.grid)

	_mode.require_unlocks = false
	_mode.land_tool.land.gated = false
	_flights.runway.size = PlaneClasses.LARGE
	_hud.dismiss_intro()
	SaveTestKit.start_airport(_main)
	for _i in 4000:
		if _flights.opened_tick >= 0:
			break
		SaveTestKit.step(_main)
	assert_int(_flights.opened_tick).is_greater_equal(0)

	_expand_terminal_and_remote_stand()
	_hire_extra_staff()
	for _i in 1800:
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
	_inspect.built_card.selection.kind = BuiltSelection.Kind.NONE
	_inspect.built_card.selection.id = 0


func after_test() -> void:
	DirAccess.remove_absolute(_save_path)
	DirAccess.remove_absolute(_save_path + ".tmp")


func after() -> void:
	if _main != null:
		_main.free()
		_main = null


func _buy_plot_area(cell: Vector2i) -> void:
	for dy in [-36, -18, 0, 18, 36]:
		for dx in [-36, -18, 0, 18, 36]:
			var target := cell + Vector2i(dx, dy)
			var plot := _mode.land_tool.land.plot_of(target)
			if _mode.land_tool.land.in_site(plot) and not _mode.land_tool.land.is_owned(plot):
				LandKit.buy_to(_mode.land_tool.land, plot)


func _expand_terminal_and_remote_stand() -> void:
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

	var place_air_exit := BuildEdit.place_object(
		BuildCatalog.AIRSIDE_EXIT_ID, _o + Vector2i(-25, 8), 2
	)
	for edit: BuildEdit in DoorPlacement.edits_for(_mode.grid, place_air_exit):
		assert_bool(_mode.grid.apply(edit).ok).is_true()

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

	var exit_res := _mode.grid.apply(BuildEdit.place_object(&"exit_door", _o + Vector2i(-20, 2), 0))
	assert_bool(exit_res.ok).is_true()
	_bus_exit_id = exit_res.object_id
	var desk_res := _mode.grid.apply(
		BuildEdit.place_object(GateDesks.BUS_DESK, _o + Vector2i(-20, 5), 0)
	)
	assert_bool(desk_res.ok).is_true()
	_bus_desk_id = desk_res.object_id
	_bus_gate = _flights.bus_gate_ids()[0]

	var r1_cell := _o + Vector2i(-34, -42)
	_buy_plot_area(r1_cell)
	var rs := _mode.grid.apply(BuildEdit.place_object(RemoteStands.STAND_ID, r1_cell, 0))
	assert_bool(rs.ok).is_true()


func _hire_extra_staff() -> void:
	for _i in 12:
		_staff.hire(StaffMember.Role.CHECKIN)
		_staff.hire(StaffMember.Role.SECURITY)
	_staff.hire(StaffMember.Role.GATE)


func _airline_for_07a() -> String:
	for candidate in ["Gotta Air", "Nordic Air", "JetStar", "AirZero", "SkyWay"]:
		if PlaneClasses.model_for(candidate, PlaneClasses.LARGE) == "tp_plane_07a":
			return candidate
	return "Nordic Air"


func _accept_offer(
	offer_index: int, minute: int, size: String, pax: int, airline := "", fee := 25
) -> Dictionary:
	var desk := _main.get_node("OfferDesk") as OfferDesk
	var board := desk.board
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


func _accept_remote_large(id: String, start_min: int, pax := 120) -> Dictionary:
	var a_max := String(_flights.gate_grounds().get("A", {}).get("max_class", ""))
	if a_max == PlaneClasses.LARGE:
		var blk := {
			"id": "BLK" + id,
			"airline": "Gotta Air",
			"destination": "Oslo",
			"departure_minute": start_min - 45,
			"plane_size": PlaneClasses.MEDIUM,
			"booked_passengers": 24,
			"fee_per_passenger": 20,
			FlightContract.TRAITS_KEY: {},
		}
		assert_bool(_flights.accept_contract(blk)).is_true()
	var terms := {
		"id": id,
		"airline": _airline_for_07a(),
		"destination": "Reykjavik",
		"departure_minute": start_min,
		"plane_size": PlaneClasses.LARGE,
		"booked_passengers": pax,
		"fee_per_passenger": 25,
		FlightContract.TRAITS_KEY: {},
	}
	assert_bool(_flights.accept_contract(terms)).is_true()
	return _flights.contract_of(id)


func test_remote_stand_inbound_preposition_cap_exit_and_outbound_boarding() -> void:
	_pax.landside = null
	for sid: int in _pax.layout.desks + _pax.layout.scanners:
		if (_mode.grid.get_object(sid)["anchor"] as Vector2i).x >= _o.x + 10:
			_staff.closures.set_closed(sid, true)

	var contract := _accept_remote_large("REMARR120", 755, 120)
	var day := int(contract["first_day"])
	var occ := FlightTimetable.occurrence_id("REMARR120", day)
	var expected_arr := FlightTimetable.arriving_passengers_for(contract, day, occ)
	assert_int(expected_arr).is_less_equal(BusShuttleSim.BUS_CAPACITY)
	assert_int(expected_arr).is_greater(0)

	var arrived_ids: Array[int] = []
	var finished_ids: Array[int] = []
	var mood_before_bus := {}
	_pax.arrival_spawned.connect(
		func(pid: int) -> void:
			var p := _pax.get_passenger(pid)
			if p != null and p.flight_id == occ:
				arrived_ids.append(pid)
				mood_before_bus[pid] = p.mood
	)
	_pax.arrival_finished.connect(
		func(pid: int) -> void:
			var p := _pax.get_passenger(pid)
			if p != null and p.flight_id == occ:
				finished_ids.append(pid)
	)

	var starts := FlightTimetable.starts_for(contract, day, _flights.epoch)
	var pushback_tick := int(starts[FlightSim.State.PUSHBACK])
	var views := _main.get_node("PassengerViews") as PassengerViews
	var saw_preposition := false
	var saw_wait_at_stand := false
	var saw_inbound_on_bus := false
	var saw_inbound_driving_back := false
	var saw_inbound_unloading := false
	var saw_airside_exit := false

	for _s in 12000:
		if _flights.tick >= pushback_tick and finished_ids.size() >= expected_arr:
			break
		SaveTestKit.step(_main)
		var fst := _flights.state_of(occ)
		var bus := _bus_sim.bus_state(_bus_gate)
		var b_state := int(bus.get("state", BusShuttleSim.State.IDLE_AT_BAY))
		var b_inbound := bool(bus.get("inbound", false))
		if b_inbound and fst in [FlightSim.State.TAXI_IN, FlightSim.State.AT_STAND]:
			if b_state == BusShuttleSim.State.DRIVING_OUT:
				saw_preposition = true
			elif b_state == BusShuttleSim.State.LOADING:
				saw_wait_at_stand = true
		if b_inbound and b_state == BusShuttleSim.State.DRIVING_BACK:
			saw_inbound_driving_back = true
		if b_inbound and b_state == BusShuttleSim.State.UNLOADING:
			saw_inbound_unloading = true
		for pid in arrived_ids:
			var p := _pax.get_passenger(pid)
			if p == null:
				continue
			if p.stage == Passenger.Stage.ON_BUS:
				saw_inbound_on_bus = true
				assert_bool(p.bus_nudged).is_false()
				assert_int(p.mood).is_equal(int(mood_before_bus[pid]))
				assert_bool(views.shows(p)).is_false()
			elif p.stage == Passenger.Stage.TO_AIRSIDE_EXIT:
				saw_airside_exit = true

	assert_bool(saw_preposition).is_true()
	assert_bool(saw_wait_at_stand).is_true()
	assert_bool(saw_inbound_on_bus).is_true()
	assert_bool(saw_inbound_driving_back).is_true()
	assert_bool(saw_inbound_unloading).is_true()
	assert_bool(saw_airside_exit).is_true()
	assert_int(arrived_ids.size()).is_equal(expected_arr)
	assert_int(finished_ids.size()).is_equal(expected_arr)
	assert_int(_flights.arriving_passengers_of(occ)).is_equal(expected_arr)

	# Outbound boarding still completes all 120 departing passengers with zero misses.
	var res: Dictionary = _pax.flight_results.get(occ, {})
	assert_int(int(res.get("made", 0))).is_equal(120)
	assert_int(int(res.get("missed", 0))).is_equal(0)


func test_pose_at_symmetry_and_built_item_card_inbound_labels() -> void:
	var card := _inspect.built_card
	card.selection.kind = BuiltSelection.Kind.OBJECT
	card.selection.id = _bus_desk_id
	card.invalidate()
	_hud.refresh()
	assert_str(card.field_text("shuttle")).is_equal("Shuttle: Idle at bay")

	var bus_entry: Dictionary = _bus_sim._buses[_bus_gate]
	var stand: Dictionary = _flights.remote_stand_grounds()["R1"]["stand"]
	var bay_pose: Dictionary = bus_entry["bay_pose"]
	var stop_pose := BusShuttleRoutes.stop_pose_for(
		stand, "tp_plane_07a", AirstairsPose.ground_y(stand)
	)
	bus_entry["stop_pose"] = stop_pose
	bus_entry["stand_id"] = "R1"
	bus_entry["inbound"] = true
	bus_entry["aboard"] = [101, 102]

	bus_entry["state"] = BusShuttleSim.State.LOADING
	var loading_pose := _bus_sim.pose_at(_bus_gate, float(_bus_sim.tick))
	assert_vector(loading_pose["origin"]).is_equal(stop_pose["origin"])
	assert_float(float(loading_pose["yaw"])).is_equal_approx(float(stop_pose["yaw"]), 1e-4)

	bus_entry["state"] = BusShuttleSim.State.UNLOADING
	var unloading_pose := _bus_sim.pose_at(_bus_gate, float(_bus_sim.tick))
	assert_vector(unloading_pose["origin"]).is_equal(bay_pose["origin"])
	assert_float(float(unloading_pose["yaw"])).is_equal_approx(float(bay_pose["yaw"]), 1e-4)

	for pair in [
		[BusShuttleSim.State.DRIVING_OUT, "Shuttle: Heading to R1 for arrivals"],
		[BusShuttleSim.State.LOADING, "Shuttle: Boarding arrivals at R1 (2)"],
		[BusShuttleSim.State.DRIVING_BACK, "Shuttle: Returning with arrivals (2)"],
		[BusShuttleSim.State.UNLOADING, "Shuttle: Unloading arrivals at bay"],
	]:
		bus_entry["state"] = pair[0]
		card.invalidate()
		_hud.refresh()
		assert_str(card.field_text("shuttle")).is_equal(pair[1])


func test_arriving_on_bus_isolated_from_late_count_flight_result_rescue_and_forecast() -> void:
	_pax.auto_schedule = false
	var contract := _accept_remote_large("ARRISO", 755, 48)
	var day := int(contract["first_day"])
	var occ := FlightTimetable.occurrence_id("ARRISO", day)
	var starts := FlightTimetable.starts_for(contract, day, _flights.epoch)
	var deboard_tick := int(starts[FlightSim.State.DEBOARDING])
	for _s in 12000:
		if _flights.tick >= deboard_tick + 5:
			break
		SaveTestKit.step(_main)
	assert_int(_flights.state_of(occ)).is_equal(FlightSim.State.DEBOARDING)

	var p := PassengerArrivals.spawn(_pax, occ, 0)
	assert_object(p).is_not_null()
	PassengerArrivals.board_bus(_pax, p)
	assert_int(p.stage).is_equal(Passenger.Stage.ON_BUS)
	assert_bool(p.is_arriving()).is_true()

	# LateCount, JourneyForecast, FlightResult, and RescueGrant isolate ARRIVING ON_BUS.
	p.late = true
	assert_dict(LateCount.by_flight(_pax)).is_empty()
	assert_dict(LateCount.tightest_overall(_pax)).is_empty()
	assert_int(LateCount.tightest_passenger(_pax, occ)).is_equal(0)
	assert_int(JourneyForecast.arrival_tick(_pax, p)).is_equal(JourneyForecast.NEVER)
	assert_int(_bus_sim.remaining_ticks_for_passenger(p, _flights.tick)).is_equal(0)

	var grant := _main.get_node("RescueGrant") as RescueGrant
	for oid in _mode.grid.object_ids():
		var def := StringName(_mode.grid.get_object(oid)["def"])
		if def == &"exit_door":
			_mode.grid.apply(BuildEdit.remove_object(oid))
	assert_bool(grant._someone_can_make_a_flight()).is_false()

	var doors_close_tick := _flights.doors_close_tick(occ)
	for _s in 1500:
		if _flights.tick > doors_close_tick + 2:
			break
		SaveTestKit.step(_main)
	var summary := FlightResult.summarize(_pax, occ)
	assert_int(int(summary.get("missed", 0))).is_equal(0)
	assert_int(int(summary.get("made", 0))).is_equal(0)


func test_save_game_v50_round_trip_mid_inbound_driving_back_and_validation() -> void:
	_pax.auto_schedule = false
	assert_int(SaveGame.SAVE_VERSION).is_equal(51)
	assert_int(BusShuttleSnapshot.SNAPSHOT_VERSION).is_equal(2)

	var a_max := String(_flights.gate_grounds().get("A", {}).get("max_class", ""))
	if a_max == PlaneClasses.LARGE:
		_accept_offer(0, 720, PlaneClasses.MEDIUM, 24, "Gotta Air", 25)
	var contract := _accept_offer(
		1 if a_max == PlaneClasses.LARGE else 0, 765, PlaneClasses.LARGE, 48, "Polar Jet", 30
	)
	assert_bool(contract.is_empty()).is_false()
	var cid := String(contract["id"])
	var day := int(contract["first_day"])
	var occ := FlightTimetable.occurrence_id(cid, day)
	var starts := FlightTimetable.starts_for(contract, day, _flights.epoch)
	var deboard_tick := int(starts[FlightSim.State.DEBOARDING])
	for _s in 12000:
		if _flights.tick >= deboard_tick + 2:
			break
		SaveTestKit.step(_main)
	assert_int(_flights.state_of(occ)).is_equal(FlightSim.State.DEBOARDING)

	PassengerArrivals.schedule_deboarding(_pax, occ, 6)
	var saw_driving_back := false
	for _s in 600:
		SaveTestKit.step(_main)
		var st := _bus_sim.bus_state(_bus_gate)
		if (
			bool(st.get("inbound", false))
			and int(st.get("state", 0)) == BusShuttleSim.State.DRIVING_BACK
		):
			saw_driving_back = true
			break
	assert_bool(saw_driving_back).is_true()

	var bus_before := _bus_sim.bus_state(_bus_gate)
	var aboard_before: Array = bus_before["aboard"]
	assert_int(aboard_before.size()).is_equal(6)
	var rider_id := int(aboard_before[0])

	assert_bool(_save.save_to_file(_save_path)).is_true()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_save_path))
	assert_int(int(raw["save_version"])).is_equal(51)

	# Refuse v48 saves.
	var v48 := raw.duplicate(true)
	v48["save_version"] = 48
	var reject := SaveTestKit.boot(self, 991)
	assert_bool(SaveTestKit.save_game(reject).load_world(v48)).is_false()
	reject.free()

	# Refuse inbound SaveLinks non-remote stand & BusShuttleSnapshot non-remote stand.
	var bad_stand := raw.duplicate(true)
	bad_stand["buses"]["buses"][0]["stand_id"] = "A"
	var reject_stand := SaveTestKit.boot(self, 992)
	assert_bool(SaveTestKit.save_game(reject_stand).load_world(bad_stand)).is_false()
	reject_stand.free()
	var bus_dict: Dictionary = (raw["buses"]["buses"][0] as Dictionary).duplicate(true)
	bus_dict["stand_id"] = "A"
	var gate_set: Array[String] = _flights.gate_ids()
	for bg in _flights.bus_gate_ids():
		gate_set.append(bg)
	var flights_dict := FlightSnapshot.load(raw["flights"], gate_set, _flights.epoch)
	assert_bool(flights_dict.has("error")).is_false()
	for f: Dictionary in flights_dict["flights"]:
		if String(f["id"]) == occ:
			f["stand_id"] = "A"
	assert_str(SaveLinks._bus_problem({"buses": [bus_dict]}, flights_dict)).contains("not remote")

	# Load v49 save and run to completion.
	var loaded := SaveTestKit.boot(self, 993)
	assert_bool(SaveTestKit.save_game(loaded).load_from_file(_save_path)).is_true()
	var l_bus: BusShuttleSim = loaded.get_node("BusShuttleSim")
	var l_pax: PassengerSim = loaded.get_node("PassengerSim")
	var l_state := l_bus.bus_state(_bus_gate)
	assert_bool(bool(l_state["inbound"])).is_true()
	assert_int(int(l_state["state"])).is_equal(BusShuttleSim.State.DRIVING_BACK)
	assert_int(l_pax.get_passenger(rider_id).stage).is_equal(Passenger.Stage.ON_BUS)

	for _s in 2500:
		SaveTestKit.step(loaded)
		if l_pax.get_passenger(rider_id) == null:
			break
	assert_object(l_pax.get_passenger(rider_id)).is_null()
	loaded.free()
