class_name TestStaffSpotUnreachable
extends GdUnitTestSuite
## A layout saved before the reach rule can hold a desk whose staff spot is
## free but sits in a pocket staff cannot walk into from the entrance. It
## loads; the desk stays closed with "Closed: staff can't reach", StaffSim
## never sends anyone there, and the airport gate names the staff spot rather
## than the passengers' way (decision
## desk-belts-run-one-row-back-desk-then-the-agent-row-then-the, v3).
##
## The reference terminal, with belt pieces put round both desks' spots in the
## save: each spot and the cell beside it form a closed two-cell pocket.

const CHECKIN := StaffMember.Role.CHECKIN
const LIMIT_TICKS := 600

var _w: PassengerTestWorld
var _desks: Array = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var source := BuildGrid.new()
	assert_bool(ReferenceTerminal.build(source)).is_true()
	var data := source.to_snapshot()
	var next: int = data["next_object_id"]
	for cell in _ring():
		(data["objects"] as Array).append(
			{"id": next, "def": "baggage_belt", "anchor": [cell.x, cell.y], "facing": 0}
		)
		next += 1
	data["next_object_id"] = next
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(JSON.parse_string(JSON.stringify(data)))).is_true()
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_w.auto_staff = false
	# ReferenceTerminal.object_ids() knows no belt pieces, so read the layout.
	_desks = _w.sim.layout.desks.duplicate()
	assert_int(_desks.size()).is_equal(2)


## Belt cells that close each desk's spot and the cell beside it into a pocket.
func _ring() -> Array[Vector2i]:
	var ring: Array[Vector2i] = []
	for x in range(10, 17):
		ring.append(Vector2i(x, 9))
	for x in [10, 13, 16]:
		ring.append_array([Vector2i(x, 10), Vector2i(x, 11)])
	return ring


func after_test() -> void:
	if _w != null:
		_w.free_all()
	_w = null


func test_a_pocketed_spot_loads_and_its_desk_says_staff_cannot_reach_it() -> void:
	_w.step()
	for desk: int in _desks:
		print(
			(
				"desk %d spot %s: blocked %s, unreachable %s, reason '%s'"
				% [
					desk,
					_w.staff.spot_of(desk),
					_w.staff.spot_blocked(desk),
					_w.staff.spot_unreachable(desk),
					MissSignals.closed_reason(_w.sim, desk)
				]
			)
		)
		assert_bool(_w.staff.spot_blocked(desk)).is_false()
		assert_bool(_w.staff.spot_unreachable(desk)).is_true()
		assert_str(MissSignals.closed_reason(_w.sim, desk)).is_equal(MissSignals.UNREACHABLE_REASON)
	var scanner: int = _w.sim.layout.scanners[0]
	assert_bool(_w.staff.spot_unreachable(scanner)).is_false()
	assert_str(MissSignals.closed_reason(_w.sim, scanner)).is_equal(MissSignals.NO_STAFF_REASON)
	var views := PassengerViews.new()
	views.clock = _w.clock
	views.sim = _w.sim
	add_child(views)
	var markers := views.get_node("MissMarkers") as MissMarkers
	markers.sync()
	print("captions: '%s', '%s'" % [markers.closed_text(_desks[0]), markers.closed_text(scanner)])
	assert_str(markers.closed_text(_desks[0])).is_equal(MissMarkers.UNREACHABLE_CAPTION)
	assert_str(markers.closed_text(_desks[0])).is_equal("Closed: staff can't reach")
	assert_str(markers.closed_text(scanner)).is_equal(MissMarkers.CLOSED_CAPTION)
	views.free()


func test_an_agent_is_never_sent_to_a_desk_staff_cannot_reach() -> void:
	var m := _w.staff.get_member(_w.staff.hire(CHECKIN))
	var states := {}
	for i in LIMIT_TICKS:
		_w.step()
		states[m.state] = true
	print("agent states seen %s, station %d" % [states.keys(), m.station])
	assert_int(m.station).is_equal(0)
	assert_bool(states.has(StaffMember.State.TO_STATION)).is_false()
	assert_bool(states.has(StaffMember.State.ON_DUTY)).is_false()
	for desk: int in _desks:
		assert_bool(_w.staff.is_staffed(desk)).is_false()


