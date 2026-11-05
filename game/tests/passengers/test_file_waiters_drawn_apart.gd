class_name TestFileWaitersDrawnApart
extends GdUnitTestSuite
## Walkers waiting to join a boarding file stand apart in the sim (board
## 3e3cb33e). Walkers that turn to the exit on one cell are on one point: the
## files let one set off and hold the rest pending (test_boarding_files). Each
## pending walker within BoardingFiles.GAP_MM of another waiter walks to a free
## wait spot (FileWaiters), waits there and walks back to its point once it
## joins its file or its spot is dropped; with no free spot it waits pending on
## its point, keeping its exit. The spacing check (_Spacing) covers every
## waiter on every tick, walking or not: two waiters are the gap apart, except
## a pair already together before turning out (inherited), which may only
## part. The views draw the sim's position.

## The cell the walkers turn out on together (TestBoardingFiles).
const FILE_CELL := Vector2i(19, 6)
const WALKERS := 5
## More walkers than FileWaiters.WAIT_SPOTS has spots, plus the cell's own.
const CROWD := 12
const EPS := 0.001
## The tick by which the third walker is on its wait spot.
const LIMIT := TestBoardingFiles.BOARDING + 60
## The most a walker moves in a tick, at a run, in metres.
## Cleared passengers in the standing-spot case.
const PASSENGERS := 40
const MOST_STEP_M := PassengerSim.RUN_MM / 1000.0 + EPS

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


## WALKERS walkers on one cell as boarding opens: no two waiters come within
## the gap (only the inherited pairs part), each stands on a cell it can walk
## to from its own, and is drawn where the sim puts it. All board, and no wait
## spot is left over.
func test_walkers_waiting_on_one_cell_stand_apart() -> void:
	_world = _boarding()
	_open_views()
	var walkers := _turn_out(_world, WALKERS)
	var sim := _world.sim
	var spacing := _Spacing.new(walkers)
	var off_cell := 0
	var off_drawn := 0.0
	var at_spot := 0
	while not walkers.all(_gone) and _world.clock.tick < TestBoardingFiles.BOARDING + 600:
		_world.step()
		spacing.check(sim)
		for p in walkers:
			if _gone(p):
				continue
			var at := sim.world_position(p)
			if not _one_step(sim.grid, p.at, sim.grid.world_to_cell(at)):
				off_cell += 1
			off_drawn = maxf(off_drawn, _views.tick_position(p.id, true).distance_to(at))
			at_spot += int(sim.files.waiters.at_spot(p))
	print("%s; at spot %d, off cell %d, drawn off %.3f m" % [spacing, at_spot, off_cell, off_drawn])
	# Controls: walkers waited apart, some on a spot, and every one boarded.
	assert_int(spacing.apart).is_greater(0)
	assert_int(at_spot).is_greater(0)
	for p in walkers:
		assert_bool(_gone(p)).is_true()
	assert_int(spacing.closer).is_equal(0)
	assert_int(spacing.closing).is_equal(0)
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


## More walkers on one cell than there are spots round it: every one keeps its
## exit and waits pending, those with no spot on their own point; a spot is
## given as one frees, no waiter comes within the gap of another (the stack
## they turned out in only parts), and all board.
func test_walkers_with_no_free_spot_wait_pending_and_never_close_in() -> void:
	_world = _boarding()
	var walkers := _turn_out(_world, CROWD)
	var sim := _world.sim
	var spacing := _Spacing.new(walkers)
	_world.step()
	spacing.check(sim)
	var spotless := walkers.filter(
		func(p: Passenger) -> bool:
			return sim.files.is_pending(p.id) and not sim.files.waiters.ids().has(p.id)
	)
	var dropped := walkers.filter(func(p: Passenger) -> bool: return p.exit_object == 0)
	var given_later := 0
	var first_spots := sim.files.waiters.ids().size()
	var seen := {}
	while not walkers.all(_gone) and _world.clock.tick < TestBoardingFiles.BOARDING + 2000:
		_world.step()
		spacing.check(sim)
		for id in sim.files.waiters.ids():
			if not seen.has(id) and spotless.any(func(p: Passenger) -> bool: return p.id == id):
				given_later += 1
			seen[id] = true
	print(
		(
			(
				"of %d walkers: %d with a spot at first, %d pending on their point, "
				+ "%d given a spot later, %d dropped their exit; %s"
			)
			% [CROWD, first_spots, spotless.size(), given_later, dropped.size(), spacing]
		)
	)
	assert_int(spotless.size()).is_greater(1)
	assert_int(dropped.size()).is_equal(0)
	for p in walkers:
		assert_bool(_gone(p)).is_true()
	assert_int(spacing.inherited).is_greater(0)
	assert_int(spacing.closer).is_equal(0)
	assert_int(spacing.closing).is_equal(0)


