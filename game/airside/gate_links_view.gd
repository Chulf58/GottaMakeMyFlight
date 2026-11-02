class_name GateLinksView
extends Node3D
## Shows which exit and stand each gate desk is linked to (Gates 2/4, board
## 51bcad8a), so the automatic link is never hidden (user ruling gates-are-
## placed-gate-desks-each-desk-links-automatically-to: "shown with a visible
## connection, never a manual hook-up").
##
## While build mode lasts (as the guard area and the buildable outline, decision
## plane-guard-area-shows-only-in-build-mode-the-site-paving-ex), every gate
## gets a sky-blue line on the ground from the edge of its desk to its exit and
## on out to where its plane's door will stand (StandPlacement.door_point()), a
## disc at that end and a "Gate A" caption over the desk. The line keeps
## WIDTH_PX on screen at every zoom: a vertex shader pushes each segment's
## corners apart in screen space, a dark rim pass drawn under the fill pass.
## Where the terminal's north wall hides the part out past the exit, a faint
## pass of that part drawn through everything (THROUGH_ALPHA) keeps the link
## readable; the part inside is depth tested only, so it comes out from behind
## its own desk instead of being drawn across it.
##
## A gate desk with no gate (GateDesks.unlinked(), decision gates-1b-as-built-
## gatedesks-link-desks-to-north-exits-as-sti, residual) gets no line and, at
## all times, an unlinked sign over it: the queue-full sign's form (decision
## queue-full-marker-a-red-sign-with-a-queue-full-n-waiting-cap: MarkerIcons'
## rounded square and outline, 56 px on screen, over walls and roof) in the
## closed-station slate, with its own broken-link glyph so the "!" keeps its
## meanings, and a caption under it naming why (caption_for()). The signs are
## not part of MissMarkers' declutter layout, like the wall-gap signs.
##
## Redrawn on every GateDesks.changed (each graph change). Draws in world space,
## so it sits at the world origin. View only.

