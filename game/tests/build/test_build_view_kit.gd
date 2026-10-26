class_name TestBuildViewKit
extends GdUnitTestSuite
## The kit piece each object and wall uses, and BuildView drawing them with
## the cutaway.

const NORTH := BuildGrid.Side.NORTH
const WEST := BuildGrid.Side.WEST
const DOOR_EDGE := Vector3i(3, 5, NORTH)
const GLASS_EDGE := Vector3i(2, 5, NORTH)

var _grid: BuildGrid
var _view: BuildView


## The 3x3 room of test_build_view_cutaway, with a door and a glass wall in
## the south side.
func before() -> void:
	_grid = BuildGrid.new(Vector2i(8, 8))
	for y in range(2, 5):
		for x in range(2, 5):
			_grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for i in range(2, 5):
		_grid.apply(BuildEdit.place_wall(Vector2i(i, 2), NORTH))
		_grid.apply(BuildEdit.place_wall(Vector2i(i, 4), BuildGrid.Side.SOUTH))
		_grid.apply(BuildEdit.place_wall(Vector2i(2, i), WEST))
		_grid.apply(BuildEdit.place_wall(Vector2i(4, i), BuildGrid.Side.EAST))
	_grid.apply(BuildEdit.place_object(&"seat_row", Vector2i(2, 3), 0))
	_view = BuildView.new()
	_view.wall_kind_source = func(cell: Vector2i, side: int) -> int:
		var edge := Vector3i(cell.x, cell.y, side)
		if edge == DOOR_EDGE:
			return InteriorKit.WallKind.DOOR
		if edge == GLASS_EDGE:
			return InteriorKit.WallKind.GLASS
		return InteriorKit.WallKind.PLAIN
	add_child(_view)
	_view.refresh(_grid)


func after() -> void:
	_view.free()


func _toward_eye(yaw_degrees: float) -> Vector3:
	return Basis(Vector3.UP, deg_to_rad(yaw_degrees)) * Vector3(0.0, 1.0, 1.0).normalized()


func test_desk_scanner_and_seats_use_their_kit_pieces() -> void:
	for id in [&"checkin_desk", &"security_scanner", &"seat_row"]:
		assert_object(BuildCatalog.get_def(id)).is_not_null()
		assert_str(InteriorKit.object_piece(id)).is_equal(str(id))
	assert_str(InteriorKit.object_piece(&"no_such_thing")).is_empty()


func test_wall_parts_per_kind_full_and_cut() -> void:
	var stub_y := InteriorKit.STUB_HEIGHT / InteriorKit.WALL_HEIGHT
	assert_str(InteriorKit.wall_parts(InteriorKit.WallKind.PLAIN, false)[0][0]).is_equal("wall")
	assert_str(InteriorKit.wall_parts(InteriorKit.WallKind.GLASS, false)[0][0]).is_equal(
		"wall_glass"
	)
	assert_str(InteriorKit.wall_parts(InteriorKit.WallKind.DOOR, false)[0][0]).is_equal("wall_door")
	var plain_cut: Array = InteriorKit.wall_parts(InteriorKit.WallKind.PLAIN, true)
	assert_str(plain_cut[0][0]).is_equal("wall")
	assert_float((plain_cut[0][1] as Transform3D).basis.get_scale().y).is_equal_approx(
		stub_y, 0.0001
	)
	var glass_cut: Array = InteriorKit.wall_parts(InteriorKit.WallKind.GLASS, true)
	assert_str(glass_cut[0][0]).is_equal(InteriorKit.GLASS_KERB)
	var door_cut: Array = InteriorKit.wall_parts(InteriorKit.WallKind.DOOR, true)
	assert_int(door_cut.size()).is_equal(2)
	for part in door_cut:
		var at: Transform3D = part[1]
		assert_str(part[0]).is_equal("wall")
		assert_float(absf(at.origin.x)).is_equal_approx(InteriorKit.JAMB_OFFSET, 0.0001)
		assert_float(at.basis.get_scale().x).is_equal_approx(InteriorKit.JAMB_WIDTH, 0.0001)
	var post_cut: Transform3D = InteriorKit.post_parts(true)[0][1]
	assert_float(post_cut.basis.get_scale().y * InteriorKit.POST_HEIGHT).is_equal_approx(
		InteriorKit.STUB_HEIGHT, 0.0001
	)


