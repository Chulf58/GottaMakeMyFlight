class_name TestBuildModeGhostOverUi
extends GdUnitTestSuite
## The build ghost and its hover status follow the mouse over the world only:
## while the pointer is over a HUD Control the ghost is hidden and the status
## line drops the hovered cell's refusal (board item hud-follow-ups).

## A top-down orthographic camera over a 40x40 grid: 1 px is 40/720 m, so the
## top half of a 1280x720 port is a Control strip and the lower half is world.
const PORT_SIZE := Vector2i(1280, 720)
const OVER_HUD := Vector2(640, 100)
const OVER_WORLD := Vector2(640, 600)

var _port: SubViewport
var _finances: Finances
var _mode: BuildMode
var _strip: Control


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = PORT_SIZE
	add_child(_port)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 40.0
	_port.add_child(camera)
	camera.position = Vector3(0.0, 20.0, 0.0)
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	camera.make_current()
	_strip = Control.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	_strip.position = Vector2.ZERO
	_strip.size = Vector2(PORT_SIZE.x, PORT_SIZE.y / 2.0)
	_port.add_child(_strip)
	_finances = Finances.new()
	_port.add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(40, 40)
	_mode.finances = _finances
	_port.add_child(_mode)
	assert_bool(_finances.wallet.from_snapshot({"balance": "0"})).is_true()


func after_test() -> void:
	_port.free()


func _hover(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	_port.push_input(motion)
	await await_idle_frame()
	await await_idle_frame()


func _ghost() -> Node3D:
	return _mode.get_node("Ghost") as Node3D


func test_the_ghost_shows_with_its_refusal_over_the_world() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	await _hover(OVER_WORLD)
	print(
		(
			"world: hovered=%s ghost_visible=%s status='%s'"
			% [_port.gui_get_hovered_control(), _ghost().visible, _mode.status_text()]
		)
	)
	assert_object(_port.gui_get_hovered_control()).is_null()
	assert_bool(_ghost().visible).is_true()
	assert_int(_ghost().get_child_count()).is_greater(0)
	assert_str(_mode.status_text()).contains("Not enough money")


func test_the_ghost_hides_and_the_status_clears_over_a_hud_control() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	await _hover(OVER_WORLD)
	await _hover(OVER_HUD)
	print(
		(
			"hud: hovered=%s ghost_visible=%s status='%s'"
			% [_port.gui_get_hovered_control(), _ghost().visible, _mode.status_text()]
		)
	)
	assert_object(_port.gui_get_hovered_control()).is_same(_strip)
	assert_bool(_ghost().visible).is_false()
	assert_str(_mode.status_text()).is_equal("")


func test_the_ghost_returns_when_the_pointer_leaves_the_hud() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	await _hover(OVER_HUD)
	assert_bool(_ghost().visible).is_false()
	await _hover(OVER_WORLD)
	print("back: ghost_visible=%s status='%s'" % [_ghost().visible, _mode.status_text()])
	assert_bool(_ghost().visible).is_true()
	assert_str(_mode.status_text()).contains("Not enough money")


func test_an_affordable_ghost_is_hidden_over_the_hud_too() -> void:
	assert_bool(_finances.wallet.from_snapshot({"balance": "100000"})).is_true()
	_mode.set_tool(BuildMode.Tool.FLOOR)
	await _hover(OVER_WORLD)
	assert_bool(_ghost().visible).is_true()
	await _hover(OVER_HUD)
	assert_bool(_ghost().visible).is_false()
