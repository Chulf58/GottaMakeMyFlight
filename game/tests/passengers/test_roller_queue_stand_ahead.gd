class_name TestRollerQueueStandAhead
extends GdUnitTestSuite
## A desk or security queue walker that stops behind a member standing still on
## its own place stands its roller up at once, with no RollerPark.STILL_TICKS
## wait, so the stood roller is up before the follower closes in on its 1.0 m
## trail; one that stops behind a member still walking keeps the wait, so a
## step-up behind a moving line does not stand and tip at once (decision
## a-queue-passenger-who-stops-behind-a-standing-member-stands, board
## e7028790; QueueStandWait).

const ROLLER := SecurityLooks.Kind.ROLLER
const DESK_AT := Vector2i(3, 1)
const SCANNER_AT := Vector2i(8, 6)
const CELLS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)]
const RUN_LIMIT := 2500

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


## A passenger `id` standing on `at`, walking on to `to` when given.
static func _member(host: Host, id: int, at: Vector2i, to := Vector2i(-1, -1)) -> Passenger:
	var p := Passenger.new()
	p.id = id
	p.at = at
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


## The ticks of standing still `bag` is asked for its stand after, given `wait`
## (RollerPark.queue_stand()), or -1 for none within `still` ticks.
static func _asked_after(wait: int, still: int) -> int:
	var bag := _pulled()
	for t in still:
		RollerPark.queue_stand(bag, ROLLER, true, 100.0 + t, wait)
		if RollerPark.restamps(bag):
			return t
	return -1


func test_a_stop_behind_a_member_standing_on_its_place_stands_at_once() -> void:
	var host := Host.new()
	_member(host, 1, CELLS[0])
	var p := _member(host, 2, CELLS[1])
	var lane: Array[int] = [1, 2]
	var behind := QueueStandWait.behind_still(host, p, lane)
	var asked := _asked_after(0, RollerPark.STILL_TICKS)
	print(
		"behind a member standing on its place: behind_still %s, asked after %d" % [behind, asked]
	)
	assert_bool(behind).is_true()
	# Asked for on the first still tick, as QueueStandWait.ticks() gives it no wait.
	assert_int(asked).is_equal(0)


## A step-up of one place behind a member still walking: that member is not
## standing, so the wait stays and a stop shorter than STILL_TICKS asks for
## no stand.
func test_a_step_up_behind_a_moving_member_does_not_stand() -> void:
	var host := Host.new()
	_member(host, 1, CELLS[1], CELLS[0])
	var p := _member(host, 2, CELLS[2])
	var lane: Array[int] = [1, 2]
	var behind := QueueStandWait.behind_still(host, p, lane)
	var short_stop := _asked_after(RollerPark.STILL_TICKS, RollerPark.STILL_TICKS)
	var long_stop := _asked_after(RollerPark.STILL_TICKS, RollerPark.STILL_TICKS + 1)
	print(
		(
			"behind a moving member: behind_still %s, asked within %d still ticks %d, within %d %d"
			% [behind, RollerPark.STILL_TICKS, short_stop, RollerPark.STILL_TICKS + 1, long_stop]
		)
	)
	assert_bool(behind).is_false()
	assert_int(short_stop).is_equal(-1)
	# Control: the same record does stand once it has waited.
	assert_int(long_stop).is_equal(RollerPark.STILL_TICKS)


## The front has no member to stand behind and keeps the wait. A member
## standing short of its own place still counts as standing (QueueStandWait's
## header: requiring the place left more held-row overlap and no fewer short
## stands), and the same member walking on does not.
func test_the_front_keeps_the_wait_and_a_member_off_its_place_counts() -> void:
	var host := Host.new()
	var front := _member(host, 1, CELLS[1])
	var p := _member(host, 2, CELLS[2])
	var lane: Array[int] = [1, 2]
	var first := QueueStandWait.behind_still(host, front, lane)
	var off := QueueStandWait.behind_still(host, p, lane)
	var path: Array[Vector2i] = [CELLS[1], CELLS[0]]
	front.set_path(path)
	var walking := QueueStandWait.behind_still(host, p, lane)
	print("front %s, behind one off its place %s, behind it walking %s" % [first, off, walking])
	assert_bool(first).is_false()
	assert_bool(off).is_true()
	assert_bool(walking).is_false()


## In a real desk queue of walkers pulling rollers (the QueueRipple holds each
## behind a roller puller until its stand), every still member's wait is
## measured tick by tick: none behind a member standing on its place, the full
## STILL_TICKS behind one walking. Both are seen, so the test cannot pass on
## one kind of tick alone.
func test_still_wait_in_a_desk_queue_follows_the_member_ahead() -> void:
	_world = _desk_world()
	var desk: int = _world.sim.layout.desks[0]
	for i in 5:
		_send(_world, true)
		_world.run_to(_world.clock.tick + 3)
	var behind_standing := 0
	var behind_walking := 0
	var wrong: Array = []
	var stop := _world.clock.tick + RUN_LIMIT
	while _world.clock.tick < stop and (behind_standing < 20 or behind_walking < 20):
		_world.step()
		var sim := _world.sim
		var members := sim.queue_of(desk) + sim.holding_of(desk)
		var line := sim.layout.line_of(desk)
		for i in range(1, members.size()):
			var p := sim.get_passenger(members[i])
			var ahead := sim.get_passenger(members[i - 1])
			if p.is_moving() or p.stage != Passenger.Stage.CHECKIN_QUEUE:
				continue
			var wait := QueueStandWait.ticks(sim, p)
			if ahead.is_moving():
				behind_walking += 1
				if wait != RollerPark.STILL_TICKS:
					wrong.append([sim.tick, p.id, "ahead walking", wait])
			elif ahead.at == line[i - 1]:
				behind_standing += 1
				if wait != 0:
					wrong.append([sim.tick, p.id, "ahead standing", wait])
	print(
		(
			"still ticks behind a standing member %d, behind a walking member %d; wrong %s"
			% [behind_standing, behind_walking, wrong]
		)
	)
	assert_int(behind_standing).is_greater(0)
	assert_int(behind_walking).is_greater(0)
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
