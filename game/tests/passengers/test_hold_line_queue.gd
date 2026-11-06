class_name TestHoldLineQueue
extends GdUnitTestSuite
## Queue members on the line (decision full-queue-design-a-derived-hold-
## line-behind-each-lane-gives): each member stands on line[index], a walker
## joins when it reaches the next free line cell (same-tick arrivals by line
## index, then id), holders move up one cell under the QueueRipple rule, and
## a station whose line is full is not chosen.

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


## Ten walkers into the desk hall one after another, the first held in
## service: six fill the lane, four hold, each on its own cell.
func _ten_queued() -> Array[int]:
	_world = HoldLineKit.desk_hall()
	var desk: int = _world.sim.get_meta(&"desk")
	var ids: Array[int] = []
	for i in 10:
		var p := HoldLineKit.passenger(
			_world, HoldLineKit.HALL_DOOR + Vector2i(0, -1), Passenger.Stage.TO_CHECKIN, i % 3
		)
		ids.append(p.id)
		_world.run_to(_world.clock.tick + 14)
	var q: Dictionary = _world.sim._queue(desk)
	for i in 1200:
		if StationQueue.size_of(q) == ids.size() and HoldLineKit.settled(_world, desk):
			break
		_world.step()
		if q["serving"] != 0:
			_world.passenger(q["serving"]).service_end = _world.sim.tick + HoldLineKit.LONG
	assert_int(StationQueue.size_of(q)).is_equal(ids.size())
	assert_bool(HoldLineKit.settled(_world, desk)).is_true()
	return ids


func test_holders_stand_on_as_many_cells_as_there_are_holders() -> void:
	var ids := _ten_queued()
	var desk: int = _world.sim.get_meta(&"desk")
	var holding := _world.sim.holding_of(desk)
	var line: Array = _world.sim.layout.line_of(desk)
	var got: Array = HoldLineKit.standing_cells(_world, holding)
	print("holding %s on %s" % [holding, got[0]])
	assert_int(holding.size()).is_equal(4)
	assert_int((got[0] as Array).size()).is_equal(4)
	assert_int(got[1]).is_equal(0)
	for i in holding.size():
		assert_that(_world.passenger(holding[i]).at).is_equal(line[TerminalLayout.LANE_SLOTS + i])
	assert_array(_world.sim.queue_of(desk) + holding).is_equal(ids)


func test_a_full_line_is_not_chosen() -> void:
	_world = HoldLineKit.desk_hall()
	var desk: int = _world.sim.get_meta(&"desk")
	var line: Array = _world.sim.layout.line_of(desk)
	var members: Array[Passenger] = []
	for i in line.size():
		members.append(HoldLineKit.member(_world, desk))
	var late := HoldLineKit.passenger(_world, Vector2i(8, 15), Passenger.Stage.TO_CHECKIN)
	_world.run_to(_world.clock.tick + PassengerSim.BEAT_TICKS * 2)
	assert_int(line.size()).is_equal(18)
	assert_int(late.station).is_equal(0)
	assert_int(late.stuck).is_equal(Passenger.Stuck.QUEUE_FULL)
	assert_bool(late.is_moving()).is_false()
	# Control: a member leaves, and the waiter takes its place on its beat.
	var gone: Passenger = members.back()
	_world.sim._leave_station(gone)
	gone.stage = Passenger.Stage.TO_GATE
	_world.run_to(_world.clock.tick + PassengerSim.BEAT_TICKS + 1)
	assert_int(late.station).is_equal(desk)


