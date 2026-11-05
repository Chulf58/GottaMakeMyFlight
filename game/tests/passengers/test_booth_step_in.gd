class_name TestBoothStepIn
extends GdUnitTestSuite
## A booth guest steps in from the bench's open end (board 64ee4dc0). The bench
## has a high end panel across its whole depth behind the seat root, so the
## shuffle from the approach cell first steps forward, beside the bench, to a
## line just ahead of the root and then slides in along it: a straight line
## from the approach cell (0.45 m behind the root) would carry the body through
## the end panel (windowed probe game/spike/food_seats_probe.gd: 4 to 176 body
## points inside it at every booth seat). The cafe table's chairs, also
## stepped into from a cell to the side, keep their straight shuffle.

## The body reaches this far to each side of its spot: while the spot is
## nearer the seat root than this plus half a cell, part of the body is past
## the bench end.
const BODY_HALF_M := 0.25

var _worlds: Array[PassengerTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in _worlds:
		world.free_all()
	_worlds.clear()


## A guest of a restaurant with `table` stepped to the first tick of its sit-down.
func _sitting(table: StringName) -> Array:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid, false, &"restaurant", true, &"cafe_counter", table)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_worlds.append(world)
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.cafe_cooldown = 1000000
	p.hunger = 30
	while p.stage != Passenger.Stage.TO_GATE and world.clock.tick < 900:
		world.step()
	assert_bool(world.sim.cafes.try_visit(p)).override_failure_message("visit refused").is_true()
	while p.stage != Passenger.Stage.CAFE_SITTING_DOWN and world.clock.tick < 3000:
		world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_SITTING_DOWN)
	return [world, p]


## The drawn spot over the shuffle, one sample a tick, as [ahead of the root,
## across from the root] in the seat's frame.
func _shuffle(world: PassengerTestWorld, p: Passenger) -> Array[Vector2]:
	var seat: Dictionary = world.sim.cafes.visit_of(p.id).seat
	var root := BuildObjectDef.seat_root_world(world.grid, seat)
	var facing: Vector2i = seat["facing"]
	var ahead := Vector3(facing.x, 0.0, facing.y)
	var out: Array[Vector2] = []
	for k in CafeSim.SHUFFLE_TICKS + 1:
		var d := world.sim.cafes.seat_position(p) - root
		var forward := d.dot(ahead)
		out.append(Vector2(forward, (d - ahead * forward).length()))
		world.step()
	return out


func test_a_booth_guest_steps_in_ahead_of_the_end_panel() -> void:
	var made := _sitting(&"restaurant_booth")
	var path := _shuffle(made[0], made[1])
	print("booth shuffle [ahead, across] per tick: %s" % [path])
	# Control: the shuffle starts at the approach cell, behind the root and a
	# cell to its side, so a check on the bench end has something to see.
	assert_float(path[0].x).is_less(-0.4)
	assert_float(path[0].y).is_greater(0.9)
	var near := 0
	for at in path:
		if at.y < 0.5 + BODY_HALF_M:
			near += 1
			var why := "the body passes the bench end behind the root at %s" % at
			assert_float(at.x).override_failure_message(why).is_greater_equal(0.0)
	assert_int(near).is_greater(2)
	assert_float(path[-1].length()).is_less(0.001)


func test_a_cafe_table_guest_keeps_the_straight_shuffle() -> void:
	var made := _sitting(&"cafe_table")
	var path := _shuffle(made[0], made[1])
	print("cafe table shuffle [ahead, across] per tick: %s" % [path])
	assert_float(path[0].length()).is_greater(0.4)
	# Every spot on the line from the approach cell to the root.
	for at in path:
		assert_float(absf(at.x * path[0].y - at.y * path[0].x)).is_less(0.001)
	assert_float(path[-1].length()).is_less(0.001)
