class_name TestParkWalls
extends GdUnitTestSuite
## A roller parked beside a seat is moved out of the walls round it (board
## a40fdbaf, ParkWalls): out past a wall's end along the wall when that is the
## shorter way, out of its face otherwise, not at all when clear; and a
## floor>pull stamped with a seat's face draws its park out of the walls
## BoothRoller.fix_start() keeps for it (RollerPark.plan()).

## A wall box as PullSide.walls_near() makes one: along x, 0.14 m thick.
const HALF := Vector3(0.5 + BuildView.WALL_THICKNESS / 2.0, 1.5, BuildView.WALL_THICKNESS / 2.0)
## How far the parked roller is put into the wall in each case.
const INTO_M := 0.04


## One wall box at the origin, along x, as PullSide.walls_near() builds it.
func _wall() -> Array:
	return [[Vector3(0.0, HALF.y, 0.0), [Vector3.RIGHT, Vector3.UP, Vector3.BACK], HALF]]


## A roller parked (RollerPark.park(), right hand, scale 1) for a body at
## `body`, facing -x: the park is on its -z side, towards the wall.
func _parked(body: Vector3) -> Transform3D:
	return RollerPark.park(Transform3D(Basis(Vector3.UP, -PI / 2.0), body), 0, 1.0)


## [least, most] of the parked roller's box corners along `axis`.
func _span(xf: Transform3D, axis: Vector3) -> Vector2:
	var box := CarryOnProps.bag_box(SecurityLooks.Kind.ROLLER)
	var span := Vector2(INF, -INF)
	for k in 8:
		var d := (xf * box.get_endpoint(k)).dot(axis)
		span = Vector2(minf(span.x, d), maxf(span.y, d))
	return span


## A park whose corner is INTO_M into the wall's end, along it and across it,
## moves out along the wall (the shorter way when the corner is less far in
## along than across) by about that depth, and is then clear. Control: it was
## in the wall.
func test_a_park_in_a_wall_end_moves_out_along_the_wall() -> void:
	var walls := _wall()
	var probe := _parked(Vector3.ZERO)
	var along := _span(probe, Vector3.RIGHT)
	var across := _span(probe, Vector3.BACK)
	# The roller's box reaches INTO_M past the wall's -x end and 1.5 times that
	# past its +z face.
	var body := Vector3(-HALF.x - along.y + INTO_M, 0.0, HALF.z - across.x - 1.5 * INTO_M)
	var parked := _parked(body)
	assert_bool(ParkWalls.inside(parked, walls)).is_true()
	var moved := ParkWalls.shift(parked, walls)
	print("park in the wall's end: moved %s" % moved)
	assert_float(moved.length()).is_equal_approx(INTO_M + ParkWalls.SLACK_M, 0.002)
	assert_float(absf(moved.x)).is_greater(absf(moved.z) + 0.03)
	parked.origin += moved
	assert_bool(ParkWalls.inside(parked, walls)).is_false()


## A park INTO_M into the middle of a wall's face moves out of the face by
## that depth, and is then clear. Control: it was in the wall.
func test_a_park_in_a_wall_middle_moves_out_of_its_face() -> void:
	var walls := _wall()
	var probe := _parked(Vector3.ZERO)
	var along := _span(probe, Vector3.RIGHT)
	var across := _span(probe, Vector3.BACK)
	var body := Vector3(-(along.x + along.y) / 2.0, 0.0, HALF.z - across.x - INTO_M)
	var parked := _parked(body)
	assert_bool(ParkWalls.inside(parked, walls)).is_true()
	var moved := ParkWalls.shift(parked, walls)
	print("park in the wall's middle: moved %s" % moved)
	assert_vector(moved).is_equal_approx(
		Vector3(0.0, 0.0, INTO_M + ParkWalls.SLACK_M), Vector3.ONE * 0.002
	)
	parked.origin += moved
	assert_bool(ParkWalls.inside(parked, walls)).is_false()


