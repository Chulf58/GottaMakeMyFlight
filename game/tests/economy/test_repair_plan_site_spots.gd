class_name TestRepairPlanSiteSpots
extends GdUnitTestSuite
## Where RepairPlan looks for a new entrance on the airport site: up to
## RepairPlan.SITE_SPOTS_PER_COLUMN spots per column, nearest the road first,
## passing over a spot whose service cell objects box in, and a column with
## more spots than it keeps marks the plan capped.

const SITE := preload("res://build/terminal_site.tres")


## A plan object set up on `grid` the way make() sets it up, before its search.
func _plan_on(grid: BuildGrid) -> RepairPlan:
	var plan := RepairPlan.new()
	plan._site = SITE
	plan._layout.site = SITE
	plan._grid = grid
	grid.check_staff_reach = false
	plan._layout.rebuild(grid)
	return plan


## The doors of `sources` (RepairPlan._door_sources()) in column `x`.
static func _column(sources: Array, x: int) -> Array:
	var out := []
	for source: Dictionary in sources:
		if (source["door"] as Vector2i).x == x:
			out.append(source["door"])
	return out


func test_the_empty_plot_scan_keeps_two_spots_a_column_and_is_capped() -> void:
	var plan := _plan_on(BuildGrid.new(SITE.grid_size, SITE.grid_origin))
	var started := Time.get_ticks_usec()
	var sources := plan._door_sources(&"entrance_door")
	var usec := Time.get_ticks_usec() - started
	print("empty plot entrance scan: %d spots in %d ms" % [sources.size(), usec / 1000])
	assert_int(sources.size()).is_equal(2 * SITE.grid_size.x)
	assert_array(_column(sources, 40)).contains_exactly([Vector2i(40, 39), Vector2i(40, 38)])
	assert_bool(plan._capped).is_true()


## Door objects on three sides of (40, 38), each served from a floored cell
## away from it, box in the service cell of the spot nearest the road in
## column 40; the spots above them whose way out is blocked are passed over
## too, and the first two that work are kept.
func test_a_boxed_in_nearest_spot_is_passed_over_for_farther_ones() -> void:
	var grid := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	# [object cell, the step to its interaction cell]
	var boxes := [
		[Vector2i(39, 38), Vector2i(0, 1)],
		[Vector2i(41, 38), Vector2i(0, 1)],
		[Vector2i(40, 37), Vector2i(-1, 0)],
	]
	for box: Array in boxes:
		var cell: Vector2i = box[0]
		var front: Vector2i = box[1]
		for each in [cell, cell + front]:
			grid.apply(BuildEdit.paint_floor(each, BuildGrid.FLOOR_TILE, 1))
		var facing := 0
		while TerminalLayout.front_of(facing) != front:
			facing += 1
		var result := grid.apply(BuildEdit.place_object(&"exit_door", cell, facing))
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	var plan := _plan_on(grid)
	var spots := _column(plan._door_sources(&"entrance_door"), 40)
	print("column 40 entrance spots %s" % [spots])
	assert_array(spots).contains_exactly([Vector2i(40, 35), Vector2i(40, 34)])
	# A column beside it still keeps its two nearest the road.
	assert_array(_column(plan._door_sources(&"entrance_door"), 20)).has_size(2)
