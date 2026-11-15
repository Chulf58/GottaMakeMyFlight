extends GdUnitTestSuite
## The site's grey paving covers exactly the land plots the player owns and
## grows the moment a plot is bought (decision site-paving-covers-only-the-
## owned-land-plots-and-grows-as-ea). The site asset holds one paving mesh per
## land plot (Lot_<column>_<row>); OwnedPaving shows those the land owns, on a
## new game, after a buy and after a load.

const SITE := preload("res://build/terminal_site.tres")
const SITE_SCENE := preload("res://assets/buildings/tp_airport_site.glb")
## Where main.tscn places the site asset.
const SITE_AT := Vector3(0.0, 0.0, -80.0)

var _site: Node3D
var _land: LandPlots
var _paving: OwnedPaving


func before() -> void:
	_site = SITE_SCENE.instantiate()
	_site.position = SITE_AT
	add_child(_site)


func after() -> void:
	_site.free()


func before_test() -> void:
	_land = LandPlots.for_site(SITE)
	_paving = auto_free(OwnedPaving.new()) as OwnedPaving


## The plots whose paving mesh is shown.
func _shown() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var meshes := OwnedPaving.plot_meshes(_site)
	for plot: Vector2i in meshes:
		if (meshes[plot] as Node3D).visible:
			out.append(plot)
	out.sort()
	return out


func _owned() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(_land.owned_plots())
	out.sort()
	return out


func test_the_site_has_one_paving_mesh_per_plot_covering_exactly_that_plot() -> void:
	var meshes := OwnedPaving.plot_meshes(_site)
	print("plot meshes %d, plots %s" % [meshes.size(), _land.plots])
	assert_int(meshes.size()).is_equal(_land.plots.x * _land.plots.y)
	for y in _land.plots.y:
		for x in _land.plots.x:
			var plot := Vector2i(x, y)
			assert_bool(meshes.has(plot)).is_true()
			var mi := meshes[plot] as MeshInstance3D
			var box := mi.global_transform * mi.get_aabb()
			var cells := _land.plot_cells(plot)
			var want := Rect2(
				Vector2(SITE.grid_origin.x, SITE.grid_origin.z) + Vector2(cells.position),
				Vector2(cells.size)
			)
			var got := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
			if plot == Vector2i(0, 0) or plot == Vector2i(11, 5):
				print("plot %s paving %s want %s top %.3f" % [plot, got, want, box.end.y])
			assert_vector(got.position).is_equal_approx(want.position, Vector2.ONE * 0.01)
			assert_vector(got.end).is_equal_approx(want.end, Vector2.ONE * 0.01)
			# Its top is the site's paving height.
			assert_float(box.end.y).is_equal_approx(SITE.ground_height, 0.001)
	# The road is its own mesh, not a plot's.
	assert_object(_site.find_child("Road", true, false)).is_not_null()


func test_a_new_game_paves_only_its_owned_plots() -> void:
	_land.own_start(SITE)
	_paving.bind(_site, _land)
	print("owned %s shown %s" % [_owned(), _shown()])
	assert_int(_owned().size()).is_equal(6)
	assert_array(_shown()).is_equal(_owned())
	# Control: the rest of the plots are there and hidden.
	assert_int(OwnedPaving.plot_meshes(_site).size() - _shown().size()).is_equal(66)
	assert_bool((_site.find_child("Road", true, false) as Node3D).visible).is_true()


func test_buying_a_plot_paves_it_at_once() -> void:
	_land.own_start(SITE)
	_paving.bind(_site, _land)
	var before := _shown().size()
	# Two plots north of the start land and one east of it.
	for plot: Vector2i in [Vector2i(4, 2), Vector2i(6, 4), Vector2i(5, 2)]:
		assert_bool(_land.buyable_plots().has(plot)).is_true()
		assert_bool(_shown().has(plot)).is_false()
		var result := _land.buy(plot, null)
		assert_bool(result.ok).is_true()
		assert_bool(_shown().has(plot)).is_true()
	print("shown before %d after %d: %s" % [before, _shown().size(), _shown()])
	assert_int(_shown().size()).is_equal(before + 3)
	assert_array(_shown()).is_equal(_owned())


