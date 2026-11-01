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
	assert_bool(_grid.apply(BuildEdit.place_wall(Vector2i(5, 2), BuildGrid.Side.EAST)).ok).is_true()
	assert_int(_markers.strip_count()).is_equal(0)
	assert_int(_markers.sign_count()).is_equal(0)


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
	# queue-full icon is its red fill.
	var at := Vector2i(MarkerIcons.SIZE / 2 - 26, MarkerIcons.SIZE / 2 - 4)
	var gap_pixel := GapMarkers.wall_gap_icon().get_image().get_pixelv(at)
	var queue_pixel := MarkerIcons.queue_full().get_image().get_pixelv(at)
	assert_float(gap_pixel.b).is_greater(0.9)
	assert_float(queue_pixel.b).is_less(0.4)
	assert_bool(gap_pixel.is_equal_approx(queue_pixel)).is_false()
