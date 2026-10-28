class_name TestPlaytestViewMissing
extends GdUnitTestSuite
## Smoke playtest 8 placed a tray table straight through BuildGrid.apply(), as
## the playtest skill's scripts do, after removing another one the same way.
## The build view must follow edits that do not come through BuildMode, so the
## new tray gets its node, the removed one loses its node, and the hook's
## view_missing anomaly does not stay raised.

const MAIN := "res://main/main.tscn"
const HOOK := preload("res://debug/playtest_hook.gd")
const DIR := "user://playtest_view_missing_test"
## Free starter-terminal floor on the landside, clear of every station and
## staff spot; the second tray goes one cell off the first, as in the playtest.
const FIRST_TRAY := Vector2i(20, 20)
const SECOND_TRAY := Vector2i(20, 19)

var _main: Node
var _hook: Node
var _mode: BuildMode


func before() -> void:
	_main = load(MAIN).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(7)
	_mode = _main.get_node("BuildMode")
	add_child(_main)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	_hook = HOOK.new()
	_hook.configure(true, DIR)
	add_child(_hook)
	_hook.attach(_main)
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()


func after() -> void:
	_hook.detach()
	_hook.free()
	_main.free()
	for name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute("%s/%s" % [DIR, name])
	DirAccess.remove_absolute(DIR)


func _view() -> BuildView:
	return _mode.get_node("BuildView") as BuildView


func _open_view_missing() -> Array[String]:
	var subjects: Array[String] = []
	for record in _hook.anomalies():
		if record["kind"] == "view_missing":
			subjects.append(record["subject"])
	return subjects


func test_a_tray_placed_through_the_grid_gets_its_node_and_no_view_missing() -> void:
	var grid := _mode.grid
	var nodes_before := _view().object_node_count()
	var first := grid.apply(BuildEdit.place_object(SecurityLanes.TRAY_TABLE, FIRST_TRAY, 0))
	assert_bool(first.ok).is_true()
	await await_idle_frame()
	await await_idle_frame()
	assert_object(_view().object_node(first.object_id)).is_not_null()
	var removed := grid.apply(BuildEdit.remove_object(first.object_id))
	assert_bool(removed.ok).is_true()
	var second := grid.apply(BuildEdit.place_object(SecurityLanes.TRAY_TABLE, SECOND_TRAY, 0))
	assert_bool(second.ok).is_true()
	await await_idle_frame()
	await await_idle_frame()
	_hook.run_checks()
	var node := _view().object_node(second.object_id)
	print(
		(
			"nodes before=%d after=%d second=%d node=%s stale_first=%s view_missing=%s"
			% [
				nodes_before,
				_view().object_node_count(),
				second.object_id,
				node,
				_view().object_node(first.object_id),
				_open_view_missing()
			]
		)
	)
	assert_object(node).is_not_null()
	assert_object(_view().object_node(first.object_id)).is_null()
	assert_int(_view().object_node_count()).is_equal(nodes_before + 1)
	assert_array(_open_view_missing()).is_empty()
	if node == null:
		return
	var centre := (
		_view().global_transform
		* BuildView.object_transform(grid, [SECOND_TRAY] as Array[Vector2i], 0).origin
	)
	assert_float(node.global_position.distance_to(centre)).is_less(0.01)
