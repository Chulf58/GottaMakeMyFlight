class_name TestAlertSources
extends GdUnitTestSuite
## The alert cards' causes, read from the sim through the checks the world
## signs already use: a full check-in or security queue (MissSignals, the
## queue-full signs), passengers with no walkable route (Passenger.Stuck
## NO_ROUTE, the "I can't get there" bubble) and a dirty terminal (DirtyAlert's
## band). Each is true while its condition holds and gone once it is fixed,
## and points the camera at the problem.

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


func _keys(causes: Array[Dictionary]) -> Array[StringName]:
	var keys: Array[StringName] = []
	for cause in causes:
		keys.append(cause["key"])
	return keys


## The cells under the object `id`.
func _footprint(id: int) -> Array[Vector2i]:
	var record := _world.sim.grid.get_object(id)
	var def := BuildCatalog.get_def(StringName(record["def"]))
	return def.footprint(record["anchor"], record["facing"])


## TestMissSignals' world: one desk whose lane holds 3, an entrance, no scanner.
func _short_lane_world() -> int:
	var grid := PassengerTestWorld.floored(Vector2i(6, 5))
	var desk := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(2, 1), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 4), 3)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	return desk


## Keeps `desk`'s passenger in service two ticks past now. The hold cells lie
## past the lane in this world, and walkers come round the lane over the desk's
## far side instead of through it (decision queue-walkers-route-around-their-
## own-line-a-walker-heading-t), so the line fills after the first service
## would end. Its service ends two ticks after the last hold, so the lane is
## still full once the holders stand.
func _hold_service(desk: int) -> void:
	var serving: int = _world.sim._queue(desk)["serving"]
	if serving != 0:
		var p := _world.passenger(serving)
		p.service_end = maxi(p.service_end, _world.sim.tick + 2)


func test_a_full_check_in_queue_is_a_cause_pointing_at_its_desk() -> void:
	var desk := _short_lane_world()
	assert_array(AlertSources.queue_full(_world.sim)).is_empty()
	# Three ticks apart: the fifth walks on past the first hold cell and turns
	# back onto the second (TerminalLayout.line_of(), StationQueue.approach()),
	# and stands there before the first is served.
	for i in 5:
		_world.sim.spawn_now(PassengerTestWorld.FLIGHT)
		_world.run_to(_world.clock.tick + 3)
	for i in 300:
		if _world.sim.holding_of(desk).size() == 2:
			break
		_world.step()
		_hold_service(desk)
	assert_int(_world.sim.holding_of(desk).size()).is_equal(2)
	var causes := AlertSources.queue_full(_world.sim)
	assert_array(_keys(causes)).is_equal([AlertSources.QUEUE_CHECKIN])
	var cause := causes[0]
	assert_str(cause["title"]).is_equal("Check-in queue full")
	assert_str(cause["detail"]).is_equal("1 desk full · +2 waiting")
	assert_int(cause["show_after"]).is_equal(AlertSources.QUEUE_HOLD_TICKS)
	assert_int(cause["clear_after"]).is_equal(AlertSources.QUEUE_HOLD_TICKS)
	var targets: Array = cause["targets"]
	assert_int(targets.size()).is_equal(1)
	var cell := _world.sim.grid.world_to_cell(targets[0])
	assert_array(_footprint(desk)).contains([cell])
	# The queue drains (no scanner, so the served stand elsewhere): no cause.
	_world.run_to(_world.clock.tick + 5 * PassengerSim.CHECKIN_TICKS + 40)
	assert_int(_world.sim.queue_of(desk).size()).is_equal(0)
	assert_array(AlertSources.queue_full(_world.sim)).is_empty()


func test_passengers_with_no_route_are_one_cause_until_the_wall_opens() -> void:
	# TestPassengerJourney's walled desk: a wall cuts the desk off the entrance.
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	for y in 6:
		grid.apply(BuildEdit.place_wall(Vector2i(4, y), BuildGrid.Side.WEST))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(7, 0), 0)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(5, 1), 0)
	var first := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var second := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(_world.clock.tick + 21)
	assert_int(_world.passenger(first).stuck).is_equal(Passenger.Stuck.NO_ROUTE)
	assert_int(_world.passenger(second).stuck).is_equal(Passenger.Stuck.NO_ROUTE)
	var causes := AlertSources.no_route(_world.sim)
	assert_array(_keys(causes)).is_equal([AlertSources.NO_ROUTE])
	assert_str(causes[0]["title"]).is_equal("No walkable route")
	assert_str(causes[0]["detail"]).is_equal("2 passengers can't get where they are going")
	var targets: Array = causes[0]["targets"]
	assert_int(targets.size()).is_equal(2)
	var at := _world.sim.world_position(_world.passenger(first))
	assert_float((targets[0] as Vector3).distance_to(Vector3(at.x, 0.0, at.z))).is_less(0.01)
	grid.apply(BuildEdit.remove_wall(Vector2i(4, 3), BuildGrid.Side.WEST))
	_world.run_to(_world.clock.tick + 120)
	assert_int(_world.passenger(first).stuck).is_not_equal(Passenger.Stuck.NO_ROUTE)
	assert_array(AlertSources.no_route(_world.sim)).is_empty()


func test_a_dirty_terminal_is_a_cause_pointing_at_the_dirtiest_mess() -> void:
	_world = MessTestKit.open_world()
	var dirty := DirtyAlert.new()
	dirty.sim = _world.sim
	dirty.refresh()
	assert_array(dirty.cause()).is_empty()
	var cells: Array[Vector2i] = []
	for i in DirtyAlert.SHOW_AT:
		var cell := Vector2i(2 + i * 2, 8)
		assert_int(_world.sim.messes.add(MessSim.Kind.SPILL, cell)).is_greater(0)
		cells.append(cell)
	dirty.refresh()
	var causes := dirty.cause()
	assert_array(_keys(causes)).is_equal([DirtyAlert.KEY])
	assert_str(causes[0]["detail"]).is_equal(DirtyAlert.HIRE_TEXT)
	var targets: Array = causes[0]["targets"]
	assert_int(targets.size()).is_equal(mini(cells.size(), AlertSources.MAX_TARGETS))
	for target: Vector3 in targets:
		assert_array(cells).contains([_world.sim.grid.world_to_cell(target)])
	for id in _world.sim.messes.mess_ids():
		assert_bool(_world.sim.messes.clean(id)).is_true()
	dirty.refresh()
	assert_array(dirty.cause()).is_empty()
