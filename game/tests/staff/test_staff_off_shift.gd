class_name TestStaffOffShift
extends GdUnitTestSuite
## Overnight off-shift routine (ruling quiet-night-faster-stop-at-first-arrival-
## and-staff-off-shift-overnight): non-ramp staff walk out through the
## terminal entrance when the airport is open, quiet and >2h before the next
## morning activity, rest in OFF_SHIFT, and return 30 game min before the
## first arrival.

const CHECKIN := StaffMember.Role.CHECKIN
const SECURITY := StaffMember.Role.SECURITY
const CLEANER := StaffMember.Role.CLEANER
const RAMP := StaffMember.Role.RAMP
const FIRST := 20_000
const LIMIT_TICKS := 1500

var _w: PassengerTestWorld
var _b: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in [_w, _b]:
		if world != null:
			world.free_all()
	_w = null
	_b = null


func _make_open(first_tick := FIRST) -> PassengerTestWorld:
	var on_grid := BuildGrid.new()
	ReferenceTerminal.build(on_grid)
	var w := PassengerTestWorld.make(on_grid, FlightSim.schedule_starts(first_tick))
	w.auto_staff = false
	assert_bool(w.flights.open_airport()).is_true()
	return w


func test_staff_walk_out_to_off_shift_and_panel_shows_off_shift() -> void:
	_w = _make_open()
	var panel := auto_free(StaffPanel.new()) as StaffPanel
	panel.staff = _w.staff
	add_child(panel)
	StaffTestKit.staff_all(_w.staff, [CHECKIN, SECURITY])
	var cleaner_id := _w.staff.hire(CLEANER)
	_w.staff.hire(RAMP)
	_w.step()
	assert_bool(_w.staff.is_off_shift()).is_true()
	for id in _w.staff.member_ids():
		var m := _w.staff.get_member(id)
		if m.role == RAMP:
			assert_int(m.state).is_equal(StaffMember.State.IDLE)
		elif id == cleaner_id:
			assert_int(m.state).is_equal(StaffMember.State.OFF_SHIFT)
		else:
			assert_int(m.state).is_equal(StaffMember.State.LEAVING_SHIFT)
	assert_str(panel.counts_text(CHECKIN)).contains("off shift")
	assert_str(panel.counts_text(RAMP)).is_equal("1 hired, 0 on duty")
	var steps := 0
	while _w.staff.off_shift_count(CHECKIN) > 0 and steps < LIMIT_TICKS:
		var all_off := true
		for id in _w.staff.member_ids():
			var m := _w.staff.get_member(id)
			if m.role != RAMP and m.state != StaffMember.State.OFF_SHIFT:
				all_off = false
				break
		if all_off:
			break
		_w.step()
		steps += 1
	assert_int(_w.staff.off_shift_count(CHECKIN)).is_equal(2)
	assert_int(_w.staff.off_shift_count(SECURITY)).is_equal(2)
	assert_int(_w.staff.off_shift_count(CLEANER)).is_equal(1)
	assert_int(_w.staff.count(CHECKIN)).is_equal(2)
	assert_int(_w.staff.on_duty_count(CHECKIN)).is_equal(0)
	for id in _w.staff.member_ids():
		var m := _w.staff.get_member(id)
		if m.role != RAMP:
			assert_int(m.state).is_equal(StaffMember.State.OFF_SHIFT)
			assert_bool(m.in_pool()).is_true()


func test_cleaner_finishes_reachable_mess_before_leaving_shift() -> void:
	_w = _make_open()
	var mess_cell := ReferenceTerminal.ENTRANCE_CELL + Vector2i(0, -1)
	var mess_id := _w.sim.messes.add(MessSim.Kind.LITTER, mess_cell)
	assert_int(mess_id).is_greater(0)
	var cleaner := _w.staff.get_member(_w.staff.hire(CLEANER))
	StaffTestKit.staff_all(_w.staff, [CHECKIN])
	_w.step()
	assert_int(cleaner.job).is_equal(mess_id)
	assert_int(cleaner.state).is_equal(StaffMember.State.TO_STATION)
	assert_int(_w.staff.off_shift_count(CHECKIN)).is_equal(2)
	var guard := 0
	while _w.sim.messes.mess_count() > 0 and guard < LIMIT_TICKS:
		_w.step()
		guard += 1
	assert_int(_w.sim.messes.mess_count()).is_equal(0)
	assert_int(cleaner.job).is_equal(0)
	assert_int(cleaner.state).is_equal(StaffMember.State.LEAVING_SHIFT)
	guard = 0
	while cleaner.state != StaffMember.State.OFF_SHIFT and guard < LIMIT_TICKS:
		_w.step()
		guard += 1
	assert_int(cleaner.state).is_equal(StaffMember.State.OFF_SHIFT)
	assert_bool(cleaner.in_pool()).is_true()


