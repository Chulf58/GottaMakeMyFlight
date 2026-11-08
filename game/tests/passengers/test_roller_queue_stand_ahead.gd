class_name TestRollerQueueStandAhead
extends GdUnitTestSuite
## A desk or security queue walker that is stuck (on its own place, behind a
## member standing still on its own place) stands its roller up at once, with
## no RollerPark.STILL_TICKS wait, so the stood roller is up before the
## follower closes in on its 1.0 m trail. Every other stop keeps the wait: one
## behind a member still walking, or behind a member standing short of its
## place that steps on the next tick (QueueRipple), does not stand and tip at
## once (decision a-queue-passenger-who-stops-behind-a-standing-member-stands,
## board e7028790; QueueStandWait).

const ROLLER := SecurityLooks.Kind.ROLLER
const DESK_AT := Vector2i(3, 1)
const SCANNER_AT := Vector2i(8, 6)
const CELLS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)]
const RUN_LIMIT := 2500
## Ticks a one-cell step takes in the ripple regression (a walk is 7 to 10).
const STEP_TICKS := 7

var _world: PassengerTestWorld


## A host of passengers by id, as PassengerSim has them (get_passenger()).
class Host:
	var by_id := {}

	func get_passenger(id: int) -> Passenger:
		return by_id.get(id)


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
	_world = null


## A passenger `id` with no bags standing on `at`, walking on to `to` when given.
static func _member(host: Host, id: int, at: Vector2i, to := Vector2i(-1, -1)) -> Passenger:
	var p := Passenger.new()
	p.id = id
	p.at = at
	p.carry_on = 0
	p.clear_path()
	if to.x >= 0:
		var path: Array[Vector2i] = [at, to]
		p.set_path(path)
	host.by_id[id] = p
	return p


## A roller's record settled in the right hand's pull since tick 0
## (test_roller_queue_stand's _pulled()).
static func _pulled() -> Dictionary:
	var place := (SecurityLooks.Home.HAND * 2 + 0) * 2
	return {
		"kind": ROLLER,
		"place": place,
		"home": place,
		"carry": SecurityLooks.Carry.PULL,
		"settled": true,
		"since": 0.0,
		"changed": 0.0,
	}


## `bag` stamped as CarryOnProps stamps the move it asked for at `now`
## (test_roller_queue_stand's _stamped()).
static func _stamped(bag: Dictionary) -> void:
	bag["led"] = true
	bag["was"] = bag["home"]
	bag["carry_from"] = SecurityLooks.Carry.PULL
	bag["since"] = bag["changed"]
	CarryLead.stamp_move(bag, false, SecurityLooks.Home.HAND, Transform3D.IDENTITY)


## The ticks of standing still `bag` is asked for its stand after, given `wait`
## (RollerPark.queue_stand()), or -1 for none within `still` ticks.
static func _asked_after(wait: int, still: int) -> int:
	var bag := _pulled()
	for t in still:
		RollerPark.queue_stand(bag, ROLLER, true, 100.0 + t, wait)
		if RollerPark.restamps(bag):
			return t
	return -1


func test_a_stuck_stop_stands_at_once() -> void:
	var host := Host.new()
	_member(host, 1, CELLS[0])
	var p := _member(host, 2, CELLS[1])
	var lane: Array[int] = [1, 2]
	var wait := QueueStandWait.line_wait(host, p, lane, CELLS)
	var asked := _asked_after(wait, RollerPark.STILL_TICKS)
	print("on its place behind one on its place: wait %d, asked after %d" % [wait, asked])
	assert_int(wait).is_equal(0)
	# Asked for on the first still tick.
	assert_int(asked).is_equal(0)


