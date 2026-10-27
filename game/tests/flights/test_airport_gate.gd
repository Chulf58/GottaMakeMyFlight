class_name TestAirportGate
extends GdUnitTestSuite
## The airport opens once passengers have a working path, a check-in agent is
## on duty at a desk and a security officer at a scanner (decision
## airport-opening-design-stays-open-once-opened-starter-flight-placed-after-
## opening). A member still walking to a station does not count. Once open it
## never closes, and the opening accepts the starter contract.
##
## The reference terminal has a working path; PassengerTestWorld's one-off
## GMF101 holds gate C over ticks 0 to 2580.

const CHECKIN := StaffMember.Role.CHECKIN
const SECURITY := StaffMember.Role.SECURITY
const STARTER := FlightSim.DEFAULT_ID

var _w: PassengerTestWorld
var _gate: AirportGate


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _w != null:
		_w.free_all()
	_w = null


func _make(reference := true) -> void:
	if reference:
		_w = PassengerTestWorld.reference_world()
	else:
		_w = PassengerTestWorld.make(
			PassengerTestWorld.floored(Vector2i(12, 12)), FlightSim.schedule_starts(0)
		)
	_w.auto_staff = false
	_gate = auto_free(AirportGate.new())
	_gate.bind(_w.flights, _w.staff)


## Steps until a member of `role` is on duty; returns the tick it went on duty.
func _until_on_duty(role: StaffMember.Role) -> int:
	while _w.staff.on_duty_count(role) == 0 and _w.clock.tick < 3000:
		_w.step()
	assert_int(_w.staff.on_duty_count(role)).is_equal(1)
	return _w.clock.tick


func test_a_grid_with_no_working_path_is_blocked_on_the_path() -> void:
	_make(false)
	assert_int(_gate.blocker()).is_equal(AirportGate.Blocker.NO_PATH)
	assert_bool(_gate.ready_to_open()).is_false()
	_w.run_to(100)
	assert_int(_w.flights.opened_tick).is_equal(-1)


func test_it_opens_on_the_tick_after_an_agent_and_an_officer_are_on_duty() -> void:
	_make()
	assert_int(_gate.blocker()).is_equal(AirportGate.Blocker.NO_CHECKIN)
	_w.staff.hire(CHECKIN)
	_w.step()
	var walking := _w.staff.get_member(_w.staff.member_ids()[0])
	assert_int(walking.state).is_equal(StaffMember.State.TO_STATION)
	assert_int(_gate.blocker()).is_equal(AirportGate.Blocker.NO_CHECKIN)
	_until_on_duty(CHECKIN)
	assert_int(_gate.blocker()).is_equal(AirportGate.Blocker.NO_SECURITY)
	_w.staff.hire(SECURITY)
	_w.step()
	assert_int(_gate.blocker()).is_equal(AirportGate.Blocker.NO_SECURITY)
	assert_bool(_gate.ready_to_open()).is_false()
	var on_duty := _until_on_duty(SECURITY)
	print("checkin on duty, security on duty at tick %d" % on_duty)
	assert_bool(_gate.ready_to_open()).is_true()
	assert_int(_w.flights.opened_tick).is_equal(-1)
	assert_array(_w.flights.contract_ids()).is_empty()
	_w.step()
	assert_int(_w.flights.opened_tick).is_equal(on_duty + 1)
	assert_bool(_gate.is_open()).is_true()
	assert_int(_gate.blocker()).is_equal(AirportGate.Blocker.NONE)
	assert_array(_w.flights.contract_ids()).is_equal([STARTER])


func test_once_open_it_stays_open_after_everyone_is_fired() -> void:
	_make()
	StaffTestKit.staff_all(_w.staff)
	_w.step()
	var opened := _w.flights.opened_tick
	assert_int(opened).is_equal(1)
	while _w.staff.fire(CHECKIN) or _w.staff.fire(SECURITY):
		pass
	_w.run_to(400)
	assert_int(_w.staff.count(CHECKIN) + _w.staff.count(SECURITY)).is_equal(0)
	assert_int(_w.flights.opened_tick).is_equal(opened)
	assert_bool(_gate.is_open()).is_true()
	assert_bool(_gate.ready_to_open()).is_false()
	assert_int(_gate.blocker()).is_equal(AirportGate.Blocker.NONE)
	var first := FlightTimetable.occurrence_id(STARTER, 0)
	_w.run_to(_w.flights.state_start(first, FlightSim.State.SCHEDULED) + 1)
	assert_int(_w.flights.state_of(first)).is_equal(FlightSim.State.SCHEDULED)


## Opened at 1000, a whole minute: the starter's first state is 1000 + 2400,
## so it is issued on the opening tick and departs 98 minutes after that.
func test_the_starter_s_first_flight_starts_the_lead_after_opening_and_repeats_daily() -> void:
	_make()
	_w.run_to(1000)
	assert_bool(_gate.open()).is_true()
	var first := FlightTimetable.occurrence_id(STARTER, 0)
	var start := 1000 + FlightTimetable.ISSUE_LEAD_TICKS
	assert_array(_w.flights.flight_ids()).contains([first])
	assert_int(_w.flights.state_start(first, FlightSim.State.SCHEDULED)).is_equal(start)
	var pushback := _w.flights.state_start(first, FlightSim.State.PUSHBACK)
	assert_int(pushback).is_equal(start + FlightTimetable.departure_offset())
	var contract := _w.flights.contract_of(STARTER)
	assert_int(contract["departure_minute"]).is_equal(GameCalendar.minute_of_day(pushback))
	assert_int(contract["booked_passengers"]).is_equal(FlightSim.STARTER_TERMS["booked_passengers"])
	_w.run_to(1000 + GameCalendar.TICKS_PER_DAY)
	var second := FlightTimetable.occurrence_id(STARTER, 1)
	assert_array(_w.flights.flight_ids()).contains([second])
	assert_int(_w.flights.state_start(second, FlightSim.State.SCHEDULED)).is_equal(
		start + GameCalendar.TICKS_PER_DAY
	)


## Opened at 1007, between whole minutes: the first state rounds up to 3420,
## so the first flight is issued at 1020 and never earlier than the lead.
func test_an_opening_between_minutes_rounds_the_starter_up_to_the_next_minute() -> void:
	_make()
	_w.run_to(1007)
	_gate.open()
	var first := FlightTimetable.occurrence_id(STARTER, 0)
	assert_array(_w.flights.flight_ids()).not_contains([first])
	_w.run_to(1019)
	assert_array(_w.flights.flight_ids()).not_contains([first])
	_w.run_to(1020)
	assert_array(_w.flights.flight_ids()).contains([first])
	assert_int(_w.flights.state_start(first, FlightSim.State.SCHEDULED)).is_equal(3420)


func test_a_second_open_is_refused_and_adds_no_second_starter() -> void:
	_make()
	_w.run_to(1000)
	assert_bool(_gate.open()).is_true()
	await (
		assert_error(func() -> void: _gate.open())
		. is_push_error("FlightSim.open_airport: the airport opened at tick 1000")
	)
	assert_array(_w.flights.contract_ids()).is_equal([STARTER])
