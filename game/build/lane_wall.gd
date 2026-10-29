class_name LaneWall
extends RefCounted
## The rule that a security lane part is not placed across a wall (decision
## a-security-lane-part-placed-across-the-security-divider-wall). A lane's
## geometry (SecurityLanes.geometry) names the cells passengers, trays and
## officers step between; a plain or glass wall on any of those edges breaks
## the lane, and the player is told so at the placement rather than when the
## lane stays incomplete (smoke playtest 8: a lane in the hall below the starter
## terminal's divider put its exit and helper spot beyond the wall). The
## placement is refused with LANE_WALL and no wall is ever removed for it.
##
## Any plain or glass wall counts, not only the divider: the grid stores no
## divider, and a wall across a lane breaks it the same way. A door wall is a
## way through and does not count.
##
## An arch is refused when every mirror of its lane (RIGHT and LEFT) has a
## walled edge, because one clear side is enough for a lane. A part is refused
## when every lane an arch beside it could give it (the same facing, the part's
## cell where that lane puts the part) has a wall on a step into the part's own
## cell, so a part is not blamed for a wall elsewhere in the lane. A part no
## arch could own is not checked: it may be placed first and the arch after.

## The pairs of neighbouring lane cells a step crosses, by geometry() key: the
## parts and what they serve, the conveyor, the passage, the queue, the
## repack berth, the exit and the officers' spots. The return route's steps
## are added in walled_edge().
const EDGES := [
	["tray_table", "unpack"],
	["xray_belt", "arch"],
	["pickup_table", "pickup"],
	["tray_table", "xray_belt"],
	["xray_belt", "pickup_table"],
	["unpack", "arch"],
	["arch", "pickup"],
	["queue_entry", "unpack"],
	["berth", "pickup"],
	["exit", "pickup"],
	["primary_spot", "xray_belt"],
	["helper_spot", "berth"],
]


## LANE_WALL when placing a lane part by `edit` would put it across a wall,
## else null.
static func problem(grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	if edit.kind != BuildEdit.Kind.PLACE_OBJECT or not SecurityLanes.is_part(edit.def_id):
		return null
	var lanes := _candidates(grid, edit)
	if lanes.is_empty():
		return null
	var only := BuildObjectDef.NO_CELL if edit.def_id == SecurityLanes.ARCH else edit.cell
	for lane in lanes:
		if not walled_edge(grid, lane, only):
			return null
	return BuildResult.refused(BuildResult.Reason.LANE_WALL)


## Whether a plain or glass wall stands on a step of `lane` (geometry()): any
## step, or with `only` set, a step that starts or ends at that cell.
static func walled_edge(grid: BuildGrid, lane: Dictionary, only := BuildObjectDef.NO_CELL) -> bool:
	var steps: Array = []
	for pair in EDGES:
		steps.append([lane[pair[0]], lane[pair[1]]])
	var from: Vector2i = lane["berth"]
	for cell: Vector2i in lane["return_route"]:
		steps.append([from, cell])
		from = cell
	steps.append([from, lane["unpack"]])
	for step in steps:
		if only != BuildObjectDef.NO_CELL and step[0] != only and step[1] != only:
			continue
		var side := BuildGrid.SIDE_STEP.find((step[1] as Vector2i) - (step[0] as Vector2i))
		var kind := grid.wall_kind(step[0], side)
		if kind == BuildGrid.WallKind.PLAIN or kind == BuildGrid.WallKind.GLASS:
			return true
	return false


## The lanes placing `edit` could belong to: both mirrors of an arch placed
## here, or, for another part, each lane of an arch of the same facing that
## puts this part at the edit's cell.
static func _candidates(grid: BuildGrid, edit: BuildEdit) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if edit.def_id == SecurityLanes.ARCH:
		for mirror in SecurityLanes.MIRRORS:
			out.append(SecurityLanes.geometry(edit.cell, edit.facing, mirror))
		return out
	for id in grid.object_ids():
		var arch := grid.get_object(id)
		if StringName(arch["def"]) != SecurityLanes.ARCH or arch["facing"] != edit.facing:
			continue
		for mirror in SecurityLanes.MIRRORS:
			var lane := SecurityLanes.geometry(arch["anchor"], arch["facing"], mirror)
			if lane[edit.def_id] == edit.cell:
				out.append(lane)
	return out
