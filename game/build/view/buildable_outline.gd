class_name BuildableOutline
extends Node3D
## A thin bright outline round the land the player may build on, shown only
## while build mode lasts (user ruling buildable-land-shows-as-an-outline-only-
## in-build-mode-the-da: "While a build tray is open, a thin bright outline runs
## around the owned, buildable land of the terminal site. Outside build mode it
## is not drawn."). Build mode is BuildMenu's BuildSession (decision build-mode-
## pauses-the-game-while-a-build-tray-is-open-closin), so the outline follows its
## changed signal.
##
## Each buildable rectangle gets a flat frame laid on the ground just inside its
## edge, so nothing hangs over the paving's skirt. The frame keeps about the
## same width on screen at every zoom (user ruling buildable-outline-keeps-a-
## constant-on-screen-width-at-every-zoom): while it shows, each side's inward
## offset is solved at every piece end through the camera's own projection, so
## the band is WIDTH_PX thick on screen, measured across itself from the outer
## edge's screen line, whatever the pitch, yaw and depth. It is refit only when
## the camera or the view size changes. The colour is the HUD's teal for
## "normal" (decision hud-look-warm-cozy-cream-cards-with-a-dark-outline-toon-
## pale, point 2), kept apart from the ghost's green and red, the wall-gap
## bars' red and the road's yellow and white paint. Unshaded and casting no
## shadow.
##
## The land comes from buildable_rects() alone. Today it is the site's whole
## BuildGrid; land plots (board ee9914e6) replace that one function with the
## owned plots and call redraw() when a plot is bought.
##
## Like BuildView it draws in world space, so it sits at the world origin.

## The frame's width on screen, in the viewport's pixels (the 1536x864 base
## view at 1.25 stretch): about the 0.3 m strip seen from an 18 m build zoom.
const WIDTH_PX := 12.0
## Each side is drawn in pieces at most this long, the width solved at each
## piece end.
const SEGMENT_M := 2.0
## The inward direction of each side, north, east, south and west. Side i runs
## from corner i to corner i + 1.
const SIDE_INWARD: Array[Vector3] = [Vector3.BACK, Vector3.LEFT, Vector3.FORWARD, Vector3.RIGHT]
## The width before any camera has been fitted, and the narrowest it gets.
const FALLBACK_WIDTH_M := 0.3
const MIN_WIDTH_M := 0.05
## Bisection steps for one width: the bracket shrinks 2^18-fold, under a
## millimetre on a 40 m plot.
const SOLVE_STEPS := 18
## The strips lie this far over the grid's floor height, above the paving and
## the floor tiles at the edge.
const LIFT_M := 0.05
const COLOR := Color(0.2, 0.86, 0.86)

## The build mode whose grid is outlined; main.tscn sets it, and _ready()
## binds its grid.
@export var build_mode: BuildMode
## The menu whose build session shows and hides the outline.
@export var menu: BuildMenu

var _grid: BuildGrid
var _rects: Array[Rect2] = []
var _height := 0.0
## The mitred inner corners, in the order of outline_points().
var _inner := PackedVector3Array()
## Per side (four per rectangle): each piece end's outer point and the point
## straight in from it at that end's width, alternating.
var _edges: Array[PackedVector3Array] = []
var _strips := MeshInstance3D.new()
## What the widths were last fitted to: camera transform, fov or size, view size.
var _fitted_key: Array = []


func _init() -> void:
	visible = false
	set_process(false)
	_strips.name = "OutlineStrips"
	_strips.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = COLOR
	_strips.material_override = material
	add_child(_strips)


func _ready() -> void:
	if build_mode != null:
		bind(build_mode.grid)
	if menu != null:
		watch(menu.build_session)


func _process(_delta: float) -> void:
	fit(get_viewport().get_camera_3d())


## The land the player may build on, as world rectangles on the ground
## (Rect2 x is world x, y is world z). Land plots will return the owned plots.
static func buildable_rects(grid: BuildGrid) -> Array[Rect2]:
	return [Rect2(grid.origin.x, grid.origin.z, grid.size.x, grid.size.y)]


## The ground width, MIN_WIDTH_M to `widest`, that sets the point `inward` of
## `outer` WIDTH_PX viewport pixels from the side's outer edge line as `camera`
## projects them: the band's thickness across itself on screen. The side runs
## square to `inward` on the ground, so its screen line is found by projecting
## `outer` and a point a metre along the side. That thickness grows with the
## width along a ground ray, so it is found by bisection. An outer point behind
## the camera, or a side with no point a metre either way in front of it, gets
## MIN_WIDTH_M; an inner point behind the camera counts as too wide; a grazing
## view whose widest strip is still under WIDTH_PX gets `widest`.
static func solve_width(camera: Camera3D, outer: Vector3, inward: Vector3, widest: float) -> float:
	if widest <= MIN_WIDTH_M or camera.is_position_behind(outer):
		return MIN_WIDTH_M
	var along := inward.cross(Vector3.UP)
	if camera.is_position_behind(outer + along):
		along = -along
		if camera.is_position_behind(outer + along):
			return MIN_WIDTH_M
	var at := camera.unproject_position(outer)
	var line := camera.unproject_position(outer + along) - at
	if line.length() < 0.001:
		return MIN_WIDTH_M
	line = line.normalized()
	if _pixels(camera, at, line, outer + inward * MIN_WIDTH_M) >= WIDTH_PX:
		return MIN_WIDTH_M
	if _pixels(camera, at, line, outer + inward * widest) <= WIDTH_PX:
		return widest
	var low := MIN_WIDTH_M
	var high := widest
	for _i in SOLVE_STEPS:
		var mid := (low + high) / 2.0
		if _pixels(camera, at, line, outer + inward * mid) < WIDTH_PX:
			low = mid
		else:
			high = mid
	return (low + high) / 2.0


