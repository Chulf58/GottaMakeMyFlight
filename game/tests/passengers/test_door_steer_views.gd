class_name TestDoorSteerViews
extends GdUnitTestSuite
## DoorSteer through PassengerViews with real carry state (board 4b062450):
## a roller guest coming in through an entrance is drawn off the door's axis,
## away from its pulling hand, by the steer DoorSteer gives for its bags; the
## steer does not jump on a change of hand, nor on the tick after a load
## (snap()); a roller with a hard case in the other hand is not steered (user
## ruling "No steer with a case"), and a case taken out of that hand eases the
## steer in.
## The entrance faces west on a floored grid, so a guest comes in walking east
## (+x) and the door's plane is the grid's west edge, x = 0.

const DOOR := Vector2i(0, 4)
const WEST := 3
## Ticks of walk watched, from the door cell out past the steer's reach.
const WALK_TICKS := 30
## The most a drawn offset may move in a tick: a change of hand at full weight
## moves it 2 * SIDE_M / TRANSFER_TICKS (0.04 m); the ease adds about 0.02 m.
const STEP_MAX_M := 0.065

var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(12, 9))
	PassengerTestWorld.place(grid, &"entrance_door", DOOR, WEST)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(9, 3), 0)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(60, 80))
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)


func after_test() -> void:
	_views.free()
	_world.free_all()


## A new guest whose first bag is a roller, with `bags` carry-on bags; with
## two, its second is a hard case.
func _roller_guest(bags := 1) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while (
		SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.ROLLER
		or (bags > 1 and SecurityLooks.bag_kind(p, 1) != SecurityLooks.Kind.CASE)
	):
		p.stage = Passenger.Stage.MADE
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.carry_on = bags
	return p


## Where `p` is drawn on this tick less where the sim puts it.
func _drawn_off(p: Passenger) -> Vector3:
	return _views.tick_position(p.id, true) - _world.sim.world_position(p)


## The door steer DoorSteer gives `p` now, as PassengerViews reads it.
func _steer(p: Passenger) -> Vector3:
	return DoorSteer.offset_of(_views, p, float(_world.clock.tick) + 1.0)


## Steps `ticks` ticks and returns the drawn offset of `p` after each, starting
## with the one now.
func _walk(p: Passenger, ticks: int) -> Array[Vector3]:
	var out: Array[Vector3] = [_drawn_off(p)]
	for i in ticks:
		_world.step()
		out.append(_drawn_off(p))
	return out


## The largest move of the drawn offset from one tick to the next in `offs`.
static func _largest_step(offs: Array[Vector3]) -> float:
	var most := 0.0
	for i in range(1, offs.size()):
		most = maxf(most, offs[i].distance_to(offs[i - 1]))
	return most


func test_a_roller_guest_coming_in_is_drawn_off_the_axis_away_from_its_hand() -> void:
	var p := _roller_guest()
	_world.step()
	var most := Vector3.ZERO
	for i in WALK_TICKS:
		var off := _drawn_off(p)
		# The tick position carries exactly DoorSteer's steer (nothing else
		# moves a walker in from the door), and draw_position() agrees with it.
		assert_vector(off).is_equal_approx(_steer(p), Vector3.ONE * 1e-5)
		assert_vector(_views.draw_position(p)).is_equal_approx(
			_views.tick_position(p.id, true), Vector3.ONE * 1e-5
		)
		if off.length() > most.length():
			most = off
		_world.step()
	var hand := CarryLead.hand_of(int(_views.carry_on_props().bag_state(p.id, 0)["place"]))
	print("id %d hand %d: largest drawn offset %s" % [p.id, hand, most])
	# Positive: the steer was drawn, near its whole size, across the door
	# (along z) and to the walker's left for the right hand (walking east the
	# left is north, -z).
	assert_float(most.length()).is_greater(DoorSteer.SIDE_M * 0.8)
	assert_float(absf(most.x)).is_less(1e-5)
	assert_float(signf(most.z)).is_equal(-1.0 if hand == 0 else 1.0)


