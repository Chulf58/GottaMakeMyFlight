class_name TestLandsideViewsTicks
extends GdUnitTestSuite
## LandsideViews draws each car between its last two ticks with the clock's
## alpha (decision sim-architecture-fixed-tick-data-records-snapshot-saves-
## grid-astar): on one lane by distance along the lane, through the clock's
## ticked signal after PassengerSim stepped the road. A car that changed
## place (road to curb berth) is drawn where it is now, never on a line
## between the two. snap() draws the state now with nothing between. The
## world is the starter road with the reference terminal, 12 passengers
## booked, seed 3.

const BOOKED := 12
const LIMIT := 4000

var _land: LandsideTestWorld
var _views: LandsideViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_land = LandsideTestWorld.make(null, [], 3)
	_views = LandsideViews.new()
	_views.landside = _land.landside
	_views.clock = _land.world.clock
	add_child(_views)
	_land.schedule(BOOKED)


func after_test() -> void:
	_views.free()
	_land.free_all()
	_land = null


## Steps until a vehicle drives on road_in on the map; its id, or 0.
func _first_driving() -> int:
	while _land.sim.tick < LIMIT:
		_land.step()
		for id in _land.landside.vehicle_ids():
			var v := _land.landside.get_vehicle(id)
			if v.lane == LandsideVehicle.Lane.ROAD_IN and v.pos_mm >= 0:
				if v.stage == LandsideVehicle.Stage.DRIVE:
					return id
	return 0


func test_a_driving_car_is_drawn_between_its_two_ticks_by_distance() -> void:
	var id := _first_driving()
	assert_int(id).is_greater(0)
	var v := _land.landside.get_vehicle(id)
	var before_mm := v.pos_mm
	_land.step()
	var after_mm := v.pos_mm
	var road := _land.landside.definition.road_in
	var half := LandsideDefinition.point_at(road, roundi((before_mm + after_mm) * 0.5))
	var at_half := _views.pose_at(id, 0.5).origin
	print("mm %d -> %d, half %s drawn %s" % [before_mm, after_mm, half, at_half])
	assert_int(after_mm).is_greater(before_mm)
	assert_vector(_views.pose_at(id, 0.0).origin).is_equal_approx(
		LandsideDefinition.point_at(road, before_mm), Vector3.ONE * 0.001
	)
	assert_vector(_views.pose_at(id, 1.0).origin).is_equal_approx(
		LandsideDefinition.point_at(road, after_mm), Vector3.ONE * 0.001
	)
	assert_vector(at_half).is_equal_approx(half, Vector3.ONE * 0.001)
	assert_float(_views.pose_at(id, 0.5).basis.z.x).is_less(-0.99)


func test_a_frame_draws_with_the_clock_alpha() -> void:
	var id := _first_driving()
	assert_int(id).is_greater(0)
	_land.step()
	# Half a step of frame time: no tick, alpha 0.5.
	_land.world.clock.advance(SimClock.STEP * 0.5)
	_views.draw()
	var drawn := _views.node_for(id).transform
	print(
		(
			"alpha %.2f drawn %s want %s"
			% [_land.world.clock.alpha, drawn.origin, _views.pose_at(id, 0.5).origin]
		)
	)
	assert_float(_land.world.clock.alpha).is_equal_approx(0.5, 0.001)
	assert_vector(drawn.origin).is_equal_approx(_views.pose_at(id, 0.5).origin, Vector3.ONE * 0.001)
	assert_vector(drawn.origin).is_not_equal(_views.pose_at(id, 1.0).origin)


func test_a_car_pulling_into_a_berth_is_drawn_in_the_berth_not_between() -> void:
	var on_road := {}
	var arrived := 0
	while _land.sim.tick < LIMIT and arrived == 0:
		for id in _land.landside.vehicle_ids():
			on_road[id] = _land.landside.get_vehicle(id).lane == LandsideVehicle.Lane.ROAD_IN
		_land.step()
		for id in _land.landside.vehicle_ids():
			var v := _land.landside.get_vehicle(id)
			if v.lane == LandsideVehicle.Lane.BERTH and on_road.get(id, false):
				arrived = id
	assert_int(arrived).is_greater(0)
	var v := _land.landside.get_vehicle(arrived)
	var berth := _land.landside.definition.curb.berths[v.stop]
	print(
		(
			"vehicle %d in berth %d at %s drawn at alpha 0 %s"
			% [arrived, v.stop, berth, _views.pose_at(arrived, 0.0).origin]
		)
	)
	assert_vector(_views.pose_at(arrived, 0.0).origin).is_equal_approx(berth, Vector3.ONE * 0.001)
	assert_float(_views.pose_at(arrived, 0.0).basis.z.x).is_less(-0.99)


func test_snap_draws_the_state_now_with_nothing_between() -> void:
	var id := _first_driving()
	_land.step()
	assert_vector(_views.pose_at(id, 0.0).origin).is_not_equal(_views.pose_at(id, 1.0).origin)
	_views.selected_id = id
	_views.snap()
	assert_vector(_views.pose_at(id, 0.0).origin).is_equal_approx(
		_views.pose_at(id, 1.0).origin, Vector3.ONE * 0.0001
	)
	assert_int(_views.selected_id).is_equal(0)
	assert_int(_views.vehicle_count()).is_greater(0)


func test_a_frame_that_runs_three_ticks_draws_between_the_last_two() -> void:
	var id := _first_driving()
	assert_int(id).is_greater(0)
	var seen: Array[int] = []
	var v := _land.landside.get_vehicle(id)
	_land.world.clock.ticked.connect(func(_tick: int) -> void: seen.append(v.pos_mm))
	_land.world.clock.set_speed(3)
	_land.world.clock.advance(SimClock.STEP)
	var road := _land.landside.definition.road_in
	print("three ticks in one frame: mm %s" % [seen])
	assert_int(seen.size()).is_equal(3)
	assert_int(seen[2]).is_greater(seen[1])
	assert_vector(_views.pose_at(id, 0.0).origin).is_equal_approx(
		LandsideDefinition.point_at(road, seen[1]), Vector3.ONE * 0.001
	)
	assert_vector(_views.pose_at(id, 1.0).origin).is_equal_approx(
		LandsideDefinition.point_at(road, seen[2]), Vector3.ONE * 0.001
	)


func test_a_lot_built_while_paused_shows_on_the_next_frame() -> void:
	_views.draw()
	assert_object(_views.places().lot_node(0)).is_null()
	assert_bool(_land.landside.build_lot(0)).is_true()
	_views.draw()
	assert_object(_views.places().lot_node(0)).is_not_null()


func test_selecting_a_vehicle_moves_the_anchor_to_it_at_once() -> void:
	var id := _first_driving()
	assert_int(id).is_greater(0)
	_views.select(id)
	assert_int(_views.selected_id).is_equal(id)
	assert_vector(_views.follow_anchor.position).is_equal(_views.node_for(id).position)
	assert_vector(_views.follow_anchor.position).is_not_equal(Vector3.ZERO)
	_views.select(987654)
	assert_int(_views.selected_id).is_equal(0)
