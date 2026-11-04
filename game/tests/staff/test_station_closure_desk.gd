class_name TestStationClosureDesk
extends GdUnitTestSuite
## The player closes and opens a check-in desk (StationClosures; decision
## select-placed-items-design-click-order-gold-footprint-highli). Closing stops
## admission at once and sends the queue to choose again; the passenger in
## service is finished; then the agent goes idle where it stood, still paid,
## and the posting pass may send it to another desk. Opening before that keeps
## the same agent serving; opening after it waits for the posting pass.

const CHECKIN := StaffMember.Role.CHECKIN
const STATE := StaffMember.State
const STATUS := StationClosures.Status
const LIMIT_TICKS := 1500

var _w: PassengerTestWorld
var _a := 0
var _b := 0


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_w = PassengerTestWorld.reference_world(5)
	_w.auto_staff = false
	var desks := _w.sim.layout.desks.duplicate()
	desks.sort()
	_a = desks[0]
	_b = desks[1]


func after_test() -> void:
	_w.free_all()
	_w = null


## Hires an agent and puts it on duty at `desk` at once; returns it.
func _seat(desk: int) -> StaffMember:
	var m := _w.staff.get_member(_w.staff.hire(CHECKIN))
	m.station = desk
	m.at = _w.staff.spot_of(desk)
	m.clear_path()
	m.state = STATE.ON_DUTY
	_w.staff.rederive()
	return m


## The passenger being checked in at `desk`, or null.
func _serving(desk: int) -> Passenger:
	for id in _w.sim.passenger_ids():
		var p := _w.passenger(id)
		if p.station == desk and p.stage == Passenger.Stage.CHECKIN:
			return p
	return null


## Spawns `count` passengers and steps until `desk` serves one with at least
## `queued` more in its lane or holding; returns the one in service.
func _until_served(desk: int, count: int, queued: int) -> Passenger:
	for i in count:
		_w.sim.spawn_now(PassengerTestWorld.FLIGHT)
	while _w.clock.tick < LIMIT_TICKS:
		_w.step()
		var p := _serving(desk)
		var waiting := _w.sim.queue_of(desk).size() + _w.sim.holding_of(desk).size() - 1
		if p != null and waiting >= queued:
			return p
	return null


func test_closing_a_desk_sends_its_queue_to_the_open_desk_and_finishes_the_service() -> void:
	var agent := _seat(_a)
	_seat(_b)
	var served := _until_served(_a, 10, 2)
	assert_object(served).is_not_null()
	var queued: Array[int] = []
	for id: int in _w.sim.queue_of(_a) + _w.sim.holding_of(_a):
		if id != served.id:
			queued.append(id)
	print("desk %d serves %d, queued %s at tick %d" % [_a, served.id, queued, _w.clock.tick])
	assert_int(queued.size()).is_greater_equal(2)
	var checked_at := {}
	_w.sim.checked_in.connect(func(id: int, desk: int) -> void: checked_at[id] = desk)
	assert_bool(_w.staff.closures.set_closed(_a, true)).is_true()
	assert_bool(_w.staff.is_open(_a)).is_false()
	assert_str(_w.staff.closures.status_text(_a)).is_equal("Finishing current service")
	_w.step()
	for id in queued:
		assert_int(_w.passenger(id).station).is_not_equal(_a)
	var joined_a := 0
	while served.stage == Passenger.Stage.CHECKIN and _w.clock.tick < LIMIT_TICKS:
		assert_int(agent.state).is_equal(STATE.ON_DUTY)
		_w.step()
		for id in _w.sim.passenger_ids():
			joined_a += int(id != served.id and _w.passenger(id).station == _a)
	assert_int(checked_at.get(served.id, 0)).is_equal(_a)
	var spot := _w.staff.spot_of(_a)
	_w.step()
	print(
		(
			"agent %d state %d at %s (spot %s), station %d"
			% [agent.id, agent.state, agent.at, spot, agent.station]
		)
	)
	assert_int(joined_a).is_equal(0)
	assert_int(agent.state).is_equal(STATE.IDLE)
	assert_that(agent.at).is_equal(spot)
	assert_int(_w.staff.staff_at(_a)).is_equal(0)
	# Still on the roster, so Settlement still pays its wage.
	assert_int(_w.staff.count(CHECKIN)).is_equal(2)
	assert_str(_w.staff.closures.status_text(_a)).is_equal("Closed by you")
	_w.run_to(_w.clock.tick + 900)
	var at_b := 0
	for id in queued:
		at_b += int(checked_at.get(id, 0) == _b)
	print(
		"queued checked in: %s" % [queued.map(func(id: int) -> int: return checked_at.get(id, 0))]
	)
	assert_int(at_b).is_equal(queued.size())
	# Only the passenger in service at the closure was checked in at the desk.
	assert_int(checked_at.values().count(_a)).is_equal(1)


