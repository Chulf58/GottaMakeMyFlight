class_name TestBenchSeating
extends GdUnitTestSuite
## bench_1a (1x3, mesh z in [-0.96, 0.98], backrest +X, open front -X at facing 0)
## provides two gate seats at its outer cells (indices 0 and 2), shifted 0.50 m
## inward onto the bench slats, and reloads cleanly through GateRelocation.

const SIZE := Vector2i(14, 14)

var _world: PassengerTestWorld
var _other: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in [_world, _other]:
		if world != null:
			world.free_all()
	_world = null
	_other = null


func test_bench_1a_registers_two_outward_seats_across_all_4_facings() -> void:
	var grid := PassengerTestWorld.floored(SIZE)
	var anchors: Array[Vector2i] = [
		Vector2i(3, 2), Vector2i(10, 3), Vector2i(9, 10), Vector2i(2, 9)
	]
	var expected_fronts := [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1)]
	var bench_ids: Array[int] = []
	for facing in 4:
		bench_ids.append(PassengerTestWorld.place(grid, &"bench_1a", anchors[facing], facing))
	var layout := TerminalLayout.new()
	layout.rebuild(grid)
	assert_int(layout.seats.size()).is_equal(8)
	for facing in 4:
		var bid := bench_ids[facing]
		var def := BuildCatalog.get_def(&"bench_1a")
		var cells := def.footprint(anchors[facing], facing)
		var mine := layout.seats.filter(func(s: Dictionary) -> bool: return s["object_id"] == bid)
		assert_int(mine.size()).is_equal(2)
		assert_vector(Vector2(mine[0]["cell"])).is_equal(Vector2(cells[0]))
		assert_vector(Vector2(mine[1]["cell"])).is_equal(Vector2(cells[2]))
		for seat in mine:
			assert_vector(Vector2(seat["front"] - seat["cell"])).is_equal(
				Vector2(expected_fronts[facing])
			)
	# Clearing the floor on seat 0's front cell (facing 0) drops only that seat.
	var blocked_front := anchors[0] + Vector2i(-1, 0)
	assert_bool(grid.apply(BuildEdit.remove_floor(blocked_front)).ok).is_true()
	layout.rebuild(grid)
	var remaining := layout.seats.filter(
		func(s: Dictionary) -> bool: return s["object_id"] == bench_ids[0]
	)
	assert_int(remaining.size()).is_equal(1)
	assert_vector(Vector2(remaining[0]["cell"])).is_equal(Vector2(anchors[0] + Vector2i(0, 2)))


func test_seated_passengers_sit_on_bench_1a_facing_outward_without_backrest_clipping() -> void:
	var grid := PassengerTestWorld.floored(SIZE)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(1, 13), 2)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(1, 0), 0)
	var anchors: Array[Vector2i] = [
		Vector2i(3, 2), Vector2i(10, 3), Vector2i(9, 10), Vector2i(2, 9)
	]
	for facing in 4:
		PassengerTestWorld.place(grid, &"bench_1a", anchors[facing], facing)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var sim := _world.sim
	var views := PassengerTestWorld.views()
	views.sim = sim
	add_child(views)
	var def := BuildCatalog.get_def(&"bench_1a")
	assert_int(sim.layout.seats.size()).is_equal(8)
	# Compute actual tc_bench_1a.glb mesh span in bench-local space.
	var mesh_span := AABB()
	var first_part := true
	for part in InteriorKit.meshes(InteriorKit.object_piece(&"bench_1a")):
		var part_box := (part[1] as Transform3D) * (part[0] as Mesh).get_aabb()
		mesh_span = part_box if first_part else mesh_span.merge(part_box)
		first_part = false
	var pax_ids: Array[int] = []
	for i in sim.layout.seats.size():
		var seat: Dictionary = sim.layout.seats[i]
		var record := grid.get_object(seat["object_id"])
		var cells := def.footprint(record["anchor"], record["facing"])
		var bench_xf := BuildView.object_transform(grid, cells, record["facing"])
		var pid := sim.spawn_now(PassengerTestWorld.FLIGHT)
		pax_ids.append(pid)
		var p := sim.get_passenger(pid)
		p.variant = i % 2
		p.cleared = true
		p.stage = Passenger.Stage.SEATED
		p.seat_object = seat["object_id"]
		p.seat_cell = seat["cell"]
		p.seat_front = seat["front"]
		p.seat_piece = Relocation.placement(grid, seat["object_id"])
		p.at = seat["front"]
		p.clear_path()
		assert_bool(GateRelocation.valid(p)).is_true()
		var frame: Transform3D = GateChairs.seated_frame(sim, p)
		var local := bench_xf.affine_inverse() * frame.origin
		var expected_z := -0.50 if cells.find(seat["cell"]) == 0 else 0.50
		# In bench_1a local frame, backrest is at x >= +0.20 and open front is -X.
		assert_float(local.x).is_less(-0.45)
		assert_float(local.z).is_equal_approx(expected_z, 0.01)
		assert_float(local.z).is_greater(mesh_span.position.z + 0.35)
		assert_float(local.z).is_less(mesh_span.end.z - 0.35)
		var out_dir := (
			(grid.cell_to_world(seat["front"]) - grid.cell_to_world(seat["cell"])).normalized()
		)
		assert_float(frame.basis.z.normalized().dot(out_dir)).is_greater(0.999)
		assert_vector(views.draw_position(p)).is_equal_approx(frame.origin, Vector3.ONE * 0.01)
	views.snap()
	for i in sim.layout.seats.size():
		var seat: Dictionary = sim.layout.seats[i]
		var record := grid.get_object(seat["object_id"])
		var cells := def.footprint(record["anchor"], record["facing"])
		var bench_xf := BuildView.object_transform(grid, cells, record["facing"])
		var node := views._nodes.get(pax_ids[i]) as Node3D
		assert_object(node).is_not_null()
		var out_dir := (
			(grid.cell_to_world(seat["front"]) - grid.cell_to_world(seat["cell"])).normalized()
		)
		var node_forward := node.global_basis.z.slide(Vector3.UP).normalized()
		assert_float(node_forward.dot(out_dir)).is_greater(0.99)
		var node_local := bench_xf.affine_inverse() * node.global_position
		var expected_z := -0.50 if cells.find(seat["cell"]) == 0 else 0.50
		assert_float(node_local.z).is_equal_approx(expected_z, 0.01)
	views.free()


