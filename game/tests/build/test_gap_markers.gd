class_name TestGapMarkers
extends GdUnitTestSuite
## Gap markers (GapMarkers): a strip on every open edge of the outer wall and
## one sign per run of them (EnclosureGaps), redrawn when the grid changes.
## The subject is a closed 4x3 box of floor at x 2-5, y 2-4 on a 12x10 grid.

const BOX := Rect2i(2, 2, 4, 3)

var _grid: BuildGrid
var _markers: GapMarkers


func before_test() -> void:
	_grid = BuildGrid.new(Vector2i(12, 10))
	var edits: Array[BuildEdit] = []
	for y in range(BOX.position.y, BOX.end.y):
		for x in range(BOX.position.x, BOX.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for result in _grid.apply_batch(edits):
		assert_bool(result.ok).is_true()
	EnclosureKit.close_floor(_grid)
	_markers = auto_free(GapMarkers.new())
	add_child(_markers)
	_markers.bind(_grid)


func _remove(cell: Vector2i, side: int) -> void:
	assert_bool(_grid.apply(BuildEdit.remove_wall(cell, side)).ok).is_true()


func test_a_closed_box_shows_no_marker() -> void:
	assert_int(_markers.strip_count()).is_equal(0)
	assert_int(_markers.sign_count()).is_equal(0)


func test_open_edges_get_a_strip_each_and_a_sign_per_run() -> void:
	for x in [2, 3, 4]:
		_remove(Vector2i(x, 4), BuildGrid.Side.SOUTH)
	_remove(Vector2i(5, 2), BuildGrid.Side.EAST)
	assert_int(_markers.strip_count()).is_equal(4)
	assert_int(_markers.sign_count()).is_equal(2)
	# The south run's sign stands over the middle of its three edges.
	var at := _markers.sign_positions()
	var south := _grid.origin + Vector3(3.5, GapMarkers.SIGN_LIFT_M, 5.0)
	assert_bool(at.any(func(p: Vector3) -> bool: return p.is_equal_approx(south))).is_true()


func test_closing_the_gap_clears_the_markers() -> void:
	_remove(Vector2i(5, 2), BuildGrid.Side.EAST)
	assert_int(_markers.sign_count()).is_equal(1)
	var marker: Sprite3D = _markers.signs()[0]
	assert_bool(marker.visible).is_true()
	assert_bool(_grid.apply(BuildEdit.place_wall(Vector2i(5, 2), BuildGrid.Side.EAST)).ok).is_true()
	assert_int(_markers.strip_count()).is_equal(0)
	assert_int(_markers.sign_count()).is_equal(0)
	# The sign that was shown is hidden (kept as a spare), not left standing.
	assert_bool(is_instance_valid(marker)).is_true()
	assert_bool(marker.visible).is_false()


## Hidden signs are kept for reuse only up to SPARE_SIGNS; the rest are freed.
func test_spare_signs_are_bounded_when_many_gaps_close() -> void:
	var cells: Array[Vector2i] = [
		Vector2i(2, 2), Vector2i(4, 2), Vector2i(2, 4), Vector2i(4, 4), Vector2i(5, 3)
	]
	var sides: Array[int] = [
		BuildGrid.Side.NORTH,
		BuildGrid.Side.NORTH,
		BuildGrid.Side.SOUTH,
		BuildGrid.Side.SOUTH,
		BuildGrid.Side.EAST,
	]
	for i in cells.size():
		_remove(cells[i], sides[i])
	var runs := _markers.sign_count()
	assert_int(runs).is_greater(GapMarkers.SPARE_SIGNS)
	var made := _markers.signs().duplicate()
	for i in cells.size():
		assert_bool(_grid.apply(BuildEdit.place_wall(cells[i], sides[i])).ok).is_true()
	assert_int(_markers.sign_count()).is_equal(0)
	assert_int(_markers.signs().size()).is_equal(GapMarkers.SPARE_SIGNS)
	var kept := 0
	for marker: Sprite3D in made:
		if marker.is_inside_tree():
			kept += 1
			assert_bool(marker.visible).is_false()
		else:
			assert_bool(marker.is_queued_for_deletion()).is_true()
	assert_int(kept).is_equal(GapMarkers.SPARE_SIGNS)


## The sign is MissMarkers.SIGN_PX on screen, worked out as the MissMarkers
## test does: pixel size times the icon's pixels, over the view's size at one
## metre, at the window's rendered height.
func test_the_sign_is_sign_px_on_screen() -> void:
	_remove(Vector2i(5, 2), BuildGrid.Side.EAST)
	_markers.update_sizes(true)
	var marker: Sprite3D = _markers.signs()[0]
	var window := get_tree().root
	var camera := window.get_camera_3d()
	var fov := camera.fov if camera != null else GapMarkers.FALLBACK_FOV
	var rendered := float(window.size.y)
	var on_screen := (
		marker.pixel_size * MarkerIcons.SIZE * rendered / (2.0 * tan(deg_to_rad(fov) / 2.0))
	)
	print("wall gap sign on screen: %.2f px" % on_screen)
	assert_float(on_screen).is_equal_approx(MissMarkers.SIGN_PX, 0.01)


## The wall-gap sign is the broken-wall build hint, drawn over walls and roof,
## with no caption (decision calm-cozy-default-view-quiet-world-detail-on-ask-
## soft-statio, part 2).
func test_the_sign_is_the_wall_gap_glyph_with_no_caption() -> void:
	_remove(Vector2i(5, 2), BuildGrid.Side.EAST)
	var marker: Sprite3D = _markers.signs()[0]
	assert_object(marker.texture).is_same(MarkerIcons.icon(MarkerIcons.Glyph.WALL_GAP))
	assert_object(marker.texture).is_not_same(MarkerIcons.icon(MarkerIcons.Glyph.QUEUE_FULL))
	assert_bool(marker.no_depth_test).is_true()
	assert_int(marker.find_children("*", "Label3D", true, false).size()).is_equal(0)


## Its words reach HoverTarget only in build mode; the sign stays outside it.
func test_the_hover_text_is_reported_only_in_build_mode() -> void:
	var port: SubViewport = auto_free(SubViewport.new())
	port.size = Vector2i(1920, 1080)
	add_child(port)
	var markers: GapMarkers = GapMarkers.new()
	port.add_child(markers)
	markers.bind(_grid)
	var camera := Camera3D.new()
	port.add_child(camera)
	camera.make_current()
	var at := _grid.origin + Vector3(6.0, 0.0, 2.5)
	var eye := at + Vector3(0.0, 14.0, 12.0)
	camera.global_transform = Transform3D.IDENTITY.translated(eye).looking_at(at)
	_remove(Vector2i(5, 2), BuildGrid.Side.EAST)
	var session: BuildSession = auto_free(BuildSession.new())
	markers.build_session = session
	assert_int(markers.sign_count()).is_equal(1)
	print("outside build mode: %d hover signs" % markers.hover_signs().size())
	assert_int(markers.hover_signs().size()).is_equal(0)
	assert_bool(markers.signs()[0].visible).is_true()
	session.active = true
	var signs := markers.hover_signs()
	print("in build mode: %s" % [signs])
	assert_int(signs.size()).is_equal(1)
	assert_str(signs[0]["text"]).is_equal(GapMarkers.HOVER_TEXT)
	var foot := camera.unproject_position(markers.signs()[0].global_position)
	var rect: Rect2 = signs[0]["rect"]
	assert_bool(rect.has_point(foot + Vector2(0.0, -rect.size.y / 2.0))).is_true()
	assert_float(rect.size.y).is_greater(0.0)


## A pinned gap tooltip belongs to its gap: when that gap closes, the pin ends
## instead of moving to the other gap that took its place in the list.
func test_a_pinned_gap_clears_when_it_closes_instead_of_moving() -> void:
	var port: SubViewport = auto_free(SubViewport.new())
	port.size = Vector2i(1920, 1080)
	add_child(port)
	var markers: GapMarkers = GapMarkers.new()
	port.add_child(markers)
	markers.bind(_grid)
	var camera := Camera3D.new()
	port.add_child(camera)
	camera.make_current()
	var at := _grid.origin + Vector3(3.5, 0.0, 3.5)
	camera.global_transform = Transform3D.IDENTITY.translated(at + Vector3(0.0, 16.0, 10.0))
	camera.look_at(at)
	var session: BuildSession = auto_free(BuildSession.new())
	session.active = true
	markers.build_session = session
	# Two gaps: the north-west corner's north edge (first run), and the east edge.
	_remove(Vector2i(2, 2), BuildGrid.Side.NORTH)
	_remove(Vector2i(5, 3), BuildGrid.Side.EAST)
	var hover: HoverTarget = auto_free(HoverTarget.new())
	port.add_child(hover)
	hover.register_provider(markers)
	var signs := markers.hover_signs()
	print("two gaps: %s" % [signs])
	assert_int(signs.size()).is_equal(2)
	assert_bool(signs[0]["key"] != signs[1]["key"]).is_true()
	# Pin the first gap with a click on its sign.
	var first_rect: Rect2 = signs[0]["rect"]
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = first_rect.get_center()
	hover._unhandled_input(click)
	hover.pointer_override = Vector2(-500.0, -500.0)
	hover.refresh()
	var pinned := hover.pinned_target()
	assert_object(pinned).is_not_null()
	assert_that(pinned.key).is_equal(signs[0]["key"])
	# Close the pinned gap: the other gap is now the only (first) sign.
	(
		assert_bool(_grid.apply(BuildEdit.place_wall(Vector2i(2, 2), BuildGrid.Side.NORTH)).ok)
		. is_true()
	)
	assert_int(markers.sign_count()).is_equal(1)
	hover.refresh()
	print("after closing: pinned %s, signs %s" % [hover.pinned_target(), markers.hover_signs()])
	assert_object(hover.pinned_target()).is_null()
