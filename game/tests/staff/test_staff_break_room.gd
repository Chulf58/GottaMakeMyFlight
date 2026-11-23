class_name TestStaffBreakRoom
extends GdUnitTestSuite
## Break Room + Soft Staff Energy (Slice S3-P2b; decision b764f946).

const CHECKIN := StaffMember.Role.CHECKIN
const SECURITY := StaffMember.Role.SECURITY
const CLEANER := StaffMember.Role.CLEANER
const BREAK_RECT := Rect2i(11, 13, 5, 4)

var _w: PassengerTestWorld
var _other: PassengerTestWorld
var _port: SubViewport


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	PseudoLocale.disable()
	for w in [_w, _other]:
		if w != null:
			w.free_all()
	_w = null
	_other = null
	if _port != null:
		_port.free()
		_port = null


func _ref_world(first_tick := -1) -> PassengerTestWorld:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	var schedule := (
		FlightSim.schedule_starts(first_tick) if first_tick >= 0 else FlightSim.schedule_starts(0)
	)
	var w := PassengerTestWorld.make(grid, schedule)
	w.auto_staff = false
	return w


func _add_break_room(grid: BuildGrid, rect := BREAK_RECT, high_prestige := false) -> int:
	var edits: Array[BuildEdit] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if grid.floor_at(Vector2i(x, y)) == BuildGrid.FLOOR_NONE:
				edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	edits.append(BuildEdit.place_room(rect, &"break_room"))
	if high_prestige:
		# Non-overlapping layout inside 8x4 reaching Level 5 (110+ pts) with 6 walkable cells.
		edits.append(BuildEdit.place_object(&"bench_1a", rect.position + Vector2i(0, 0), 0))
		edits.append(BuildEdit.place_object(&"statue_indoor", rect.position + Vector2i(0, 3), 0))
		edits.append(BuildEdit.place_object(&"metal_pole_chain", rect.position + Vector2i(1, 0), 0))
		edits.append(BuildEdit.place_object(&"metal_pole", rect.position + Vector2i(1, 3), 0))
		edits.append(BuildEdit.place_object(&"fountain_indoor", rect.position + Vector2i(2, 0), 0))
		edits.append(BuildEdit.place_object(&"tree_indoor", rect.position + Vector2i(2, 2), 0))
		edits.append(BuildEdit.place_object(&"bush", rect.position + Vector2i(4, 0), 0))
		edits.append(BuildEdit.place_object(&"plant_pot_2a", rect.position + Vector2i(4, 2), 0))
		edits.append(BuildEdit.place_object(&"plant_pot_1a", rect.position + Vector2i(6, 0), 0))
		edits.append(BuildEdit.place_object(&"fountain_indoor", rect.position + Vector2i(6, 2), 0))
		edits.append(BuildEdit.place_object(&"statue_indoor", rect.position + Vector2i(7, 0), 0))
	else:
		edits.append(BuildEdit.place_object(&"bench_1a", rect.position, 0))
	var room_id := 0
	for res: BuildResult in grid.apply_batch(edits):
		assert_bool(res.ok).override_failure_message(res.reason_text()).is_true()
		if res.room_id != 0:
			room_id = res.room_id
	return room_id


func test_energy_drains_on_duty_and_resets_overnight_off_shift() -> void:
	_w = _ref_world(20_000)
	assert_bool(_w.flights.open_airport()).is_true()
	var id := _w.staff.hire(CHECKIN)
	var m := _w.staff.get_member(id)
	assert_int(m.energy).is_equal(StaffMember.ENERGY_MAX)
	assert_float(m.work_speed_factor()).is_equal(1.0)
	# Keep a passenger in flight/queued so shift doesn't go off-shift during drain test.
	_w.sim.spawn_now(PassengerTestWorld.FLIGHT)
	while m.state != StaffMember.State.ON_DUTY and _w.clock.tick < 600:
		_w.step()
	assert_int(m.state).is_equal(StaffMember.State.ON_DUTY)
	var before_energy := m.energy
	for i in StaffMember.DRAIN_INTERVAL_TICKS:
		_w.step()
	assert_int(m.energy).is_equal(before_energy - 1)
	# Clear active passengers so overnight quiet shift triggers and resets energy to 100.
	m.energy = 20
	for pid in _w.sim.passenger_ids():
		_w.sim.get_passenger(pid).stage = Passenger.Stage.MADE
	var guard := 0
	while m.state != StaffMember.State.OFF_SHIFT and guard < 1500:
		_w.step()
		guard += 1
	assert_int(m.state).is_equal(StaffMember.State.OFF_SHIFT)
	assert_int(m.energy).is_equal(StaffMember.ENERGY_MAX)


