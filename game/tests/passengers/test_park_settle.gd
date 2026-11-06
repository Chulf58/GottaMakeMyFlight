class_name TestParkSettle
extends GdUnitTestSuite
## A roller set down at a gate chair walled on both sides lies out of the walls
## once it has settled, not only while its move is drawn (CarryPlace.
## _off_walls(), ParkWalls; board a40fdbaf): the floor spot beside the feet
## reaches 0.07 m past a wall on its cell's edge. And a guest keeps the hand
## ParkSide chose for its seat when a wall is built beside it mid-stay.

var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
		_world.free_all()
	_views = null


func _tick() -> void:
	_world.clock.advance(SimClock.STEP)
	await get_tree().process_frame


## The first gate chair: [its seat cell, its front cell, the two side edges of
## the front cell (right, left of one facing out of the chair)].
func _chair() -> Array:
	var seat: Dictionary = _world.sim.layout.seats[0]
	var front: Vector2i = seat["front"]
	var out: Vector2i = front - (seat["cell"] as Vector2i)
	# +x of a frame facing out is on the left of one facing out.
	var x := Basis(Vector3.UP, atan2(out.x, out.y)).x
	var right := Vector2i(roundi(-x.x), roundi(-x.z))
	return [seat, front, BuildGrid.SIDE_STEP.find(right), BuildGrid.SIDE_STEP.find(-right)]


## A walker with one roller at the first gate chair's front, drawn a few ticks
## (bound for the chair), then sitting down there.
func _sitting_walker(walls: Array[int]) -> Passenger:
	_world = PassengerTestWorld.reference_world()
	_world.run_to(10)
	var chair := _chair()
	for side in walls:
		var made := _world.grid.apply(BuildEdit.place_wall(chair[1], chair[2 + side]))
		assert_bool(made.ok).override_failure_message("wall %d refused" % side).is_true()
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.ROLLER:
		ToiletTestLayout.calm(p)
		p.carry_on = 0
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 1
	p.cleared = true
	var seat: Dictionary = chair[0]
	p.stage = Passenger.Stage.TO_GATE
	p.seat_cell = seat["cell"]
	p.seat_front = seat["front"]
	p.at = seat["front"]
	p.clear_path()
	p.boarding_tick = _world.sim.tick + 100000
	for n in 4:
		await _tick()
	p.seat_object = seat["object_id"]
	p.seat_piece = Relocation.placement(_world.grid, p.seat_object)
	p.stage = Passenger.Stage.SITTING_DOWN
	p.stage_tick = _world.sim.tick
	p.clear_path()
	return p


## Walled on both sides, the roller set down lies out of the walls on every
## tick once its move has ended, for 20 ticks. Control: the floor spot beside
## the feet (RollerPark.floor_spot() in the chair front's frame) is in a wall,
## and the roller did come to rest on the floor.
func test_a_roller_settled_at_a_chair_walled_on_both_sides_lies_out_of_the_walls() -> void:
	var p := await _sitting_walker([0, 1])
	var props := _views.carry_on_props()
	var front: Transform3D = RollerPark.chair_front(_world.sim, p, SecurityLooks.Kind.ROLLER)
	var walls := PullSide.walls_near(_world.grid, front.origin)
	var hand := SecurityLooks.hand_of(_world.sim, p, 0)
	var spot := RollerPark.floor_spot(_world.sim, p, SecurityLooks.Kind.ROLLER, hand, 0, 1)
	assert_bool(ParkWalls.inside(front * spot, walls)).is_true()
	var settled := 0
	var inside := 0
	for n in 80:
		await _tick()
		var bag := props.bag_state(p.id, 0)
		var place := int(bag.get("place", -1))
		if place / 4 != SecurityLooks.Home.FLOOR or props.transfer_progress(p.id, 0) < 1.0:
			continue
		settled += 1
		var node: Node3D = bag["node"]
		if ParkWalls.inside(node.global_transform, walls):
			inside += 1
	print("walled both sides: settled ticks %d, in a wall %d" % [settled, inside])
	assert_int(settled).is_greater(20)
	assert_int(inside).is_equal(0)


## A guest bound for a chair with no walls beside it keeps the hand it chose
## there when a wall is built on that hand's side: the roller is already
## coming down or on the floor. Control: chosen afresh (the stamp cleared),
## the walled seat gives the other hand.
func test_a_wall_built_mid_stay_keeps_the_hand() -> void:
	var p := await _sitting_walker([])
	var hand := SecurityLooks.hand_of(_world.sim, p, 0)
	for n in 6:
		await _tick()
	var chair := _chair()
	var made := _world.grid.apply(BuildEdit.place_wall(chair[1], chair[2 + hand]))
	assert_bool(made.ok).is_true()
	await _tick()
	var kept := SecurityLooks.hand_of(_world.sim, p, 0)
	# ParkSide.STAMPS, spelled out so this file also runs against code without it.
	_world.sim.remove_meta(&"park_side_hands")
	var fresh := SecurityLooks.hand_of(_world.sim, p, 0)
	print("wall built mid-stay: hand %d, kept %d, chosen afresh %d" % [hand, kept, fresh])
	assert_int(kept).is_equal(hand)
	assert_int(fresh).is_equal(1 - hand)
