class_name TestToiletDeadline
extends GdUnitTestSuite
## A toilet detour never costs the flight (decision a-passenger-with-a-high-
## need-detours-to-the-nearest-facility; decision toilet-design-queue-free-
## reservable-stalls-per-stall-daily-u, point 3). On a winding layout, where
## the way from the toilets to the exit goes round a long wall, passengers
## asking for a stall at every moment up to the doors closing are admitted
## only when VisitForecast lets the whole visit fit on the real route; a wall
## that grows mid-visit brings the deadline forward and cuts visits short;
## every admitted passenger boards. Past the deadline each phase before
## standing up hands over to the way out.

## The winding layout of test_visit_forecast with a toilet room east of the
## wall: STALLS stalls along its north side from x 14, a sink at x 25.
const SIZE := Vector2i(30, 40)
const WALL_X := 12
const WALL_END_Y := 35
const EXIT_CELL := Vector2i(2, 0)
const ENTRANCE_CELL := Vector2i(2, 39)
const TOILET_ROOM := Rect2i(14, 2, 12, 4)
const STALLS := 11
const GUEST_CELL := Vector2i(20, 10)
const BOARDING := 30
const DOORS := 6000
## When the guests start asking, how often, and when the wall grows.
const FIRST_ASK := DOORS - 2000
const ASK_EVERY := 40
const EDIT_TICK := DOORS - 1100

var _world: PassengerTestWorld
## Passenger id -> [[stage, tick], ...].
var _stages: Dictionary = {}


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null
	_stages.clear()


func _winding_world() -> PassengerTestWorld:
	var grid := PassengerTestWorld.floored(SIZE)
	for y in range(0, WALL_END_Y + 1):
		_apply(grid, BuildEdit.place_wall(Vector2i(WALL_X, y), BuildGrid.Side.EAST))
	PassengerTestWorld.place(grid, &"exit_door", EXIT_CELL, 0)
	PassengerTestWorld.place(grid, &"entrance_door", ENTRANCE_CELL, 2)
	_apply(grid, BuildEdit.place_room(TOILET_ROOM, &"toilet"))
	for i in STALLS:
		PassengerTestWorld.place(grid, &"toilet_stall", Vector2i(14 + i, 2), 0)
	PassengerTestWorld.place(grid, &"toilet_sink", Vector2i(25, 2), 0)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(BOARDING, DOORS))
	# The plane stands just outside the exit, so the walk inside decides.
	_world.sim.apron_waypoints = PackedVector3Array()
	var sim := _world.sim
	sim.stage_changed.connect(
		func(id: int, stage: Passenger.Stage) -> void:
			if not _stages.has(id):
				_stages[id] = []
			_stages[id].append([stage, sim.tick])
	)
	_world.run_to(BOARDING + 1)
	return _world


func _apply(grid: BuildGrid, edit: BuildEdit) -> void:
	var result := grid.apply(edit)
	assert(result.ok, "winding layout edit refused: %s" % result.reason_text())


## A calm cleared passenger at `cell` heading for the gate, with a high need.
func _guest(cell := GUEST_CELL) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.toilet_need = 95
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _world.clock.tick
	p.at = cell
	p.clear_path()
	return p


## Whether `id`'s visit ended before a whole use of the stall.
func _cut_short(id: int) -> bool:
	var entries: Array = _stages.get(id, [])
	for i in entries.size():
		if entries[i][0] == Passenger.Stage.TOILET_USE:
			var ended: int = entries[i + 1][1] if i + 1 < entries.size() else _world.clock.tick
			return ended - int(entries[i][1]) < ToiletSim.USE_TICKS
	return true


