class_name TestBuildUnlocksWiring
extends GdUnitTestSuite
## Where the build unlocks are asked (decision build-unlocks-need-stars-and-
## passengers-served-hunger-cafe-a): BuildMode.set_tool(), the tool a mode
## starts on, and the rooms and pieces of a plan. A mode that requires the gate
## and has none refuses every gated tool and starts on no tool; a node with no
## clock says so unless it is manual.

var _rating: AirportRating
var _pax: PassengerSim
var _unlocks: BuildUnlocks


func before_test() -> void:
	_rating = auto_free(AirportRating.new())
	_pax = auto_free(PassengerSim.new())
	_unlocks = auto_free(BuildUnlocks.new())
	_unlocks.rating = _rating
	_unlocks.passengers = _pax
	_unlocks.manual = true
	add_child(_unlocks)


func test_a_world_without_a_gate_builds_with_every_tool_only_when_it_does_not_require_one() -> void:
	for tool: BuildMode.Tool in BuildMode.Tool.values():
		assert_str(BuildUnlocks.lock_text(null, false, tool)).is_empty()
	assert_str(BuildUnlocks.lock_text(null, true, BuildMode.Tool.CAFE_ROOM)).is_equal(
		BuildUnlocks.NOT_WIRED_TEXT
	)
	assert_str(BuildUnlocks.lock_text(null, true, BuildMode.Tool.FLOOR)).is_equal(
		BuildUnlocks.NOT_WIRED_TEXT
	)
	assert_str(BuildUnlocks.lock_text(null, true, BuildMode.Tool.NONE)).is_empty()
	assert_str(BuildUnlocks.lock_text(null, true, BuildMode.Tool.REMOVE)).is_empty()


func test_build_mode_refuses_a_locked_tool_and_takes_it_once_unlocked() -> void:
	var mode: BuildMode = auto_free(BuildMode.new())
	mode.grid_size = Vector2i(20, 20)
	mode.unlocks = _unlocks
	mode.require_unlocks = true
	add_child(mode)
	mode.set_tool(BuildMode.Tool.WALL)
	assert_int(mode.tool).is_equal(BuildMode.Tool.WALL)
	mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	assert_int(mode.tool).is_equal(BuildMode.Tool.WALL)
	assert_str(mode.status_text()).contains("Unlocks at 2 stars and 50 passengers")
	_unlocks.from_snapshot({"tier": 2, "made": 50})
	mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	assert_int(mode.tool).is_equal(BuildMode.Tool.CAFE_ROOM)
	mode.set_tool(BuildMode.Tool.TREE)
	assert_int(mode.tool).is_equal(BuildMode.Tool.CAFE_ROOM)


func test_a_missing_clock_is_reported_unless_the_node_is_manual() -> void:
	var unlocks: BuildUnlocks = auto_free(BuildUnlocks.new())
	unlocks.rating = _rating
	unlocks.passengers = _pax
	await (
		assert_error(func() -> void: add_child(unlocks))
		. is_push_error("BuildUnlocks: no clock is set; nothing unlocks until check() is called")
	)
	var manual: BuildUnlocks = auto_free(BuildUnlocks.new())
	manual.rating = _rating
	manual.passengers = _pax
	manual.manual = true
	await assert_error(func() -> void: add_child(manual)).is_success()