## Viewport pixels from the screen line through `at` along unit `line` to where
## `camera` projects `point`; INF when the point is behind the camera.
static func _pixels(camera: Camera3D, at: Vector2, line: Vector2, point: Vector3) -> float:
	if camera.is_position_behind(point):
		return INF
	return absf((camera.unproject_position(point) - at).cross(line))


## Outlines `grid`'s buildable land.
func bind(grid: BuildGrid) -> void:
	_grid = grid
	redraw()


## Shows the outline exactly while `session` is in build mode.
func watch(session: BuildSession) -> void:
	if not session.changed.is_connected(set_building):
		session.changed.connect(set_building)
	set_building(session.active)


func set_building(on: bool) -> void:
	visible = on
	set_process(on)
	if on and is_inside_tree():
		_process(0.0)


## Rebuilds the frame from buildable_rects(), at the fallback width until a
## camera is fitted.
func redraw() -> void:
	_rects = buildable_rects(_grid)
	_height = _grid.origin.y + LIFT_M
	_fitted_key = []
	_build_mesh(
		func(_point: Vector3, _inward: Vector3, widest: float) -> float:
			return minf(FALLBACK_WIDTH_M, widest)
	)


## Sets the frame to WIDTH_PX on screen for `camera`, in its viewport's
## visible pixels. Does nothing when that is what it is fitted to.
func fit(camera: Camera3D) -> void:
	if camera == null or not camera.is_inside_tree() or _rects.is_empty():
		return
	var view := camera.get_viewport().get_visible_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	var lens := camera.size if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else camera.fov
	var key := [camera.global_transform, camera.projection, lens, view]
	if key == _fitted_key:
		return
	_fitted_key = key
	_build_mesh(
		func(point: Vector3, inward: Vector3, widest: float) -> float:
			return solve_width(camera, point, inward, widest)
	)


## The rectangles drawn.
func rects() -> Array[Rect2]:
	return _rects.duplicate()


## The outer corners of every drawn rectangle at the strips' height, four per
## rectangle, clockwise from the north-west seen from above.
func outline_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	for rect in _rects:
		out.append(Vector3(rect.position.x, _height, rect.position.y))
		out.append(Vector3(rect.end.x, _height, rect.position.y))
		out.append(Vector3(rect.end.x, _height, rect.end.y))
		out.append(Vector3(rect.position.x, _height, rect.end.y))
	return out


## The mitred inner corners, in the order of outline_points(): each lies in
## from its outer corner by the two meeting sides' own widths there.
func inner_points() -> PackedVector3Array:
	return _inner.duplicate()


## Per side, four per rectangle in the order north, east, south, west: every
## piece end's outer point followed by the point straight in from it at that
## end's width (not the mitre), from the side's first corner to its last.
func side_edges() -> Array[PackedVector3Array]:
	return _edges.duplicate(true)


## The mesh the frame is drawn with.
func strip_mesh() -> Mesh:
	return _strips.mesh


## Quads from the outer edge to the inner edge, each side cut into pieces at
## most SEGMENT_M long. `width_at(point, inward, widest)` gives the width in
## metres at an outer-edge point of the side pointing `inward`. Each corner is
## mitred: moved in along each meeting side's inward direction by that side's
## width at the corner, so both inner edges meet there.
## Short pieces keep the width right where a far corner lies behind the camera.
func _build_mesh(width_at: Callable) -> void:
	var outer := outline_points()
	_edges.clear()
	for r in _rects.size():
		var widest := _widest(r)
		for side in 4:
			var a := outer[r * 4 + side]
			var b := outer[r * 4 + (side + 1) % 4]
			var pieces := maxi(1, ceili(a.distance_to(b) / SEGMENT_M))
			var edge := PackedVector3Array()
			for k in pieces + 1:
				var at := a.lerp(b, k / float(pieces))
				var width: float = width_at.call(at, SIDE_INWARD[side], widest)
				edge.append(at)
				edge.append(at + SIDE_INWARD[side] * width)
			_edges.append(edge)
	_inner.resize(outer.size())
	for i in outer.size():
		var leaving := _edges[i]
		var arriving := _edges[i - i % 4 + (i + 3) % 4]
		var tail := arriving.size()
		_inner[i] = outer[i] + leaving[1] - leaving[0] + arriving[tail - 1] - arriving[tail - 2]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in _edges.size():
		var edge := _edges[s]
		var last := int(edge.size() / 2.0) - 1
		for k in last:
			var prev_in := _inner[s] if k == 0 else edge[k * 2 + 1]
			var next_in := edge[k * 2 + 3]
			if k + 1 == last:
				next_in = _inner[s - s % 4 + (s + 1) % 4]
			for p in [edge[k * 2], edge[k * 2 + 2], next_in, edge[k * 2], next_in, prev_in]:
				surface.set_normal(Vector3.UP)
				surface.add_vertex(p)
	_strips.mesh = surface.commit()


func _widest(rect_index: int) -> float:
	var rect := _rects[rect_index]
	return minf(rect.size.x, rect.size.y) / 2.0
