class_name TestRollerFollowingSpacing
extends GdUnitTestSuite
## Regression tests for board cca1327b: EntranceLine, BoardingFiles, and
## same-direction walking streams keep at least 1.25 m (1250 mm) center-to-
## center behind a leader pulling a roller suitcase, without breaking opposite-
## direction corridor passing or forecasts.

const SITE := preload("res://build/terminal_site.tres")
const MIN_ROLLER_CLEAR_M := 1.25

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


func _roller_guest(world: PassengerTestWorld) -> Passenger:
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	world.sim.entrance.forget(p.id)
	while SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.ROLLER:
		p.carry_on = 0
		p.stage = Passenger.Stage.MADE
		p = world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		world.sim.entrance.forget(p.id)
	ToiletTestLayout.calm(p)
	p.carry_on = 1
	p.liquids = false
	p.alarm = false
	return p


func _plain_guest(world: PassengerTestWorld) -> Passenger:
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	world.sim.entrance.forget(p.id)
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	return p


func _apart_2d(world: PassengerTestWorld, a: Passenger, b: Passenger) -> float:
	var pa := world.sim.world_position(a)
	var pb := world.sim.world_position(b)
	return Vector2(pa.x, pa.z).distance_to(Vector2(pb.x, pb.z))


func test_entrance_line_admitted_follower_clears_leaders_pulled_roller() -> void:
	var grid := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	assert_bool(ReferenceTerminal.build(grid, SITE.starter_offset)).is_true()
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 19)
	_world.sim.site = SITE
	_world.step()

	var leader := _roller_guest(_world)
	var follower := _plain_guest(_world)
	assert_bool(QueueRipple.pulls_roller(leader)).is_true()
	var walk := OutsideWalks.arrival(_world.sim, _world.sim.layout.passenger_entrances[0])
	assert_int(walk.size()).is_greater_equal(2)

	leader.apron = walk.duplicate()
	leader.apron_mm = 1500
	follower.apron = walk.duplicate()
	follower.apron_mm = 0
	_world.sim.entrance.take(_world.sim, leader)
	_world.sim.entrance.take(_world.sim, follower)
	assert_bool(_world.sim.entrance.has_claim(leader.id)).is_true()
	assert_bool(_world.sim.entrance.has_claim(follower.id)).is_true()

	# Force the follower to run so it catches up to the leader's gap limit.
	follower.late = true
	var min_apart := INF
	var both_walking := 0
	for _i in 150:
		_world.step()
		if (
			leader.stage in [Passenger.Stage.SPAWNED, Passenger.Stage.TO_CHECKIN]
			and follower.stage == Passenger.Stage.SPAWNED
		):
			both_walking += 1
			min_apart = minf(min_apart, _apart_2d(_world, leader, follower))
		if follower.stage != Passenger.Stage.SPAWNED:
			break

	print("entrance line min_apart=%.3f m over %d ticks" % [min_apart, both_walking])
	assert_int(both_walking).is_greater(5)
	assert_float(min_apart).is_greater_equal(MIN_ROLLER_CLEAR_M)
	assert_int(follower.stage).is_greater_equal(Passenger.Stage.TO_CHECKIN)


func test_boarding_files_follower_clears_leaders_pulled_roller_and_matches_forecast() -> void:
	_world = TestBoardingFiles.boarding_world()
	_world.run_to(TestBoardingFiles.BOARDING + 5)

	var leader := _roller_guest(_world)
	TestBoardingFiles.turn_out(_world, leader, Vector2i(20, 4))
	leader.carry_on = 1
	var follower := _plain_guest(_world)
	TestBoardingFiles.turn_out(_world, follower, Vector2i(20, 6))
	_world.step()
	follower.late = true

	var forecast := JourneyForecast.arrival_tick(_world.sim, follower)
	var min_apart := INF
	var samples := 0
	while not (leader.is_done() and follower.is_done()) and _world.clock.tick < 2000:
		_world.step()
		if TestBoardingFiles.heading_out(leader) and TestBoardingFiles.heading_out(follower):
			samples += 1
			min_apart = minf(min_apart, _apart_2d(_world, leader, follower))

	print(
		(
			"boarding min_apart=%.3f m over %d ticks, follower=%d forecast=%d"
			% [min_apart, samples, follower.outcome_tick, forecast]
		)
	)
	assert_int(samples).is_greater(20)
	assert_float(min_apart).is_greater_equal(MIN_ROLLER_CLEAR_M)
	assert_int(leader.stage).is_equal(Passenger.Stage.MADE)
	assert_int(follower.stage).is_equal(Passenger.Stage.MADE)
	assert_int(follower.outcome_tick).is_less_equal(forecast + TestBoardingFiles.FORECAST_LATE)


