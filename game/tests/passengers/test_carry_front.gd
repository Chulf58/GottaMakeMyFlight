class_name TestCarryFront
extends GdUnitTestSuite
## The front carry (decision in-a-cell-closed-on-both-sides-a-passenger-
## carries-their-bag): a passenger carries its bag in front of the body while
## the cell it stands on, or the next cell it walks into, is closed on both
## flanks, and goes back to the side carry once there is room; the arm turns
## between the two over CarryOnProps.TRANSFER_TICKS of sim time with the bag
## in its hand.
##
## The world is SecurityTestWorld's lane (arch on (5, 6), RIGHT) with a wall
## on the west edge of the return route's first cell (4, 6), so that cell is
## closed by the arch on one side and the wall on the other, as when a lane
## stands against a wall.

const CORRIDOR := Vector2i(4, 6)

var _worlds: Array[SecurityTestWorld] = []
var _views: Array[PassengerViews] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for v in _views:
		v.free()
	_views.clear()
	for w in _worlds:
		w.world.free_all()
	_worlds.clear()


func _make() -> SecurityTestWorld:
	var w := SecurityTestWorld.make(true)
	_worlds.append(w)
	var wall := BuildEdit.place_wall(CORRIDOR, BuildGrid.Side.WEST)
	assert_bool(w.world.sim.grid.apply(wall).ok).is_true()
	var views := PassengerViews.new()
	views.clock = w.world.clock
	views.sim = w.world.sim
	add_child(views)
	_views.append(views)
	return w


## A passenger standing in or walking into a cell closed on both flanks
## carries in front; a cell with one open flank does not count.
func test_a_cell_closed_on_both_flanks_means_a_front_carry() -> void:
	var w := _make()
	var sim := w.world.sim
	var lane := sim.layout.security_lanes.lane(w.station)
	assert_bool(sim.layout.security_lanes.is_complete(w.station)).is_true()
	var p := Passenger.new()
	p.carry_on = 1
	var route: Array[Vector2i] = [lane["berth"], CORRIDOR, CORRIDOR + Vector2i(0, 1)]
	p.at = route[0]
	p.set_path(route)
	# On the berth, walking into the corridor: the next cell is closed.
	assert_bool(SecurityLooks.carry_front(sim, p)).is_true()
	# In the corridor.
	p.path_index = 1
	p.at = route[1]
	assert_bool(SecurityLooks.carry_front(sim, p)).is_true()
	# Arrived on the route's end: open to the west.
	p.path_index = 2
	p.at = route[2]
	assert_bool(SecurityLooks.carry_front(sim, p)).is_false()
	# Control: without the wall the corridor cell is open on one side.
	sim.grid.apply(BuildEdit.remove_wall(CORRIDOR, BuildGrid.Side.WEST))
	p.path_index = 1
	p.at = route[1]
	assert_bool(SecurityLooks.carry_front(sim, p)).is_false()


## An alarm passenger walking back carries in front from the berth into the
## corridor and back at the side on the route's end; each turn takes
## TRANSFER_TICKS ticks, halfway after half of them.
func test_the_walk_back_switches_to_the_front_and_back_on_sim_time() -> void:
	var w := _make()
	var views := _views[-1]
	var props := views.carry_on_props()
	var ids := w.send_all([[1, false, true]])
	var p := w.world.passenger(ids[0])
	var sim := w.world.sim
	var front_cells := {}
	var switches: Array = []
	var was_front := false
	var halfway: Array[float] = []
	for i in 3000:
		w.world.step()
		views.draw()
		var front := SecurityLooks.carry_front(sim, p)
		var carried := SecurityLooks.bag_homes(sim, p) == [SecurityLooks.Home.HAND]
		if p.stage == Passenger.Stage.SECURITY and carried and front != was_front:
			switches.append([sim.tick, front, p.at, p.security_phase])
			var start := sim.tick
			var half := int(CarryOnProps.TRANSFER_TICKS / 2.0)
			while sim.tick < start + half:
				w.world.step()
			views.draw()
			halfway.append(props.front_weight_of(ids[0]))
		if front and carried:
			front_cells[p.at] = true
		was_front = front and carried
		if w.cleared.has(ids[0]):
			break
	print(
		(
			"front carry switches %s; cells seen in front carry %s; front weight halfway %s"
			% [switches, front_cells.keys(), halfway]
		)
	)
	assert_bool(w.cleared.has(ids[0])).is_true()
	assert_int(switches.size()).is_greater_equal(2)
	assert_bool(switches[0][1]).is_true()
	assert_int(switches[0][3]).is_equal(SecurityRuntime.Phase.RETURN)
	assert_bool(switches[1][1]).is_false()
	assert_bool(front_cells.has(CORRIDOR)).is_true()
	# Halfway through each turn in time, three quarters of the way in pose
	# (the turn eases out: 1 - (1 - 0.5)^2), to the front and back.
	assert_float(halfway[0]).is_equal_approx(0.75, 0.01)
	assert_float(halfway[1]).is_equal_approx(0.25, 0.01)


