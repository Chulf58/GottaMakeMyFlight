class_name BusBays
extends RefCounted
## The 16 x 6 m parallel-to-wall bus bay outside each bus gate's exit door
## (tp_bus_01a.glb is 3.28 x 13.31 m). Pure: nothing here changes the grid.

const BAY_LENGTH_M := 16.0
const BAY_WIDTH_M := 6.0


## World xz rectangle for the bus bay outside `stand`'s exit door, or empty
## Rect2() when `stand` is empty or invalid.
static func bay_rect(stand: Dictionary) -> Rect2:
	if stand.is_empty():
		return Rect2()
	var x := float(stand.get("x", 0.0))
	var z := float(stand.get("wall_z", 0.0))
	match StandPlacement.side_of(stand):
		StandPlacement.NORTH:
			return Rect2(x - 0.5 * BAY_LENGTH_M, z - BAY_WIDTH_M, BAY_LENGTH_M, BAY_WIDTH_M)
		StandPlacement.WEST:
			return Rect2(x - BAY_WIDTH_M, z - 0.5 * BAY_LENGTH_M, BAY_WIDTH_M, BAY_LENGTH_M)
		StandPlacement.EAST:
			return Rect2(x, z - 0.5 * BAY_LENGTH_M, BAY_WIDTH_M, BAY_LENGTH_M)
	return Rect2()


## True when `stand`'s 16 x 6 m bay is on the apron, clear of terminal cells,
## walls extending into the bay, road/lane/runway zones, other bus bays, and
## existing stand envelopes.
static func bay_clear(
	grid: BuildGrid,
	site: SiteDefinition,
	stand: Dictionary,
	other_bays: Array[Rect2] = [],
	blocked_envelopes: Array[Rect2] = []
) -> bool:
	var bay := bay_rect(stand)
	if not bay.has_area():
		return false
	if not _bounds_clear(grid, bay):
		return false
	if not _ground_clear(grid, site, stand, bay):
		return false
	return not _rects_overlap(bay, other_bays) and not _rects_overlap(bay, blocked_envelopes)


## In-bounds cells under `bay`.
static func bay_cells(grid: BuildGrid, bay: Rect2) -> Dictionary:
	return StandPlacement.cells_under(grid, [bay])


## True when `edit` places a wall strictly along the terminal sill edge of
## `stand`'s bus bay (such as closing a removed exit door or extending the
## terminal wall), never protruding into the bay.
static func is_bay_sill_wall(grid: BuildGrid, stand: Dictionary, edit: BuildEdit) -> bool:
	if edit.kind != BuildEdit.Kind.PLACE_WALL or stand.is_empty():
		return false
	var bay := bay_rect(stand)
	if not bay.has_area():
		return false
	var span := StandPlacement._span_under(grid, bay)
	var side := StandPlacement.side_of(stand)
	var other := edit.cell + BuildGrid.SIDE_STEP[edit.side]
	var opp := (edit.side + 2) % 4
	return (
		(span.has_point(edit.cell) and _is_terminal_sill_wall(edit.cell, span, side, edit.side))
		or (span.has_point(other) and _is_terminal_sill_wall(other, span, side, opp))
	)


## Bus gate letter -> bay Rect2 for every bus-gate binding on `grid`.
static func bays_for(grid: BuildGrid, bindings: Array[Dictionary]) -> Dictionary:
	var out := {}
	if grid == null:
		return out
	for binding in bindings:
		if bool(binding.get("is_bus_gate", false)):
			var stand := StandPlacement.for_exit(grid, int(binding["exit"]))
			var bay := bay_rect(stand)
			if bay.has_area():
				out[String(binding["gate"])] = bay
	return out


## Array of bay Rect2s for every bus-gate binding on `grid`.
static func bay_rects_for(grid: BuildGrid, bindings: Array[Dictionary]) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for bay: Rect2 in bays_for(grid, bindings).values():
		out.append(bay)
	return out


