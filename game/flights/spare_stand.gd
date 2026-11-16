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
## (north, west, east).
static func find(grid: BuildGrid, stands: Array[Dictionary], plane_class: String) -> Dictionary:
	if stands.size() >= GateDesks.LETTERS.length():
		return {}
	var site := GateDesks.site_of(grid)
	var land: LandPlots = (grid as SiteGrid).land if grid is SiteGrid else null
	var steps := _parked_steps(grid)
	for y in range(grid.size.y - 1, -1, -1):
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			if land != null and not land.owns_cell(cell):
				continue
			if site != null and site.is_obstacle(cell):
				continue
			for side: String in StandPlacement.SIDES:
				var parked: Vector2i = cell + steps[side]
				if grid.in_bounds(parked) and not StandPlacement.apron_clear(grid, site, parked):
					continue
				var stand := StandPlacement.for_cell(grid, cell, 0, side)
				if _fits(grid, site, stand, stands, plane_class):
					return stand
	return {}


## Each side's step from a candidate cell to the cell under its parked plane's
## stand point. Every class's swing square holds that cell well inside it (the
## nearest edge is NOSE_M away), so a blocked cell there makes blocked_part()
## SWING and find() skips the candidate without building its stand and
## envelope: on a built-over grid nearly every candidate ends here. The step is
## the same for every cell, since for_cell() places a stand by its cell alone.
static func _parked_steps(grid: BuildGrid) -> Dictionary:
	@warning_ignore("integer_division")
	var at := Vector2i(grid.size.x / 2, grid.size.y / 2)
	var out := {}
	for side: String in StandPlacement.SIDES:
		var stand := StandPlacement.for_cell(grid, at, 0, side)
		out[side] = grid.world_to_cell(StandPlacement.stand_point(stand)) - at
	return out


## Whether `stand` meets none of `stands`' swing squares and its `plane_class`
## envelope is clear on `grid`.
static func _fits(
	grid: BuildGrid,
	site: SiteDefinition,
	stand: Dictionary,
	stands: Array[Dictionary],
	plane_class: String
) -> bool:
	if stands.any(func(other: Dictionary) -> bool: return GateDesks.stands_overlap(stand, other)):
		return false
	return StandEnvelope.blocked_part(grid, site, stand, plane_class) == StandEnvelope.Part.CLEAR
