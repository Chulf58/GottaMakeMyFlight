class_name TestGateStaff
extends GdUnitTestSuite
## Gate agent (StaffMember.Role.GATE) parity with check-in, security and shop
## staff: hiring/firing via StaffPanel, walking through security to airside
## gate_desk posts, distinct uniform tint, closed sign & AlertSources warning
## while unstaffed, boarding blocked until staffed, and save/load round-trip.

const GATE := StaffMember.Role.GATE
const CHECKIN := StaffMember.Role.CHECKIN
const SECURITY := StaffMember.Role.SECURITY
const SITE := preload("res://build/terminal_site.tres")
const FLIGHT := "G101"

var _a: PassengerTestWorld
var _b: PassengerTestWorld
var _gates: GateDesks
var _apron: ApronStand
var _desk := 0


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in [_a, _b]:
		if world != null:
			world.free_all()
	_a = null
	_b = null
	_gates = null
	_apron = null


func _gate_world(starts: Array[int] = []) -> PassengerTestWorld:
	var grid := SiteGrid.new(SITE)
	assert_bool(StarterShell.place(grid, SITE.starter_offset)).is_true()
	assert_bool(ReferenceTerminal.fill_interior(grid, SITE.starter_offset).ok).is_true()
	var timing := starts if not starts.is_empty() else FlightSim.schedule_starts(0)
	var world := PassengerTestWorld.make(grid, timing, 17)
	world.sim.site = SITE
	world.auto_staff = false
	_gates = auto_free(GateDesks.new()) as GateDesks
	_gates.bind(grid, world.flights)
	var placed := grid.apply(ReferenceTerminal.gate_desk_edit(SITE.starter_offset))
	assert_bool(placed.ok).is_true()
	_desk = placed.object_id
	_apron = auto_free(ApronStand.new()) as ApronStand
	_apron.passengers = world.sim
	_apron.bind(grid, SITE, world.flights, _gates)
	return world


func _step_until_on_duty(world: PassengerTestWorld, role: StaffMember.Role, limit := 1200) -> bool:
	for _i in limit:
		world.step()
		if world.staff.on_duty_count(role) > 0:
			return true
	return false


func test_hiring_and_firing_gate_agent_through_panel_and_pool() -> void:
	_a = _gate_world()
	var panel := auto_free(StaffPanel.new()) as StaffPanel
	panel.staff = _a.staff
	add_child(panel)
	assert_array(StaffPanel.ROLES).contains([GATE])
	assert_int(PriceTable.wage_of(GATE)).is_equal(60)
	assert_str(panel.hire_button(GATE).name).is_equal("HireGate")
	assert_str(panel.fire_button(GATE).name).is_equal("FireGate")
	assert_bool(panel.fire_button(GATE).disabled).is_true()
	assert_str(panel.hint_text()).contains("Hire a gate agent")

	panel.hire_button(GATE).pressed.emit()
	assert_int(_a.staff.count(GATE)).is_equal(1)
	assert_str(panel.counts_text(GATE)).is_equal("1 hired, 0 on duty")
	assert_bool(panel.fire_button(GATE).disabled).is_false()
	assert_str(panel.hint_text()).not_contains("Hire a gate agent")

	assert_bool(_step_until_on_duty(_a, GATE)).is_true()
	assert_str(panel.counts_text(GATE)).is_equal("1 hired, 1 on duty")

	panel.fire_button(GATE).pressed.emit()
	assert_int(_a.staff.count(GATE)).is_equal(0)
	assert_str(panel.counts_text(GATE)).is_equal("0 hired, 0 on duty")
	assert_bool(panel.fire_button(GATE).disabled).is_true()


func test_gate_agent_walks_through_security_to_gate_desk_with_distinct_uniform() -> void:
	_a = _gate_world()
	var views := auto_free(StaffCharacters.new()) as StaffCharacters
	views.clock = _a.clock
	views.staff = _a.staff
	add_child(views)

	var ci_id := _a.staff.hire(CHECKIN)
	var gate_id := _a.staff.hire(GATE)
	_a.step()
	var m := _a.staff.get_member(gate_id)
	var divider_y := ReferenceTerminal.DIVIDER_Y + SITE.starter_offset.y
	var crossed_scanner := false
	for cell in m.path:
		if cell.y <= divider_y and _a.grid.object_at(cell) != 0:
			var def_id := StringName(_a.grid.get_object(_a.grid.object_at(cell))["def"])
			if def_id == &"security_scanner":
				crossed_scanner = true
	assert_bool(crossed_scanner).is_true()

	assert_bool(_step_until_on_duty(_a, GATE)).is_true()
	assert_bool(_step_until_on_duty(_a, CHECKIN)).is_true()
	assert_int(m.station).is_equal(_desk)
	assert_vector(m.at).is_equal(StaffSpots.spot_of(_a.grid, _desk))
	assert_bool(_a.staff.is_open(_desk)).is_true()

	views.sync(true)
	var ci_node := views.node_for(ci_id)
	var gate_node := views.node_for(gate_id)
	var ci_mesh := PassengerLooks.body_mesh(ci_node).mesh
	var gate_mesh := PassengerLooks.body_mesh(gate_node).mesh
	assert_object(gate_mesh).is_not_null()
	assert_object(gate_mesh).is_not_same(ci_mesh)
	assert_int(gate_mesh.get_surface_count()).is_equal(2)


