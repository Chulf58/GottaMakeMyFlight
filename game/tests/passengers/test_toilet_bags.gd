class_name TestToiletBags
extends GdUnitTestSuite
## Carry-on bags on a toilet visit (Toilets 5/5): carried in and out of the
## stall, set down on the stall's floor while the passenger sits down, sits
## and stands up, at one point fixed in the stall between the seated knees and
## the closed door, clear of the side partitions (decision toilet-stall-kit-
## piece-1x2-footprint-side-partitions-out-to: 0.94 m clear, door at the
## front, a seated passenger reaches about 0.26 m in front of Mount_Use).

## Half the clear width between the side partitions, less a margin.
const CLEAR_HALF_M := 0.46
## Along the way out from the footprint centre: past the seated knees and the
## toes of the passenger standing at Mount_Turn, and inside the closed door.
const NEAREST_M := 0.4
const DOOR_M := 0.9

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new()
	ToiletTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.run_to(10)


func after_test() -> void:
	_world.free_all()


func _visitor(bags: int) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = bags
	p.liquids = false
	p.alarm = false
	p.stage = Passenger.Stage.TO_SECURITY
	p.at = Vector2i(20, 14)
	p.clear_path()
	assert_bool(_world.sim.toilets.try_visit(p)).is_true()
	return p


func _homes(p: Passenger) -> Array:
	return Array(SecurityLooks.bag_homes(_world.sim, p))


## The world transform the views give floor bag `index`: the body faces out of
## the door in these stages (PassengerViews._pose), and CarryOnProps puts a
## floor bag at the body's transform times its floor spot.
func _floor_world(p: Passenger, index: int, count: int) -> Transform3D:
	var out := Vector2(_world.sim.toilets.visit_of(p.id).stall["front"])
	var body := Transform3D(Basis(Vector3.UP, atan2(out.x, out.y)), _world.sim.world_position(p))
	return body * SecurityLooks.floor_spot(_world.sim, p, index, count)


## {stage: [homes, the first bag's world spot]} through one whole visit.
func _walk_visit(p: Passenger) -> Dictionary:
	var seen := {}
	while p.stage != Passenger.Stage.TO_SECURITY or seen.is_empty():
		_world.step()
		if Passenger.in_toilet(p.stage) and not seen.has(p.stage):
			seen[p.stage] = [_homes(p), _floor_world(p, 0, p.carry_on).origin]
		if _world.clock.tick > 3000:
			break
	return seen


func test_bags_are_carried_in_set_down_while_seated_and_picked_up_to_walk_out() -> void:
	var p := _visitor(1)
	var seen := _walk_visit(p)
	print(seen)
	var floor := [SecurityLooks.Home.FLOOR]
	var hand := [SecurityLooks.Home.HAND]
	assert_array(seen[Passenger.Stage.TOILET_WALK][0]).is_equal(hand)
	assert_array(seen[Passenger.Stage.TOILET_ENTER][0]).is_equal(hand)
	assert_array(seen[Passenger.Stage.TOILET_SITTING_DOWN][0]).is_equal(floor)
	assert_array(seen[Passenger.Stage.TOILET_USE][0]).is_equal(floor)
	assert_array(seen[Passenger.Stage.TOILET_STANDING_UP][0]).is_equal(floor)
	assert_array(seen[Passenger.Stage.TOILET_EXIT][0]).is_equal(hand)
	assert_array(_homes(p)).is_equal(hand)


func test_the_floor_spot_stays_put_in_the_stall_while_the_body_shuffles() -> void:
	var p := _visitor(1)
	while p.stage != Passenger.Stage.TOILET_SITTING_DOWN:
		_world.step()
	var stall := _world.sim.toilets.visit_of(p.id).stall
	var out := SecurityLooks.world_dir(stall["front"])
	var centre: Vector3 = stall["use"] - out * ToiletLayout.USE_M
	var expected := centre + out * SecurityLooks.STALL_BAG_M
	var spots: Array[Vector3] = []
	var bodies: Array[Vector3] = []
	while p.stage != Passenger.Stage.TOILET_EXIT:
		spots.append(_floor_world(p, 0, 1).origin)
		bodies.append(_world.sim.world_position(p))
		_world.step()
	print("body moved %.3f m, bag spots %d" % [bodies[0].distance_to(stall["use"]), spots.size()])
	# The control: the body did move under the bag.
	assert_float(bodies[0].distance_to(stall["use"])).is_greater(0.3)
	for spot in spots:
		assert_float(Vector2(spot.x - expected.x, spot.z - expected.z).length()).is_less(0.001)


func test_every_bag_kind_lies_inside_the_stall_clear_of_partitions_knees_and_door() -> void:
	for count in [1, 2]:
		var p := _visitor(count)
		while p.stage != Passenger.Stage.TOILET_USE:
			_world.step()
		var stall := _world.sim.toilets.visit_of(p.id).stall
		var out := SecurityLooks.world_dir(stall["front"])
		var side := out.cross(Vector3.UP)
		var centre: Vector3 = stall["use"] - out * ToiletLayout.USE_M
		var scale_by := SecurityLooks.bag_scale(p)
		for kind in SecurityLooks.Kind.values():
			var box := CarryOnProps.bag_box(kind)
			for index in count:
				var xf := _floor_world(p, index, count)
				xf = Transform3D(xf.basis.scaled(Vector3.ONE * scale_by), xf.origin)
				var lateral := Vector2(INF, -INF)
				var along := Vector2(INF, -INF)
				for corner in 8:
					var at := xf * box.get_endpoint(corner) - centre
					lateral = Vector2(minf(lateral.x, at.dot(side)), maxf(lateral.y, at.dot(side)))
					along = Vector2(minf(along.x, at.dot(out)), maxf(along.y, at.dot(out)))
				print(
					(
						"%d bags, kind %d, bag %d: across %.3f to %.3f, out %.3f to %.3f"
						% [count, kind, index, lateral.x, lateral.y, along.x, along.y]
					)
				)
				assert_float(lateral.x).is_greater_equal(-CLEAR_HALF_M)
				assert_float(lateral.y).is_less_equal(CLEAR_HALF_M)
				assert_float(along.x).is_greater_equal(NEAREST_M)
				assert_float(along.y).is_less_equal(DOOR_M)
