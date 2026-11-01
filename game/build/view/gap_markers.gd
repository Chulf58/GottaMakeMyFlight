class_name GapMarkers
extends Node3D
## Marks the gaps in the outer wall (EnclosureGaps), so the player sees why a
## building has no roof and passengers will not use it (decision player-
## builds-the-terminal-floor-outer-walls-auto-roof-land-plots-starter-one-
## floor, point 2: "an open gap is shown on screen"). Every gap edge gets a low
## red bar on the floor along the open wall line, all drawn as one multimesh,
## and every run of gap edges gets a wall-gap sign over its middle: an amber
## rounded square with a broken wall in white and the caption "Wall gap" under
## it (user ruling player-built-terminal-roof-tall-5-2-m-roof-with-the-facade-f,
## point 3), so the red "!" keeps meaning a full queue. The sign has the
## queue-full sign's form (decision queue-full-marker-a-red-sign-with-a-queue-
## full-n-waiting-cap): MarkerIcons' rounded square, outline and size, 56 px on
## screen whatever the zoom, with MissMarkers' caption font and outline, both
## billboards drawn over walls and roof (no depth test). The gap captions are
## not part of MissMarkers' declutter layout (decision station-captions-
## declutter-on-screen-overlap-staff-spot-reas). Redrawn when the grid's graph
## changes. View only.
##
## Like BuildView it draws in world space, so it sits at the world origin.

## The bar on each open edge: as long as the edge, this tall and deep.
const BAR_HEIGHT := 0.12
const BAR_DEPTH := 0.16
## The sign's foot stands this high over the run's middle.
const SIGN_LIFT_M := 1.6
const CAPTION := "Wall gap"
const GAP_FILL := Color(0.937, 0.6, 0.137)
## The camera's field of view and the view's height when there is no camera.
const FALLBACK_FOV := 55.0
const FALLBACK_HEIGHT := 1080.0
## Hidden signs kept for reuse when gaps close; any more are freed.
const SPARE_SIGNS := 4

static var _icon: ImageTexture

var _grid: BuildGrid
var _bars := MultiMeshInstance3D.new()
var _signs: Array[Sprite3D] = []
var _shown_signs := 0
## The screen unit the shown signs were last sized for.
var _unit := 0.0
## Where each bar is drawn, kept here because a headless run reads the
## multimesh back as identities.
var _bar_transforms: Array[Transform3D] = []


func _init() -> void:
	_bars.name = "GapBars"
	var bar := BoxMesh.new()
	bar.size = Vector3(1.0, BAR_HEIGHT, BAR_DEPTH)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = MarkerIcons.QUEUE_FILL
	bar.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = bar
	_bars.multimesh = multimesh
	_bars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bars)


## Marks `grid`'s gaps and redraws them whenever its graph changes.
func bind(grid: BuildGrid) -> void:
	if _grid != null and _grid.graph_changed.is_connected(_on_graph_changed):
		_grid.graph_changed.disconnect(_on_graph_changed)
	_grid = grid
	_grid.graph_changed.connect(_on_graph_changed)
	rebuild()


## Draws the bars and signs again from the grid's gaps.
func rebuild() -> void:
	var edges: Array[Vector3i] = []
	var runs: Array[EnclosureGaps.Run] = []
	if _grid != null:
		edges = EnclosureGaps.gap_edges(_grid)
		runs = EnclosureGaps.gap_runs(_grid)
	var multimesh := _bars.multimesh
	multimesh.instance_count = edges.size()
	_bar_transforms.clear()
	for i in edges.size():
		_bar_transforms.append(_bar_transform(edges[i]))
		multimesh.set_instance_transform(i, _bar_transforms[i])
	while _signs.size() < runs.size():
		_signs.append(_make_sign())
	# Keep at most SPARE_SIGNS hidden signs for reuse; free the rest.
	while _signs.size() > runs.size() + SPARE_SIGNS:
		var surplus: Sprite3D = _signs.pop_back()
		remove_child(surplus)
		surplus.queue_free()
	for i in _signs.size():
		var shown := i < runs.size()
		_signs[i].visible = shown
		if shown:
			_signs[i].position = runs[i].centre(_grid) + Vector3(0.0, SIGN_LIFT_M, 0.0)
	_shown_signs = runs.size()
	update_sizes(true)


func strip_count() -> int:
	return _bars.multimesh.instance_count


func sign_count() -> int:
	return _shown_signs


## Where each shown sign's foot stands, in world space.
func sign_positions() -> Array:
	var out := []
	for i in _shown_signs:
		out.append(_signs[i].position)
	return out


## The sign nodes, shown ones first (for probes).
func signs() -> Array[Sprite3D]:
	return _signs


func bar_node() -> MultiMeshInstance3D:
	return _bars


## Each bar's transform in world space (the bar mesh is centred on it).
func bar_transforms() -> Array[Transform3D]:
	return _bar_transforms.duplicate()


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	rebuild()