func test_unstaffed_gate_desk_shows_closed_sign_and_blocks_boarding_until_staffed() -> void:
	var starts := PassengerTestWorld.starts_with(200, 2400)
	_a = _gate_world(starts)
	assert_bool(_a.flights.add_flight(FLIGHT, starts, "A")).is_true()
	StaffTestKit.staff_all(_a.staff, [CHECKIN, SECURITY])
	var markers := auto_free(MissMarkers.new()) as MissMarkers
	markers.sim = _a.sim
	add_child(markers)
	markers.sync()

	assert_array(MissSignals.closed_stations(_a.sim)).contains([_desk])
	assert_str(MissSignals.closed_reason(_a.sim, _desk)).is_equal(MissSignals.NO_STAFF_REASON)
	assert_object(markers.closed_sign_for(_desk)).is_not_null()
	assert_int(MissMarkers.glyph_of(markers.closed_sign_for(_desk))).is_equal(
		MarkerIcons.Glyph.CLOSED
	)
	var alerts := AlertSources.closed_stations(_a.sim)
	assert_int(alerts.size()).is_equal(1)
	assert_that(alerts[0]["key"]).is_equal(AlertSources.NO_STAFF)

	# Send a cleared passenger airside to the gate before boarding opens.
	var pid := _a.sim.spawn_now(FLIGHT)
	var p := _a.passenger(pid)
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.at = ReferenceTerminal.GATE_DESK_CELL + Vector2i(-1, 0) + SITE.starter_offset
	p.apron = []
	p.apron_mm = 0
	p.clear_path()

	_a.run_to(280)
	assert_int(p.stage).is_not_equal(Passenger.Stage.TO_EXIT)
	assert_int(p.stage).is_not_equal(Passenger.Stage.MADE)
	assert_int(_a.sim.made_count()).is_equal(0)
	assert_str(_a.sim.bubble_text(p)).is_equal("Gate is closed")
	assert_int(JourneyForecast.arrival_tick(_a.sim, p)).is_equal(JourneyForecast.NEVER)

	# Hiring a Gate Agent clears the closed sign and lets the passenger board.
	_a.staff.hire(GATE)
	assert_bool(_step_until_on_duty(_a, GATE)).is_true()
	markers.sync()
	assert_array(MissSignals.closed_stations(_a.sim)).not_contains([_desk])
	assert_object(markers.closed_sign_for(_desk)).is_null()
	assert_array(AlertSources.closed_stations(_a.sim)).is_empty()

	_a.run_to(2200)
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)
	assert_int(_a.sim.made_count()).is_equal(1)


func test_gate_agent_save_load_round_trip_and_invalid_role_refusal() -> void:
	_a = _gate_world()
	StaffTestKit.staff_all(_a.staff, [CHECKIN, SECURITY])
	var gate_id := _a.staff.hire(GATE)
	var m := _a.staff.get_member(gate_id)
	for _i in 200:
		_a.step()
		if m.state == StaffMember.State.TO_STATION and m.seg_mm > 0:
			break
	assert_int(m.state).is_equal(StaffMember.State.TO_STATION)

	_b = StaffTestKit.load_world(StaffTestKit.save_text(_a))
	assert_object(_b).is_not_null()
	assert_str(StaffTestKit.signature(_b.staff)).is_equal(StaffTestKit.signature(_a.staff))

	var differing := 0
	for _i in 600:
		_a.step()
		_b.step()
		if StaffTestKit.signature(_a.staff) != StaffTestKit.signature(_b.staff):
			differing += 1
	assert_int(differing).is_equal(0)
	assert_int(_b.staff.on_duty_count(GATE)).is_equal(1)

	# A Gate Agent assigned to a check-in desk must be refused by StaffSnapshot.
	var bad: Dictionary = JSON.parse_string(JSON.stringify(_b.staff.to_snapshot()))
	for record in bad["members"]:
		if int(record["role"]) == GATE:
			record["state"] = StaffMember.State.ON_DUTY
			record["station"] = _a.sim.layout.desks[0]
			record["at"] = [
				StaffSpots.spot_of(_a.grid, _a.sim.layout.desks[0]).x,
				StaffSpots.spot_of(_a.grid, _a.sim.layout.desks[0]).y,
			]
			record["path"] = [record["at"]]
			record["path_index"] = 0
			record["seg_mm"] = 0
	var loaded := StaffSnapshot.load(bad, _b.sim)
	assert_bool(loaded.has("error")).is_true()
	assert_str(loaded["error"]).contains("not one of its role")


func test_firing_gate_agent_mid_to_exit_returns_never_forecast_immediately() -> void:
	var starts := PassengerTestWorld.starts_with(200, 2400)
	_a = _gate_world(starts)
	assert_bool(_a.flights.add_flight(FLIGHT, starts, "A")).is_true()
	StaffTestKit.staff_all(_a.staff, [CHECKIN, SECURITY, GATE])
	var pid := _a.sim.spawn_now(FLIGHT)
	var p := _a.passenger(pid)
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.at = ReferenceTerminal.GATE_DESK_CELL + Vector2i(-1, 0) + SITE.starter_offset
	p.apron = []
	p.apron_mm = 0
	p.clear_path()
	for _i in 600:
		_a.step()
		if p.stage == Passenger.Stage.TO_EXIT and p.exit_object != 0:
			break
	assert_int(p.stage).is_equal(Passenger.Stage.TO_EXIT)
	assert_int(p.exit_object).is_not_equal(0)
	assert_int(JourneyForecast.arrival_tick(_a.sim, p)).is_less(JourneyForecast.NEVER)
	assert_bool(_a.staff.fire(GATE)).is_true()
	assert_int(p.stage).is_equal(Passenger.Stage.TO_EXIT)
	assert_int(p.exit_object).is_not_equal(0)
	assert_int(JourneyForecast.arrival_tick(_a.sim, p)).is_equal(JourneyForecast.NEVER)