func test_bench_1a_roller_park_gate_roller_and_pull_side() -> void:
	var grid := PassengerTestWorld.floored(SIZE)
	var anchors: Array[Vector2i] = [
		Vector2i(3, 2), Vector2i(10, 3), Vector2i(9, 10), Vector2i(2, 9)
	]
	for facing in 4:
		PassengerTestWorld.place(grid, &"bench_1a", anchors[facing], facing)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var sim := _world.sim
	var def := BuildCatalog.get_def(&"bench_1a")
	for i in sim.layout.seats.size():
		var seat: Dictionary = sim.layout.seats[i]
		var record := grid.get_object(seat["object_id"])
		var cells := def.footprint(record["anchor"], record["facing"])
		var idx := cells.find(seat["cell"])
		var p := Passenger.new()
		p.id = 3000 + i
		p.variant = i % 2
		p.stage = Passenger.Stage.SEATED
		p.seat_object = seat["object_id"]
		p.seat_cell = seat["cell"]
		p.seat_front = seat["front"]
		p.seat_piece = Relocation.placement(grid, seat["object_id"])
		var out := Vector2(seat["front"] - seat["cell"])
		var expected_yaw := atan2(out.x, out.y)
		var actual_yaw := RollerPark.sit_face(sim, p)
		assert_float(absf(angle_difference(actual_yaw, expected_yaw))).is_less(0.001)
		var expected_slide := 0.50 if idx == 0 else -0.50
		assert_float(GateRoller.slide(p.seat_piece, p.seat_cell, p.seat_front)).is_equal_approx(
			expected_slide, 0.001
		)
		var spot := GateRoller.spot(p, 0)
		assert_float(absf(spot.origin.x)).is_greater(0.35)
	# PullSide.stamp_clear excludes bench_1a as gate seating along its front,
	# while a trash_can placed in the reach zone still fails stamp_clear.
	var mid_grid := PassengerTestWorld.floored(SIZE)
	PassengerTestWorld.place(mid_grid, &"bench_1a", Vector2i(7, 6), 0)
	var walk_pose := Transform3D(Basis(Vector3.UP, 0.0), mid_grid.cell_to_world(Vector2i(6, 6)))
	assert_bool(PullSide.stamp_clear(mid_grid, [walk_pose], 1)).is_true()
	(
		assert_bool(mid_grid.apply(BuildEdit.place_wall(Vector2i(6, 5), BuildGrid.Side.WEST)).ok)
		. is_true()
	)
	assert_bool(PullSide.stamp_clear(mid_grid, [walk_pose], 0)).is_false()


func test_bench_1a_seated_passenger_survives_save_load_round_trip() -> void:
	var grid := PassengerTestWorld.floored(SIZE)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(2, 13), 2)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(2, 0), 0)
	var bench_id := PassengerTestWorld.place(grid, &"bench_1a", Vector2i(7, 5), 0)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(900, 1600))
	_world.sim.apron_waypoints = PackedVector3Array()
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.cleared = true
	p.hunger = 0
	p.boredom = 0
	p.toilet_need = 0
	p.stage = Passenger.Stage.TO_GATE
	p.at = Vector2i(5, 6)
	p.clear_path()
	while p.stage != Passenger.Stage.SEATED and _world.clock.tick < 400:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SEATED)
	assert_int(p.seat_object).is_equal(bench_id)
	assert_str(String(p.seat_piece["def"])).is_equal("bench_1a")
	assert_bool(GateRelocation.valid(p)).is_true()

	var save := {
		"clock": _world.clock.to_snapshot(),
		"flights": _world.flights.to_snapshot(),
		"grid": _world.grid.to_snapshot(),
		"passengers": _world.sim.to_snapshot(),
		"wallet": _world.sim.wallet.to_snapshot(),
	}
	var data: Dictionary = JSON.parse_string(JSON.stringify(save))
	var grid_b := BuildGrid.new()
	assert_bool(grid_b.from_snapshot(data["grid"])).is_true()
	_other = PassengerTestWorld.make(grid_b, PassengerTestWorld.starts_with(900, 1600))
	_other.sim.apron_waypoints = PackedVector3Array()
	assert_bool(_other.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(_other.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(_other.sim.from_snapshot(data["passengers"])).is_true()
	assert_bool(_other.sim.wallet.from_snapshot(data["wallet"])).is_true()

	var q := _other.passenger(p.id)
	assert_int(q.stage).is_equal(Passenger.Stage.SEATED)
	assert_str(String(q.seat_piece["def"])).is_equal("bench_1a")
	assert_vector(Vector2(q.seat_cell)).is_equal(Vector2(p.seat_cell))
	assert_vector(Vector2(q.seat_front)).is_equal(Vector2(p.seat_front))
	assert_bool(GateRelocation.valid(q)).is_true()

	var end := _world.flights.doors_close_tick(PassengerTestWorld.FLIGHT) + 1
	_world.run_to(end)
	_other.run_to(end)
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)
	assert_int(q.stage).is_equal(Passenger.Stage.MADE)
	assert_str(_other.signature()).is_equal(_world.signature())