## A bar centred on the open edge's wall line, lying along it on the floor.
func _bar_transform(edge: Vector3i) -> Transform3D:
	var step: Vector2i = BuildGrid.SIDE_STEP[edge.z]
	var at := _grid.cell_to_world(Vector2i(edge.x, edge.y)) + Vector3(step.x, 0.0, step.y) * 0.5
	at.y += BAR_HEIGHT * 0.5
	var basis := Basis.IDENTITY
	if step.x != 0:
		basis = Basis(Vector3.UP, PI * 0.5)
	return Transform3D(basis, at)


## Keeps the signs MissMarkers.SIGN_PX tall on screen and the captions at
## their font size, as MissMarkers sizes its signs.
func _process(_delta: float) -> void:
	update_sizes()


## Works out the screen unit from the camera's field of view and the rendered
## view's height, and resizes the shown signs only when it changed (or when
## `force`, after the shown set changed).
func update_sizes(force := false) -> void:
	var fov := FALLBACK_FOV
	var height := FALLBACK_HEIGHT
	if is_inside_tree():
		var view := get_viewport()
		var camera := view.get_camera_3d()
		if camera != null:
			fov = camera.fov
		height = view.get_visible_rect().size.y * view.get_stretch_transform().get_scale().y
	# World units per screen pixel at one metre (a fixed-size sprite is drawn
	# as if it stood one metre from the camera).
	var unit := 2.0 * tan(deg_to_rad(fov) / 2.0) / height
	if height > 0.0 and (force or unit != _unit):
		_size_signs(unit)


## Sizes the shown signs for the screen unit `unit`; hidden spares are sized
## when they are shown again.
func _size_signs(unit: float) -> void:
	_unit = unit
	for i in _shown_signs:
		_signs[i].pixel_size = MissMarkers.SIGN_PX * unit / MarkerIcons.SIZE
		(_signs[i].get_node("Caption") as Label3D).pixel_size = unit


## The caption under a sign.
func caption_of(marker: Sprite3D) -> Label3D:
	return marker.get_node("Caption") as Label3D


func _make_sign() -> Sprite3D:
	var marker := Sprite3D.new()
	marker.name = "GapSign"
	marker.texture = wall_gap_icon()
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.fixed_size = true
	marker.no_depth_test = true
	marker.shaded = false
	marker.render_priority = 11
	marker.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	marker.offset = Vector2(0.0, MarkerIcons.SIZE / 2.0)
	var caption := Label3D.new()
	caption.name = "Caption"
	caption.text = CAPTION
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.fixed_size = true
	caption.no_depth_test = true
	caption.render_priority = 12
	caption.outline_render_priority = 11
	caption.font_size = MissMarkers.CAPTION_FONT
	caption.outline_size = MissMarkers.CAPTION_OUTLINE
	caption.outline_modulate = MarkerIcons.OUTLINE
	# Under the sign: its top edge a gap below the sign's foot.
	caption.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	caption.offset = Vector2(0.0, -MissMarkers.CAPTION_GAP_PX)
	marker.add_child(caption)
	add_child(marker)
	return marker


## The wall-gap icon, painted once: MarkerIcons' rounded square and outline
## filled amber, with a white wall line broken in the middle and an arrow
## passing down through the opening, drawn with MarkerIcons.shape_distance and
## segment_distance so the queue-full sign's shape is reused, not copied.
static func wall_gap_icon() -> Texture2D:
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
			var colour := MarkerIcons.OUTLINE.lerp(GAP_FILL, inside)
			var glyph := clampf(0.5 - _broken_wall(p), 0.0, 1.0) * inside
			colour = colour.lerp(MarkerIcons.GLYPH, glyph)
			colour.a = cover
			img.set_pixel(x, y, colour)
	img.generate_mipmaps()
	_icon = ImageTexture.create_from_image(img)
	return _icon


## Signed distance in pixels to the white broken wall. Image y runs down.
static func _broken_wall(p: Vector2) -> float:
	# A thick wall line broken in the middle...
	var wall := minf(
		MarkerIcons.segment_distance(p, Vector2(-36.0, -4.0), Vector2(-17.0, -4.0)),
		MarkerIcons.segment_distance(p, Vector2(17.0, -4.0), Vector2(36.0, -4.0))
	)
	wall -= 9.0
	# ...and an arrow passing down through the opening.
	var shaft := MarkerIcons.segment_distance(p, Vector2(0.0, -34.0), Vector2(0.0, 24.0))
	var head := minf(
		MarkerIcons.segment_distance(p, Vector2(0.0, 30.0), Vector2(-13.0, 15.0)),
		MarkerIcons.segment_distance(p, Vector2(0.0, 30.0), Vector2(13.0, 15.0))
	)
	return minf(wall, minf(shaft, head) - 5.0)
