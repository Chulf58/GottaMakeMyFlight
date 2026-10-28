class_name TestStaffGating
extends GdUnitTestSuite
## A desk or scanner without staff on duty is closed: nobody queues at it and
## nobody is served there. An agent fired mid-service stays on duty until that
## service ends; the desk takes nobody new and sends its queue to choose again.

const CHECKIN := StaffMember.Role.CHECKIN
const SECURITY := StaffMember.Role.SECURITY

var _w: PassengerTestWorld
var _ids: Dictionary
var _reached: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_w = PassengerTestWorld.reference_world()
	_w.auto_staff = false
	_ids = ReferenceTerminal.object_ids(_w.grid)
	_reached = {}
	_w.sim.stage_changed.connect(_on_stage)


func after_test() -> void:
	_w.free_all()
	_w = null


func _on_stage(_id: int, stage: Passenger.Stage) -> void:
	_reached[stage] = int(_reached.get(stage, 0)) + 1


func _spawn(count: int) -> Array[int]:
	var ids: Array[int] = []
	for i in count:
		ids.append(_w.sim.spawn_now(PassengerTestWorld.FLIGHT))
	return ids


func test_with_no_staff_nobody_checks_in() -> void:
	var ids := _spawn(4)
	_w.run_to(_w.clock.tick + 400)
	var stuck := 0
	for id in ids:
		var p := _w.passenger(id)
		stuck += int(p.stuck == Passenger.Stuck.NO_CHECKIN)
		assert_int(p.stage).is_equal(Passenger.Stage.TO_CHECKIN)
	print(
		(
			"TO_CHECKIN reached %d, CHECKIN reached %d"
			% [
				_reached.get(Passenger.Stage.TO_CHECKIN, 0),
				_reached.get(Passenger.Stage.CHECKIN, 0)
			]
		)
	)
	assert_int(_reached.get(Passenger.Stage.TO_CHECKIN, 0)).is_equal(4)
	assert_int(stuck).is_equal(4)
	assert_int(_reached.get(Passenger.Stage.CHECKIN_QUEUE, 0)).is_equal(0)
	assert_int(_reached.get(Passenger.Stage.CHECKIN, 0)).is_equal(0)
	for desk in _ids["desks"]:
		assert_array(_w.sim.queue_of(desk)).is_empty()


func test_a_passenger_with_no_open_desk_is_stuck_not_late() -> void:
	var id: int = _spawn(1)[0]
	_w.run_to(_w.clock.tick + 100)
	var p := _w.passenger(id)
	assert_int(JourneyForecast.arrival_tick(_w.sim, p)).is_equal(JourneyForecast.NEVER)
	assert_bool(p.late).is_false()


func test_with_agents_but_no_officer_nobody_is_screened() -> void:
	StaffTestKit.staff_all(_w.staff)
	while _w.staff.fire(SECURITY):
		pass
	var ids := _spawn(3)
	_w.run_to(_w.clock.tick + 900)
	print(
		(
			"CHECKIN reached %d, SECURITY reached %d"
			% [_reached.get(Passenger.Stage.CHECKIN, 0), _reached.get(Passenger.Stage.SECURITY, 0)]
		)
	)
	assert_int(_reached.get(Passenger.Stage.CHECKIN, 0)).is_equal(3)
	assert_int(_reached.get(Passenger.Stage.SECURITY_QUEUE, 0)).is_equal(0)
	assert_int(_reached.get(Passenger.Stage.SECURITY, 0)).is_equal(0)
	for id in ids:
		assert_int(_w.passenger(id).stuck).is_equal(Passenger.Stuck.NO_SECURITY)


