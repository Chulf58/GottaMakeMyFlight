class_name TestPlateSightEmptyBottom
extends GdUnitTestSuite
## PlateSight.empty_bottom: a plate whose bottom rows are the world's clear
## colour (the camera stood outside the building's floor) is refused.

const PlateSight := preload("res://spike/plate_sight.gd")
const W := 60
const H := 90
const FLOOR := Color(0.45, 0.4, 0.35)


func _plate(white_rows: int, sample_dark_cols := W) -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(FLOOR)
	for y in range(H - white_rows, H):
		for x in W:
			img.set_pixel(x, y, Color.WHITE)
	# Dark pixels in the bottom row keep it from counting as empty when asked.
	if white_rows > 0 and sample_dark_cols < W:
		for x in range(sample_dark_cols, W):
			img.set_pixel(x, H - 1, FLOOR)
	return img


func test_white_bottom_third_is_refused() -> void:
	var r := PlateSight.empty_bottom(_plate(H / 3))
	assert_int(r["run"]).is_equal(30)
	assert_int(r["rows"]).is_equal(H)
	assert_float(r["share"]).is_equal_approx(1.0 / 3.0, 0.001)
	assert_bool(r["ok"]).is_false()


func test_normal_floor_is_accepted() -> void:
	var r := PlateSight.empty_bottom(_plate(0))
	assert_int(r["run"]).is_equal(0)
	assert_bool(r["ok"]).is_true()


func test_a_thin_white_strip_under_the_limit_is_accepted() -> void:
	var r := PlateSight.empty_bottom(_plate(5))
	assert_int(r["run"]).is_equal(5)
	assert_bool(r["ok"]).is_true()


func test_white_above_a_floor_row_is_not_a_bottom_run() -> void:
	var img := _plate(0)
	for y in range(0, 40):
		for x in W:
			img.set_pixel(x, y, Color.WHITE)
	var r := PlateSight.empty_bottom(img)
	assert_int(r["run"]).is_equal(0)
	assert_bool(r["ok"]).is_true()


func test_a_row_mostly_white_but_not_pure_does_not_count() -> void:
	# Half the bottom row is floor, so the run stops at that row.
	var r := PlateSight.empty_bottom(_plate(30, W / 2))
	assert_int(r["run"]).is_equal(0)


func test_off_white_sky_is_not_pure_white() -> void:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.9, 0.92, 0.95))
	var r := PlateSight.empty_bottom(img)
	assert_int(r["run"]).is_equal(0)


func test_an_all_white_plate_is_refused() -> void:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var r := PlateSight.empty_bottom(img)
	assert_int(r["run"]).is_equal(H)
	assert_bool(r["ok"]).is_false()
