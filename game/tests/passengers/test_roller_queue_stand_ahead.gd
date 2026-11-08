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

## Which wait the follower in _front_leaves_run() gets: the rule as built, the
## rule before the front-leaves case (stuck, else STILL_TICKS) or plain
## STILL_TICKS (main before the queue stand wait).
enum Rule { BUILT, BEFORE, PLAIN }

const ROLLER := SecurityLooks.Kind.ROLLER
const DESK_AT := Vector2i(3, 1)
const SCANNER_AT := Vector2i(8, 6)
const CELLS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)]
const RUN_LIMIT := 2500
## Ticks a one-cell step takes in the ripple regression (a walk is 7 to 10).
const STEP_TICKS := 7
## A stand tipped within this many ticks of being upright was a stand for
## nothing (queue_spacing_probe's SHORT_STOOD).
const SHORT_STOOD := 4.0

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


## A desk lane [front, A, B] (Sol re-check of 24ac8fe, board e6b4e303): the
## front is served until tick `ends`, A has no roller, B pulls one and stopped
## on its place at tick `stop`, with A on its place. Played tick by tick: B's
## roller record (RollerPark.queue_stand() with the wait `rule` gives, as
## CarryOnProps.sync() calls it), then the sim tick: the front leaves the lane
## on `ends` and the ripple (QueueRipple) sets A and B off one place up, each
## walk taking STEP_TICKS. Returns {"asked": tick of B's stand or -1, "tip":
## the ticks into its stand move that B's tip was marked, or -1}.
static func _front_leaves_run(stop: int, ends: int, rule: Rule) -> Dictionary:
	var host := Host.new()
	var front := _member(host, 1, CELLS[0])
	front.stage = Passenger.Stage.CHECKIN
	front.service_end = ends
	var a := _member(host, 2, CELLS[1])
	var b := _member(host, 3, CELLS[2])
	var lane: Array[int] = [1, 2, 3]
	var bag := _pulled()
	var set_off := {}
	var asked := -1
	for t in range(stop, ends + STEP_TICKS * 2 + 4):
		var wait := RollerPark.STILL_TICKS
		match rule:
			Rule.BUILT:
				var leaving := QueueStandWait.desk_front_leaves(host, lane, t)
				wait = QueueStandWait.line_wait(host, b, lane, CELLS, leaving, true)
			Rule.BEFORE:
				wait = QueueStandWait.line_wait(host, b, lane, CELLS)
		RollerPark.queue_stand(bag, ROLLER, not b.is_moving(), float(t), wait)
		if RollerPark.restamps(bag):
			if asked < 0:
				asked = t
			_stamped(bag)
		if bag.has("queue_tip"):
			return {"asked": asked, "tip": float(bag["queue_tip"])}
		if lane.has(1) and t + 1 >= ends:
			lane.erase(1)
			front.stage = Passenger.Stage.TO_SECURITY
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
	return {"asked": asked, "tip": -1.0}


## Whether the run `stood` began a stand that tipped within SHORT_STOOD ticks
## of being upright.
static func _tipped_soon(stood: Dictionary) -> bool:
	return float(stood["tip"]) >= 0.0 and stood["tip"] < RollerPark.QUEUE_STAND_TICKS + SHORT_STOOD


## B stops two ticks before the front's service ends and would have got wait 0
## (stuck behind A): its stand must not start, so it does not tip within
## SHORT_STOOD ticks of standing when the front leaves and the places move up.
## Control: with the front's service ending later, B stands at once and its
## tip, once it walks on, comes after the stand.
func test_a_stop_just_before_the_front_leaves_starts_no_stand_that_tips() -> void:
	var ends := 130
	var near := _front_leaves_run(ends - 2, ends, Rule.BUILT)
	var before := _front_leaves_run(ends - 2, ends, Rule.BEFORE)
	var far := _front_leaves_run(ends - 12, ends, Rule.BUILT)
	print("stop 2 before: built %s, before %s; stop 12 before: built %s" % [near, before, far])
	# B's stand is asked for only once it has stepped up and stopped again.
	assert_bool(_tipped_soon(near)).is_false()
	assert_int(near["asked"]).is_greater_equal(ends + STEP_TICKS)
	# Control: the rule before this case stood it there, and it tipped soon.
	assert_bool(_tipped_soon(before)).is_true()
	assert_int(far["asked"]).is_equal(ends - 12)
	assert_bool(_tipped_soon(far)).is_false()


