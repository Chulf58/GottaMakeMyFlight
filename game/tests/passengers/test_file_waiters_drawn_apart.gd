class_name TestFileWaitersDrawnApart
extends GdUnitTestSuite
## Walkers waiting to join a boarding file stand apart in the sim (board
## 3e3cb33e). Walkers that turn to the exit on one cell are on one point: the
## files let one set off and hold the rest pending (test_boarding_files). Each
## pending walker within BoardingFiles.GAP_MM of one already waiting walks to a
## free wait spot (FileWaiters), waits there and walks back to its point once
## it joins its file; with no free spot it does not join. The views draw the
## sim's position.

## The cell the walkers turn out on together (TestBoardingFiles).
const FILE_CELL := Vector2i(19, 6)
const WALKERS := 5
## More walkers than FileWaiters.WAIT_SPOTS has spots, plus the cell's own.
const CROWD := 12
const EPS := 0.001
## The tick by which the third walker is on its wait spot.
const LIMIT := TestBoardingFiles.BOARDING + 60

var _world: PassengerTestWorld
var _views: PassengerViews
var _other: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
	for world in [_world, _other]:
		if world != null:
			world.free_all()
	_views = null
	_world = null
	_other = null


## WALKERS walkers on one cell as boarding opens: every pair waiting together
## and standing still in the sim is at least the gap apart, each on a cell it
## can walk to from its own, and drawn where the sim puts it. All board, and
## no wait spot is left over.
func test_walkers_waiting_on_one_cell_stand_apart() -> void:
	_world = _boarding()
	_open_views()
	var walkers := _turn_out(_world, WALKERS)
	var sim := _world.sim
	var last := {}
	var nearest := INF
	var pairs := 0
	var off_cell := 0
	var off_drawn := 0.0
	var at_spot := 0
	while not walkers.all(_gone) and _world.clock.tick < TestBoardingFiles.BOARDING + 600:
		_world.step()
		var still: Array[Passenger] = []
		for p in walkers:
			if _gone(p):
				continue
			var at := sim.world_position(p)
			var cell := sim.grid.world_to_cell(at)
			if not _one_step(sim.grid, p.at, cell):
				off_cell += 1
			off_drawn = maxf(off_drawn, _views.tick_position(p.id, true).distance_to(at))
			at_spot += int(sim.files.waiters.at_spot(p))
			if sim.files.is_pending(p.id) and last.has(p.id) and at.distance_to(last[p.id]) < EPS:
				still.append(p)
			last[p.id] = at
		for i in still.size():
			for k in range(i + 1, still.size()):
				pairs += 1
				var d := sim.world_position(still[i]).distance_to(sim.world_position(still[k]))
				nearest = minf(nearest, d)
	print(
		(
			"still waiting pairs %d nearest %.3f m, at spot %d, off cell %d, drawn off %.3f m"
			% [pairs, nearest, at_spot, off_cell, off_drawn]
		)
	)
	# Controls: walkers waited together, some on a spot, and every one boarded.
	assert_int(pairs).is_greater(0)
	assert_int(at_spot).is_greater(0)
	for p in walkers:
		assert_bool(_gone(p)).is_true()
	assert_float(nearest).is_greater_equal(BoardingFiles.GAP_MM / 1000.0 - EPS)
	assert_int(off_cell).is_equal(0)
	assert_float(off_drawn).is_less(EPS)
	assert_array(sim.files.waiters.ids()).is_empty()


## A waiter keeps its cell and the start of its path while it walks to its
## spot in the sim, and owes the forecast the walk there and back.
func test_a_waiter_walks_to_its_spot_and_keeps_its_place_on_its_path() -> void:
	_world = _boarding()
	var walkers := _turn_out(_world, 3)
	var last := walkers[2]
	var sim := _world.sim
	var start := sim.world_position(last)
	_world.step()
	var owed := sim.files.waiters.owed_mm(last.id)
	for i in BoardingFiles.step_ticks():
		_world.step()
	var moved := sim.world_position(last).distance_to(start)
	print("last waiter %.3f m from where it turned out; owed %d mm at first" % [moved, owed])
	assert_bool(sim.files.is_pending(last.id)).is_true()
	assert_that(last.at).is_equal(FILE_CELL)
	assert_int(last.path_index).is_equal(0)
	assert_int(last.seg_mm).is_equal(0)
	assert_float(moved).is_greater(0.3)
	assert_bool(sim.files.waiters.at_spot(last)).is_true()
	assert_int(owed).is_greater(2 * BoardingFiles.GAP_MM - 2 * PassengerSim.WALK_MM)
	assert_int(sim.files.waiters.owed_mm(walkers[0].id)).is_equal(0)


## A save with a walker on its wait spot loads into a world that plays on
## exactly like the one that never stopped; a save whose spot is off its
## walk is refused.
func test_a_save_with_a_waiter_on_its_spot_loads_and_plays_on_alike() -> void:
	_world = _boarding()
	var walkers := _turn_out(_world, 3)
	while not _world.sim.files.waiters.at_spot(walkers[2]) and _world.clock.tick < LIMIT:
		_world.step()
	assert_bool(_world.sim.files.waiters.at_spot(walkers[2])).is_true()
	var saved := _save(_world)
	assert_array(saved["passengers"]["boarding"]["waiters"] as Array).is_not_empty()
	_other = _load(saved)
	var loaded := _other.sim.get_passenger(walkers[2].id)
	(
		assert_float(
			_other.sim.world_position(loaded).distance_to(_world.sim.world_position(walkers[2]))
		)
		. is_less(EPS)
	)
	for i in 120:
		_world.step()
		_other.step()
	assert_str(_signature(_other)).is_equal(_signature(_world))
	var bad := saved.duplicate(true)
	var waiters: Array = bad["passengers"]["boarding"]["waiters"]
	(waiters[0] as Dictionary)["at"] = 99999
	var refused := _load_world(bad)
	print("bad wait spot load: %s" % refused)
	assert_bool(refused).is_false()


