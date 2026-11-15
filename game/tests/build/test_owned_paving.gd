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
			if plot == Vector2i(0, 0) or plot == Vector2i(3, 5):
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
	assert_int(OwnedPaving.plot_meshes(_site).size() - _shown().size()).is_equal(18)
	assert_bool((_site.find_child("Road", true, false) as Node3D).visible).is_true()


func test_buying_a_plot_paves_it_at_once() -> void:
	_land.own_start(SITE)
	_paving.bind(_site, _land)
	var before := _shown().size()
	# One plot north of the start land and one east of it.
	for plot: Vector2i in [Vector2i(0, 2), Vector2i(2, 4)]:
		assert_bool(_land.buyable_plots().has(plot)).is_true()
		assert_bool(_shown().has(plot)).is_false()
		var result := _land.buy(plot, null)
		assert_bool(result.ok).is_true()
		assert_bool(_shown().has(plot)).is_true()
	print("shown before %d after %d: %s" % [before, _shown().size(), _shown()])
	assert_int(_shown().size()).is_equal(before + 2)
	assert_array(_shown()).is_equal(_owned())


func test_a_load_repaves_from_the_saved_ownership() -> void:
	_land.own_start(SITE)
	_paving.bind(_site, _land)
	var saved := LandPlots.for_site(SITE)
	saved.own_start(SITE)
	LandKit.buy_to(saved, Vector2i(3, 0))
	var data := saved.to_snapshot()
	assert_bool(_land.from_snapshot(JSON.parse_string(JSON.stringify(data)))).is_true()
	var want: Array[Vector2i] = []
	want.assign(saved.owned_plots())
	want.sort()
	print("loaded owned %s shown %s" % [want, _shown()])
	assert_int(want.size()).is_greater(6)
	assert_array(_shown()).is_equal(want)