func test_tired_staff_work_slower_and_keep_working_without_break_room() -> void:
	_w = _ref_world()
	StaffTestKit.staff_all(_w.staff, [CHECKIN, SECURITY])
	while _w.staff.on_duty_count(CHECKIN) < 2 and _w.clock.tick < 600:
		_w.step()
	var agent := _w.staff.get_member(1)
	agent.energy = StaffMember.TIRED_THRESHOLD
	assert_bool(agent.is_tired()).is_true()
	assert_float(agent.work_speed_factor()).is_equal_approx(0.80, 0.001)
	# Also make second agent tired so whichever desk is picked is 0.80x.
	_w.staff.get_member(2).energy = StaffMember.TIRED_THRESHOLD
	var pid := _w.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _w.passenger(pid)
	while p.stage != Passenger.Stage.CHECKIN and _w.clock.tick < 1200:
		_w.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CHECKIN)
	assert_int(p.service_end - _w.clock.tick).is_equal(75)
	# Without a Break Room, tired agents stay on duty and finish check-in.
	while p.stage == Passenger.Stage.CHECKIN and _w.clock.tick < 1400:
		_w.step()
	assert_int(p.stage).is_not_equal(Passenger.Stage.CHECKIN)
	assert_int(_w.staff.on_break_count(CHECKIN)).is_equal(0)


func test_tired_staff_cycle_to_break_room_in_lulls_and_high_prestige_recovers_faster() -> void:
	# L1 bare Break Room recovery.
	_w = _ref_world()
	var l1_room := _add_break_room(_w.grid, BREAK_RECT, false)
	assert_int(RoomPrestige.evaluate_room(_w.grid, l1_room)["level"]).is_equal(1)
	var id1 := _w.staff.hire(CHECKIN)
	var m1 := _w.staff.get_member(id1)
	while m1.state != StaffMember.State.ON_DUTY and _w.clock.tick < 600:
		_w.step()
	m1.energy = StaffMember.TIRED_THRESHOLD
	var guard := 0
	while m1.state != StaffMember.State.ON_BREAK and guard < 600:
		_w.step()
		guard += 1
	assert_int(m1.state).is_equal(StaffMember.State.ON_BREAK)
	assert_int(m1.break_room).is_equal(l1_room)
	# Step until rested to 95.
	var l1_ticks := 0
	while m1.is_on_break() and l1_ticks < 2000:
		_w.step()
		l1_ticks += 1
	assert_bool(m1.is_on_break()).is_false()
	assert_int(m1.energy).is_greater_equal(StaffMember.BREAK_DONE_THRESHOLD)

	# L5 prestigious Break Room recovery: strictly fewer ticks!
	_other = _ref_world()
	var l5_room := _add_break_room(_other.grid, Rect2i(10, 13, 8, 4), true)
	assert_int(RoomPrestige.evaluate_room(_other.grid, l5_room)["level"]).is_equal(5)
	var id2 := _other.staff.hire(CHECKIN)
	var m2 := _other.staff.get_member(id2)
	while m2.state != StaffMember.State.ON_DUTY and _other.clock.tick < 600:
		_other.step()
	m2.energy = StaffMember.TIRED_THRESHOLD
	guard = 0
	while m2.state != StaffMember.State.ON_BREAK and guard < 600:
		_other.step()
		guard += 1
	assert_int(m2.state).is_equal(StaffMember.State.ON_BREAK)
	var l5_ticks := 0
	while m2.is_on_break() and l5_ticks < 2000:
		_other.step()
		l5_ticks += 1
	assert_bool(m2.is_on_break()).is_false()
	print("Break recovery ticks (25->95): L1=%d L5=%d" % [l1_ticks, l5_ticks])
	assert_int(l5_ticks).is_less(l1_ticks)


