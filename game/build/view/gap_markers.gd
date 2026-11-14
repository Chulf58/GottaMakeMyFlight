class_name GapMarkers
extends Node3D
## Marks the gaps in the outer wall (EnclosureGaps), so the player sees why a
## building has no roof and passengers will not use it (decision player-
## builds-the-terminal-floor-outer-walls-auto-roof-land-plots-starter-one-
## floor, point 2: "an open gap is shown on screen"). Every gap edge gets a low
## red bar on the floor along the open wall line, all drawn as one multimesh,
## and every run of gap edges gets a wall-gap sign over its middle: MarkerIcons'
## build-hint disc with the broken-wall glyph (MarkerIcons.Glyph.WALL_GAP),
## MissMarkers.SIGN_PX on screen whatever the zoom, drawn over walls and roof
## (no depth test). It has no caption (decision calm-cozy-default-view-quiet-
## world-detail-on-ask-soft-statio, part 2): a wall gap is a build hint, so its
## words (HOVER_TEXT) show in the HoverTarget tooltip only in build mode, through
## hover_signs(). The sign itself stays outside build mode, small and soft.
## Redrawn when the grid's graph changes. View only.
##
## Like BuildView it draws in world space, so it sits at the world origin.

## The bar on each open edge: as long as the edge, this tall and deep.
const BAR_HEIGHT := 0.12
const BAR_DEPTH := 0.16
const BAR_FILL := Color(0.847, 0.263, 0.231)
## The sign's foot stands this high over the run's middle.
const SIGN_LIFT_M := 1.6
const HOVER_TEXT := "Wall gap · close the outer wall so the roof can go on"
## The camera's field of view and the view's height when there is no camera.
const FALLBACK_FOV := 55.0
const FALLBACK_HEIGHT := 1080.0
## Hidden signs kept for reuse when gaps close; any more are freed.
const SPARE_SIGNS := 4

## The build mode whose grid's gaps are marked; main.tscn sets it, and
## _ready() binds its grid.
@export var build_mode: BuildMode
## Unset, the first BuildSession in the tree is taken, looked for until found: the
## hover text shows only while it is active.
var build_session: BuildSession

var _grid: BuildGrid
var _bars := MultiMeshInstance3D.new()
var _signs: Array[Sprite3D] = []
var _shown_signs := 0
## Each shown sign's stable hover key: its run's first edge (cell, side) and length.
var _run_keys: Array[Vector4i] = []
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
	material.albedo_color = BAR_FILL
	bar.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = bar
	_bars.multimesh = multimesh
	_bars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bars)


func _ready() -> void:
	if build_mode != null:
		bind(build_mode.grid)
	var hover := HoverTarget.find(get_tree())
	if hover != null:
		hover.register_provider(self)


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
	_run_keys.clear()
	for run in runs:
		_run_keys.append(Vector4i(run.cell.x, run.cell.y, run.side, run.length))
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


## The HoverTarget provider contract: in build mode, every shown sign's screen
## rect this frame (viewport px) and HOVER_TEXT; nothing outside build mode.
func hover_signs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_inside_tree() or not is_building():
		return out
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return out
	var side := MissMarkers.SIGN_PX / get_viewport().get_stretch_transform().get_scale().y
	for i in _shown_signs:
		if camera.is_position_behind(_signs[i].global_position):
			continue
		var foot := camera.unproject_position(_signs[i].global_position)
		(
			out
			. append(
				{
					"key": _run_keys[i],
					"rect": Rect2(foot.x - side / 2.0, foot.y - side, side, side),
					"text": HOVER_TEXT,
				}
			)
		)
	return out


## True while build mode lasts (build_session, else the first BuildSession in
## the tree, looked for until one is found).
func is_building() -> bool:
	if build_session == null and is_inside_tree():
		build_session = MissMarkers.find_session(get_tree())
	return build_session != null and build_session.active


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


## Keeps the signs MissMarkers.SIGN_PX tall on screen, as MissMarkers sizes
## its signs.
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


func _make_sign() -> Sprite3D:
	var marker := Sprite3D.new()
	marker.name = "GapSign"
	marker.texture = wall_gap_icon()
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.fixed_size = true
	marker.no_depth_test = true
	marker.shaded = false
	marker.render_priority = MissMarkers.SIGN_PRIORITY
	marker.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	marker.offset = Vector2(0.0, MarkerIcons.SIZE / 2.0)
	add_child(marker)
	return marker


## The wall-gap icon: MarkerIcons' build-hint disc with the broken-wall glyph.
static func wall_gap_icon() -> Texture2D:
	return MarkerIcons.icon(MarkerIcons.Glyph.WALL_GAP)