func test_the_released_agent_is_posted_to_an_unstaffed_desk() -> void:
	var agent := _seat(_a)
	var served := _until_served(_a, 2, 0)
	assert_object(served).is_not_null()
	var seen: Array = []
	_w.staff.member_state_changed.connect(
		func(id: int, state: StaffMember.State) -> void:
			if id == agent.id:
				seen.append([state, agent.at, agent.station])
	)
	assert_str(_w.staff.closures.status_text(_b)).is_equal("Waiting for staff")
	_w.staff.closures.set_closed(_a, true)
	while not _w.staff.is_open(_b) and _w.clock.tick < LIMIT_TICKS:
		_w.step()
	print("agent %d went %s; desk %d open %s" % [agent.id, seen, _b, _w.staff.is_open(_b)])
	assert_int(seen.size()).is_greater_equal(3)
	assert_that(seen[0]).is_equal([STATE.IDLE, _w.staff.spot_of(_a), 0])
	assert_int(seen[1][0]).is_equal(STATE.TO_STATION)
	assert_int(seen[1][2]).is_equal(_b)
	assert_bool(_w.staff.is_open(_b)).is_true()
	assert_int(_w.staff.staff_at(_b)).is_equal(agent.id)
	assert_int(_w.staff.count(CHECKIN)).is_equal(1)
	assert_str(_w.staff.closures.status_text(_b)).is_equal("Serving")


func test_reopening_before_the_release_keeps_the_same_agent_serving() -> void:
	var agent := _seat(_a)
	var served := _until_served(_a, 2, 0)
	assert_object(served).is_not_null()
	_w.staff.closures.set_closed(_a, true)
	_w.step()
	var closed_open := _w.staff.is_open(_a)
	assert_bool(served.stage == Passenger.Stage.CHECKIN).is_true()
	_w.staff.closures.set_closed(_a, false)
	print("open while closed %s, after reopening %s" % [closed_open, _w.staff.is_open(_a)])
	assert_bool(closed_open).is_false()
	assert_bool(_w.staff.is_open(_a)).is_true()
	assert_str(_w.staff.closures.status_text(_a)).is_equal("Serving")
	while served.stage == Passenger.Stage.CHECKIN and _w.clock.tick < LIMIT_TICKS:
		_w.step()
	_w.run_to(_w.clock.tick + 30)
	assert_int(agent.state).is_equal(STATE.ON_DUTY)
	assert_int(_w.staff.staff_at(_a)).is_equal(agent.id)
	assert_bool(_w.staff.is_open(_a)).is_true()


func test_reopening_after_the_release_waits_for_the_posting_pass() -> void:
	var first := _seat(_a)
	_w.staff.closures.set_closed(_a, true)
	_w.step()
	assert_int(first.station).is_equal(_b)
	_w.staff.closures.set_closed(_a, false)
	assert_bool(_w.staff.closures.is_closed(_a)).is_false()
	assert_str(_w.staff.closures.status_text(_a)).is_equal("Waiting for staff")
	_w.staff.hire(CHECKIN)
	var statuses := {}
	while not _w.staff.is_open(_a) and _w.clock.tick < LIMIT_TICKS:
		_w.step()
		statuses[_w.staff.closures.status_text(_a)] = true
	print("desk %d went through %s" % [_a, statuses.keys()])
	assert_bool(statuses.has("Staff on the way")).is_true()
	assert_bool(_w.staff.is_open(_a)).is_true()
	assert_int(_w.staff.staff_at(_a)).is_not_equal(first.id)
	assert_int(_w.staff.staff_at(_b)).is_equal(first.id)


func test_closing_the_last_desk_warns_but_is_allowed() -> void:
	var closures := _w.staff.closures
	var seat: int = _w.sim.layout.seats[0]["object_id"]
	print(
		(
			"closable desk %s scanner %s seat %s"
			% [
				closures.is_closable(_a),
				closures.is_closable(_w.sim.layout.scanners[0]),
				closures.is_closable(seat)
			]
		)
	)
	assert_bool(closures.is_closable(_a)).is_true()
	assert_bool(closures.is_closable(_w.sim.layout.scanners[0])).is_true()
	assert_bool(closures.is_closable(seat)).is_false()
	assert_int(closures.station_of(seat)).is_equal(0)
	assert_int(closures.station_of(_a)).is_equal(_a)
	assert_bool(closures.would_strand(CHECKIN, _a)).is_false()
	assert_bool(closures.set_closed(_a, true)).is_true()
	assert_bool(closures.would_strand(CHECKIN, _b)).is_true()
	assert_bool(closures.would_strand(StaffMember.Role.SHOP, _b)).is_false()
	assert_bool(closures.set_closed(_b, true)).is_true()
	assert_array(closures.ids()).is_equal([_a, _b])
	assert_bool(closures.would_strand(CHECKIN)).is_true()
	assert_bool(closures.would_strand(StaffMember.Role.SECURITY)).is_false()


func test_a_closed_desk_shows_the_closed_by_you_sign() -> void:
	_seat(_a)
	_seat(_b)
	assert_array(MissSignals.closed_stations(_w.sim)).not_contains([_a])
	var changes := [0]
	_w.staff.staff_changed.connect(func() -> void: changes[0] += 1)
	_w.staff.closures.set_closed(_a, true)
	print(
		(
			"closed %s, reason '%s'"
			% [MissSignals.closed_stations(_w.sim), MissSignals.closed_reason(_w.sim, _a)]
		)
	)
	assert_int(changes[0]).is_equal(1)
	assert_array(MissSignals.closed_stations(_w.sim)).contains([_a])
	assert_str(MissSignals.closed_reason(_w.sim, _a)).is_equal("Closed by you")
	assert_str(MissSignals.closed_reason(_w.sim, _b)).is_equal("")
