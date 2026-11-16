class_name TaxiRoutes
extends RefCounted
## The one route definition (decision airside-all-around-technical-design-one-
## route-source-per-con, slice S0): every phase path a plane follows, built
## from the Airside waypoints, the stand and the lane layout. FlightGround plans
## the taxi bookings on these paths, Airside.phase_path() gives them to the
## drawn planes, and TaxiPaving paves Airside.taxi_routes(), which are these
## too, so the planned and the drawn movement cannot differ. Pure: no node is
## built.
##
## Planes land and take off eastbound (decision runway-and-taxi-technical-
## design-movement-plan-analytic-bookings-planned-pauses, point 1), so a plane
## taxis in from RunwayExit up the east stub to the lane's east end, west along
## the lane to its stand's join, south to its pushback's end and on to the stand;
## it taxis out from the pushback's end north to the join, west to the lane's
## west end and down the west stub to RunwayEntry. Every taxi route runs west
## along the lane, so a north stand's join must lie strictly between the lane's
## ends (joins_lane()); Airside refuses a stand whose join does not. The routes
## leave out the other stands' joins they pass, straight points on the lane
## that change no length, corner or slice.
##
## The layout (slice S4, board airside-all-around-s4) has two two-way spurs
## that run the stubs on south of the lane, at its ends. A west or east stand's
## join lies on its side's spur (StandPlacement.lane_join(), SIDE_LANE_X), and
## spur_of() tells which from the join alone. A west stand taxis in along the
## whole lane and south down the west spur, and out north up the spur straight
## on to the west stub. An east stand taxis in straight on from the east stub
## down the east spur, and out north up the spur and west along the lane. So the
## lane stays westbound, every segment runs along x or z, and inbound and
## outbound planes share each spur, which GroundPlanner books in time.
##
## The layout is {"west_x", "east_x", "lane_z"}: the x of the lane's west and
## east ends, where it meets the runway stubs and the spurs, and the lane's z.
## Production has the north lane with its spurs at the TaxiWest and TaxiEast
## waypoints (north_only()); later slices of the same decision move the ends.

## The paths of the phases a plane moves in, by FlightSim.State.
const MOVING_STATES: Array[int] = [
	FlightSim.State.APPROACH,
	FlightSim.State.LANDING,
	FlightSim.State.TAXI_IN,
	FlightSim.State.PUSHBACK,
	FlightSim.State.TAXI_OUT,
	FlightSim.State.TAKEOFF,
]
## A join this close to a lane end's x or the lane's z is on that line.
const SAME_M := 0.01


## The layout of the north lane and its spurs: its ends at the TaxiWest and
## TaxiEast waypoints of `points` (name -> position), and its z at TaxiWest.
static func north_only(points: Dictionary) -> Dictionary:
	var west: Vector3 = points[&"TaxiWest"]
	return {"west_x": west.x, "east_x": (points[&"TaxiEast"] as Vector3).x, "lane_z": west.z}


## The three route points of StandPlacement stand `stand`: "spot" (where the
## plane parks), "back" (where its pushback ends) and "join" (where its way
## north meets the lane).
static func stand_ends(stand: Dictionary) -> Dictionary:
	return {
		"spot": StandPlacement.stand_point(stand),
		"back": StandPlacement.pushback_end(stand),
		"join": StandPlacement.lane_join(stand),
	}


## Whether `join` lies on the lane strictly between the ends of `layout`, or on
## one of its spurs (spur_of()). East of the east end or west of the west end a
## route to it would turn back along the lane, and on an end it would add a
## zero-length step.
static func joins_lane(join: Vector3, layout: Dictionary) -> bool:
	if spur_of(join, layout) != StandPlacement.NORTH:
		return true
	if absf(join.z - float(layout["lane_z"])) > SAME_M:
		return false
	return join.x > float(layout["west_x"]) and join.x < float(layout["east_x"])


## The spur `join` lies on: StandPlacement.WEST or EAST when it is at that end's
## x and south of the lane, else NORTH (on the lane, or on no taxiway).
static func spur_of(join: Vector3, layout: Dictionary) -> String:
	if join.z <= float(layout["lane_z"]) + SAME_M:
		return StandPlacement.NORTH
	if absf(join.x - float(layout["west_x"])) <= SAME_M:
		return StandPlacement.WEST
	if absf(join.x - float(layout["east_x"])) <= SAME_M:
		return StandPlacement.EAST
	return StandPlacement.NORTH


## Each moving phase's path (MOVING_STATES -> PackedVector3Array) for a plane of
## `plane_class` at the stand whose route points are `ends` (stand_ends()),
## from the waypoints `points` (name -> position) and the lane `layout`. The
## class picks the approach, touchdown and liftoff points (Airside.
## class_point()); the taxi routes are the same for every class. A join on a
## spur (spur_of()) gives that side's routes.
static func phase_paths(
	points: Dictionary, ends: Dictionary, plane_class: String, layout: Dictionary
) -> Dictionary:
	var at := func(base: StringName) -> Vector3:
		return points[Airside.class_point(base, plane_class)]
	var exit: Vector3 = points[&"RunwayExit"]
	var entry: Vector3 = points[&"RunwayEntry"]
	var east: Vector3 = points[&"TaxiEast"]
	var west: Vector3 = points[&"TaxiWest"]
	east.x = layout["east_x"]
	west.x = layout["west_x"]
	var spot: Vector3 = ends["spot"]
	var back: Vector3 = ends["back"]
	var join: Vector3 = ends["join"]
	var taxi_in := PackedVector3Array([exit, east, join, back, spot])
	var taxi_out := PackedVector3Array([back, join, west, entry])
	match spur_of(join, layout):
		StandPlacement.WEST:
			taxi_in = PackedVector3Array([exit, east, west, join, back, spot])
		StandPlacement.EAST:
			taxi_out = PackedVector3Array([back, join, east, west, entry])
	return {
		FlightSim.State.APPROACH:
		PackedVector3Array([at.call(&"ApproachStart"), at.call(&"Touchdown")]),
		FlightSim.State.LANDING: PackedVector3Array([at.call(&"Touchdown"), exit]),
		FlightSim.State.TAXI_IN: taxi_in,
		FlightSim.State.PUSHBACK: PackedVector3Array([spot, back]),
		FlightSim.State.TAXI_OUT: taxi_out,
		FlightSim.State.TAKEOFF:
		PackedVector3Array([entry, at.call(&"Liftoff"), points[&"ClimbEnd"]]),
	}
