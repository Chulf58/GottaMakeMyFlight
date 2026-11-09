class_name TestDoorSteer
extends GdUnitTestSuite
## DoorSteer (board 4b062450, decision door-steer: a guest pulling a roller is
## drawn 0.12 m off the door's centre line, away from the pulling hand): the
## side it steers to, the ease in before the door plane and out after it, and
## no offset away from a door or without a pulled roller in hand. The exit is
## the reference terminal's, on its own grid; it faces north, so a guest going
## out walks north (-z) and its left is west (-x).

const AT := Vector2i.ZERO

var _grid: BuildGrid
## The exit door's plane: the middle of its back edge.
var _plane := Vector3.ZERO
## The way out through it (world x, z).
var _out := Vector2.ZERO


func before() -> void:
	_grid = BuildGrid.new()
	assert_bool(ReferenceTerminal.build(_grid)).is_true()
	var exit: int = ReferenceTerminal.object_ids(_grid)["exits"][0]
	var record := _grid.get_object(exit)
	var step := DoorPlacement.back_step(record["facing"])
	_out = Vector2(step)
	_plane = _grid.cell_to_world(record["anchor"]) + Vector3(step.x, 0.0, step.y) * 0.5
	assert_vector(_out).is_equal(Vector2(0.0, -1.0))


func after() -> void:
	_grid = null


## A point `along` metres past the exit's plane on the way out (negative:
## before it, inside) and `across` metres to the east of its axis.
func _at(along: float, across := 0.0) -> Vector3:
	return _plane + Vector3(_out.x, 0.0, _out.y) * along + Vector3(across, 0.0, 0.0)


## A bag record as CarryOnProps keeps it: `kind` at home `home` in `hand`.
static func _bag(kind: int, home: int, hand: int, lifted := false) -> Dictionary:
	return {"kind": kind, "place": (home * 2 + hand) * 2 + int(lifted)}


static func _roller(hand: int) -> Dictionary:
	return _bag(SecurityLooks.Kind.ROLLER, SecurityLooks.Home.HAND, hand)


func test_a_right_hand_roller_steers_left_and_a_left_hand_one_right() -> void:
	var right := DoorSteer.side_of([_roller(0)], 0.0)
	var left := DoorSteer.side_of([_roller(1)], 0.0)
	assert_float(right).is_equal(1.0)
	assert_float(left).is_equal(-1.0)
	var heading := _out
	var by_right := DoorSteer.offset_at(_grid, _at(0.0), heading, right)
	var by_left := DoorSteer.offset_at(_grid, _at(0.0), heading, left)
	print("at the plane: right hand %s, left hand %s" % [by_right, by_left])
	# Walking north, the left is west (-x): away from the right hand.
	assert_vector(by_right).is_equal_approx(
		Vector3(-DoorSteer.SIDE_M, 0.0, 0.0), Vector3.ONE * 1e-5
	)
	assert_vector(by_left).is_equal_approx(Vector3(DoorSteer.SIDE_M, 0.0, 0.0), Vector3.ONE * 1e-5)


func test_the_offset_is_across_the_door_whatever_the_heading_wobble() -> void:
	var skew := _out.rotated(deg_to_rad(20.0))
	var off := DoorSteer.offset_at(_grid, _at(0.1), skew, 1.0)
	print("skewed heading %s: offset %s" % [skew, off])
	assert_float(absf(off.z)).is_less(1e-5)
	assert_float(off.x).is_less(-0.1)


func test_a_still_guest_at_the_exit_is_steered_as_one_walking_out() -> void:
	var walking := DoorSteer.offset_at(_grid, _at(-0.5), _out, 1.0)
	var still := DoorSteer.offset_at(_grid, _at(-0.5), Vector2.ZERO, 1.0)
	print("in the door cell: walking %s, still %s" % [walking, still])
	assert_float(walking.length()).is_greater(0.1)
	assert_vector(still).is_equal_approx(walking, Vector3.ONE * 1e-5)


func test_one_walking_in_through_the_exit_is_steered_to_its_own_left() -> void:
	var off := DoorSteer.offset_at(_grid, _at(0.2), -_out, 1.0)
	# Walking south, the left is east (+x).
	assert_float(off.x).is_greater(0.1)


