class_name TestPassengerShellWalk
extends GdUnitTestSuite
## Passengers in the Toon terminal shell walk the door connections' outside
## routes: from the road through landside door B into the player's terminal
## (stage SPAWNED until they stand on the entrance cell), and out of gate C's
## door along the apron to the plane. The lateness forecast counts the road
## walk, a save taken on the road plays out the same, and a passenger makes
## the flight along the whole path.

const SHELL := preload("res://build/toon_terminal_shell.tres")
const LANDSIDE_B := Vector2i(16, 29)
const GATE_C := Vector2i(16, 0)
const GATE_C_DOORWAY := Vector2(-16.99, -95.25)
const LANDSIDE_B_DOORWAY := Vector2(-16.99, -64.35)
const PLANE_DOOR := Vector2(-14.5, -106.5)
const LAST_TICK := 1900

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_world = _shell_world()


func after_test() -> void:
	_world.free_all()
	_world = null


## Floor on columns 12 to 20, every row: entrance at landside B, a desk and a
## scanner on the way, the exit at gate C, no seats (passengers stand).
func _shell_world() -> PassengerTestWorld:
	var grid := BuildGrid.new(SHELL.grid_size, SHELL.grid_origin)
	for y in SHELL.grid_size.y:
		for x in range(12, 21):
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	PassengerTestWorld.place(grid, &"entrance_door", LANDSIDE_B, 2)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(13, 20), 0)
	PassengerTestWorld.place(grid, &"security_scanner", Vector2i(16, 10), 0)
	PassengerTestWorld.place(grid, &"exit_door", GATE_C, 0)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	world.sim.shell = SHELL
	return world


func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func test_a_new_passenger_starts_on_the_road_and_walks_in_through_door_b() -> void:
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	var start := _world.sim.world_position(p)
	var road_ticks := JourneyForecast.walk_ticks(p.apron_total_mm())
	print("ROAD start=%s apron_points=%d total_mm=%d" % [start, p.apron.size(), p.apron_total_mm()])
	assert_int(p.stage).is_equal(Passenger.Stage.SPAWNED)
	assert_float(start.z).is_greater(-60.3)
	assert_float(start.y).is_less(0.25)
	var crossed_doorway := false
	var ticks := 0
	while p.stage == Passenger.Stage.SPAWNED and ticks < 400:
		_world.step()
		ticks += 1
		var at := _xz(_world.sim.world_position(p))
		if at.distance_to(LANDSIDE_B_DOORWAY) < 0.1:
			crossed_doorway = true
	print("ROAD arrival ticks=%d stage=%d at=%s" % [ticks, p.stage, p.at])
	assert_bool(crossed_doorway).is_true()
	assert_int(p.stage).is_equal(Passenger.Stage.TO_CHECKIN)
	assert_vector(p.at).is_equal(LANDSIDE_B)
	assert_array(p.apron).is_empty()
	# At a walk, 98 mm a tick, plus the tick that turns it to check-in.
	assert_int(road_ticks).is_greater(80)
	assert_int(ticks).is_between(road_ticks, road_ticks + 2)


## Spawned once boarding is open, nothing waits on boarding, so the road
## still ahead adds exactly its own walking ticks to the forecast: the walk
## drops leftover distance where the road meets the grid, so the road and the
## indoor walk round up to whole ticks separately. Every road progress within
## one tick's step is tried, so a combined rounding cannot pass by luck.
func test_the_forecast_counts_the_road_walk_as_its_own_leg() -> void:
	_world.run_to(_world.flights.boarding_window(PassengerTestWorld.FLIGHT).x)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	var total := p.apron_total_mm()
	p.apron_mm = total
	var walked := JourneyForecast.arrival_tick(_world.sim, p)
	var exact := 0
	for done_mm in range(0, PassengerSim.WALK_MM):
		p.apron_mm = done_mm
		var road_ticks := JourneyForecast.walk_ticks(total - done_mm)
		var with_road := JourneyForecast.arrival_tick(_world.sim, p)
		assert_int(with_road - walked).is_equal(road_ticks)
		exact += int(with_road - walked == road_ticks)
	p.apron_mm = 0
	print(
		"FORECAST walked=%d total_mm=%d exact=%d/%d" % [walked, total, exact, PassengerSim.WALK_MM]
	)
	assert_int(exact).is_equal(PassengerSim.WALK_MM)


