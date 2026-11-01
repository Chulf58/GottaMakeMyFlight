class_name TestRoofCutaway
extends GdUnitTestSuite
## The player-built roof's level rule (RoofCutaway): drawn when the camera is
## far, gone when it is near, holding its last target inside the band, and
## fading at a constant rate (user ruling toon-terminal-roof-shows-from-far-
## away-and-fades-out-when-th, the same rule as ShellCutaway's roof).

var _cut: RoofCutaway


func before_test() -> void:
	_cut = RoofCutaway.new()
	_cut.roof_hide_below = 100.0
	_cut.roof_show_above = 120.0
	_cut.roof_fade_seconds = 0.4


func test_snap_draws_the_roof_far_and_hides_it_near() -> void:
	_cut.snap(200.0)
	assert_float(_cut.roof_level).is_equal(0.0)
	assert_bool(_cut.is_drawn()).is_true()
	_cut.snap(40.0)
	assert_float(_cut.roof_level).is_equal(1.0)
	assert_bool(_cut.is_drawn()).is_false()


func test_snap_inside_the_band_draws_the_roof() -> void:
	_cut.snap(110.0)
	assert_float(_cut.roof_target).is_equal(0.0)
	assert_float(_cut.roof_level).is_equal(0.0)


func test_inside_the_band_the_target_holds_so_it_does_not_flicker() -> void:
	_cut.snap(40.0)
	_cut.step(110.0, 1.0)
	assert_float(_cut.roof_target).is_equal(1.0)
	assert_float(_cut.roof_level).is_equal(1.0)
	_cut.step(130.0, 1.0)
	assert_float(_cut.roof_target).is_equal(0.0)
	_cut.step(110.0, 1.0)
	assert_float(_cut.roof_target).is_equal(0.0)
	assert_float(_cut.roof_level).is_equal(0.0)


func test_the_level_fades_at_a_constant_rate_and_lands_on_the_target() -> void:
	_cut.snap(200.0)
	_cut.step(50.0, 0.1)
	assert_float(_cut.roof_level).is_equal_approx(0.25, 0.0001)
	assert_bool(_cut.is_drawn()).is_true()
	_cut.step(50.0, 0.1)
	assert_float(_cut.roof_level).is_equal_approx(0.5, 0.0001)
	_cut.step(50.0, 1.0)
	assert_float(_cut.roof_level).is_equal(1.0)
	assert_bool(_cut.is_drawn()).is_false()


func test_tuning_error_names_bad_values() -> void:
	assert_str(_cut.tuning_error()).is_empty()
	_cut.roof_fade_seconds = 0.0
	assert_str(_cut.tuning_error()).contains("fade")
	_cut.roof_fade_seconds = 0.4
	_cut.roof_hide_below = 130.0
	assert_str(_cut.tuning_error()).contains("roof_hide_below")
