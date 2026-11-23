class_name SpareStand
extends RefCounted
## Where one more gate's stand could be built (board 544f4270, decision
## airline-offers-2-a-day-fit-the-free-gate-slots-1-needs-more). FlightSim asks
## for it when it works out whether another gate would help a flight, so the
## card says "build another gate" only where the player could.
##
## A candidate is the stand straight out from an exit at a grid cell facing
## north, west or east (StandPlacement.for_cell, slice S5 of design airside-
## all-around-technical-design-one-route-source-per-con). Each candidate cell
## is a grid cell, so a west or east stand's sill lies on that cell's outer
## edge, on the grid. It counts when the cell is on land the player
## owns and is not a site obstacle, its small swing square meets none of the
## existing gates' (GateDesks.stands_overlap, the rule a gate desk is refused
## by), and the envelope of the plane class is clear of everything built, the
## site's obstacles and the lane band (StandEnvelope.blocked_part, the rule that
## sets a gate's max_class). Pure: nothing here changes the grid.
##
## Not guaranteed: that an exit door can be placed in a wall at the cell, or
## that the player can afford the floor, walls and desk around it.


## The first stand of `plane_class` that fits on `grid` beside `stands`, or {}
## with none, or when every gate letter is in use. The cells are tried row by
## row, south first, and at each cell the sides in StandPlacement.SIDES order
## (north, west, east). An optional precomputed blocked-cell data dictionary from
## build_prefix() may be passed to reuse across plane classes on the same grid.
static func find(
	grid: BuildGrid, stands: Array[Dictionary], plane_class: String, grid_cache := {}
) -> Dictionary:
	if stands.size() >= GateDesks.LETTERS.length():
		return {}
	var site := GateDesks.site_of(grid)
	var land: LandPlots = (grid as SiteGrid).land if grid is SiteGrid else null
	var bounds := _search_bounds(grid, land)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return {}
	var gw := grid.size.x
	var gh := grid.size.y
	var stride := gw + 1
	var data: Dictionary = grid_cache if not grid_cache.is_empty() else build_prefix(grid, site)
	var prefix: PackedInt32Array = data["prefix"]
	var blocked: PackedByteArray = data["blocked"]
	var steps := _parked_steps(grid)
	var step_n: Vector2i = steps[StandPlacement.NORTH]
	var step_w: Vector2i = steps[StandPlacement.WEST]
	var step_e: Vector2i = steps[StandPlacement.EAST]
	var north_lane_x := PackedByteArray()
	var west_lane_x := PackedByteArray()
	var east_lane_x := PackedByteArray()
	var x_plots := PackedInt32Array()
	north_lane_x.resize(bounds.size.x)
	west_lane_x.resize(bounds.size.x)
	east_lane_x.resize(bounds.size.x)
	x_plots.resize(bounds.size.x)
	for i in bounds.size.x:
		var cell := Vector2i(bounds.position.x + i, bounds.position.y)
		if land != null:
			x_plots[i] = land.plot_of(cell).x
		var ns := StandPlacement.for_cell(grid, cell, 0, StandPlacement.NORTH)
		if StandPlacement.reaches_lane(ns):
			north_lane_x[i] = 1
		var ws := StandPlacement.for_cell(grid, cell, 0, StandPlacement.WEST)
		if StandPlacement.reaches_lane(ws) and StandEnvelope.clears_lane(ws, plane_class):
			west_lane_x[i] = 1
		var es := StandPlacement.for_cell(grid, cell, 0, StandPlacement.EAST)
		if StandPlacement.reaches_lane(es) and StandEnvelope.clears_lane(es, plane_class):
			east_lane_x[i] = 1
	for y in range(bounds.end.y - 1, bounds.position.y - 1, -1):
		var y_plot := land.plot_of(Vector2i(bounds.position.x, y)).y if land != null else 0
		var north_row_ok := StandEnvelope.clears_lane(
			StandPlacement.for_cell(grid, Vector2i(bounds.position.x, y), 0, StandPlacement.NORTH),
			plane_class
		)
		for x in range(bounds.position.x, bounds.end.x):
			var xi := x - bounds.position.x
			var allow_n := north_row_ok and north_lane_x[xi] == 1
			var allow_w := west_lane_x[xi] == 1
			var allow_e := east_lane_x[xi] == 1
			if not allow_n and not allow_w and not allow_e:
				continue
			var cell := Vector2i(x, y)
			if land != null and not land.is_owned(Vector2i(x_plots[xi], y_plot)):
				continue
			if site != null and site.is_obstacle(cell):
				continue
			for side: String in StandPlacement.SIDES:
				var parked: Vector2i
				if side == StandPlacement.NORTH:
					if not allow_n:
						continue
					parked = cell + step_n
				elif side == StandPlacement.WEST:
					if not allow_w:
						continue
					parked = cell + step_w
				else:
					if not allow_e:
						continue
					parked = cell + step_e
				if (
					parked.x >= 0
					and parked.x < gw
					and parked.y >= 0
					and parked.y < gh
					and blocked[parked.y * gw + parked.x] != 0
				):
					continue
				var stand := StandPlacement.for_cell(grid, cell, 0, side)
				if _overlaps_any(stand, stands):
					continue
				var parts := StandEnvelope.rects(stand, plane_class)
				if StandPlacement.reaches_road(grid, parts):
					continue
				var clear := true
				for rect in parts:
					var span := StandPlacement._span_under(grid, rect)
					if span.size.x <= 0 or span.size.y <= 0:
						continue
					var x0 := span.position.x
					var y0 := span.position.y
					var x1 := span.end.x
					var y1 := span.end.y
					var count := (
						prefix[y1 * stride + x1]
						- prefix[y0 * stride + x1]
						- prefix[y1 * stride + x0]
						+ prefix[y0 * stride + x0]
					)
					if count > 0:
						clear = false
						break
				if clear:
					return stand
	return {}


