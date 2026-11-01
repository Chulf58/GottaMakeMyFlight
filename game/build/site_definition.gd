class_name SiteDefinition
extends Resource
## The airport site the player builds the terminal on, as the game's rules
## see it, authored in build/terminal_site.tres against tp_airport_site.glb
## (decision player-built-terminal-technical-design-site-plot-indoor-mask-
## passenger-eligibility, point 1): the build grid's frame, where the walks
## outside join the road and the plane, and the kept site obstacles.
##
## The road runs past the grid's south edge (+z, ROAD_STEP) and the apron and
## the parked plane lie beyond its north edge (-z, PLANE_STEP). Passengers
## walk the site's open ground between them (SiteRoutes).

## The grid step out over the edge the road runs along.
const ROAD_STEP := Vector2i(0, 1)
## The grid step out over the edge the apron lies beyond.
const PLANE_STEP := Vector2i(0, -1)
## How far a saved grid origin may lie from the site's and still match (JSON
## round trips of floats).
const ORIGIN_TOLERANCE_M := 0.001

## World position of grid cell (0, 0)'s north-west corner; y is the floor,
## 2 cm above the site's paving.
@export var grid_origin := Vector3(-43.0, 0.22, -100.0)
@export var grid_size := Vector2i(86, 40)
## Height of the site's paving, where the walks outside run.
@export var ground_height := 0.2
## Where a walk in from the road starts: the pavement line along the road
## (z) and its height, straight out from the grid cell the walk enters by.
@export var road_z := -57.0
@export var road_height := 0.1
## The walk from the grid's north edge to the plane door, world points: along
## the gap between the site and the parked plane's nose, then out to its port
## door (the plane at the stand at (-18, 0, -117) spans x -32.2 to -3.8 with
## its wings).
@export
var plane_route := PackedVector3Array([Vector3(-14.5, 0.0, -101.0), Vector3(-14.5, 0.0, -106.5)])
## Grid cells kept site art stands on, which no walk crosses: the road's sign
## post near (14.1, -59.9) reaches z -60.33, into cell (57, 39).
@export var obstacles: Array[Vector2i] = [Vector2i(57, 39)]


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