const LIFT_M := 0.07
const WIDTH_PX := 8.0
const RIM_PX := 2.0
const LINE_FILL := Color(0.38, 0.68, 0.98)
## The fill's opacity where something stands between the camera and the line.
const THROUGH_ALPHA := 0.6
const END_RADIUS_M := 0.7
## The "Gate A" caption stands this far over the desk's top.
const CAPTION_LIFT_M := 0.5
const UNLINKED_PREFIX := "Unlinked: "
const FALLBACK_FOV := 55.0
const FALLBACK_HEIGHT := 1080.0
const LINE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled%s;
uniform vec4 colour : source_color = vec4(1.0);
uniform float width_px = 8.0;
// CUSTOM0.xyz is the segment's other end, CUSTOM0.w the side (+1 or -1). The
// corner moves half the width to its side and half the width past its own end
// (a square cap, so the bends close), measured in screen pixels.
void vertex() {
	vec4 here = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec4 there = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(CUSTOM0.xyz, 1.0));
	vec2 a = here.xy / here.w * VIEWPORT_SIZE;
	vec2 b = there.xy / there.w * VIEWPORT_SIZE;
	vec2 along = normalize(b - a);
	vec2 side = vec2(-along.y, along.x) * CUSTOM0.w;
	vec2 offset_px = (side - along) * width_px * 0.5;
	POSITION = here + vec4(offset_px * 2.0 / VIEWPORT_SIZE * here.w, 0.0, 0.0);
}
void fragment() {
	ALBEDO = colour.rgb;
	ALPHA = colour.a;
}
"""

static var _icon: ImageTexture
## The line shader with the depth test, and without it (the faint pass).
static var _shaders: Dictionary = {}

var _grid: BuildGrid
var _gates: GateDesks
## Lines, end discs and gate captions: shown only while build mode lasts.
var _links := Node3D.new()
var _through := MeshInstance3D.new()
var _rim := MeshInstance3D.new()
var _fill := MeshInstance3D.new()
var _ends: Array[MeshInstance3D] = []
var _captions: Array[Label3D] = []
var _signs: Array[Sprite3D] = []
var _paths: Array[PackedVector3Array] = []
var _unit := 0.0


func _init() -> void:
	_links.name = "Links"
	_links.visible = false
	add_child(_links)
	_through.name = "LineThrough"
	_rim.name = "LineRim"
	_fill.name = "LineFill"
	var faint := Color(LINE_FILL, THROUGH_ALPHA)
	_through.material_override = _line_material(faint, WIDTH_PX, 0, false)
	_rim.material_override = _line_material(MarkerIcons.OUTLINE, WIDTH_PX + 2.0 * RIM_PX, 1)
	_fill.material_override = _line_material(LINE_FILL, WIDTH_PX, 2)
	for line in [_through, _rim, _fill]:
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		line.extra_cull_margin = 4.0
		_links.add_child(line)


## Follows `on_gates`' links on `on_grid`.
func bind(on_grid: BuildGrid, on_gates: GateDesks) -> void:
	if _gates != null and _gates.changed.is_connected(rebuild):
		_gates.changed.disconnect(rebuild)
	_grid = on_grid
	_gates = on_gates
	_gates.changed.connect(rebuild)
	rebuild()


## Shows the lines, end discs and gate captions while build mode lasts.
func set_building(on: bool) -> void:
	_links.visible = on


func is_building() -> bool:
	return _links.visible


## The ground path of `binding`'s link on `grid`: where the way from the desk's
## footprint centre to the exit's cell centre leaves the footprint (the desk's
## edge), the exit's cell centre, and where the plane's door stands at its
## stand, each LIFT_M over the grid's floor.
static func link_points(grid: BuildGrid, binding: Dictionary) -> PackedVector3Array:
	var cells := GateDesks.desk_footprint(grid, binding["desk"])
	var area := Rect2(Vector2(cells[0]), Vector2.ONE)
	for cell in cells:
		area = area.merge(Rect2(Vector2(cell), Vector2.ONE))
	var origin := Vector2(grid.origin.x, grid.origin.z)
	var centre := area.get_center() + origin
	var exit_3d := grid.cell_to_world(grid.get_object(binding["exit"])["anchor"])
	var exit := Vector2(exit_3d.x, exit_3d.z)
	var edge := (
		centre + (exit - centre) * _leave_t(Rect2(area.position + origin, area.size), centre, exit)
	)
	var door := StandPlacement.door_point(StandPlacement.for_exit(grid, binding["exit"]))
	var y := grid.origin.y + LIFT_M
	return PackedVector3Array(
		[Vector3(edge.x, y, edge.y), Vector3(exit.x, y, exit.y), Vector3(door.x, y, door.z)]
	)


## The fraction of the way from `from` (inside `box`) to `to` at which it
## leaves `box`, at most 1.
static func _leave_t(box: Rect2, from: Vector2, to: Vector2) -> float:
	var t := 1.0
	var d := to - from
	for axis in 2:
		if d[axis] > 0.0:
			t = minf(t, (box.end[axis] - from[axis]) / d[axis])
		elif d[axis] < 0.0:
			t = minf(t, (box.position[axis] - from[axis]) / d[axis])
	return t


## What the sign over an unlinked desk says, from a GateDesks.unlinked() entry.
static func caption_for(reason: Dictionary) -> String:
	match reason["why"]:
		GateDesks.Unlinked.NO_EXIT:
			return UNLINKED_PREFIX + "no north exit within %d cells" % GateDesks.LINK_CELLS
		GateDesks.Unlinked.EXIT_TAKEN:
			return UNLINKED_PREFIX + "Gate %s uses the exit" % reason["gate"]
		GateDesks.Unlinked.STAND_OVERLAP:
			return UNLINKED_PREFIX + "stand would overlap Gate %s" % reason["gate"]
	return UNLINKED_PREFIX + "every gate letter is in use"


## Draws the links and the unlinked signs again from the gates.
func rebuild() -> void:
	_paths.clear()
	var gate_texts: Array[String] = []
	var desk_tops: Array[Vector3] = []
	if _grid != null and _gates != null:
		for binding in _gates.bindings:
			var path := link_points(_grid, binding)
			_paths.append(path)
			gate_texts.append("Gate %s" % binding["gate"])
			desk_tops.append(_desk_top(binding["desk"]))
	_draw_lines()
	_draw_ends()
	while _captions.size() < gate_texts.size():
		_captions.append(_make_caption("GateCaption", VERTICAL_ALIGNMENT_BOTTOM, 0.0))
		_links.add_child(_captions[-1])
	for i in _captions.size():
		_captions[i].visible = i < gate_texts.size()
		if i < gate_texts.size():
			_captions[i].text = gate_texts[i]
			_captions[i].position = desk_tops[i] + Vector3.UP * CAPTION_LIFT_M
	var unlinked: Dictionary = _gates.unlinked() if _gates != null else {}
	var desks: Array = unlinked.keys()
	desks.sort()
	while _signs.size() < desks.size():
		_signs.append(_make_sign())
	for i in _signs.size():
		_signs[i].visible = i < desks.size()
		if i < desks.size():
			_signs[i].position = _desk_top(desks[i]) + Vector3.UP * MissMarkers.SIGN_LIFT_M
			_signs[i].set_meta("desk", desks[i])
			caption_of(_signs[i]).text = caption_for(unlinked[desks[i]])
	update_sizes(true)


## The link paths drawn, one per gate in desk order (for probes and tests).
func paths() -> Array[PackedVector3Array]:
	return _paths.duplicate()


## The shown "Gate X" captions.
func gate_captions() -> Array[Label3D]:
	var out: Array[Label3D] = []
	for caption in _captions:
		if caption.visible:
			out.append(caption)
	return out


## The shown unlinked signs, in desk id order; each has meta "desk".
func signs() -> Array[Sprite3D]:
	var out: Array[Sprite3D] = []
	for marker in _signs:
		if marker.visible:
			out.append(marker)
	return out


func caption_of(marker: Sprite3D) -> Label3D:
	return marker.get_node("Caption") as Label3D


## The end discs shown, one per gate.
func ends() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for disc in _ends:
		if disc.visible:
			out.append(disc)
	return out


func line_node() -> MeshInstance3D:
	return _fill


## The faint pass drawn through walls (the part out past each exit).
func through_node() -> MeshInstance3D:
	return _through


func _process(_delta: float) -> void:
	update_sizes()


## Keeps the signs MissMarkers.SIGN_PX tall and the captions at their font
## size on screen, as GapMarkers sizes its signs; resizes only when the screen
## unit changed, or when `force`.
func update_sizes(force := false) -> void:
	var fov := FALLBACK_FOV
	var height := FALLBACK_HEIGHT
	if is_inside_tree():
		var view := get_viewport()
		var camera := view.get_camera_3d()
		if camera != null:
			fov = camera.fov
		height = view.get_visible_rect().size.y * view.get_stretch_transform().get_scale().y
	if height <= 0.0:
		return
	var unit := 2.0 * tan(deg_to_rad(fov) / 2.0) / height
	if not force and unit == _unit:
		return
	_unit = unit
	for marker in _signs:
		marker.pixel_size = MissMarkers.SIGN_PX * unit / MarkerIcons.SIZE
		caption_of(marker).pixel_size = unit
	for caption in _captions:
		caption.pixel_size = unit


## The top centre of gate desk `desk`: its footprint centre at the catalog
## height.
func _desk_top(desk: int) -> Vector3:
	var cells := GateDesks.desk_footprint(_grid, desk)
	var at := Vector3.ZERO
	for cell in cells:
		at += _grid.cell_to_world(cell)
	at /= cells.size()
	at.y = _grid.origin.y + BuildCatalog.get_def(GateDesks.DESK).height
	return at


## The whole paths for the rim and fill passes; for the faint pass only the
## part outside, from the exit's wall line (half a cell out from its centre)
## to the plane door, so nothing inside is drawn over.
func _draw_lines() -> void:
	var mesh := segments_mesh(_paths)
	_rim.mesh = mesh
	_fill.mesh = mesh
	var outside: Array[PackedVector3Array] = []
	for path in _paths:
		outside.append(PackedVector3Array([path[1].move_toward(path[2], 0.5), path[2]]))
	_through.mesh = segments_mesh(outside)


## One quad per segment of each of `paths`; every vertex carries the segment's
## other end and its side in CUSTOM0 for the line shader.
static func segments_mesh(paths: Array[PackedVector3Array]) -> ArrayMesh:
	var verts := PackedVector3Array()
	var custom := PackedFloat32Array()
	var index := PackedInt32Array()
	for path in paths:
		for i in path.size() - 1:
			var a := path[i]
			var b := path[i + 1]
			var base := verts.size()
			# Seen along a -> b: a's +1 corner and b's -1 corner are on one side.
			for corner in [[a, b, 1.0], [a, b, -1.0], [b, a, 1.0], [b, a, -1.0]]:
				verts.append(corner[0])
				var other: Vector3 = corner[1]
				custom.append_array(PackedFloat32Array([other.x, other.y, other.z, corner[2]]))
			index.append_array(
				PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3])
			)
	var mesh := ArrayMesh.new()
	if not verts.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_CUSTOM0] = custom
		arrays[Mesh.ARRAY_INDEX] = index
		var flags := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return mesh


## A disc at each path's far end (the plane door's place), rim under fill.
func _draw_ends() -> void:
	while _ends.size() < _paths.size():
		var disc := MeshInstance3D.new()
		disc.name = "LinkEnd%d" % _ends.size()
		var rim := CylinderMesh.new()
		rim.top_radius = END_RADIUS_M + 0.15
		rim.bottom_radius = rim.top_radius
		rim.height = 0.02
		rim.material = _flat(MarkerIcons.OUTLINE)
		disc.mesh = rim
		var fill := MeshInstance3D.new()
		var top := CylinderMesh.new()
		top.top_radius = END_RADIUS_M
		top.bottom_radius = END_RADIUS_M
		top.height = 0.02
		top.material = _flat(LINE_FILL)
		fill.mesh = top
		fill.position.y = 0.01
		disc.add_child(fill)
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_links.add_child(disc)
		_ends.append(disc)
	for i in _ends.size():
		_ends[i].visible = i < _paths.size()
		if i < _paths.size():
			_ends[i].position = _paths[i][-1]


static func _flat(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	return material


## A line pass: `colour` at `width_px` on screen, drawn in `priority` order,
## hidden behind what stands in front of it when `depth_test`.
static func _line_material(
	colour: Color, width_px: float, priority: int, depth_test := true
) -> ShaderMaterial:
	if not _shaders.has(depth_test):
		var shader := Shader.new()
		shader.code = LINE_SHADER % ("" if depth_test else ", depth_test_disabled")
		_shaders[depth_test] = shader
	var material := ShaderMaterial.new()
	material.shader = _shaders[depth_test]
	material.set_shader_parameter("colour", colour)
	material.set_shader_parameter("width_px", width_px)
	material.render_priority = priority
	return material


func _make_caption(node_name: String, align: VerticalAlignment, gap_px: float) -> Label3D:
	var caption := Label3D.new()
	caption.name = node_name
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.fixed_size = true
	caption.no_depth_test = true
	caption.render_priority = 12
	caption.outline_render_priority = 11
	caption.font_size = MissMarkers.CAPTION_FONT
	caption.outline_size = MissMarkers.CAPTION_OUTLINE
	caption.outline_modulate = MarkerIcons.OUTLINE
	caption.vertical_alignment = align
	caption.offset = Vector2(0.0, gap_px)
	return caption


func _make_sign() -> Sprite3D:
	var marker := Sprite3D.new()
	marker.name = "UnlinkedSign"
	marker.texture = unlinked_icon()
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.fixed_size = true
	marker.no_depth_test = true
	marker.shaded = false
	marker.render_priority = 11
	marker.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	marker.offset = Vector2(0.0, MarkerIcons.SIZE / 2.0)
	# Under the sign: its top edge a gap below the sign's foot.
	var caption := _make_caption("Caption", VERTICAL_ALIGNMENT_TOP, -MissMarkers.CAPTION_GAP_PX)
	marker.add_child(caption)
	add_child(marker)
	return marker


## The unlinked icon, painted once: MarkerIcons' rounded square and outline in
## the closed-station slate (MissMarkers.CLOSED_FILL), with a white broken chain
## link, drawn with MarkerIcons.shape_distance and segment_distance.
static func unlinked_icon() -> Texture2D:
	if _icon != null:
		return _icon
	var size := MarkerIcons.SIZE
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := size / 2.0
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5 - half, y + 0.5 - half)
			var edge := MarkerIcons.shape_distance(p)
			var cover := clampf(0.5 - edge, 0.0, 1.0)
			if cover <= 0.0:
				img.set_pixel(x, y, Color(MarkerIcons.OUTLINE, 0.0))
				continue
			var inside := clampf(0.5 - (edge + MarkerIcons.OUTLINE_PX), 0.0, 1.0)
			var colour := MarkerIcons.OUTLINE.lerp(MissMarkers.CLOSED_FILL, inside)
			var glyph := clampf(0.5 - _broken_link(p), 0.0, 1.0) * inside
			colour = colour.lerp(MarkerIcons.GLYPH, glyph)
			colour.a = cover
			img.set_pixel(x, y, colour)
	img.generate_mipmaps()
	_icon = ImageTexture.create_from_image(img)
	return _icon


## Signed distance in pixels to the white broken link: two chain links on a
## diagonal with a gap between them, and a short spark either side of the gap.
## Image y runs down.
static func _broken_link(p: Vector2) -> float:
	var ring_r := 12.0
	var stroke := 5.0
	var left := absf(
		MarkerIcons.segment_distance(p, Vector2(-32.0, 22.0), Vector2(-14.0, 4.0)) - ring_r
	)
	var right := absf(
		MarkerIcons.segment_distance(p, Vector2(14.0, -4.0), Vector2(32.0, -22.0)) - ring_r
	)
	var links := minf(left, right) - stroke
	var sparks := minf(
		MarkerIcons.segment_distance(p, Vector2(-14.0, -14.0), Vector2(-24.0, -26.0)),
		MarkerIcons.segment_distance(p, Vector2(14.0, 14.0), Vector2(24.0, 26.0))
	)
	return minf(links, sparks - 4.0)
