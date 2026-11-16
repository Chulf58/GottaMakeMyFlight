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
	for y in range(grid.size.y - 1, -1, -1):
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			if land != null and not land.owns_cell(cell):
				continue
			if site != null and site.is_obstacle(cell):
				continue
			for side: String in StandPlacement.SIDES:
				var stand := StandPlacement.for_cell(grid, cell, 0, side)
				if _fits(grid, site, stand, stands, plane_class):
					return stand
	return {}


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
