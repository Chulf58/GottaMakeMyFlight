class_name TestBuildModeRemoveWallPick
extends GdUnitTestSuite
## The Remove tool takes the wall the pointer is on, not the floor behind it:
## a wall stands 2.5 m tall, so a click on its face lands on a ground point
## well past its foot. The wall under the pointer is found along the camera's
## line of sight (WallPick); a wall cut to a stub by the cutaway is only its
## stub; an object in front of a wall still wins; a click in the middle of a
## cell still takes the floor.

const PORT_SIZE := Vector2i(1280, 720)
## The wall stands on the north edge of this cell: the line z = 4, x from 4 to 5.
const WALL_CELL := Vector2i(4, 4)
const NORTH := BuildGrid.Side.NORTH

var _port: SubViewport
var _camera: Camera3D
var _mode: BuildMode


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = PORT_SIZE
	add_child(_port)
	_camera = Camera3D.new()
	_port.add_child(_camera)
	_camera.make_current()
	# South of the wall and above it, looking north: the default build view.
	_camera.position = Vector3(4.5, 10.0, 12.0)
	_camera.look_at(Vector3(4.5, 1.25, 4.0), Vector3.UP)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(10, 10)
	_mode.grid_centred = false
	_port.add_child(_mode)
	for y in 10:
		for x in 10:
			_mode.grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	assert_bool(_mode.grid.apply(BuildEdit.place_wall(WALL_CELL, NORTH)).ok).is_true()
	# Walls are drawn full height unless a test turns the cutaway on.
	_view().cutaway_enabled = false
	# The hover follows the real mouse each frame; the tests call it themselves.
	_mode.set_process(false)
	_mode.set_tool(BuildMode.Tool.REMOVE)


func after_test() -> void:
	_port.free()


func _view() -> BuildView:
	return _mode.get_node("BuildView") as BuildView


## The ground point under the pixel where the wall's line z = 4 shows at `height`
## metres, `along` metres from the cell's west edge.
func _ground_under_wall(height: float, along := 0.5) -> Vector3:
	var screen := _camera.unproject_position(Vector3(4.0 + along, height, 4.0))
	return _ground_under(screen)


func _ground_under(screen: Vector2) -> Vector3:
	var from := _camera.project_ray_origin(screen)
	var direction := _camera.project_ray_normal(screen)
	var point: Variant = _mode.grid_point(from, direction)
	assert_object(point).is_not_null()
	return point


func _draw_walls() -> void:
	await await_idle_frame()


func test_a_click_on_the_wall_body_takes_the_wall_not_the_floor() -> void:
	await _draw_walls()
	var point := _ground_under_wall(1.25)
	print("ground point %s" % point)
	# The floor under the pointer is well behind the wall: the old rule took it.
	assert_float(absf(point.z - 4.0)).is_greater(1.0)
	var edit := _mode.edit_at(point)
	assert_int(edit.kind).is_equal(BuildEdit.Kind.REMOVE_WALL)
	assert_that(edit.cell).is_equal(WALL_CELL)
	assert_int(edit.side).is_equal(NORTH)


func test_clicking_the_wall_body_removes_the_wall_and_keeps_the_floor() -> void:
	await _draw_walls()
	var point := _ground_under_wall(1.25)
	var cell := _mode.grid.world_to_cell(point)
	var result := _mode.apply_at(point)
	assert_bool(result.ok).is_true()
	assert_bool(_mode.grid.has_wall(WALL_CELL, NORTH)).is_false()
	assert_int(_mode.grid.floor_at(cell)).is_equal(BuildGrid.FLOOR_TILE)


func test_the_whole_height_of_the_wall_and_its_ends_are_picked() -> void:
	await _draw_walls()
	for height in [0.1, 0.8, 1.6, 2.4]:
		for along in [0.1, 0.5, 0.9]:
			var edit := _mode.edit_at(_ground_under_wall(height, along))
			assert_int(edit.kind).is_equal(BuildEdit.Kind.REMOVE_WALL)
			assert_that(edit.cell).is_equal(WALL_CELL)


func test_a_click_above_the_wall_takes_the_floor_behind_it() -> void:
	await _draw_walls()
	var edit := _mode.edit_at(_ground_under_wall(BuildView.WALL_HEIGHT + 0.5))
	assert_int(edit.kind).is_equal(BuildEdit.Kind.REMOVE_FLOOR)


func test_a_click_in_the_middle_of_a_cell_still_takes_the_floor() -> void:
	await _draw_walls()
	# In front of the wall, beside it and far behind it (the sight line passes
	# over its top): nothing stands between the camera and the point.
	for cell in [Vector2i(4, 5), Vector2i(7, 6), Vector2i(1, 1), Vector2i(4, 0)]:
		var point := _mode.grid.cell_to_world(cell)
		var edit := _mode.edit_at(point)
		assert_int(edit.kind).is_equal(BuildEdit.Kind.REMOVE_FLOOR)
		assert_that(edit.cell).is_equal(cell)


func test_a_cut_away_wall_is_not_picked_above_its_stub() -> void:
	await _draw_walls()
	# Floor lies north of the wall and the camera looks from the south: it is cut.
	_view().cutaway_enabled = true
	_view().update_cutaway(_camera.global_basis.z)
	var edge := Vector3i(WALL_CELL.x, WALL_CELL.y, NORTH)
	assert_bool(_view().cut_edges().has(edge)).is_true()
	var body := _mode.edit_at(_ground_under_wall(1.25))
	assert_int(body.kind).is_equal(BuildEdit.Kind.REMOVE_FLOOR)
	# The stub that is still drawn is picked.
	var stub := _mode.edit_at(_ground_under_wall(0.1))
	assert_int(stub.kind).is_equal(BuildEdit.Kind.REMOVE_WALL)
	assert_that(stub.cell).is_equal(WALL_CELL)


