class_name TestRepairPlanLand
extends GdUnitTestSuite
## RepairPlan on a site grid (SiteGrid) with land plots keeps its repair on
## the land the player owns: no floor, piece or door on a cell of a plot not
## owned, because the live grid would refuse each one (LandPlots). A 30x12 grid
## cut into 3 columns of 10 cells by 2 rows of 6, of which only the east column
## (x 20 to 29) is owned, holds a walled hall two cells wide on the west edge of that land (x 20 and
## 21, y 2 to 9) with an entrance and an exit and nothing else, so the repair
## must lay floor to fit a desk and a scanner. The same grid with no land
## plots plans its repair further west, which shows the land changed the plan.

const OWNED_FROM_X := 20
const HALL := Rect2i(20, 2, 2, 8)

var _site: SiteDefinition


func before() -> void:
	_site = SiteDefinition.new()
	_site.grid_size = Vector2i(30, 12)
	_site.grid_origin = Vector3.ZERO
	_site.plot_counts = Vector2i(3, 2)
	_site.obstacles = [] as Array[Vector2i]


func _grid(with_land: bool) -> SiteGrid:
	var grid := SiteGrid.new(_site)
	for y in range(HALL.position.y, HALL.end.y):
		for x in range(HALL.position.x, HALL.end.x):
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	EnclosureKit.close_floor(grid)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(20, HALL.end.y - 1), 2)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(21, HALL.position.y), 0)
	if with_land:
		var land := LandPlots.for_site(_site)
		(
			assert_bool(
				land.from_snapshot({"plot_counts": [3, 2], "owned": [[2, 0], [2, 1]], "bought": 0})
			)
			. is_true()
		)
		grid.land = land
	return grid


## The westmost cell an edit builds on: its cell, and for a wall the cell on
## the far side of its edge when that is further east (a wall needs one owned
## side).
static func _westmost(edits: Array[BuildEdit]) -> int:
	var west := 1 << 20
	for edit in edits:
		var x := edit.cell.x
		if edit.kind == BuildEdit.Kind.PLACE_WALL:
			x = maxi(x, edit.cell.x + BuildGrid.SIDE_STEP[edit.side].x)
		elif edit.kind == BuildEdit.Kind.PLACE_OBJECT:
			for cell in BuildCatalog.get_def(edit.def_id).footprint(edit.cell, edit.facing):
				x = mini(x, cell.x)
		west = mini(west, x)
	return west


func test_the_repair_stays_on_owned_land() -> void:
	var plan := RepairPlan.make(_grid(true))
	print(
		(
			"land repair: ok %s, %d edits, westmost x %d"
			% [plan.ok, plan.edits.size(), _westmost(plan.edits)]
		)
	)
	assert_bool(plan.ok).is_true()
	assert_int(plan.edits.size()).is_greater(0)
	assert_int(_westmost(plan.edits)).is_greater_equal(OWNED_FROM_X)
	# Every edit of the plan builds on the live grid, land and all, in order.
	var live := _grid(true)
	for edit in plan.edits:
		var result := live.apply(edit)
		(
			assert_bool(result.ok)
			. override_failure_message("%s %s: %d" % [edit.kind, edit.cell, result.reason])
			. is_true()
		)


func test_without_land_plots_the_repair_goes_further_west() -> void:
	var plan := RepairPlan.make(_grid(false))
	print(
		(
			"plain repair: ok %s, %d edits, westmost x %d"
			% [plan.ok, plan.edits.size(), _westmost(plan.edits)]
		)
	)
	assert_bool(plan.ok).is_true()
	assert_int(_westmost(plan.edits)).is_less(OWNED_FROM_X)