## Every stop tick from long before the front leaves to the tick it does: the
## built rule tips soon on no tick where plain STILL_TICKS (main) does not.
func test_no_stop_tips_more_than_main_before_the_front_leaves() -> void:
	var ends := 130
	var worse: Array = []
	var before_tips := 0
	for stop in range(ends - 16, ends):
		var built := _front_leaves_run(stop, ends, Rule.BUILT)
		var plain := _front_leaves_run(stop, ends, Rule.PLAIN)
		if _tipped_soon(built) and not _tipped_soon(plain):
			worse.append(stop)
		if _tipped_soon(_front_leaves_run(stop, ends, Rule.BEFORE)):
			before_tips += 1
	print("stops tipping more than main %s; tips before this case %d" % [worse, before_tips])
	assert_array(worse).is_empty()
	assert_int(before_tips).is_greater(0)


## desk_front_leaves(): a served front whose service ends within STILL_TICKS.
func test_desk_front_leaves_within_the_still_ticks_of_its_service_end() -> void:
	var host := Host.new()
	var front := _member(host, 1, CELLS[0])
	var lane: Array[int] = [1, 2]
	var queued := QueueStandWait.desk_front_leaves(host, lane, 100)
	front.stage = Passenger.Stage.CHECKIN
	front.service_end = 100 + RollerPark.STILL_TICKS
	var at_window := QueueStandWait.desk_front_leaves(host, lane, 100)
	front.service_end += 1
	var before_window := QueueStandWait.desk_front_leaves(host, lane, 100)
	front.service_end = 90
	var overdue := QueueStandWait.desk_front_leaves(host, lane, 100)
	var none := QueueStandWait.desk_front_leaves(host, [], 100)
	print(
		(
			"queued %s, at window %s, before it %s, overdue %s, empty %s"
			% [queued, at_window, before_window, overdue, none]
		)
	)
	assert_bool(queued).is_false()
	assert_bool(at_window).is_true()
	assert_bool(before_window).is_false()
	assert_bool(overdue).is_true()
	assert_bool(none).is_false()


## Steps the security world `w` until security_front_leaves() says the front
## leaves, at most RUN_LIMIT ticks; returns whether it did.
func _until_front_leaves(w: PassengerTestWorld) -> bool:
	var sim := w.sim
	var scanner: int = sim.layout.scanners[0]
	var stop := w.clock.tick + RUN_LIMIT
	while w.clock.tick < stop:
		w.step()
		var members := sim.queue_of(scanner) + sim.holding_of(scanner)
		if QueueStandWait.security_front_leaves(sim, scanner, members, sim.layout.line_of(scanner)):
			return true
	return false


## security_front_leaves() in a real world: every front it says leaves is out
## of the queue within STILL_TICKS ticks (admitted into the scanner), checked
## for DISTINCT fronts until each deadline has passed: a front still queued on
## its deadline tick is wrong. Five different fronts are seen, so the check
## cannot pass on an empty set or on one front said again and again.
func test_security_front_leaves_is_followed_by_its_admission() -> void:
	var fronts_wanted := 5
	_world = _desk_world()
	for i in 6:
		_send(_world, false, Passenger.Stage.TO_SECURITY)
		_world.run_to(_world.clock.tick + 3)
	var said := {}
	var longest := 0
	var left := 0
	var wrong: Array = []
	var due := {}
	var sim := _world.sim
	var scanner: int = sim.layout.scanners[0]
	var stop := _world.clock.tick + RUN_LIMIT
	while _world.clock.tick < stop and (said.size() < fronts_wanted or not due.is_empty()):
		_world.step()
		var members := sim.queue_of(scanner) + sim.holding_of(scanner)
		longest = maxi(longest, members.size())
		for id: int in due.keys():
			if not members.has(id):
				left += 1
				due.erase(id)
			elif sim.tick >= due[id]:
				wrong.append([sim.tick, id, "still queued"])
				due.erase(id)
		if said.size() >= fronts_wanted or members.is_empty() or said.has(members[0]):
			continue
		if QueueStandWait.security_front_leaves(sim, scanner, members, sim.layout.line_of(scanner)):
			said[members[0]] = sim.tick
			due[members[0]] = sim.tick + RollerPark.STILL_TICKS
	print(
		(
			(
				"security front leaves said for %d fronts, %d left in time, %d unchecked; "
				+ "longest queue %d; wrong %s"
			)
			% [said.size(), left, due.size(), longest, wrong]
		)
	)
	# Control: fronts did wait in a queue behind the one being scanned.
	assert_int(longest).is_greater(2)
	assert_int(said.size()).is_equal(fronts_wanted)
	assert_int(left).is_equal(fronts_wanted)
	assert_array(wrong).is_empty()
	assert_int(due.size()).is_equal(0)