## Nearest free N/W/E exit within GateDesks.LINK_CELLS of `footprint` with a
## clear 16 x 6 m bus bay, or 0 for none.
static func nearest_bus_exit(
	grid: BuildGrid,
	footprint: Array[Vector2i],
	taken: Dictionary,
	other_bays: Array[Rect2],
	blocked_envelopes: Array[Rect2]
) -> int:
	var site := (grid as SiteGrid).site if grid is SiteGrid else null
	for exit_id in GateDesks.exits_in_reach(grid, footprint):
		if taken.has(exit_id):
			continue
		var stand := StandPlacement.for_exit(grid, exit_id)
		if bay_clear(grid, site, stand, other_bays, blocked_envelopes):
			return exit_id
	return 0


## Yellow/white painted curb marking mesh placed just above the apron for a bus
## bay rectangle.
static func make_marking_mesh(bay: Rect2) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.78, 0.22, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.8
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	var min_x := bay.position.x + 0.35
	var max_x := bay.end.x - 0.35
	var min_z := bay.position.y + 0.35
	var max_z := bay.end.y - 0.35
	var t := 0.22
	var y := 0.03
	_add_quad(im, min_x, min_z, max_x, min_z + t, y)
	_add_quad(im, min_x, max_z - t, max_x, max_z, y)
	_add_quad(im, min_x, min_z + t, min_x + t, max_z - t, y)
	_add_quad(im, max_x - t, min_z + t, max_x, max_z - t, y)
	im.surface_end()
	var node := MeshInstance3D.new()
	node.name = "BusBayMarking"
	node.mesh = im
	return node


static func _bounds_clear(grid: BuildGrid, bay: Rect2) -> bool:
	var rects: Array[Rect2] = [bay]
	if StandPlacement.reaches_road(grid, rects):
		return false
	var shrunk := bay.grow(-0.01)
	if shrunk.intersects(StandPlacement.lane_zone()):
		return false
	if shrunk.intersects(StandPlacement.runway_zone()):
		return false
	return true


static func _ground_clear(
	grid: BuildGrid, site: SiteDefinition, stand: Dictionary, bay: Rect2
) -> bool:
	var span := StandPlacement._span_under(grid, bay)
	var side := StandPlacement.side_of(stand)
	for y in range(span.position.y, span.end.y):
		for x in range(span.position.x, span.end.x):
			var cell := Vector2i(x, y)
			if not _cell_clear(grid, site, cell, span, side):
				return false
	return true


static func _cell_clear(
	grid: BuildGrid, site: SiteDefinition, cell: Vector2i, span: Rect2i, side: String
) -> bool:
	if grid.floor_at(cell) != BuildGrid.FLOOR_NONE or grid.object_at(cell) != 0:
		return false
	if site != null and site.is_obstacle(cell):
		return false
	for wall_side in 4:
		if not grid.has_wall(cell, wall_side):
			continue
		if _is_terminal_sill_wall(cell, span, side, wall_side):
			continue
		return false
	return true


static func _is_terminal_sill_wall(
	cell: Vector2i, span: Rect2i, side: String, wall_side: int
) -> bool:
	match side:
		StandPlacement.NORTH:
			return cell.y == span.end.y - 1 and wall_side == BuildGrid.Side.SOUTH
		StandPlacement.WEST:
			return cell.x == span.end.x - 1 and wall_side == BuildGrid.Side.EAST
		StandPlacement.EAST:
			return cell.x == span.position.x and wall_side == BuildGrid.Side.WEST
	return false


static func _rects_overlap(bay: Rect2, others: Array[Rect2]) -> bool:
	var shrunk := bay.grow(-0.01)
	for other in others:
		if shrunk.intersects(other):
			return true
	return false


static func _add_quad(
	im: ImmediateMesh, x0: float, z0: float, x1: float, z1: float, y: float
) -> void:
	im.surface_add_vertex(Vector3(x0, y, z0))
	im.surface_add_vertex(Vector3(x1, y, z0))
	im.surface_add_vertex(Vector3(x1, y, z1))
	im.surface_add_vertex(Vector3(x0, y, z0))
	im.surface_add_vertex(Vector3(x1, y, z1))
	im.surface_add_vertex(Vector3(x0, y, z1))