## The case of queue_spacing_probe seed 3 (board de64b195): P chooses first
## and walks up the line from its back, Q chooses next and comes in from the
## side beside a place further back, which it reaches long before P reaches
## its own. Each joins on the free cell it reaches; nobody turns back.
func test_a_walker_overtaken_on_the_way_joins_in_cell_order_without_turning_back() -> void:
	_world = HoldLineKit.desk_hall()
	var desk: int = _world.sim.get_meta(&"desk")
	var line: Array = _world.sim.layout.line_of(desk)
	HoldLineKit.member(_world, desk)
	HoldLineKit.member(_world, desk)
	var p := HoldLineKit.passenger(_world, Vector2i(4, 20), Passenger.Stage.TO_CHECKIN)
	_world.step()
	assert_that(p.path_end()).is_equal(line[2])
	var q := HoldLineKit.passenger(_world, Vector2i(7, 5), Passenger.Stage.TO_CHECKIN)
	_world.step()
	assert_that(q.path_end()).is_equal(line[3])
	var walkers := {p.id: [p.at], q.id: [q.at]}
	for i in 400:
		_world.step()
		for w: Passenger in [p, q]:
			var cells: Array = walkers[w.id]
			if cells.back() != w.at:
				cells.append(w.at)
		if HoldLineKit.settled(_world, desk) and _world.sim.queue_of(desk).size() == 4:
			break
	print("cells walked: P %s, Q %s" % [walkers[p.id], walkers[q.id]])
	assert_bool(HoldLineKit.settled(_world, desk)).is_true()
	var lane := _world.sim.queue_of(desk)
	assert_int(lane.size()).is_equal(4)
	for w: Passenger in [p, q]:
		assert_that(w.at).is_equal(line[lane.find(w.id)])
		var cells: Array = walkers[w.id]
		for i in range(2, cells.size()):
			var was: Vector2i = cells[i - 1] - cells[i - 2]
			var now: Vector2i = cells[i] - cells[i - 1]
			if was == -now:
				fail("passenger %d turned back at %s: %s" % [w.id, cells[i - 1], cells])


func test_same_tick_arrivals_join_by_line_index_then_id() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(4, 4))
	var line: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)]
	var lanes := {1: line.slice(0, 2)}
	var lines := {1: line}
	var queues := {1: {"lane": [100], "holding": [], "serving": 0}}
	var front := Passenger.new()
	front.id = 100
	front.at = line[0]
	front.clear_path()
	# A (id 5) reaches line[2] and B (id 9) line[1] on this tick: B first.
	var a := _arriving(5, Vector2i(1, 2), Vector2i(0, 2))
	var b := _arriving(9, Vector2i(1, 1), Vector2i(0, 1))
	var by_id := {100: front, 5: a, 9: b}
	var joined := StationQueue.arrive(grid, queues, lanes, lines, [a, b], by_id, 7)
	assert_array(joined.map(func(w: Passenger) -> int: return w.id)).is_equal([9, 5])
	assert_array(queues[1]["lane"]).is_equal([100, 9])
	assert_array(queues[1]["holding"]).is_equal([5])
	for w: Passenger in [a, b]:
		assert_bool(w.is_moving()).is_false()
		assert_int(w.halt_tick).is_equal(7)
	assert_that(a.at).is_equal(Vector2i(0, 2))
	# Both reach line[1]: the lower id joins; the other turns back where it
	# is for line[2], the nearer way, never stepping onto the winner's cell.
	queues[1] = {"lane": [100], "holding": [], "serving": 0}
	var c := _arriving(5, Vector2i(1, 1), Vector2i(0, 1))
	var d := _arriving(9, Vector2i(0, 2), Vector2i(0, 1))
	by_id = {100: front, 5: c, 9: d}
	joined = StationQueue.arrive(grid, queues, lanes, lines, [d, c], by_id, 7)
	assert_array(joined.map(func(w: Passenger) -> int: return w.id)).is_equal([5])
	assert_array(queues[1]["lane"]).is_equal([100, 5])
	assert_bool(d.is_moving()).is_true()
	assert_that(d.path_end()).is_equal(Vector2i(0, 2))
	assert_vector(d.grid_position()).is_equal_approx(Vector2(0.5, 1.55), Vector2(0.001, 0.001))
	d.walk(950)
	assert_that(d.at).is_equal(Vector2i(0, 2))


## Moved for decision hold-line-rebuild-the-security-line-follows-where-
## people-sta: same-tick entries go by where each stands along the line, the
## walk still to go included, so one standing on the free cell is ahead of a
## lower id still stepping onto it (it was line index, then id).
func test_a_walker_standing_on_the_free_cell_beats_a_lower_id_stepping_onto_it() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(4, 4))
	var line: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)]
	var front := Passenger.new()
	front.id = 100
	front.at = line[0]
	front.clear_path()
	var standing := Passenger.new()
	standing.id = 9
	standing.station = 1
	standing.stage = Passenger.Stage.TO_CHECKIN
	standing.at = line[1]
	standing.clear_path()
	var reaching := _arriving(5, Vector2i(1, 1), Vector2i(0, 1))
	var queues := {1: {"lane": [100], "holding": [], "serving": 0}}
	var by_id := {100: front, 5: reaching, 9: standing}
	var joined := StationQueue.arrive(
		grid, queues, {1: line.slice(0, 2)}, {1: line}, [reaching, standing], by_id, 7
	)
	assert_array(joined.map(func(w: Passenger) -> int: return w.id)).is_equal([9])
	assert_array(queues[1]["lane"]).is_equal([100, 9])
	# The one stepping onto it loses the cell and turns back on its step, to
	# the cell it came from, off the line.
	assert_bool(reaching.is_moving()).is_true()
	assert_that(reaching.path_end()).is_equal(Vector2i(1, 1))
	for i in 20:
		reaching.walk(PassengerSim.WALK_MM)
	assert_bool(reaching.is_moving()).is_false()
	assert_bool(line.has(reaching.at)).is_false()
	assert_that(reaching.at).is_not_equal(standing.at)


