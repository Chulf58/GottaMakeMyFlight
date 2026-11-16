class_name SideSpurs
extends RefCounted
## Where the west and east spurs run: the one source of each side's spur x, the
## lane_x of every gate's west or east stand (decision side-spur-move-design-
## s7-stands-carry-lane-x-the-wanted-spur). GateDesks and ApronStand both take a
## gate's stand from stand_for_exit(), so they read the same spur.
##
## Slice S7a: side land is locked, so both spurs stay on the floor,
## StandPlacement.SIDE_LANE_X west and east, and nothing moves. Slice S7b
## replaces lane_x() with the wanted spur x that follows the build.


## The world x of `side`'s spur (StandPlacement.WEST or EAST).
static func lane_x(side: String) -> float:
	return StandPlacement.default_lane_x(side)


## The stand of exit door `exit_id` on `grid` (StandPlacement.for_exit()), a
## west or east one on its side's spur (lane_x()); {} for none.
static func stand_for_exit(grid: BuildGrid, exit_id: int) -> Dictionary:
	var stand := StandPlacement.for_exit(grid, exit_id)
	if stand.is_empty() or StandPlacement.side_of(stand) == StandPlacement.NORTH:
		return stand
	return StandPlacement.with_lane_x(stand, lane_x(StandPlacement.side_of(stand)))
