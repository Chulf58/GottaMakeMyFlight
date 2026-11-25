class_name TestRemoteStandTimetableAndPlanner
extends GdUnitTestSuite
## Slice B2: Remote Stand timetable & nearest Bus Gate auto-pairing,
## [TAXI_IN, DOORS_CLOSED + bus_return] bus-gate spans, >40-pax charter rule,
## FlightPlanner & DeparturesBoard remote UI, airside ops parity, and save v42.

const SEED := 7_204_211
const SITE := preload("res://build/terminal_site.tres")

var _main: Node
var _save: SaveGame
var _mode: BuildMode
var _flights: FlightSim
var _gates: GateDesks
var _planner: FlightPlanner
var _board: DeparturesBoard
var _fleet: PlaneFleet
var _ramp: RampDispatch
var _staff: StaffSim
var _bg_near := ""
var _bg_far := ""
var _bg_near_desk := 0
var _bg_far_desk := 0
var _base_snap := {}


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_save = SaveTestKit.save_game(_main)
	_mode = _main.get_node("BuildMode")
	_flights = _main.get_node("FlightSim")
	_gates = _main.get_node("GateDesks")
	_planner = _main.get_node("PassengerHud/FlightPlanner")
	_board = _main.get_node("PassengerHud/DeparturesBoard")
	_fleet = _main.get_node("PlaneFleet")
	_ramp = _main.get_node("RampDispatch")
	_staff = _main.get_node("Staff")
	_board.settings_path = SaveTestKit.run_path("remote_b2_board")
	_mode.require_unlocks = false
	_mode.land_tool.land.gated = false
	_flights.runway.size = PlaneClasses.LARGE
	SaveTestKit.start_airport(_main)
	for i in 4000:
		if _flights.opened_tick >= 0:
			break
		SaveTestKit.step(_main)
	assert_int(_flights.opened_tick).is_greater_equal(0)

	# Build a west wing with two Bus Gate Desks at different distances from R1/R2.
	var wing := _ensure_west_bay_wing()
	var exit_far := wing + Vector2i(2, 0)
	var exit_near := wing + Vector2i(18, 0)
	assert_bool(_mode.grid.apply(BuildEdit.place_object(&"exit_door", exit_far, 0)).ok).is_true()
	assert_bool(_mode.grid.apply(BuildEdit.place_object(&"exit_door", exit_near, 0)).ok).is_true()

	var r_far := _mode.grid.apply(
		BuildEdit.place_object(GateDesks.BUS_DESK, wing + Vector2i(1, 2), 0)
	)
	assert_bool(r_far.ok).is_true()
	_bg_far_desk = r_far.object_id
	_bg_far = _flights.bus_gate_ids()[0]

	var r_near := _mode.grid.apply(
		BuildEdit.place_object(GateDesks.BUS_DESK, wing + Vector2i(17, 2), 0)
	)
	assert_bool(r_near.ok).is_true()
	_bg_near_desk = r_near.object_id
	for bg in _flights.bus_gate_ids():
		if bg != _bg_far:
			_bg_near = bg

	# Place R1 (closer to exit_near) and R2 (further west) on owned apron cells.
	var r1_cell := SITE.starter_offset + Vector2i(-25, -45)
	var r2_cell := SITE.starter_offset + Vector2i(-50, -45)
	for c in [r1_cell, r2_cell]:
		_buy_plot_area(c)
	(
		assert_bool(_mode.grid.apply(BuildEdit.place_object(RemoteStands.STAND_ID, r1_cell, 0)).ok)
		. is_true()
	)
	(
		assert_bool(_mode.grid.apply(BuildEdit.place_object(RemoteStands.STAND_ID, r2_cell, 0)).ok)
		. is_true()
	)
	assert_array(_flights.remote_stand_ids()).is_equal(["R1", "R2"])
	var r_cart := _mode.grid.apply(
		BuildEdit.place_object(BaggageSim.CART_DEF, wing + Vector2i(10, 3), 0)
	)
	assert_bool(r_cart.ok).is_true()
	SaveTestKit.step(_main)
	_base_snap = _save.snapshot()
	assert_bool(_base_snap.is_empty()).is_false()


