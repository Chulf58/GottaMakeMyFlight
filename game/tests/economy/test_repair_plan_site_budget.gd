class_name TestRepairPlanSiteBudget
extends GdUnitTestSuite
## The time RescueGrant.prepare() spends on the 86x150 airport site: the repair
## plan and its price (RepairPlan.make() and least_balance()), for the empty
## plot and for the starter shell a new game starts with. prepare() runs before
## a new game's first frame and after every load, on the main thread, so it must
## stay well under a frame budget. The plan is made on the part of the site a
## repair can use, not the whole grid. The target is 300 ms each; the asserts
## allow 600 ms so a slow test machine does not fail them. Each plan is also
## built on a fresh grid to show it still repairs.

const SITE := preload("res://build/terminal_site.tres")
## What prepare() aims for, and what the asserts allow.
const TARGET_MS := 300
const ALLOWED_MS := 600

## Per scenario: {"ms", "plan", "least"}.
var _runs := {}


func before() -> void:
	for scenario in ["empty", "shell"]:
		var grid := _grid(scenario)
		var started := Time.get_ticks_usec()
		var plan := RepairPlan.make(grid, SITE)
		var least := RepairPlan.least_balance(grid, plan.edits) if plan.ok else -1
		var ms := (Time.get_ticks_usec() - started) / 1000
		_runs[scenario] = {"ms": ms, "plan": plan, "least": least}


## The site grid a new game has, empty or with the starter shell.
func _grid(scenario: String) -> SiteGrid:
	var grid := SiteGrid.new(SITE)
	if scenario == "shell":
		assert_bool(StarterShell.place(grid)).is_true()
	return grid


func _report(scenario: String) -> Dictionary:
	var run: Dictionary = _runs[scenario]
	var plan: RepairPlan = run["plan"]
	print(
		(
			"%s site: plan and price in %d ms (target %d, allowed %d), ok %s, %d edits, least %d"
			% [scenario, run["ms"], TARGET_MS, ALLOWED_MS, plan.ok, plan.edits.size(), run["least"]]
		)
	)
	return run


## Builds the plan on a fresh grid of `scenario`, each edit asserted, and
## whether a new passenger then gets through.
func _repairs(scenario: String, plan: RepairPlan) -> bool:
	var grid := _grid(scenario)
	for edit in plan.edits:
		var result := grid.apply(edit)
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	var layout := TerminalLayout.new()
	layout.site = SITE
	layout.rebuild(grid)
	return RepairPlan.has_working_path(grid, layout)


func test_the_empty_plot_is_planned_and_priced_within_the_budget() -> void:
	var run := _report("empty")
	assert_bool(run["plan"].ok).is_true()
	assert_int(run["least"]).is_between(1, PriceTable.STARTING_BUDGET)
	assert_int(run["ms"]).is_less(ALLOWED_MS)


func test_the_starter_shell_is_planned_and_priced_within_the_budget() -> void:
	var run := _report("shell")
	assert_bool(run["plan"].ok).is_true()
	assert_int(run["least"]).is_between(1, PriceTable.STARTING_BUDGET)
	assert_int(run["ms"]).is_less(ALLOWED_MS)


func test_the_empty_plot_plan_still_repairs() -> void:
	var plan: RepairPlan = _runs["empty"]["plan"]
	assert_bool(plan.ok).is_true()
	assert_bool(_repairs("empty", plan)).is_true()


func test_the_starter_shell_plan_still_repairs() -> void:
	var plan: RepairPlan = _runs["shell"]["plan"]
	assert_bool(plan.ok).is_true()
	assert_bool(_repairs("shell", plan)).is_true()
