class_name TestDoorCaseFront
extends GdUnitTestSuite
## A hard case in the free hand of a guest pulling a roller is carried in front
## through an entrance or exit door (board d52f21db), the front carry of a cell
## closed on both sides (decision in-a-cell-closed-on-both-sides-a-passenger-
## carries-their-bag), so it does not swing into the far open leaf. The door
## steer stays off for such a guest (user ruling "No steer with a case").
## DoorSteer.case_front_at() says when: a pulled roller and a hand-carried case
## both in hand, within CASE_FRONT_M of the door's plane and LATERAL_M of its
## axis. The entrance faces west on a floored grid, so a guest comes in walking
## east (+x) and the door's plane is the grid's west edge, x = 0.

const DOOR := Vector2i(0, 4)
const WEST := 3
## Ticks of walk watched, from the door cell out past CASE_FRONT_M.
const WALK_TICKS := 40
const ROLLER := SecurityLooks.Kind.ROLLER
const CASE := SecurityLooks.Kind.CASE
const HAND := SecurityLooks.Home.HAND

var _world: PassengerTestWorld
var _views: PassengerViews
## The door's plane at its axis (world), and the way in through it (world x, z).
var _plane := Vector3.ZERO
var _in := Vector2.ZERO


func before() -> void:
	PassengerTestWorld.tracker = self
	var grid := PassengerTestWorld.floored(Vector2i(12, 9))
	PassengerTestWorld.place(grid, &"entrance_door", DOOR, WEST)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(9, 3), 0)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(60000, 80000))
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	var record := grid.get_object(grid.object_at(DOOR))
	var step := DoorPlacement.back_step(record["facing"])
	_in = -Vector2(step)
	_plane = grid.cell_to_world(record["anchor"]) + Vector3(step.x, 0.0, step.y) * 0.5
	assert_vector(_in).is_equal(Vector2(1.0, 0.0))


func after() -> void:
	_views.free()
	_world.free_all()
	PassengerTestWorld.tracker = null


func before_test() -> void:
	for id in _world.sim.passenger_ids():
		_world.passenger(id).stage = Passenger.Stage.MADE
	_world.step()


## A point `along` metres in past the door's plane (negative: outside) and
## `across` metres to the north (-z) of its axis.
func _at(along: float, across := 0.0) -> Vector3:
	return _plane + Vector3(_in.x, 0.0, _in.y) * along + Vector3(0.0, 0.0, -across)


func _front(here: Vector3, kinds: Array, homes: Array, lifts: Array) -> bool:
	return DoorSteer.case_front_at(_world.sim.grid, here, kinds, homes, lifts)


func test_a_pulled_roller_and_a_case_at_the_door_carry_the_case_in_front() -> void:
	var both := [[ROLLER, CASE], [HAND, HAND], [false, false]]
	assert_bool(_front(_at(0.0), both[0], both[1], both[2])).is_true()
	assert_bool(_front(_at(-1.0), both[0], both[1], both[2])).is_true()
	assert_bool(_front(_at(1.0, 0.5), both[0], both[1], both[2])).is_true()
	# Either order of the two bags.
	assert_bool(_front(_at(0.3), [CASE, ROLLER], both[1], both[2])).is_true()


func test_away_from_the_door_the_case_stays_at_the_side() -> void:
	var kinds := [ROLLER, CASE]
	var homes := [HAND, HAND]
	var lifts := [false, false]
	var past := DoorSteer.CASE_FRONT_M + 0.05
	assert_bool(_front(_at(past), kinds, homes, lifts)).is_false()
	assert_bool(_front(_at(-past), kinds, homes, lifts)).is_false()
	assert_bool(_front(_at(0.0, DoorSteer.LATERAL_M + 0.05), kinds, homes, lifts)).is_false()
	assert_bool(_front(_at(6.0), kinds, homes, lifts)).is_false()


func test_only_a_case_beside_a_pulled_roller_turns() -> void:
	var here := _at(0.0)
	# A case alone, a roller alone, a lifted roller with a case, a case not in
	# the hand: no turn.
	assert_bool(_front(here, [CASE], [HAND], [false])).is_false()
	assert_bool(_front(here, [ROLLER], [HAND], [false])).is_false()
	assert_bool(_front(here, [ROLLER, CASE], [HAND, HAND], [true, false])).is_false()
	(
		assert_bool(_front(here, [ROLLER, CASE], [HAND, SecurityLooks.Home.FLOOR], [false, false]))
		. is_false()
	)
	# A worn bag beside the roller is no hand-carried case.
	(
		assert_bool(
			_front(here, [ROLLER, SecurityLooks.Kind.BACKPACK], [HAND, HAND], [false, false])
		)
		. is_false()
	)


## A new guest whose first bag is a roller, with `bags` carry-on bags; with
## two, its second is a hard case.
func _roller_guest(bags: int) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while (
		SecurityLooks.bag_kind(p, 0) != ROLLER
		or (bags > 1 and SecurityLooks.bag_kind(p, 1) != CASE)
	):
		p.stage = Passenger.Stage.MADE
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.carry_on = bags
	return p


