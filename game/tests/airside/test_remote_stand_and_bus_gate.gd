class_name TestRemoteStandAndBusGate
extends GdUnitTestSuite
## Slice B1: Tier-3 bus_gate_desk & remote_stand build items, 16x6 m bus bay
## and StandEnvelope clearance, automatic taxi paving, no jet bridge on bus
## gates or remote stands, FlightContract/FlightSim gate vs stand split, and
## SaveGame SAVE_VERSION 42 round-trip.

const SEED := 7_204_109
const SITE := preload("res://build/terminal_site.tres")

var _main: Node
var _save: SaveGame
var _mode: BuildMode
var _flights: FlightSim
var _gates: GateDesks
var _airside: Airside
var _apron: ApronStand


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_save = SaveTestKit.save_game(_main)
	_mode = _main.get_node("BuildMode")
	_flights = _main.get_node("FlightSim")
	_gates = _main.get_node("GateDesks")
	_airside = _main.get_node("Airside")
	_apron = _main.get_node("ApronStand")
	_mode.require_unlocks = false
	_mode.land_tool.land.gated = false
	SaveTestKit.start_airport(_main)
	for i in 4000:
		if _flights.opened_tick >= 0:
			break
		SaveTestKit.step(_main)
	assert_int(_flights.opened_tick).is_greater_equal(0)


func after() -> void:
	_main.free()


func _buy_plot_for(cell: Vector2i) -> void:
	var plot := _mode.land_tool.land.plot_of(cell)
	if _mode.land_tool.land.in_site(plot) and not _mode.land_tool.land.is_owned(plot):
		LandKit.buy_to(_mode.land_tool.land, plot)


func _ensure_west_bay_wing() -> Vector2i:
	# Starter shell spans [0..26, 0..15] relative to SITE.starter_offset.
	# Build a second west wing far enough from Gate A's stand envelope.
	var wing_origin := SITE.starter_offset + Vector2i(-42, 0)
	for x in range(0, 20):
		for y in range(0, 6):
			var c := wing_origin + Vector2i(x, y)
			_buy_plot_for(c)
			_mode.grid.apply(BuildEdit.paint_floor(c, 1, 0))
	for x in range(0, 20):
		var north_c := wing_origin + Vector2i(x, 0)
		_mode.grid.apply(
			BuildEdit.place_wall(north_c, BuildGrid.Side.NORTH, BuildGrid.WallKind.PLAIN)
		)
		var south_c := wing_origin + Vector2i(x, 5)
		_mode.grid.apply(
			BuildEdit.place_wall(south_c, BuildGrid.Side.SOUTH, BuildGrid.WallKind.PLAIN)
		)
	for y in range(0, 6):
		var west_c := wing_origin + Vector2i(0, y)
		_mode.grid.apply(
			BuildEdit.place_wall(west_c, BuildGrid.Side.WEST, BuildGrid.WallKind.PLAIN)
		)
		var east_c := wing_origin + Vector2i(19, y)
		_mode.grid.apply(
			BuildEdit.place_wall(east_c, BuildGrid.Side.EAST, BuildGrid.WallKind.PLAIN)
		)
	return wing_origin


func test_tier_3_unlock_and_demo_mode_teaser() -> void:
	assert_int(BuildUnlocks.tier_of(BuildMode.Tool.BUS_GATE_DESK)).is_equal(3)
	assert_int(BuildUnlocks.tier_of(BuildMode.Tool.REMOTE_STAND)).is_equal(3)
	var req: Dictionary = BuildUnlocks.TIERS[2]
	assert_float(float(req["stars"])).is_equal_approx(3.0, 0.001)
	assert_int(int(req["passengers"])).is_equal(120)
	assert_bool(DemoMode.MAX_PLAYABLE_TIER < 3).is_true()
	assert_bool(BuildCatalog.STAFF_ROLES.has(GateDesks.BUS_DESK)).is_true()
	assert_int(BuildCatalog.STAFF_ROLES[GateDesks.BUS_DESK]).is_equal(StaffMember.Role.GATE)
	assert_bool(BuildCatalog.get_def(RemoteStands.STAND_ID).unfloored).is_true()