func before_test() -> void:
	assert_bool(_save.load_world(_base_snap.duplicate(true))).is_true()


func after() -> void:
	if _planner.is_open():
		_planner.close()
	_main.free()


func _buy_plot_area(cell: Vector2i) -> void:
	for dy in [-20, 0, 20]:
		for dx in [-20, 0, 20]:
			var target := cell + Vector2i(dx, dy)
			var plot := _mode.land_tool.land.plot_of(target)
			if _mode.land_tool.land.in_site(plot) and not _mode.land_tool.land.is_owned(plot):
				LandKit.buy_to(_mode.land_tool.land, plot)


func _ensure_west_bay_wing() -> Vector2i:
	var wing_origin := SITE.starter_offset + Vector2i(-42, 0)
	for x in range(0, 20):
		for y in range(0, 6):
			var c := wing_origin + Vector2i(x, y)
			_buy_plot_area(c)
			_mode.grid.apply(BuildEdit.paint_floor(c, 1, 0))
	for x in range(0, 20):
		_mode.grid.apply(
			BuildEdit.place_wall(
				wing_origin + Vector2i(x, 0), BuildGrid.Side.NORTH, BuildGrid.WallKind.PLAIN
			)
		)
		_mode.grid.apply(
			BuildEdit.place_wall(
				wing_origin + Vector2i(x, 5), BuildGrid.Side.SOUTH, BuildGrid.WallKind.PLAIN
			)
		)
	for y in range(0, 6):
		_mode.grid.apply(
			BuildEdit.place_wall(
				wing_origin + Vector2i(0, y), BuildGrid.Side.WEST, BuildGrid.WallKind.PLAIN
			)
		)
		_mode.grid.apply(
			BuildEdit.place_wall(
				wing_origin + Vector2i(19, y), BuildGrid.Side.EAST, BuildGrid.WallKind.PLAIN
			)
		)
	return wing_origin


func _medium_terms(id: String, minute: int, pax := 30) -> Dictionary:
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


func _charter_terms(id: String, minute: int, pax: int) -> Dictionary:
	var terms := _medium_terms(id, minute, pax)
	terms[FlightContract.ONE_OFF_DAY_KEY] = GameCalendar.day_of(_flights.tick, _flights.epoch)
	return terms


