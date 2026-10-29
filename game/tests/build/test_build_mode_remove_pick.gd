class_name TestBuildModeRemovePick
extends GdUnitTestSuite
## The Remove tool takes the object the pointer is on, even where a tall object
## hides the ground behind it on screen: the pointer's ground point then lies
## beyond the object, near the wall edge behind it (smoke playtest 8: a click
## on a security arch at the terminal edge removed the wall behind it). A wall
## the pointer really points at is still taken. An object behind a wall drawn
## full height is not seen, one behind a cut wall or glass is, and an object is
## seen up to the top of its model (BuildView.pick_height), not its def height.

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


func _view() -> BuildView:
	return _mode.get_node("BuildView") as BuildView


## Adds a wall straight on the grid and lets the view draw it.
func _wall(cell: Vector2i, side: int, kind: int) -> void:
	assert_bool(_mode.grid.apply(BuildEdit.place_wall(cell, side, kind)).ok).is_true()
	await await_idle_frame()


func test_an_opaque_wall_in_front_hides_the_arch() -> void:
	_view().cutaway_enabled = false
	await _wall(ARCH_CELL, BuildGrid.Side.WEST, BuildGrid.WallKind.PLAIN)
	var point := _beyond_point()
	_look(Vector3(0.0, 6.0, point.z), point)
	var edit := _mode.edit_at(point)
	print("full wall in front: kind=%d cell=%s side=%d" % [edit.kind, edit.cell, edit.side])
	assert_int(edit.kind).is_equal(BuildEdit.Kind.REMOVE_WALL)
	assert_that(edit.cell).is_equal(BEYOND)


func test_a_cut_wall_in_front_does_not_hide_the_arch() -> void:
	await _wall(ARCH_CELL, BuildGrid.Side.WEST, BuildGrid.WallKind.PLAIN)
	var point := _beyond_point()
	_look(Vector3(0.0, 6.0, point.z), point)
	_view().update_cutaway(_camera.global_basis.z)
	var edge := Vector3i(ARCH_CELL.x, ARCH_CELL.y, BuildGrid.Side.WEST)
	assert_bool(_view().cut_edges().has(edge)).is_true()
	assert_int(_mode.edit_at(point).object_id).is_equal(_arch)


func test_a_glass_wall_in_front_does_not_hide_the_arch() -> void:
	_view().cutaway_enabled = false
	await _wall(ARCH_CELL, BuildGrid.Side.WEST, BuildGrid.WallKind.GLASS)
	var point := _beyond_point()
	_look(Vector3(0.0, 6.0, point.z), point)
	assert_int(_mode.edit_at(point).object_id).is_equal(_arch)


## A door on the arch's west edge, between plain walls in line with it.
func _door_wall() -> void:
	for row in [ARCH_CELL.y - 1, ARCH_CELL.y + 1]:
		(
			assert_bool(
				(
					_mode
					. grid
					. apply(BuildEdit.place_wall(Vector2i(ARCH_CELL.x, row), BuildGrid.Side.WEST))
					. ok
				)
			)
			. is_true()
		)
	await _wall(ARCH_CELL, BuildGrid.Side.WEST, BuildGrid.WallKind.DOOR)


## A door wall on the arch's west edge, drawn full: its leaves park beside a
## clear opening 0.8 m wide and 2.24 m tall (wall_door.glb), centred on the edge.
func test_a_line_of_sight_through_a_door_wall_opening_takes_the_arch() -> void:
	_view().cutaway_enabled = false
	await _door_wall()
	var point := _beyond_point()
	_look(Vector3(0.0, 6.0, point.z), point)
	var edit := _mode.edit_at(point)
	print("through the door opening: kind=%d object=%d" % [edit.kind, edit.object_id])
	assert_int(edit.kind).is_equal(BuildEdit.Kind.REMOVE_OBJECT)
	assert_int(edit.object_id).is_equal(_arch)


func test_a_line_of_sight_through_a_door_wall_beside_its_opening_is_hidden() -> void:
	_view().cutaway_enabled = false
	await _door_wall()
	# 0.45 m off the door's axis the line meets the leaf, not the opening.
	var point := _beyond_point() + Vector3(0.0, 0.0, 0.45)
	_look(Vector3(0.0, 6.0, point.z), point)
	var edit := _mode.edit_at(point)
	print("beside the door opening: kind=%d object=%d" % [edit.kind, edit.object_id])
	assert_int(edit.kind).is_not_equal(BuildEdit.Kind.REMOVE_OBJECT)


func test_a_line_of_sight_through_the_top_of_the_arch_takes_it() -> void:
	# The line passes over the arch's far side 2.37 m up: above its def height
	# (2.3 m) but under the top of its model (2.42 m).
	var top := BuildView.pick_height(BuildCatalog.get_def(SecurityLanes.ARCH))
	var over := _mode.grid.cell_to_world(BEYOND) + Vector3(-0.5, 2.37, 0.0)
	var eye := Vector3(0.0, 12.0, over.z)
	var point := eye + (over - eye) * (eye.y / (eye.y - over.y))
	_look(eye, point)
	var edit := _mode.edit_at(point)
	var def_height := BuildCatalog.get_def(SecurityLanes.ARCH).height
	print(
		(
			"arch pick height %.3f def height %.2f; point %s kind=%d object=%d"
			% [top, def_height, point, edit.kind, edit.object_id]
		)
	)
	assert_float(top).is_greater_equal(2.42)
	assert_int(edit.kind).is_equal(BuildEdit.Kind.REMOVE_OBJECT)
	assert_int(edit.object_id).is_equal(_arch)


func test_every_pick_height_covers_the_drawn_model() -> void:
	for id in BuildCatalog.ids():
		var def := BuildCatalog.get_def(id)
		var node := BuildView.make_object_node(def, null)
		var top := 0.0
		for mesh in node.find_children("*", "MeshInstance3D", true, false):
			var frame := (mesh as Node3D).transform
			var parent := mesh.get_parent()
			while parent != node:
				frame = (parent as Node3D).transform * frame
				parent = parent.get_parent()
			top = maxf(top, (frame * (mesh as MeshInstance3D).get_aabb()).end.y)
		node.free()
		print("%s model top %.3f pick height %.3f" % [id, top, BuildView.pick_height(def)])
		assert_float(BuildView.pick_height(def)).is_greater_equal(top - 0.0001)
		assert_float(BuildView.pick_height(def)).is_greater_equal(def.height)
