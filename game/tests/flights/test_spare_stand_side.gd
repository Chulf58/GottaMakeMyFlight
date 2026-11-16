class_name TestSpareStandSide
extends GdUnitTestSuite
## SpareStand tries west and east stands as well as north ones (slice S5 of
## design airside-all-around-technical-design-one-route-source-per-con). One
## plot of the first site is owned, with nothing built on it. A floor row just
## north of the plot crosses every north stand's way to the lane, so only a side
## stand fits; without the row the first fit is a north one.

const SITE := preload("res://build/terminal_site.tres")
## The owned plot (column, row): grid cells x 107 to 128, rows 100 to 124.
const PLOT := [5, 4]
const PLOT_CELLS := Rect2i(107, 100, 22, 25)
## Five rows north of the plot: a north stand's swing square starts 2.2 m out
## from its wall, so a row nearer the plot would leave its first rows clear.
const FLOOR_ROW := 95
const FLOOR_FROM := 80
const FLOOR_TO := 160


func _grid(with_floor: bool) -> SiteGrid:
	var grid := SiteGrid.new(SITE)
	if with_floor:
		var edits: Array[BuildEdit] = []
		for x in range(FLOOR_FROM, FLOOR_TO + 1):
			edits.append(BuildEdit.paint_floor(Vector2i(x, FLOOR_ROW), BuildGrid.FLOOR_TILE, 1))
		for result in grid.apply_batch(edits):
			assert_bool(result.ok).is_true()
	var land := LandPlots.for_site(SITE)
	var owned := {"plot_counts": [12, 6], "owned": [PLOT], "bought": 0}
	assert_bool(land.from_snapshot(owned)).is_true()
	grid.land = land
	return grid


func test_only_a_side_stand_fits_and_is_found() -> void:
	var grid := _grid(true)
	var spare := SpareStand.find(grid, [] as Array[Dictionary], PlaneClasses.SMALL)
	print("spare with the floor row: %s" % [spare])
	assert_bool(StandPlacement.is_stand(spare)).is_true()
	assert_str(StandPlacement.side_of(spare)).is_not_equal(StandPlacement.NORTH)
	assert_int(StandEnvelope.blocked_part(grid, SITE, spare, PlaneClasses.SMALL)).is_equal(
		StandEnvelope.Part.CLEAR
	)
	# Every north stand from the plot is blocked by the row.
	var owned := 0
	var north_clear := 0
	for y in range(PLOT_CELLS.position.y, PLOT_CELLS.end.y):
		for x in range(PLOT_CELLS.position.x, PLOT_CELLS.end.x):
			var cell := Vector2i(x, y)
			if not grid.land.owns_cell(cell):
				continue
			owned += 1
			var north := StandPlacement.for_cell(grid, cell)
			var part := StandEnvelope.blocked_part(grid, SITE, north, PlaneClasses.SMALL)
			if part == StandEnvelope.Part.CLEAR:
				north_clear += 1
	print("owned cells %d, north stands clear %d" % [owned, north_clear])
	assert_int(owned).is_equal(PLOT_CELLS.get_area())
	assert_int(north_clear).is_equal(0)


func test_without_the_floor_row_the_first_fit_is_north() -> void:
	var grid := _grid(false)
	var spare := SpareStand.find(grid, [] as Array[Dictionary], PlaneClasses.SMALL)
	print("spare without the row: %s" % [spare])
	assert_bool(StandPlacement.is_stand(spare)).is_true()
	assert_str(StandPlacement.side_of(spare)).is_equal(StandPlacement.NORTH)