func test_nearest_bus_gate_pairing_staggered_reuse_and_clash_refusal() -> void:
	# Occupy regular gate A at 14:00 ([11:47..15:02]) and 18:10 ([15:57..19:12]).
	assert_bool(_flights.accept_contract(_medium_terms("REG1", 840))).is_true()
	assert_str(_flights.contract_of("REG1")["gate"]).is_equal("A")
	assert_bool(_flights.accept_contract(_medium_terms("REG2", 1090))).is_true()
	assert_str(_flights.contract_of("REG2")["gate"]).is_equal("A")

	# Remove far bus gate so only _bg_near exists first, then verify staggered vs clash.
	assert_bool(_mode.grid.apply(BuildEdit.remove_object(_bg_far_desk)).ok).is_true()
	assert_array(_flights.bus_gate_ids()).is_equal([_bg_near])

	# REM1 at 14:30 (30 min after REG1 so runway is free while A is busy) -> R1 + _bg_near.
	assert_bool(_flights.accept_contract(_medium_terms("REM1", 870))).is_true()
	var c1 := _flights.contract_of("REM1")
	assert_str(c1["stand"]).is_equal("R1")
	assert_str(c1["gate"]).is_equal(_bg_near)

	# REM3 at 15:00 finds R2 stand free, yet _bg_near's bus span clashes when no 2nd Bus Gate exists.
	var clash_trial := _flights.trial_assignment(_medium_terms("REM3", 900))
	assert_str(clash_trial["gate"]).is_empty()
	assert_str(clash_trial["blocker"]).is_equal(FlightSim.BLOCKER_GATE)
	assert_bool(_flights.accept_contract(_medium_terms("REM3", 900))).is_false()

	# REM2 at 17:40 (190 min later): overlaps REG2 on A, overlaps REM1 on R1 (5 min),
	# while [TAXI_IN, DOORS_CLOSED + bus_return] bus spans do not overlap -> R2 reuses _bg_near.
	var s1 := FlightTimetable.starts_for(c1, 0, 0)
	assert_bool(_flights.accept_contract(_medium_terms("REM2", 1060))).is_true()
	var c2 := _flights.contract_of("REM2")
	var s2 := FlightTimetable.starts_for(c2, 0, 0)
	assert_str(c2["stand"]).is_equal("R2")
	assert_str(c2["gate"]).is_equal(_bg_near)
	(
		assert_bool(
			FlightTimetable.holds_overlap(
				s1[0], s1[FlightSim.State.DEPARTED], s2[0], s2[FlightSim.State.DEPARTED]
			)
		)
		. is_true()
	)
	assert_bool(BusGatePairing.bus_holds_overlap(s1, s2)).is_false()

	# Reload baseline (both bus gates present) and verify nearest bus gate is picked for R1.
	assert_bool(_save.load_world(_base_snap.duplicate(true))).is_true()
	assert_bool(_flights.accept_contract(_medium_terms("REG1B", 840))).is_true()
	assert_bool(_flights.accept_contract(_medium_terms("REMNEAR", 870))).is_true()
	var c_near := _flights.contract_of("REMNEAR")
	assert_str(c_near["stand"]).is_equal("R1")
	assert_str(c_near["gate"]).is_equal(_bg_near)


func test_charters_prefer_regular_gates_and_reject_over_40_pax_on_remote() -> void:
	# Regular gate A free at 15:00 -> 45-pax charter takes regular gate A.
	var ch_big_reg := _charter_terms("CHBIG1", 900, 45)
	assert_bool(_flights.accept_contract(ch_big_reg)).is_true()
	assert_str(_flights.contract_of("CHBIG1")["gate"]).is_equal("A")
	assert_str(_flights.contract_of("CHBIG1")["stand"]).is_equal("A")

	# Regular gate A free at 18:30 -> <=40-pax charter also prefers regular gate A first.
	var ch_small_reg := _charter_terms("CHSML1", 1110, 35)
	assert_bool(_flights.accept_contract(ch_small_reg)).is_true()
	assert_str(_flights.contract_of("CHSML1")["gate"]).is_equal("A")
	assert_str(_flights.contract_of("CHSML1")["stand"]).is_equal("A")

	# Regular gate A busy at 12:00 ([09:47..13:02]) -> <=40-pax charter at 12:30 uses R1.
	assert_bool(_flights.accept_contract(_medium_terms("BLK12", 720))).is_true()
	assert_str(_flights.contract_of("BLK12")["gate"]).is_equal("A")
	var ch_small_rem := _charter_terms("CHSML2", 750, 40)
	assert_bool(_flights.accept_contract(ch_small_rem)).is_true()
	assert_str(_flights.contract_of("CHSML2")["stand"]).is_equal("R1")
	assert_str(_flights.contract_of("CHSML2")["gate"]).is_equal(_bg_near)

	# Occupy regular gate A at 20:15 -> >40-pax charter at 20:45 MUST NOT go to R2 (refused).
	assert_bool(_flights.accept_contract(_medium_terms("BLK20", 1215))).is_true()
	var ch_over := _charter_terms("CHOVER", 1245, 45)
	var trial := _flights.trial_assignment(ch_over)
	assert_str(trial["gate"]).is_empty()
	assert_bool(_flights.accept_contract(ch_over)).is_false()

	# With no regular gates at all (remote-only stands), >40-pax charter gets BLOCKER_CHARTER_CAPACITY.
	var rem_only := auto_free(FlightSim.new()) as FlightSim
	rem_only.opened_tick = 0
	rem_only.gate_source = func() -> Array[String]: return [] as Array[String]
	rem_only.bus_gate_source = func() -> Array[String]: return ["D"] as Array[String]
	rem_only.remote_stand_source = func() -> Array[String]: return ["R1"] as Array[String]
	rem_only.remote_ground_source = func() -> Dictionary:
		return {"R1": _flights.remote_stand_grounds()["R1"]}
	var ch_only_rem := _charter_terms("CHONLY", 900, 45)
	ch_only_rem[FlightContract.ONE_OFF_DAY_KEY] = 0
	var rem_trial := rem_only.trial_assignment(ch_only_rem)
	assert_str(rem_trial["gate"]).is_empty()
	assert_str(rem_trial["blocker"]).is_equal(FlightSim.BLOCKER_CHARTER_CAPACITY)
	(
		assert_str(FlightFit.text(FlightFit.assess(rem_only, ch_only_rem), PlaneClasses.MEDIUM))
		. contains("40")
	)


