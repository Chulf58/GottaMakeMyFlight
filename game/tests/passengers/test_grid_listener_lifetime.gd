class_name TestGridListenerLifetime
extends GdUnitTestSuite
## A RefCounted helper that follows a BuildGrid's signals while holding the
## grid (ScreenCoverage, PrizeCar, DecorEffect) must not keep itself or the
## grid alive. A lambda that reads a member captures the helper strongly, so a
## lambda connected to the grid's signal and the helper's own _grid formed a
## cycle that neither freed: main.tscn left both at exit (board item 7c3e3427).
## Each test binds a helper, checks the binding took (a connection appeared),
## drops every reference and checks both the helper and the grid are gone.

const SIZE := Vector2i(8, 8)


func test_screen_coverage_frees_with_its_grid() -> void:
	_assert_both_free(_bind_and_drop(&"screen"))


func test_prize_car_frees_with_its_grid() -> void:
	_assert_both_free(_bind_and_drop(&"prize"))


func test_decor_effect_frees_with_its_grid() -> void:
	_assert_both_free(_bind_and_drop(&"decor"))


## Binds a fresh helper of `kind` to a fresh grid, then drops the helper while
## the grid is still held, and returns what was seen. The grid's last
## reference goes when this function returns, so the caller can check it freed.
func _bind_and_drop(kind: StringName) -> Dictionary:
	var grid := BuildGrid.new(SIZE)
	var before := grid.graph_changed.get_connections().size()
	var helper: RefCounted
	match kind:
		&"screen":
			var coverage := ScreenCoverage.new()
			coverage.bind(grid)
			helper = coverage
		&"prize":
			var prize := PrizeCar.new()
			prize.bind(grid)
			helper = prize
		&"decor":
			var sim := PassengerSim.new()
			sim.grid = grid
			var decor := DecorEffect.new()
			decor.bind(sim)
			sim.grid = null
			sim.free()
			helper = decor
	var bound := grid.graph_changed.get_connections().size()
	var helper_ref: WeakRef = weakref(helper)
	helper = null
	return {
		"before": before,
		"bound": bound,
		"helper_gone": helper_ref.get_ref() == null,
		"left": grid.graph_changed.get_connections().size(),
		"grid": weakref(grid),
	}


func _assert_both_free(seen: Dictionary) -> void:
	var grid_gone: bool = (seen["grid"] as WeakRef).get_ref() == null
	print(
		(
			"connections before bind %d, after %d, left %d; helper freed %s, grid freed %s"
			% [seen["before"], seen["bound"], seen["left"], seen["helper_gone"], grid_gone]
		)
	)
	assert_int(seen["bound"]).is_equal(seen["before"] + 1)
	assert_bool(seen["helper_gone"]).is_true()
	assert_int(seen["left"]).is_equal(seen["before"])
	assert_bool(grid_gone).is_true()