## No cell in the line (a paused edit can leave a scanner in the passages with
## an empty rebuilt line), or a station that is not one: false, no error.
func test_security_front_leaves_is_false_without_a_line_or_a_station() -> void:
	_world = _desk_world()
	for i in 6:
		_send(_world, false, Passenger.Stage.TO_SECURITY)
		_world.run_to(_world.clock.tick + 3)
	assert_bool(_until_front_leaves(_world)).is_true()
	var sim := _world.sim
	var scanner: int = sim.layout.scanners[0]
	var members := sim.queue_of(scanner) + sim.holding_of(scanner)
	var line := sim.layout.line_of(scanner)
	var no_cells: Array[Vector2i] = []
	var empty := QueueStandWait.security_front_leaves(sim, scanner, members, no_cells)
	var no_station := QueueStandWait.security_front_leaves(sim, -1, members, line)
	var control := QueueStandWait.security_front_leaves(sim, scanner, members, line)
	print("empty line %s, no station %s, control %s" % [empty, no_station, control])
	assert_bool(control).is_true()
	assert_bool(empty).is_false()
	assert_bool(no_station).is_false()


## A front stuck GATE_FULL is not admitted, so the places do not move up: the
## prediction is false, and a member stuck behind a standing member keeps wait
## 0 (control: the front is ready on its first cell and the main position is
## free, so only the gate stops it).
func test_a_gate_full_front_does_not_leave_so_the_follower_stands_at_once() -> void:
	var gate := GateFullWorld.make()
	var sim := gate.world.sim
	sim.standing.rebuild(sim)
	gate.send_many(GateFullWorld.SPOTS + 4)
	var full := func() -> bool:
		var front := gate.front()
		return front != null and front.stuck == Passenger.Stuck.GATE_FULL
	assert_bool(gate.run_until(full)).is_true()
	gate.world.run_to(gate.world.clock.tick + 60)
	var members := sim.queue_of(gate.station) + sim.holding_of(gate.station)
	var line := sim.layout.line_of(gate.station)
	var follower := gate.world.passenger(members[2])
	var ready := sim.security.ready_front(gate.station, {"lane": members}, line, true)
	var main: int = sim.security.record_of(gate.station).get("main", 0)
	var leaves := QueueStandWait.security_front_leaves(sim, gate.station, members, line)
	var stuck := QueueStandWait.stuck(sim, follower, members, line)
	var wait := QueueStandWait.ticks(sim, follower)
	print(
		(
			"front %d stuck %d, ready %s, main %d, leaves %s; follower %d stuck %s wait %d"
			% [
				members[0],
				gate.front().stuck,
				ready != null,
				main,
				leaves,
				follower.id,
				stuck,
				wait
			]
		)
	)
	assert_bool(ready != null).is_true()
	assert_int(main).is_equal(0)
	assert_bool(leaves).is_false()
	assert_bool(stuck).is_true()
	assert_int(wait).is_equal(0)
	gate.world.free_all()


