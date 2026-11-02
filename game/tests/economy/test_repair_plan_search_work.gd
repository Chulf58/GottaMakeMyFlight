class_name TestRepairPlanSearchWork
extends GdUnitTestSuite
## The work RepairPlan.make() does on the 86x150 site for the starter shell a
## new game starts with, and for the same grid after a load. Counted, not
## timed, so a slow machine cannot fail it; the times are printed.
##
## Each search (RepairPlan._search(), one per leg tried) prices a step only
## to a cell not settled yet: a settled cell has its lowest price, and every
## settled cell but a source was reached from a settled neighbour, so at most
## 3 steps per settled cell, plus one per source, are priced (4 per cell
## before). The plan is made on the crop (_site_area()), so no search settles
## more cells than the crop has; a whole-grid retry would settle the whole site.

const SITE := preload("res://build/terminal_site.tres")

## Per scenario: {"plan", "ms", "area"}.
var _runs := {}


func before() -> void:
	var fresh := SiteGrid.new(SITE)
	assert_bool(StarterShell.place(fresh)).is_true()
	var loaded := SiteGrid.new(SITE)
	assert_bool(loaded.from_snapshot(fresh.to_snapshot())).is_true()
	for scenario: String in ["new game", "load"]:
		var grid := fresh if scenario == "new game" else loaded
		var area := RepairPlan._site_area(grid, grid.to_snapshot(), SITE, {})
		var started := Time.get_ticks_usec()
		var plan := RepairPlan.make(grid, SITE)
		var make_ms := (Time.get_ticks_usec() - started) / 1000.0
		started = Time.get_ticks_usec()
		var least := RepairPlan.least_balance(grid, plan.edits)
		var least_ms := (Time.get_ticks_usec() - started) / 1000.0
		print(
			(
				"%s: make %.1f ms, least_balance %.1f ms (%d), ok %s, %d edits, crop %s, work %s"
				% [scenario, make_ms, least_ms, least, plan.ok, plan.edits.size(), area, plan.work]
			)
		)
		_runs[scenario] = {"plan": plan, "area": area}


func _check(scenario: String) -> void:
	var plan: RepairPlan = _runs[scenario]["plan"]
	var area: Rect2i = _runs[scenario]["area"]
	var work := plan.work
	assert_bool(plan.ok).is_true()
	assert_int(work["searches"]).is_greater(0)
	assert_int(work["settled"]).is_greater(0)
	assert_int(work["priced"]).is_less_equal(3 * work["settled"] + work["seeded"])
	assert_int(work["priced"]).is_less(4 * work["settled"])
	assert_int(work["settled"]).is_less_equal(work["searches"] * area.get_area())


func test_a_new_game_plan_prices_at_most_three_steps_per_settled_cell() -> void:
	_check("new game")


func test_a_loaded_game_plan_prices_at_most_three_steps_per_settled_cell() -> void:
	_check("load")
