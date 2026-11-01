class_name TestRepairPlanFallbackWalls
extends GdUnitTestSuite
## A capped RepairPlan's fallback price covers the walls that close in the
## floor (RepairEnclosure). Nine one-cell-high strips of floor, nothing
## walled, need far more walls than the outline of the area they span, so a
## price with only the outline's walls would fall short.

const SITE := preload("res://build/terminal_site.tres")


func after_test() -> void:
	RepairPlan.max_candidates = RepairPlan.MAX_CANDIDATES
	RepairPlan.max_tries = RepairPlan.MAX_TRIES
	RepairPlan.max_attempts = RepairPlan.MAX_ATTEMPTS


func test_the_fallback_covers_the_walls_the_floor_needs() -> void:
	var grid := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	var floor: Array[Vector2i] = []
	for y in range(2, 19, 2):
		for x in range(10, 31):
			floor.append(Vector2i(x, y))
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	RepairPlan.max_tries = 1
	RepairPlan.max_attempts = 1
	var plan := RepairPlan.make(grid, SITE)
	var walls := RepairEnclosure.walls_for(grid, floor).size()
	var objects := 0
	for def_id in [&"entrance_door", &"checkin_desk", &"security_scanner", &"exit_door"]:
		objects += PriceTable.price_of_object(def_id)
	var needed := objects + walls * PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)
	print(
		(
			"capped plan ok %s, fallback %d; walls to close the floor %d, objects and walls %d"
			% [plan.ok, plan.fallback_price, walls, needed]
		)
	)
	assert_bool(plan.ok).is_false()
	assert_int(walls).is_equal(9 * 44)
	assert_int(plan.fallback_price).is_greater_equal(needed)