## spot do not join (no exit, in no file) and stand where they are, and all
## still board.
## no waiter stands on another's point, and all still board.
func test_walkers_with_no_free_spot_wait_without_an_exit() -> void:
	_world = _boarding()
	var walkers := _turn_out(_world, CROWD)
	_world.step()
	_world.step()
	var sim := _world.sim
	var crowded := walkers.filter(
		func(p: Passenger) -> bool: return p.exit_object == 0 and not _gone(p)
	)
	var spots := sim.files.waiters.ids().size()
	print("of %d walkers: %d with a spot, %d crowded out" % [CROWD, spots, crowded.size()])
	assert_int(crowded.size()).is_greater(0)
	for p: Passenger in crowded:
		assert_int(p.exit_object).is_equal(0)
		assert_bool(sim.files.holds(p.id)).is_false()
		assert_that(p.at).is_equal(FILE_CELL)
	assert_int(spots).is_greater(0)
	while not walkers.all(_gone) and _world.clock.tick < TestBoardingFiles.BOARDING + 2000:
		_world.step()
	for p in walkers:
		assert_bool(_gone(p)).is_true()


## The same walkers turned out in two fresh worlds take the same spots.
func test_wait_spots_are_the_same_every_run() -> void:
	_world = _boarding()
	_other = _boarding()
	_turn_out(_world, WALKERS)
	_turn_out(_other, WALKERS)
	for i in 6:
		_world.step()
		_other.step()
	var mine := JSON.stringify(_world.sim.files.waiters.to_list())
	print("spots %s" % mine)
	assert_array(_world.sim.files.waiters.to_list()).is_not_empty()
	assert_str(JSON.stringify(_other.sim.files.waiters.to_list())).is_equal(mine)


## A snap (a load) draws each waiter at the sim's position at once.
func test_a_snap_draws_the_waiters_where_the_sim_puts_them() -> void:
	_world = _boarding()
	_open_views()
	var walkers := _turn_out(_world, 3)
	while not _world.sim.files.waiters.at_spot(walkers[2]) and _world.clock.tick < LIMIT:
		_world.step()
	assert_bool(_world.sim.files.waiters.at_spot(walkers[2])).is_true()
	_views.snap()
	var d := _views.tick_position(walkers[1].id, true).distance_to(
		_views.tick_position(walkers[2].id, true)
	)
	var off := _views.tick_position(walkers[2].id, true).distance_to(
		_world.sim.world_position(walkers[2])
	)
	print("after snap the two waiters are %.3f m apart, drawn %.3f m off" % [d, off])
	assert_float(d).is_greater_equal(BoardingFiles.GAP_MM / 1000.0 - EPS)
	assert_float(off).is_less(EPS)


static func _boarding() -> PassengerTestWorld:
	var world := TestBoardingFiles.boarding_world()
	world.run_to(TestBoardingFiles.BOARDING + 5)
	return world


func _open_views() -> void:
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)


## `count` calm walkers on FILE_CELL of `world`, turning to the exit on the
## next tick.
static func _turn_out(world: PassengerTestWorld, count: int) -> Array[Passenger]:
	var walkers: Array[Passenger] = []
	for i in count:
		walkers.append(TestBoardingFiles.walker(world, FILE_CELL))
	return walkers


static func _save(world: PassengerTestWorld) -> Dictionary:
	return {
		"clock": world.clock.to_snapshot(),
		"flights": world.flights.to_snapshot(),
		"grid": world.grid.to_snapshot(),
		"passengers": world.sim.to_snapshot(),
	}


func _load(data: Dictionary) -> PassengerTestWorld:
	var world := _fresh(data)
	assert_bool(world.sim.from_snapshot(data["passengers"])).is_true()
	return world


## Whether the passengers of `data` load into a fresh world.
func _load_world(data: Dictionary) -> bool:
	var world := _fresh(data)
	var ok := world.sim.from_snapshot(data["passengers"])
	world.free_all()
	return ok


static func _fresh(data: Dictionary) -> PassengerTestWorld:
	var grid := BuildGrid.new()
	grid.from_snapshot(data["grid"])
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	world.clock.from_snapshot(data["clock"])
	world.flights.from_snapshot(data["flights"])
	return world


static func _signature(world: PassengerTestWorld) -> String:
	return "%s#%s" % [world.signature(), JSON.stringify(world.sim.files.to_dict())]


## Whether `b` is cell `a` or a step a passenger can walk from it (a diagonal
## through a cell beside both).
static func _one_step(grid: BuildGrid, a: Vector2i, b: Vector2i) -> bool:
	if a == b:
		return true
	var d := b - a
	if absi(d.x) + absi(d.y) == 1:
		return grid.can_passenger_route(a, b)
	if absi(d.x) != 1 or absi(d.y) != 1:
		return false
	for via: Vector2i in [a + Vector2i(d.x, 0), a + Vector2i(0, d.y)]:
		if grid.can_passenger_route(a, via) and grid.can_passenger_route(via, b):
			return true
	return false


static func _gone(p: Passenger) -> bool:
	return p.is_done() or p.stage == Passenger.Stage.APRON
