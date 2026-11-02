class_name TestBuildMenuRotateHint
extends GdUnitTestSuite
## With no Rotate card, the build status line ends with "R rotate" while a piece
## or a pasted template that can turn is under the cursor (board 6bd94761,
## decision no-rotate-card-in-build-trays, "Hint while placing"): after whatever
## the line already shows, and nothing for a tool that places no piece.

const HINT := "R rotate"

var _port: SubViewport
var _finances: Finances
var _mode: BuildMode
var _menu: BuildMenu


func before() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_finances = Finances.new()
	_port.add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_mode.finances = _finances
	_port.add_child(_mode)
	_mode.set_process(false)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)
	var edits: Array[BuildEdit] = []
	for y in range(2, 12):
		for x in range(2, 14):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)
	var room := _mode.grid.apply(BuildEdit.place_room(Rect2i(3, 3, 5, 4), &"cafe")).room_id
	assert_int(room).is_greater(0)
	_mode.grid.apply(BuildEdit.place_object(&"cafe_counter", Vector2i(4, 3), 0))


func before_test() -> void:
	_mode.templates.disarm()
	_mode.set_tool(BuildMode.Tool.NONE)
	_menu.status_label().text = ""


func after() -> void:
	_port.free()


func test_a_piece_that_turns_ends_the_status_line_with_the_hint() -> void:
	_mode.set_tool(BuildMode.Tool.SEATS)
	assert_str(_menu.status_label().text).is_equal(_mode.status_text() + "  " + HINT)
	# After whatever the line already shows (a refusal, a size).
	_mode.status_changed.emit("Too close to a wall")
	assert_str(_menu.status_label().text).is_equal("Too close to a wall  " + HINT)


func test_a_tool_that_places_no_piece_shows_no_hint() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	assert_str(_menu.status_label().text).is_equal("")
	_mode.status_changed.emit("5 x 3")
	assert_str(_menu.status_label().text).is_equal("5 x 3")


func test_no_tool_armed_shows_no_hint() -> void:
	_mode.set_tool(BuildMode.Tool.SEATS)
	_mode.set_tool(BuildMode.Tool.NONE)
	assert_str(_menu.status_label().text).is_equal("")


func test_an_armed_template_paste_ends_its_line_with_the_hint() -> void:
	_mode.templates.arm_capture()
	_mode.templates.click(Vector2i(4, 4))
	_mode.templates.arm(0)
	var line := TemplatePaste.PLACE_HINT % _mode.templates.library.get_template(0).name
	assert_str(_menu.status_label().text).is_equal(line + "  " + HINT)
	_mode.templates.disarm()
	assert_str(_menu.status_label().text).is_equal("")
