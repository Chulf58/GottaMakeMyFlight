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
##
## The grid is 256 cells wide (BuildGrid.MAX_SIDE_CELLS), x -128 to 128: the
## first 86 m site in the middle (centre_columns) and 85 m of side land west
## and east of it, which the player buys plot by plot (decision land-west-and-
## east-of-the-site-becomes-buyable-that-side-s-t), so the terminal can grow as
## wide as the build grid allows.

## The grid step out over the edge the road runs along.
const ROAD_STEP := Vector2i(0, 1)
## The grid step out of a door that faces the apron (north).
const PLANE_STEP := Vector2i(0, -1)
## How far a saved grid origin may lie from the site's and still match (JSON
## round trips of floats).
const ORIGIN_TOLERANCE_M := 0.001
## Whether the side land west and east of the first site is for sale
## (LandPlots.open_columns). Opened with the side airside slices (board
## 16f7f8c2, S7c): the side spurs follow what is built (SideSpurs), the whole
## grid is paved at ground_height (grid_rect(), PlaneView.ground_height_at()),
## and a stand with no way onto its lane is refused (StandPlacement.
## reaches_lane()). False locks the side land again: only centre_columns sell.
const SIDE_LAND_OPEN := true

## World position of grid cell (0, 0)'s north-west corner; y is the floor,
## 2 cm above the site's paving.
@export var grid_origin := Vector3(-128.0, 0.22, -210.0)
@export var grid_size := Vector2i(256, 150)
## Height of the site's paving, where the walks outside run.
@export var ground_height := 0.2
## Where a walk in from the road starts: the pavement line along the road
## (z) and its height, straight out from the grid cell the walk enters by.
@export var road_z := -57.0
@export var road_height := 0.1
## Where ReferenceTerminal's cells (and the starter shell) go on this grid:
## the grid grew 110 rows north and 85 columns west, so the starter keeps its
## world place (x -33 to -21, z -98 to -82).
@export var starter_offset := Vector2i(85, 110)
## The land plot columns' widths in cells, west to east (LandPlots); they add
## up to grid_size.x. Each part of the site is cut as evenly as whole cells
## allow, its first columns taking the extra cells (user ruling land-plots-are-
## near-even-columns-of-22-22-21-and-21-m-by-25): the 85 cells of side land
## each way into 22, 21, 21 and 21, the first site's 86 into 22, 22, 21 and 21.
@export var plot_columns := PackedInt32Array([22, 21, 21, 21, 22, 22, 21, 21, 22, 21, 21, 21])
## How many land plot rows lie down the grid, cut as evenly as the columns:
## six rows of 25 down its 150.
@export var plot_rows := 6
## The first site's plot columns (first column, count): x -43 to 43, the land
## a new game starts on (LandPlots).
@export var centre_columns := Vector2i(4, 4)
## Grid cells kept site art stands on, which no walk crosses: the road's sign
## post near (14.1, -59.9) reaches z -60.33, into cell (142, 149).
@export var obstacles: Array[Vector2i] = [Vector2i(142, 149)]


func is_obstacle(cell: Vector2i) -> bool:
	return obstacles.has(cell)


## How many land plots lie across (x) and down (y) the grid.
func plot_counts() -> Vector2i:
	return Vector2i(plot_columns.size(), plot_rows)


## The first site's ground (centre_columns, every row), x as world x and y as
## world z.
func centre_rect() -> Rect2:
	var west := 0
	for i in centre_columns.x:
		west += plot_columns[i]
	var wide := 0
	for i in centre_columns.y:
		wide += plot_columns[centre_columns.x + i]
	return Rect2(Vector2(grid_origin.x + west, grid_origin.z), Vector2(wide, grid_size.y))


## The whole site grid, x as world x and y as world z: the ground the site's
## paving covers and the plane rides on at ground_height
## (PlaneView.ground_height_at()).
func grid_rect() -> Rect2:
	return Rect2(Vector2(grid_origin.x, grid_origin.z), Vector2(grid_size))


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