## {"blocked": PackedByteArray, "prefix": PackedInt32Array} of non-apron_clear
## cells on `grid` (stride grid.size.x + 1).
static func build_prefix(grid: BuildGrid, site: SiteDefinition) -> Dictionary:
	var gw := grid.size.x
	var gh := grid.size.y
	var v_stride := gw + 1
	var stride := gw + 1
	var blocked := PackedByteArray()
	blocked.resize(gw * gh)
	var prefix := PackedInt32Array()
	prefix.resize((gh + 1) * stride)
	var floors := grid._floor
	var occupants := grid._occupant
	var h_walls := grid._h_walls
	var v_walls := grid._v_walls
	var has_obs := site != null and not site.obstacles.is_empty()
	if has_obs:
		for cell: Vector2i in site.obstacles:
			if cell.x >= 0 and cell.x < gw and cell.y >= 0 and cell.y < gh:
				blocked[cell.y * gw + cell.x] = 1
	for py in gh:
		var row_base := py * gw
		var v_base := py * v_stride
		var row_sum := 0
		var row_off := (py + 1) * stride
		var prev_off := py * stride
		for px in gw:
			var idx := row_base + px
			var v_idx := v_base + px
			if (
				blocked[idx] != 0
				or floors[idx] != BuildGrid.FLOOR_NONE
				or occupants[idx] != 0
				or h_walls[idx] != 0
				or h_walls[idx + gw] != 0
				or v_walls[v_idx] != 0
				or v_walls[v_idx + 1] != 0
			):
				blocked[idx] = 1
				row_sum += 1
			prefix[row_off + px + 1] = prefix[prev_off + px + 1] + row_sum
	return {"blocked": blocked, "prefix": prefix}


static func _parked_steps(grid: BuildGrid) -> Dictionary:
	@warning_ignore("integer_division")
	var at := Vector2i(grid.size.x / 2, grid.size.y / 2)
	var out := {}
	for side: String in StandPlacement.SIDES:
		var stand := StandPlacement.for_cell(grid, at, 0, side)
		out[side] = grid.world_to_cell(StandPlacement.stand_point(stand)) - at
	return out


static func _search_bounds(grid: BuildGrid, land: LandPlots) -> Rect2i:
	if land == null:
		return Rect2i(Vector2i.ZERO, grid.size)
	var plots := land.owned_plots()
	if plots.is_empty():
		return Rect2i()
	var area := land.plot_cells(plots[0])
	for i in range(1, plots.size()):
		area = area.merge(land.plot_cells(plots[i]))
	return area.intersection(Rect2i(Vector2i.ZERO, grid.size))


static func _overlaps_any(stand: Dictionary, stands: Array[Dictionary]) -> bool:
	for other in stands:
		if GateDesks.stands_overlap(stand, other):
			return true
	return false