func test_staff_return_30_min_before_arrival_and_reach_desks_early() -> void:
	_w = _make_open()
	StaffTestKit.staff_all(_w.staff, [CHECKIN, SECURITY])
	while _w.staff.on_duty_count(CHECKIN) > 0 or _w.staff.on_duty_count(SECURITY) > 0:
		_w.step()
		assert_int(_w.clock.tick).is_less(LIMIT_TICKS)
	var approach := FlightSim.schedule_starts(FIRST)[FlightSim.State.APPROACH]
	var return_tick := approach - StaffSim.RETURN_LEAD_TICKS
	_w.run_to(return_tick - 1)
	assert_bool(_w.staff.is_off_shift()).is_true()
	_w.step()
	assert_bool(_w.staff.is_off_shift()).is_false()
	assert_int(_w.staff.off_shift_count(CHECKIN)).is_equal(0)
	_w.run_to(approach - QuietNight.LEAD_TICKS)
	assert_int(_w.staff.on_duty_count(CHECKIN)).is_equal(2)
	assert_int(_w.staff.on_duty_count(SECURITY)).is_equal(2)


func test_off_shift_recalls_immediately_if_passenger_spawns() -> void:
	_w = _make_open()
	StaffTestKit.staff_all(_w.staff, [CHECKIN])
	var first := _w.staff.get_member(_w.staff.member_ids()[0])
	while first.state != StaffMember.State.OFF_SHIFT:
		_w.step()
		assert_int(_w.clock.tick).is_less(LIMIT_TICKS)
	assert_int(_w.sim.spawn_now(PassengerTestWorld.FLIGHT)).is_greater(0)
	_w.step()
	assert_bool(_w.staff.is_off_shift()).is_false()
	for id in _w.staff.member_ids():
		assert_int(_w.staff.get_member(id).state).is_equal(StaffMember.State.TO_STATION)


func test_fire_and_hire_work_while_off_shift_and_leaving_shift() -> void:
	_w = _make_open()
	StaffTestKit.staff_all(_w.staff, [CHECKIN, SECURITY])
	_w.step()
	var sec_id := _w.staff.member_ids()[3]
	assert_int(_w.staff.get_member(sec_id).state).is_equal(StaffMember.State.LEAVING_SHIFT)
	assert_bool(_w.staff.fire(SECURITY)).is_true()
	assert_int(_w.staff.get_member(sec_id).state).is_equal(StaffMember.State.WALKING_OUT)
	assert_int(_w.staff.count(SECURITY)).is_equal(1)
	while _w.staff.get_member(_w.staff.member_ids()[0]).state != StaffMember.State.OFF_SHIFT:
		_w.step()
		assert_int(_w.clock.tick).is_less(LIMIT_TICKS)
	assert_bool(_w.staff.is_off_shift()).is_true()
	var hired := _w.staff.hire(CHECKIN)
	assert_int(_w.staff.get_member(hired).state).is_equal(StaffMember.State.OFF_SHIFT)
	assert_bool(_w.staff.get_member(hired).in_pool()).is_true()
	assert_int(_w.staff.count(CHECKIN)).is_equal(3)
	assert_bool(_w.staff.fire(CHECKIN)).is_true()
	assert_object(_w.staff.get_member(hired)).is_null()
	assert_int(_w.staff.count(CHECKIN)).is_equal(2)