func test_move_between_regular_and_remote_and_bus_gate_removal() -> void:
	# Accept contract on regular gate A.
	assert_bool(_flights.accept_contract(_medium_terms("MOV1", 900))).is_true()
	assert_str(_flights.contract_of("MOV1")["gate"]).is_equal("A")

	# Move to R1 via DeparturesBoard.move_outcome -> auto-pairs nearest Bus Gate (_bg_near).
	var to_r1 := DeparturesBoard.move_outcome(_flights, "MOV1", "R1")
	assert_bool(to_r1["moved"]).is_true()
	assert_str(to_r1["text"]).contains("R1")
	assert_str(to_r1["text"]).contains(_bg_near)
	assert_str(_flights.contract_of("MOV1")["stand"]).is_equal("R1")
	assert_str(_flights.contract_of("MOV1")["gate"]).is_equal(_bg_near)

	# Remove _bg_near while _bg_far exists -> succeeds and re-pairs MOV1 to _bg_far!
	var rem_near := _mode.grid.apply(BuildEdit.remove_object(_bg_near_desk))
	assert_bool(rem_near.ok).is_true()
	assert_str(_flights.contract_of("MOV1")["stand"]).is_equal("R1")
	assert_str(_flights.contract_of("MOV1")["gate"]).is_equal(_bg_far)

	# Remove _bg_far (last Bus Gate) while MOV1 is on R1 -> refused cleanly (never falls back to A).
	var rem_far_fail := _mode.grid.apply(BuildEdit.remove_object(_bg_far_desk))
	assert_bool(rem_far_fail.ok).is_false()
	assert_int(rem_far_fail.reason).is_equal(BuildResult.Reason.GATE_FLIGHTS_STUCK)

	# Move MOV1 back to regular gate A -> now removing _bg_far succeeds cleanly.
	var to_a := DeparturesBoard.move_outcome(_flights, "MOV1", "A")
	assert_bool(to_a["moved"]).is_true()
	assert_str(_flights.contract_of("MOV1")["stand"]).is_equal("A")
	assert_str(_flights.contract_of("MOV1")["gate"]).is_equal("A")
	var rem_far_ok := _mode.grid.apply(BuildEdit.remove_object(_bg_far_desk))
	assert_bool(rem_far_ok.ok).is_true()


func _accept_via_offer_board(offer_index: int, minute: int) -> Dictionary:
	var desk := _main.get_node("OfferDesk") as OfferDesk
	var board := desk.board
	var snap := board.to_snapshot()
	var open := board.open_offers()
	assert_int(open.size()).is_greater(offer_index)
	var target_id := String(open[offer_index]["id"])
	for entry: Dictionary in snap["offers"]:
		if String(entry["id"]) == target_id:
			entry["departure_minute"] = minute
			entry["plane_size"] = PlaneClasses.MEDIUM
			entry["booked_passengers"] = 30
			entry["fee_per_passenger"] = 25
			entry[FlightContract.TRAITS_KEY] = OfferTraits.frozen({})
			break
	assert_bool(board.from_snapshot(snap)).is_true()
	assert_bool(board.accept(target_id, _flights)).is_true()
	return _flights.contract_of(target_id)