## A step-up of one place behind a member still walking: not stuck, so the
## wait stays and a stop shorter than STILL_TICKS asks for no stand.
func test_a_step_up_behind_a_moving_member_does_not_stand() -> void:
	var host := Host.new()
	_member(host, 1, CELLS[1], CELLS[0])
	var p := _member(host, 2, CELLS[2])
	var lane: Array[int] = [1, 2]
	var wait := QueueStandWait.line_wait(host, p, lane, CELLS)
	var short_stop := _asked_after(wait, RollerPark.STILL_TICKS)
	var long_stop := _asked_after(wait, RollerPark.STILL_TICKS + 1)
	print(
		(
			"behind a moving member: wait %d, asked within %d still ticks %d, within %d %d"
			% [wait, RollerPark.STILL_TICKS, short_stop, RollerPark.STILL_TICKS + 1, long_stop]
		)
	)
	assert_int(wait).is_equal(RollerPark.STILL_TICKS)
	assert_int(short_stop).is_equal(-1)
	# Control: the same record does stand once it has waited.
	assert_int(long_stop).is_equal(RollerPark.STILL_TICKS)


## The front has no member ahead; a member short of its own place, or one
## standing on its place behind a member short of its, is not stuck.
func test_the_front_and_a_stop_short_of_a_place_keep_the_wait() -> void:
	var host := Host.new()
	var front := _member(host, 1, CELLS[1])
	var p := _member(host, 2, CELLS[2])
	var lane: Array[int] = [1, 2]
	var first := QueueStandWait.line_wait(host, front, lane, CELLS)
	var both_short := QueueStandWait.line_wait(host, p, lane, CELLS)
	p.at = CELLS[1]
	p.clear_path()
	front.at = CELLS[0]
	front.clear_path()
	var both_on := QueueStandWait.line_wait(host, p, lane, CELLS)
	p.at = CELLS[2]
	p.clear_path()
	var self_short := QueueStandWait.line_wait(host, p, lane, CELLS)
	print(
		(
			"front %d, both short %d, both on their places %d, follower short %d"
			% [first, both_short, both_on, self_short]
		)
	)
	assert_int(first).is_equal(RollerPark.STILL_TICKS)
	assert_int(both_short).is_equal(RollerPark.STILL_TICKS)
	assert_int(both_on).is_equal(0)
	assert_int(self_short).is_equal(RollerPark.STILL_TICKS)


## Sol review of 8cf51a0: a security lane [A, B] where both stopped a cell short
## of their places, A with no roller and B pulling one. Played tick by tick: B's
## roller record (RollerPark.queue_stand() with QueueStandWait's wait, as
## CarryOnProps.sync() calls it, a stand asked for stamped as CarryOnProps
## stamps it), then the ripple (QueueRipple.may_step(), target_index()) sets A
## and B off, each walk taking STEP_TICKS. B must ask for no stand before it
## has stepped up, and no tip may start; once both stand on their places it is
## stuck and asks at once (control).
func test_a_follower_short_of_its_place_behind_a_member_about_to_step_waits() -> void:
	var host := Host.new()
	var a := _member(host, 1, CELLS[1])
	var b := _member(host, 2, CELLS[2])
	var lane: Array[int] = [1, 2]
	var bag := _pulled()
	var set_off := {}
	var early: Array = []
	var asked_on := -1
	for t in range(100, 100 + STEP_TICKS * 2 + 4):
		var now := float(t)
		# The view's sync on this tick.
		RollerPark.queue_stand(
			bag, ROLLER, not b.is_moving(), now, QueueStandWait.line_wait(host, b, lane, CELLS)
		)
		if RollerPark.restamps(bag):
			if b.at != CELLS[1]:
				early.append([t, "stand asked at %s" % b.at])
			if asked_on < 0:
				asked_on = t
			_stamped(bag)
		if bag.has("queue_tip"):
			early.append([t, "tip"])
		# The next sim tick: arrivals, then the ripple sets members off.
		for m: Passenger in [a, b]:
			if m.is_moving() and t + 1 - int(set_off[m.id]) >= STEP_TICKS:
				m.at = m.path_end()
				m.clear_path()
		for i in lane.size():
			var m: Passenger = host.get_passenger(lane[i])
			if m.is_moving() or not QueueRipple.may_step(host, m, lane, CELLS, t + 1, false):
				continue
			var target := QueueRipple.target_index(host, lane, CELLS, i)
			if m.at != CELLS[target]:
				var path: Array[Vector2i] = [m.at, CELLS[target]]
				m.set_path(path)
				set_off[m.id] = t + 1
	print(
		(
			"B set off at %s, at %s; stand asked on tick %d; early %s"
			% [set_off.get(2, -1), b.at, asked_on, early]
		)
	)
	assert_int(int(set_off.get(2, -1))).is_equal(101)
	assert_that(b.at).is_equal(CELLS[1])
	assert_array(early).is_empty()
	# Control: stuck once both stand on their places, it asks on that tick.
	assert_int(asked_on).is_equal(101 + STEP_TICKS)