func test_a_change_of_hand_at_the_door_does_not_jump() -> void:
	var p := _roller_guest()
	_world.step()
	var before := _drawn_off(p)
	assert_float(before.length()).override_failure_message("no steer at the door").is_greater(0.1)
	# A change of hand as CarryOnProps.sync() stamps one for the next tick:
	# the new place, the tick it is seen on, the old place still drawn.
	var bag: Dictionary = _views.carry_on_props()._held[p.id]["bags"][0]
	var place := int(bag["place"])
	var other := place + 2 if CarryLead.hand_of(place) == 0 else place - 2
	bag["home"] = place
	bag["place"] = other
	bag["changed"] = float(_world.clock.tick + 1)
	var offs := _walk(p, WALK_TICKS)
	print("offsets over the change: %s" % [offs.slice(0, 10)])
	# Control: the steer crossed to the other side before it eased out (the
	# guest walks out of its reach in about as many ticks as the change takes).
	var crossed := offs.any(func(off: Vector3) -> bool: return off.z * before.z < -1e-5)
	assert_bool(crossed).override_failure_message("never crossed").is_true()
	assert_float(_largest_step(offs)).is_less(STEP_MAX_M)


func test_a_load_at_the_door_draws_the_steer_and_does_not_jump_next_tick() -> void:
	var p := _roller_guest()
	_world.step()
	var steer := _steer(p)
	assert_float(steer.length()).override_failure_message("no steer at the door").is_greater(0.08)
	_views.snap()
	var snapped := _drawn_off(p)
	print("steer %s, drawn after the snap %s" % [steer, snapped])
	# The snap records the steer draw_position() gives, previous and current.
	assert_vector(snapped).is_equal_approx(_steer(p), Vector3.ONE * 1e-5)
	assert_vector(_views.tick_position(p.id, false)).is_equal_approx(
		_views.tick_position(p.id, true), Vector3.ONE * 1e-5
	)
	assert_float(snapped.length()).is_greater(0.08)
	var offs := _walk(p, 3)
	print("offsets after the snap: %s" % [offs])
	assert_float(_largest_step(offs)).is_less(STEP_MAX_M)


func test_a_roller_with_a_hard_case_in_the_other_hand_is_not_steered() -> void:
	var p := _roller_guest(2)
	_world.step()
	var props := _views.carry_on_props()
	var roller := props.bag_state(p.id, 0)
	var case_bag := props.bag_state(p.id, 1)
	print("roller %s case %s" % [roller.get("place"), case_bag.get("place")])
	# Control: both are held, in the two hands, the roller pulled.
	assert_int(int(roller["place"]) / 4).is_equal(SecurityLooks.Home.HAND)
	assert_int(roller["carry"]).is_equal(SecurityLooks.Carry.PULL)
	assert_int(int(case_bag["place"]) / 4).is_equal(SecurityLooks.Home.HAND)
	assert_int(case_bag["carry"]).is_equal(SecurityLooks.Carry.HAND)
	assert_int(CarryLead.hand_of(int(case_bag["place"]))).is_not_equal(
		CarryLead.hand_of(int(roller["place"]))
	)
	var offs := _walk(p, 6)
	print("offsets: %s" % [offs])
	for off in offs:
		assert_vector(off).is_equal(Vector3.ZERO)


func test_a_case_leaving_the_free_hand_at_the_door_eases_the_steer_in() -> void:
	var p := _roller_guest(2)
	_world.step()
	assert_vector(_steer(p)).is_equal(Vector3.ZERO)
	# The case goes down out of the other hand, as CarryOnProps.sync() stamps
	# a move for the next tick: its new place, the tick, its old place drawn.
	var bag: Dictionary = _views.carry_on_props()._held[p.id]["bags"][1]
	var place := int(bag["place"])
	bag["home"] = place
	bag["place"] = (SecurityLooks.Home.FLOOR * 2 + CarryLead.hand_of(place)) * 2
	var tick := float(_world.clock.tick + 1)
	bag["changed"] = tick
	var lengths: Array[float] = []
	for k in int(CarryOnProps.TRANSFER_TICKS) + 2:
		lengths.append(DoorSteer.offset_of(_views, p, tick + k).length())
	print("steer over the case's move: %s" % [lengths])
	assert_float(lengths[0]).is_equal(0.0)
	assert_float(lengths[lengths.size() - 1]).is_greater(0.08)
	for i in range(1, lengths.size()):
		assert_float(lengths[i] - lengths[i - 1]).is_greater_equal(0.0)
		assert_float(lengths[i] - lengths[i - 1]).is_less(0.03)