func test_staff_arriving_opens_the_desk_for_waiting_passengers() -> void:
	var ids := _spawn(2)
	_w.run_to(_w.clock.tick + 100)
	assert_int(_reached.get(Passenger.Stage.CHECKIN, 0)).is_equal(0)
	_w.staff.hire(CHECKIN)
	_w.staff.hire(SECURITY)
	_w.run_to(_w.clock.tick + 900)
	print(
		(
			"CHECKIN reached %d, SECURITY reached %d"
			% [_reached.get(Passenger.Stage.CHECKIN, 0), _reached.get(Passenger.Stage.SECURITY, 0)]
		)
	)
	assert_int(_reached.get(Passenger.Stage.CHECKIN, 0)).is_equal(2)
	assert_int(_reached.get(Passenger.Stage.SECURITY, 0)).is_equal(2)
	for id in ids:
		assert_bool(_w.passenger(id).cleared).is_true()


func test_an_agent_fired_mid_service_stays_until_it_ends_then_the_desk_closes() -> void:
	StaffTestKit.staff_all(_w.staff)
	# The kit seats desks in id order; firing an agent takes the higher id, so
	# only the first desk stays open.
	assert_bool(_w.staff.fire(CHECKIN)).is_true()
	var desk: int = _ids["desks"][0]
	assert_bool(_w.staff.is_staffed(desk)).is_true()
	_spawn(4)
	var served := 0
	for i in 600:
		_w.step()
		served = _w.sim.queue_of(desk)[0] if _w.sim.queue_of(desk).size() >= 3 else 0
		if served != 0 and _w.passenger(served).stage == Passenger.Stage.CHECKIN:
			break
		served = 0
	assert_int(served).is_greater(0)
	var behind := _w.sim.queue_of(desk).slice(1)
	var agent := _w.staff.staff_at(desk)
	var check_ins: int = _reached[Passenger.Stage.CHECKIN]
	# Fired mid-service: the agent stays on duty until this service ends, and
	# the desk takes nobody new meanwhile.
	assert_bool(_w.staff.fire(CHECKIN)).is_true()
	assert_int(_w.staff.leaving_count(CHECKIN)).is_equal(1)
	assert_int(_w.staff.count(CHECKIN)).is_equal(1)
	assert_bool(_w.staff.fire(CHECKIN)).is_false()
	assert_bool(_w.staff.is_staffed(desk)).is_true()
	assert_bool(_w.staff.is_open(desk)).is_false()
	_w.step()
	assert_array(_w.sim.queue_of(desk)).is_equal([served])
	for id in behind:
		var p := _w.passenger(id)
		assert_int(p.station).is_equal(0)
		assert_int(p.stage).is_equal(Passenger.Stage.TO_CHECKIN)
		assert_int(p.stuck).is_equal(Passenger.Stuck.NO_CHECKIN)
	var unstaffed_in_service := 0
	while _w.passenger(served).stage == Passenger.Stage.CHECKIN and _w.clock.tick < 1000:
		unstaffed_in_service += int(not _w.staff.is_staffed(desk))
		_w.step()
	assert_int(unstaffed_in_service).is_equal(0)
	assert_int(_w.passenger(served).stage).is_equal(Passenger.Stage.TO_SECURITY)
	# The service ended on this tick; the agent walks out on the next one.
	_w.step()
	print("agent %d left its desk at tick %d" % [agent, _w.clock.tick])
	var leaver := _w.staff.get_member(agent)
	assert_int(leaver.state).is_equal(StaffMember.State.WALKING_OUT)
	assert_bool(leaver.leaving).is_false()
	assert_int(_w.staff.count(CHECKIN)).is_equal(0)
	assert_int(_w.staff.leaving_count(CHECKIN)).is_equal(0)
	assert_bool(_w.staff.is_staffed(desk)).is_false()
	_w.run_to(_w.clock.tick + 200)
	# It reached the entrance and is gone.
	assert_object(_w.staff.get_member(agent)).is_null()
	assert_that(leaver.at).is_equal(ReferenceTerminal.ENTRANCE_CELL)
	assert_array(_w.sim.queue_of(desk)).is_empty()
	assert_int(_reached[Passenger.Stage.CHECKIN]).is_equal(check_ins)
	for id in behind:
		assert_int(_w.passenger(id).stage).is_equal(Passenger.Stage.TO_CHECKIN)
