class_name TestBoothStepIn
extends GdUnitTestSuite
## A booth guest steps in from the bench's open end (board 64ee4dc0). The bench
## has a high end panel across its whole depth behind the seat root, so the
## shuffle from the approach cell first steps forward inside that cell, beside
## the bench, to a line just ahead of the root and then slides in along it: a
## straight line from the approach cell (0.45 m behind the root) would carry
## the body through the end panel (windowed probe game/spike/food_seats_probe.gd:
## 4 to 176 body points inside it at every booth seat). It leaves the approach
## cell at walking pace, with no lunge, and stands up along the same path. A
## guest with a roller, held at the approach cell while it sets the roller down
## (SitHold), takes the same path into the seat. The cafe table's chairs, also
## stepped into from a cell to the side, keep their straight shuffle.

## The body reaches this far to each side of its spot: while the spot is
## nearer the seat root than this plus PANEL_FACE_M, part of the body is past
## the end panel's inner face.
const BODY_HALF_M := 0.25
## The bench's end panel's inner face, across from the seat root
## (tools/blender/interior/build_services_kit.py: the panel at x 0.86-0.92 m,
## the roots at x 0.5 m).
const PANEL_FACE_M := 0.42
## The approach cell's forward edge, ahead of the root (the root is 0.45 m from
## the seat cell's centre towards the table, the approach cell beside it).
const CELL_EDGE_M := 0.05
const WALK_M := PassengerSim.WALK_MM / 1000.0

var _worlds: Array[PassengerTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in _worlds:
		world.free_all()
	_worlds.clear()


## A guest of a restaurant with `table` (pulling a roller with `roller`)
## stepped to the first tick of its sit-down.
func _sitting(table: StringName, roller := false) -> Array:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid, false, &"restaurant", true, &"cafe_counter", table)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_worlds.append(world)
	var p: Passenger = null
	for attempt in 200:
		p = world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		p.cafe_cooldown = 1000000
		p.hunger = 30
		p.carry_on = 1 if roller else 0
		if not roller or SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER:
			break
		p.carry_on = 0
		ToiletTestLayout.calm(p)
	p.liquids = false
	p.alarm = false
	while p.stage != Passenger.Stage.TO_GATE and world.clock.tick < 1500:
		world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
	assert_bool(world.sim.cafes.try_visit(p)).override_failure_message("visit refused").is_true()
	while p.stage != Passenger.Stage.CAFE_SITTING_DOWN and world.clock.tick < 3000:
		world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_SITTING_DOWN)
	return [world, p]


## `at` in `seat`'s frame: [ahead of the root, across from the root].
func _seat_xy(world: PassengerTestWorld, seat: Dictionary, at: Vector3) -> Vector2:
	var facing: Vector2i = seat["facing"]
	var ahead := Vector3(facing.x, 0.0, facing.y)
	var d := at - BuildObjectDef.seat_root_world(world.grid, seat)
	var forward := d.dot(ahead)
	return Vector2(forward, (d - ahead * forward).length())


## The sim's spot each tick while `p` stays in `stage` (at most `ticks` + 1
## samples), in the seat's frame.
func _track(
	world: PassengerTestWorld, p: Passenger, stage: Passenger.Stage, ticks: int
) -> Array[Vector2]:
	var seat: Dictionary = world.sim.cafes.visit_of(p.id).seat
	var out: Array[Vector2] = []
	for k in ticks + 1:
		if p.stage != stage:
			break
		out.append(_seat_xy(world, seat, world.sim.cafes.seat_position(p)))
		world.step()
	return out


## Every spot of `path` where the body reaches past the bench end is ahead of
## the root; at least three such spots (or nothing was checked).
func _assert_clear_of_the_end_panel(path: Array[Vector2]) -> void:
	var near := 0
	for at in path:
		if at.y < PANEL_FACE_M + BODY_HALF_M:
			near += 1
			var why := "the body passes the bench end behind the root at %s" % at
			assert_float(at.x).override_failure_message(why).is_greater_equal(0.0)
	assert_int(near).is_greater(2)


## No tick's step is longer than `most` walking steps; the first and last no
## longer than 1.2 walking steps (the guest arrives walking and stops seated).
func _assert_no_lunge(path: Array[Vector2], most: float) -> Array[float]:
	var steps: Array[float] = []
	for i in range(1, path.size()):
		steps.append(path[i].distance_to(path[i - 1]))
	var moving: Array[float] = steps.filter(func(s: float) -> bool: return s > 1e-4)
	assert_int(moving.size()).is_greater(5)
	assert_float(moving[0]).is_less_equal(1.2 * WALK_M)
	assert_float(moving[-1]).is_less_equal(1.2 * WALK_M)
	for s in moving:
		assert_float(s).is_less_equal(most * WALK_M)
	return moving


