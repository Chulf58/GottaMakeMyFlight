class_name TestBuildableOutline
extends GdUnitTestSuite
## The buildable-land outline (user ruling buildable-land-shows-as-an-outline-
## only-in-build-mode-the-da): drawn while build mode lasts, hidden outside it,
## and running round the terminal site's buildable bounds (the site's
## BuildGrid, x -43..43 and z -100..-60, until land plots replace it).

const SITE := preload("res://build/terminal_site.tres")

var _mode: BuildMode
var _menu: BuildMenu
var _outline: BuildableOutline


func before() -> void:
	_mode = BuildMode.new()
	_mode.initial_tool = BuildMode.Tool.NONE
	_mode.site = SITE
	add_child(_mode)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	add_child(_menu)
	_outline = BuildableOutline.new()
	_outline.build_mode = _mode
	_outline.menu = _menu
	add_child(_outline)


func after() -> void:
	for node in [_outline, _menu, _mode]:
		node.free()


## Every test starts and ends outside build mode.
func after_test() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	if _menu.is_tray_open():
		_menu.press_category(_menu.open_category())


func test_hidden_with_no_tray_open() -> void:
	assert_bool(_menu.is_tray_open()).is_false()
	assert_bool(_menu.build_session.active).is_false()
	assert_bool(_outline.visible).is_false()


func test_visible_while_a_tray_is_open_and_hidden_once_it_closes() -> void:
	_menu.press_category(0)
	assert_bool(_menu.is_tray_open()).is_true()
	assert_bool(_outline.visible).is_true()
	_menu.press_category(0)
	assert_bool(_menu.is_tray_open()).is_false()
	assert_bool(_outline.visible).is_false()


func test_switching_trays_keeps_it_shown() -> void:
	_menu.press_category(0)
	_menu.press_category(1)
	assert_int(_menu.open_category()).is_equal(1)
	assert_bool(_outline.visible).is_true()


func test_the_rectangle_is_the_site_grid() -> void:
	var rects := _outline.rects()
	assert_int(rects.size()).is_equal(1)
	assert_that(rects[0]).is_equal(Rect2(-43.0, -100.0, 86.0, 40.0))
	assert_that(rects[0]).is_equal(BuildableOutline.buildable_rects(_mode.grid)[0])


func test_points_are_the_buildable_corners() -> void:
	var y := SITE.grid_origin.y + BuildableOutline.LIFT_M
	var want := PackedVector3Array(
		[
			Vector3(-43.0, y, -100.0),
			Vector3(43.0, y, -100.0),
			Vector3(43.0, y, -60.0),
			Vector3(-43.0, y, -60.0),
		]
	)
	var got := _outline.outline_points()
	assert_int(got.size()).is_equal(want.size())
	for i in want.size():
		(
			assert_bool(got[i].is_equal_approx(want[i]))
			. override_failure_message("corner %d: got %s, want %s" % [i, got[i], want[i]])
			. is_true()
		)


## The strips run all round inside the edge: the mesh spans the rectangle
## exactly and covers each side's middle, and its centre is left open.
func test_the_strips_run_all_round_inside_the_edge() -> void:
	var box := _outline.strip_mesh().get_aabb()
	assert_bool(box.position.is_equal_approx(Vector3(-43.0, box.position.y, -100.0))).is_true()
	assert_bool(box.end.is_equal_approx(Vector3(43.0, box.end.y, -60.0))).is_true()
	var faces := _outline.strip_mesh().get_faces()
	assert_int(faces.size()).is_equal(4 * 6)
	var w := BuildableOutline.WIDTH_M / 2.0
	for probe in [
		Vector2(0.0, -100.0 + w),
		Vector2(0.0, -60.0 - w),
		Vector2(-43.0 + w, -80.0),
		Vector2(43.0 - w, -80.0),
	]:
		(
			assert_bool(_covered(faces, probe))
			. override_failure_message("%s uncovered" % probe)
			. is_true()
		)
	assert_bool(_covered(faces, Vector2(0.0, -80.0))).is_false()


func _covered(faces: PackedVector3Array, at: Vector2) -> bool:
	for i in range(0, faces.size(), 3):
		var tri := PackedVector2Array(
			[
				Vector2(faces[i].x, faces[i].z),
				Vector2(faces[i + 1].x, faces[i + 1].z),
				Vector2(faces[i + 2].x, faces[i + 2].z),
			]
		)
		if Geometry2D.is_point_in_polygon(at, tri):
			return true
	return false