## Normal play: PASSENGERS cleared passengers standing on the 0.6 m lattice of
## standing spots in a seatless terminal (some closer than the gap) set off at
## boarding; the files add no waiter within the gap of another, and every
## passenger boards. A real shortage (more passengers than spots, those with
## none held together) needs more passengers than this terminal's spots, too
## slow for this suite.
func test_setting_off_from_standing_spots_adds_no_waiter_within_the_gap() -> void:
	_world = TestStandingSpotClaims.seatless_world(PassengerTestWorld.starts_with(400, 4000))
	var group: Array[Passenger] = []
	var spots := _world.sim.standing.spots.size()
	for i in PASSENGERS:
		group.append(TestStandingSpotClaims.cleared(_world))
	_world.run_to(399)
	var held := group.filter(
		func(p: Passenger) -> bool:
			return _world.sim.standing.spot_of(p.id) == StandingSpots.NO_SPOT
	)
	var spacing := _Spacing.new(group, _world.sim)
	while not group.all(_gone) and _world.clock.tick < 4000:
		_world.step()
		spacing.check(_world.sim)
	print(
		(
			"%d spots, %d passengers, %d held with none; %s"
			% [spots, group.size(), held.size(), spacing]
		)
	)
	for p in group:
		assert_bool(_gone(p)).is_true()
	assert_int(spacing.closer).is_equal(0)
	assert_int(spacing.closing).is_equal(0)


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
	_to_spot(walkers[2])
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


## Its exit closed (floor laid outside the door) while a waiter stands on its
## spot: its spot is dropped and it walks back from where it stands, never
## jumping, then goes out by the other door.
func test_a_waiter_whose_exit_closes_walks_back_from_its_spot() -> void:
	_world = _two_doors()
	var walkers := _turn_out(_world, 3)
	_to_spot(walkers[2])
	var door := walkers[2].exit_object
	var cell := _world.sim.layout.door_cell(_world.grid, door)
	var paint := BuildEdit.paint_floor(cell + Vector2i(0, -1), BuildGrid.FLOOR_TILE, 1)
	assert_bool(_world.grid.apply(paint).ok).is_true()
	_check_walks_back(walkers[2], door)


## Its exit removed (the door and its gap walled in) while a waiter stands on
## its spot: as above.
func test_a_waiter_whose_exit_is_removed_walks_back_from_its_spot() -> void:
	_world = _two_doors()
	var walkers := _turn_out(_world, 3)
	_to_spot(walkers[2])
	var door := walkers[2].exit_object
	var cell := _world.sim.layout.door_cell(_world.grid, door)
	var side := BuildGrid.SIDE_STEP.find(_world.sim.layout.door_outward(_world.grid, door))
	var edits: Array[BuildEdit] = [BuildEdit.remove_object(door), BuildEdit.place_wall(cell, side)]
	(
		assert_bool(_world.grid.apply_batch(edits).all(func(r: BuildResult) -> bool: return r.ok))
		. is_true()
	)
	_check_walks_back(walkers[2], door)


## A wall built between a waiter's point and its spot while it stands there
## (its exit still open): the spot cannot be stood on now, so it is dropped and
## the waiter walks back, never jumping, and still boards.
func test_a_wall_built_at_a_waiters_spot_drops_the_spot() -> void:
	_world = _boarding()
	var walkers := _turn_out(_world, 3)
	var p := walkers[2]
	_to_spot(p)
	var spot := _world.sim.world_position(p)
	var own := _world.grid.world_to_cell(spot - _world.sim.files.waiters.shift(p))
	var step := _world.grid.world_to_cell(spot) - own
	print("waiter %d on cell %s, its spot a step %s away" % [p.id, own, step])
	assert_int(absi(step.x) + absi(step.y)).is_equal(1)
	var wall := BuildEdit.place_wall(own, BuildGrid.SIDE_STEP.find(step))
	assert_bool(_world.grid.apply(wall).ok).is_true()
	_check_walks_back(p, 0)


