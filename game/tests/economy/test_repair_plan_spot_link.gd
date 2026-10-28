class_name TestRepairPlanSpotLink
extends GdUnitTestSuite
## The floor RepairPlan lays from a new desk's or scanner's staff spot to the
## walk (RepairPlan._spot_link()), and the repair's price (ruling going-broke-
## a-one-off-rescue-grant-when-the-airport-is-stuck: the grant is just big
## enough). The link ends on the walk or a cell staff reach, never on a floor
## island cut off from the entrances; it never starts on the side the leg may
## not reach (ruling rescue-grant-repair-price-never-removes-the-security-
## divider); and a floor cell is charged once however many edits paint it.

const SHELL := "res://build/toon_terminal_shell.tres"
## The row of floor laid across the empty shell as an island in front of the
## doors, near where the cheapest desks' staff spots fall.
const ISLAND_ROW := 25


static func _paint(cell: Vector2i) -> BuildEdit:
	return BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, BuildMode.TERMINAL_ZONE)


## Buys `edits` one by one with `wallet` through paid build transactions, then
## says whether a new passenger has a working path. Every buy must go through.
func _buy_all(grid: BuildGrid, edits: Array[BuildEdit], wallet: Wallet) -> bool:
	for edit in edits:
		var result := BuildTransaction.commit_plan(grid, [edit] as Array[BuildEdit], wallet)
		var why := "buying %s at %s refused: %d" % [edit.kind, edit.cell, result.reason]
		assert_bool(result.ok).override_failure_message(why).is_true()
		if not result.ok:
			return false
	var layout := TerminalLayout.new()
	layout.rebuild(grid)
	return RepairPlan.has_working_path(grid, layout)


## A floor island (no way to an entrance) lies next to where the cheapest
## desks' spots fall. The link goes on to the walk, so the plan still finds a
## repair within its caps, and the money it names builds a working path.
func test_a_floor_island_by_the_spot_is_not_taken_for_the_way_in() -> void:
	var shell: ShellDefinition = load(SHELL)
	var grid := BuildGrid.new(shell.grid_size, shell.grid_origin)
	var island := 0
	for x in grid.size.x:
		var edit := _paint(Vector2i(x, ISLAND_ROW))
		if grid.validate(edit).ok and grid.apply(edit).ok:
			island += 1
	assert_int(island).is_greater(30)
	var plan := RepairPlan.make(grid, shell)
	var price := RepairPlan.least_balance(grid, plan.edits) if plan.ok else -1
	prints("island", island, "ok", plan.ok, "price", price, "fallback", plan.fallback_price)
	assert_bool(plan.ok).is_true()
	assert_int(price).is_between(1, PriceTable.STARTING_BUDGET)
	var wallet := Wallet.new(price)
	assert_bool(_buy_all(grid, plan.edits, wallet)).is_true()
	prints("left", wallet.balance)
	assert_int(wallet.balance).is_equal(0)


## A spot whose only floored neighbour is an island staff cannot reach is
## linked on to the walk, not stopped at the island. On the reference
## terminal's grid, far from the terminal: island (60, 60), spot (60, 59),
## walk cell (60, 55); the way in is the spot and the three cells after it.
func test_the_link_passes_an_island_and_ends_at_the_walk() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	for y in range(54, 62):
		assert_int(grid.floor_at(Vector2i(60, y))).is_equal(BuildGrid.FLOOR_NONE)
	assert_bool(grid.apply(_paint(Vector2i(60, 60))).ok).is_true()
	var plan := RepairPlan.make(grid)
	assert_bool(plan.ok).is_true()
	plan._refresh_sets(RepairPlan.Leg.DESK)
	var link: Array[Vector2i] = plan._spot_link(Vector2i(60, 59), {}, {Vector2i(60, 55): true})
	prints("link", link)
	assert_array(link).is_equal(
		[Vector2i(60, 59), Vector2i(60, 58), Vector2i(60, 57), Vector2i(60, 56)]
	)


## Two edits painting one bare cell cost one floor tile.
func test_a_cell_painted_twice_is_charged_once() -> void:
	var grid := BuildGrid.new()
	var cell := Vector2i(3, 3)
	var twice: Array[BuildEdit] = [_paint(cell), _paint(cell)]
	var once: Array[BuildEdit] = [_paint(cell)]
	var price_twice := RepairPlan.least_balance(grid, twice)
	var price_once := RepairPlan.least_balance(grid, once)
	prints("twice", price_twice, "once", price_once)
	assert_int(price_once).is_equal(PriceTable.FLOOR_PRICE)
	assert_int(price_twice).is_equal(PriceTable.FLOOR_PRICE)


## A plan paints each cell at most once, so its price counts each tile once.
func test_the_empty_shell_plan_paints_each_cell_once() -> void:
	var shell: ShellDefinition = load(SHELL)
	var grid := BuildGrid.new(shell.grid_size, shell.grid_origin)
	var plan := RepairPlan.make(grid, shell)
	assert_bool(plan.ok).is_true()
	var painted := {}
	var twice: Array[Vector2i] = []
	for edit in plan.edits:
		if edit.kind == BuildEdit.Kind.PAINT_FLOOR:
			if painted.has(edit.cell):
				twice.append(edit.cell)
			painted[edit.cell] = true
	prints("painted", painted.size(), "twice", twice)
	assert_int(painted.size()).is_greater(0)
	assert_array(twice).is_empty()


## A spot on a bare cell open to airside (the divider's far side for a
## landside leg) starts no link, so no floor is laid that joins the sides.
## Control: such cells exist on the reference terminal's grid.
func test_a_spot_on_the_forbidden_side_starts_no_link() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	var plan := RepairPlan.make(grid)
	plan._refresh_sets(RepairPlan.Leg.DESK)
	var seeds: Array[Vector2i] = []
	var linked: Array[Vector2i] = []
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			if grid.floor_at(cell) != BuildGrid.FLOOR_NONE or not plan._off_side(cell):
				continue
			seeds.append(cell)
			if not plan._spot_link(cell, {}, {}).is_empty():
				linked.append(cell)
	prints("forbidden-side bare cells", seeds.size(), "linked", linked.size())
	assert_int(seeds.size()).is_greater(0)
	assert_array(linked).is_empty()
