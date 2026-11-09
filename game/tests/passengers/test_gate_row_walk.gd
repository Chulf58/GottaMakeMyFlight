extends GdUnitTestSuite
## A guest bound for a gate chair walks one cell out from the row of chair
## fronts and turns in only at its own (user ruling gate-chair-row-walk-
## guests-walk-one-cell-out-from-the-chair, board 11922532): GateRowWalk.path()
## asks BuildGrid.find_path_costed() with every other front costing
## GateRowWalk.FRONT_COST times its step, for that query only. The reference
## world's row of fronts at (11..16, 4), the chairs one cell north; pair1_a of
## the windowed gate_chair_roller_probe walks from (17, 4) to its front (14, 4).

const FRONT := Vector2i(14, 4)
const START := Vector2i(17, 4)
## The fronts between START and FRONT.
const PASSED: Array[Vector2i] = [Vector2i(16, 4), Vector2i(15, 4)]
## From a front to its seat: the chairs are one cell north.
const SEAT_STEP := Vector2i(0, -1)
## A row of fronts whose outer row runs along a wall (its south edge): the
## probe's female_right walks from (10, 7) to her front (13, 7).
const WALLED_FRONT := Vector2i(13, 7)
const WALLED_START := Vector2i(10, 7)

var _world: PassengerTestWorld
var _seat: Dictionary = {}


func before() -> void:
	PassengerTestWorld.tracker = self
	_world = PassengerTestWorld.reference_world()
	_world.run_to(10)
	for s: Dictionary in _world.sim.layout.seats:
		if s["front"] == FRONT:
			_seat = s


func after() -> void:
	_world.free_all()
	_world = null
	PassengerTestWorld.tracker = null


static func _meets(path: Array[Vector2i], cells: Array[Vector2i]) -> Array[Vector2i]:
	var met: Array[Vector2i] = []
	for cell in cells:
		if cell in path:
			met.append(cell)
	return met


func test_the_fronts_passed_are_seat_fronts() -> void:
	assert_bool(_seat.is_empty()).is_false()
	var fronts := GateRowWalk.costly_fronts(_world.sim, FRONT)
	for cell in PASSED:
		assert_bool(cell in fronts).is_true()


func test_a_guest_walks_one_cell_out_and_turns_in_at_its_own_front() -> void:
	var plain := _world.sim.grid.find_path(START, FRONT)
	var costed := GateRowWalk.path(_world.sim, START, FRONT, FRONT + SEAT_STEP)
	print("ROW_WALK plain %s costed %s" % [plain, costed])
	# Control: the plain walk goes along the fronts.
	assert_array(_meets(plain, PASSED)).is_not_empty()
	assert_array(_meets(costed, PASSED)).is_empty()
	assert_vector(costed[0]).is_equal(START)
	assert_vector(costed[-1]).is_equal(FRONT)


func test_a_guest_turns_in_square_at_its_own_front() -> void:
	var costed := GateRowWalk.path(_world.sim, START, FRONT, FRONT + SEAT_STEP)
	var outer := FRONT - SEAT_STEP
	# The last step is straight out of the outer cell in front of the front,
	# never a diagonal across the neighbour's gap.
	assert_vector(costed[-2]).is_equal(outer)
	assert_int((costed[-1] - costed[-2]).length_squared()).is_equal(1)
	assert_array(_meets(costed, PASSED)).is_empty()
	# Control: the costed walk alone (no square turn-in) cuts the corner.
	var cut := _world.sim.grid.find_path_costed(
		START, FRONT, GateRowWalk.costly_fronts(_world.sim, FRONT), GateRowWalk.FRONT_COST
	)
	assert_int((cut[-1] - cut[-2]).length_squared()).is_equal(2)