## A save with a walker on its wait spot loads into a world that plays on
## exactly like the one that never stopped.
func test_a_save_with_a_waiter_on_its_spot_loads_and_plays_on_alike() -> void:
	_world = _boarding()
	var walkers := _turn_out(_world, 3)
	_to_spot(walkers[2])
	var saved := _save(_world)
	assert_array(saved["passengers"]["boarding"]["waiters"] as Array).is_not_empty()
	_other = _load(saved)
	var loaded := _other.sim.get_passenger(walkers[2].id)
	var there := _other.sim.world_position(loaded)
	assert_float(there.distance_to(_world.sim.world_position(walkers[2]))).is_less(EPS)
	for i in 120:
		_world.step()
		_other.step()
	assert_str(_signature(_other)).is_equal(_signature(_world))


## Bad wait spots are refused whole, the live sim left as it was: walked past
## its spot, a spot WAIT_SPOTS never gives, two spots within the gap, and a
## spot kept by a walker that is not waiting to join.
func test_bad_wait_spots_are_refused() -> void:
	_world = _boarding()
	var walkers := _turn_out(_world, 6)
	for i in 12:
		_world.step()
	var saved := _save(_world)
	var list: Array = saved["passengers"]["boarding"]["waiters"]
	print("waiters %s" % [list])
	assert_int(list.size()).is_greater_equal(2)
	_other = _load(saved)
	var before := _signature(_other)
	for name: String in ["walked past", "not a wait spot", "within the gap", "kept but filed"]:
		var bad := saved.duplicate(true)
		_spoil(name, bad["passengers"]["boarding"]["waiters"], walkers[0].id)
		var ok := _other.sim.from_snapshot(bad["passengers"])
		print("%s: loaded %s" % [name, ok])
		assert_bool(ok).override_failure_message(name).is_false()
		assert_str(_signature(_other)).is_equal(before)


## A waiter that set off from its standing spot (a 0.6 m lattice point, not a
## cell centre) is checked on load against the loaded standing claims: the
## save loads, into a sim whose own claims differ, and plays on alike.
func test_a_waiter_that_set_off_from_a_standing_spot_loads() -> void:
	_world = TestStandingSpotClaims.seatless_world(PassengerTestWorld.starts_with(400, 4000))
	var group: Array[Passenger] = []
	for i in 12:
		group.append(TestStandingSpotClaims.cleared(_world))
	_world.run_to(399)
	var subject: Passenger = null
	while subject == null and _world.clock.tick < 600:
		_world.step()
		for p in group:
			var stood := _world.sim.standing.spot_of(p.id) != StandingSpots.NO_SPOT
			if stood and _world.sim.files.waiters.ids().has(p.id):
				subject = p
	assert_object(subject).is_not_null()
	print(
		(
			"waiter %d set off from standing spot %d"
			% [subject.id, _world.sim.standing.spot_of(subject.id)]
		)
	)
	var saved := _save(_world)
	# A fresh world: its sim holds no standing claims of its own.
	_other = _load(saved)
	for i in 60:
		_world.step()
		_other.step()
	assert_str(_signature(_other)).is_equal(_signature(_world))


## Spoils saved wait spots `w` as case `name` says; `filed` is a walker that
## joined its file at once.
static func _spoil(name: String, w: Array, filed: int) -> void:
	match name:
		"walked past":
			w[0]["at"] = 99999
		"not a wait spot":
			w[0]["x"] = int(w[0]["x"]) + 150
		"within the gap":
			w[1]["x"] = w[0]["x"]
			w[1]["y"] = w[0]["y"]
		"kept but filed":
			w[0]["id"] = filed


static func _boarding() -> PassengerTestWorld:
	var world := TestBoardingFiles.boarding_world()
	world.run_to(TestBoardingFiles.BOARDING + 5)
	return world


## The reference terminal with a second exit door, run to boarding.
static func _two_doors() -> PassengerTestWorld:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	grid.apply(BuildEdit.remove_wall(Vector2i(17, 2), BuildGrid.Side.NORTH))
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(17, 2), 0)
	var world := PassengerTestWorld.make(
		grid, PassengerTestWorld.starts_with(TestBoardingFiles.BOARDING, TestBoardingFiles.DOORS)
	)
	world.run_to(TestBoardingFiles.BOARDING + 5)
	return world