func test_bus_gate_desk_and_remote_stand_flow_and_save_v42() -> void:
	assert_int(SaveGame.SAVE_VERSION).is_equal(42)
	assert_int(FlightSim.SAVE_VERSION).is_equal(14)
	assert_int(GateDesks.SAVE_VERSION).is_equal(3)

	var wing := _ensure_west_bay_wing()
	var exit1_cell := wing + Vector2i(2, 0)
	var exit2_cell := wing + Vector2i(18, 0)
	var exit_close := wing + Vector2i(10, 0)
	assert_bool(_mode.grid.apply(BuildEdit.place_object(&"exit_door", exit1_cell, 0)).ok).is_true()
	assert_bool(_mode.grid.apply(BuildEdit.place_object(&"exit_door", exit2_cell, 0)).ok).is_true()
	assert_bool(_mode.grid.apply(BuildEdit.place_object(&"exit_door", exit_close, 0)).ok).is_true()

	# Place bus_gate_desk 1 at exit1 (16 m away from exit2, < 19 m regular gate spacing!).
	var desk1_cell := wing + Vector2i(1, 2)
	var r1 := _mode.grid.apply(BuildEdit.place_object(GateDesks.BUS_DESK, desk1_cell, 0))
	assert_bool(r1.ok).is_true()
	assert_bool(GateDesks.is_desk(_mode.grid, r1.object_id)).is_true()
	assert_bool(GateDesks.is_bus_desk(_mode.grid, r1.object_id)).is_true()

	# A second bus gate 8 m away (< 16 m bay) is refused with BUS_BAY_BLOCKED.
	var close_desk := _mode.grid.apply(
		BuildEdit.place_object(GateDesks.BUS_DESK, wing + Vector2i(9, 2), 0)
	)
	assert_bool(close_desk.ok).is_false()
	assert_int(close_desk.reason).is_equal(BuildResult.Reason.BUS_BAY_BLOCKED)

	# A second bus gate 16 m away fits cleanly (no 19 m aircraft spacing required).
	var desk2_cell := wing + Vector2i(17, 2)
	var r2 := _mode.grid.apply(BuildEdit.place_object(GateDesks.BUS_DESK, desk2_cell, 0))
	assert_bool(r2.ok).is_true()

	var bgates := _flights.bus_gate_ids()
	assert_int(bgates.size()).is_equal(2)
	assert_bool(_flights.gate_ids().has(bgates[0])).is_false()
	# Bus gates get bay markings, NO jet bridges.
	assert_bool(_airside.props.bus_bay_nodes.has(bgates[0])).is_true()
	assert_bool(_airside.props.bridges.has(bgates[0])).is_false()

	# Remote stand placed on terminal floor is refused with REMOTE_STAND_NEEDS_APRON.
	var on_floor := _mode.grid.apply(
		BuildEdit.place_object(RemoteStands.STAND_ID, wing + Vector2i(4, 2), 0)
	)
	assert_bool(on_floor.ok).is_false()
	assert_int(on_floor.reason).is_equal(BuildResult.Reason.REMOTE_STAND_NEEDS_APRON)

	# Remote stand placed on unowned plot is refused with LAND_NOT_OWNED.
	var unowned_cell := SITE.starter_offset + Vector2i(35, -90)
	assert_bool(_mode.land_tool.land.owns_cell(unowned_cell)).is_false()
	var on_unowned := _mode.grid.apply(
		BuildEdit.place_object(RemoteStands.STAND_ID, unowned_cell, 0)
	)
	assert_bool(on_unowned.ok).is_false()
	assert_int(on_unowned.reason).is_equal(BuildResult.Reason.LAND_NOT_OWNED)

	# Place remote stand R1 on owned unbuilt apron north of the starter terminal.
	var rstand_cell := SITE.starter_offset + Vector2i(-25, -45)
	_buy_plot_for(rstand_cell)
	_buy_plot_for(rstand_cell + Vector2i(-20, -20))
	_buy_plot_for(rstand_cell + Vector2i(20, -20))
	_buy_plot_for(rstand_cell + Vector2i(-20, 20))
	_buy_plot_for(rstand_cell + Vector2i(20, 20))
	var rs1 := _mode.grid.apply(BuildEdit.place_object(RemoteStands.STAND_ID, rstand_cell, 0))
	assert_bool(rs1.ok).is_true()
	assert_array(_flights.remote_stand_ids()).is_equal(["R1"])
	var grounds := _flights.remote_stand_grounds()
	assert_bool(grounds.has("R1")).is_true()
	assert_str(grounds["R1"]["max_class"]).is_not_empty()
	assert_bool(_airside.props.bridges.has("R1")).is_false()
	# Airside routes + paving include R1 automatically.
	assert_bool(_airside.routes_gate("R1")).is_true()
	assert_int(_airside.paving.pads.size()).is_greater_equal(2)

	# Another remote stand within 19 m swing is refused with REMOTE_STAND_OVERLAP.
	var too_close := _mode.grid.apply(
		BuildEdit.place_object(RemoteStands.STAND_ID, rstand_cell + Vector2i(10, 0), 0)
	)
	assert_bool(too_close.ok).is_false()
	assert_int(too_close.reason).is_equal(BuildResult.Reason.REMOTE_STAND_OVERLAP)

	# FlightContract stand vs gate split: regular gate defaults stand = gate, explicit stand kept.
	var regular := FlightContract.assigned(
		TestFlightContracts.terms("GMF810", 660), "A", _apron.gate_stands["A"]["live"]
	)
	assert_str(regular["gate"]).is_equal("A")
	assert_str(regular["stand"]).is_equal("A")
	var remote_c := FlightContract.assigned(
		TestFlightContracts.terms("GMF811", 720), bgates[0], grounds["R1"]["stand"], "R1"
	)
	assert_str(remote_c["gate"]).is_equal(bgates[0])
	assert_str(remote_c["stand"]).is_equal("R1")
	assert_str(_flights.flight_stand_id(FlightSim.DEFAULT_ID + "-d0")).is_equal("A")
	assert_str(_flights.flight_gate(FlightSim.DEFAULT_ID + "-d0")).is_equal("A")
	assert_bool(_flights.flight_stand(FlightSim.DEFAULT_ID + "-d0") is Dictionary).is_true()

	# SaveGame v42 round-trip preserves bus gates + remote stands and rejects v41.
	SaveTestKit.step(_main)
	var snap := _save.snapshot()
	assert_bool(snap.is_empty()).is_false()
	var json_copy: Dictionary = JSON.parse_string(JSON.stringify(snap, "", true, true))
	assert_int(int(json_copy["save_version"])).is_equal(42)

	var old_copy := json_copy.duplicate(true)
	old_copy["save_version"] = 41
	assert_bool(_save.load_world(old_copy)).is_false()

	assert_bool(_mode.grid.apply(BuildEdit.remove_object(rs1.object_id)).ok).is_true()
	assert_array(_flights.remote_stand_ids()).is_empty()

	assert_bool(_save.load_world(json_copy)).is_true()
	assert_array(_flights.remote_stand_ids()).is_equal(["R1"])
	assert_array(_flights.bus_gate_ids()).is_equal(bgates)

	# Regression (Finding #3): active contract/flight referencing "R1" preserves "R1" on refresh
	# and blocks removal with REMOTE_STAND_IN_USE.
	var flight_snap := _flights.to_snapshot()
	var small_terms := TestFlightContracts.terms("GMF812", 780)
	small_terms["plane_size"] = PlaneClasses.SMALL
	small_terms["booked_passengers"] = 6
	var active_c := FlightContract.assigned(small_terms, "A", grounds["R1"]["stand"], "R1")
	active_c = FlightContract.make(
		active_c.merged({"first_day": GameCalendar.day_of(_flights.tick, _flights.epoch)})
	)
	(flight_snap["contracts"] as Array).append(active_c)
	flight_snap["start_day"]["GMF812"] = active_c["first_day"]
	flight_snap["next_day"]["GMF812"] = active_c["first_day"]
	assert_bool(_flights.from_snapshot(flight_snap)).is_true()
	_gates.refresh()
	assert_array(_flights.remote_stand_ids()).is_equal(["R1"])
	var remove_r1 := _mode.grid.apply(
		BuildEdit.remove_object(_gates.remote_stands["R1"]["object_id"])
	)
	assert_bool(remove_r1.ok).is_false()
	assert_int(remove_r1.reason).is_equal(BuildResult.Reason.REMOTE_STAND_IN_USE)

	# Regression (Finding #2): removing a linked bus gate's exit door closes the wall cleanly
	# without failing step 1 (place_wall) with BUS_BAY_BLOCKED, and unlinks the bus gate.
	var first_bgate := bgates[0]
	var bg_binding := _gates.binding_of(first_bgate)
	var exit_id := int(bg_binding["exit"])
	var exit_anchor: Vector2i = _mode.grid.get_object(exit_id)["anchor"]
	var close_edits := DoorPlacement.edits_for(_mode.grid, BuildEdit.remove_object(exit_id))
	var close_results := _mode.grid.apply_batch(close_edits)
	for res in close_results:
		assert_bool(res.ok).is_true()
	assert_int(_mode.grid.object_at(exit_anchor)).is_equal(0)
	assert_int(_mode.grid.wall_kind(exit_anchor, BuildGrid.Side.NORTH)).is_equal(
		BuildGrid.WallKind.PLAIN
	)
	assert_bool(_flights.bus_gate_ids().has(first_bgate)).is_false()
