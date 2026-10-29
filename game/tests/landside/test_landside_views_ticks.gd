class_name TestLandsideViewsTicks
extends GdUnitTestSuite
## LandsideViews draws each car between its last two ticks with the clock's
## alpha (decision sim-architecture-fixed-tick-data-records-snapshot-saves-
## grid-astar): by distance along the lane or the berth's path it drives,
## through the clock's ticked signal after PassengerSim stepped the road. A car
## pulling into a berth is drawn along the berth's path, a short step a frame.
## snap() draws the state now with nothing between. The
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


## Until the berth's path carried a car in, a car that took a berth was drawn
## in it at once; now it is drawn along the path, from the road into the berth.
func test_a_car_pulling_into_a_berth_is_drawn_along_its_path_into_the_berth() -> void:
	var on_road := {}
	var turned := 0
	while _land.sim.tick < LIMIT and turned == 0:
		for id in _land.landside.vehicle_ids():
			on_road[id] = _land.landside.get_vehicle(id).lane == LandsideVehicle.Lane.ROAD_IN
		_land.step()
		for id in _land.landside.vehicle_ids():
			var v := _land.landside.get_vehicle(id)
			if v.lane == LandsideVehicle.Lane.BERTH and on_road.get(id, false):
				turned = id
	assert_int(turned).is_greater(0)
	var v := _land.landside.get_vehicle(turned)
	var path := _land.landside.paths.berth_path[v.stop]
	var berth := _land.landside.definition.curb.berths[v.stop]
	# On the tick it took the berth it still stands on the road, where it was.
	var start := _views.pose_at(turned, 1.0).origin
	print("vehicle %d took berth %d at %s, drawn at %s" % [turned, v.stop, berth, start])
	assert_vector(start).is_equal_approx(
		LandsideDefinition.point_at(path, v.pos_mm), Vector3.ONE * 0.001
	)
	assert_float(start.distance_to(berth)).is_greater(1.0)
	var last := start
	var ticks := 0
	while v.stage == LandsideVehicle.Stage.DRIVE and ticks < 100:
		_land.step()
		ticks += 1
		for alpha in [0.25, 0.5, 0.75, 1.0]:
			var at := _views.pose_at(turned, alpha).origin
			assert_float(at.distance_to(last)).is_less_equal(LandsideSim.SPEED_MM / 1000.0 + 0.001)
			last = at
	print("pulled in after %d ticks, drawn at %s" % [ticks, last])
	assert_int(v.stage).is_equal(LandsideVehicle.Stage.DWELL)
	assert_int(ticks).is_greater(1)
	assert_vector(_views.pose_at(turned, 1.0).origin).is_equal_approx(berth, Vector3.ONE * 0.001)
	assert_float(_views.pose_at(turned, 1.0).basis.z.x).is_less(-0.99)


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
