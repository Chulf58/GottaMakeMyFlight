class_name TestStaffReachCost
extends GdUnitTestSuite
## The staff reach rule costs about one flood per rectangle or belt line, not
## one per cell: on the full 64x64 grid, floored, with an entrance and a desk
## whose spot staff reach, a 50x10 Remove rectangle (about 30 s when every
## cell flooded twice) and a 59-cell belt preview each take well under their
## bound. The times are printed; the bounds are generous so a slow machine
## does not fail them.

const SIZE := Vector2i(64, 64)
const DESK_SPOT := Vector2i(32, 9)
const CLEAR := Rect2i(5, 20, 50, 10)
const BOUND_MS := 3000
## Checked cell by cell this preview took about 1.9 s on the dev machine.
const BELT_BOUND_MS := 1000

var _template := {}
var _grid: BuildGrid
var _desk := 0


func before() -> void:
	var grid := PassengerTestWorld.floored(SIZE)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, SIZE.y - 1), 2)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(32, 10), 0)
	_template = grid.to_snapshot()


func before_test() -> void:
	_grid = BuildGrid.new(SIZE)
	assert_bool(_grid.from_snapshot(_template)).is_true()
	_desk = _grid.object_at(Vector2i(32, 10))
	assert_bool(_grid.staff_reach().has(DESK_SPOT)).is_true()


func test_a_large_remove_rectangle_floods_once() -> void:
	var start := Time.get_ticks_msec()
	var outcome := AreaDrag.clear(_grid, CLEAR)
	var ms := Time.get_ticks_msec() - start
	print(
		"clear %s: removed %d, skipped %d in %d ms" % [CLEAR, outcome.placed, outcome.skipped, ms]
	)
	assert_int(outcome.placed).is_equal(CLEAR.size.x * CLEAR.size.y)
	assert_int(outcome.skipped).is_equal(0)
	assert_bool(StaffSpots.unreachable(_grid, _desk)).is_false()
	assert_int(ms).is_less(BOUND_MS)


func test_a_long_belt_preview_floods_once() -> void:
	var start := Time.get_ticks_msec()
	var plan := BeltShaper.plan_line(_grid, Vector2i(2, 40), Vector2i(60, 40), 1)
	var ms := Time.get_ticks_msec() - start
	print("belt preview: %d new cells, %s, in %d ms" % [plan.new_cells.size(), plan.result.ok, ms])
	assert_bool(plan.result.ok).is_true()
	assert_int(plan.new_cells.size()).is_equal(59)
	assert_int(ms).is_less(BELT_BOUND_MS)
