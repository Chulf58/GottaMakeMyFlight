class_name TestQueueRippleGap
extends GdUnitTestSuite
## A member the gap rule lets set off (more than a place behind the one ahead,
## QueueRipple.may_step) walks to its place no further than the cell behind the
## member ahead (QueueRipple.target_index(); decision hold-line-rebuild-the-
## security-line-follows-where-people-sta, rule 1: advancing targets are given
## out front to back). Before, the walk went to the full place whatever the one
## ahead did: when the front left while two members were mid-walk, they
## halted one short of their moved-up places and waited on the rollers ahead,
## and a member three places back set off for the cell of the one ahead and
## stood on it (board c2336d77, found by queue_spacing_probe HOLDERS).

const ROLLER_MEMBERS := 12
## The members mid-walk when the front leaves, and the gap behind them: the
## member after them stands this many cells past its place.
const WALKERS := [8, 9]
const GAP_AFTER := 3
const RUN_TICKS := 600

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


## The next queue member of `desk` who pulls a roller; others drawn on the way
## are sent off.
func _roller_member(desk: int) -> Passenger:
	for attempt in 40:
		var p := HoldLineKit.member(_world, desk, 1)
		if QueueRipple.pulls_roller(p):
			return p
		_world.sim._leave_station(p)
		p.stage = Passenger.Stage.MADE
	fail("no passenger pulling a roller in 40 draws")
	return null


## Twelve roller members: the first eight on their places, two mid-walk onto
## theirs (one cell off), the rest GAP_AFTER cells past theirs.
func _queue_with_walkers(desk: int) -> Array[Passenger]:
	var line: Array = _world.sim.layout.line_of(desk)
	var members: Array[Passenger] = []
	for i in ROLLER_MEMBERS:
		var p := _roller_member(desk)
		if i in WALKERS:
			p.at = line[i + 1]
			var step: Array[Vector2i] = [line[i + 1], line[i]]
			p.set_path(step)
		elif i > WALKERS.back():
			p.at = line[i + GAP_AFTER]
		members.append(p)
	return members


func test_a_member_never_walks_onto_the_cell_of_the_one_ahead() -> void:
	_world = HoldLineKit.desk_hall()
	var desk: int = _world.sim.get_meta(&"desk")
	var members := _queue_with_walkers(desk)
	var line: Array = _world.sim.layout.line_of(desk)
	var shared := 0
	var first := -1
	var left := false
	for t in RUN_TICKS:
		_world.step()
		var q: Dictionary = _world.sim._queue(desk)
		if q["serving"] != 0:
			_world.passenger(q["serving"]).service_end = _world.sim.tick + HoldLineKit.LONG
		if not left:
			var front := members[0]
			_world.sim._leave_station(front)
			front.stage = Passenger.Stage.MADE
			left = true
		var cells := {}
		for m in members:
			if m.station != desk or m.is_moving():
				continue
			if cells.has(m.at):
				shared += 1
				if first < 0:
					first = t
			cells[m.at] = true
	print("frames with two members on one cell: %d (first at tick %d)" % [shared, first])
	assert_bool(left).is_true()
	assert_int(shared).is_equal(0)
	# Control: the queue moved up the whole way, onto the places behind the
	# front that left.
	var rest := _world.sim.queue_of(desk) + _world.sim.holding_of(desk)
	assert_int(rest.size()).is_equal(ROLLER_MEMBERS - 1)
	assert_bool(HoldLineKit.settled(_world, desk)).is_true()
	assert_that(_world.passenger(rest.back()).at).is_equal(line[ROLLER_MEMBERS - 2])