func test_the_gate_names_the_staff_spot_and_the_hint_says_how_to_fix_it() -> void:
	var layout := _w.sim.layout
	assert_bool(RepairPlan.has_working_path(_w.grid, layout)).is_false()
	assert_bool(RepairPlan.has_working_path(_w.grid, layout, false)).is_true()
	var gate: AirportGate = auto_free(AirportGate.new())
	gate.bind(_w.flights, _w.staff)
	var panel: StaffPanel = auto_free(StaffPanel.new())
	panel.staff = _w.staff
	panel.gate = gate
	add_child(panel)
	var first := panel.hint_text().split("\n")[0]
	print("blocker %d, hint '%s'" % [gate.blocker(), panel.hint_text()])
	assert_int(gate.blocker()).is_equal(AirportGate.Blocker.STAFF_SPOT)
	assert_str(first).is_equal(StaffPanel.CLOSED_HINTS[AirportGate.Blocker.STAFF_SPOT])
	assert_str(first).contains("staff spot")
	assert_str(first).is_not_equal(StaffPanel.CLOSED_HINTS[AirportGate.Blocker.NO_PATH])


## A spot an old save left under a seat row is the same blocker for the gate.
func test_the_gate_names_the_staff_spot_when_the_spots_are_blocked() -> void:
	var source := BuildGrid.new()
	assert_bool(ReferenceTerminal.build(source)).is_true()
	var data := source.to_snapshot()
	var next: int = data["next_object_id"]
	for desk: int in ReferenceTerminal.object_ids(source)["desks"]:
		var spot := StaffSpots.spot_of(source, desk)
		(data["objects"] as Array).append(
			{"id": next, "def": "seat_row", "anchor": [spot.x, spot.y], "facing": 0}
		)
		next += 1
	data["next_object_id"] = next
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(JSON.parse_string(JSON.stringify(data)))).is_true()
	var blocked := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	blocked.auto_staff = false
	for desk: int in blocked.sim.layout.desks:
		assert_bool(blocked.staff.spot_blocked(desk)).is_true()
	var gate: AirportGate = auto_free(AirportGate.new())
	gate.bind(blocked.flights, blocked.staff)
	print("blocked spots: blocker %d" % gate.blocker())
	assert_int(gate.blocker()).is_equal(AirportGate.Blocker.STAFF_SPOT)


## A staff save with agents on duty on the desks' spots, loaded with a grid that
## has those spots pocketed (an old save): the agents load idle where they
## stood, and the desks are closed because staff cannot reach them.
func test_an_on_duty_agent_at_a_pocketed_spot_loads_released() -> void:
	var source := PassengerTestWorld.reference_world()
	source.auto_staff = false
	assert_int(StaffTestKit.staff_all(source.staff)).is_equal(4)
	var data: Dictionary = JSON.parse_string(StaffTestKit.save_text(source))
	var grid_data: Dictionary = data["grid"]
	var next: int = grid_data["next_object_id"]
	for cell in _ring():
		(grid_data["objects"] as Array).append(
			{"id": next, "def": "baggage_belt", "anchor": [cell.x, cell.y], "facing": 0}
		)
		next += 1
	grid_data["next_object_id"] = next
	var loaded := StaffTestKit.load_world(JSON.stringify(data))
	assert_object(loaded).is_not_null()
	if loaded == null:
		return
	loaded.step()
	var desks: Array[int] = loaded.sim.layout.desks
	for id in loaded.staff.member_ids():
		var m := loaded.staff.get_member(id)
		print(
			"member %d role %d state %d station %d at %s" % [id, m.role, m.state, m.station, m.at]
		)
		if m.role == CHECKIN:
			assert_int(m.state).is_equal(StaffMember.State.IDLE)
			assert_int(m.station).is_equal(0)
	for desk in desks:
		assert_bool(loaded.staff.is_staffed(desk)).is_false()
		assert_str(MissSignals.closed_reason(loaded.sim, desk)).is_equal(
			MissSignals.UNREACHABLE_REASON
		)
	var views := PassengerViews.new()
	views.clock = loaded.clock
	views.sim = loaded.sim
	add_child(views)
	var markers := views.get_node("MissMarkers") as MissMarkers
	markers.sync()
	assert_str(markers.closed_text(desks[0])).is_equal(MissMarkers.UNREACHABLE_CAPTION)
	views.free()