func test_planner_departures_board_airside_ops_and_save_v42() -> void:
	# Hire ramp staff so RampDispatch can service pushback on R1.
	_staff.hire(StaffMember.Role.RAMP)
	# Occupy A at 12:00 so the second accepted offer at 12:30 lands on R1 paired with _bg_near.
	_accept_via_offer_board(0, 720)
	var c := _accept_via_offer_board(1, 750)
	var rem_id := String(c["id"])
	assert_str(c["stand"]).is_equal("R1")
	assert_str(c["gate"]).is_equal(_bg_near)

	# FlightPlanner shows A, R1, R2 rows, distinguishes Remote R1, and shows "Bus <gate>" on bar.
	_planner.open()
	_planner.refresh()
	assert_array(_planner.row_gates()).is_equal(["A", "R1", "R2"])
	var head_r1 := _planner.part("GateHead_R1") as PanelContainer
	assert_object(head_r1).is_not_null()
	var head_label := head_r1.get_child(0) as Label
	assert_str(head_label.text).is_equal("Remote R1")
	var day := int(c["first_day"])
	var bar := _planner.bar_button(rem_id, day)
	assert_object(bar).is_not_null()
	assert_str(FlightPlanner.bar_text(bar)).contains("Bus %s" % _bg_near)
	assert_str(bar.tooltip_text).contains("Remote R1")
	assert_str(bar.tooltip_text).contains("Bus %s" % _bg_near)

	# DeparturesBoard shows "<bus_gate> → R1" on remote flight row.
	var entries := DeparturesBoard.entries_for(_flights, _flights.tick)
	var rem_entry := {}
	for entry in entries:
		if entry.get("contract", "") == rem_id:
			rem_entry = entry
			break
	assert_bool(rem_entry.is_empty()).is_false()
	assert_str(DeparturesBoard._line_two_text(rem_entry)).contains("%s → R1" % _bg_near)

	# SaveGame v42 round-trip preserves remote contract + paired bus gate.
	var snap := _save.snapshot()
	var json_copy: Dictionary = JSON.parse_string(JSON.stringify(snap, "", true, true))
	assert_int(int(json_copy["save_version"])).is_equal(42)
	assert_bool(_save.load_world(json_copy)).is_true()
	var reloaded := _flights.contract_of(rem_id)
	assert_str(reloaded["stand"]).is_equal("R1")
	assert_str(reloaded["gate"]).is_equal(_bg_near)

	# Step until <rem_id>-d<day> reaches DOORS_CLOSED and verify PlaneFleet / PlaneView / RampDispatch.
	var occ := FlightTimetable.occurrence_id(rem_id, int(reloaded["first_day"]))
	var target_tick := (
		FlightTimetable
		. starts_for(reloaded, int(reloaded["first_day"]), _flights.epoch)[
			FlightSim.State.DOORS_CLOSED
		]
	)
	while _flights.tick < target_tick:
		SaveTestKit.step(_main)
	assert_int(_flights.state_of(occ)).is_equal(FlightSim.State.DOORS_CLOSED)
	assert_str(_flights.flight_stand_id(occ)).is_equal("R1")
	assert_str(_flights.flight_gate(occ)).is_equal(_bg_near)

	_fleet.update_views()
	assert_bool(_fleet.gates.has("R1")).is_true()
	assert_bool(_fleet.gates.has(_bg_near)).is_false()
	var r1_view: PlaneView = null
	for v in _fleet.views:
		if v.gate == "R1" and v.slot == 0:
			r1_view = v
			break
	assert_object(r1_view).is_not_null()
	r1_view.update_pose()
	assert_str(r1_view.flight_id).is_equal(occ)

	var pushback_worker := _ramp._worker_for_flight(occ, StaffMember.RampJob.PUSHBACK)
	assert_object(pushback_worker).is_not_null()

	# Verify BaggageSim._shuttle_plan targets R1's stand (cargo point at remote stand).
	var bag_sim := _main.get_node("BaggageSim") as BaggageSim
	var cart_ids := _mode.grid.object_ids().filter(
		func(oid: int) -> bool:
			return StringName(_mode.grid.get_object(oid).get("def", &"")) == BaggageSim.CART_DEF
	)
	assert_array(cart_ids).is_not_empty()
	var plan := bag_sim._shuttle_plan(int(cart_ids[0]), occ, _flights.flight_stand(occ))
	var expected_cargo := BaggageShuttle.cargo_point(
		_gates.remote_stands["R1"]["stand"], PlaneClasses.flight_model(_flights, occ)
	)
	assert_vector(Vector2(plan["target"].x, plan["target"].z)).is_equal_approx(
		Vector2(expected_cargo.x, expected_cargo.z), Vector2(0.05, 0.05)
	)


