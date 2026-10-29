class_name TestBuildModeDragReleaseOverUi
extends GdUnitTestSuite
## A Floor, Remove or Wall drag released over a HUD Control still applies: the
## Control takes the release before BuildMode's _unhandled_input would see it,
## so BuildMode catches the release of a drag in progress ahead of the HUD (the
## drag keeps its last size while the pointer is over the HUD, DRAG_OVER_UI).

## A top-down orthographic camera over a 40x40 grid, 18 px to the metre: the top
## half of a 1280x720 port is a Control strip, the lower half is world.
const PORT_SIZE := Vector2i(1280, 720)
const OVER_HUD := Vector2(640, 100)

var _port: SubViewport
var _camera: Camera3D
var _mode: BuildMode


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = PORT_SIZE
	add_child(_port)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 40.0
	_port.add_child(_camera)
	_camera.position = Vector3(0.0, 20.0, 0.0)
	_camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_camera.make_current()
	var strip := Button.new()
	strip.mouse_filter = Control.MOUSE_FILTER_STOP
	strip.size = Vector2(PORT_SIZE.x, PORT_SIZE.y / 2.0)
	_port.add_child(strip)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(40, 40)
	_port.add_child(_mode)


func after_test() -> void:
	_port.free()


func _screen(cell: Vector2i, toward := Vector2.ZERO) -> Vector2:
	var world := _mode.grid.cell_to_world(cell) + Vector3(toward.x, 0.0, toward.y) * 0.45
	return _camera.unproject_position(world)


func _push(event: InputEventMouse, position: Vector2) -> void:
	event.position = position
	event.global_position = position
	_port.push_input(event)
	await await_idle_frame()


func _motion(position: Vector2) -> void:
	await _push(InputEventMouseMotion.new(), position)


func _button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	await _push(event, position)


## Presses at `from`, drags to `to`, then onto the HUD strip and releases there.
func _drag_and_release_over_hud(from: Vector2, to: Vector2) -> void:
	await _motion(from)
	await _button(from, true)
	await _motion(to)
	await _motion(OVER_HUD)
	assert_object(_port.gui_get_hovered_control()).is_not_null()
	await _button(OVER_HUD, false)


func test_a_wall_row_released_over_the_hud_is_laid() -> void:
	_mode.set_tool(BuildMode.Tool.WALL)
	var north := Vector2(0.0, -1.0)
	await _drag_and_release_over_hud(
		_screen(Vector2i(10, 30), north), _screen(Vector2i(14, 30), north)
	)
	for x in range(10, 15):
		assert_bool(_mode.grid.has_wall(Vector2i(x, 30), BuildGrid.Side.NORTH)).is_true()
	assert_bool(_mode.grid.has_wall(Vector2i(15, 30), BuildGrid.Side.NORTH)).is_false()
	assert_bool(_mode.drag_held_by_ui()).is_false()
	assert_int(_mode.undo_history().size()).is_equal(1)


func test_a_floor_rectangle_released_over_the_hud_is_filled() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	await _drag_and_release_over_hud(_screen(Vector2i(10, 30)), _screen(Vector2i(13, 32)))
	for y in range(30, 33):
		for x in range(10, 14):
			assert_int(_mode.grid.floor_at(Vector2i(x, y))).is_equal(BuildGrid.FLOOR_TILE)
	assert_int(_mode.grid.floor_at(Vector2i(14, 32))).is_equal(BuildGrid.FLOOR_NONE)
	assert_bool(_mode.drag_held_by_ui()).is_false()
	assert_int(_mode.undo_history().size()).is_equal(1)


func test_a_remove_rectangle_released_over_the_hud_clears() -> void:
	for y in range(30, 33):
		for x in range(10, 14):
			_mode.grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.set_tool(BuildMode.Tool.REMOVE)
	await _drag_and_release_over_hud(_screen(Vector2i(10, 30)), _screen(Vector2i(13, 32)))
	for y in range(30, 33):
		for x in range(10, 14):
			assert_int(_mode.grid.floor_at(Vector2i(x, y))).is_equal(BuildGrid.FLOOR_NONE)
