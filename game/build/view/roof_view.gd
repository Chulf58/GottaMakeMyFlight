class_name RoofView
extends Node3D
## Draws the roof of the player-built terminal: a flat toon roof over every
## indoor cell (BuildGrid.is_indoor) with an overhang and a fascia band round
## its edge, as one batched mesh (decision player-built-terminal-technical-
## design-site-plot-indoor-mask-passenger-eligibility, point 7). It is rebuilt
## when the grid's graph changes and the indoor cells changed with it, so a
## gap in the outer wall takes the roof off that building and closing it puts
## the roof back. View only: it changes no grid or path.
##
## The roof fades out as the camera zooms in and back as it zooms out
## (RoofCutaway, user ruling toon-terminal-roof-shows-from-far-away-and-fades-
## out-when-th), drawn as the shell roof's dither on the surface and its
## outline. It casts no shadow while it fades or is gone: the dither would run
## in the shadow pass too (anti-pattern a-screen-space-dither-dissolve-also-
## runs-in-the-shadow-pass).
##
## Shape, in the grid's frame: the top sits roof_height above the floor. Each
## outer edge of the indoor cells gets a top strip `overhang` wide outward, a
## soffit under it and a fascia face on its outer line from the top down
## fascia_depth. At a convex corner the north or south strip and both fascia
## faces run on by the overhang; at an inner corner the north or south strip
## and both fascia faces stop short by it, so no two faces overlap. The
## colours are two texels of the Toon palette atlas (roof_uv, fascia_uv; the
## defaults are the Toon terminal's Upper roof top and its edge band).
##
## Like BuildView it draws in world space, so it sits at the world origin.

const ROOF_MATERIAL := "res://assets/materials/tp_atlas_toon.tres"
const TOON := "res://shaders/toon.gdshader"
const OUTLINE := "res://shaders/toon_outline.gdshader"
const TOON_DISSOLVE := preload("res://shaders/toon_dissolve.gdshader")
const OUTLINE_DISSOLVE := preload("res://shaders/toon_outline_dissolve.gdshader")

## The camera rig whose distance drives the fade. Without one the roof keeps
## whatever level draw_level() last set.
@export var camera: TycoonCamera
## Shape tuning in metres. The wall height the roof sits on is still a plate
## decision (kit walls 2.5 m or the old facade's 5.2 m), so both are inputs.
@export var roof_height := 2.8
@export var fascia_depth := 0.6
@export var overhang := 0.25
@export var roof_uv := Vector2(0.546, 0.0141)
@export var fascia_uv := Vector2(0.543, 0.054)
@export var roof_hide_below := 100.0
@export var roof_show_above := 120.0
@export var roof_fade_seconds := 0.4

var cutaway := RoofCutaway.new()

var _grid: BuildGrid
var _roof := MeshInstance3D.new()
## The surface material and its outline pass, both on the dissolve shaders.
var _materials: Array[ShaderMaterial] = []
## The indoor mask the roof was last built from, one byte per cell.
var _indoor := PackedByteArray()
var _roofed := 0
var _level := 0.0


func _init() -> void:
	_roof.name = "Roof"
	add_child(_roof)
	var problem := _make_materials()
	if problem != "":
		push_error("RoofView: " + problem)


func _ready() -> void:
	cutaway.roof_hide_below = roof_hide_below
	cutaway.roof_show_above = roof_show_above
	cutaway.roof_fade_seconds = roof_fade_seconds
	var problem := cutaway.tuning_error()
	if problem != "":
		push_error("RoofView: " + problem)
	if camera != null and problem == "":
		cutaway.snap(camera.distance)
		draw_level(cutaway.roof_level)
	set_process(camera != null and problem == "")


func _process(delta: float) -> void:
	cutaway.step(camera.distance, delta)
	if cutaway.roof_level != _level:
		draw_level(cutaway.roof_level)


## Draws `grid`'s roof and redraws it whenever its indoor cells change.
func bind(grid: BuildGrid) -> void:
	if _grid != null and _grid.graph_changed.is_connected(_on_graph_changed):
		_grid.graph_changed.disconnect(_on_graph_changed)
	_grid = grid
	_grid.graph_changed.connect(_on_graph_changed)
	rebuild()


## Builds the roof mesh again from the grid's indoor cells.
func rebuild() -> void:
	_indoor = _indoor_mask()
	_roofed = 0
	for value in _indoor:
		_roofed += value
	_roof.mesh = _build_mesh() if _roofed > 0 else null
	draw_level(_level)


## Draws a fade level: 0 drawn, 1 gone.
func draw_level(level: float) -> void:
	_level = level
	for mat in _materials:
		mat.set_shader_parameter("dissolve", level)
	_roof.visible = _roofed > 0 and level < 1.0
	_roof.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if level == 0.0
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)


func roofed_cell_count() -> int:
	return _roofed


func roof_node() -> MeshInstance3D:
	return _roof


## The roof surface's material (its outline is its next_pass).
func surface_material() -> ShaderMaterial:
	return _materials[0] if not _materials.is_empty() else null


## The roof mesh's bounds in world space; empty with no roof.
func roof_box() -> AABB:
	return _roof.mesh.get_aabb() if _roof.mesh != null else AABB()


## The area of the roof's upward faces in square metres.
func top_area() -> float:
	if _roof.mesh == null:
		return 0.0
	var verts: PackedVector3Array = _roof.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var area := 0.0
	for i in range(0, verts.size(), 3):
		var normal := (verts[i + 1] - verts[i]).cross(verts[i + 2] - verts[i])
		if absf(normal.y) > 0.5 * normal.length() and _is_top(verts[i].y):
			area += normal.length() * 0.5
	return area