## Steps until `p` stands on its wait spot.
func _to_spot(p: Passenger) -> void:
	while not _world.sim.files.waiters.at_spot(p) and _world.clock.tick < LIMIT:
		_world.step()
	assert_bool(_world.sim.files.waiters.at_spot(p)).is_true()


## After an edit dropped `p`'s spot: it never moves more than a step a tick,
## is back on its point with no spot within the walk back, and boards, not by
## `closed` (0 for none).
func _check_walks_back(p: Passenger, closed: int) -> void:
	var sim := _world.sim
	var last := sim.world_position(p)
	var biggest := 0.0
	var back_by := -1
	var out_by := 0
	var start := _world.clock.tick
	while not p.is_done() and _world.clock.tick < TestBoardingFiles.DOORS:
		_world.step()
		var at := sim.world_position(p)
		if p.stage == Passenger.Stage.TO_EXIT:
			biggest = maxf(biggest, at.distance_to(last))
		last = at
		if back_by < 0 and not sim.files.waiters.ids().has(p.id):
			back_by = _world.clock.tick - start
		if p.stage == Passenger.Stage.APRON and out_by == 0:
			out_by = p.exit_object
	print(
		(
			"walker %d: biggest step %.3f m, back on its point after %d ticks, out by %d"
			% [p.id, biggest, back_by, out_by]
		)
	)
	assert_float(biggest).is_less_equal(MOST_STEP_M)
	assert_int(back_by).is_between(1, 2 * BoardingFiles.step_ticks() + 4)
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)
	if closed != 0:
		assert_int(out_by).is_not_equal(closed)


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
	var grid := BuildGrid.new()
	grid.from_snapshot(data["grid"])
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	world.clock.from_snapshot(data["clock"])
	world.flights.from_snapshot(data["flights"])
	assert_bool(world.sim.from_snapshot(data["passengers"])).is_true()
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


## The spacing of a group's waiters (pending, or on, to or from a wait spot)
## on every tick: a pair within the gap ("closer") is an offence unless it has
## been within the gap since before the files held it (inherited), and an
## inherited pair must not close in ("closing"). "apart" counts pairs the gap
## apart or more, "inherited" the inherited pair-ticks.
class _Spacing:
	extends RefCounted
	var apart := 0
	var inherited := 0
	var closer := 0
	var closing := 0
	var _group: Array[Passenger] = []
	var _together := {}
	var _last := {}

	func _init(group: Array[Passenger], sim: PassengerSim = null) -> void:
		_group = group
		for i in group.size():
			for k in range(i + 1, group.size()):
				var key := Vector2i(mini(group[i].id, group[k].id), maxi(group[i].id, group[k].id))
				if sim == null or _apart(sim, group[i], group[k]) < FileWaiters.ROOM_M:
					_together[key] = true

	func check(sim: PassengerSim) -> void:
		var waiting: Array[Passenger] = []
		for p in _group:
			if sim.files.is_pending(p.id) or sim.files.waiters.ids().has(p.id):
				waiting.append(p)
		for i in waiting.size():
			for k in range(i + 1, waiting.size()):
				var a := waiting[i]
				var b := waiting[k]
				var key := Vector2i(mini(a.id, b.id), maxi(a.id, b.id))
				var d := _apart(sim, a, b)
				if d >= FileWaiters.ROOM_M:
					apart += 1
					_together.erase(key)
				elif _together.has(key):
					inherited += 1
					if _last.has(key) and d < float(_last[key]) - EPS:
						closing += 1
						print("closing: %d and %d %.3f m (was %.3f)" % [a.id, b.id, d, _last[key]])
				else:
					closer += 1
					print("closer: %d and %d %.3f m" % [a.id, b.id, d])
				_last[key] = d

	func _to_string() -> String:
		return (
			"waiter pairs apart %d, inherited %d, closer %d, closing %d"
			% [apart, inherited, closer, closing]
		)

	static func _apart(sim: PassengerSim, a: Passenger, b: Passenger) -> float:
		var pa := sim.world_position(a)
		var pb := sim.world_position(b)
		return Vector2(pa.x, pa.z).distance_to(Vector2(pb.x, pb.z))
