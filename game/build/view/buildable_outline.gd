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
## constant-on-screen-width-at-every-zoom): while it shows, every point of the
## inner edge is set WIDTH_PX screen pixels in from the outer edge, measured at
## its own depth from the camera, and refit only when the camera or the
## view size changes. The colour is the HUD's teal for "normal" (decision hud-
## look-warm-cozy-cream-cards-with-a-dark-outline-toon-pale, point 2), kept
## apart from the ghost's green and red, the wall-gap bars' red and the road's
## yellow and white paint. Unshaded and casting no shadow.
##
## The land comes from buildable_rects() alone. Today it is the site's whole
## BuildGrid; land plots (board ee9914e6) replace that one function with the
## owned plots and call redraw() when a plot is bought.
##
## Like BuildView it draws in world space, so it sits at the world origin.

## The frame's width on screen, in the viewport's pixels (the 1536x864 base
## view at 1.25 stretch): about the 0.3 m strip seen from an 18 m build zoom.
const WIDTH_PX := 12.0
## Each side is drawn in pieces at most this long, each piece's inner edge set
## from its own ends' depth.
const SEGMENT_M := 2.0
## The inward direction of each side, north, east, south and west.
const SIDE_INWARD: Array[Vector3] = [Vector3.BACK, Vector3.LEFT, Vector3.FORWARD, Vector3.RIGHT]
## The width before any camera has been fitted, and the narrowest it gets.
const FALLBACK_WIDTH_M := 0.3
const MIN_WIDTH_M := 0.05
## The strips lie this far over the grid's floor height, above the paving and
## the floor tiles at the edge.
const LIFT_M := 0.05
const COLOR := Color(0.2, 0.86, 0.86)
## The inward direction of each outer corner, clockwise from the north-west.
const INWARD: Array[Vector3] = [
	Vector3(1.0, 0.0, 1.0),
	Vector3(-1.0, 0.0, 1.0),
	Vector3(-1.0, 0.0, -1.0),
	Vector3(1.0, 0.0, -1.0)
]

## The build mode whose grid is outlined; main.tscn sets it, and _ready()
## binds its grid.
@export var build_mode: BuildMode
## The menu whose build session shows and hides the outline.
@export var menu: BuildMenu

var _grid: BuildGrid
var _rects: Array[Rect2] = []
var _height := 0.0
## Each outer corner's inward width in metres, four per rectangle.
var _widths := PackedFloat32Array()
var _strips := MeshInstance3D.new()
## What the widths were last fitted to: camera transform, fov or size, view height.
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
	fit(get_viewport().get_camera_3d(), get_viewport().get_visible_rect().size.y)


## The land the player may build on, as world rectangles on the ground
## (Rect2 x is world x, y is world z). Land plots will return the owned plots.
static func buildable_rects(grid: BuildGrid) -> Array[Rect2]:
	return [Rect2(grid.origin.x, grid.origin.z, grid.size.x, grid.size.y)]


## Metres on the ground that one viewport pixel covers at `point`, seen by
## `camera` in a view `view_height` pixels tall.
static func metres_per_pixel(camera: Camera3D, point: Vector3, view_height: float) -> float:
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return camera.size / view_height
	var depth := -(camera.global_transform.affine_inverse() * point).z
	depth = maxf(depth, camera.near)
	return 2.0 * depth * tan(deg_to_rad(camera.fov) / 2.0) / view_height


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
	_build_mesh(func(_point: Vector3, _widest: float) -> float: return FALLBACK_WIDTH_M)


## Sets the frame to WIDTH_PX on screen for `camera` in a view `view_height`
## pixels tall. Does nothing when that is what it is fitted to.
func fit(camera: Camera3D, view_height: float) -> void:
	if camera == null or view_height <= 0.0 or _rects.is_empty():
		return
	var lens := camera.size if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else camera.fov
	var key := [camera.global_transform, lens, view_height]
	if key == _fitted_key:
		return
	_fitted_key = key
	var width_at := func(point: Vector3, widest: float) -> float:
		var metres := WIDTH_PX * metres_per_pixel(camera, point, view_height)
		return clampf(metres, MIN_WIDTH_M, widest)
	_build_mesh(width_at)


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


## The inner corners, in the order of outline_points().
func inner_points() -> PackedVector3Array:
	var outer := outline_points()
	var out := PackedVector3Array()
	for i in outer.size():
		out.append(outer[i] + INWARD[i % 4] * _widths[i])
	return out


## The mesh the frame is drawn with.
func strip_mesh() -> Mesh:
	return _strips.mesh


## Quads from the outer edge to the inner edge, each side cut into pieces at
## most SEGMENT_M long. `width_at(point, widest)` gives the width in metres at
## an outer-edge point; the corners are mitred (moved in along both axes).
## Short pieces keep the width right where a far corner lies behind the camera.
func _build_mesh(width_at: Callable) -> void:
	var outer := outline_points()
	_widths.resize(outer.size())
	for i in outer.size():
		_widths[i] = width_at.call(outer[i], _widest(floori(i / 4.0)))
	var inner := inner_points()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in _rects.size():
		var widest := _widest(r)
		for side in 4:
			var a := r * 4 + side
			var b := r * 4 + (side + 1) % 4
			var pieces := maxi(1, ceili(outer[a].distance_to(outer[b]) / SEGMENT_M))
			var prev_out := outer[a]
			var prev_in := inner[a]
			for k in range(1, pieces + 1):
				var next_out := outer[a].lerp(outer[b], k / float(pieces))
				var next_in := inner[b]
				if k < pieces:
					next_in = next_out + SIDE_INWARD[side] * width_at.call(next_out, widest)
				for p in [prev_out, next_out, next_in, prev_out, next_in, prev_in]:
					surface.set_normal(Vector3.UP)
					surface.add_vertex(p)
				prev_out = next_out
				prev_in = next_in
	_strips.mesh = surface.commit()


func _widest(rect_index: int) -> float:
	var rect := _rects[rect_index]
	return minf(rect.size.x, rect.size.y) / 2.0
