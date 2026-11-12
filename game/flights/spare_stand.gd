class_name SpareStand
extends RefCounted
## Where one more gate's stand could be built (board 544f4270, decision
## airline-offers-2-a-day-fit-the-free-gate-slots-1-needs-more). FlightSim asks
## for it when it works out whether another gate would help a flight, so the
## card says "build another gate" only where the player could.
##
## A candidate is the stand straight out from a north exit at a grid cell
## (StandPlacement.for_cell). It counts when the cell is on land the player
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
## row, south first.
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
			var stand := StandPlacement.for_cell(grid, cell)
			if stands.any(
				func(other: Dictionary) -> bool: return GateDesks.stands_overlap(stand, other)
			):
				continue
			if (
				StandEnvelope.blocked_part(grid, site, stand, plane_class)
				== StandEnvelope.Part.CLEAR
			):
				return stand
	return {}