## A desk front pulling a roller walks FRONT_CLEAR_MM away before the new front
## steps onto the desk cell (QueueRipple.desk_clear()), so the walkers behind
## are held and B stands at once; a front with no roller holds nobody, and a
## security front's roller never holds anybody.
func test_a_desk_front_pulling_a_roller_holds_the_places_so_the_follower_stands() -> void:
	var host := Host.new()
	var front := _member(host, 1, CELLS[0])
	front.carry_on = 1
	front.id = _roller_id()
	host.by_id.erase(1)
	host.by_id[front.id] = front
	front.stage = Passenger.Stage.CHECKIN
	front.service_end = 102
	var a := _member(host, 2, CELLS[1])
	var b := _member(host, 3, CELLS[2])
	var lane: Array[int] = [front.id, a.id, b.id]
	var roller_desk := QueueStandWait.line_wait(host, b, lane, CELLS, true, true)
	var roller_security := QueueStandWait.line_wait(host, b, lane, CELLS, true, false)
	front.carry_on = 0
	var plain_desk := QueueStandWait.line_wait(host, b, lane, CELLS, true, true)
	print(
		(
			"front pulls a roller: desk wait %d, security wait %d; plain front: desk wait %d"
			% [roller_desk, roller_security, plain_desk]
		)
	)
	assert_bool(QueueRipple.pulls_roller(front)).is_false()
	assert_int(roller_desk).is_equal(0)
	assert_int(roller_security).is_equal(RollerPark.STILL_TICKS)
	assert_int(plain_desk).is_equal(RollerPark.STILL_TICKS)


## A passenger id whose one carry-on is a roller (SecurityLooks.bag_kind()).
static func _roller_id() -> int:
	var p := Passenger.new()
	p.carry_on = 1
	for id in range(10, 500):
		p.id = id
		if QueueRipple.pulls_roller(p):
			return id
	return 0


## In a real desk queue of walkers pulling rollers (the QueueRipple holds each
## behind a roller puller until its stand), every still member's wait is
## measured tick by tick: none when it stands on its place behind a member on
## its own, the full STILL_TICKS otherwise, and also while the desk's front
## leaves within STILL_TICKS. All three are seen, so the test cannot pass on
## one kind of tick alone.
func test_still_wait_in_a_desk_queue_follows_the_member_ahead() -> void:
	_world = _desk_world()
	var desk: int = _world.sim.layout.desks[0]
	for i in 5:
		_send(_world, i >= 2)
		_world.run_to(_world.clock.tick + 3)
	var stuck_ticks := 0
	var other_ticks := 0
	var leaving_ticks := 0
	var wrong: Array = []
	var stop := _world.clock.tick + RUN_LIMIT
	while _world.clock.tick < stop and (stuck_ticks < 20 or other_ticks < 20 or leaving_ticks < 5):
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
			var leaving := (
				QueueStandWait.desk_front_leaves(sim, members, sim.tick)
				and QueueStandWait.steps_at_once(sim, p, members, true)
			)
			if p.at == line[i] and not ahead.is_moving() and ahead.at == line[i - 1]:
				if leaving:
					leaving_ticks += 1
					if wait != RollerPark.STILL_TICKS:
						wrong.append([sim.tick, p.id, "stuck, front leaving", wait])
					continue
				stuck_ticks += 1
				if wait != 0:
					wrong.append([sim.tick, p.id, "stuck", wait])
			else:
				other_ticks += 1
				if wait != RollerPark.STILL_TICKS:
					wrong.append([sim.tick, p.id, "not stuck", wait])
	print(
		(
			"still ticks stuck %d, front leaving %d, not stuck %d; wrong %s"
			% [stuck_ticks, leaving_ticks, other_ticks, wrong]
		)
	)
	assert_int(stuck_ticks).is_greater(0)
	assert_int(leaving_ticks).is_greater(0)
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
func _send(w: PassengerTestWorld, roller: bool, stage := Passenger.Stage.TO_CHECKIN) -> int:
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
		p.stage = stage
		p.clear_path()
		return id
	return 0


static func _roller(p: Passenger) -> bool:
	for i in p.carry_on:
		if SecurityLooks.bag_kind(p, i) == ROLLER:
			return true
	return false