func _is_top(y: float) -> bool:
	return is_equal_approx(y, _grid.origin.y + roof_height)


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	if _indoor_mask() != _indoor:
		rebuild()


func _indoor_mask() -> PackedByteArray:
	var mask := PackedByteArray()
	if _grid == null:
		return mask
	mask.resize(_grid.size.x * _grid.size.y)
	for y in _grid.size.y:
		for x in _grid.size.x:
			mask[x + y * _grid.size.x] = 1 if _grid.is_indoor(Vector2i(x, y)) else 0
	return mask


func _roofed_at(cell: Vector2i) -> bool:
	return _grid.in_bounds(cell) and _indoor[cell.x + cell.y * _grid.size.x] == 1


func _build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := roof_height
	var bottom := roof_height - fascia_depth
	for y in _grid.size.y:
		for x in _grid.size.x:
			var cell := Vector2i(x, y)
			if not _roofed_at(cell):
				continue
			var lo := Vector2(x, y)
			_flat(st, lo, lo + Vector2.ONE, top, Vector3.UP, roof_uv)
			for side in 4:
				if not _roofed_at(cell + BuildGrid.SIDE_STEP[side]):
					_edge(st, cell, side, top, bottom)
	var mesh := st.commit()
	if not _materials.is_empty():
		mesh.surface_set_material(0, _materials[0])
	return mesh


## The overhang strip, its soffit and its fascia face on one outer edge.
func _edge(st: SurfaceTool, cell: Vector2i, side: int, top: float, bottom: float) -> void:
	var out_step: Vector2i = BuildGrid.SIDE_STEP[side]
	var along_step := EnclosureGaps.Run.along_of(side)
	var out := Vector2(out_step)
	var along := Vector2(along_step)
	var north_south := along_step.x == 1
	var strip_ends := PackedFloat32Array([0.0, 0.0])
	var face_ends := PackedFloat32Array([0.0, 0.0])
	for k in 2:
		var next := cell + along_step * (-1 if k == 0 else 1)
		var turn := 0.0
		if not _roofed_at(next):
			turn = overhang
		elif _roofed_at(next + out_step):
			turn = -overhang
		face_ends[k] = turn
		strip_ends[k] = turn if north_south else 0.0
	var mid := Vector2(cell) + Vector2(0.5, 0.5) + out * 0.5
	var a := mid - along * (0.5 + strip_ends[0])
	var b := mid + along * (0.5 + strip_ends[1]) + out * overhang
	_flat(st, a, b, top, Vector3.UP, roof_uv)
	_flat(st, a, b, bottom, Vector3.DOWN, fascia_uv)
	var line := mid + out * overhang
	var f0 := line - along * (0.5 + face_ends[0])
	var f1 := line + along * (0.5 + face_ends[1])
	var normal := Vector3(out.x, 0.0, out.y)
	_quad(
		st,
		[_world(f0, bottom), _world(f1, bottom), _world(f1, top), _world(f0, top)],
		normal,
		fascia_uv
	)


## A horizontal rectangle between grid-frame corners `a` and `b` at `height`.
func _flat(
	st: SurfaceTool, a: Vector2, b: Vector2, height: float, normal: Vector3, uv: Vector2
) -> void:
	var lo := a.min(b)
	var hi := a.max(b)
	_quad(
		st,
		[
			_world(lo, height),
			_world(Vector2(hi.x, lo.y), height),
			_world(hi, height),
			_world(Vector2(lo.x, hi.y), height),
		],
		normal,
		uv
	)


## Two triangles over the loop `corners`, wound so `normal` is their front
## (Godot's front faces wind clockwise as seen from the front).
func _quad(st: SurfaceTool, corners: Array, normal: Vector3, uv: Vector2) -> void:
	var loop: Array = corners
	if (loop[1] - loop[0]).cross(loop[2] - loop[0]).dot(normal) > 0.0:
		loop = [corners[3], corners[2], corners[1], corners[0]]
	st.set_normal(normal)
	st.set_uv(uv)
	for i in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(loop[i])


## World position of a grid-frame point (cells, x east and y south) at
## `height` above the floor.
func _world(point: Vector2, height: float) -> Vector3:
	return _grid.origin + Vector3(point.x, height, point.y)


## The roof's own copies of the Toon atlas material and its outline on the
## dissolve shaders. Returns what is wrong, or "".
func _make_materials() -> String:
	var source := load(ROOF_MATERIAL) as ShaderMaterial
	if source == null or source.shader == null or source.shader.resource_path != TOON:
		return "%s is not the toon material" % ROOF_MATERIAL
	var outline := source.next_pass as ShaderMaterial
	if outline == null or outline.shader == null or outline.shader.resource_path != OUTLINE:
		return "%s has no toon outline pass" % ROOF_MATERIAL
	var surface := _copy(source, TOON_DISSOLVE)
	surface.next_pass = _copy(outline, OUTLINE_DISSOLVE)
	_materials = [surface, surface.next_pass as ShaderMaterial]
	return ""


## A new material on `shader` holding every parameter value `source` has set
## (as ShellView copies the shell roof's materials).
static func _copy(source: ShaderMaterial, shader: Shader) -> ShaderMaterial:
	var made := ShaderMaterial.new()
	made.shader = shader
	made.render_priority = source.render_priority
	for uniform in source.shader.get_shader_uniform_list():
		var key: String = uniform["name"]
		var value: Variant = source.get_shader_parameter(key)
		if value != null:
			made.set_shader_parameter(key, value)
	return made
