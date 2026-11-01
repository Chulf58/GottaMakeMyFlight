class_name TestRoomTemplatesGuard
extends GdUnitTestSuite
## A template paste on a site grid (SiteGrid) whose guard refuses one of the
## paste's later cells (decision plane-stand-design-airside-moves-110-m-north-
## stand-snaps-to, point 4). The paste is all or nothing: the check runs on a
## copy that carries the same guard, so the refusal comes from the copy and the
## live grid, the wallet and the undo history are never touched. Before, the
## copy was a plain BuildGrid without the guard: it accepted the paste, the
## live grid then laid the earlier floor, charged for it and kept an undo step
## before refusing the guarded cell.
##
## A 20x20 site with floor on columns 2 to 9 and rows 2 to 8. The cafe saved
## there covers columns 3 to 7 and rows 3 to 6; it is pasted on bare ground
## centred on (14, 14), so the paste lays its own floor first. The stand-in
## guard refuses building on the cell of the paste's last floor edit.

const CAFE := Rect2i(3, 3, 5, 4)
const BARE_CENTRE := Vector2i(14, 14)

var _mode: BuildMode
var _finances: Finances
var _paste: TemplatePaste
var _guarded := {}


func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	var site := SiteDefinition.new()
	site.grid_size = Vector2i(20, 20)
	site.obstacles = [] as Array[Vector2i]
	_mode = BuildMode.new()
	_mode.site = site
	_mode.finances = _finances
	add_child(_mode)
	_mode.set_process(false)
	_paste = _mode.templates
	var edits: Array[BuildEdit] = []
	for y in range(2, 9):
		for x in range(2, 10):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)
	var room := _commit(BuildEdit.place_room(CAFE, &"cafe")).room_id
	_commit(BuildEdit.place_object(&"cafe_counter", Vector2i(4, 3), 0))
	_commit(BuildEdit.place_object(&"cafe_table", Vector2i(4, 5), 0))
	_mode.clear_undo()
	assert_object(_paste.save_room(room)).is_not_null()
	_paste.arm(0)
	_guarded.clear()
	(_mode.grid as SiteGrid).guard = _guard


func after_test() -> void:
	_mode.free()
	_finances.free()


func _commit(edit: BuildEdit) -> BuildResult:
	var plan: Array[BuildEdit] = [edit]
	var result := BuildTransaction.commit_plan(_mode.grid, plan, _mode.wallet())
	var why := "setup edit refused: %s" % result.reason_text()
	assert_bool(result.ok).override_failure_message(why).is_true()
	return result


## Refuses an edit that builds on a guarded cell, as ApronStand.edit_problem().
func _guard(_on_grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	if edit.kind == BuildEdit.Kind.PAINT_FLOOR and _guarded.has(edit.cell):
		return BuildResult.refused(BuildResult.Reason.PLANE_AREA)
	return null


## The cell of the paste's last floor edit at BARE_CENTRE.
func _last_floor_cell() -> Vector2i:
	var last := BuildObjectDef.NO_CELL
	for edit in _paste.library.get_template(0).plan(BARE_CENTRE, 0, _mode.grid):
		if edit.kind == BuildEdit.Kind.PAINT_FLOOR:
			last = edit.cell
	return last


func test_a_paste_whose_last_floor_cell_is_guarded_is_refused_with_nothing_changed() -> void:
	var cell := _last_floor_cell()
	assert_that(cell).is_not_equal(BuildObjectDef.NO_CELL)
	_guarded[cell] = true
	var snapshot := _mode.grid.to_snapshot()
	var balance := _mode.wallet().balance
	var done := [null]
	# No error: the copy refuses the paste, the live grid is never asked.
	await assert_error(func() -> void: done[0] = _paste.paste_at(BARE_CENTRE)).is_success()
	var result: BuildResult = done[0]
	print(
		(
			"guarded paste at %s, guarded cell %s: %s (%d), balance %d -> %d, undo steps %d"
			% [
				BARE_CENTRE,
				cell,
				result.reason_text(),
				result.reason,
				balance,
				_mode.wallet().balance,
				_mode.undo_history().size()
			]
		)
	)
	assert_int(result.reason).is_equal(BuildResult.Reason.PLANE_AREA)
	assert_int(_paste.check_at(BARE_CENTRE).reason).is_equal(BuildResult.Reason.PLANE_AREA)
	assert_dict(_mode.grid.to_snapshot()).is_equal(snapshot)
	assert_int(_mode.wallet().balance).is_equal(balance)
	assert_int(_mode.undo_history().size()).is_equal(0)


## The control: with nothing guarded, the same paste goes down and is charged.
func test_the_same_paste_with_nothing_guarded_is_placed() -> void:
	var cell := _last_floor_cell()
	var balance := _mode.wallet().balance
	var result := _paste.paste_at(BARE_CENTRE)
	print("unguarded paste: %s, balance %d -> %d" % [result.ok, balance, _mode.wallet().balance])
	assert_bool(result.ok).is_true()
	assert_int(_mode.grid.floor_at(cell)).is_equal(BuildGrid.FLOOR_TILE)
	assert_int(_mode.wallet().balance).is_less(balance)
	assert_int(_mode.undo_history().size()).is_equal(1)