## The last free cell of a full line: a lower id reaches it on the tick a
## higher id stands on it. Moved for decision hold-line-rebuild-the-security-
## line-follows-where-people-sta: the one standing there joins and the one
## stepping onto it turns back, and every passenger keeps a cell of its own
## over the ticks that follow (it was the lower id joining).
func test_a_mover_onto_the_last_cell_a_stander_holds_turns_back() -> void:
	_world = HoldLineKit.desk_hall()
	var desk: int = _world.sim.get_meta(&"desk")
	var line: Array = _world.sim.layout.line_of(desk)
	for i in line.size() - 1:
		HoldLineKit.member(_world, desk)
	var last: Vector2i = line[line.size() - 1]
	var mover := HoldLineKit.passenger(_world, last + Vector2i(1, 0), Passenger.Stage.TO_CHECKIN)
	var stander := HoldLineKit.passenger(_world, last, Passenger.Stage.TO_CHECKIN)
	var step: Array[Vector2i] = [mover.at, last]
	mover.set_path(step)
	mover.seg_mm = Passenger.STRAIGHT_MM - 50
	for w: Passenger in [mover, stander]:
		w.station = desk
	_world.sim._incoming[desk] = 2
	var shared := 0
	for i in 60:
		_world.step()
		var cells := {}
		for id in _world.sim.passenger_ids():
			var p := _world.passenger(id)
			if not p.is_moving():
				shared += int(cells.has(p.at))
				cells[p.at] = true
	print("stander at %s station %d, mover at %s" % [stander.at, stander.station, mover.at])
	assert_int(StationQueue.size_of(_world.sim._queue(desk))).is_equal(line.size())
	assert_bool(_world.sim.holding_of(desk).has(stander.id)).is_true()
	assert_that(stander.at).is_equal(last)
	assert_bool(line.has(mover.at)).is_false()
	assert_int(shared).is_equal(0)


## A walker passing over a member's cell with exactly one tick's walk left to
## its centre walks on past it: it never ends a tick on the centre.
func test_a_walker_passing_over_a_member_never_ends_a_tick_on_its_centre() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(4, 4))
	var line: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)]
	var by_id := {}
	for i in 2:
		var member := Passenger.new()
		member.id = 100 + i
		member.at = line[i]
		member.clear_path()
		by_id[member.id] = member
	var passer := Passenger.new()
	passer.id = 7
	passer.station = 1
	passer.stage = Passenger.Stage.TO_CHECKIN
	passer.at = Vector2i(1, 1)
	var path: Array[Vector2i] = [Vector2i(1, 1), line[1], line[2], line[3]]
	passer.set_path(path)
	passer.seg_mm = Passenger.STRAIGHT_MM - passer.pace_mm()
	by_id[7] = passer
	var queues := {1: {"lane": [100, 101], "holding": [], "serving": 0}}
	StationQueue.arrive(grid, queues, {1: line.slice(0, 2)}, {1: line}, [passer], by_id, 7)
	passer.walk(passer.pace_mm())
	print("passer at %s seg %d, %s" % [passer.at, passer.seg_mm, passer.grid_position()])
	assert_bool(passer.at == line[1] and passer.seg_mm == 0).is_false()
	assert_bool(passer.grid_position() == Vector2(0.5, 1.5)).is_false()
	assert_bool(passer.is_moving()).is_true()


