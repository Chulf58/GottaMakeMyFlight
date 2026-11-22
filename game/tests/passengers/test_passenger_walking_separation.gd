class_name TestPassengerWalkingSeparation
extends GdUnitTestSuite
## Wall-clamped right-hand corridor lane bias in PassengerViews / CorridorLane
## and occupied-queue avoidance with clean fallback in StationQueue.path_to().

const WIDE_SIZE := Vector2i(14, 7)

var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self
	var grid := PassengerTestWorld.floored(WIDE_SIZE)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 3), 3)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(13, 3), 1)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(60000, 80000))
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)


func after() -> void:
	_views.free()
	_world.free_all()
	PassengerTestWorld.tracker = null


func before_test() -> void:
	for id in _world.sim.passenger_ids():
		_world.passenger(id).stage = Passenger.Stage.MADE
	_world.step()


func _walker(stage: Passenger.Stage, path: Array[Vector2i], index: int, seg_mm := 0) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.stage = stage
	p.at = path[index]
	p.set_path(path)
	p.path_index = index
	p.seg_mm = seg_mm
	return p


func test_opposite_walkers_in_wide_corridor_separate_onto_right_hand_lanes() -> void:
	var east_path: Array[Vector2i] = []
	var west_path: Array[Vector2i] = []
	for x in range(2, 12):
		east_path.append(Vector2i(x, 3))
		west_path.append(Vector2i(13 - x, 3))
	# Both are mid-corridor at x = 6 (far from endpoints and doors).
	var east := _walker(Passenger.Stage.TO_GATE, east_path, 4)
	var west := _walker(Passenger.Stage.TO_CHECKIN, west_path, 5)
	_views.snap()
	var off_e := _views.corridor_offset(east.id)
	var off_w := _views.corridor_offset(west.id)
	print("east offset %s, west offset %s" % [off_e, off_w])
	# Walking east (+x) shifts right (+z, south); walking west (-x) shifts right (-z, north).
	assert_float(off_e.z).is_equal_approx(CorridorLane.LANE_OFFSET_M, 0.005)
	assert_float(off_w.z).is_equal_approx(-CorridorLane.LANE_OFFSET_M, 0.005)
	var drawn_e := _views.tick_position(east.id, true)
	var drawn_w := _views.tick_position(west.id, true)
	var lateral_gap := absf(drawn_e.z - drawn_w.z)
	assert_float(lateral_gap).is_greater_equal(CorridorLane.LANE_OFFSET_M * 1.9)