func test_no_admitted_detour_misses_on_the_winding_route_even_when_the_wall_grows() -> void:
	_winding_world()
	var admitted: Array[Passenger] = []
	var refused := 0
	var grown := false
	var ask := FIRST_ASK
	_world.run_to(FIRST_ASK)
	while _world.clock.tick < DOORS:
		if not grown and _world.clock.tick >= EDIT_TICK:
			# The wall runs on south, so the way round it gets longer for
			# everyone on a visit.
			for y in range(WALL_END_Y + 1, SIZE.y - 1):
				_apply(_world.grid, BuildEdit.place_wall(Vector2i(WALL_X, y), BuildGrid.Side.EAST))
			grown = true
		if _world.clock.tick >= ask:
			var p := _guest()
			if _world.sim.toilets.try_visit(p):
				admitted.append(p)
			else:
				refused += 1
			ask += ASK_EVERY
		_world.step()
	_world.run_to(DOORS + 1)
	var made := 0
	var cut := 0
	var last_admitted := 0
	for p in admitted:
		made += int(p.stage == Passenger.Stage.MADE)
		cut += int(_cut_short(p.id))
		last_admitted = maxi(last_admitted, p.spawn_tick)
	print(
		(
			"admitted %d (last asked at %d), refused %d, made %d, cut short %d"
			% [admitted.size(), last_admitted, refused, made, cut]
		)
	)
	# The forecast engaged both ways and the edit cut some visits short.
	assert_int(admitted.size()).is_greater(10)
	assert_int(refused).is_greater(5)
	assert_int(cut).is_greater(0)
	# Every admitted detour boarded.
	assert_int(made).is_equal(admitted.size())


## Runs a fresh guest's visit until it is in `stage`, then puts its deadline
## on the next tick and steps once. Returns the guest.
func _past_deadline_in(stage: Passenger.Stage) -> Passenger:
	_winding_world()
	var p := _guest()
	assert_bool(_world.sim.toilets.try_visit(p)).is_true()
	while p.stage != stage and _world.clock.tick < 2000:
		_world.step()
	assert_int(p.stage).is_equal(stage)
	# Partway in, so a timed phase has something to undo.
	if stage != Passenger.Stage.TOILET_WALK:
		_world.step()
	_world.sim.toilets.visit_of(p.id).deadline = _world.clock.tick + 1
	_world.step()
	return p


func test_past_the_deadline_a_walker_gives_up_with_its_need_kept() -> void:
	var p := _past_deadline_in(Passenger.Stage.TOILET_WALK)
	print("walker now %s need %d" % [Passenger.Stage.keys()[p.stage], p.toilet_need])
	assert_object(_world.sim.toilets.visit_of(p.id)).is_null()
	# On with its journey: boarding has begun, so from the gate to the exit.
	assert_int(StageKinds.leg(p.stage)).is_equal(StageKinds.Leg.AIRSIDE)
	assert_int(p.toilet_need).is_greater_equal(95)


func test_past_the_deadline_one_stepping_in_turns_back_as_far_as_it_came() -> void:
	var p := _past_deadline_in(Passenger.Stage.TOILET_ENTER)
	var spent := _world.clock.tick - p.stage_tick
	print(
		(
			"stepping in now %s, %d of %d ticks out done"
			% [Passenger.Stage.keys()[p.stage], spent, ToiletSim.EXIT_TICKS]
		)
	)
	assert_int(p.stage).is_equal(Passenger.Stage.TOILET_EXIT)
	# It had stepped in for 2 ticks, so 2 of the way out are left.
	assert_int(ToiletSim.EXIT_TICKS - spent).is_equal(2)
	assert_int(p.toilet_need).is_greater_equal(95)


func test_past_the_deadline_one_sitting_down_stands_up_again() -> void:
	var p := _past_deadline_in(Passenger.Stage.TOILET_SITTING_DOWN)
	print("sitting down now %s" % Passenger.Stage.keys()[p.stage])
	assert_int(p.stage).is_equal(Passenger.Stage.TOILET_STANDING_UP)
	assert_int(p.toilet_need).is_greater_equal(95)


func test_past_the_deadline_one_using_the_stall_stands_up_with_the_need_reset() -> void:
	var p := _past_deadline_in(Passenger.Stage.TOILET_USE)
	print("using now %s need %d" % [Passenger.Stage.keys()[p.stage], p.toilet_need])
	assert_int(p.stage).is_equal(Passenger.Stage.TOILET_STANDING_UP)
	assert_int(p.toilet_need).is_equal(0)


func test_standing_up_and_stepping_out_do_not_check_the_deadline() -> void:
	var p := _past_deadline_in(Passenger.Stage.TOILET_STANDING_UP)
	assert_int(p.stage).is_equal(Passenger.Stage.TOILET_STANDING_UP)
	while _world.sim.toilets.visit_of(p.id) != null and _world.clock.tick < 3000:
		_world.step()
	print("left at %d as %s" % [_world.clock.tick, Passenger.Stage.keys()[p.stage]])
	assert_int(StageKinds.leg(p.stage)).is_equal(StageKinds.Leg.AIRSIDE)
	# Back on its stall's approach cell, the row in front of the stalls.
	assert_int(p.at.y).is_equal(4)
