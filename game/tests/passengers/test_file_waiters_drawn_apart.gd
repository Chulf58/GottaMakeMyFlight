class_name TestFileWaitersDrawnApart
extends GdUnitTestSuite
## Walkers waiting to join a boarding file are drawn apart (board 3e3cb33e).
## Walkers that turn to the exit on one cell are on one point in the sim: the
## files let one set off and hold the rest pending where they stand
## (test_boarding_files). Each pending walker that stands closer than
## BoardingFiles.GAP_MM to one before it in the admission order is drawn on a
## free point near its own (FileWaiters), reached at a walk,
## and walks back onto its own point once it is no longer crowded.

## The cell the walkers turn out on together (TestBoardingFiles).
const FILE_CELL := Vector2i(19, 6)
const WALKERS := 5
## Ticks a walk takes to the farthest of FileWaiters.WAIT_SPOTS, plus one: a
## drawn offset has reached its target, or gone after joining, by then.
const SETTLE := 17
const EPS := 0.001

var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
		_world.free_all()
	_views = null
	_world = null


## WALKERS walkers on one cell as boarding opens: every pair waiting together
## and standing still (drawn on the same point as on the tick before) is drawn at
## least the gap apart, each on a cell it can walk to from its own. A walker that
## set off is drawn on its sim point again within SETTLE ticks.
func test_walkers_waiting_on_one_cell_are_drawn_apart() -> void:
	var walkers := _turn_out(WALKERS)
	var sim := _world.sim
	var walked := {}
	var drawn_ticks := {}
	var nearest := INF
	var pairs := 0
	var off_cell := 0
	var off_path := 0.0
	while not walkers.all(_gone) and _world.clock.tick < TestBoardingFiles.BOARDING + 600:
		_world.step()
		var settled: Array[Passenger] = []
		for p in walkers:
			var pending := not _gone(p) and sim.files.is_pending(p.id)
			walked[p.id] = int(walked.get(p.id, 0)) + 1 if not pending else 0
			if _gone(p):
				continue
			var drawn := _views.tick_position(p.id, true)
			var cell := sim.grid.world_to_cell(drawn)
			var own := sim.grid.world_to_cell(sim.world_position(p))
			if not _one_step(sim.grid, own, cell):
				off_cell += 1
			if walked[p.id] > SETTLE:
				off_path = maxf(off_path, drawn.distance_to(sim.world_position(p)))
			# A view is first drawn with no tick before it: not a still one.
			var still := drawn.distance_to(_views.tick_position(p.id, false)) < EPS
			if pending and still and drawn_ticks.has(p.id):
				settled.append(p)
			drawn_ticks[p.id] = true
		for i in settled.size():
			for k in range(i + 1, settled.size()):
				pairs += 1
				var d := _views.tick_position(settled[i].id, true).distance_to(
					_views.tick_position(settled[k].id, true)
				)
				nearest = minf(nearest, d)
	print(
		(
			"waiting pairs %d nearest %.3f m, off cell %d, off path after walking %.3f m"
			% [pairs, nearest, off_cell, off_path]
		)
	)
	# Control: walkers did wait together, and every one boarded.
	assert_int(pairs).is_greater(0)
	for p in walkers:
		assert_bool(_gone(p)).is_true()
	assert_float(nearest).is_greater_equal(BoardingFiles.GAP_MM / 1000.0 - EPS)
	assert_int(off_cell).is_equal(0)
	assert_float(off_path).is_less(EPS)


## The sim does not move a pending walker: it stays on its cell, at the start
## of its path, while it is drawn away from it.
func test_a_drawn_apart_waiter_keeps_its_place_in_the_sim() -> void:
	var walkers := _turn_out(3)
	var last := walkers[2]
	for i in BoardingFiles.step_ticks():
		_world.step()
	assert_bool(_world.sim.files.is_pending(last.id)).is_true()
	assert_that(last.at).is_equal(FILE_CELL)
	assert_int(last.path_index).is_equal(0)
	assert_int(last.seg_mm).is_equal(0)
	var drawn := _views.tick_position(last.id, true)
	print(
		(
			"last waiter drawn %.3f m from its sim point"
			% drawn.distance_to(_world.sim.world_position(last))
		)
	)
	assert_float(drawn.distance_to(_world.sim.world_position(last))).is_greater(0.3)


## A snap (a load) draws each waiter on its spot at once, with no walk to it
## from its sim point.
func test_a_snap_draws_the_waiters_apart_at_once() -> void:
	var walkers := _turn_out(3)
	_world.step()
	_views.snap()
	var waiting := walkers.filter(
		func(p: Passenger) -> bool: return _world.sim.files.is_pending(p.id)
	)
	assert_int(waiting.size()).is_equal(2)
	var d := _views.tick_position(waiting[0].id, true).distance_to(
		_views.tick_position(waiting[1].id, true)
	)
	print("after snap the two waiters are %.3f m apart" % d)
	assert_float(d).is_greater_equal(BoardingFiles.GAP_MM / 1000.0 - EPS)


## `count` calm walkers on FILE_CELL, turning to the exit on the next tick,
## with the views drawing them.
func _turn_out(count: int) -> Array[Passenger]:
	_world = TestBoardingFiles.boarding_world()
	_world.run_to(TestBoardingFiles.BOARDING + 5)
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)
	var walkers: Array[Passenger] = []
	for i in count:
		walkers.append(TestBoardingFiles.walker(_world, FILE_CELL))
	return walkers


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