func test_no_cost_along_a_walled_outer_row() -> void:
	var grid := _world.sim.grid
	# Control: the outer row in front of these fronts runs along a wall.
	for x in range(WALLED_START.x + 1, WALLED_FRONT.x + 1):
		var outer := Vector2i(x, WALLED_FRONT.y) - SEAT_STEP
		assert_int(grid.wall_kind(outer, BuildGrid.Side.SOUTH)).is_not_equal(
			BuildGrid.WallKind.NONE
		)
	var fronts := GateRowWalk.costly_fronts(_world.sim, WALLED_FRONT)
	for x in range(WALLED_START.x + 1, WALLED_FRONT.x):
		assert_bool(Vector2i(x, WALLED_FRONT.y) in fronts).is_false()
	var plain := grid.find_path(WALLED_START, WALLED_FRONT)
	var walk := GateRowWalk.path(_world.sim, WALLED_START, WALLED_FRONT, WALLED_FRONT + SEAT_STEP)
	assert_array(walk).is_equal(plain)


func test_the_cost_is_off_for_the_seats_own_front() -> void:
	var fronts := GateRowWalk.costly_fronts(_world.sim, FRONT)
	assert_bool(FRONT in fronts).is_false()
	# Straight in from two cells out: its own front costs no more, so the walk
	# is the plain one, and it ends on the front.
	var out := FRONT + Vector2i(0, 2)
	var plain := _world.sim.grid.find_path(out, FRONT)
	assert_array(GateRowWalk.path(_world.sim, out, FRONT, FRONT + SEAT_STEP)).is_equal(plain)
	# Control: with its own front costly too (another guest's walk past it),
	# the same scale does change a walk along the row onto it.
	var other := FRONT + Vector2i(-1, 0)
	var past := _world.sim.grid.find_path(START, other)
	assert_array(_meets(past, [FRONT])).is_not_empty()
	(
		assert_array(_meets(GateRowWalk.path(_world.sim, START, other, other + SEAT_STEP), [FRONT]))
		. is_empty()
	)


func test_other_routes_and_the_graph_are_unchanged_after_a_query() -> void:
	var before := _world.sim.grid.find_path(START, FRONT + Vector2i(-3, 0))
	var front_before := _world.sim.grid.find_path(START, FRONT)
	GateRowWalk.path(_world.sim, START, FRONT, FRONT + SEAT_STEP)
	var after := _world.sim.grid.find_path(START, FRONT + Vector2i(-3, 0))
	# Control: these routes walk the fronts, so a weight left behind would move them.
	assert_array(_meets(before, PASSED)).is_not_empty()
	assert_array(_meets(front_before, PASSED)).is_not_empty()
	assert_array(after).is_equal(before)
	assert_array(_world.sim.grid.find_path(START, FRONT)).is_equal(front_before)
	# The staff graph is another graph: its walk is the same before and after.
	var staff := _world.sim.grid.find_staff_path(START, FRONT)
	GateRowWalk.path(_world.sim, START, FRONT, FRONT + SEAT_STEP)
	assert_array(_world.sim.grid.find_staff_path(START, FRONT)).is_equal(staff)


## A grid edit replans a TO_GATE guest bound for its seat on the costed walk;
## a guest with no seat keeps the plain one.
func test_a_replan_keeps_the_walk_one_cell_out() -> void:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.stage = Passenger.Stage.TO_GATE
	p.seat_object = _seat["object_id"]
	p.seat_cell = _seat["cell"]
	p.seat_front = _seat["front"]
	p.at = START
	p.set_path(_world.sim.grid.find_path(START, FRONT))
	PassengerEdits.replan(_world.sim, p)
	assert_array(_meets(p.path, PASSED)).is_empty()
	assert_vector(p.path_end()).is_equal(FRONT)
	# Control: not bound for a seat, the same replan walks the fronts.
	p.seat_front = Passenger.NO_CELL
	p.set_path(_world.sim.grid.find_path(START, FRONT))
	PassengerEdits.replan(_world.sim, p)
	assert_array(_meets(p.path, PASSED)).is_not_empty()
	p.stage = Passenger.Stage.MADE