func test_glass_kerb_keeps_only_the_kerb() -> void:
	var parts := InteriorKit.meshes(InteriorKit.GLASS_KERB)
	assert_int(parts.size()).is_equal(1)
	var box: AABB = (parts[0][0] as Mesh).get_aabb()
	assert_float(box.end.y).is_less_equal(InteriorKit.GLASS_KERB_TOP + 0.003)
	assert_float(box.size.x).is_equal_approx(1.0, 0.01)


func test_door_leaves_keep_their_parked_offsets() -> void:
	var offsets := []
	for part in InteriorKit.meshes("wall_door"):
		offsets.append(snappedf((part[1] as Transform3D).origin.x, 0.01))
	offsets.sort()
	assert_array(offsets).is_equal([-0.61, 0.0, 0.61])


func test_placed_objects_keep_their_materials_and_ghosts_are_tinted() -> void:
	var def := BuildCatalog.get_def(&"seat_row")
	var real := auto_free(BuildView.make_object_node(def, null)) as Node3D
	var tint := StandardMaterial3D.new()
	var ghost := auto_free(BuildView.make_object_node(def, tint)) as Node3D
	var real_mesh := real.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var ghost_mesh := ghost.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	assert_object(real_mesh.material_override).is_null()
	assert_object(real_mesh.mesh.surface_get_material(0)).is_not_null()
	assert_object(ghost_mesh.material_override).is_same(tint)
	assert_int(_view.object_node_count()).is_equal(1)


func test_view_draws_the_south_side_as_stubs_from_the_south_east() -> void:
	_view.cutaway_enabled = true
	_view.update_cutaway(_toward_eye(45.0))
	var counts := _view.piece_counts()
	# South: door cut to 2 jambs, glass to its kerb, 1 plain stub. East: 3 stubs.
	assert_int(counts["wall_door"]).is_equal(0)
	assert_int(counts["wall_glass"]).is_equal(0)
	assert_int(counts[InteriorKit.GLASS_KERB]).is_equal(1)
	assert_int(counts["wall"]).is_equal(6 + 2 + 1 + 3)
	assert_int(counts["wall_post"]).is_equal(4)
	assert_int(counts["floor_tile"]).is_equal(9)
	assert_int(_view.cut_edges().size()).is_equal(6)
	var low := 0
	for at in _view.piece_transforms("wall_post"):
		if at.basis.get_scale().y < 0.5:
			low += 1
	assert_int(low).override_failure_message("only the south-east post is a stub").is_equal(1)


func test_view_draws_the_door_and_glass_full_from_the_north_west() -> void:
	_view.update_cutaway(_toward_eye(-135.0))
	var counts := _view.piece_counts()
	assert_int(counts["wall_door"]).is_equal(1)
	assert_int(counts["wall_glass"]).is_equal(1)
	assert_int(counts[InteriorKit.GLASS_KERB]).is_equal(0)
	assert_int(counts["wall"]).is_equal(10)
	var stubs := 0
	for at in _view.piece_transforms("wall"):
		if at.basis.get_scale().y < 0.5:
			stubs += 1
	assert_int(stubs).is_equal(6)


func test_cutaway_off_draws_every_wall_full() -> void:
	_view.update_cutaway(_toward_eye(45.0))
	_view.cutaway_enabled = false
	assert_int(_view.cut_edges().size()).is_equal(0)
	assert_int(_view.piece_counts()["wall_door"]).is_equal(1)
	_view.cutaway_enabled = true


