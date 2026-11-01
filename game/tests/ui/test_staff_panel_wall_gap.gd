class_name TestStaffPanelWallGap
extends GdUnitTestSuite
## The banner above the bar (the staff panel's hint card) names an open gap in
## the outer wall with the sign's own words, "Wall gap", and drops the line
## once the gap is closed again (decision player-built-roof-as-built-roofview-
## one-batched-mesh-over-in: EnclosureGaps finds the open edges).

var _w: PassengerTestWorld
var _panel: StaffPanel


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(12, 12))
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_w.auto_staff = false
	# PassengerTestWorld.floored walls the floor in, so nothing is open yet.
	_panel = auto_free(StaffPanel.new())
	_panel.staff = _w.staff
	add_child(_panel)


func after_test() -> void:
	_w.free_all()
	_w = null


func _edit(edit: BuildEdit) -> void:
	var result := _w.grid.apply(edit)
	assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()


func _open_gap(cell: Vector2i, side: int) -> void:
	_edit(BuildEdit.remove_wall(cell, side))


func test_a_closed_wall_adds_no_gap_line() -> void:
	assert_str(_panel.hint_text()).not_contains("Wall gap")
	assert_str(_panel.hint_text()).not_contains("wall gaps")


func test_an_open_edge_is_named_on_the_banner() -> void:
	_open_gap(Vector2i(11, 5), BuildGrid.Side.EAST)
	assert_str(_panel.hint_text()).contains("Wall gap")
	assert_str(_panel.hint_text()).is_equal(StaffPanel.GAP_HINT)
	assert_bool(_panel.hint_card().visible).is_true()
	assert_str(_panel.hint_label().text).contains("Wall gap")


func test_the_line_goes_once_the_gap_is_closed() -> void:
	_open_gap(Vector2i(11, 5), BuildGrid.Side.EAST)
	assert_str(_panel.hint_text()).contains("Wall gap")
	_edit(BuildEdit.place_wall(Vector2i(11, 5), BuildGrid.Side.EAST))
	assert_str(_panel.hint_text()).not_contains("Wall gap")
	assert_bool(_panel.hint_card().visible).is_false()


func test_gaps_on_two_sides_are_counted() -> void:
	_open_gap(Vector2i(11, 5), BuildGrid.Side.EAST)
	_open_gap(Vector2i(5, 11), BuildGrid.Side.SOUTH)
	assert_str(_panel.hint_text()).contains("2 wall gaps")


func test_neighbouring_open_edges_are_one_gap() -> void:
	for y in [4, 5, 6]:
		_open_gap(Vector2i(11, y), BuildGrid.Side.EAST)
	assert_str(_panel.hint_text()).is_equal(StaffPanel.GAP_HINT)


func test_a_batch_of_edits_scans_for_gaps_once() -> void:
	var before_scans := _panel.gap_scans
	var edits: Array[BuildEdit] = []
	for y in [3, 4, 5, 6]:
		edits.append(BuildEdit.remove_wall(Vector2i(11, y), BuildGrid.Side.EAST))
	for result in _w.grid.apply_batch(edits):
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	assert_int(_panel.gap_scans - before_scans).is_equal(1)
	assert_str(_panel.hint_text()).is_equal(StaffPanel.GAP_HINT)