func test_it_eases_in_before_the_plane_and_out_after_it() -> void:
	var samples := []
	var along := -1.6
	while along <= 1.6001:
		samples.append([along, DoorSteer.offset_at(_grid, _at(along), _out, 1.0).length()])
		along += 0.1
	print("along, offset: %s" % [samples])
	var peak := 0.0
	for s: Array in samples:
		var a: float = s[0]
		var m: float = s[1]
		peak = maxf(peak, m)
		if absf(a) >= DoorSteer.EASE_M:
			assert_float(m).override_failure_message("at %.1f m" % a).is_equal(0.0)
		elif absf(a) <= DoorSteer.FULL_M:
			assert_float(m).override_failure_message("at %.1f m" % a).is_equal_approx(
				DoorSteer.SIDE_M, 1e-5
			)
	assert_float(peak).is_equal_approx(DoorSteer.SIDE_M, 1e-5)
	# Rising before the plane and falling after it, with no step bigger than
	# a smooth ease gives over 0.1 m.
	for i in range(1, samples.size()):
		var step: float = samples[i][1] - samples[i - 1][1]
		assert_float(absf(step)).is_less(0.035)
		if float(samples[i][0]) <= -DoorSteer.FULL_M:
			assert_float(step).is_greater_equal(0.0)
		elif float(samples[i - 1][0]) >= DoorSteer.FULL_M:
			assert_float(step).is_less_equal(0.0)


func test_it_eases_out_off_to_the_side_of_the_opening() -> void:
	var on_axis := DoorSteer.offset_at(_grid, _at(0.0), _out, 1.0).length()
	var beside := DoorSteer.offset_at(_grid, _at(0.0, 1.5), _out, 1.0).length()
	print("on the axis %.3f, 1.5 m beside it %.3f" % [on_axis, beside])
	assert_float(on_axis).is_equal_approx(DoorSteer.SIDE_M, 1e-5)
	assert_float(beside).is_equal(0.0)


func test_no_offset_away_from_any_door() -> void:
	var far := _at(-6.0)
	assert_int(_grid.object_at(_grid.world_to_cell(far))).is_equal(0)
	assert_vector(DoorSteer.offset_at(_grid, far, _out, 1.0)).is_equal(Vector3.ZERO)
	# A door wall is not a door object: a plain grid with one has no steer.
	var walls := BuildGrid.new()
	var edits: Array[BuildEdit] = []
	for x in range(4, 9):
		edits.append(BuildEdit.place_wall(Vector2i(x, 10), BuildGrid.Side.NORTH))
	# A door goes in a wall with a plain wall on each side.
	var door := BuildGrid.WallKind.DOOR
	edits.append(BuildEdit.place_wall(Vector2i(6, 10), BuildGrid.Side.NORTH, door))
	for result in walls.apply_batch(edits):
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	assert_int(walls.wall_kind(Vector2i(6, 10), BuildGrid.Side.NORTH)).is_equal(door)
	var middle := BuildView.wall_transform(walls, Vector2i(6, 10), BuildGrid.Side.NORTH).origin
	assert_vector(DoorSteer.offset_at(walls, middle, Vector2(0.0, -1.0), 1.0)).is_equal(
		Vector3.ZERO
	)


func test_no_offset_without_a_pulled_roller() -> void:
	var hand := SecurityLooks.Home.HAND
	var cases := {
		"no bags": [],
		"roller lifted": [_bag(SecurityLooks.Kind.ROLLER, hand, 0, true)],
		"roller on the floor": [_bag(SecurityLooks.Kind.ROLLER, SecurityLooks.Home.FLOOR, 0)],
		"roller in a tray": [_bag(SecurityLooks.Kind.ROLLER, SecurityLooks.Home.TRAY, 0)],
		"case in hand": [_bag(SecurityLooks.Kind.CASE, hand, 0)],
		"no place yet": [{"kind": SecurityLooks.Kind.ROLLER}],
	}
	for name: String in cases:
		var side := DoorSteer.side_of(cases[name], 0.0)
		assert_float(side).override_failure_message(name).is_equal(0.0)
		var off := DoorSteer.offset_at(_grid, _at(0.0), _out, side)
		assert_vector(off).override_failure_message(name).is_equal(Vector3.ZERO)
	# A worn backpack (home HAND, carried on the back) beside the pulled roller
	# does not stop the steer.
	var worn := _bag(SecurityLooks.Kind.BACKPACK, hand, 0)
	assert_float(DoorSteer.side_of([worn, _roller(0)], 0.0)).is_equal(1.0)