## An entrance or exit the shell does not know (only the debug starter
## terminal places one) walks the default route, with a warning.
func test_a_door_off_the_toon_doors_walks_the_default_route_with_a_warning() -> void:
	var stray := PassengerTestWorld.place(_world.grid, &"exit_door", Vector2i(20, 0), 0)
	# A lambda captures locals by value, so it fills an array it shares.
	var points: Array[Vector3] = []
	await (
		assert_error(func() -> void: points.append_array(ShellRoutes.departure(_world.sim, stray)))
		. is_push_warning(
			(
				"ShellRoutes: exit_door at (20, 0) is not on a Toon door;"
				+ " its passengers walk the default route"
			)
		)
	)
	var centre := _world.grid.cell_to_world(Vector2i(20, 0))
	assert_int(points.size()).is_equal(3 + _world.sim.apron_waypoints.size())
	assert_vector(points[0]).is_equal(centre)
	assert_vector(points[2]).is_equal(centre + Vector3(0.0, 0.0, -1.5))
	assert_vector(points[3]).is_equal(_world.sim.apron_waypoints[0])
	var stray_in := PassengerTestWorld.place(_world.grid, &"entrance_door", Vector2i(20, 29), 2)
	assert_array(ShellRoutes.arrival(_world.sim, stray_in)).is_empty()


func test_the_exit_walk_leaves_through_gate_c_to_the_plane_door() -> void:
	var exit_id := 0
	for id in _world.sim.layout.exits:
		exit_id = id
	var mm := _world.sim.apron_length_mm(exit_id)
	var walk := Passenger.new()
	walk.apron.assign(ShellRoutes.departure(_world.sim, exit_id))
	var first := _xz(walk.apron[0])
	var last := _xz(walk.apron[walk.apron.size() - 1])
	print("APRON points=%d mm=%d first=%s last=%s" % [walk.apron.size(), mm, first, last])
	assert_vector(first).is_equal_approx(_xz(_world.grid.cell_to_world(GATE_C)), Vector2.ONE * 1e-4)
	assert_float(last.distance_to(PLANE_DOOR)).is_less(0.01)
	var through_door := false
	for point in walk.apron:
		through_door = through_door or _xz(point).distance_to(GATE_C_DOORWAY) < 0.05
	assert_bool(through_door).is_true()
	assert_int(mm).is_equal(walk.apron_total_mm())
	assert_int(mm).is_between(12000, 20000)


func test_a_save_on_the_road_plays_out_the_same() -> void:
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	for i in 30:
		_world.step()
	var p := _world.passenger(id)
	assert_int(p.stage).is_equal(Passenger.Stage.SPAWNED)
	assert_int(p.apron_mm).is_greater(0)
	var saved := JSON.parse_string(JSON.stringify(_world.sim.to_snapshot())) as Dictionary
	var twin := _shell_world()
	twin.clock.from_snapshot(_world.clock.to_snapshot())
	twin.flights.from_snapshot(_world.flights.to_snapshot())
	assert_bool(twin.sim.from_snapshot(saved)).is_true()
	assert_vector(twin.sim.world_position(twin.passenger(id))).is_equal_approx(
		_world.sim.world_position(p), Vector3.ONE * 1e-4
	)
	for i in 200:
		_world.step()
		twin.step()
	assert_str(twin.signature()).is_equal(_world.signature())
	twin.free_all()


func test_a_passenger_walks_road_to_plane_and_makes_the_flight() -> void:
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	var stages := {}
	var on_apron_at := Vector2.INF
	while _world.clock.tick < LAST_TICK and not p.is_done():
		_world.step()
		stages[p.stage] = true
		if p.stage == Passenger.Stage.APRON and on_apron_at == Vector2.INF:
			on_apron_at = _xz(_world.sim.world_position(p))
	var keys := stages.keys()
	print("JOURNEY outcome_tick=%d stages=%s first_apron=%s" % [p.outcome_tick, keys, on_apron_at])
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)
	assert_int(_world.sim.made_count()).is_equal(1)
	for stage in [
		Passenger.Stage.CHECKIN,
		Passenger.Stage.SECURITY,
		Passenger.Stage.STANDING,
		Passenger.Stage.TO_EXIT,
		Passenger.Stage.APRON,
	]:
		assert_bool(stages.has(stage)).is_true()
	assert_float(on_apron_at.distance_to(_xz(_world.grid.cell_to_world(GATE_C)))).is_less(0.5)
	var end := _world.sim.world_position(p)
	assert_float(_xz(end).distance_to(PLANE_DOOR)).is_less(0.01)
