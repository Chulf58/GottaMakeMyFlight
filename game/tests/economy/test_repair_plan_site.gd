class_name TestRepairPlanSite
extends GdUnitTestSuite
## RepairPlan on the empty airport site plot (decision player-built-terminal-
## technical-design-site-plot-indoor-mask-passenger-eligibility, point 8):
## with no Toon shell closing the grid border, passengers use only floor that
## walls close in, so the plan walls in the floor it lays (RepairEnclosure)
## and its doors have walks outside to the road and the plane. The plan is
## made once in before().

const SITE := preload("res://build/terminal_site.tres")

var _plan: RepairPlan
var _usec := 0
var _least := -1


func before() -> void:
	var grid := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	var started := Time.get_ticks_usec()
	_plan = RepairPlan.make(grid, null, SITE)
	_usec = Time.get_ticks_usec() - started
	if _plan.ok:
		_least = RepairPlan.least_balance(grid, _plan.edits)


## The plan's edits applied to a fresh empty site grid, each asserted.
func _built() -> BuildGrid:
	var grid := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	for edit in _plan.edits:
		var result := grid.apply(edit)
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	return grid


func test_the_empty_site_plot_has_a_repair_the_starting_budget_pays_for() -> void:
	var walls := _plan.edits.filter(
		func(e: BuildEdit) -> bool: return e.kind == BuildEdit.Kind.PLACE_WALL
	)
	print(
		(
			"empty site plan: ok %s in %d ms, %d edits (%d walls), least balance %d, undo failures %d"
			% [
				_plan.ok,
				_usec / 1000,
				_plan.edits.size(),
				walls.size(),
				_least,
				_plan.undo_failures
			]
		)
	)
	assert_bool(_plan.ok).is_true()
	assert_int(_least).is_between(1, PriceTable.STARTING_BUDGET)
	assert_int(walls.size()).is_greater(0)
	assert_int(_plan.undo_failures).is_equal(0)


func test_the_plan_leaves_a_working_path_on_walled_in_floor() -> void:
	var grid := _built()
	var layout := TerminalLayout.new()
	layout.site = SITE
	layout.rebuild(grid)
	print(
		(
			"built: entrances %s for passengers %s, open exits %s, out of service %s"
			% [
				layout.entrances,
				layout.passenger_entrances,
				layout.open_exits(grid),
				layout.out_of_service
			]
		)
	)
	assert_bool(EnclosureKit.all_indoor(grid)).is_true()
	assert_array(layout.out_of_service).is_empty()
	assert_bool(RepairPlan.has_working_path(grid, layout)).is_true()
