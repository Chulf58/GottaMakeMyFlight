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
## Each loop of the buildable land's edge gets a flat frame laid on the ground
## just inside it, so nothing hangs over the paving's skirt. The frame keeps about the
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
## The land comes from buildable_loops() alone: the edge of the owned land
## plots on the site's grid (LandPlots.outline_loops()), or a grid's whole
## rectangle when it has no land plots. A loop runs clockwise seen from above
## with the land on its right, so a hole of land not owned gets its band on
## the owned side too. It is drawn again whenever a plot is bought or the land
## is loaded (LandPlots.changed).
##
## Like BuildView it draws in world space, so it sits at the world origin.

## The frame's width on screen, in the viewport's pixels (the 1536x864 base
## view at 1.25 stretch): about the 0.3 m strip seen from an 18 m build zoom.
const WIDTH_PX := 12.0
## Each side is drawn in pieces at most this long, the width solved at each
## piece end.
const SEGMENT_M := 2.0
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
var _loops: Array[PackedVector2Array] = []
var _height := 0.0
## The mitred inner corners, in the order of outline_points().
var _inner := PackedVector3Array()
## Per side (one per corner, in the order of outline_points()): each piece
## end's outer point and the point straight in from it at that end's width,
## alternating.
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


## The edge of the land the player may build on, as closed loops of corner
## points on the ground (x is world x, y is world z), each clockwise seen from
## above from its north-west corner: the owned plots on the site's grid, or
## the whole grid when it has no land plots.
static func buildable_loops(grid: BuildGrid) -> Array[PackedVector2Array]:
	var site_grid := grid as SiteGrid
	if site_grid != null and site_grid.land != null:
		return site_grid.land.outline_loops(grid.origin)
	var whole := Rect2(grid.origin.x, grid.origin.z, grid.size.x, grid.size.y)
	return [
		PackedVector2Array(
			[
				whole.position,
				Vector2(whole.end.x, whole.position.y),
				whole.end,
				Vector2(whole.position.x, whole.end.y),
			]
		)
	]


## The ground direction straight in from a side running `along` (land on its
## right, seen from above).
static func inward_of(along: Vector3) -> Vector3:
	return Vector3(-along.z, 0.0, along.x).normalized()


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


## Outlines `grid`'s buildable land, and again whenever its land plots change.
func bind(grid: BuildGrid) -> void:
	_grid = grid
	var site_grid := grid as SiteGrid
	if site_grid != null and site_grid.land != null:
		if not site_grid.land.changed.is_connected(redraw):
			site_grid.land.changed.connect(redraw)
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


## Rebuilds the frame from buildable_loops(), at the fallback width until a
## camera is fitted.
func redraw() -> void:
	_loops = buildable_loops(_grid)
	_height = _grid.origin.y + LIFT_M
	_fitted_key = []
	_build_mesh(
		func(_point: Vector3, _inward: Vector3, widest: float) -> float:
			return minf(FALLBACK_WIDTH_M, widest)
	)


## Sets the frame to WIDTH_PX on screen for `camera`, in its viewport's
## visible pixels. Does nothing when that is what it is fitted to.
func fit(camera: Camera3D) -> void:
	if camera == null or not camera.is_inside_tree() or _loops.is_empty():
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


## The loops drawn.
func loops() -> Array[PackedVector2Array]:
	return _loops.duplicate()


## The outer corners of every drawn loop at the strips' height, loop by loop,
## each clockwise from its north-west corner seen from above.
func outline_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	for loop in _loops:
		for corner in loop:
			out.append(Vector3(corner.x, _height, corner.y))
	return out


## The mitred inner corners, in the order of outline_points(): each lies in
## from its outer corner by the two meeting sides' own widths there.
func inner_points() -> PackedVector3Array:
	return _inner.duplicate()


## Per side, one per corner in the order of outline_points() (side i runs from
## corner i to the next corner of its loop; for a rectangle north, east, south,
## west): every piece end's outer point followed by the point straight in from
## it at that end's width (not the mitre), from the side's first corner to its
## last.
func side_edges() -> Array[PackedVector3Array]:
	return _edges.duplicate(true)


## The mesh the frame is drawn with.
func strip_mesh() -> Mesh:
	return _strips.mesh


## Quads from the outer edge to the inner edge, each side cut into pieces at
## most SEGMENT_M long. `width_at(point, inward, widest)` gives the width in
## metres at an outer-edge point of the side pointing `inward`. Each corner is
## mitred: moved in along each meeting side's inward direction by that side's
## width at the corner, so both inner edges meet there (inside the land at a
## corner where the land turns in, too).
## Short pieces keep the width right where a far corner lies behind the camera.
func _build_mesh(width_at: Callable) -> void:
	var outer := outline_points()
	_edges.clear()
	var base := 0
	for loop in _loops:
		var count := loop.size()
		var widest := _widest(loop)
		for k in count:
			var a := outer[base + k]
			var b := outer[base + (k + 1) % count]
			var inward := inward_of(b - a)
			var pieces := maxi(1, ceili(a.distance_to(b) / SEGMENT_M))
			var edge := PackedVector3Array()
			for j in pieces + 1:
				var at := a.lerp(b, j / float(pieces))
				var width: float = width_at.call(at, inward, widest)
				edge.append(at)
				edge.append(at + inward * width)
			_edges.append(edge)
		base += count
	_inner.resize(outer.size())
	base = 0
	for loop in _loops:
		var count := loop.size()
		for k in count:
			var leaving := _edges[base + k]
			var arriving := _edges[base + (k + count - 1) % count]
			var tail := arriving.size()
			_inner[base + k] = (
				outer[base + k] + leaving[1] - leaving[0] + arriving[tail - 1] - arriving[tail - 2]
			)
		base += count
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	base = 0
	for loop in _loops:
		var count := loop.size()
		for k in count:
			var edge := _edges[base + k]
			var last := int(edge.size() / 2.0) - 1
			for j in last:
				var prev_in := _inner[base + k] if j == 0 else edge[j * 2 + 1]
				var next_in := edge[j * 2 + 3]
				if j + 1 == last:
					next_in = _inner[base + (k + 1) % count]
				for p in [edge[j * 2], edge[j * 2 + 2], next_in, edge[j * 2], next_in, prev_in]:
					surface.set_normal(Vector3.UP)
					surface.add_vertex(p)
		base += count
	_strips.mesh = surface.commit()


## The widest a band may grow on a loop: half its shortest side, so the band
## stays inside a narrow part of the land.
func _widest(loop: PackedVector2Array) -> float:
	var shortest := INF
	for k in loop.size():
		shortest = minf(shortest, loop[k].distance_to(loop[(k + 1) % loop.size()]))
	return shortest / 2.0