func test_a_booth_guest_steps_in_ahead_of_the_end_panel_at_walking_pace() -> void:
	var made := _sitting(&"restaurant_booth")
	var path := _track(made[0], made[1], Passenger.Stage.CAFE_SITTING_DOWN, CafeSim.SHUFFLE_TICKS)
	var steps := _assert_no_lunge(path, 1.6)
	print("booth sit-down [ahead, across] per tick: %s steps %s" % [path, steps])
	# Control: the shuffle starts at the approach cell, behind the root and a
	# cell to its side, so a check on the bench end has something to see.
	assert_float(path[0].x).is_less(-0.4)
	assert_float(path[0].y).is_greater(0.9)
	_assert_clear_of_the_end_panel(path)
	assert_float(path[-1].length()).is_less(0.001)


## The spot stays inside the approach cell until it is inside the booth's
## footprint: no part of the path is on the next cell's edge, which the seat's
## reachability does not check.
func test_the_booth_step_in_path_keeps_inside_the_approach_cell() -> void:
	var made := _sitting(&"restaurant_booth")
	var world: PassengerTestWorld = made[0]
	var p: Passenger = made[1]
	var seat: Dictionary = world.sim.cafes.visit_of(p.id).seat
	var approach := world.grid.cell_to_world(seat["approach"])
	var root := BuildObjectDef.seat_root_world(world.grid, seat)
	var outside := 0
	for i in 101:
		var f := i / 100.0
		var at := _seat_xy(world, seat, approach.lerp(root, f) + world.sim.cafes.shuffle_bend(p, f))
		if at.y > 0.5:
			outside += 1
			var why := "the path leaves the approach cell at %s" % at
			assert_float(at.x).override_failure_message(why).is_less(CELL_EDGE_M)
	assert_int(outside).is_greater(10)


func test_a_booth_guest_stands_up_along_the_same_path() -> void:
	var made := _sitting(&"restaurant_booth")
	var world: PassengerTestWorld = made[0]
	var p: Passenger = made[1]
	while p.stage != Passenger.Stage.CAFE_SEATED and world.clock.tick < 4000:
		world.step()
	world.sim.cafes.visit_of(p.id).dwell_end = world.clock.tick + 1
	while p.stage != Passenger.Stage.CAFE_STANDING_UP and world.clock.tick < 4000:
		world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_STANDING_UP)
	var seat: Dictionary = world.sim.cafes.visit_of(p.id).seat
	var path := _track(world, p, Passenger.Stage.CAFE_STANDING_UP, CafeSim.up_ticks(p))
	# The stand-up's last tick ends at the approach cell, where the walk starts.
	path.append(_seat_xy(world, seat, world.grid.cell_to_world(seat["approach"])))
	var steps := _assert_no_lunge(path, 1.6)
	print("booth stand-up [ahead, across] per tick: %s steps %s" % [path, steps])
	assert_float(path[0].length()).is_less(0.001)
	# The sim's last spot standing up: a tick's step from the approach cell.
	assert_float(path[-2].distance_to(path[-1])).is_greater(0.05)
	assert_float(path[-1].x).is_less(-0.4)
	assert_float(path[-1].y).is_greater(0.9)
	_assert_clear_of_the_end_panel(path)


## Drawn as PassengerViews draws it: the sim's spot with the cafe seat step,
## held at the approach cell while the roller is set down (SitHold.offset(),
## with no prop record here: as long as a pull>floor park), then eased in.
func test_a_booth_guest_with_a_roller_takes_the_same_path_in() -> void:
	var made := _sitting(&"restaurant_booth", true)
	var world: PassengerTestWorld = made[0]
	var p: Passenger = made[1]
	var seat: Dictionary = world.sim.cafes.visit_of(p.id).seat
	var props: CarryOnProps = auto_free(CarryOnProps.new())
	var held := SitHold.held_ticks(props, world.sim, p)
	var path: Array[Vector2] = []
	for k in PassengerSim.SIT_DOWN_TICKS + 1:
		var now := world.sim.world_position(p) + CafeChairs.offset(world.sim, p)
		path.append(_seat_xy(world, seat, now + SitHold.offset(props, world.sim, p, now)))
		world.step()
	print("booth roller sit-down, held %d ticks, drawn [ahead, across]: %s" % [held, path])
	# Control: a roller guest is held at the approach cell, longer than the
	# sim's shuffle, so the ease into the seat is the view's own.
	assert_int(held).is_greater(CafeSim.SHUFFLE_TICKS)
	assert_float(path[held - 1].distance_to(path[0])).is_less(0.001)
	_assert_clear_of_the_end_panel(path)
	assert_float(path[-1].length()).is_less(0.03)


func test_a_cafe_table_guest_keeps_the_straight_shuffle() -> void:
	var made := _sitting(&"cafe_table")
	var path := _track(made[0], made[1], Passenger.Stage.CAFE_SITTING_DOWN, CafeSim.SHUFFLE_TICKS)
	print("cafe table shuffle [ahead, across] per tick: %s" % [path])
	assert_float(path[0].length()).is_greater(0.4)
	# Every spot on the line from the approach cell to the root.
	for at in path:
		assert_float(absf(at.x * path[0].y - at.y * path[0].x)).is_less(0.001)
	assert_float(path[-1].length()).is_less(0.001)
