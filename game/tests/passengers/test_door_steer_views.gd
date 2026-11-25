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


## The world is built once for the file; each case takes a new guest at the
## door (before_test() clears the last case's guests away first).
func before() -> void:
	PassengerTestWorld.tracker = self
	var grid := PassengerTestWorld.floored(Vector2i(12, 9))
	PassengerTestWorld.place(grid, &"entrance_door", DOOR, WEST)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(9, 3), 0)
	# Boarding and doors far off, so no guest is late in any case.
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(60000, 80000))
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)


func after() -> void:
	_views.free()
	_world.free_all()
	PassengerTestWorld.tracker = null


## Every guest of an earlier case leaves (made its flight).
func before_test() -> void:
	for id in _world.sim.passenger_ids():
		_world.passenger(id).stage = Passenger.Stage.MADE
	_world.step()


## A new guest whose first bag is a roller (1-bag) or a 2-bag non-roller guest.
func _roller_guest(bags := 1) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.carry_on = bags
	while bags == 1 and SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.ROLLER:
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
	var within_ease := 0
	for i in WALK_TICKS:
		var off := _drawn_off(p)
		var lane := _views.corridor_offset(p.id)
		var steer_part := off - lane
		if p.grid_position().x < DoorSteer.EASE_M:
			within_ease += 1
		assert_vector(off).is_equal_approx(_steer(p) + lane, Vector3.ONE * 1e-5)
		assert_vector(_views.draw_position(p)).is_equal_approx(
			_views.tick_position(p.id, true), Vector3.ONE * 1e-5
		)
		if steer_part.length() > most.length():
			most = steer_part
		_world.step()
	assert_int(within_ease).is_greater(0)
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


func test_a_two_bag_guest_coming_in_is_not_steered() -> void:
	var p := _roller_guest(2)
	_world.step()
	var props := _views.carry_on_props()
	for i in 2:
		assert_int(props.bag_state(p.id, i)["kind"]).is_not_equal(SecurityLooks.Kind.ROLLER)
	var steer_offs: Array[Vector3] = []
	var lane_active := false
	for i in 20:
		_world.step()
		var lane := _views.corridor_offset(p.id)
		if lane.length() > 0.05:
			lane_active = true
		steer_offs.append(_drawn_off(p) - lane)
	print("steer offsets (2-bag guest): %s" % [steer_offs])
	assert_bool(lane_active).is_true()
	for off in steer_offs:
		assert_vector(off).is_equal_approx(Vector3.ZERO, Vector3.ONE * 1e-5)


func test_corridor_offset_is_zero_within_full_m_of_a_doorway() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(12, 9))
	PassengerTestWorld.place(grid, &"entrance_door", DOOR, WEST)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(9, 3), 0)
	for y in 9:
		if y != 4:
			grid.apply(BuildEdit.place_wall(Vector2i(5, y), BuildGrid.Side.WEST))
	var door_res := grid.apply(
		BuildEdit.place_wall(Vector2i(5, 4), BuildGrid.Side.WEST, BuildGrid.WallKind.DOOR)
	)
	assert_bool(door_res.ok).is_true()
	assert_int(grid.wall_kind(Vector2i(5, 4), BuildGrid.Side.WEST)).is_equal(
		BuildGrid.WallKind.DOOR
	)
	var w := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(60000, 80000))
	var views := PassengerTestWorld.views()
	views.clock = w.clock
	views.sim = w.sim
	add_child(views)
	var p := w.passenger(w.sim.spawn_now(PassengerTestWorld.FLIGHT))
	var path: Array[Vector2i] = []
	for x in range(0, 10):
		path.append(Vector2i(x, 4))
	p.stage = Passenger.Stage.TO_GATE
	p.cleared = true
	p.at = path[0]
	p.set_path(path)
	var within_full := 0
	var outside_lane := false
	for i in 80:
		p.walk(PassengerSim.WALK_MM)
		views.sync()
		var dist := absf(p.grid_position().x - 5.0)
		var lane := views.corridor_offset(p.id)
		if dist <= DoorSteer.FULL_M:
			within_full += 1
			assert_vector(lane).is_equal(Vector3.ZERO)
		elif p.grid_position().x > 2.5 and p.grid_position().x < 3.5 and lane.length() > 0.05:
			outside_lane = true
	print("doorway pass: %d ticks within FULL_M, outside_lane=%s" % [within_full, outside_lane])
	assert_int(within_full).is_greater(0)
	assert_bool(outside_lane).is_true()
	views.free()
	w.free_all()


func test_a_lifted_roller_returning_to_pull_at_the_door_eases_the_steer_in() -> void:
	var p := _roller_guest(1)
	p.late = true
	_world.step()
	assert_vector(_steer(p)).is_equal(Vector3.ZERO)
	# The lifted roller returns to the pull, as CarryOnProps.sync() stamps a
	# move for the next tick: its new place, the tick, its old place drawn.
	var bag: Dictionary = _views.carry_on_props()._held[p.id]["bags"][0]
	var place := int(bag["place"])
	bag["home"] = place
	bag["place"] = place - 1
	var tick := float(_world.clock.tick + 1)
	bag["changed"] = tick
	var lengths: Array[float] = []
	for k in int(CarryOnProps.TRANSFER_TICKS) + 2:
		lengths.append(DoorSteer.offset_of(_views, p, tick + k).length())
	print("steer over the lift release: %s" % [lengths])
	assert_float(lengths[0]).is_equal(0.0)
	assert_float(lengths[lengths.size() - 1]).is_greater(0.08)
	for i in range(1, lengths.size()):
		assert_float(lengths[i] - lengths[i - 1]).is_greater_equal(0.0)
		assert_float(lengths[i] - lengths[i - 1]).is_less(0.03)
