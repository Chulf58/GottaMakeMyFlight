class_name TestStaffOnTheWay
extends GdUnitTestSuite
## A hired member still walking to a station does not open it (decisions the-
## airport-opens-when-staffed and staff-are-hired-by-role-into-a-pool-and-walk-
## to-unstaffed-st): the checklist keeps that opening line unticked with an "on
## the way" note until the member is on duty, and the Nobody on duty alert asks
## the player to hire only for stations nobody is assigned to.

const LIMIT_TICKS := 4000

var _w: PassengerTestWorld
var _gate: AirportGate
var _panel: StaffPanel


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _w != null:
		_w.free_all()
	_w = null


func _make() -> void:
	_w = PassengerTestWorld.reference_world()
	_w.auto_staff = false
	_gate = auto_free(AirportGate.new())
	_gate.bind(_w.flights, _w.staff)
	_panel = auto_free(StaffPanel.new())
	_panel.staff = _w.staff
	_panel.gate = _gate
	add_child(_panel)


func _role_of(station: int) -> StaffMember.Role:
	if _w.sim.layout.desks.has(station):
		return StaffMember.Role.CHECKIN
	if _w.sim.layout.scanners.has(station):
		return StaffMember.Role.SECURITY
	return StaffMember.Role.SHOP


## Hires one member of the right role for each closed station of `roles` (every
## role when empty) and steps once, so each is sent walking to its station.
func _hire_for_closed(roles: Array[StaffMember.Role] = []) -> int:
	var stations := MissSignals.closed_stations(_w.sim)
	stations.append_array(ShopCounters.closed(_w.sim))
	var hired := 0
	for station in stations:
		var role := _role_of(station)
		if roles.is_empty() or roles.has(role):
			_w.staff.hire(role)
			hired += 1
	_w.step()
	return hired


func _walking() -> int:
	var count := 0
	for id in _w.staff.member_ids():
		count += int(_w.staff.get_member(id).state == StaffMember.State.TO_STATION)
	return count


func _rows() -> PackedStringArray:
	return _panel.checklist().row_texts()


func _open_texts(lines: Array[Dictionary], done: bool) -> Array:
	var out := []
	for entry in lines:
		if entry["done"] == done:
			out.append(entry["text"])
	return out


func test_the_staff_lines_stay_unticked_while_the_members_walk_and_tick_on_arrival() -> void:
	_make()
	_hire_for_closed()
	_panel.refresh()
	var walking := _walking()
	var lines := _panel.card_lines()
	print("walking %d, unmet %s, lines %s" % [walking, _gate.unmet(), lines])
	assert_int(walking).is_greater(0)
	assert_array(_gate.unmet()).contains([AirportGate.Blocker.NO_CHECKIN])
	assert_array(_gate.unmet()).contains([AirportGate.Blocker.NO_SECURITY])
	var open := _open_texts(lines, false)
	assert_array(open).contains(["Check-in desk and an agent: the agent is on the way"])
	assert_array(open).contains(["Security scanner and an officer: the officer is on the way"])
	assert_array(Array(_rows())).contains(
		["Security scanner and an officer: the officer is on the way"]
	)
	# Arrival: every member on duty, the lines tick and fold away.
	while _walking() > 0 and _w.clock.tick < LIMIT_TICKS:
		_w.step()
	_panel.refresh()
	print("arrived, unmet %s, open %s" % [_gate.unmet(), _gate.is_open()])
	assert_int(_walking()).is_equal(0)
	assert_array(_gate.unmet()).is_empty()
	# The same rules with every blocker gone tick both lines, and the airport,
	# staffed now, opens and drops its opening lines from the card.
	var counts := {
		"desks": 1, "scanners": 1, "seats": 1, "checkin_staying": 1, "security_staying": 1
	}
	var done := _open_texts(Checklist.opening_lines(_gate.unmet(), counts), true)
	assert_array(done).contains([Checklist.CHECKIN, Checklist.SECURITY])
	assert_bool(_gate.is_open()).is_true()
	(
		assert_array(
			Array(_rows()).filter(func(t: String) -> bool: return t.contains("on the way"))
		)
		. is_empty()
	)


func test_the_alert_says_staff_are_on_the_way_when_every_closed_station_has_a_walker() -> void:
	_make()
	var closed := MissSignals.closed_stations(_w.sim).size() + ShopCounters.closed(_w.sim).size()
	assert_int(closed).is_greater(1)
	# The control: nobody hired, the alert asks to hire.
	var before_hire := AlertSources.closed_stations(_w.sim)
	assert_str(before_hire[0]["detail"]).is_equal(
		"%d stations are closed · hire staff on the Staff card" % closed
	)
	_hire_for_closed()
	assert_int(_walking()).is_equal(closed)
	var causes := AlertSources.closed_stations(_w.sim)
	print("walking %d of %d closed, causes %s" % [_walking(), closed, causes])
	assert_int(causes.size()).is_equal(1)
	assert_str(causes[0]["key"]).is_equal(AlertSources.NO_STAFF)
	assert_str(causes[0]["title"]).is_equal("Nobody on duty")
	assert_str(causes[0]["detail"]).is_equal(
		"%d stations are closed · staff are on the way" % closed
	)
	assert_str(causes[0]["detail"]).not_contains("hire")
	assert_int((causes[0]["targets"] as Array).size()).is_equal(
		mini(closed, AlertSources.MAX_TARGETS)
	)
	# On arrival the card has nothing left to say.
	while _walking() > 0 and _w.clock.tick < LIMIT_TICKS:
		_w.step()
	assert_array(AlertSources.closed_stations(_w.sim)).is_empty()


func test_a_station_nobody_is_assigned_to_keeps_the_hire_text() -> void:
	_make()
	var closed := MissSignals.closed_stations(_w.sim).size() + ShopCounters.closed(_w.sim).size()
	var hired := _hire_for_closed([StaffMember.Role.CHECKIN])
	var left := closed - hired
	var causes := AlertSources.closed_stations(_w.sim)
	print("hired %d agents, %d stations left, causes %s" % [hired, left, causes])
	assert_int(hired).is_greater(0)
	assert_int(left).is_greater(0)
	assert_int(causes.size()).is_equal(1)
	var detail: String = causes[0]["detail"]
	assert_str(detail).contains("hire staff on the Staff card")
	assert_str(detail).not_contains("on the way")
	# It counts and points at the stations nobody is assigned to, not the walkers.
	assert_str(detail).starts_with("%d station" % left)
	assert_int((causes[0]["targets"] as Array).size()).is_equal(
		mini(left, AlertSources.MAX_TARGETS)
	)
