class_name TestBuildableOutline
extends GdUnitTestSuite
## The buildable-land outline (user ruling buildable-land-shows-as-an-outline-
## only-in-build-mode-the-da): drawn while build mode lasts, hidden outside it,
## and running round the land the player owns. These cases own every land plot
## (LandKit.own_all()), so the outline is the site's whole BuildGrid, 86 x 150 m
## from z -210, and the width checks keep the large rectangle they were
## measured on; test_build_mode_buy_land.gd covers the outline of a partly owned site.

const SITE := preload("res://build/terminal_site.tres")
const CAMERA := preload("res://camera/tycoon_camera.tscn")
## The fewest sides in view, added over all poses, that one angle step may show.
const MIN_SIDES_PER_STEP := 20

var _mode: BuildMode
var _menu: BuildMenu
var _outline: BuildableOutline


func before() -> void:
	_mode = BuildMode.new()
	_mode.initial_tool = BuildMode.Tool.NONE
	_mode.site = SITE
	add_child(_mode)
	LandKit.own_all(_mode.land_tool.land)
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


## The site's grid as a rectangle on the ground (x, z).
func _plot() -> Rect2:
	return Rect2(SITE.grid_origin.x, SITE.grid_origin.z, SITE.grid_size.x, SITE.grid_size.y)


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


func test_the_loop_is_the_site_grid_when_every_plot_is_owned() -> void:
	var loops := _outline.loops()
	var plot := _plot()
	assert_int(loops.size()).is_equal(1)
	assert_that(loops[0]).is_equal(
		PackedVector2Array(
			[
				plot.position,
				Vector2(plot.end.x, plot.position.y),
				plot.end,
				Vector2(plot.position.x, plot.end.y)
			]
		)
	)
	assert_that(loops[0]).is_equal(BuildableOutline.buildable_loops(_mode.grid)[0])


func test_points_are_the_buildable_corners() -> void:
	var y := SITE.grid_origin.y + BuildableOutline.LIFT_M
	var plot := _plot()
	var want := PackedVector3Array(
		[
			Vector3(plot.position.x, y, plot.position.y),
			Vector3(plot.end.x, y, plot.position.y),
			Vector3(plot.end.x, y, plot.end.y),
			Vector3(plot.position.x, y, plot.end.y),
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
	var plot := _plot()
	var middle := plot.get_center()
	var box := _outline.strip_mesh().get_aabb()
	var low := Vector3(plot.position.x, box.position.y, plot.position.y)
	var high := Vector3(plot.end.x, box.end.y, plot.end.y)
	assert_bool(box.position.is_equal_approx(low)).is_true()
	assert_bool(box.end.is_equal_approx(high)).is_true()
	var faces := _outline.strip_mesh().get_faces()
	# Each side in pieces of 2 m (43 and 75 for the 86 m and 150 m sides, two of
	# each), two triangles a piece.
	var pieces := int(plot.size.x / 2.0) + int(plot.size.y / 2.0)
	assert_int(faces.size()).is_equal(pieces * 2 * 6)
	var w := BuildableOutline.MIN_WIDTH_M / 2.0
	for probe in [
		Vector2(middle.x, plot.position.y + w),
		Vector2(middle.x, plot.end.y - w),
		Vector2(plot.position.x + w, middle.y),
		Vector2(plot.end.x - w, middle.y),
	]:
		(
			assert_bool(_covered(faces, probe))
			. override_failure_message("%s uncovered" % probe)
			. is_true()
		)
	assert_bool(_covered(faces, middle)).is_false()


## Constant width on screen (user ruling buildable-outline-keeps-a-constant-on-
## screen-width-at-every-zoom), measured as the band's thickness across itself: the real
## TycoonCamera at each of its three angle steps (the tilt no longer follows the zoom), in a
## 1536x864 view (the game's base view). Over the plot's middle at four zooms (80 m is the home
## view) and two yaws, close over the north-west corner (the corner_nw plate) and low over the
## south edge looking at the far north edge (the edge_floor plate). At every piece end and piece
## middle of every side in view, the inner point lies WIDTH_PX from the outer edge's line on
## screen, give or take one pixel. The two close poses fail a width solved along the inward
## direction alone (7.7 and 4.3 px there). The width check holds at every angle step.
func test_width_measures_its_pixels_across_the_band_under_the_tycoon_camera() -> void:
	var rig := _make_rig()
	var cam: Camera3D = rig.get_node("Camera3D")
	var view := Rect2(Vector2.ZERO, cam.get_viewport().get_visible_rect().size)
	assert_that(view.size).is_equal(Vector2(1536.0, 864.0))
	# The close plates focus at the strips' height, as the plates probe does.
	var edge_y := SITE.grid_origin.y + BuildableOutline.LIFT_M
	var plot := _plot()
	var middle := plot.get_center()
	# [focus, zoom, yaw, sides wholly or partly in view at least, at the least
	# of the three angle steps]. The plot is 150 m deep, not 40, so the far side
	# is out of view from the south-edge pose and, over the middle, the north and
	# south sides leave the view at the lower zooms (at the top-down step the 30 m
	# poses see none): the counts are what the 86 x 150 m plot shows (measured),
	# and each step must see MIN_SIDES_PER_STEP in all so the width check is never
	# empty. The width check on every side seen is unchanged.
	var poses := [
		[Vector3(plot.position.x + 4.0, 0.0, plot.position.y + 3.0), 18.0, 0.0, 2],
		[Vector3(middle.x, edge_y, plot.end.y - 4.0), 18.0, 0.0, 1],
		[Vector3(middle.x, 0.0, middle.y), 30.0, 0.0, 0],
		[Vector3(middle.x, 0.0, middle.y), 30.0, 0.7, 0],
		[Vector3(middle.x, 0.0, middle.y), 80.0, 0.0, 2],
		[Vector3(middle.x, 0.0, middle.y), 80.0, 0.7, 3],
		[Vector3(middle.x, 0.0, middle.y), 150.0, 0.0, 3],
		[Vector3(middle.x, 0.0, middle.y), 150.0, 0.7, 4],
		[Vector3(middle.x, 0.0, middle.y), 300.0, 0.0, 4],
		[Vector3(middle.x, 0.0, middle.y), 300.0, 0.7, 4],
	]
	for step in [
		TycoonCamera.AngleStep.LOW, TycoonCamera.AngleStep.MEDIUM, TycoonCamera.AngleStep.TOP_DOWN
	]:
		rig.angle_step = step
		var total := 0
		for pose in poses:
			var seen := _check_widths_at(rig, cam, view, pose)
			total += seen
			(
				assert_int(seen)
				. override_failure_message(
					"angle %d pose %s: %d sides in view" % [step, pose, seen]
				)
				. is_greater_equal(pose[3])
			)
		assert_int(total).is_greater_equal(MIN_SIDES_PER_STEP)
	rig.get_parent().free()
	_outline.redraw()


## Poses `rig` as `pose` says, fits the outline to it, checks every side in
## view for the band width and returns how many sides were in view.
func _check_widths_at(rig: TycoonCamera, cam: Camera3D, view: Rect2, pose: Array) -> int:
	var want := BuildableOutline.WIDTH_PX
	_pose(rig, pose[0], pose[1], pose[2])
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
					"angle %d pose %s side %d: %d points, %.2f..%.2f px, want %.0f +- 1"
					% [rig.angle_step, pose, s, px.size(), low, high, want]
				)
			)
			. is_true()
		)
	return sides_seen