func test_a_load_repaves_from_the_saved_ownership() -> void:
	_land.own_start(SITE)
	_paving.bind(_site, _land)
	var saved := LandPlots.for_site(SITE)
	saved.own_start(SITE)
	LandKit.buy_to(saved, Vector2i(7, 0))
	var data := saved.to_snapshot()
	assert_bool(_land.from_snapshot(JSON.parse_string(JSON.stringify(data)))).is_true()
	var want: Array[Vector2i] = []
	want.assign(saved.owned_plots())
	want.sort()
	print("loaded owned %s shown %s" % [want, _shown()])
	assert_int(want.size()).is_greater(6)
	assert_array(_shown()).is_equal(want)


## Whether the kerb on `side` (0 N, 1 E, 2 S, 3 W) of `plot` is shown.
func _kerb_shown(plot: Vector2i, side: int) -> bool:
	var kerbs := OwnedPaving.kerb_meshes(_site)
	return (kerbs[Vector3i(plot.x, plot.y, side)] as Node3D).visible


func test_every_inner_plot_side_has_a_kerb_on_its_edge() -> void:
	var kerbs := OwnedPaving.kerb_meshes(_site)
	var origin := Vector2(SITE.grid_origin.x, SITE.grid_origin.z)
	var inner := 0
	for y in _land.plots.y:
		for x in _land.plots.x:
			for side in 4:
				var plot := Vector2i(x, y)
				if not _land.in_site(plot + LandPlots.EDGE_STEPS[side]):
					continue
				inner += 1
				var key := Vector3i(x, y, side)
				assert_bool(kerbs.has(key)).is_true()
				var mi := kerbs[key] as MeshInstance3D
				var box := mi.global_transform * mi.get_aabb()
				var cells := _land.plot_cells(plot)
				var lo := origin + Vector2(cells.position)
				var hi := origin + Vector2(cells.end)
				# On its side's edge, from the paving's top down under the grass.
				var edge_at: float = [lo.y, hi.x, hi.y, lo.x][side]
				var along: float = box.position.z if side % 2 == 0 else box.position.x
				assert_float(along).is_equal_approx(edge_at, 0.01)
				assert_float(box.end.y).is_equal_approx(SITE.ground_height, 0.001)
				assert_float(box.position.y).is_less(TaxiPavingSite.GRASS_Y)
	print("kerb meshes %d, inner plot sides %d" % [kerbs.size(), inner])
	assert_int(inner).is_equal(252)
	assert_int(kerbs.size()).is_equal(inner)


func test_touching_owned_plots_show_no_kerb_between_them_and_the_grass_edge_does() -> void:
	_land.own_start(SITE)
	_paving.bind(_site, _land)
	# (4, 4) and (5, 4) are both owned: no kerb on either side of their edge.
	assert_bool(_kerb_shown(Vector2i(4, 4), 1)).is_false()
	assert_bool(_kerb_shown(Vector2i(5, 4), 3)).is_false()
	# (5, 4) owned, (6, 4) not: the kerb shows on the owned side only.
	assert_bool(_kerb_shown(Vector2i(5, 4), 1)).is_true()
	assert_bool(_kerb_shown(Vector2i(6, 4), 3)).is_false()
	# Every kerb shows exactly where its plot is owned and the plot across is not.
	var kerbs := OwnedPaving.kerb_meshes(_site)
	var shown := 0
	for key: Vector3i in kerbs:
		var plot := Vector2i(key.x, key.y)
		var want := _land.is_owned(plot) and not _land.is_owned(plot + LandPlots.EDGE_STEPS[key.z])
		assert_bool((kerbs[key] as Node3D).visible).is_equal(want)
		shown += 1 if want else 0
	print("kerbs shown on a new game %d of %d" % [shown, kerbs.size()])
	# The start land's edges toward other plots: 3 plot sides east, 3 west (side land), 2 north.
	assert_int(shown).is_equal(8)
	# Buying (6, 4) joins it without a kerb and puts kerbs on its own open sides.
	assert_bool(_land.buy(Vector2i(6, 4), null).ok).is_true()
	assert_bool(_kerb_shown(Vector2i(5, 4), 1)).is_false()
	assert_bool(_kerb_shown(Vector2i(6, 4), 3)).is_false()
	assert_bool(_kerb_shown(Vector2i(6, 4), 1)).is_true()
	assert_bool(_kerb_shown(Vector2i(6, 4), 0)).is_true()