func test_a_roller_with_another_bag_in_the_other_hand_is_not_steered() -> void:
	var hand := SecurityLooks.Home.HAND
	var case_left := _bag(SecurityLooks.Kind.CASE, hand, 1)
	var case_right := _bag(SecurityLooks.Kind.CASE, hand, 0)
	var lifted_bag := _bag(SecurityLooks.Kind.BACKPACK, hand, 1, true)
	assert_float(DoorSteer.side_of([_roller(0), case_left], 0.0)).is_equal(0.0)
	assert_float(DoorSteer.side_of([case_right, _roller(1)], 0.0)).is_equal(0.0)
	assert_float(DoorSteer.side_of([_roller(0), lifted_bag], 0.0)).is_equal(0.0)
	# Rollers pulled in both hands have no side away from both.
	assert_float(DoorSteer.side_of([_roller(0), _roller(1)], 0.0)).is_equal(0.0)
	# A case resting on the floor or in a tray leaves the hand free.
	var floor_case := _bag(SecurityLooks.Kind.CASE, SecurityLooks.Home.FLOOR, 1)
	assert_float(DoorSteer.side_of([_roller(0), floor_case], 0.0)).is_equal(1.0)


func test_a_case_taken_into_or_out_of_the_free_hand_eases_the_steer() -> void:
	var held := _bag(SecurityLooks.Kind.CASE, SecurityLooks.Home.HAND, 1)
	var down := _bag(SecurityLooks.Kind.CASE, SecurityLooks.Home.FLOOR, 1)
	var into := []
	var out_of := []
	var case_in := _moved(down, held, false)
	var case_out := _moved(held, down, true)
	for k in int(CarryLead.ticks_of(case_in)) + 2:
		into.append(DoorSteer.side_of([_roller(0), case_in], 100.0 + k))
		out_of.append(DoorSteer.side_of([_roller(0), case_out], 100.0 + k))
	print("case into the hand %s, out of it %s" % [into, out_of])
	assert_float(into[0]).is_equal(1.0)
	assert_float(into[into.size() - 1]).is_equal(0.0)
	assert_float(out_of[0]).is_equal(0.0)
	assert_float(out_of[out_of.size() - 1]).is_equal(1.0)
	for i in range(1, into.size()):
		assert_float(float(into[i]) - float(into[i - 1])).is_less_equal(0.0)
		assert_float(float(out_of[i]) - float(out_of[i - 1])).is_greater_equal(0.0)
		assert_float(absf(float(into[i]) - float(into[i - 1]))).is_less_equal(0.2)
		assert_float(absf(float(out_of[i]) - float(out_of[i - 1]))).is_less_equal(0.2)


## A roller record moved from `from` to `to` at tick 100, as CarryOnProps
## keeps it before a draw stamps the move (`drawn` false: "home" is still the
## old place) or after (`drawn` true: "home" the new, "was" the old).
static func _moved(from: Dictionary, to: Dictionary, drawn: bool) -> Dictionary:
	var bag := to.duplicate()
	bag["changed"] = 100.0
	bag["home"] = to["place"] if drawn else from["place"]
	if drawn:
		bag["was"] = from["place"]
	return bag


func _sides(bag: Dictionary) -> Array:
	var out := []
	for k in int(CarryLead.ticks_of(bag)) + 2:
		out.append(DoorSteer.side_of([bag], 100.0 + k))
	return out


func test_a_change_of_hand_crosses_over_smoothly_drawn_or_not() -> void:
	var before := _moved(_roller(0), _roller(1), false)
	var after := _moved(_roller(0), _roller(1), true)
	var ticks := CarryLead.ticks_of(after)
	var sides := _sides(before)
	print("sides over the change: %s" % [sides])
	# The same whether or not a frame has stamped the move.
	assert_array(_sides(after)).is_equal(sides)
	# From the right hand's side to the left hand's, through 0 half way.
	assert_float(sides[0]).is_equal(1.0)
	assert_float(sides[sides.size() - 1]).is_equal(-1.0)
	assert_float(DoorSteer.side_of([after], 100.0 + ticks * 0.5)).is_equal_approx(0.0, 1e-5)
	for i in range(1, sides.size()):
		assert_float(float(sides[i]) - float(sides[i - 1])).is_less_equal(0.0)
		assert_float(absf(float(sides[i]) - float(sides[i - 1]))).is_less_equal(2.0 / ticks + 1e-5)


func test_a_lift_eases_the_steer_out_and_a_set_down_eases_it_in() -> void:
	var lifted := _bag(SecurityLooks.Kind.ROLLER, SecurityLooks.Home.HAND, 0, true)
	var out := _sides(_moved(_roller(0), lifted, true))
	var back := _sides(_moved(lifted, _roller(0), false))
	print("lift %s, back to the pull %s" % [out, back])
	assert_float(out[0]).is_equal(1.0)
	assert_float(out[out.size() - 1]).is_equal(0.0)
	assert_float(back[0]).is_equal(0.0)
	assert_float(back[back.size() - 1]).is_equal(1.0)
	for i in range(1, out.size()):
		assert_float(absf(float(out[i]) - float(out[i - 1]))).is_less_equal(0.2)
		assert_float(absf(float(back[i]) - float(back[i - 1]))).is_less_equal(0.2)