## In a real desk queue of walkers pulling rollers (the QueueRipple holds each
## behind a roller puller until its stand), every still member's wait is
## measured tick by tick: none when it stands on its place behind a member on
## its own, the full STILL_TICKS otherwise. Both are seen, so the test cannot
## pass on one kind of tick alone.
func test_still_wait_in_a_desk_queue_follows_the_member_ahead() -> void:
	_world = _desk_world()
	var desk: int = _world.sim.layout.desks[0]
	for i in 5:
		_send(_world, true)
		_world.run_to(_world.clock.tick + 3)
	var stuck_ticks := 0
	var other_ticks := 0
	var wrong: Array = []
	var stop := _world.clock.tick + RUN_LIMIT
	while _world.clock.tick < stop and (stuck_ticks < 20 or other_ticks < 20):
		_world.step()
		var sim := _world.sim
		var members := sim.queue_of(desk) + sim.holding_of(desk)
		var line := sim.layout.line_of(desk)
		for i in range(1, mini(members.size(), line.size())):
			var p := sim.get_passenger(members[i])
			var ahead := sim.get_passenger(members[i - 1])
			if p.is_moving() or p.stage != Passenger.Stage.CHECKIN_QUEUE:
				continue
			var wait := QueueStandWait.ticks(sim, p)
			if p.at == line[i] and not ahead.is_moving() and ahead.at == line[i - 1]:
				stuck_ticks += 1
				if wait != 0:
					wrong.append([sim.tick, p.id, "stuck", wait])
			else:
				other_ticks += 1
				if wait != RollerPark.STILL_TICKS:
					wrong.append([sim.tick, p.id, "not stuck", wait])
	print("still ticks stuck %d, not stuck %d; wrong %s" % [stuck_ticks, other_ticks, wrong])
	assert_int(stuck_ticks).is_greater(0)
	assert_int(other_ticks).is_greater(0)
	assert_array(wrong).is_empty()


## One desk with its lane, a scanner past it and the doors (test_queue_ripple).
func _desk_world() -> PassengerTestWorld:
	var grid := PassengerTestWorld.floored(Vector2i(12, 16))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(5, 15), 2)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(8, 0), 0)
	PassengerTestWorld.place(grid, &"checkin_desk", DESK_AT, 0)
	PassengerTestWorld.place(grid, &"security_scanner", SCANNER_AT, 0)
	return PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(3000, 6000))


## Spawns a calm passenger walking in to check in with one bag, a roller when
## `roller` (test_queue_ripple's _send()). Returns its id.
func _send(w: PassengerTestWorld, roller: bool) -> int:
	for attempt in 50:
		var id := w.sim.spawn_now(PassengerTestWorld.FLIGHT)
		var p := w.passenger(id)
		p.carry_on = 1
		if _roller(p) != roller:
			p.carry_on = 0
			p.stage = Passenger.Stage.MADE
			continue
		p.hunger = 0
		p.liquids = false
		p.alarm = false
		p.apron = []
		p.apron_mm = 0
		p.stage = Passenger.Stage.TO_CHECKIN
		p.clear_path()
		return id
	return 0


static func _roller(p: Passenger) -> bool:
	for i in p.carry_on:
		if SecurityLooks.bag_kind(p, i) == ROLLER:
			return true
	return false
