class_name TestPanelRoom
extends GdUnitTestSuite
## PanelRoom.free_rect: the largest screen rectangle the open panels leave.

const SCREEN := Rect2(0.0, 0.0, 1920.0, 1080.0)
## A tray stack across the bottom centre and a card down the right edge.
const TRAY := Rect2(640.0, 620.0, 640.0, 460.0)
const SIDE_CARD := Rect2(1460.0, 258.0, 440.0, 160.0)


func _free(panels: Array[Rect2]) -> Rect2:
	return PanelRoom.free_rect(SCREEN, panels)


func test_no_panel_leaves_the_whole_screen() -> void:
	assert_that(_free([])).is_equal(SCREEN)


func test_a_tray_at_the_bottom_leaves_what_is_above_it() -> void:
	assert_that(_free([TRAY])).is_equal(Rect2(0.0, 0.0, 1920.0, 620.0))


func test_a_card_at_the_right_leaves_what_is_left_of_it() -> void:
	assert_that(_free([SIDE_CARD])).is_equal(Rect2(0.0, 0.0, 1460.0, 1080.0))


func test_a_tray_and_a_card_leave_the_corner_clear_of_both() -> void:
	assert_that(_free([TRAY, SIDE_CARD])).is_equal(Rect2(0.0, 0.0, 1460.0, 620.0))


func test_a_panel_the_free_share_does_not_touch_changes_nothing() -> void:
	var over := Rect2(0.0, 0.0, 1920.0, 620.0)
	var floor_card := Rect2(100.0, 700.0, 300.0, 200.0)
	assert_that(PanelRoom.free_rect(over, [floor_card])).is_equal(over)


func test_a_cut_that_leaves_too_little_is_skipped() -> void:
	# A card over most of the screen: every side it could leave is thin.
	var huge := Rect2(100.0, 100.0, 1700.0, 900.0)
	assert_that(_free([huge])).is_equal(SCREEN)


func test_the_cut_that_keeps_more_area_wins() -> void:
	var tall := Rect2(1000.0, 0.0, 300.0, 1080.0)
	assert_that(_free([tall])).is_equal(Rect2(0.0, 0.0, 1000.0, 1080.0))