func test_staff_never_abandon_busy_queue_and_return_immediately_on_arrival() -> void:
	_w = _ref_world()
	_add_break_room(_w.grid, BREAK_RECT, false)
	var id := _w.staff.hire(CHECKIN)
	var m := _w.staff.get_member(id)
	while m.state != StaffMember.State.ON_DUTY and _w.clock.tick < 600:
		_w.step()
	# Spawn passenger heading to check-in: agent MUST NOT abandon queue even when tired!
	var p := _w.passenger(_w.sim.spawn_now(PassengerTestWorld.FLIGHT))
	m.energy = StaffMember.TIRED_THRESHOLD
	var busy_ticks := 0
	var active_stages := [
		Passenger.Stage.SPAWNED,
		Passenger.Stage.TO_CHECKIN,
		Passenger.Stage.CHECKIN_QUEUE,
		Passenger.Stage.CHECKIN,
	]
	while active_stages.has(p.stage) and busy_ticks < 200:
		_w.step()
		assert_bool(m.is_on_break()).is_false()
		busy_ticks += 1
	assert_int(p.stage).is_equal(Passenger.Stage.TO_SECURITY)
	# Once check-in is done and no one else seeks check-in, agent goes on break.
	p.stage = Passenger.Stage.MADE
	var guard := 0
	while not m.is_on_break() and guard < 600:
		_w.step()
		guard += 1
	assert_bool(m.is_on_break()).is_true()
	# New passenger arrives needing check-in while no other desk is open -> immediate return!
	_w.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_w.step()
	assert_bool(m.is_on_break()).is_false()
	assert_int(m.station).is_greater(0)
	(
		assert_bool(m.state == StaffMember.State.TO_STATION or m.state == StaffMember.State.ON_DUTY)
		. is_true()
	)


func test_staff_panel_and_room_panel_display_energy_and_prestige_recovery() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	var mode := BuildMode.new()
	mode.grid_size = Vector2i(20, 20)
	_port.add_child(mode)
	mode.set_process(false)
	var menu := BuildMenu.new()
	menu.build_mode = mode
	_port.add_child(menu)

	var edits: Array[BuildEdit] = []
	for y in range(2, 16):
		for x in range(2, 16):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	mode.grid.apply_batch(edits)
	var room_id := _add_break_room(mode.grid, Rect2i(3, 3, 9, 5), true)
	EnclosureKit.close_floor(mode.grid)
	var eval := RoomPrestige.evaluate_room(mode.grid, room_id)
	assert_int(eval["level"]).is_equal(5)
	mode.set_tool(BuildMode.Tool.NONE)
	mode.update_room_focus(mode.grid.cell_to_world(Vector2i(4, 4)))
	var room_panel := menu.room_panel()
	assert_bool(room_panel.visible).is_true()
	var room_texts: Array[String] = []
	for lbl in room_panel.find_children("*", "Label", true, false):
		if (lbl as Label).is_visible_in_tree():
			room_texts.append((lbl as Label).text)
	var expected_prestige := (
		"Prestige: Lv. 5 / 5 (%d pts · +%d%% recovery)"
		% [eval["score"], eval["break_bonus_percent"]]
	)
	assert_array(room_texts).contains(["Break Room", "Benches 1", expected_prestige])

	_w = _ref_world()
	_add_break_room(_w.grid, BREAK_RECT, false)
	var panel := StaffPanel.new()
	panel.staff = _w.staff
	_port.add_child(panel)
	var id := _w.staff.hire(CHECKIN)
	var m := _w.staff.get_member(id)
	assert_str(panel.member_energy_text(id)).is_equal("Rested 100%")
	m.energy = 20
	_w.staff.member_energy_changed.emit(id, 20)
	assert_str(panel.member_energy_text(id)).is_equal("Tired 20%")
	while not m.is_on_break() and _w.clock.tick < 600:
		_w.step()
	assert_str(panel.member_energy_text(id)).starts_with("On break ")
	assert_str(panel.counts_text(CHECKIN)).contains("on break")

	PseudoLocale.enable(0.4)
	panel.notification(Node.NOTIFICATION_TRANSLATION_CHANGED)
	assert_str(panel.member_energy_text(id)).starts_with("[")
	PseudoLocale.disable()


