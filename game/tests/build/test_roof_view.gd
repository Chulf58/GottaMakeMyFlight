class_name TestRoofView
extends GdUnitTestSuite
## The generated roof (RoofView): one batched mesh over the indoor cells only,
## rebuilt when the grid's graph changes, and its fade drawn from RoofCutaway.
## The subject is a closed 4x3 box of floor at x 2-5, y 2-4 on a 12x10 grid
## whose origin sits off the world origin.

const BOX := Rect2i(2, 2, 4, 3)
const ORIGIN := Vector3(-43.0, 0.22, -100.0)

var _grid: BuildGrid
var _view: RoofView


func before_test() -> void:
	_grid = BuildGrid.new(Vector2i(12, 10), ORIGIN)
	var edits: Array[BuildEdit] = []
	for y in range(BOX.position.y, BOX.end.y):
		for x in range(BOX.position.x, BOX.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for result in _grid.apply_batch(edits):
		assert_bool(result.ok).is_true()
	EnclosureKit.close_floor(_grid)
	_view = auto_free(RoofView.new())
	add_child(_view)
	_view.bind(_grid)


func test_a_closed_box_gets_one_roof_mesh_over_its_cells() -> void:
	assert_int(_view.roofed_cell_count()).is_equal(12)
	assert_int(_view.find_children("*", "MeshInstance3D", true, false).size()).is_equal(1)
	assert_bool(_view.roof_node().visible).is_true()
	var box := _view.roof_box()
	var o := _view.overhang
	assert_float(box.position.x).is_equal_approx(ORIGIN.x + 2.0 - o, 0.001)
	assert_float(box.end.x).is_equal_approx(ORIGIN.x + 6.0 + o, 0.001)
	assert_float(box.position.z).is_equal_approx(ORIGIN.z + 2.0 - o, 0.001)
	assert_float(box.end.z).is_equal_approx(ORIGIN.z + 5.0 + o, 0.001)
	assert_float(box.end.y).is_equal_approx(ORIGIN.y + _view.roof_height, 0.001)
	assert_float(box.position.y).is_equal_approx(
		ORIGIN.y + _view.roof_height - _view.fascia_depth, 0.001
	)


func test_an_open_wall_takes_the_roof_away_and_closing_it_brings_it_back() -> void:
	var east := BuildGrid.Side.EAST
	assert_bool(_grid.apply(BuildEdit.remove_wall(Vector2i(5, 3), east)).ok).is_true()
	assert_int(_view.roofed_cell_count()).is_equal(0)
	assert_bool(_view.roof_node().visible).is_false()
	assert_bool(_grid.apply(BuildEdit.place_wall(Vector2i(5, 3), east)).ok).is_true()
	assert_int(_view.roofed_cell_count()).is_equal(12)
	assert_bool(_view.roof_node().visible).is_true()


func test_roof_height_moves_the_top() -> void:
	_view.roof_height = 5.2
	_view.fascia_depth = 2.9
	_view.rebuild()
	assert_float(_view.roof_box().end.y).is_equal_approx(ORIGIN.y + 5.2, 0.001)
	assert_float(_view.roof_box().position.y).is_equal_approx(ORIGIN.y + 2.3, 0.001)


## An L of floor: the overhang strips meet at the inner corner without
## overlapping, so the top's area is the cells plus the overhang ring.
func test_an_l_shape_top_area_counts_the_inner_corner_once() -> void:
	var grid := BuildGrid.new(Vector2i(8, 8))
	var edits: Array[BuildEdit] = []
	for cell in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)]:
		edits.append(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(edits)
	EnclosureKit.close_floor(grid)
	_view.bind(grid)
	assert_int(_view.roofed_cell_count()).is_equal(3)
	var o := _view.overhang
	# Three cells, the outline is 8 m long with 5 outer and 1 inner corner:
	# 3 + 8 * o + 5 * o * o - 1 * o * o.
	assert_float(_view.top_area()).is_equal_approx(3.0 + 8.0 * o + 4.0 * o * o, 0.0001)


func test_the_fade_reaches_the_material_and_hides_the_roof_when_gone() -> void:
	_view.draw_level(0.5)
	assert_float(_view.surface_material().get_shader_parameter("dissolve")).is_equal(0.5)
	assert_int(_view.roof_node().cast_shadow).is_equal(
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	assert_bool(_view.roof_node().visible).is_true()
	_view.draw_level(1.0)
	assert_bool(_view.roof_node().visible).is_false()
	_view.draw_level(0.0)
	assert_bool(_view.roof_node().visible).is_true()
	assert_int(_view.roof_node().cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