func test_the_edits_of_a_plan_are_locked_by_their_room_and_their_pieces() -> void:
	var cafe_room: Array[BuildEdit] = [BuildEdit.place_room(Rect2i(1, 1, 4, 4), &"cafe")]
	var cafe_piece: Array[BuildEdit] = [BuildEdit.place_object(&"cafe_counter", Vector2i(2, 2), 0)]
	var start_piece: Array[BuildEdit] = [BuildEdit.place_object(&"checkin_desk", Vector2i(2, 2), 0)]
	var floor_only: Array[BuildEdit] = [
		BuildEdit.paint_floor(Vector2i(2, 2), BuildGrid.FLOOR_TILE, 1)
	]
	for locked: Array[BuildEdit] in [cafe_room, cafe_piece]:
		assert_str(BuildUnlocks.edits_lock_text(_unlocks, true, locked)).starts_with(
			"Unlocks at 2 stars and 50 passengers"
		)
	assert_str(BuildUnlocks.edits_lock_text(_unlocks, true, start_piece)).is_empty()
	assert_str(BuildUnlocks.edits_lock_text(_unlocks, true, floor_only)).is_empty()
	assert_str(BuildUnlocks.edits_lock_text(null, true, cafe_room)).is_equal(
		BuildUnlocks.NOT_WIRED_TEXT
	)
	assert_str(BuildUnlocks.edits_lock_text(null, false, cafe_room)).is_empty()
	_unlocks.from_snapshot({"tier": 2, "made": 50})
	assert_str(BuildUnlocks.edits_lock_text(_unlocks, true, cafe_room)).is_empty()
	assert_str(BuildUnlocks.edits_lock_text(_unlocks, true, cafe_piece)).is_empty()


## The scene-less default tool must not outlive a missing gate: with unlocks
## required and none wired, a mode that keeps the default Floor tool starts on
## no tool, and a click builds nothing (the control, a mode that does not
## require unlocks, paints with the same click).
func test_a_required_but_missing_gate_leaves_no_tool_and_builds_nothing() -> void:
	var mode: BuildMode = auto_free(BuildMode.new())
	mode.grid_size = Vector2i(20, 20)
	mode.require_unlocks = true
	await (
		assert_error(func() -> void: add_child(mode))
		. is_push_error("BuildMode: no BuildUnlocks is wired; every gated tool is refused")
	)
	var cell := Vector2i(5, 5)
	var point := mode.grid.cell_to_world(cell)
	assert_int(mode.tool).is_equal(BuildMode.Tool.NONE)
	assert_object(mode.apply_at(point)).is_null()
	assert_int(mode.grid.floor_at(cell)).is_equal(BuildGrid.FLOOR_NONE)
	var open: BuildMode = auto_free(BuildMode.new())
	open.grid_size = Vector2i(20, 20)
	add_child(open)
	assert_int(open.tool).is_equal(BuildMode.Tool.FLOOR)
	assert_bool(open.apply_at(open.grid.cell_to_world(cell)).ok).is_true()
	assert_int(open.grid.floor_at(cell)).is_equal(BuildGrid.FLOOR_TILE)


func test_a_required_but_missing_gate_refuses_gated_tools() -> void:
	var mode: BuildMode = auto_free(BuildMode.new())
	mode.grid_size = Vector2i(20, 20)
	mode.require_unlocks = true
	mode.initial_tool = BuildMode.Tool.NONE
	await (
		assert_error(func() -> void: add_child(mode))
		. is_push_error("BuildMode: no BuildUnlocks is wired; every gated tool is refused")
	)
	mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	assert_int(mode.tool).is_equal(BuildMode.Tool.NONE)
	assert_str(mode.status_text()).is_equal(BuildUnlocks.NOT_WIRED_TEXT)
	mode.set_tool(BuildMode.Tool.REMOVE)
	assert_int(mode.tool).is_equal(BuildMode.Tool.REMOVE)


func test_moving_something_built_picks_a_locked_tool_but_a_fresh_pick_stays_refused() -> void:
	var mode: BuildMode = auto_free(BuildMode.new())
	mode.grid_size = Vector2i(20, 20)
	mode.unlocks = _unlocks
	mode.require_unlocks = true
	add_child(mode)
	mode.set_tool(BuildMode.Tool.WALL)
	mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	assert_int(mode.tool).is_equal(BuildMode.Tool.WALL)
	mode.set_tool_for_move(BuildMode.Tool.CAFE_ROOM)
	assert_int(mode.tool).is_equal(BuildMode.Tool.CAFE_ROOM)
	mode.set_tool(BuildMode.Tool.NONE)
	mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	assert_int(mode.tool).is_equal(BuildMode.Tool.NONE)