func _small_terms(id: String, minute: int, pax := 6) -> Dictionary:
	return {
		"id": id,
		"airline": "Sunhop",
		"destination": "Bergen",
		"departure_minute": minute,
		"plane_size": PlaneClasses.SMALL,
		"booked_passengers": pax,
		"fee_per_passenger": 20,
		FlightContract.TRAITS_KEY: {},
	}


func test_unissued_charter_blocks_r1_removal_and_finished_day0_allows_later_days() -> void:
	# Occupy Gate A at 20:00 and accept an unissued <=40-pax charter onto R1 at 20:30.
	assert_bool(_flights.accept_contract(_medium_terms("BLK20R", 1200))).is_true()
	var ch_terms := _charter_terms("CHREM", 1230, 30)
	assert_bool(_flights.accept_contract(ch_terms)).is_true()
	assert_str(_flights.contract_of("CHREM")["stand"]).is_equal("R1")
	assert_array(_flights.flight_ids()).not_contains(["CHREM-d0"])
	assert_bool(_flights.scheduled_contract_ids().has("CHREM")).is_true()
	assert_str(_gates.booked_class("R1")).is_equal(PlaneClasses.MEDIUM)
	var rem_res := _mode.grid.apply(
		BuildEdit.remove_object(_gates.remote_stands["R1"]["object_id"])
	)
	assert_bool(rem_res.ok).is_false()
	assert_int(rem_res.reason).is_equal(BuildResult.Reason.REMOTE_STAND_IN_USE)

	# Day-0 charters on R1 must not block Day-2 repeating accepts or Day-2 moves onto R1.
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.runway.size = PlaneClasses.LARGE
	var reg_grounds := _flights.gate_grounds()
	var rem_grounds := _flights.remote_stand_grounds()
	var bus_grounds := _flights.bus_gate_grounds()
	var bg_id := _bg_near
	sim.gate_source = func() -> Array[String]: return ["A"]
	sim.stand_source = func() -> Dictionary: return reg_grounds
	sim.remote_stand_source = func() -> Array[String]: return ["R1"]
	sim.remote_ground_source = func() -> Dictionary: return {"R1": rem_grounds["R1"]}
	sim.bus_gate_source = func() -> Array[String]: return [bg_id]
	sim.bus_ground_source = func() -> Dictionary: return {bg_id: bus_grounds[bg_id]}
	sim.open_airport()

	assert_bool(sim.accept_contract(_medium_terms("MOVEREP", 660))).is_true()
	var ch0a := _medium_terms("CHDAY0A", 690, 30)
	ch0a[FlightContract.ONE_OFF_DAY_KEY] = 0
	assert_bool(sim.accept_contract(ch0a)).is_true()
	assert_bool(sim.accept_contract(_medium_terms("BLK18", 1110))).is_true()
	var ch0b := _medium_terms("CHDAY0B", 1140, 30)
	ch0b[FlightContract.ONE_OFF_DAY_KEY] = 0
	assert_bool(sim.accept_contract(ch0b)).is_true()
	assert_str(sim.contract_of("CHDAY0A")["stand"]).is_equal("R1")
	assert_str(sim.contract_of("CHDAY0B")["stand"]).is_equal("R1")

	var cha := sim.contract_of("CHDAY0A")
	var chb := sim.contract_of("CHDAY0B")
	var chb_starts := FlightTimetable.starts_for(chb, 0, sim.epoch)
	for t in [
		FlightTimetable.issue_tick(cha, 0, sim.epoch),
		FlightTimetable.issue_tick(chb, 0, sim.epoch),
		chb_starts[FlightSim.State.DEPARTED],
		FlightTimetable.prune_tick(chb_starts) + 10,
	]:
		sim.on_tick(t)
	sim.on_tick(GameCalendar.day_start(2, sim.epoch) + 100)

	assert_bool(sim.reassign_gate("MOVEREP", "R1")).is_true()
	assert_str(sim.contract_of("MOVEREP")["stand"]).is_equal("R1")
	assert_bool(sim.accept_contract(_medium_terms("DAY2R", 1140))).is_true()
	assert_str(sim.contract_of("DAY2R")["stand"]).is_equal("R1")
	assert_int(int(sim.contract_of("DAY2R")["first_day"])).is_greater_equal(2)