func test_staff_snapshot_and_save_game_persist_energy_and_reject_corrupt() -> void:
	_w = _ref_world()
	_add_break_room(_w.grid, BREAK_RECT, false)
	var id := _w.staff.hire(CHECKIN)
	var m := _w.staff.get_member(id)
	while m.state != StaffMember.State.ON_DUTY and _w.clock.tick < 600:
		_w.step()
	m.energy = 20
	while m.state != StaffMember.State.TO_BREAK and _w.clock.tick < 800:
		_w.step()
	assert_int(m.state).is_equal(StaffMember.State.TO_BREAK)
	_other = StaffTestKit.load_world(StaffTestKit.save_text(_w))
	var loaded_m := _other.staff.get_member(id)
	assert_int(loaded_m.state).is_equal(StaffMember.State.TO_BREAK)
	assert_int(loaded_m.energy).is_equal(20)
	assert_int(loaded_m.break_room).is_equal(m.break_room)
	assert_vector(loaded_m.break_spot).is_equal(m.break_spot)

	for i in 120:
		_w.step()
		_other.step()
	assert_str(StaffTestKit.signature(_other.staff)).is_equal(StaffTestKit.signature(_w.staff))
	assert_int(loaded_m.energy).is_equal(m.energy)

	var good: Dictionary = JSON.parse_string(JSON.stringify(_w.staff.to_snapshot()))
	var bad_low := good.duplicate(true)
	bad_low["members"][0]["energy"] = -1
	var bad_high := good.duplicate(true)
	bad_high["members"][0]["energy"] = 101
	var bad_room := good.duplicate(true)
	bad_room["members"][0]["break_room"] = 9999
	for bad in [bad_low, bad_high, bad_room]:
		assert_bool(_w.staff.from_snapshot(bad)).is_false()
	assert_int(StaffSim.SAVE_VERSION).is_equal(9)
	assert_int(SaveGame.SAVE_VERSION).is_equal(37)


func test_gate_agent_interrupts_break_for_own_gate_even_when_other_gate_is_open_idle() -> void:
	_w = _ref_world(20_000)
	_add_break_room(_w.grid, BREAK_RECT, false)
	var desk_a_res := _w.grid.apply(ReferenceTerminal.gate_desk_edit())
	var desk_b_res := _w.grid.apply(BuildEdit.place_object(GateDesks.DESK, Vector2i(17, 5), 0))
	assert_bool(desk_a_res.ok).is_true()
	assert_bool(desk_b_res.ok).is_true()
	var desk_a := desk_a_res.object_id
	var desk_b := desk_b_res.object_id
	var exit_id := 0
	for oid in _w.grid.object_ids():
		if _w.grid.get_object(oid)["def"] == &"exit_door":
			exit_id = oid
			break
	assert_int(exit_id).is_greater(0)
	_w.sim.set_gate_stands({exit_id: "A"}, {exit_id: "A"}, {"A": desk_a, "B": desk_b})
	StaffTestKit.staff_all(_w.staff, [CHECKIN, SECURITY])
	var ga_id := _w.staff.hire(StaffMember.Role.GATE)
	var gb_id := _w.staff.hire(StaffMember.Role.GATE)
	while _w.staff.on_duty_count(StaffMember.Role.GATE) < 2 and _w.clock.tick < 1200:
		_w.step()
	assert_int(_w.staff.on_duty_count(StaffMember.Role.GATE)).is_equal(2)
	var m_a := _w.staff.get_member(_w.staff.staff_at(desk_a))
	var m_b := _w.staff.get_member(_w.staff.staff_at(desk_b))
	assert_object(m_a).is_not_null()
	assert_object(m_b).is_not_null()
	assert_int(m_a.id).is_not_equal(m_b.id)
	assert_bool(ga_id == m_a.id or gb_id == m_a.id).is_true()

	# Let Gate A agent enter break during a lull while Gate B stays open & idle.
	m_a.energy = StaffMember.TIRED_THRESHOLD
	var guard := 0
	while not m_a.is_on_break() and guard < 800:
		_w.step()
		guard += 1
	assert_bool(m_a.is_on_break()).is_true()
	assert_int(m_b.state).is_equal(StaffMember.State.ON_DUTY)

	# Add a flight boarding at Gate A: Gate A agent MUST interrupt immediately
	# even though Gate B is open and idle.
	var t := _w.clock.tick + 1
	var starts: Array[int] = [
		t, t + 1, t + 2, t + 3, t + 4, t + 10, t + 2000, t + 2060, t + 2180, t + 2480, t + 2680
	]
	_w.flights.gate_source = func() -> Array[String]: return ["A", "B"] as Array[String]
	assert_bool(_w.flights.add_flight("GA1", starts, "A")).is_true()
	guard = 0
	while guard < 100:
		_w.step()
		guard += 1
		if not m_a.is_on_break():
			break
	assert_bool(m_a.is_on_break()).is_false()
	assert_int(m_b.state).is_equal(StaffMember.State.ON_DUTY)


