class_name TestRoomMoveToilet
extends GdUnitTestSuite
## Toilet users when their stall moves (decision move-rooms-technical-design-
## roommove-plan-of-existing-edits, parts 4 to 6), on ToiletTestLayout's
## landside room with one stall at x 23 (cells 23,10 and 23,11, approached
## from 23,12). The stall is moved by hand as a room move moves it: removed
## and placed again under its id with its paid, here to x 25.
##
## Steps are measured on the drawn position a PassengerViews records each tick
## (tick_position()), which the frame draws between: no tick may move the user
## further than a walking step (PassengerSim.WALK_MM), which is also the
## longest step of the step in and out (1.15 m over ToiletSim.EXIT_TICKS).

const MAX_STEP_M := PassengerSim.WALK_MM / 1000.0 + 0.002
const MOVED_TO := Vector2i(25, 10)

var _world: PassengerTestWorld
var _views: PassengerViews
var _ids: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
		_views = null
	if _world != null:
		_world.free_all()
		_world = null


func _make() -> void:
	var grid := BuildGrid.new()
	_ids = ToiletTestLayout.build(grid, 1)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	# The views sync on every tick, recording each passenger's drawn position.
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	# Staff come on duty on the first ticks; until then security is closed.
	_world.run_to(10)


func _toilets() -> ToiletSim:
	return _world.sim.toilets


func _at() -> Vector2i:
	return ReferenceTerminal.offset_on(_world.grid)


func _stall() -> int:
	return _ids["land_stalls"][0]


## A landside passenger on a visit to the stall, run until it reaches `stage`.
func _user_to(stage: Passenger.Stage) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.stage = Passenger.Stage.TO_SECURITY
	p.stage_tick = _world.clock.tick
	p.at = Vector2i(20, 14) + _at()
	p.clear_path()
	p.toilet_need = 90
	assert_bool(_toilets().try_visit(p)).is_true()
	var until := _world.clock.tick + 1500
	while p.stage != stage and _world.clock.tick < until:
		_world.step()
	assert_int(p.stage).is_equal(stage)
	return p


func _move_stall(anchor: Vector2i) -> void:
	var record := _world.grid.get_object(_stall())
	var place := BuildEdit.place_object(record["def"], anchor + _at(), record["facing"])
	place.object_id = _stall()
	place.paid = int(record.get("paid", 0))
	for result in _world.grid.apply_batch([BuildEdit.remove_object(_stall()), place]):
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()


## Steps until `done` holds or `limit` ticks pass, failing when the
## passenger's drawn position (the views' record for the tick) moves more than
## MAX_STEP_M on any tick; the message names the tick and stage.
func _walk_until(world: PassengerTestWorld, p: Passenger, done: Callable, limit := 1500) -> void:
	var last := _views.tick_position(p.id, true)
	var largest := 0.0
	var worst := ""
	var until := world.clock.tick + limit
	while not done.call() and world.clock.tick < until:
		world.step()
		var now := _views.tick_position(p.id, true)
		if now.distance_to(last) > largest:
			largest = now.distance_to(last)
			worst = "tick %d stage %d step %.3f" % [world.clock.tick, p.stage, largest]
		last = now
	assert_bool(done.call()).is_true()
	assert_float(largest).override_failure_message(worst).is_less(MAX_STEP_M)


