class_name TestAirportGateGateAgent
extends GdUnitTestSuite
## AirportGate requires a staffed gate desk (NO_GATE_AGENT) when a linked
## gate_desk exists, matching check-in and security parity, and reports
## STAFF_SPOT if the gate desk's staff spot is unreachable.

const CHECKIN := StaffMember.Role.CHECKIN
const SECURITY := StaffMember.Role.SECURITY
const GATE := StaffMember.Role.GATE
const SITE := preload("res://build/terminal_site.tres")

var _w: PassengerTestWorld
var _gates: GateDesks
var _apron: ApronStand
var _gate: AirportGate
var _panel: StaffPanel
var _desk := 0


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _w != null:
		_w.free_all()
	_w = null


func _make(place_gate := true) -> void:
	var grid := SiteGrid.new(SITE)
	assert_bool(StarterShell.place(grid, SITE.starter_offset)).is_true()
	assert_bool(ReferenceTerminal.fill_interior(grid, SITE.starter_offset).ok).is_true()
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 23)
	_w.auto_staff = false
	_w.sim.site = SITE
	_gates = auto_free(GateDesks.new()) as GateDesks
	_gates.bind(grid, _w.flights)
	if place_gate:
		var placed := grid.apply(ReferenceTerminal.gate_desk_edit(SITE.starter_offset))
		assert_bool(placed.ok).is_true()
		_desk = placed.object_id
	_apron = auto_free(ApronStand.new()) as ApronStand
	_apron.passengers = _w.sim
	_apron.bind(grid, SITE, _w.flights, _gates)
	_gate = auto_free(AirportGate.new()) as AirportGate
	_gate.bind(_w.flights, _w.staff)
	_panel = auto_free(StaffPanel.new()) as StaffPanel
	_panel.staff = _w.staff
	_panel.gate = _gate
	add_child(_panel)


func test_no_gate_agent_blocks_opening_until_gate_agent_is_on_duty() -> void:
	_make(false)
	StaffTestKit.staff_all(_w.staff, [CHECKIN, SECURITY])
	assert_int(_gate.blocker()).is_equal(AirportGate.Blocker.NO_GATE)

	var placed := _w.grid.apply(ReferenceTerminal.gate_desk_edit(SITE.starter_offset))
	assert_bool(placed.ok).is_true()
	_desk = placed.object_id
	assert_array(_gate.unmet()).contains_exactly([AirportGate.Blocker.NO_GATE_AGENT])
	assert_str(_panel.hint_text()).contains("Gate desk and an agent: hire a gate agent on Staff")
	assert_bool(_gate.ready_to_open()).is_false()

	_panel.hire_button(GATE).pressed.emit()
	_w.step()
	assert_str(_panel.hint_text()).contains("Gate desk and an agent: the gate agent is on the way")
	assert_bool(_gate.is_open()).is_false()

	var guard := 0
	while not _gate.is_open() and guard < 1200:
		_w.step()
		guard += 1
	assert_bool(_gate.is_open()).is_true()
	assert_int(_gate.blocker()).is_equal(AirportGate.Blocker.NONE)


func test_unreachable_gate_desk_staff_spot_blocks_opening_with_staff_spot() -> void:
	_make(true)
	StaffTestKit.staff_all(_w.staff, [CHECKIN, SECURITY])
	# Enclose a 2-cell pocket around the gate desk's staff spot (spot and
	# spot + (-1, 0)) with check_staff_reach disabled to simulate an
	# unreachable legacy spot.
	var spot := StaffSpots.spot_of(_w.grid, _desk)
	var wing := spot + Vector2i(-1, 0)
	_w.grid.check_staff_reach = false
	for edit in [
		BuildEdit.place_wall(spot, BuildGrid.Side.NORTH),
		BuildEdit.place_wall(spot, BuildGrid.Side.EAST),
		BuildEdit.place_wall(wing, BuildGrid.Side.NORTH),
		BuildEdit.place_wall(wing, BuildGrid.Side.SOUTH),
		BuildEdit.place_wall(wing, BuildGrid.Side.WEST),
	]:
		assert_bool(_w.grid.apply(edit).ok).is_true()
	_w.grid.check_staff_reach = true
	assert_bool(_w.staff.spot_unreachable(_desk)).is_true()
	assert_array(_gate.unmet()).contains_exactly([AirportGate.Blocker.STAFF_SPOT])
	assert_bool(_gate.ready_to_open()).is_false()


func test_unlinked_gate_desk_never_emits_no_gate_agent() -> void:
	_make(true)
	StaffTestKit.staff_all(_w.staff, [CHECKIN, SECURITY])
	var exit_id := _w.grid.object_at(ReferenceTerminal.EXIT_CELL + SITE.starter_offset)
	assert_bool(_w.grid.apply(BuildEdit.remove_object(exit_id)).ok).is_true()
	assert_array(_w.flights.gate_ids()).is_empty()
	assert_bool(_gate.unmet().has(AirportGate.Blocker.NO_GATE_AGENT)).is_false()
	assert_bool(_gate.unmet().has(AirportGate.Blocker.NO_GATE)).is_true()
	_w.sim.layout.by_gate = false
	assert_bool(_gate.unmet().has(AirportGate.Blocker.NO_GATE_AGENT)).is_false()
