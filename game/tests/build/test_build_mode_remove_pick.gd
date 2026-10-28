class_name TestBuildModeRemovePick
extends GdUnitTestSuite
## The Remove tool takes the object the pointer is on, even where a tall object
## hides the ground behind it on screen: the pointer's ground point then lies
## beyond the object, near the wall edge behind it (smoke playtest 8: a click
## on a security arch at the terminal edge removed the wall behind it). A wall
## the pointer really points at is still taken.

const PORT_SIZE := Vector2i(1280, 720)
## A security arch with a wall on its east edge, the edge it shares with BEYOND.
const ARCH_CELL := Vector2i(4, 4)
const BEYOND := Vector2i(5, 4)

var _port: SubViewport
var _camera: Camera3D
var _mode: BuildMode
var _arch := 0


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
	_port.add_child(_mode)
	var grid := _mode.grid
	for y in 10:
		for x in 10:
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	assert_bool(grid.apply(BuildEdit.place_wall(ARCH_CELL, BuildGrid.Side.EAST)).ok).is_true()
	var placed := grid.apply(BuildEdit.place_object(SecurityLanes.ARCH, ARCH_CELL, 0))
	assert_bool(placed.ok).is_true()
	_arch = placed.object_id
	_mode.set_tool(BuildMode.Tool.REMOVE)


func after_test() -> void:
	_port.free()


## A ground point in BEYOND, 0.15 m from the wall edge it shares with the arch.
func _beyond_point() -> Vector3:
	return _mode.grid.cell_to_world(BEYOND) + Vector3(-0.35, 0.0, 0.0)


## Puts the camera at `eye`, looking at `point`.
func _look(eye: Vector3, point: Vector3) -> void:
	_camera.position = eye
	_camera.look_at(point, Vector3.UP if absf(eye.x - point.x) > 0.01 else Vector3.FORWARD)


func test_a_point_behind_the_arch_from_the_camera_takes_the_arch() -> void:
	var point := _beyond_point()
	# From the west and above: the line of sight to the point passes through
	# the 2.3 m arch, about 0.2 m up at its far side.
	_look(Vector3(0.0, 6.0, point.z), point)
	var edit := _mode.edit_at(point)
	print("slanted from the west: kind=%d object=%d" % [edit.kind, edit.object_id])
	assert_int(edit.kind).is_equal(BuildEdit.Kind.REMOVE_OBJECT)
	assert_int(edit.object_id).is_equal(_arch)


func test_clicking_there_removes_the_arch_and_keeps_the_wall() -> void:
	var point := _beyond_point()
	_look(Vector3(0.0, 6.0, point.z), point)
	var result := _mode.apply_at(point)
	assert_bool(result.ok).is_true()
	assert_int(_mode.grid.object_ids().size()).is_equal(0)
	assert_bool(_mode.grid.has_wall(ARCH_CELL, BuildGrid.Side.EAST)).is_true()


func test_the_same_point_seen_from_above_takes_the_wall() -> void:
	var point := _beyond_point()
	_look(point + Vector3(0.0, 12.0, 0.0), point)
	var edit := _mode.edit_at(point)
	print("from above: kind=%d side=%d" % [edit.kind, edit.side])
	assert_int(edit.kind).is_equal(BuildEdit.Kind.REMOVE_WALL)
	assert_that(edit.cell).is_equal(BEYOND)


func test_an_arch_behind_the_point_is_not_taken() -> void:
	var point := _beyond_point()
	# From the east the point is reached before the arch.
	_look(Vector3(10.0, 6.0, point.z), point)
	var edit := _mode.edit_at(point)
	print("slanted from the east: kind=%d" % edit.kind)
	assert_int(edit.kind).is_equal(BuildEdit.Kind.REMOVE_WALL)


func test_the_object_on_the_point_still_wins_without_a_camera() -> void:
	_camera.clear_current(false)
	var edit := _mode.edit_at(_mode.grid.cell_to_world(ARCH_CELL))
	assert_int(edit.kind).is_equal(BuildEdit.Kind.REMOVE_OBJECT)
	assert_int(edit.object_id).is_equal(_arch)
	assert_int(_mode.edit_at(_beyond_point()).kind).is_equal(BuildEdit.Kind.REMOVE_WALL)
