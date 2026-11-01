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
## exit on its north wall, fifteen cells south of the plane door.

const SITE := preload("res://build/terminal_site.tres")
## The cells of the layout below, moved by the site's starter_offset so the
## boxes stand where the starter terminal does, beside the plane stand.
var _entrance_a := Vector2i(11, 35) + SITE.starter_offset
var _entrance_b := Vector2i(21, 35) + SITE.starter_offset
var _exit_cell := Vector2i(31, 10) + SITE.starter_offset
## A wall of box A, away from its door.
var _gap_a := Vector2i(10, 32) + SITE.starter_offset
var _gap_b := Vector2i(20, 32) + SITE.starter_offset

var _world: PassengerTestWorld
var _exit := 0


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	var edits: Array[BuildEdit] = []
	var off := SITE.starter_offset
	for box in [Rect2i(10, 30, 4, 6), Rect2i(20, 30, 4, 6), Rect2i(30, 10, 4, 4)]:
		for y in range(box.position.y + off.y, box.end.y + off.y):
			for x in range(box.position.x + off.x, box.end.x + off.x):
				edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	edits.append(BuildEdit.place_object(&"entrance_door", _entrance_a, 2))
	edits.append(BuildEdit.place_object(&"entrance_door", _entrance_b, 2))
	edits.append(BuildEdit.place_object(&"exit_door", _exit_cell, 0))
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
	assert_vector(Vector2(p.at)).is_equal(Vector2(_entrance_a))
	_steps(50)
	var here := p.apron_position()
	var walked := p.apron_mm
	_set_wall(_gap_a, true)
	print(
		(
			"walker %d at %s (%d mm) rerouted to %s, walk %s"
			% [p.id, here, walked, p.at, p.apron.slice(p.apron.size() - 3)]
		)
	)
	assert_array(_world.sim.layout.passenger_entrances).has_size(1)
	assert_vector(Vector2(p.at)).is_equal(Vector2(_entrance_b))
	assert_int(p.stuck).is_equal(Passenger.Stuck.NONE)
	assert_int(p.apron_mm).is_between(walked - 2, walked + 2)
	assert_vector(p.apron_position()).is_equal_approx(here, Vector3(0.01, 0.01, 0.01))
	assert_vector(p.apron.back()).is_equal(_world.grid.cell_to_world(_entrance_b))
	assert_bool(_walk_left_is_open(p, _entrance_b)).is_true()
	var inside := func(q: Passenger) -> bool: return q.stage >= Passenger.Stage.TO_CHECKIN
	var ticks := _step_until(p, inside, 600)
	print("walker %d came in at %s after %d ticks" % [p.id, p.at, ticks])
	assert_int(ticks).is_less(600)
	assert_vector(Vector2(p.at)).is_equal(Vector2(_entrance_b))


## Forty walkers on the grid sent to entrance B by one wall edit: the walk
## field to B is searched once for all of them (OutsideWalks.fields_searched),
## not once per walker.
func test_many_walkers_reroute_in_one_revalidate() -> void:
	var walkers: Array[Passenger] = []
	for i in 40:
		walkers.append(_world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT)))
	_steps(50)
	var searched := OutsideWalks.fields_searched
	var started := Time.get_ticks_usec()
	_set_wall(_gap_a, true)
	var usec := Time.get_ticks_usec() - started
	searched = OutsideWalks.fields_searched - searched
	var at_b := 0
	for p in walkers:
		if p.at == _entrance_b and p.stuck == Passenger.Stuck.NONE:
			at_b += 1
	print(
		(
			"%d walkers x 2 entrances: %d sent to B in %d us, %d fields searched"
			% [walkers.size(), at_b, usec, searched]
		)
	)
	assert_int(at_b).is_equal(walkers.size())
	assert_int(searched).is_equal(1)


func test_with_no_entrance_left_the_walker_waits_where_it_stands_until_one_is_back() -> void:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	_steps(50)
	_set_wall(_gap_a, true)
	_set_wall(_gap_b, true)
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
	_set_wall(_gap_a, false)
	assert_int(p.stuck).is_equal(Passenger.Stuck.NONE)
	var inside := func(q: Passenger) -> bool: return q.stage >= Passenger.Stage.TO_CHECKIN
	var ticks := _step_until(p, inside, 600)
	print("walker %d came in at %s after %d ticks" % [p.id, p.at, ticks])
	assert_int(ticks).is_less(600)
	assert_vector(Vector2(p.at)).is_equal(Vector2(_entrance_a))


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
	(
		assert_bool(
			_world.grid.apply(BuildEdit.paint_floor(Vector2i(31, 5) + SITE.starter_offset, 1, 1)).ok
		)
		. is_true()
	)
	print("apron walker %d at %s, walk now %s" % [p.id, here, p.apron])
	assert_int(p.stuck).is_equal(Passenger.Stuck.NONE)
	assert_vector(p.apron.back()).is_equal(end)
	assert_vector(p.apron_position()).is_equal_approx(here, Vector3(0.01, 0.01, 0.01))
	assert_bool(_walk_left_is_open(p, _exit_cell)).is_true()
	var made := func(q: Passenger) -> bool: return q.stage == Passenger.Stage.MADE
	assert_int(_step_until(p, made, 600)).is_less(600)


func test_an_apron_walker_with_no_way_on_waits_until_it_is_cleared() -> void:
	var p := _apron_walker()
	var row: Array[BuildEdit] = []
	for x in SITE.grid_size.x:
		row.append(
			BuildEdit.paint_floor(Vector2i(x, 5) + SITE.starter_offset, BuildGrid.FLOOR_TILE, 1)
		)
	_world.grid.apply_batch(row)
	var stood := p.apron_position()
	_steps(30)
	print("apron walker %d waits at %s, stuck %s" % [p.id, stood, Passenger.Stuck.keys()[p.stuck]])
	assert_int(p.stage).is_equal(Passenger.Stage.APRON)
	assert_int(p.stuck).is_equal(Passenger.Stuck.NO_ROUTE)
	assert_vector(p.apron_position()).is_equal(stood)
	(
		assert_bool(
			_world.grid.apply(BuildEdit.remove_floor(Vector2i(40, 5) + SITE.starter_offset)).ok
		)
		. is_true()
	)
	assert_int(p.stuck).is_equal(Passenger.Stuck.NONE)
	var made := func(q: Passenger) -> bool: return q.stage == Passenger.Stage.MADE
	var ticks := _step_until(p, made, 900)
	print("apron walker %d made it after %d ticks" % [p.id, ticks])
	assert_int(ticks).is_less(900)