func test_flightless_world_and_closed_airport_stay_on_post() -> void:
	var closed_grid := BuildGrid.new()
	ReferenceTerminal.build(closed_grid)
	_w = PassengerTestWorld.make(closed_grid, FlightSim.schedule_starts(FIRST))
	_w.auto_staff = false
	assert_int(_w.flights.opened_tick).is_equal(-1)
	# Closed airport with far flight stays on post (opened_tick < 0 is the sole guard).
	StaffTestKit.staff_all(_w.staff, [CHECKIN, SECURITY])
	_w.run_to(3000)
	assert_bool(_w.staff.is_off_shift()).is_false()
	assert_int(_w.staff.on_duty_count(CHECKIN)).is_equal(2)
	assert_int(_w.staff.on_duty_count(SECURITY)).is_equal(2)
	_w.free_all()
	# Open airport with no flights stays on post.
	_w = _make_open()
	var snap := _w.flights.to_snapshot()
	snap["flights"] = []
	assert_bool(_w.flights.from_snapshot(snap)).is_true()
	StaffTestKit.staff_all(_w.staff, [CHECKIN])
	_w.run_to(3000)
	assert_bool(_w.staff.is_off_shift()).is_false()
	assert_int(_w.staff.on_duty_count(CHECKIN)).is_equal(2)


func test_missing_entrance_falls_back_gracefully_to_off_shift() -> void:
	_w = _make_open()
	StaffTestKit.staff_all(_w.staff, [CHECKIN])
	var entrance: int = _w.sim.layout.entrances[0]
	_w.grid.check_staff_reach = false
	assert_bool(_w.grid.apply(BuildEdit.remove_object(entrance)).ok).is_true()
	_w.grid.check_staff_reach = true
	_w.step()
	assert_bool(_w.staff.is_off_shift()).is_true()
	for id in _w.staff.member_ids():
		var m := _w.staff.get_member(id)
		assert_int(m.state).is_equal(StaffMember.State.OFF_SHIFT)
		assert_bool(m.in_pool()).is_true()


func test_save_and_load_round_trip_leaving_shift_and_off_shift() -> void:
	_w = _make_open()
	StaffTestKit.staff_all(_w.staff, [CHECKIN])
	var cleaner := _w.staff.get_member(_w.staff.hire(CLEANER))
	_w.step()
	var walker := _w.staff.get_member(_w.staff.member_ids()[0])
	assert_int(walker.state).is_equal(StaffMember.State.LEAVING_SHIFT)
	assert_int(cleaner.state).is_equal(StaffMember.State.OFF_SHIFT)
	_w.step()
	assert_int(walker.seg_mm).is_greater(0)
	_b = StaffTestKit.load_world(StaffTestKit.save_text(_w))
	assert_object(_b).is_not_null()
	assert_str(StaffTestKit.signature(_b.staff)).is_equal(StaffTestKit.signature(_w.staff))
	var differing := 0
	for i in 400:
		_w.step()
		_b.step()
		differing += int(StaffTestKit.signature(_w.staff) != StaffTestKit.signature(_b.staff))
	assert_int(differing).is_equal(0)
	assert_int(_b.staff.get_member(walker.id).state).is_equal(StaffMember.State.OFF_SHIFT)


func test_miss_signals_hides_overnight_off_shift_closures_but_keeps_real_issues() -> void:
	_w = _make_open()
	# Hire only CHECKIN (not SECURITY): scanners have 0 hired staff.
	StaffTestKit.staff_all(_w.staff, [CHECKIN])
	_w.step()
	assert_bool(_w.staff.is_off_shift()).is_true()
	var desks := _w.sim.layout.desks
	var scanners := _w.sim.layout.scanners
	var closed := MissSignals.closed_stations(_w.sim)
	assert_array(closed).not_contains([desks[0], desks[1]])
	assert_array(closed).contains([scanners[0]])
	# Player-closed desk is still flagged overnight.
	assert_bool(_w.staff.closures.set_closed(desks[0], true)).is_true()
	closed = MissSignals.closed_stations(_w.sim)
	assert_array(closed).contains([desks[0]])
	assert_array(closed).not_contains([desks[1]])
	# Faulted scanner (even with hired off-shift security) is still flagged.
	_w.staff.hire(SECURITY)
	_w.step()
	assert_array(MissSignals.closed_stations(_w.sim)).not_contains([scanners[0]])
	assert_bool(_w.staff.faults.add(scanners[0], 5000)).is_true()
	assert_array(MissSignals.closed_stations(_w.sim)).contains([scanners[0]])


