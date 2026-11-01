class_name TestRepairPlanCrop
extends GdUnitTestSuite
## RepairPlan.make() on a site plans on a cropped copy of the grid: what is
## built and the plane door's cell, RepairPlan.SITE_MARGIN cells wider each
## way and down to the road edge. A repair that needs ground outside that crop
## is not found there. The plan then searches the whole grid once, so such a
## repair is still found (or, when the whole search hits its caps, priced by
## the fallback on the whole grid), and the rescue grant never pays nothing for
## a grid that can be repaired.
##
## A 40x30 plot with nothing built: the crop is the starter shell's place,
## columns 6 to 26. Kept site art stands on the road edge from column 0 to
## 30, so no walk in from the road starts inside the crop. The only way in is
## from the road edge east of column 30, round the art: outside the crop.

const SIZE := Vector2i(40, 30)
const ART_END_X := 30

var _site: SiteDefinition
var _plan: RepairPlan
var _least := -1


func before() -> void:
	_site = SiteDefinition.new()
	_site.grid_size = SIZE
	_site.starter_offset = Vector2i.ZERO
	var art: Array[Vector2i] = []
	for x in range(0, ART_END_X + 1):
		art.append(Vector2i(x, SIZE.y - 1))
	_site.obstacles = art
	var grid := _fresh()
	_plan = RepairPlan.make(grid, _site)
	if _plan.ok:
		_least = RepairPlan.least_balance(grid, _plan.edits)


func after_test() -> void:
	RepairPlan.max_attempts = RepairPlan.MAX_ATTEMPTS


func _fresh() -> SiteGrid:
	return SiteGrid.new(_site)


func test_a_repair_whose_walk_in_lies_outside_the_crop_is_found() -> void:
	var walls := _plan.edits.filter(
		func(e: BuildEdit) -> bool: return e.kind == BuildEdit.Kind.PLACE_WALL
	)
	print(
		(
			(
				"plan with the road edge blocked in the crop: ok %s, %d edits (%d walls), "
				+ "least balance %d, fallback %d"
			)
			% [_plan.ok, _plan.edits.size(), walls.size(), _least, _plan.fallback_price]
		)
	)
	assert_bool(_plan.ok).is_true()
	assert_int(_least).is_greater(0)
	assert_int(_plan.undo_failures).is_equal(0)


func test_the_found_repair_gives_a_working_path_with_a_walk_in_from_east_of_the_art() -> void:
	var grid := _fresh()
	for edit in _plan.edits:
		var result := grid.apply(edit)
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	var layout := TerminalLayout.new()
	layout.site = _site
	layout.rebuild(grid)
	var walk_in: Array[Vector2i] = []
	if not layout.passenger_entrances.is_empty():
		walk_in.assign(layout.outside_routes.get(layout.passenger_entrances[0], []))
	# The walk runs from the door out to the road edge cell, its last.
	var road_cell: Vector2i = walk_in.back() if not walk_in.is_empty() else Vector2i(-1, -1)
	print(
		(
			"built: entrances %s, walk in from the road starts at %s (%d cells)"
			% [layout.passenger_entrances, road_cell, walk_in.size()]
		)
	)
	assert_bool(RepairPlan.has_working_path(grid, layout)).is_true()
	assert_int(road_cell.x).is_greater(ART_END_X)


## With the caps run out at once, the crop's search gives no answer and the
## whole grid's is priced: the fallback floors every bare cell of the 40x30
## plot, not only the crop's.
func test_with_the_caps_run_out_the_fallback_is_priced_on_the_whole_grid() -> void:
	RepairPlan.max_attempts = 0
	var plan := RepairPlan.make(_fresh(), _site)
	var objects := 0
	for def_id in [&"entrance_door", &"checkin_desk", &"security_scanner", &"exit_door"]:
		objects += PriceTable.price_of_object(def_id)
	var whole_floor := SIZE.x * SIZE.y * PriceTable.price_of_floor()
	print(
		(
			"capped plan ok %s, fallback %d; objects %d and floor for the whole plot %d"
			% [plan.ok, plan.fallback_price, objects, whole_floor]
		)
	)
	assert_bool(plan.ok).is_false()
	assert_int(plan.fallback_price).is_greater_equal(objects + whole_floor)