func test_deplaning_and_indoor_same_direction_followers_clear_pulled_roller() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(14, 7))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 3), 3)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(13, 3), 1)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(60000, 80000), 11)
	_world.step()

	# 1. Indoor same-direction corridor (TO_GATE): runner behind roller walker.
	var path: Array[Vector2i] = []
	for x in range(1, 13):
		path.append(Vector2i(x, 3))
	var lead := _roller_guest(_world)
	lead.cleared = true
	lead.stage = Passenger.Stage.TO_GATE
	lead.at = path[2]
	lead.set_path(path)
	lead.path_index = 2

	var follow := _plain_guest(_world)
	follow.cleared = true
	follow.stage = Passenger.Stage.TO_GATE
	follow.at = path[0]
	follow.set_path(path)
	follow.path_index = 0
	follow.late = true

	var min_indoor := INF
	for _i in 100:
		_world.step()
		if lead.is_moving() and follow.is_moving():
			min_indoor = minf(min_indoor, _apart_2d(_world, lead, follow))
		if not lead.is_moving() and not follow.is_moving():
			break

	# 2. Deplaning same-apron stream: follower spaced behind roller leader.
	var de_lead := _roller_guest(_world)
	var de_follow := _plain_guest(_world)
	var de_walk: Array[Vector3] = [Vector3(0.5, 0.0, -30.0), Vector3(0.5, 0.0, 0.0)]
	for dp: Passenger in [de_lead, de_follow]:
		dp.direction = Passenger.Direction.ARRIVING
		dp.stage = Passenger.Stage.DEPLANING
		dp.exit_object = _world.sim.layout.exits[0]
		dp.apron = de_walk.duplicate()
		dp.apron_mm = 0
		dp.clear_path()
	de_lead.apron_mm = 1500

	var min_deplane := INF
	for _i in 320:
		_world.step()
		if (
			de_lead.stage == Passenger.Stage.DEPLANING
			and de_follow.stage == Passenger.Stage.DEPLANING
		):
			min_deplane = minf(min_deplane, _apart_2d(_world, de_lead, de_follow))
		if de_lead.arrival_done and de_follow.arrival_done:
			break

	print("indoor min_apart=%.3f m, deplane min_apart=%.3f m" % [min_indoor, min_deplane])
	assert_float(min_indoor).is_greater_equal(MIN_ROLLER_CLEAR_M)
	assert_float(min_deplane).is_greater_equal(MIN_ROLLER_CLEAR_M)


func test_opposite_direction_corridor_walkers_never_block_each_other() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(14, 7))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 3), 3)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(13, 3), 1)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(60000, 80000), 23)
	_world.step()

	var east_path: Array[Vector2i] = []
	var west_path: Array[Vector2i] = []
	for x in range(1, 13):
		east_path.append(Vector2i(x, 3))
		west_path.append(Vector2i(13 - x, 3))

	var east := _roller_guest(_world)
	east.cleared = true
	east.stage = Passenger.Stage.TO_GATE
	east.at = east_path[0]
	east.set_path(east_path)

	var west := _plain_guest(_world)
	west.direction = Passenger.Direction.ARRIVING
	west.stage = Passenger.Stage.TO_AIRSIDE_EXIT
	west.at = west_path[0]
	west.set_path(west_path)

	for _i in 150:
		_world.step()
		if not east.is_moving() and not west.is_moving():
			break

	assert_bool(east.is_moving()).is_false()
	assert_int(east.at.x).is_greater_equal(10)
	assert_bool(west.is_moving()).is_false()
	assert_int(west.at.x).is_less_equal(2)
