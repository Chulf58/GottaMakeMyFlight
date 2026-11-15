class_name OwnedPaving
extends Node
## Shows the terminal site's grey paving on exactly the land plots the player
## owns (decision site-paving-covers-only-the-owned-land-plots-and-grows-as-ea):
## the site asset (tp_airport_site.glb, built by tools/blender/terminal_site/
## build_terminal_site.py) holds one paving mesh per land plot, named
## Lot_<column>_<row> as LandPlots numbers them, and this shows each one while
## its plot is owned. It looks again whenever the land changes, so a bought
## plot is paved at once and a load repaves from the saved ownership. A plot
## not owned shows the grass under it, with the Buy land tool's fill and price
## (LandTool). Visual only: nothing in the sim reads it. Prison Architect and
## SimAirport also show land the player has not bought as plain ground.
##
## Each plot side that faces another plot has a kerb mesh of its own,
## Lot_<column>_<row>_<N, E, S or W>, a dark skirt from the paving down into
## the grass. A kerb shows only while its plot is owned and the plot across
## that side is not, so touching owned plots pave as one surface with no line
## between them (user ruling touching-owned-land-plots-pave-as-one-seamless-
## surface-no-lin): a kerb drawn between two owned plots shows its toon outline
## as a thin dark line across the paving.

## The name every plot's paving and kerb mesh starts with.
const PREFIX := "Lot_"
## A kerb name's last part, by side, in LandPlots.EDGE_STEPS order.
const SIDES := ["N", "E", "S", "W"]

## The site asset's root, as main.tscn places it.
@export var site: Node3D
## Its land_tool's land is the land shown.
@export var build_mode: BuildMode

## The land shown, or null before bind().
var land: LandPlots = null
## Plot -> its paving mesh (plot_meshes()).
var _meshes := {}
## Vector3i(column, row, side) -> its kerb mesh (kerb_meshes()).
var _kerbs := {}


func _ready() -> void:
	if site == null or build_mode == null:
		push_error("OwnedPaving: site or build_mode is not set; the site stays fully paved")
		return
	if build_mode.land_tool == null or build_mode.land_tool.land == null:
		push_error("OwnedPaving: BuildMode has no land plots; the site stays fully paved")
		return
	bind(site, build_mode.land_tool.land)


## Shows `site_root`'s plot paving for `plots`, now and on every change of it.
func bind(site_root: Node, plots: LandPlots) -> void:
	if land != null and land.changed.is_connected(refresh):
		land.changed.disconnect(refresh)
	_meshes = plot_meshes(site_root)
	_kerbs = kerb_meshes(site_root)
	if _meshes.size() != plots.plots.x * plots.plots.y:
		push_error(
			(
				"OwnedPaving: the site has %d plot paving meshes for %d plots"
				% [_meshes.size(), plots.plots.x * plots.plots.y]
			)
		)
	land = plots
	land.changed.connect(refresh)
	refresh()


## Shows each plot's paving exactly while the land owns the plot, and each
## kerb exactly while its plot is owned and the plot across its side is not.
func refresh() -> void:
	for plot: Vector2i in _meshes:
		(_meshes[plot] as Node3D).visible = land.is_owned(plot)
	for key: Vector3i in _kerbs:
		var plot := Vector2i(key.x, key.y)
		var open := not land.is_owned(plot + LandPlots.EDGE_STEPS[key.z])
		(_kerbs[key] as Node3D).visible = land.is_owned(plot) and open


## Plot (column, row) -> the site's paving mesh for it, for every mesh under
## `site_root` named PREFIX + "<column>_<row>".
static func plot_meshes(site_root: Node) -> Dictionary:
	var out := {}
	for node in site_root.find_children(PREFIX + "*", "MeshInstance3D", true, false):
		var parts := String(node.name).trim_prefix(PREFIX).split("_")
		if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			out[Vector2i(int(parts[0]), int(parts[1]))] = node
	return out


## Vector3i(column, row, side) -> the site's kerb mesh on that side of that
## plot (side 0 N, 1 E, 2 S, 3 W), for every mesh under `site_root` named
## PREFIX + "<column>_<row>_<N, E, S or W>".
static func kerb_meshes(site_root: Node) -> Dictionary:
	var out := {}
	for node in site_root.find_children(PREFIX + "*", "MeshInstance3D", true, false):
		var parts := String(node.name).trim_prefix(PREFIX).split("_")
		if parts.size() == 3 and parts[0].is_valid_int() and parts[1].is_valid_int():
			var side := SIDES.find(parts[2])
			if side >= 0:
				out[Vector3i(int(parts[0]), int(parts[1]), side)] = node
	return out