## The case of the Sol review: a loser 1364 mm into a 1414 mm diagonal onto
## the cell a lower id takes on the same tick, the next free cell behind the
## winner. Walls west of (1, 1) and (1, 2) make the way back round by (1, 3)
## longer than on through the winner's cell. It turns back on its step and
## heads on from where it came, never nearer the winner than when it lost.
func test_a_same_tick_loser_turns_back_and_never_walks_through_the_winner() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(4, 4))
	var west := BuildGrid.SIDE_STEP.find(Vector2i(-1, 0))
	for cell in [Vector2i(1, 1), Vector2i(1, 2)]:
		assert_bool(grid.apply(BuildEdit.place_wall(cell, west)).ok).is_true()
	var line: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)]
	var front := Passenger.new()
	front.id = 100
	front.at = line[0]
	front.clear_path()
	var winner := _arriving(5, Vector2i(1, 1), Vector2i(0, 1))
	var loser := Passenger.new()
	loser.id = 9
	loser.station = 1
	loser.stage = Passenger.Stage.TO_CHECKIN
	loser.at = Vector2i(1, 2)
	var diagonal: Array[Vector2i] = [Vector2i(1, 2), Vector2i(0, 1)]
	loser.set_path(diagonal)
	loser.seg_mm = 1364
	var queues := {1: {"lane": [100], "holding": [], "serving": 0}}
	var by_id := {100: front, 5: winner, 9: loser}
	var lanes := {1: line.slice(0, 2)}
	var lines := {1: line}
	var before := loser.grid_position()
	var joined := StationQueue.arrive(grid, queues, lanes, lines, [winner, loser], by_id, 7)
	assert_array(joined.map(func(w: Passenger) -> int: return w.id)).is_equal([5])
	assert_vector(loser.grid_position()).is_equal_approx(before, Vector2(0.001, 0.001))
	var least := loser.grid_position().distance_to(winner.grid_position())
	var start := least
	for tick in range(8, 60):
		if (queues[1]["holding"] as Array).has(9):
			break
		# The line's pass sets a standing loser off for the tail itself (moved
		# for decision hold-line-rebuild-the-security-line-follows-where-people-sta).
		StationQueue.arrive(grid, queues, lanes, lines, [loser], by_id, tick)
		loser.walk(PassengerSim.WALK_MM)
		least = minf(least, loser.grid_position().distance_to(winner.grid_position()))
	print("loser to winner: at the loss %.3f m, least after %.3f m" % [start, least])
	assert_float(least).is_greater_equal(start)
	assert_array(queues[1]["holding"]).is_equal([9])
	# Moved for decision hold-line-rebuild-the-security-line-follows-where-
	# people-sta: it enters where it steps onto the line behind the winner,
	# coming round by line[3] to face the front, and moves up from there.
	assert_int(line.find(loser.at)).is_between(2, 3)


## A walker of station 1 on `from`, 950 mm into the step to `to`: it reaches
## `to` this tick at a walk.
static func _arriving(id: int, from: Vector2i, to: Vector2i) -> Passenger:
	var w := Passenger.new()
	w.id = id
	w.station = 1
	w.stage = Passenger.Stage.TO_CHECKIN
	w.at = from
	var path: Array[Vector2i] = [from, to]
	w.set_path(path)
	w.seg_mm = Passenger.segment_mm(from, to) - 50
	return w


func test_holders_move_up_one_cell_each_under_the_ripple_rule() -> void:
	_ten_queued()
	var desk: int = _world.sim.get_meta(&"desk")
	var line: Array = _world.sim.layout.line_of(desk)
	var members := _world.sim.queue_of(desk) + _world.sim.holding_of(desk)
	var front := _world.passenger(members[0])
	front.service_end = _world.sim.tick
	var set_off := {}
	var stood := {}
	for i in 600:
		_world.step()
		for id: int in members.slice(1):
			var w := _world.passenger(id)
			if w.is_moving() and not set_off.has(id):
				set_off[id] = _world.sim.tick
			if set_off.has(id) and not w.is_moving() and not stood.has(id):
				stood[id] = w.halt_tick
		if stood.size() == members.size() - 1:
			break
	var rollers := 0
	for k in range(1, members.size()):
		var w := _world.passenger(members[k])
		assert_that(w.at).is_equal(line[k - 1])
		if k == 1:
			continue
		var ahead := _world.passenger(members[k - 1])
		if QueueRipple.pulls_roller(ahead):
			rollers += 1
			assert_int(int(set_off[w.id]) - int(stood[ahead.id])).is_greater_equal(
				QueueRipple.STAND_TICKS
			)
	print("set off %s stood %s rollers ahead %d" % [set_off, stood, rollers])
	assert_int(rollers).is_greater(0)
	assert_int(_world.sim.holding_of(desk).size()).is_equal(3)