func test_the_same_wall_with_the_cutaway_off_is_picked_at_the_same_pixel() -> void:
	await _draw_walls()
	assert_int(_mode.edit_at(_ground_under_wall(1.25)).kind).is_equal(BuildEdit.Kind.REMOVE_WALL)


func test_a_glass_wall_is_picked_up_its_whole_height() -> void:
	var glass := BuildEdit.place_wall(WALL_CELL, NORTH, BuildGrid.WallKind.GLASS)
	assert_bool(_mode.grid.apply(glass).ok).is_true()
	await _draw_walls()
	var edit := _mode.edit_at(_ground_under_wall(1.8))
	assert_int(edit.kind).is_equal(BuildEdit.Kind.REMOVE_WALL)
	assert_that(edit.cell).is_equal(WALL_CELL)


func test_an_object_in_front_of_the_wall_still_wins() -> void:
	# An arch on the cell south of the wall: the line of sight to the foot of the
	# wall passes through it first.
	var placed := _mode.grid.apply(BuildEdit.place_object(SecurityLanes.ARCH, Vector2i(4, 5), 0))
	assert_bool(placed.ok).is_true()
	await _draw_walls()
	var edit := _mode.edit_at(_ground_under_wall(0.1))
	print("object in front: kind=%d object=%d" % [edit.kind, edit.object_id])
	assert_int(edit.kind).is_equal(BuildEdit.Kind.REMOVE_OBJECT)
	assert_int(edit.object_id).is_equal(placed.object_id)


func test_a_wall_in_front_of_an_object_hides_it() -> void:
	# The arch stands north of the wall, behind it from the camera.
	var placed := _mode.grid.apply(BuildEdit.place_object(SecurityLanes.ARCH, Vector2i(4, 2), 0))
	assert_bool(placed.ok).is_true()
	await _draw_walls()
	var edit := _mode.edit_at(_ground_under_wall(1.25))
	assert_int(edit.kind).is_equal(BuildEdit.Kind.REMOVE_WALL)
	assert_that(edit.cell).is_equal(WALL_CELL)


func test_the_ground_band_takes_a_wall_seen_from_straight_above() -> void:
	await _draw_walls()
	# 0.35 m inside the cell from the wall: past the old 0.3 m band.
	var point := _mode.grid.cell_to_world(WALL_CELL) + Vector3(0.0, 0.0, -0.15)
	_camera.position = point + Vector3(0.0, 12.0, 0.0)
	_camera.look_at(point, Vector3.FORWARD)
	var edit := _mode.edit_at(point)
	assert_int(edit.kind).is_equal(BuildEdit.Kind.REMOVE_WALL)
	var far := _mode.grid.cell_to_world(WALL_CELL) + Vector3(0.0, 0.0, 0.05)
	assert_int(_mode.edit_at(far).kind).is_equal(BuildEdit.Kind.REMOVE_FLOOR)


func test_the_remove_hover_over_a_wall_is_orange_and_bigger_than_a_placed_wall() -> void:
	await _draw_walls()
	_mode._update_ghost(_ground_under_wall(1.25))
	var ghost := _mode.get_node("Ghost") as Node3D
	assert_int(ghost.get_child_count()).is_equal(1)
	var box := ghost.get_child(0) as MeshInstance3D
	var tint := (box.material_override as StandardMaterial3D).albedo_color
	assert_that(tint).is_equal(BuildMode.AREA_REMOVE_TINT)
	var size := (box.mesh as BoxMesh).size
	assert_float(size.z).is_greater(BuildView.WALL_THICKNESS * 1.5)
	assert_float(size.y).is_greater_equal(BuildView.WALL_HEIGHT)


# The input path: a click that slips a few pixels is still a click.


func _click(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = _mode.pointer_override
	return event


func _motion() -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = _mode.pointer_override
	return event


func test_a_click_on_a_wall_that_slips_across_a_cell_border_still_takes_the_wall() -> void:
	await _draw_walls()
	var press := _camera.unproject_position(Vector3(4.9, 1.25, 4.0))
	var slipped := press + Vector2(3.0, 0.0)
	var from := _ground_under(press)
	var to := _ground_under(slipped)
	# The slip moves the ground point into the next cell: a 2-cell rectangle.
	assert_that(_mode.grid.world_to_cell(from)).is_not_equal(_mode.grid.world_to_cell(to))
	_mode.pointer_override = press
	_mode._unhandled_input(_click(true))
	_mode.pointer_override = slipped
	_mode._unhandled_input(_motion())
	_mode._unhandled_input(_click(false))
	assert_bool(_mode.grid.has_wall(WALL_CELL, NORTH)).is_false()
	assert_int(_mode.grid.floor_at(_mode.grid.world_to_cell(from))).is_equal(BuildGrid.FLOOR_TILE)
	assert_int(_mode.grid.floor_at(_mode.grid.world_to_cell(to))).is_equal(BuildGrid.FLOOR_TILE)


func test_a_real_drag_still_clears_a_rectangle() -> void:
	await _draw_walls()
	var press := _camera.unproject_position(Vector3(4.9, 1.25, 4.0))
	var dragged := press + Vector2(0.0, -120.0)
	_mode.pointer_override = press
	_mode._unhandled_input(_click(true))
	_mode.pointer_override = dragged
	_mode._unhandled_input(_motion())
	_mode._unhandled_input(_click(false))
	var cell := _mode.grid.world_to_cell(_ground_under(press))
	assert_int(_mode.grid.floor_at(cell)).is_equal(BuildGrid.FLOOR_NONE)