func test_door_drops_with_a_neighbour_on_the_last_row_and_clears_when_walls_go() -> void:
	# A wall line on the grid's last row (SOUTH edges), door in the middle. Only
	# the neighbours have floor behind them, so only they cut on their own.
	var grid := BuildGrid.new(Vector2i(6, 5))
	for x in [2, 4]:
		grid.apply(BuildEdit.paint_floor(Vector2i(x, 4), BuildGrid.FLOOR_TILE, 1))
	for x in range(2, 5):
		grid.apply(BuildEdit.place_wall(Vector2i(x, 4), BuildGrid.Side.SOUTH))
	var view := auto_free(BuildView.new()) as BuildView
	view.wall_kind_source = func(cell: Vector2i, side: int) -> int:
		if cell == Vector2i(3, 4) and side == BuildGrid.Side.SOUTH:
			return InteriorKit.WallKind.DOOR
		return InteriorKit.WallKind.PLAIN
	add_child(view)
	view.refresh(grid)
	assert_array(WallCutaway.wall_edges(grid)).contains_exactly(
		[
			Vector3i(2, 4, BuildGrid.Side.SOUTH),
			Vector3i(3, 4, BuildGrid.Side.SOUTH),
			Vector3i(4, 4, BuildGrid.Side.SOUTH)
		]
	)
	view.update_cutaway(_toward_eye(0.0))
	assert_int(view.cut_edges().size()).is_equal(3)
	assert_int(view.piece_counts()["wall_door"]).is_equal(0)
	assert_int(view.piece_counts()["wall"]).is_equal(2 + 2)
	# Two free ends, each joining only cut walls: two stub posts.
	assert_int(view.piece_counts()["wall_post"]).is_equal(2)
	for at in view.piece_transforms("wall_post"):
		assert_float(at.basis.get_scale().y).is_less(0.5)
	view.update_cutaway(_toward_eye(180.0))
	assert_int(view.piece_counts()["wall_door"]).is_equal(1)
	for x in range(2, 5):
		grid.apply(BuildEdit.remove_wall(Vector2i(x, 4), BuildGrid.Side.SOUTH))
	view.refresh(grid)
	for piece in ["wall", "wall_door", "wall_post"]:
		assert_int(view.piece_counts()[piece]).override_failure_message(piece).is_equal(0)


func test_entrance_door_piece_drops_to_jambs_like_a_door_wall() -> void:
	# Room x 2..4, y 2..4 with plain walls beside the entrance on the south side.
	var grid := BuildGrid.new(Vector2i(8, 8))
	for y in range(2, 5):
		for x in range(2, 5):
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for x in [2, 4]:
		grid.apply(BuildEdit.place_wall(Vector2i(x, 4), BuildGrid.Side.SOUTH))
	var door_id := grid.apply(BuildEdit.place_object(&"entrance_door", Vector2i(3, 4), 2)).object_id
	var view := auto_free(BuildView.new()) as BuildView
	add_child(view)
	view.refresh(grid)
	var door := view.object_node(door_id)
	var back_edge := Vector3i(3, 5, NORTH)
	view.update_cutaway(_toward_eye(0.0))
	assert_array(view.cut_edges()).contains([back_edge])
	assert_bool(door.visible).is_false()
	assert_int(_jamb_count(view)).is_equal(2)
	view.update_cutaway(_toward_eye(180.0))
	assert_array(view.cut_edges()).not_contains([back_edge])
	assert_bool(door.visible).is_true()
	assert_int(_jamb_count(view)).is_equal(0)


## Wall instances scaled to a jamb's width.
func _jamb_count(view: BuildView) -> int:
	var count := 0
	for at in view.piece_transforms("wall"):
		if is_equal_approx(at.basis.get_scale().x, InteriorKit.JAMB_WIDTH):
			count += 1
	return count


func test_a_redraw_before_refresh_uses_the_drawn_records() -> void:
	# The grid loses the entrance but the view has not been refreshed yet: a
	# cutaway redraw in between must not read the grid's (missing) record.
	var grid := BuildGrid.new(Vector2i(8, 8))
	for y in range(3, 5):
		for x in range(2, 5):
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	var door_id := grid.apply(BuildEdit.place_object(&"entrance_door", Vector2i(3, 4), 2)).object_id
	assert_int(door_id).is_greater(0)
	var view := auto_free(BuildView.new()) as BuildView
	add_child(view)
	view.refresh(grid)
	assert_bool(grid.apply(BuildEdit.remove_object(door_id)).ok).is_true()
	view.update_cutaway(_toward_eye(0.0))
	assert_array(view.cut_edges()).contains([Vector3i(3, 5, NORTH)])
	assert_bool(view.object_node(door_id).visible).is_false()
	view.refresh(grid)
	assert_object(view.object_node(door_id)).is_null()