## A camera low over the south edge with that edge behind it (the low angle
## step: the steeper steps look down past the edge instead): every width is
## finite and inside MIN_WIDTH_M to half the plot, and so is the mesh.
func test_a_corner_behind_the_camera_keeps_finite_clamped_widths() -> void:
	var rig := _make_rig()
	var cam: Camera3D = rig.get_node("Camera3D")
	var plot := _plot()
	rig.angle_step = TycoonCamera.AngleStep.LOW
	_pose(rig, Vector3(plot.get_center().x, 0.0, plot.end.y - 8.0), 6.0, 0.0)
	var outer := _outline.outline_points()
	var behind := [2, 3].filter(func(i: int) -> bool: return cam.is_position_behind(outer[i]))
	assert_int(behind.size()).is_equal(2)
	_outline.fit(cam)
	# Half the plot's shorter side, the most a band is let grow to.
	var widest := minf(plot.size.x, plot.size.y) / 2.0
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
	rig.get_parent().free()
	_outline.redraw()


## A TycoonCamera in its own 1536x864 view, the game's base view size.
func _make_rig() -> TycoonCamera:
	var box := SubViewport.new()
	box.size = Vector2i(1536, 864)
	add_child(box)
	var rig: TycoonCamera = CAMERA.instantiate()
	box.add_child(rig)
	return rig


## Places `rig` the way TycoonCamera's own controls would: focus, zoom and yaw,
## its pitch from its angle step.
func _pose(rig: TycoonCamera, focus: Vector3, zoom: float, yaw: float) -> void:
	rig.position = focus
	rig.distance = zoom
	rig.yaw = yaw
	rig.rotate_yaw(0.0)


## The band's thickness on screen across one side's `edge`: at every piece end
## and piece middle where the outer and inner points are in front of `cam` and
## inside `view`, the pixels from the inner point to the line the side's outer
## edge projects to (through this piece end and a neighbouring one).
func _measured_pixels(cam: Camera3D, edge: PackedVector3Array, view: Rect2) -> Array[float]:
	var out: Array[float] = []
	for k in range(0, edge.size(), 2):
		var neighbour := k + 2 if k + 2 < edge.size() else k - 2
		var pairs := [[edge[k], edge[k + 1]]]
		if k + 2 < edge.size():
			pairs.append([(edge[k] + edge[k + 2]) / 2.0, (edge[k + 1] + edge[k + 3]) / 2.0])
		for pair in pairs:
			if (
				cam.is_position_behind(pair[0])
				or cam.is_position_behind(pair[1])
				or cam.is_position_behind(edge[neighbour])
			):
				continue
			var a := cam.unproject_position(pair[0])
			var b := cam.unproject_position(pair[1])
			if not view.has_point(a) or not view.has_point(b):
				continue
			var line := (cam.unproject_position(edge[neighbour]) - a).normalized()
			out.append(absf((b - a).cross(line)))
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