## The front-carry weights of `p` after each of `ticks` ticks: [arm, case].
func _weights(p: Passenger, ticks: int) -> Array:
	var props := _views.carry_on_props()
	var out := []
	for i in ticks:
		_world.step()
		var along := Vector2(_world.sim.world_position(p).x - _plane.x, 0.0).length()
		out.append([snappedf(along, 0.01), props.front_weight_of(p.id), props.bag_turn_of(p.id)])
	return out


func test_a_roller_guest_with_a_case_coming_in_carries_it_in_front_then_at_the_side() -> void:
	var p := _roller_guest(2)
	var weights := _weights(p, WALK_TICKS)
	print("id %d along, arm, case: %s" % [p.id, weights])
	var props := _views.carry_on_props()
	var case_bag := props.bag_state(p.id, 1)
	# Control: the case is in the hand, carried as a case, the roller pulled.
	assert_int(int(case_bag["place"]) / 4).is_equal(HAND)
	assert_int(case_bag["carry"]).is_equal(SecurityLooks.Carry.HAND)
	assert_int(props.bag_state(p.id, 0)["carry"]).is_equal(SecurityLooks.Carry.PULL)
	# In front at the door: whole while within CASE_FRONT_M of the plane (the
	# guest is made in the door cell, 0.6 m in, and starts in the front carry).
	var near_whole := 0
	var far_side := 0
	for w: Array in weights:
		if float(w[0]) < DoorSteer.CASE_FRONT_M:
			assert_float(float(w[2])).override_failure_message("at %.2f m" % w[0]).is_equal(1.0)
			near_whole += 1
	# And back at the side once well past the door.
	var last: Array = weights.back()
	assert_float(float(last[0])).is_greater(DoorSteer.CASE_FRONT_M + 0.5)
	assert_float(float(last[1])).is_equal(0.0)
	assert_float(float(last[2])).is_equal(0.0)
	for w: Array in weights:
		far_side += int(float(w[2]) == 0.0)
	assert_int(near_whole).is_greater(0)
	assert_int(far_side).is_greater(0)


func test_a_roller_guest_with_no_case_keeps_the_side_carry_at_the_door() -> void:
	var p := _roller_guest(1)
	var weights := _weights(p, 8)
	print("id %d along, arm, case: %s" % [p.id, weights])
	assert_float(float(weights[0][0])).is_less(DoorSteer.FULL_M + 0.5)
	for w: Array in weights:
		assert_float(float(w[1])).is_equal(0.0)


## A roller-and-case guest standing still in the check-in queue on `cell`,
## having walked east onto it (test_queue_stand_side_sim's _queuer).
func _queuer(cell: Vector2i) -> Passenger:
	var p := _roller_guest(2)
	p.late = false
	p.stage = Passenger.Stage.CHECKIN_QUEUE
	p.at = cell
	var path: Array[Vector2i] = [cell - Vector2i(1, 0), cell]
	p.set_path(path)
	p.path_index = 1
	return p


## Syncs `p` standing still for `ticks` ticks with the sim held (its clock
## stepped by hand, as test_queue_stand_side_sim does), from a load (snap(),
## so its last two tick positions are both where it stands): [roller stood in
## a queue stand, the case's turn to the front].
func _stand_still(p: Passenger, ticks: int) -> Array:
	_views.snap()
	for n in ticks:
		_world.clock.tick += 1
		_views.sync()
		_views.draw()
		# Placed as on a drawn frame (frame_pre_draw), which settles the pull.
		_views.carry_on_props()._unposed()
	var props := _views.carry_on_props()
	return [RollerPark.queued(props.bag_state(p.id, 0)), props.bag_turn_of(p.id)]


func test_a_still_queue_at_the_door_stands_the_roller_and_keeps_the_case_in_front() -> void:
	var ticks := RollerPark.STILL_TICKS + ceili(RollerPark.QUEUE_STAND_TICKS) + 4
	# Control: well away from the door the same still guest stands its roller,
	# the case at its side.
	var far := _queuer(Vector2i(6, 4))
	assert_bool(RollerPark.queue_still(_world.sim, far)).is_true()
	var away := _stand_still(far, ticks)
	print("away from the door: stood %s, case turn %.2f" % away)
	assert_bool(away[0]).is_true()
	assert_float(float(away[1])).is_equal(0.0)
	far.stage = Passenger.Stage.MADE
	_views.sync()
	# In the door cell: the roller is stood all the same, and the case is in front.
	var near := _queuer(DOOR)
	(
		assert_bool(
			DoorSteer.case_front_at(
				_world.sim.grid,
				_world.sim.world_position(near),
				[ROLLER, CASE],
				[HAND, HAND],
				[false, false]
			)
		)
		. is_true()
	)
	var at_door := _stand_still(near, ticks)
	print("in the door cell: stood %s, case turn %.2f" % at_door)
	assert_bool(at_door[0]).is_true()
	assert_float(float(at_door[1])).is_equal(1.0)
