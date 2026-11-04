class_name TestRectBins
extends GdUnitTestSuite
## The screen-rectangle broad phase (RectBins) does bounded work for a rectangle
## of any size. A speech bubble just in front of the camera plane is measured at
## pixel_size / depth, so it can be millions of pixels wide; filing it under
## every 160 px cell it covered took the game to 22.8 GB and froze it (board
## "The game now froze", playtest 2026-11-03). A rectangle wider than MAX_CELLS
## cells is filed once and compared with every rectangle instead.

const SMALL := Vector2(100.0, 30.0)


## About what a bubble 2 mm in front of the camera measures: 400 by 400 cells.
func _wide() -> Rect2:
	return Rect2(Vector2(-32000.0, -32000.0), Vector2(64000.0, 64000.0))


func test_a_small_rect_is_filed_under_the_cells_it_covers() -> void:
	var bins := {}
	RectBins.file(bins, Rect2(Vector2(150.0, 10.0), SMALL), 0)
	assert_array(bins.keys()).contains_exactly_in_any_order([Vector2i(0, 0), Vector2i(1, 0)])


func test_a_wide_rect_is_filed_in_bounded_work() -> void:
	var bins := {}
	RectBins.file(bins, _wide(), 0)
	# Filed once, not under each of its 160 000 cells.
	assert_int(bins.size()).is_equal(1)


func test_a_bubble_a_micrometre_from_the_camera_is_filed_once() -> void:
	var bubble := BubbleDeclutter.rect_of(Vector2.ZERO, BubbleDeclutter.LATE_TEXT, 56, 14, 1.0e7)
	var bins := {}
	var rects: Array[Rect2] = [bubble]
	RectBins.file(bins, bubble, 0)
	assert_int(bins.size()).is_equal(1)
	assert_bool(RectBins.hits(Rect2(Vector2.ZERO, SMALL), bins, rects)).is_true()
	assert_array(RectBins.cells(bubble)).is_empty()


func test_a_rect_that_is_not_finite_is_wide() -> void:
	var rect := Rect2(Vector2(-INF, 0.0), Vector2(INF, 10.0))
	var bins := {}
	RectBins.file(bins, rect, 0)
	assert_array(bins.keys()).is_equal([RectBins.WIDE])
	assert_bool(RectBins.is_wide(Rect2(Vector2(1.0e12, 0.0), SMALL))).is_true()
	assert_bool(RectBins.is_wide(Rect2(Vector2.ZERO, SMALL))).is_false()


func test_a_wide_rect_filed_first_hits_a_small_one_it_covers() -> void:
	var bins := {}
	var rects: Array[Rect2] = [_wide()]
	RectBins.file(bins, rects[0], 0)
	assert_bool(RectBins.hits(Rect2(Vector2(5000.0, 7000.0), SMALL), bins, rects)).is_true()
	assert_bool(RectBins.hits(Rect2(Vector2(40000.0, 0.0), SMALL), bins, rects)).is_false()


func test_a_small_rect_filed_first_is_hit_by_a_wide_one() -> void:
	var bins := {}
	var rects: Array[Rect2] = [Rect2(Vector2(5000.0, 7000.0), SMALL)]
	RectBins.file(bins, rects[0], 0)
	assert_bool(RectBins.hits(_wide(), bins, rects)).is_true()
	var far: Array[Rect2] = [Rect2(Vector2(40000.0, 0.0), SMALL)]
	var far_bins := {}
	RectBins.file(far_bins, far[0], 0)
	assert_bool(RectBins.hits(_wide(), far_bins, far)).is_false()


func test_a_wide_bubble_still_hides_the_bubbles_it_overlaps() -> void:
	var entries: Array[Dictionary] = [
		BubbleDeclutter.entry(1, BubbleDeclutter.LATE_TEXT, 0, _wide()),
		BubbleDeclutter.entry(2, "Queue full", 1, Rect2(Vector2(10.0, 10.0), SMALL)),
		BubbleDeclutter.entry(3, "Queue full", 2, Rect2(Vector2(40000.0, 0.0), SMALL)),
	]
	assert_array(BubbleDeclutter.hidden(entries)).is_equal([2])
