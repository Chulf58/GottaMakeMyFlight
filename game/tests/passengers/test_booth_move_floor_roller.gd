class_name TestBoothMoveFloorRoller
extends GdUnitTestSuite
## A booth moved while its guest sits leaves the guest's roller lying where it
## lies (RollerPark.chair_front() at the old approach cell, as the guest gets up
## from the old seat, CafeSim._relocates()) until the guest's own pick-up
## starts (board 811e4547). The 1.512 m step in a tick measured in
## test_booth_roller_turn_back.gd is the pick-up's own hand-led stretch: a
## guest that finishes its meal with no booth move draws the same 1.512 m step
## at the same point of its pick-up (k 0.44). Drawn by real PassengerViews, a
## tick a draw.

var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
	if _world != null:
		_world.free_all()
	_views = null
	_world = null


func _tick() -> void:
	_world.step()
	_views.draw()


## A guest with a roller seated at the restaurant's booth, its roller lying
## settled on the floor at the approach cell.
func _seated() -> Passenger:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid, false, &"restaurant", true, &"cafe_counter", &"restaurant_booth")
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var p: Passenger = null
	for attempt in 200:
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		p.cafe_cooldown = 1000000
		p.hunger = 30
		p.carry_on = 1
		if SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER:
			break
		p.carry_on = 0
		ToiletTestLayout.calm(p)
	p.liquids = false
	p.alarm = false
	while p.stage != Passenger.Stage.TO_GATE and _world.clock.tick < 1500:
		_world.step()
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	assert_bool(_world.sim.cafes.try_visit(p)).override_failure_message("visit refused").is_true()
	while p.stage != Passenger.Stage.CAFE_SEATED and _world.clock.tick < 3000:
		_tick()
	for n in 20:
		_tick()
	var props := _views.carry_on_props()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_SEATED)
	assert_int(int(props.bag_state(p.id, 0).get("place", -1)) / 4).is_equal(
		SecurityLooks.Home.FLOOR
	)
	assert_float(props.transfer_progress(p.id, 0)).is_equal(1.0)
	return p


## Moves the guest's booth to the first of three neighbouring cells the grid
## accepts, as a room move does; returns the anchor's shift.
func _move_booth(p: Passenger) -> Vector2i:
	var id := int(_world.sim.cafes.visit_of(p.id).seat["object_id"])
	var record := _world.grid.get_object(id)
	for shift: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0)]:
		var place := BuildEdit.place_object(
			record["def"], record["anchor"] + shift, record["facing"]
		)
		place.object_id = id
		place.paid = int(record.get("paid", 0))
		if _world.grid.apply_batch([BuildEdit.remove_object(id), place])[1].ok:
			return shift
		var back := BuildEdit.place_object(record["def"], record["anchor"], record["facing"])
		back.object_id = id
		back.paid = place.paid
		_world.grid.apply_batch([back])
	fail("the booth could not be moved")
	return Vector2i.ZERO


## Moved while its guest sits, the booth leaves the lying roller still on
## every tick until the roller's pick-up is stamped. Control: the booth did
## move, the guest was turned back to get up, and the roller lay on the floor
## for more than 5 drawn ticks after the move.
func test_a_booth_moved_while_seated_leaves_the_lying_roller_still() -> void:
	var p := _seated()
	var props := _views.carry_on_props()
	var shift := _move_booth(p)
	var node: Node3D = props.bag_state(p.id, 0)["node"]
	var last := node.global_position
	var most := 0.0
	var lying := 0
	var got_up := false
	for n in 200:
		_tick()
		got_up = got_up or p.stage == Passenger.Stage.CAFE_STANDING_UP
		if int(props.bag_state(p.id, 0).get("home", -1)) / 4 != SecurityLooks.Home.FLOOR:
			break
		lying += 1
		most = maxf(most, node.global_position.distance_to(last))
		last = node.global_position
	print("booth moved by %s: lying %d ticks, most %.4f, got up %s" % [shift, lying, most, got_up])
	assert_bool(shift != Vector2i.ZERO).is_true()
	assert_bool(got_up).is_true()
	assert_int(lying).is_greater(5)
	assert_float(most).is_less(0.0001)