## After a load (PassengerViews.snap()) a passenger on the way to the front
## carry is drawn in it at once, with no turn to play while paused. Control:
## two ticks after the front carry first becomes true the drawn blend is part
## way (strictly between 0 and 1), so the snap is what takes it to 1.
func test_a_load_in_the_corridor_starts_in_the_front_carry() -> void:
	var w := _make()
	var views := _views[-1]
	var props := views.carry_on_props()
	var ids := w.send_all([[1, false, true]])
	var p := w.world.passenger(ids[0])
	var sim := w.world.sim
	var front_at := -1
	for i in 3000:
		w.world.step()
		views.draw()
		if (
			p.stage == Passenger.Stage.SECURITY
			and SecurityLooks.bag_homes(sim, p) == [SecurityLooks.Home.HAND]
			and SecurityLooks.carry_front(sim, p)
		):
			front_at = sim.tick
			break
	assert_int(front_at).is_greater(0)
	assert_int(p.security_phase).is_equal(SecurityRuntime.Phase.RETURN)
	for tick in 2:
		w.world.step()
		views.draw()
	assert_bool(SecurityLooks.carry_front(sim, p)).is_true()
	var before := props.front_weight_of(ids[0])
	w.world.clock.set_paused(true)
	views.snap()
	var weight := props.front_weight_of(ids[0])
	print(
		(
			"front carry from tick %d: weight before the load %.3f, right after it %.3f"
			% [front_at, before, weight]
		)
	)
	assert_float(before).is_greater(0.0)
	assert_float(before).is_less(1.0)
	assert_float(weight).is_equal(1.0)


## On the walk back, the case turns back to the side upright ahead of the arm
## (CarryOnProps._bag_weight: the arm's weight squared on a turn from the
## front), so its lower end is not swung through the thigh, and both end the
## turn together. Control: the turn was seen part way (strictly between 0 and
## 1), so the two weights were compared mid-turn.
func test_the_case_turns_back_to_the_side_ahead_of_the_arm() -> void:
	var w := _make()
	var views := _views[-1]
	var props := views.carry_on_props()
	var ids := w.send_all([[1, false, true]])
	var p := w.world.passenger(ids[0])
	var sim := w.world.sim
	var mid: Array = []
	var was_front := false
	for i in 3000:
		w.world.step()
		views.draw()
		var carried := SecurityLooks.bag_homes(sim, p) == [SecurityLooks.Home.HAND]
		var front := SecurityLooks.carry_front(sim, p) and carried
		if was_front and not front and p.stage == Passenger.Stage.SECURITY:
			var start := sim.tick
			while sim.tick < start + int(CarryOnProps.TRANSFER_TICKS / 2.0):
				w.world.step()
			mid = [props.front_weight_of(ids[0]), props.bag_turn_of(ids[0])]
			while sim.tick < start + int(CarryOnProps.TRANSFER_TICKS):
				w.world.step()
			mid.append_array([props.front_weight_of(ids[0]), props.bag_turn_of(ids[0])])
			break
		was_front = front
	print("turn back to the side, [arm, bag] halfway then at the end: %s" % [mid])
	assert_int(mid.size()).is_equal(4)
	assert_float(mid[0]).is_greater(0.0)
	assert_float(mid[0]).is_less(1.0)
	assert_float(mid[1]).is_less(mid[0])
	assert_float(mid[1]).is_equal_approx(mid[0] * mid[0], 0.001)
	assert_float(mid[2]).is_equal(0.0)
	assert_float(mid[3]).is_equal(0.0)


## A turn that reverses part way starts from where the case is, both ways (the
## stamps sync() makes on a carry change, in its order: the arm's and the
## case's weights at that tick, then the tick): no jump at the reversal, and
## the case ends the last turn with the arm.
func test_a_reversed_case_turn_starts_from_where_the_case_is() -> void:
	var props := CarryOnProps.new()
	var held := {"front": false}
	var flips: Array = [[10.0, true], [13.0, false], [15.0, true]]
	for flip: Array in flips:
		var at: float = flip[0]
		var bag_then := props._bag_weight(held, at)
		var arm_then := props._front_weight(held, at)
		held["front_from"] = props._front_weight(held, at)
		held["bag_from"] = props._bag_weight(held, at)
		held["front_since"] = at
		held["front"] = flip[1]
		print("flip at %.0f to front=%s: bag %.3f arm %.3f" % [at, flip[1], bag_then, arm_then])
		assert_float(props._bag_weight(held, at)).is_equal_approx(bag_then, 0.0001)
		assert_float(props._front_weight(held, at)).is_equal_approx(arm_then, 0.0001)
	# Control: the reversals came part way, so a restart from 0 or 1 would jump.
	assert_float(held["bag_from"]).is_greater(0.0)
	assert_float(held["bag_from"]).is_less(1.0)
	var end := 15.0 + CarryOnProps.TRANSFER_TICKS
	assert_float(props._bag_weight(held, end)).is_equal(1.0)
	assert_float(props._front_weight(held, end)).is_equal(1.0)
	props.free()
