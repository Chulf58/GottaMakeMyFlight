class_name TestOutsideWalks
extends GdUnitTestSuite
## Passengers outside on the airport site keep a walk that is still there
## (OutsideWalks, decision player-built-terminal-technical-design-site-plot-
## indoor-mask-passenger-eligibility, point 6): a road walker whose entrance
## opens mid-walk walks to another entrance, or with none stops where it
## stands until one is back, and an apron walker whose way to the plane is
## built over walks round it, or stops until it is cleared.
##
## Two walled boxes on a site-sized grid, each with an entrance on its south
## wall (A first, so new passengers head for it), and a third box with an
## exit on its north wall, ten cells from the plane edge.

const SITE := preload("res://build/terminal_site.tres")
const ENTRANCE_A := Vector2i(11, 35)
const ENTRANCE_B := Vector2i(21, 35)
const EXIT_CELL := Vector2i(31, 10)
## A wall of box A, away from its door.
const GAP_A := Vector2i(10, 32)
const GAP_B := Vector2i(20, 32)

var _world: PassengerTestWorld
var _exit := 0


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	var edits: Array[BuildEdit] = []
	for box in [Rect2i(10, 30, 4, 6), Rect2i(20, 30, 4, 6), Rect2i(30, 10, 4, 4)]:
		for y in range(box.position.y, box.end.y):
			for x in range(box.position.x, box.end.x):
				edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	edits.append(BuildEdit.place_object(&"entrance_door", ENTRANCE_A, 2))
	edits.append(BuildEdit.place_object(&"entrance_door", ENTRANCE_B, 2))
	edits.append(BuildEdit.place_object(&"exit_door", EXIT_CELL, 0))
	for result in grid.apply_batch(edits):
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	EnclosureKit.close_floor(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.sim.site = SITE
	_exit = ReferenceTerminal.object_ids(grid)["exits"][0]


func after_test() -> void:
	_world.free_all()
	_world = null


func _set_wall(cell: Vector2i, open: bool) -> void:
	var side := BuildGrid.Side.WEST
	var edit := BuildEdit.remove_wall(cell, side) if open else BuildEdit.place_wall(cell, side)
	var result := _world.grid.apply(edit)
	assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()


func _steps(count: int) -> void:
	for i in count:
		_world.step()


## Steps until `done` holds for `p` or `limit` ticks pass; returns the ticks.
func _step_until(p: Passenger, done: Callable, limit: int) -> int:
	for i in limit:
		if done.call(p):
			return i
		_world.step()
	return limit


## Every grid cell the walk left of `p` passes is open ground, or `door`.
func _walk_left_is_open(p: Passenger, door: Vector2i) -> bool:
	var grid := _world.grid
	var mm := p.apron_mm
	var total := p.apron_total_mm()
	var probe := Passenger.new()
	probe.apron = p.apron
	while mm <= total:
		probe.apron_mm = mm
		var cell := grid.world_to_cell(probe.apron_position())
		if (
			grid.in_bounds(cell)
			and cell != door
			and not SiteRoutes.is_open_ground(grid, SITE, cell)
		):
			print("walk left crosses %s" % cell)
			return false
		mm += 200
	return true


func test_a_road_walker_whose_entrance_opens_walks_to_the_other_entrance() -> void:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	assert_vector(Vector2(p.at)).is_equal(Vector2(ENTRANCE_A))
	_steps(50)
	var here := p.apron_position()
	var walked := p.apron_mm
	_set_wall(GAP_A, true)
	print(
		(
			"walker %d at %s (%d mm) rerouted to %s, walk %s"
			% [p.id, here, walked, p.at, p.apron.slice(p.apron.size() - 3)]
		)
	)
	assert_array(_world.sim.layout.passenger_entrances).has_size(1)
	assert_vector(Vector2(p.at)).is_equal(Vector2(ENTRANCE_B))
	assert_int(p.stuck).is_equal(Passenger.Stuck.NONE)
	assert_int(p.apron_mm).is_between(walked - 2, walked + 2)
	assert_vector(p.apron_position()).is_equal_approx(here, Vector3(0.01, 0.01, 0.01))
	assert_vector(p.apron.back()).is_equal(_world.grid.cell_to_world(ENTRANCE_B))
	assert_bool(_walk_left_is_open(p, ENTRANCE_B)).is_true()
	var inside := func(q: Passenger) -> bool: return q.stage >= Passenger.Stage.TO_CHECKIN
	var ticks := _step_until(p, inside, 600)
	print("walker %d came in at %s after %d ticks" % [p.id, p.at, ticks])
	assert_int(ticks).is_less(600)
	assert_vector(Vector2(p.at)).is_equal(Vector2(ENTRANCE_B))


func test_with_no_entrance_left_the_walker_waits_where_it_stands_until_one_is_back() -> void:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	_steps(50)
	_set_wall(GAP_A, true)
	_set_wall(GAP_B, true)
	assert_array(_world.sim.layout.passenger_entrances).is_empty()
	var stood := p.apron_position()
	_steps(40)
	print(
		(
			"walker %d waits at %s, now %s, stuck %s"
			% [p.id, stood, p.apron_position(), Passenger.Stuck.keys()[p.stuck]]
		)
	)
	assert_int(p.stage).is_equal(Passenger.Stage.SPAWNED)
	assert_int(p.stuck).is_equal(Passenger.Stuck.NO_ROUTE)
	assert_vector(p.apron_position()).is_equal(stood)
	_set_wall(GAP_A, false)
	assert_int(p.stuck).is_equal(Passenger.Stuck.NONE)
	var inside := func(q: Passenger) -> bool: return q.stage >= Passenger.Stage.TO_CHECKIN
	var ticks := _step_until(p, inside, 600)
	print("walker %d came in at %s after %d ticks" % [p.id, p.at, ticks])
	assert_int(ticks).is_less(600)
	assert_vector(Vector2(p.at)).is_equal(Vector2(ENTRANCE_A))


## A passenger put on the apron walk from the exit, 1.5 m out.
func _apron_walker() -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.stage = Passenger.Stage.APRON
	p.exit_object = _exit
	p.apron = OutsideWalks.departure(_world.sim, _exit)
	p.apron_mm = 1500
	assert_bool(_world.sim.files.join_plane(_world.sim, p)).is_true()
	return p


func test_an_apron_walker_walks_round_floor_laid_across_its_walk() -> void:
	var p := _apron_walker()
	var end: Vector3 = p.apron.back()
	var here := p.apron_position()
	assert_bool(_world.grid.apply(BuildEdit.paint_floor(Vector2i(31, 5), 1, 1)).ok).is_true()
	print("apron walker %d at %s, walk now %s" % [p.id, here, p.apron])
	assert_int(p.stuck).is_equal(Passenger.Stuck.NONE)
	assert_vector(p.apron.back()).is_equal(end)
	assert_vector(p.apron_position()).is_equal_approx(here, Vector3(0.01, 0.01, 0.01))
	assert_bool(_walk_left_is_open(p, EXIT_CELL)).is_true()
	var made := func(q: Passenger) -> bool: return q.stage == Passenger.Stage.MADE
	assert_int(_step_until(p, made, 600)).is_less(600)


func test_an_apron_walker_with_no_way_on_waits_until_it_is_cleared() -> void:
	var p := _apron_walker()
	var row: Array[BuildEdit] = []
	for x in SITE.grid_size.x:
		row.append(BuildEdit.paint_floor(Vector2i(x, 5), BuildGrid.FLOOR_TILE, 1))
	_world.grid.apply_batch(row)
	var stood := p.apron_position()
	_steps(30)
	print("apron walker %d waits at %s, stuck %s" % [p.id, stood, Passenger.Stuck.keys()[p.stuck]])
	assert_int(p.stage).is_equal(Passenger.Stage.APRON)
	assert_int(p.stuck).is_equal(Passenger.Stuck.NO_ROUTE)
	assert_vector(p.apron_position()).is_equal(stood)
	assert_bool(_world.grid.apply(BuildEdit.remove_floor(Vector2i(40, 5))).ok).is_true()
	assert_int(p.stuck).is_equal(Passenger.Stuck.NONE)
	var made := func(q: Passenger) -> bool: return q.stage == Passenger.Stage.MADE
	var ticks := _step_until(p, made, 900)
	print("apron walker %d made it after %d ticks" % [p.id, ticks])
	assert_int(ticks).is_less(900)
