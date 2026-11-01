class_name TestBuildableOutline
extends GdUnitTestSuite
## The buildable-land outline (user ruling buildable-land-shows-as-an-outline-
## only-in-build-mode-the-da): drawn while build mode lasts, hidden outside it,
## and running round the terminal site's buildable bounds (the site's
## BuildGrid, x -43..43 and z -100..-60, until land plots replace it).

const SITE := preload("res://build/terminal_site.tres")
const CAMERA := preload("res://camera/tycoon_camera.tscn")

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
	# 86 m sides in 43 pieces of 2 m and 40 m sides in 20, two triangles a piece.
	assert_int(faces.size()).is_equal((43 + 20) * 2 * 6)
	var w := BuildableOutline.MIN_WIDTH_M / 2.0
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


## Constant width on screen (user ruling buildable-outline-keeps-a-constant-on-
## screen-width-at-every-zoom), measured in screen pixels: the real TycoonCamera,
## with its zoom-following pitch, over the plot's middle at four zooms (80 m is
## the home view) and two yaws. At every piece end and piece middle of every side
## in view, the outer point and the point straight in from it project WIDTH_PX
## apart, give or take one pixel.
func test_width_measures_its_pixels_on_screen_under_the_tycoon_camera() -> void:
	var rig: TycoonCamera = CAMERA.instantiate()
	add_child(rig)
	var cam: Camera3D = rig.get_node("Camera3D")
	var view := Rect2(Vector2.ZERO, cam.get_viewport().get_visible_rect().size)
	var want := BuildableOutline.WIDTH_PX
	for zoom in [30.0, 80.0, 150.0, 300.0]:
		for yaw in [0.0, 0.7]:
			_pose(rig, Vector3(0.0, 0.0, -80.0), zoom, yaw)
			_outline.fit(cam)
			var sides_seen := 0
			var edges := _outline.side_edges()
			for s in edges.size():
				var px := _measured_pixels(cam, edges[s], view)
				if px.is_empty():
					continue
				sides_seen += 1
				var low: float = px.min()
				var high: float = px.max()
				(
					assert_bool(low >= want - 1.0 and high <= want + 1.0)
					. override_failure_message(
						(
							"zoom %s yaw %s side %d: %d points, %.2f..%.2f px, want %.0f +- 1"
							% [zoom, yaw, s, px.size(), low, high, want]
						)
					)
					. is_true()
				)
			# The whole plot is in view from the home zoom out.
			var all_in := 4 if zoom >= 80.0 else 1
			(
				assert_int(sides_seen)
				. override_failure_message(
					"zoom %s yaw %s: %d sides in view" % [zoom, yaw, sides_seen]
				)
				. is_greater_equal(all_in)
			)
	rig.free()
	_outline.redraw()


## A camera low over the south edge with that edge behind it: every width is
## finite and inside MIN_WIDTH_M to half the plot, and so is the mesh.
func test_a_corner_behind_the_camera_keeps_finite_clamped_widths() -> void:
	var rig: TycoonCamera = CAMERA.instantiate()
	add_child(rig)
	var cam: Camera3D = rig.get_node("Camera3D")
	_pose(rig, Vector3(0.0, 0.0, -68.0), 6.0, 0.0)
	var outer := _outline.outline_points()
	var behind := [2, 3].filter(func(i: int) -> bool: return cam.is_position_behind(outer[i]))
	assert_int(behind.size()).is_equal(2)
	_outline.fit(cam)
	var widest := 20.0
	for edge in _outline.side_edges():
		for k in range(0, edge.size(), 2):
			var width := edge[k].distance_to(edge[k + 1])
			(
				assert_bool(
					width >= BuildableOutline.MIN_WIDTH_M - 0.0001 and width <= widest + 0.0001
				)
				. override_failure_message("%s: width %s" % [edge[k], width])
				. is_true()
			)
	for p in _outline.inner_points():
		assert_bool(p.is_finite()).is_true()
	for p in _outline.strip_mesh().get_faces():
		assert_bool(p.is_finite()).is_true()
	rig.free()
	_outline.redraw()


## Places `rig` the way TycoonCamera's own controls would: focus, zoom and yaw,
## its pitch from its zoom curve.
func _pose(rig: TycoonCamera, focus: Vector3, zoom: float, yaw: float) -> void:
	rig.position = focus
	rig.distance = zoom
	rig.yaw = yaw
	rig.rotate_yaw(0.0)


## Screen pixels from each outer point to the point straight in from it, at every
## piece end and piece middle of one side's `edge` where both are in front of
## `cam` and inside `view`.
func _measured_pixels(cam: Camera3D, edge: PackedVector3Array, view: Rect2) -> Array[float]:
	var out: Array[float] = []
	for k in range(0, edge.size(), 2):
		var pairs := [[edge[k], edge[k + 1]]]
		if k + 2 < edge.size():
			pairs.append([(edge[k] + edge[k + 2]) / 2.0, (edge[k + 1] + edge[k + 3]) / 2.0])
		for pair in pairs:
			if cam.is_position_behind(pair[0]) or cam.is_position_behind(pair[1]):
				continue
			var a := cam.unproject_position(pair[0])
			var b := cam.unproject_position(pair[1])
			if view.has_point(a) and view.has_point(b):
				out.append(a.distance_to(b))
	return out


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
