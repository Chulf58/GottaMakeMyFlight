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


## The sign is MissMarkers.SIGN_PX (56 px) on screen, worked out as the
## MissMarkers test does: pixel size times the icon's pixels, over the view's
## size at one metre, at the window's rendered height.
func test_the_sign_is_56_px_on_screen() -> void:
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
	assert_float(on_screen).is_equal_approx(MissMarkers.SIGN_PX, 0.01)
	var caption := _markers.caption_of(marker)
	assert_float(caption.pixel_size * MarkerIcons.SIZE).is_equal_approx(
		marker.pixel_size * MarkerIcons.SIZE * MarkerIcons.SIZE / MissMarkers.SIGN_PX, 1e-6
	)


## The wall-gap sign is its own icon, not the queue-full "!", with the caption
## "Wall gap" under it (user ruling player-built-terminal-roof-tall-5-2-m-
## roof-with-the-facade-f, point 3), drawn over walls and roof.
func test_the_sign_is_the_wall_gap_icon_with_its_caption_under_it() -> void:
	_remove(Vector2i(5, 2), BuildGrid.Side.EAST)
	var marker: Sprite3D = _markers.signs()[0]
	assert_object(marker.texture).is_same(GapMarkers.wall_gap_icon())
	assert_object(marker.texture).is_not_same(MarkerIcons.queue_full())
	assert_bool(marker.no_depth_test).is_true()
	var caption := _markers.caption_of(marker)
	assert_str(caption.text).is_equal("Wall gap")
	assert_bool(caption.no_depth_test).is_true()
	assert_int(caption.vertical_alignment).is_equal(VERTICAL_ALIGNMENT_TOP)
	assert_float(caption.offset.y).is_less(0.0)
	# On the left half of the wall line the gap icon is white and the
	# queue-full icon is its red fill. The queue-full icon is read as painted
	# (queue_full_image): under the headless renderer the texture's own image
	# can have been repainted by MissMarkers' Closed sign in an earlier suite.
	var at := Vector2i(MarkerIcons.SIZE / 2 - 26, MarkerIcons.SIZE / 2 - 4)
	var gap_pixel := GapMarkers.wall_gap_icon().get_image().get_pixelv(at)
	var queue_pixel := MarkerIcons.queue_full_image().get_pixelv(at)
	assert_float(gap_pixel.b).is_greater(0.9)
	assert_float(queue_pixel.b).is_less(0.4)
	assert_bool(gap_pixel.is_equal_approx(queue_pixel)).is_false()


## MarkerIcons.queue_full_image() is a fresh copy each time: repainting one
## (as MissMarkers repaints the image it reads for its Closed sign) leaves the
## next one red.
func test_the_queue_full_image_is_a_fresh_copy() -> void:
	var at := Vector2i(MarkerIcons.SIZE / 2 - 26, MarkerIcons.SIZE / 2 - 4)
	var first := MarkerIcons.queue_full_image()
	assert_float(first.get_pixelv(at).b).is_less(0.4)
	first.set_pixelv(at, Color.WHITE)
	var second := MarkerIcons.queue_full_image()
	assert_float(second.get_pixelv(at).b).is_less(0.4)
	assert_object(second).is_not_same(first)