## A park clear of the wall is not moved. Control: the same park moved
## 0.1 m towards the wall is in it.
func test_a_park_clear_of_a_wall_is_not_moved() -> void:
	var walls := _wall()
	var probe := _parked(Vector3.ZERO)
	var across := _span(probe, Vector3.BACK)
	var body := Vector3(0.0, 0.0, HALF.z - across.x + 0.05)
	assert_vector(ParkWalls.shift(_parked(body), walls)).is_equal(Vector3.ZERO)
	assert_bool(ParkWalls.inside(_parked(body - Vector3.BACK * 0.1), walls)).is_true()


## A floor>pull stamped with a seat's face ("up_near") draws its park
## (RollerPark.plan() in the park, between the lift's and the park's ends)
## out of the wall boxes on its record, and in the wall with none. Control:
## the same move with no boxes draws the roller in the wall.
func test_a_faced_pick_up_draws_its_park_out_of_the_kept_walls() -> void:
	var walls := _wall()
	var probe := _parked(Vector3.ZERO)
	var across := _span(probe, Vector3.BACK)
	var body := Transform3D(
		Basis(Vector3.UP, -PI / 2.0), Vector3(0.0, 0.0, HALF.z - across.x - INTO_M)
	)
	var drawn: Array[bool] = []
	for kept in [false, true]:
		var bag := {
			"kind": SecurityLooks.Kind.ROLLER,
			"was": SecurityLooks.Home.FLOOR * 4,
			"carry_from": SecurityLooks.Carry.PULL,
			"home": SecurityLooks.Home.HAND * 4,
			"park": true,
			"ticks": RollerPark.TICKS_UP,
			"park_frame": body,
			"up_near": true,
			"park_took": RollerPark.REACH_END,
		}
		if kept:
			bag["wall_boxes"] = walls
		var start := body * Transform3D(Basis.IDENTITY, Vector3(-0.34, 0.0, 0.07))
		var looks := {"scale": 1.0, "bar_z": 0.9, "grips": [Vector3.ZERO, Vector3.ZERO]}
		var plan := RollerPark.plan(bag, 0.65, start, start, body, {}, looks)
		drawn.append(ParkWalls.inside(plan["xf"], walls))
	print("faced pick-up in the wall: no boxes %s, boxes kept %s" % drawn)
	assert_bool(drawn[0]).is_true()
	assert_bool(drawn[1]).is_false()


## A lying roller whose middle lies past the wall's centre plane, seen from its
## home (the chair front or walker it belongs to, on the wall's -z side), is
## moved out of the wall on the home's side, and is then clear of it, with
## its whole box on that side. Control: worked out from the roller alone
## (no home), the shorter way took it out through the far face (board
## f1fc1e54: 0.58 m out to 0.739 m at a gate chair walled on both sides).
func test_a_roller_past_the_wall_middle_moves_back_to_its_home_side() -> void:
	var walls := _wall()
	var across := _span(Transform3D.IDENTITY, Vector3.BACK)
	# Its box's middle 0.08 m past the wall's centre plane, on the far side.
	var middle := 0.08 - (across.x + across.y) / 2.0
	var lying := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, middle))
	var home := Vector3(0.0, 0.0, -0.5)
	assert_bool(ParkWalls.inside(lying, walls)).is_true()
	var alone := ParkWalls.shift(lying, walls)
	var homed := ParkWalls.shift(lying, walls, home)
	var out := Transform3D(lying.basis, lying.origin + alone)
	var back := Transform3D(lying.basis, lying.origin + homed)
	print("past the wall's middle: alone %s, to its home %s" % [alone, homed])
	assert_float(alone.z).is_greater(0.0)
	assert_float(_span(out, Vector3.BACK).x).is_greater(HALF.z)
	assert_float(homed.z).is_less(0.0)
	assert_bool(ParkWalls.inside(back, walls)).is_false()
	assert_float(_span(back, Vector3.BACK).y).is_less_equal(-HALF.z)
