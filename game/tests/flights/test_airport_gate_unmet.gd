class_name TestAirportGateUnmet
extends GdUnitTestSuite
## AirportGate.unmet() lists every blocker that keeps the airport closed, not
## only the first, for the checklist card (decision checklist-card-shows-what-
## the-airport-still-needs). blocker() stays the first of them, or NONE.

const BLOCKER := AirportGate.Blocker

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


func _make(reference: bool) -> void:
	if reference:
		_w = PassengerTestWorld.reference_world()
	else:
		_w = PassengerTestWorld.make(
			PassengerTestWorld.floored(Vector2i(12, 12)), FlightSim.schedule_starts(0)
		)
	_w.auto_staff = false
	_gate = auto_free(AirportGate.new())
	_gate.bind(_w.flights, _w.staff)


func _first_or_none() -> int:
	var all := _gate.unmet()
	return BLOCKER.NONE if all.is_empty() else all[0]


func test_a_bare_floor_lists_the_path_check_in_and_security() -> void:
	_make(false)
	var all := _gate.unmet()
	print("bare floor unmet %s, blocker %d" % [all, _gate.blocker()])
	assert_array(all).contains_exactly([BLOCKER.NO_PATH, BLOCKER.NO_CHECKIN, BLOCKER.NO_SECURITY])
	assert_int(_gate.blocker()).is_equal(BLOCKER.NO_PATH)


func test_an_unstaffed_terminal_lists_both_roles() -> void:
	_make(true)
	var all := _gate.unmet()
	print("unstaffed reference unmet %s" % [all])
	assert_array(all).contains_exactly([BLOCKER.NO_CHECKIN, BLOCKER.NO_SECURITY])
	assert_int(_gate.blocker()).is_equal(_first_or_none())


func test_closing_every_desk_lists_the_closure_and_the_missing_officer() -> void:
	_make(true)
	for desk in _w.sim.layout.desks:
		_w.staff.closures.set_closed(desk, true)
	var all := _gate.unmet()
	print("desks closed unmet %s" % [all])
	assert_array(all).contains_exactly([BLOCKER.CHECKIN_CLOSED, BLOCKER.NO_SECURITY])
	assert_int(_gate.blocker()).is_equal(BLOCKER.CHECKIN_CLOSED)


func test_a_staffed_terminal_has_nothing_unmet_and_open_stays_empty() -> void:
	_make(true)
	var hired := StaffTestKit.staff_all(_w.staff)
	print("staffed %d, unmet %s" % [hired, _gate.unmet()])
	assert_int(hired).is_greater(0)
	assert_array(_gate.unmet()).is_empty()
	assert_int(_gate.blocker()).is_equal(BLOCKER.NONE)
	assert_bool(_gate.open()).is_true()
	# Fired staff do not close an open airport, so nothing is unmet.
	for id in _w.staff.member_ids():
		_w.staff.fire(_w.staff.get_member(id).role)
	assert_array(_gate.unmet()).is_empty()
	assert_int(_gate.blocker()).is_equal(BLOCKER.NONE)
