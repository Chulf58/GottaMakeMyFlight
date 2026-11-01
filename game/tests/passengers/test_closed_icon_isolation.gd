class_name TestClosedIconIsolation
extends GdUnitTestSuite
## Drawing the grey Closed sign leaves the shared queue-full icon red.

## The Closed icon cached by an earlier suite, put back after each case.
var _cached_closed: ImageTexture


func before_test() -> void:
	_cached_closed = MissMarkers._closed_texture
	MissMarkers._closed_texture = null


func after_test() -> void:
	MissMarkers._closed_texture = _cached_closed


func test_building_the_closed_icon_leaves_the_queue_full_texture_red() -> void:
	var at := Vector2i(MarkerIcons.SIZE / 2 - 26, MarkerIcons.SIZE / 2 - 4)
	var before_pixel := MarkerIcons.queue_full().get_image().get_pixelv(at)
	assert_float(before_pixel.b).is_less(0.4)
	var closed := MissMarkers._closed_icon()
	# The Closed icon is grey at that pixel: it was repainted from a copy.
	assert_float(closed.get_image().get_pixelv(at).b).is_greater(0.5)
	var after_pixel := MarkerIcons.queue_full().get_image().get_pixelv(at)
	assert_float(after_pixel.r).is_equal_approx(MarkerIcons.QUEUE_FILL.r, 0.05)
	assert_float(after_pixel.b).is_equal_approx(MarkerIcons.QUEUE_FILL.b, 0.05)
