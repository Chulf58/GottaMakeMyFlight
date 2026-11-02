class_name SiteDefinition
extends Resource
## The airport site the player builds the terminal on, as the game's rules
## see it, authored in build/terminal_site.tres against tp_airport_site.glb
## (decision player-built-terminal-technical-design-site-plot-indoor-mask-
## passenger-eligibility, point 1): the build grid's frame, where the walks
## outside join the road, the starter terminal's place and the kept site
## obstacles.
##
## The road runs past the grid's south edge (+z, ROAD_STEP). The grid reaches
## north to z -210 (decision plane-stand-design-airside-moves-110-m-north-
## stand-snaps-to, point 1), and the plane stand lies on it, straight out from
## a north-facing exit (-z, PLANE_STEP; StandPlacement), with the taxi lane
## beyond the north edge. Passengers walk the site's open ground between the
## road, the doors and the plane (SiteRoutes).

## The grid step out over the edge the road runs along.
const ROAD_STEP := Vector2i(0, 1)
## The grid step out of a door that faces the apron (north).
const PLANE_STEP := Vector2i(0, -1)
## How far a saved grid origin may lie from the site's and still match (JSON
## round trips of floats).
const ORIGIN_TOLERANCE_M := 0.001

## World position of grid cell (0, 0)'s north-west corner; y is the floor,
## 2 cm above the site's paving.
@export var grid_origin := Vector3(-43.0, 0.22, -210.0)
@export var grid_size := Vector2i(86, 150)
## Height of the site's paving, where the walks outside run.
@export var ground_height := 0.2
## Where a walk in from the road starts: the pavement line along the road
## (z) and its height, straight out from the grid cell the walk enters by.
@export var road_z := -57.0
@export var road_height := 0.1
## Where ReferenceTerminal's cells (and the starter shell) go on this grid:
## the grid grew 110 rows north, so the starter keeps its world place (x -33
## to -21, z -98 to -82).
@export var starter_offset := Vector2i(0, 110)
## How many land plots lie across (x) and down (y) the grid (LandPlots, user
## ruling land-plots-are-near-even-columns-of-22-22-21-and-21-m-by-25): the
## site is cut as evenly as whole cells allow, the first columns or rows taking
## the extra cells. The 86x150 site's 4 by 6 plots are columns of 22, 22, 21
## and 21 cells by rows of 25.
@export var plot_counts := Vector2i(4, 6)
## Grid cells kept site art stands on, which no walk crosses: the road's sign
## post near (14.1, -59.9) reaches z -60.33, into cell (57, 149).
@export var obstacles: Array[Vector2i] = [Vector2i(57, 149)]


func is_obstacle(cell: Vector2i) -> bool:
	return obstacles.has(cell)


## Why a BuildGrid.to_snapshot() dictionary cannot be loaded on this site, or
## "": BuildGridSnapshot.problem()'s structure check, then the grid frame,
## which must be the site's size and origin.
func snapshot_problem(data: Dictionary) -> String:
	var problem := BuildGridSnapshot.problem(data)
	if problem != "":
		return problem
	var saved_size := Vector2i(int(data["width"]), int(data["height"]))
	if not data.has("origin") or saved_size != grid_size:
		return "the grid was saved in another frame than the site's"
	var saved: Array = data["origin"]
	if Vector3(saved[0], saved[1], saved[2]).distance_to(grid_origin) > ORIGIN_TOLERANCE_M:
		return "the grid was saved in another frame than the site's"
	return ""