func test_small_bus_hold_tail_skips_busy_bus_gate_and_fit_keeps_remote_grounds() -> void:
	# Occupy Gate A at 15:00 ([12:47..16:02]) so both SMREM (14:30) and CHTAIL (15:42)
	# overflow off A onto Remote Stands without REG1S colliding on taxi.
	assert_bool(_flights.accept_contract(_medium_terms("REG1S", 900))).is_true()
	assert_bool(_flights.accept_contract(_small_terms("SMREM", 870))).is_true()
	var sm_c := _flights.contract_of("SMREM")
	assert_str(sm_c["stand"]).is_equal("R1")
	assert_str(sm_c["gate"]).is_equal(_bg_near)

	# SMALL charter at 942 overlaps only the tail of SMREM's bus_hold_span on _bg_near:
	# nearest_free_bus_gate must detect the overlap, skip _bg_near, and pair R2 + _bg_far.
	var ch_tail := _small_terms("CHTAIL", 942, 6)
	ch_tail[FlightContract.ONE_OFF_DAY_KEY] = GameCalendar.day_of(_flights.tick, _flights.epoch)
	var sm_starts := FlightTimetable.starts_for(sm_c, 0, _flights.epoch)
	var sm_bus := BusGatePairing.bus_hold_span(sm_starts)
	var ch_trial := _flights.trial_assignment(ch_tail)
	assert_str(ch_trial["stand"]).is_equal("R2")
	assert_str(ch_trial["gate"]).is_equal(_bg_far)
	assert_bool(_flights.accept_contract(ch_tail)).is_true()
	var ch_c := _flights.contract_of("CHTAIL")
	var ch_starts := FlightTimetable.starts_for(ch_c, 0, _flights.epoch)
	assert_int(ch_starts[FlightSim.State.TAXI_IN]).is_less(sm_bus[1])
	assert_bool(BusGatePairing.bus_holds_overlap(sm_starts, ch_starts)).is_true()

	# FlightFit.assess with a live remote-stand flight (SMREM at 870) and only 1 Bus Gate
	# must keep R1 in world["grounds"] and return another_gate_helps == false on runway clash.
	assert_bool(_save.load_world(_base_snap.duplicate(true))).is_true()
	assert_bool(_mode.grid.apply(BuildEdit.remove_object(_bg_far_desk)).ok).is_true()
	assert_bool(_flights.accept_contract(_medium_terms("REGA", 840))).is_true()
	assert_bool(_flights.accept_contract(_medium_terms("REMR", 870))).is_true()
	var fit := FlightFit.assess(_flights, _medium_terms("CLASHR", 870))
	assert_bool(fit["fits"]).is_false()
	assert_bool(fit["another_gate_helps"]).is_false()
