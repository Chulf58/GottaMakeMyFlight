class_name TestStationFaults
extends GdUnitTestSuite
## A scanner fault (StationFaults, decision scanner-fault-incident-design-
## stationfaults-beside-stationcl) on the reference terminal's two staffed
## scanners: the faulted one admits nobody and never says "Closed by you", its
## officer stays posted, its queue and walkers choose again on the next tick,
## and it is open again from StaffSim.step() on its repair tick.

const SECURITY := StaffMember.Role.SECURITY

var _w: PassengerTestWorld
var _a := 0
var _b := 0


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_w = PassengerTestWorld.reference_world(41)
	var scanners := _w.sim.layout.scanners.duplicate()
	scanners.sort()
	_a = scanners[0]
	_b = scanners[1]
	# Seated before the first tick by auto_staff.
	_w.step()


func after_test() -> void:
	if _w != null:
		_w.free_all()
	_w = null


func test_a_faulted_scanner_is_closed_but_never_by_you() -> void:
	# The control: staffed and open before the fault.
	assert_bool(_w.staff.is_open(_a)).is_true()
	var repair := _w.sim.tick + 500
	assert_bool(_w.staff.faults.add(_a, repair)).is_true()
	var words := _w.staff.closures.status_text(_a)
	print("status %s, reason %s" % [words, MissSignals.closed_reason(_w.sim, _a)])
	assert_bool(_w.staff.is_open(_a)).is_false()
	assert_bool(_w.staff.faults.open_but_for_fault(_a)).is_true()
	assert_bool(_w.staff.closures.is_closed(_a)).is_false()
	assert_int(_w.staff.closures.status(_a)).is_equal(StationClosures.Status.FAULT)
	assert_str(words).is_equal("Scanner fault, fixed by %s" % GameCalendar.clock_text(repair))
	assert_str(words).not_contains("Closed by you")
	assert_str(MissSignals.closed_reason(_w.sim, _a)).is_equal(MissSignals.FAULT_REASON)
	# The other scanner is untouched.
	assert_bool(_w.staff.is_open(_b)).is_true()
	# Closed by the player as well, the player's closure is what it says.
	_w.staff.closures.set_closed(_a, true)
	assert_str(_w.staff.closures.status_text(_a)).is_equal("Closed by you")


func test_the_scanner_opens_from_the_staff_step_of_its_repair_tick() -> void:
	var repair := _w.sim.tick + 30
	_w.staff.faults.add(_a, repair)
	var closed_last := -1
	var open_first := -1
	while _w.sim.tick < repair + 3:
		_w.step()
		if _w.staff.is_open(_a):
			open_first = _w.sim.tick if open_first < 0 else open_first
		else:
			closed_last = _w.sim.tick
	print("repair %d, closed last on %d, open first on %d" % [repair, closed_last, open_first])
	assert_int(closed_last).is_equal(repair - 1)
	assert_int(open_first).is_equal(repair)
	assert_bool(_w.staff.faults.is_faulted(_a)).is_false()


func test_on_the_repair_tick_it_is_faulted_until_the_staff_step() -> void:
	var repair := _w.sim.tick + 10
	_w.staff.faults.add(_a, repair)
	_w.sim.tick = repair
	var before_step := _w.staff.is_open(_a)
	_w.staff.step()
	print(
		(
			"on tick %d: open %s before the staff step, %s after"
			% [repair, before_step, _w.staff.is_open(_a)]
		)
	)
	assert_bool(before_step).is_false()
	assert_bool(_w.staff.is_open(_a)).is_true()


func test_the_officer_stays_posted_through_the_fault() -> void:
	var officer := _w.staff.staff_at(_a)
	assert_int(officer).is_not_zero()
	var repair := _w.sim.tick + 40
	_w.staff.faults.add(_a, repair)
	var away := 0
	while _w.sim.tick < repair:
		_w.step()
		var m := _w.staff.get_member(officer)
		if _w.staff.staff_at(_a) != officer or m.state != StaffMember.State.ON_DUTY:
			away += 1
	print("officer %d off its post on %d ticks of the fault" % [officer, away])
	assert_int(away).is_equal(0)
	assert_bool(_w.staff.is_open(_a)).is_true()
	assert_int(_w.staff.staff_at(_a)).is_equal(officer)


func test_a_fault_sends_the_queue_and_its_walkers_to_choose_again() -> void:
	var ids: Array[int] = []
	for i in 8:
		var p := _w.passenger(_w.sim.spawn_now(PassengerTestWorld.FLIGHT))
		p.hunger = 0
		p.stage = Passenger.Stage.TO_SECURITY
		p.at = Vector2i(17, 14)
		p.clear_path()
		ids.append(p.id)
	var mine := []
	for i in 400:
		_w.step()
		mine = ids.filter(func(id: int) -> bool: return _w.passenger(id).station == _a)
		var queued := mine.filter(
			func(id: int) -> bool: return _w.passenger(id).stage == Passenger.Stage.SECURITY_QUEUE
		)
		if queued.size() >= 2:
			break
	print("committed to the faulted scanner before the fault: %s" % [mine])
	assert_int(mine.size()).is_greater_equal(2)
	_w.staff.faults.add(_a, _w.sim.tick + 600)
	_w.step()
	var still := []
	for id: int in mine:
		var p := _w.passenger(id)
		if (
			p.station == _a
			and p.stage in [Passenger.Stage.TO_SECURITY, Passenger.Stage.SECURITY_QUEUE]
		):
			still.append(id)
	var moved := mine.filter(func(id: int) -> bool: return _w.passenger(id).station == _b)
	print("after one tick: still at the faulted scanner %s, gone to the other %s" % [still, moved])
	assert_array(still).is_empty()
	assert_int(_w.sim.queue_of(_a).size() + _w.sim.holding_of(_a).size()).is_zero()
	assert_int(moved.size()).is_greater(0)


func test_staff_changed_is_emitted_on_the_fault_and_on_its_repair() -> void:
	var emitted := [0]
	_w.staff.staff_changed.connect(func() -> void: emitted[0] += 1)
	var repair := _w.sim.tick + 5
	_w.staff.faults.add(_a, repair)
	assert_int(emitted[0]).is_equal(1)
	while _w.sim.tick < repair:
		_w.step()
	print("staff_changed emitted %d times" % emitted[0])
	assert_int(emitted[0]).is_greater_equal(2)
	assert_bool(_w.staff.faults.is_faulted(_a)).is_false()