func test_snapshot_rejects_invalid_off_shift_and_leaving_shift_records() -> void:
	_w = _make_open()
	StaffTestKit.staff_all(_w.staff, [CHECKIN])
	var cleaner := _w.staff.get_member(_w.staff.hire(CLEANER))
	_w.step()
	assert_int(cleaner.state).is_equal(StaffMember.State.OFF_SHIFT)
	var good: Dictionary = JSON.parse_string(JSON.stringify(_w.staff.to_snapshot()))
	var off_on_floor := good.duplicate(true)
	off_on_floor["members"][2]["at"] = [
		ReferenceTerminal.ENTRANCE_CELL.x, ReferenceTerminal.ENTRANCE_CELL.y
	]
	off_on_floor["members"][2]["path"] = [
		[ReferenceTerminal.ENTRANCE_CELL.x, ReferenceTerminal.ENTRANCE_CELL.y]
	]
	assert_bool(StaffSnapshot.load(off_on_floor, _w.sim).has("error")).is_true()
	var leaving_in_pool := good.duplicate(true)
	leaving_in_pool["members"][0]["state"] = StaffMember.State.LEAVING_SHIFT
	leaving_in_pool["members"][0]["at"] = [-1, -1]
	leaving_in_pool["members"][0]["path"] = []
	leaving_in_pool["members"][0]["path_index"] = 0
	leaving_in_pool["members"][0]["seg_mm"] = 0
	leaving_in_pool["members"][0]["needs_replan"] = false
	assert_bool(StaffSnapshot.load(leaving_in_pool, _w.sim).has("error")).is_true()


func test_shop_counter_closed_suppressed_overnight_but_keeps_real_issues() -> void:
	var grid := BuildGrid.new()
	var ids := CafeTestLayout.build(grid, true)
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(FIRST))
	_w.auto_staff = false
	assert_bool(_w.flights.open_airport()).is_true()
	StaffTestKit.staff_all(_w.staff, [CHECKIN, StaffMember.Role.SHOP])
	_w.step()
	assert_bool(_w.staff.is_off_shift()).is_true()
	assert_array(ShopCounters.closed(_w.sim)).is_empty()
	var land_counter: int = ids["land_counter"]
	var air_counter: int = ids["air_counter"]
	assert_bool(_w.staff.closures.set_closed(land_counter, true)).is_true()
	assert_array(ShopCounters.closed(_w.sim)).is_equal([land_counter])
	assert_bool(_w.staff.closures.set_closed(land_counter, false)).is_true()
	while _w.staff.count(StaffMember.Role.SHOP) > 0:
		assert_bool(_w.staff.fire(StaffMember.Role.SHOP)).is_true()
	assert_array(ShopCounters.closed(_w.sim)).contains([land_counter, air_counter])


func test_staff_panel_cleaner_counts_text_for_all_and_mixed_off_shift() -> void:
	_w = _make_open()
	var panel := auto_free(StaffPanel.new()) as StaffPanel
	panel.staff = _w.staff
	add_child(panel)
	var mess_cell := ReferenceTerminal.ENTRANCE_CELL + Vector2i(0, -1)
	assert_int(_w.sim.messes.add(MessSim.Kind.LITTER, mess_cell)).is_greater(0)
	var active := _w.staff.get_member(_w.staff.hire(CLEANER))
	var idle := _w.staff.get_member(_w.staff.hire(CLEANER))
	_w.step()
	assert_int(active.state).is_equal(StaffMember.State.TO_STATION)
	assert_int(idle.state).is_equal(StaffMember.State.OFF_SHIFT)
	assert_str(panel.counts_text(CLEANER)).is_equal("2 hired, 0 cleaning, 1 off shift")
	var guard := 0
	while active.state != StaffMember.State.ON_DUTY and guard < LIMIT_TICKS:
		_w.step()
		guard += 1
	assert_int(active.state).is_equal(StaffMember.State.ON_DUTY)
	assert_str(panel.counts_text(CLEANER)).is_equal("2 hired, 1 cleaning, 1 off shift")
	guard = 0
	while active.state != StaffMember.State.OFF_SHIFT and guard < LIMIT_TICKS:
		_w.step()
		guard += 1
	assert_str(panel.counts_text(CLEANER)).is_equal("2 hired, off shift")