func test_a_user_gets_up_in_the_old_stall_then_uses_the_moved_one_for_what_is_left() -> void:
	_make()
	var p := _user_to(Passenger.Stage.TOILET_USE)
	for i in 30:
		_world.step()
	var visit := _toilets().visit_of(p.id)
	var used := _world.clock.tick + 1 - p.stage_tick
	var seated_at := _toilets().stall_position(p)
	_move_stall(MOVED_TO)
	assert_vector(_toilets().stall_position(p)).is_equal(seated_at)
	assert_int(Relocation.ghosts(_world.sim).size()).is_equal(1)
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.TOILET_STANDING_UP)
	assert_int(visit.relocation.left).is_equal(ToiletSim.USE_TICKS - used)
	assert_int(p.toilet_need).is_greater(0)
	assert_float(_toilets().stall_position(p).distance_to(seated_at)).is_less(MAX_STEP_M)
	_walk_until(_world, p, func() -> bool: return p.stage == Passenger.Stage.TOILET_WALK)
	assert_vector(p.at).is_equal(Vector2i(23, 12) + _at())
	assert_int(Relocation.ghosts(_world.sim).size()).is_equal(0)
	_walk_until(_world, p, func() -> bool: return p.stage == Passenger.Stage.TOILET_USE)
	assert_vector(p.at).is_equal(MOVED_TO + Vector2i(0, 2) + _at())
	assert_int(_world.clock.tick - p.stage_tick).is_equal(used)
	assert_object(visit.relocation).is_null()
	# The rest is an ordinary use and exit, not measured: the tick a visit ends,
	# the journey's own walk can start as the last step out is taken (outside
	# relocation, reported separately).
	while _toilets().visit_of(p.id) != null and _world.clock.tick < 3000:
		_world.step()
	assert_int(p.toilet_need).is_less(10)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_SECURITY)


func test_a_move_while_stepping_out_lets_the_user_finish_and_go_on() -> void:
	_make()
	var p := _user_to(Passenger.Stage.TOILET_EXIT)
	var visit := _toilets().visit_of(p.id)
	_move_stall(MOVED_TO)
	_world.step()
	assert_int(visit.relocation.left).is_equal(-1)
	_walk_until(_world, p, func() -> bool: return _toilets().visit_of(p.id) == null, 30)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_SECURITY)
	assert_vector(p.at).is_equal(Vector2i(23, 12) + _at())


func test_save_and_load_while_leaving_the_old_stall_plays_on() -> void:
	_make()
	var p := _user_to(Passenger.Stage.TOILET_USE)
	_move_stall(MOVED_TO)
	for i in 30:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.TOILET_EXIT)
	var text := (
		JSON
		. stringify(
			{
				"clock": _world.clock.to_snapshot(),
				"flights": _world.flights.to_snapshot(),
				"grid": _world.grid.to_snapshot(),
				"passengers": _world.sim.to_snapshot(),
				"wallet": _world.sim.wallet.to_snapshot(),
			}
		)
	)
	assert_str(text).contains("relocation")
	var data: Dictionary = JSON.parse_string(text)
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	var twin := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	assert_bool(twin.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(twin.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(twin.sim.from_snapshot(data["passengers"])).is_true()
	assert_bool(twin.sim.wallet.from_snapshot(data["wallet"])).is_true()
	var q := twin.passenger(p.id)
	assert_vector(twin.sim.toilets.stall_position(q)).is_equal(_toilets().stall_position(p))
	assert_int(Relocation.ghosts(twin.sim).size()).is_equal(1)
	for i in 150:
		_world.step()
		twin.step()
	assert_int(q.stage).is_equal(p.stage)
	assert_int(q.stage).is_equal(Passenger.Stage.TOILET_USE)
	assert_vector(twin.sim.world_position(q)).is_equal(_world.sim.world_position(p))
	twin.free_all()


func test_a_ghost_view_draws_the_stall_at_its_old_spot_until_the_user_leaves() -> void:
	_make()
	var p := _user_to(Passenger.Stage.TOILET_USE)
	var old := Relocation.placement(_world.grid, _stall())
	var ghosts := RelocationGhosts.new()
	ghosts.sim = _world.sim
	add_child(ghosts)
	_move_stall(MOVED_TO)
	ghosts.sync()
	assert_int(ghosts.count()).is_equal(1)
	var entry := old.duplicate()
	entry["id"] = _stall()
	var node := ghosts.node_of(entry)
	var cells := BuildCatalog.get_def(&"toilet_stall").footprint(old["anchor"], old["facing"])
	var where := BuildView.object_transform(_world.grid, cells, old["facing"]).origin
	assert_vector(node.position).is_equal(where)
	_walk_until(_world, p, func() -> bool: return p.stage == Passenger.Stage.TOILET_WALK)
	ghosts.sync()
	assert_int(ghosts.count()).is_equal(0)
	ghosts.free()
