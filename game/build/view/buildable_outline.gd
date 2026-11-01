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
## Each buildable rectangle gets four flat strips laid on the ground just
## inside its edge, so nothing hangs over the paving's skirt. The colour is the
## HUD's teal for "normal" (decision hud-look-warm-cozy-cream-cards-with-a-dark-
## outline-toon-pale, point 2), kept apart from the ghost's green and red, the
## wall-gap bars' red and the road's yellow and white paint. Unshaded and
## casting no shadow.
##
## The land comes from buildable_rects() alone. Today it is the site's whole
## BuildGrid; land plots (board ee9914e6) replace that one function with the
## owned plots and call redraw() when a plot is bought.
##
## Like BuildView it draws in world space, so it sits at the world origin.

## The strip's width, measured inward from the land's edge.
const WIDTH_M := 0.3
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
var _strips := MeshInstance3D.new()


func _init() -> void:
	visible = false
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


## The land the player may build on, as world rectangles on the ground
## (Rect2 x is world x, y is world z). Land plots will return the owned plots.
static func buildable_rects(grid: BuildGrid) -> Array[Rect2]:
	return [Rect2(grid.origin.x, grid.origin.z, grid.size.x, grid.size.y)]


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


## Rebuilds the strips from buildable_rects().
func redraw() -> void:
	_rects = buildable_rects(_grid)
	_height = _grid.origin.y + LIFT_M
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for rect in _rects:
		for strip in _strips_of(rect):
			_add_quad(surface, strip)
	_strips.mesh = surface.commit()


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


## The mesh the strips are drawn with.
func strip_mesh() -> Mesh:
	return _strips.mesh


## North and south run the full width; west and east fill between them.
static func _strips_of(rect: Rect2) -> Array[Rect2]:
	var w := minf(WIDTH_M, minf(rect.size.x, rect.size.y) / 2.0)
	var inner := rect.size.y - 2.0 * w
	return [
		Rect2(rect.position.x, rect.position.y, rect.size.x, w),
		Rect2(rect.position.x, rect.end.y - w, rect.size.x, w),
		Rect2(rect.position.x, rect.position.y + w, w, inner),
		Rect2(rect.end.x - w, rect.position.y + w, w, inner),
	]


func _add_quad(surface: SurfaceTool, strip: Rect2) -> void:
	var a := Vector3(strip.position.x, _height, strip.position.y)
	var b := Vector3(strip.end.x, _height, strip.position.y)
	var c := Vector3(strip.end.x, _height, strip.end.y)
	var d := Vector3(strip.position.x, _height, strip.end.y)
	for p in [a, b, c, a, c, d]:
		surface.set_normal(Vector3.UP)
		surface.add_vertex(p)
