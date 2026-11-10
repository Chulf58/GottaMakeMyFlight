class_name TestBuildMenuRemoveCost
extends GdUnitTestSuite
## A refused removal shows no cost: removing an exit door re-walls the gap it
## leaves (a plan of two edits, so the cost line would read the wall's price),
## but when the removal is refused (here a gate with a flight due) the status
## line gives the reason and the cost line is empty. A removal the wallet only
## cannot pay for still shows its shortfall.

const SITE := preload("res://build/terminal_site.tres")
## A north exit placed straight on the grid, so it was never paid for and its
## removal refunds nothing: the wall it leaves is the removal's whole cost.
const EXIT_CELL := Vector2i(11, 112)

var _finances: Finances
var _mode: BuildMode
var _menu: BuildMenu
var _grid: SiteGrid


func before() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.initial_tool = BuildMode.Tool.NONE
	_mode.site = SITE
	_mode.starter_shell = true
	_mode.finances = _finances
	add_child(_mode)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	add_child(_menu)
	_grid = _mode.grid as SiteGrid
	assert_bool(_grid.apply(BuildEdit.remove_wall(EXIT_CELL, BuildGrid.Side.NORTH)).ok).is_true()
	var door := _grid.apply(BuildEdit.place_object(&"exit_door", EXIT_CELL, 0))
	assert_bool(door.ok).is_true()


func after() -> void:
	for node in [_menu, _mode, _finances]:
		node.free()


func before_test() -> void:
	_mode.set_tool(BuildMode.Tool.REMOVE)
	_mode._update_ghost(_grid.cell_to_world(EXIT_CELL))


func after_test() -> void:
	_grid.guard = Callable()
	_set_balance(PriceTable.STARTING_BUDGET)


func _set_balance(amount: int) -> void:
	assert_bool(_finances.wallet.from_snapshot({"balance": str(amount)})).is_true()


func _refuse_removals(_on_grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	if edit.kind == BuildEdit.Kind.REMOVE_OBJECT:
		return BuildResult.refused(BuildResult.Reason.GATE_IN_USE)
	return null


func test_removing_an_exit_door_shows_the_wall_it_leaves_as_its_cost() -> void:
	var edit := _mode.hover_edit()
	assert_object(edit).is_not_null()
	assert_int(edit.kind).is_equal(BuildEdit.Kind.REMOVE_OBJECT)
	assert_bool(_mode.check(edit).ok).is_true()
	var text := _menu.preview_text()
	print("allowed removal: %s" % text)
	assert_str(text).starts_with("Cost ")


func test_a_refused_removal_shows_no_cost() -> void:
	_grid.guard = _refuse_removals
	var edit := _mode.hover_edit()
	var result := _mode.check(edit)
	print("refused removal: %s, cost line '%s'" % [result.reason_text(), _menu.preview_text()])
	assert_int(result.reason).is_equal(BuildResult.Reason.GATE_IN_USE)
	assert_str(_menu.preview_text()).is_equal("")
	_menu.refresh_preview()
	assert_bool(_menu.preview_label().visible).is_false()


func test_a_removal_the_wallet_cannot_pay_still_shows_its_shortfall() -> void:
	_set_balance(0)
	var edit := _mode.hover_edit()
	assert_int(_mode.check(edit).reason).is_equal(BuildResult.Reason.CANT_AFFORD)
	assert_str(_menu.preview_text()).starts_with("Cost ")
	assert_str(_menu.preview_text()).contains("Short by")
