class_name TestDoorTuckSnap
extends GdUnitTestSuite
## A tucked roller stays tucked through PassengerViews.snap() (a load), with
## no ease in from its side (board cd4ff4e0, Sol review): snap() releases
## every bag record before its sync, so the new record has no tuck state. A
## guest pulling a roller walks the cafe layout to a seat, a frame at a time,
## until its roller is fully tucked beside a wall or opening; the views then
## snap, and the first frame drawn after it must show the roller tucked.

const MAX_TICK := 3000

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


func _frame() -> void:
	_world.clock.advance(SimClock.STEP / 3.0)
	await get_tree().process_frame
	await get_tree().create_timer(0.0, true, false, true).timeout
	_views.carry_on_props()._unposed()


## A roller guest on its way to a cafe seat, with walls built on both sides of
## a stretch of its route ahead.
func _corridor_walker(start := 2) -> Passenger:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.ROLLER:
		p.carry_on = 0
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.carry_on = 1
	p.hunger = 0
	p.cafe_cooldown = 1000000
	while p.stage != Passenger.Stage.TO_GATE and _world.clock.tick < MAX_TICK:
		_world.step()
	assert_bool(_world.sim.cafes.try_visit(p)).is_true()
	# Walls on both sides of a stretch of the route ahead (a corridor no change
	# of hand clears, as a doorway): the roller tucks there.
	var edits: Array[BuildEdit] = []
	for k in range(p.path_index + start, mini(p.path_index + start + 6, p.path.size() - 1)):
		var d: Vector2i = p.path[k + 1] - p.path[k]
		var sides := (
			[BuildGrid.Side.NORTH, BuildGrid.Side.SOUTH]
			if d.x != 0
			else [BuildGrid.Side.EAST, BuildGrid.Side.WEST]
		)
		for side in sides:
			edits.append(BuildEdit.place_wall(p.path[k], side))
	var placed := 0
	for result in grid.apply_batch(edits):
		placed += int(result.ok)
	assert_int(placed).override_failure_message("no corridor wall placed").is_greater(1)
	return p


func test_a_snap_beside_a_wall_draws_the_roller_tucked_at_once() -> void:
	var p := _corridor_walker()
	var props := _views.carry_on_props()
	var tucked := false
	while not tucked and p.stage != Passenger.Stage.CAFE_SEATED and _world.clock.tick < MAX_TICK:
		await _frame()
		var state := props.bag_state(p.id, 0)
		tucked = (
			state.get("carry", -1) == SecurityLooks.Carry.PULL
			and RollerPull.tuck_weight(state, props._now()) >= 1.0
			and props.transfer_progress(p.id, 0) >= 1.0
		)
	# Control: the walk does tuck its roller somewhere.
	assert_bool(tucked).override_failure_message("the walk never tucked").is_true()
	_views.snap()
	await _frame()
	var after := props.bag_state(p.id, 0)
	var weight := RollerPull.tuck_weight(after, props._now())
	assert_float(weight).override_failure_message("eases in from %.2f" % weight).is_equal(1.0)
	# The drawn axle is at the tucked offset from the hips, not out at the side.
	var body := _views.node_for(p.id)
	var frame := Transform3D(Basis(Vector3.UP, body.rotation.y), body.global_position)
	var local: Vector3 = frame.affine_inverse() * (after["drawn_axle"] as Vector3)
	var out := -1.0 if CarryLead.hand_of(int(after["place"])) == 0 else 1.0
	var side := (local.x - float(after.get("hips_x", 0.0))) * out
	assert_float(side).is_less(RollerPull.TUCK_SIDE_M + 0.03)


func test_a_snap_before_the_walls_keeps_the_tuck_that_was_coming() -> void:
	# The tuck turns on LOOK_TICKS and TUCK_TICKS of walk before the roller's
	# settled footprint reaches the walls; a snap at that moment must look as
	# far ahead as a walking guest does, not a standing one's few centimetres.
	# The corridor starts six cells on, so the guest is walking when the tuck
	# turns on.
	var p := _corridor_walker(6)
	var props := _views.carry_on_props()
	var on := false
	while not on and p.stage != Passenger.Stage.CAFE_SEATED and _world.clock.tick < MAX_TICK:
		await _frame()
		var state := props.bag_state(p.id, 0)
		on = (
			state.get("carry", -1) == SecurityLooks.Carry.PULL
			and state.get("tuck_on", false)
			and p.is_moving()
		)
	assert_bool(on).override_failure_message("the walk never tucked").is_true()
	# Control: the walls are still ahead (the settled footprint is clear here).
	var body := _views.node_for(p.id)
	var hand := CarryLead.hand_of(int(props.bag_state(p.id, 0)["place"]))
	var here := Transform3D(Basis(Vector3.UP, body.rotation.y), body.global_position)
	var clear := not PullSide.blocked(
		_world.sim.grid, [here], PullSide.footprint(hand, false), false
	)
	assert_bool(clear).override_failure_message("snapped at the walls, not before").is_true()
	assert_bool(p.is_moving()).is_true()
	_views.snap()
	await _frame()
	var after := props.bag_state(p.id, 0)
	assert_bool(after.get("tuck_on", false)).override_failure_message("tuck lost").is_true()
	assert_float(RollerPull.tuck_weight(after, props._now())).is_equal(1.0)
