class_name TestBuildModeRemovePickShell
extends GdUnitTestSuite
## The Remove tool does not take an object the terminal shell hides. With the
## real Toon shell's roof drawn (wide zoom) every ray into the shell is blocked,
## so a click does not pick an interior object it passes through the roof to
## reach. With the roof gone, a facade side that stands full height hides the
## object behind it, and a side the cutaway has cut to a kerb does not.

const SHELL := "res://assets/buildings/tp_airport_shell.glb"
const PORT_SIZE := Vector2i(1280, 720)
const ARCH_CELL := Vector2i(4, 4)
const WEST := ShellCutaway.Side.WEST

var _world: Node3D
var _view: ShellView
var _port: SubViewport
var _camera: Camera3D
var _mode: BuildMode
var _arch := 0


func before() -> void:
	_world = Node3D.new()
	add_child(_world)
	var shell := (load(SHELL) as PackedScene).instantiate() as Node3D
	_world.add_child(shell)
	_view = ShellView.new()
	_view.shell = shell
	_world.add_child(_view)


func after() -> void:
	_world.free()


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = PORT_SIZE
	add_child(_port)
	_camera = Camera3D.new()
	_port.add_child(_camera)
	_camera.make_current()
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(10, 10)
	_mode.grid_centred = false
	_mode.shell_view = _view
	_port.add_child(_mode)
	for y in 10:
		for x in 10:
			_mode.grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	assert_bool(_mode.grid.apply(BuildEdit.place_wall(ARCH_CELL, BuildGrid.Side.EAST)).ok).is_true()
	var placed := _mode.grid.apply(BuildEdit.place_object(SecurityLanes.ARCH, ARCH_CELL, 0))
	assert_bool(placed.ok).is_true()
	_arch = placed.object_id
	_mode.set_tool(BuildMode.Tool.REMOVE)


func after_test() -> void:
	_port.free()
	_view.cutaway.roof_level = 0.0
	_view.cutaway.side_levels = [0.0, 0.0, 0.0, 0.0]
	_view.apply()


## The ground point 0.15 m inside the next cell east of the arch, whose line of
## sight from the west passes through the arch.
func _point() -> Vector3:
	return _mode.grid.cell_to_world(Vector2i(5, 4)) + Vector3(-0.35, 0.0, 0.0)


## Looks at the point from west of the grid, `rise` metres up.
func _look_from_west(rise: float) -> void:
	var point := _point()
	_camera.position = Vector3(-3.0, rise, point.z)
	_camera.look_at(point, Vector3.FORWARD)


## Draws the shell with the roof at `roof` (0 drawn, 1 gone) and the west side
## cut by `west` before the roof gate.
func _shell_state(roof: float, west: float) -> void:
	_view.cutaway.roof_level = roof
	_view.cutaway.side_levels = [0.0, 0.0, 0.0, west]
	_view.apply()


## The game scene points BuildMode at its ShellView sibling, so Remove sees the
## shell in the real game and not only in these tests. Read from the scene's
## state: instantiating a BuildMode without entering the tree leaves its view
## nodes orphans, and entering it would start the whole game.
func test_the_game_scene_gives_build_mode_its_shell_view() -> void:
	var state := (load("res://main/main.tscn") as PackedScene).get_state()
	var wired: Variant = null
	var view_node := ""
	for i in state.get_node_count():
		if state.get_node_name(i) == &"ShellView":
			view_node = str(state.get_node_path(i))
		if state.get_node_name(i) != &"BuildMode":
			continue
		for p in state.get_node_property_count(i):
			if state.get_node_property_name(i, p) == &"shell_view":
				wired = state.get_node_property_value(i, p)
	# BuildMode's "../ShellView" is the ShellView node, a child of the root.
	assert_that(wired).is_equal(NodePath("../ShellView"))
	assert_str(view_node).is_equal("./ShellView")


func test_the_real_shell_is_set_up() -> void:
	assert_bool(_view.is_ready()).is_true()


func test_the_arch_is_picked_with_no_shell_view() -> void:
	_mode.shell_view = null
	_shell_state(0.0, 0.0)
	_look_from_west(60.0)
	assert_int(_mode.edit_at(_point()).object_id).is_equal(_arch)


func test_a_drawn_roof_hides_the_arch() -> void:
	_shell_state(0.0, 0.0)
	_look_from_west(60.0)
	var edit := _mode.edit_at(_point())
	print("roof drawn: kind=%d object=%d" % [edit.kind, edit.object_id])
	assert_int(edit.kind).is_equal(BuildEdit.Kind.REMOVE_WALL)


func test_a_roof_still_fading_out_hides_the_arch() -> void:
	_shell_state(0.9, 1.0)
	_look_from_west(60.0)
	assert_int(_mode.edit_at(_point()).kind).is_equal(BuildEdit.Kind.REMOVE_WALL)


func test_a_facade_standing_full_height_hides_the_arch() -> void:
	_shell_state(1.0, 0.0)
	_look_from_west(6.0)
	assert_float(_view.cutaway.cut(WEST)).is_equal(0.0)
	var edit := _mode.edit_at(_point())
	print("roof gone, west standing: kind=%d object=%d" % [edit.kind, edit.object_id])
	assert_int(edit.kind).is_equal(BuildEdit.Kind.REMOVE_WALL)


func test_a_cut_facade_does_not_hide_the_arch() -> void:
	_shell_state(1.0, 1.0)
	_look_from_west(6.0)
	assert_float(_view.cutaway.cut(WEST)).is_equal(1.0)
	assert_int(_mode.edit_at(_point()).object_id).is_equal(_arch)


func test_a_line_over_the_standing_facade_is_not_hidden() -> void:
	_shell_state(1.0, 0.0)
	# 60 m up, the line crosses the west face about 52 m above the floor.
	_look_from_west(60.0)
	assert_int(_mode.edit_at(_point()).object_id).is_equal(_arch)


## The arch's own cell: no sight line is needed to reach it, so only the shell
## in front of the ground point can stop Remove taking it.
func _look_at_arch_cell(rise: float) -> Vector3:
	var point := _mode.grid.cell_to_world(ARCH_CELL)
	_camera.position = Vector3(-3.0, rise, point.z)
	_camera.look_at(point, Vector3.FORWARD)
	return point


func test_a_click_on_the_arch_cell_under_a_drawn_roof_does_not_take_it() -> void:
	_shell_state(0.0, 0.0)
	var point := _look_at_arch_cell(60.0)
	var edit := _mode.edit_at(point)
	print("arch cell, roof drawn: kind=%d object=%d" % [edit.kind, edit.object_id])
	assert_int(edit.kind).is_not_equal(BuildEdit.Kind.REMOVE_OBJECT)


func test_a_click_on_the_arch_cell_under_a_fading_roof_does_not_take_it() -> void:
	_shell_state(0.9, 1.0)
	var point := _look_at_arch_cell(60.0)
	assert_int(_mode.edit_at(point).kind).is_not_equal(BuildEdit.Kind.REMOVE_OBJECT)


func test_a_click_on_the_arch_cell_with_the_roof_gone_takes_it() -> void:
	_shell_state(1.0, 1.0)
	var point := _look_at_arch_cell(6.0)
	assert_int(_mode.edit_at(point).object_id).is_equal(_arch)
