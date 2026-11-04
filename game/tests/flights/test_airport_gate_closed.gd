class_name TestAirportGateClosed
extends GdUnitTestSuite
## Before the airport opens, closing every check-in desk or every scanner and
## lane (StationClosures) keeps it closed with its own blocker, CHECKIN_CLOSED
## or SECURITY_CLOSED, so the banner asks the player to open one again rather
## than to hire staff who are already there. A desk left open with nobody at
## it is still NO_CHECKIN.

const CHECKIN := StaffMember.Role.CHECKIN
const SECURITY := StaffMember.Role.SECURITY
const BLOCKER := AirportGate.Blocker

var _w: PassengerTestWorld
var _gate: AirportGate
var _panel: StaffPanel


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_w = PassengerTestWorld.reference_world()
	_w.auto_staff = false
	_gate = auto_free(AirportGate.new())
	_gate.bind(_w.flights, _w.staff)
	_panel = auto_free(StaffPanel.new())
	_panel.staff = _w.staff
	_panel.gate = _gate
	add_child(_panel)


func after_test() -> void:
	_w.free_all()
	_w = null


## Closes each of `stations` in turn; returns the blocker after each closure.
func _close_each(stations: Array[int]) -> Array:
	var blockers := []
	for station in stations:
		_w.staff.closures.set_closed(station, true)
		blockers.append(_gate.blocker())
	return blockers


func test_closing_every_desk_asks_to_open_one_again() -> void:
	StaffTestKit.staff_all(_w.staff)
	assert_int(_gate.blocker()).is_equal(BLOCKER.NONE)
	var blockers := _close_each(_w.sim.layout.desks)
	print(
		(
			"blockers as desks close %s, agents %d, hint '%s'"
			% [blockers, _w.staff.count(CHECKIN), _panel.hint_label().text]
		)
	)
	assert_array(blockers).is_equal([BLOCKER.NONE, BLOCKER.CHECKIN_CLOSED])
	assert_int(_w.staff.count(CHECKIN)).is_equal(2)
	assert_str(_panel.hint_text().split("\n")[0]).is_equal(
		"Check-in desk and an agent: you closed every desk, open one again"
	)
	_w.staff.closures.set_closed(_w.sim.layout.desks[0], false)
	assert_int(_gate.blocker()).is_equal(BLOCKER.NONE)


func test_closing_every_scanner_asks_to_open_one_again() -> void:
	StaffTestKit.staff_all(_w.staff)
	var blockers := _close_each(_w.sim.layout.scanners)
	print("blockers as scanners close %s, hint '%s'" % [blockers, _panel.hint_label().text])
	assert_int(blockers.back()).is_equal(BLOCKER.SECURITY_CLOSED)
	assert_int(blockers.size()).is_greater(1)
	for b: int in blockers.slice(0, blockers.size() - 1):
		assert_int(b).is_equal(BLOCKER.NONE)
	assert_str(_panel.hint_text().split("\n")[0]).is_equal(
		"Security scanner and an officer: you closed every scanner and lane, open one again"
	)


func test_an_open_desk_with_nobody_at_it_still_asks_for_an_agent() -> void:
	StaffTestKit.staff_all(_w.staff, [SECURITY])
	_w.staff.closures.set_closed(_w.sim.layout.desks[0], true)
	print("one desk closed, no agent: blocker %d" % _gate.blocker())
	assert_int(_gate.blocker()).is_equal(BLOCKER.NO_CHECKIN)
	assert_str(_panel.hint_text().split("\n")[0]).is_equal(
		"Check-in desk and an agent: hire an agent on Staff"
	)
