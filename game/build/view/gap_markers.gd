class_name GapMarkers
extends Node3D
## Marks the gaps in the outer wall (EnclosureGaps), so the player sees why a
## building has no roof and passengers will not use it (decision player-
## builds-the-terminal-floor-outer-walls-auto-roof-land-plots-starter-one-
## floor, point 2: "an open gap is shown on screen"). Every gap edge gets a low
## red bar on the floor along the open wall line, all drawn as one multimesh,
## and every run of gap edges gets the red "!" sign (MarkerIcons, the form of
## the queue-full marker, decision queue-full-marker-a-red-sign-with-a-queue-
## full-n-waiting-cap) over its middle. The sign is a billboard drawn over the
## world (no depth test) at one screen size, like MissMarkers, so it reads at
## every zoom. Redrawn when the grid's graph changes. View only.
##
## Like BuildView it draws in world space, so it sits at the world origin.

## The bar on each open edge: as long as the edge, this tall and deep.
const BAR_HEIGHT := 0.12
const BAR_DEPTH := 0.16
## The sign's foot stands this high over the run's middle.
const SIGN_LIFT_M := 1.6
## The sign's height on screen for a 1080-pixel-tall view.
const SIGN_PX := 48.0
const REFERENCE_HEIGHT := 1080.0

var _grid: BuildGrid
var _bars := MultiMeshInstance3D.new()
var _signs: Array[Sprite3D] = []
var _shown_signs := 0
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
	for i in _signs.size():
		var shown := i < runs.size()
		_signs[i].visible = shown
		if shown:
			_signs[i].position = runs[i].centre(_grid) + Vector3(0.0, SIGN_LIFT_M, 0.0)
	_shown_signs = runs.size()


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


func _make_sign() -> Sprite3D:
	var marker := Sprite3D.new()
	marker.name = "GapSign"
	marker.texture = MarkerIcons.queue_full()
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.fixed_size = true
	marker.no_depth_test = true
	marker.shaded = false
	marker.render_priority = 11
	marker.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	marker.offset = Vector2(0.0, MarkerIcons.SIZE / 2.0)
	marker.pixel_size = SIGN_PX / REFERENCE_HEIGHT / MarkerIcons.SIZE
	add_child(marker)
	return marker
