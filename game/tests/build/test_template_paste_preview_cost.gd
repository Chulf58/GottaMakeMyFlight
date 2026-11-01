class_name TestTemplatePastePreviewCost
extends GdUnitTestSuite
## The time a template paste preview takes on the 86x150 airport site when the
## pointer moves to a new cell (TemplatePaste.plan_at(), which tries the paste
## on a trial copy of the grid). Each new cell is checked again while the
## pointer moves, so it must fit in a frame. Before BuildGrid.clone() each
## check copied the grid through a snapshot and took about 0.7 s. The target is
## 50 ms per cell; the assert allows 120 ms so a slow test machine does not
## fail it. A control checks the preview still refuses a paste over a wall.

const SITE := preload("res://build/terminal_site.tres")
const TARGET_MS := 50
const ALLOWED_MS := 120
## A cafe saved off a floored block east of the starter shell.
const BLOCK := Rect2i(60, 20, 8, 7)
const CAFE := Rect2i(61, 21, 5, 4)
## Bare ground the preview moves over, one cell at a time.
const PATH_START := Vector2i(62, 50)
const STEPS := 6

var _mode: BuildMode
var _finances: Finances
var _paste: TemplatePaste


func before() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.site = SITE
	_mode.finances = _finances
	add_child(_mode)
	_mode.set_process(false)
	_paste = _mode.templates
	var edits: Array[BuildEdit] = []
	for y in range(BLOCK.position.y, BLOCK.end.y):
		for x in range(BLOCK.position.x, BLOCK.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)
	var room := _mode.grid.apply(BuildEdit.place_room(CAFE, &"cafe")).room_id
	_place(&"cafe_counter", Vector2i(62, 21))
	_place(&"cafe_table", Vector2i(62, 23))
	assert_object(_paste.save_room(room)).is_not_null()
	_paste.arm(0)


func _place(def_id: StringName, anchor: Vector2i) -> void:
	var result := _mode.grid.apply(BuildEdit.place_object(def_id, anchor, 0))
	assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()


func after() -> void:
	_mode.free()
	_finances.free()


func test_each_new_cell_of_the_preview_is_checked_within_the_budget() -> void:
	var times: Array[float] = []
	var accepted := 0
	for step in STEPS:
		var started := Time.get_ticks_usec()
		var planned := _paste.plan_at(PATH_START + Vector2i(step, 0))
		times.append((Time.get_ticks_usec() - started) / 1000.0)
		if (planned["result"] as BuildResult).ok:
			accepted += 1
	var slowest: float = times.max()
	print(
		(
			"paste preview over %d cells: %s ms, slowest %.1f (target %d, allowed %d), %d accepted"
			% [STEPS, times, slowest, TARGET_MS, ALLOWED_MS, accepted]
		)
	)
	assert_int(accepted).is_equal(STEPS)
	assert_float(slowest).is_less(ALLOWED_MS)


func test_the_preview_still_refuses_a_paste_on_the_saved_room() -> void:
	var result := _paste.check_at(CAFE.get_center())
	print("paste over the saved cafe: %s (%d)" % [result.reason_text(), result.reason])
	assert_bool(result.ok).is_false()