func test_two_checkin_desks_avoid_break_ping_pong_in_lull_and_busy_sibling() -> void:
	_w = _ref_world()
	_add_break_room(_w.grid, BREAK_RECT, false)
	StaffTestKit.staff_all(_w.staff, [CHECKIN, SECURITY])
	while _w.staff.on_duty_count(CHECKIN) < 2 and _w.clock.tick < 600:
		_w.step()
	var m1 := _w.staff.get_member(1)
	var m2 := _w.staff.get_member(2)
	# Case 1: busy sibling + SPAWNED passenger -> idle desk stays ON_DUTY without ping-pong.
	var p_busy := _w.passenger(_w.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while p_busy.stage != Passenger.Stage.CHECKIN and _w.clock.tick < 900:
		_w.step()
	assert_int(p_busy.stage).is_equal(Passenger.Stage.CHECKIN)
	var busy_station := p_busy.station
	var busy_member := _w.staff.get_member(_w.staff.staff_at(busy_station))
	var idle_member := m1 if busy_member.id == m2.id else m2
	var p_waiting := _w.passenger(_w.sim.spawn_now(PassengerTestWorld.FLIGHT))
	idle_member.energy = StaffMember.TIRED_THRESHOLD
	for _i in 3:
		_w.step()
		assert_bool(idle_member.is_on_break()).is_false()
	# Case 2: let both passengers clear check-in, then verify smooth break without cancelling.
	var guard := 0
	while (
		(
			p_busy.stage < Passenger.Stage.TO_SECURITY
			or p_waiting.stage < Passenger.Stage.TO_SECURITY
		)
		and guard < 400
	):
		_w.step()
		guard += 1
	idle_member.energy = StaffMember.TIRED_THRESHOLD
	var saw_to_break := false
	var saw_on_break := false
	var left_break_early := false
	for _i in 600:
		_w.step()
		if idle_member.state == StaffMember.State.TO_BREAK:
			saw_to_break = true
		elif idle_member.state == StaffMember.State.ON_BREAK:
			saw_on_break = true
			break
		elif saw_to_break:
			left_break_early = true
			break
	assert_bool(saw_to_break).is_true()
	assert_bool(left_break_early).is_false()
	assert_bool(saw_on_break).is_true()


func test_on_break_snapshot_round_trip_and_break_room_demolition_mid_break() -> void:
	_w = _ref_world()
	var room_id := _add_break_room(_w.grid, BREAK_RECT, false)
	var id := _w.staff.hire(CHECKIN)
	var m := _w.staff.get_member(id)
	while m.state != StaffMember.State.ON_DUTY and _w.clock.tick < 600:
		_w.step()
	m.energy = StaffMember.TIRED_THRESHOLD
	var guard := 0
	while m.state != StaffMember.State.ON_BREAK and guard < 600:
		_w.step()
		guard += 1
	assert_int(m.state).is_equal(StaffMember.State.ON_BREAK)
	assert_int(m.break_room).is_equal(room_id)

	_other = StaffTestKit.load_world(StaffTestKit.save_text(_w))
	var loaded_m := _other.staff.get_member(id)
	assert_int(loaded_m.state).is_equal(StaffMember.State.ON_BREAK)
	assert_int(loaded_m.break_room).is_equal(room_id)
	assert_vector(loaded_m.break_spot).is_equal(m.break_spot)
	assert_int(loaded_m.energy).is_equal(m.energy)
	for _i in 40:
		_w.step()
		_other.step()
	assert_str(StaffTestKit.signature(_other.staff)).is_equal(StaffTestKit.signature(_w.staff))

	# Demolishing the break room mid-break exits break cleanly without crashing.
	assert_bool(_w.grid.apply(BuildEdit.remove_room(room_id)).ok).is_true()
	_w.step()
	assert_bool(m.is_on_break()).is_false()
	assert_int(m.break_room).is_equal(0)
	assert_vector(m.break_spot).is_equal(StaffMember.NO_CELL)
	guard = 0
	while m.state != StaffMember.State.ON_DUTY and guard < 600:
		_w.step()
		guard += 1
	assert_int(m.state).is_equal(StaffMember.State.ON_DUTY)
