class_name TestPassengerSiteWalk
extends GdUnitTestSuite
## Passengers on the airport site walk SiteRoutes' walks outside: from the
## road over open ground through the entrance's doorway into the terminal
## (stage SPAWNED until they stand on the entrance cell), and out of the
## exit's doorway over open ground to the plane door. The lateness forecast
## counts the road walk as its own leg, a save taken on the road plays out the
## same tick for tick, and a passenger makes the flight along the whole path.
## With no site (a test grid) an exit walks the default route
## (OutsideWalks._default_departure) and an entrance has no road walk.

const SITE := preload("res://build/terminal_site.tres")
const ENTRANCE := Vector2i(16, 29)
const EXIT := Vector2i(16, 0)
## The site's plane door, the last point of its plane route.
const PLANE_DOOR := Vector2(-14.5, -106.5)
const LAST_TICK := 1900

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_world = _site_world()


func after_test() -> void:
	_world.free_all()
	_world = null


## Floor on columns 12 to 20, rows 0 to 29 of the site grid (rows 30 to 39 are
## open ground to the road): the entrance on the south edge, a desk and a
## scanner on the way, the exit on the north edge, no seats (passengers
## stand), walled in.
func _site_world() -> PassengerTestWorld:
	var grid := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	for y in range(0, 30):
		for x in range(12, 21):
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	PassengerTestWorld.place(grid, &"entrance_door", ENTRANCE, 2)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(13, 20), 0)
	PassengerTestWorld.place(grid, &"security_scanner", Vector2i(16, 10), 0)
	PassengerTestWorld.place(grid, &"exit_door", EXIT, 0)
	# Walls close the floor in, the doors filling their gaps (TerminalEnclosure).
	EnclosureKit.close_floor(grid)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	world.sim.site = SITE
	return world


func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## The middle of a door cell's back edge, where its walk outside crosses.
func _doorway(cell: Vector2i, facing: int) -> Vector2:
	var out := DoorPlacement.back_step(facing)
	return _xz(_world.grid.cell_to_world(cell) + Vector3(out.x, 0.0, out.y) * 0.5)


func test_a_new_passenger_starts_on_the_road_and_walks_in_through_the_entrance() -> void:
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	var start := _world.sim.world_position(p)
	var road_ticks := JourneyForecast.walk_ticks(p.apron_total_mm())
	print("ROAD start=%s apron_points=%d total_mm=%d" % [start, p.apron.size(), p.apron_total_mm()])
	assert_int(p.stage).is_equal(Passenger.Stage.SPAWNED)
	assert_float(start.z).is_equal_approx(SITE.road_z, 0.01)
	assert_float(start.y).is_less(0.25)
	var doorway := _doorway(ENTRANCE, 2)
	var crossed_doorway := false
	var ticks := 0
	while p.stage == Passenger.Stage.SPAWNED and ticks < 400:
		_world.step()
		ticks += 1
		if _xz(_world.sim.world_position(p)).distance_to(doorway) < 0.1:
			crossed_doorway = true
	print("ROAD arrival ticks=%d road_ticks=%d stage=%d at=%s" % [ticks, road_ticks, p.stage, p.at])
	assert_bool(crossed_doorway).is_true()
	assert_int(p.stage).is_equal(Passenger.Stage.TO_CHECKIN)
	assert_vector(p.at).is_equal(ENTRANCE)
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
	assert_int(total).is_greater(PassengerSim.WALK_MM)
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


## With no site an exit walks out through its doorway, a metre on, then the
## default apron waypoints, and an entrance has no road walk.
func test_with_no_site_an_exit_walks_the_default_route() -> void:
	_world.sim.site = null
	var exit_id: int = _world.sim.layout.exits[0]
	var entrance_id: int = _world.sim.layout.entrances[0]
	var points := OutsideWalks.departure(_world.sim, exit_id)
	var centre := _world.grid.cell_to_world(EXIT)
	print("DEFAULT points=%d first=%s third=%s" % [points.size(), points[0], points[2]])
	assert_int(points.size()).is_equal(3 + _world.sim.apron_waypoints.size())
	assert_vector(points[0]).is_equal(centre)
	assert_vector(points[1]).is_equal(centre + Vector3(0.0, 0.0, -0.5))
	assert_vector(points[2]).is_equal(centre + Vector3(0.0, 0.0, -1.5))
	assert_vector(points[3]).is_equal(_world.sim.apron_waypoints[0])
	var waypoints := _world.sim.apron_waypoints
	assert_vector(points[points.size() - 1]).is_equal(waypoints[waypoints.size() - 1])
	assert_array(OutsideWalks.arrival(_world.sim, entrance_id)).is_empty()
	# An id that is no door has no walk at all.
	assert_array(OutsideWalks.departure(_world.sim, 9999)).is_empty()


func test_the_exit_walk_leaves_through_its_doorway_to_the_plane_door() -> void:
	var exit_id: int = _world.sim.layout.exits[0]
	var mm := _world.sim.apron_length_mm(exit_id)
	var walk := Passenger.new()
	walk.apron.assign(OutsideWalks.departure(_world.sim, exit_id))
	var first := _xz(walk.apron[0])
	var last := _xz(walk.apron[walk.apron.size() - 1])
	print("APRON points=%d mm=%d first=%s last=%s" % [walk.apron.size(), mm, first, last])
	assert_vector(first).is_equal_approx(_xz(_world.grid.cell_to_world(EXIT)), Vector2.ONE * 1e-4)
	assert_float(last.distance_to(PLANE_DOOR)).is_less(0.01)
	var doorway := _doorway(EXIT, 0)
	var through_door := false
	for point in walk.apron:
		through_door = through_door or _xz(point).distance_to(doorway) < 0.05
	assert_bool(through_door).is_true()
	assert_int(mm).is_equal(walk.apron_total_mm())
	# The exit (x -26.5) is 12 m west of the plane route (x -14.5), which runs
	# 7 m out to the plane door.
	assert_int(mm).is_between(18000, 24000)


## A save taken on the road loads into a twin world, and the twin then plays
## every tick the same as the world that kept running.
func test_a_save_on_the_road_plays_out_the_same_tick_for_tick() -> void:
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	for i in 30:
		_world.step()
	var p := _world.passenger(id)
	assert_int(p.stage).is_equal(Passenger.Stage.SPAWNED)
	assert_int(p.apron_mm).is_greater(0)
	var saved := JSON.parse_string(JSON.stringify(_world.sim.to_snapshot())) as Dictionary
	var twin := _site_world()
	twin.clock.from_snapshot(_world.clock.to_snapshot())
	twin.flights.from_snapshot(_world.flights.to_snapshot())
	assert_bool(twin.sim.from_snapshot(saved)).is_true()
	assert_vector(twin.sim.world_position(twin.passenger(id))).is_equal_approx(
		_world.sim.world_position(p), Vector3.ONE * 1e-4
	)
	var same := 0
	var first_diff := -1
	for i in 200:
		_world.step()
		twin.step()
		if twin.signature() == _world.signature():
			same += 1
		elif first_diff < 0:
			first_diff = i
	print("TWIN same=%d/200 first_diff=%d stage=%d" % [same, first_diff, p.stage])
	# The walk in ends inside the 200 ticks, so both sides of it are compared.
	assert_int(p.stage).is_not_equal(Passenger.Stage.SPAWNED)
	assert_int(same).is_equal(200)
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
	assert_float(on_apron_at.distance_to(_xz(_world.grid.cell_to_world(EXIT)))).is_less(0.5)
	var end := _world.sim.world_position(p)
	assert_float(_xz(end).distance_to(PLANE_DOOR)).is_less(0.01)