func test_right_hand_wall_and_obstacle_clamp_offset_to_walkable_clearance() -> void:
	# South wall along y = 4 (right side for eastbound along y = 3) clamps offset to 0.
	var walled := PassengerTestWorld.floored(Vector2i(12, 7))
	PassengerTestWorld.place(walled, &"entrance_door", Vector2i(0, 3), 3)
	for x in range(1, 11):
		walled.apply(BuildEdit.place_wall(Vector2i(x, 3), BuildGrid.Side.SOUTH))
	# Also place a solid desk beside y = 2 at (8, 1) (interaction cell (8, 2)) to check obstacles.
	PassengerTestWorld.place(walled, &"checkin_desk", Vector2i(8, 1), 0)
	var w_world := PassengerTestWorld.make(walled, PassengerTestWorld.starts_with(60000, 80000))
	var east_path: Array[Vector2i] = []
	var west_path: Array[Vector2i] = []
	for x in range(1, 11):
		east_path.append(Vector2i(x, 3))
		west_path.append(Vector2i(11 - x, 3))
	var east := w_world.passenger(w_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	east.stage = Passenger.Stage.TO_GATE
	east.at = east_path[4]
	east.set_path(east_path)
	east.path_index = 4
	# Opposite walker has open floor on its right (north, y = 2), so it still takes its lane.
	var west := w_world.passenger(w_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	west.stage = Passenger.Stage.TO_CHECKIN
	west.at = west_path[5]
	west.set_path(west_path)
	west.path_index = 5
	var clamped := CorridorLane.target_offset(w_world.sim, east)
	var open_side := CorridorLane.target_offset(w_world.sim, west)
	print("beside south wall: east=%s, west=%s" % [clamped, open_side])
	assert_vector(clamped).is_equal(Vector3.ZERO)
	assert_float(open_side.z).is_equal_approx(-CorridorLane.LANE_OFFSET_M, 0.005)
	# Passing directly beside the solid desk footprint at (8, 1) heading west along y = 2 clamps to 0.
	var by_desk_path: Array[Vector2i] = []
	for x in range(11, 1, -1):
		by_desk_path.append(Vector2i(x, 2))
	var by_desk := w_world.passenger(w_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	by_desk.stage = Passenger.Stage.TO_GATE
	by_desk.at = Vector2i(8, 2)
	by_desk.set_path(by_desk_path)
	by_desk.path_index = 3
	assert_vector(CorridorLane.target_offset(w_world.sim, by_desk)).is_equal(Vector3.ZERO)
	# A 1-tile corridor (walled on both north and south) clamps both directions to 0.
	for x in range(1, 11):
		walled.apply(BuildEdit.place_wall(Vector2i(x, 3), BuildGrid.Side.NORTH))
	assert_vector(CorridorLane.target_offset(w_world.sim, east)).is_equal(Vector3.ZERO)
	assert_vector(CorridorLane.target_offset(w_world.sim, west)).is_equal(Vector3.ZERO)
	w_world.free_all()


func test_offset_fades_to_zero_while_moving_to_endpoint_and_in_excluded_states() -> void:
	var path: Array[Vector2i] = []
	for x in range(1, 13):
		path.append(Vector2i(x, 3))
	# Active moving passenger approaching path[-1]: within ENDPOINT_FADE_M, offset
	# shrinks monotonically toward 0 while p.is_moving() is still true.
	var mover := _walker(Passenger.Stage.TO_GATE, path, 6)
	_views.snap()
	var lengths: Array[float] = []
	while mover.is_moving():
		var rem_m := mover.remaining_mm() / 1000.0
		if rem_m <= CorridorLane.ENDPOINT_FADE_M and rem_m > 0.0:
			lengths.append(_views.corridor_offset(mover.id).length())
		mover.walk(PassengerSim.WALK_MM)
		_views.sync()
	print("endpoint fade lengths (%d ticks): %s" % [lengths.size(), lengths])
	assert_int(lengths.size()).is_greater(10)
	for i in range(1, lengths.size()):
		assert_float(lengths[i]).is_less_equal(lengths[i - 1] + 1e-5)
	assert_float(lengths[lengths.size() - 1]).is_less(0.03)
	assert_vector(_views.corridor_offset(mover.id)).is_equal(Vector3.ZERO)
	# Queue, stationary, and seated stages: strictly 0 immediately (no chase lag).
	var still := _walker(Passenger.Stage.TO_GATE, path, 6)
	_views.snap()
	assert_float(_views.corridor_offset(still.id).length()).is_greater(0.15)
	for stage in [
		Passenger.Stage.CHECKIN_QUEUE,
		Passenger.Stage.CHECKIN,
		Passenger.Stage.SECURITY_QUEUE,
		Passenger.Stage.SECURITY,
		Passenger.Stage.STANDING,
		Passenger.Stage.SEATED,
		Passenger.Stage.CAFE_QUEUE,
		Passenger.Stage.CAFE_SEATED,
		Passenger.Stage.TOILET_USE,
		Passenger.Stage.SHOP_BROWSE,
	]:
		still.stage = stage
		_views.sync()
		assert_vector(_views.corridor_offset(still.id)).is_equal(Vector3.ZERO)


func test_rendered_clearance_during_chase_narrowing_corner_snap_and_release() -> void:
	# Wide open west half (x = 1..5) narrowing into a right-wall-bounded
	# corridor (x = 6..10, south wall along y = 3) and a 90-degree turn south
	# down x = 10 with an east wall (right side while walking south -> west!).
	var grid := PassengerTestWorld.floored(Vector2i(13, 9))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 3), 3)
	for x in range(6, 10):
		grid.apply(BuildEdit.place_wall(Vector2i(x, 3), BuildGrid.Side.SOUTH))
	for y in range(4, 8):
		grid.apply(BuildEdit.place_wall(Vector2i(10, y), BuildGrid.Side.WEST))
	var w := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(60000, 80000))
	var views := PassengerTestWorld.views()
	views.clock = w.clock
	views.sim = w.sim
	add_child(views)
	var turn_path: Array[Vector2i] = [
		Vector2i(1, 3),
		Vector2i(2, 3),
		Vector2i(3, 3),
		Vector2i(4, 3),
		Vector2i(5, 3),
		Vector2i(6, 3),
		Vector2i(7, 3),
		Vector2i(8, 3),
		Vector2i(9, 3),
		Vector2i(10, 3),
		Vector2i(10, 4),
		Vector2i(10, 5),
		Vector2i(10, 6),
		Vector2i(10, 7),
	]
	var p := w.passenger(w.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.stage = Passenger.Stage.TO_GATE
	p.at = turn_path[0]
	p.set_path(turn_path)
	var min_wall_clear := INF
	var peak_wide := 0.0
	var clamped_ticks := 0
	for tick in 140:
		if not p.is_moving():
			break
		p.walk(PassengerSim.WALK_MM)
		views.sync()
		var lane := views.corridor_offset(p.id)
		var base_2d := p.grid_position()
		var rendered_2d := base_2d + Vector2(lane.x, lane.z)
		if p.at.x >= 3 and p.at.x <= 4:
			peak_wide = maxf(peak_wide, lane.length())
		if p.at.x >= 7 and p.at.x <= 9:
			clamped_ticks += int(lane.length() < 0.01)
		var under := Vector2i(floori(base_2d.x), floori(base_2d.y))
		for rect: Rect2 in CorridorLane._obstacles_near(grid, under):
			var base_dist := CorridorLane._dist_to_rect(base_2d, rect)
			var rend_dist := CorridorLane._dist_to_rect(rendered_2d, rect)
			var req := minf(CorridorLane.CLEARANCE_M, base_dist)
			assert_float(rend_dist).is_greater_equal(req - 1e-4)
			min_wall_clear = minf(min_wall_clear, rend_dist)
	print(
		(
			"narrowing chase: peak wide %.3f m, clamped ticks %d, min wall clear %.3f m"
			% [peak_wide, clamped_ticks, min_wall_clear]
		)
	)
	assert_float(peak_wide).is_greater(0.15)
	assert_int(clamped_ticks).is_greater(10)
	# snap() continuity: mid-corridor walker snaps to steady-state target without pop.
	p.stage = Passenger.Stage.TO_GATE
	p.at = turn_path[4]
	p.set_path(turn_path)
	p.path_index = 4
	p.seg_mm = 0
	views.snap()
	var target := CorridorLane.target_offset(w.sim, p)
	assert_vector(views.corridor_offset(p.id)).is_equal_approx(target, Vector3.ONE * 1e-5)
	assert_vector(views.tick_position(p.id, false)).is_equal_approx(
		views.tick_position(p.id, true), Vector3.ONE * 1e-5
	)
	assert_vector(views.tick_position(p.id, true)).is_equal_approx(
		views.draw_position(p), Vector3.ONE * 1e-5
	)
	# Immediate drop to 0 on FileWaiters entry and _release(id) cleanup on MADE.
	p.stage = Passenger.Stage.TO_EXIT
	w.sim.files.waiters._spots[p.id] = {"off": Vector2i(0, 700), "at": 700, "out": true}
	views.sync()
	assert_vector(views.corridor_offset(p.id)).is_equal(Vector3.ZERO)
	w.sim.files.waiters._spots.erase(p.id)
	p.stage = Passenger.Stage.MADE
	views.sync()
	assert_object(views.node_for(p.id)).is_null()
	assert_vector(views.corridor_offset(p.id)).is_equal(Vector3.ZERO)
	assert_bool(views._lanes.has(p.id)).is_false()
	views.free()
	w.free_all()


func test_station_queue_path_to_detours_around_occupied_cells_and_falls_back_in_choke() -> void:
	# Wide room: line runs down column 3 from (3, 1) to (3, 5).
	var grid := PassengerTestWorld.floored(Vector2i(7, 7))
	var line: Array[Vector2i] = [
		Vector2i(3, 1),
		Vector2i(3, 2),
		Vector2i(3, 3),
		Vector2i(3, 4),
		Vector2i(3, 5),
	]
	# Walker from (1, 2) heading to line[4] avoids occupied line[0..3].
	var detour := StationQueue.path_to(grid, line, Vector2i(1, 2), 4)
	print("off-line detour: %s" % [detour])
	assert_array(detour).is_not_empty()
	assert_that(detour[0]).is_equal(Vector2i(1, 2))
	assert_that(detour[detour.size() - 1]).is_equal(line[4])
	for i in range(1, detour.size()):
		var at := line.find(detour[i])
		assert_bool(at >= 0 and at < 4).is_false()
	# Walker standing on line[1] heading back to line[4] also detours around line[2..3].
	var on_line_detour := StationQueue.path_to(grid, line, line[1], 4)
	print("on-line ahead detour: %s" % [on_line_detour])
	assert_array(on_line_detour).is_not_empty()
	assert_that(on_line_detour[on_line_detour.size() - 1]).is_equal(line[4])
	for i in range(1, on_line_detour.size()):
		var at := line.find(on_line_detour[i])
		assert_bool(at >= 0 and at < 4).is_false()
	# Choke (1-tile corridor): no detour exists, so path_to falls back cleanly without stranding.
	var choke := PassengerTestWorld.floored(Vector2i(1, 6))
	var choke_line: Array[Vector2i] = [
		Vector2i(0, 1),
		Vector2i(0, 2),
		Vector2i(0, 3),
		Vector2i(0, 4),
		Vector2i(0, 5),
	]
	var fallback := StationQueue.path_to(choke, choke_line, Vector2i(0, 0), 3)
	print("choke fallback: %s" % [fallback])
	assert_array(fallback).is_equal(
		[Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4)]
	)
