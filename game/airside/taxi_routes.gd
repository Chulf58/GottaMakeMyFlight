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
## along the lane, so a join must lie strictly between the lane's ends
## (joins_lane()); Airside refuses a stand whose join does not. The routes
## leave out the other stands' joins they pass, straight points on the lane
## that change no length, corner or slice.
##
## The layout is {"west_x", "east_x"}: the x of the lane's west and east ends,
## where it meets the runway stubs. Production has the north lane only
## (north_only(), the TaxiWest and TaxiEast waypoints); later slices of the same
## decision move the ends and add side routes through it.

## The paths of the phases a plane moves in, by FlightSim.State.
const MOVING_STATES: Array[int] = [
	FlightSim.State.APPROACH,
	FlightSim.State.LANDING,
	FlightSim.State.TAXI_IN,
	FlightSim.State.PUSHBACK,
	FlightSim.State.TAXI_OUT,
	FlightSim.State.TAKEOFF,
]


## The layout of the north lane alone: its ends at the TaxiWest and TaxiEast
## waypoints of `points` (name -> position).
static func north_only(points: Dictionary) -> Dictionary:
	return {
		"west_x": (points[&"TaxiWest"] as Vector3).x, "east_x": (points[&"TaxiEast"] as Vector3).x
	}


## The three route points of StandPlacement stand `stand`: "spot" (where the
## plane parks), "back" (where its pushback ends) and "join" (where its way
## north meets the lane).
static func stand_ends(stand: Dictionary) -> Dictionary:
	return {
		"spot": StandPlacement.stand_point(stand),
		"back": StandPlacement.pushback_end(stand),
		"join": StandPlacement.lane_join(stand),
	}


## Whether `join` lies strictly between the lane ends of `layout`. East of the
## east end or west of the west end a route to it would turn back along the
## lane, and on an end it would add a zero-length step.
static func joins_lane(join: Vector3, layout: Dictionary) -> bool:
	return join.x > float(layout["west_x"]) and join.x < float(layout["east_x"])


## Each moving phase's path (MOVING_STATES -> PackedVector3Array) for a plane of
## `plane_class` at the stand whose route points are `ends` (stand_ends()),
## from the waypoints `points` (name -> position) and the lane `layout`. The
## class picks the approach, touchdown and liftoff points (Airside.
## class_point()); the taxi routes are the same for every class.
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
	return {
		FlightSim.State.APPROACH:
		PackedVector3Array([at.call(&"ApproachStart"), at.call(&"Touchdown")]),
		FlightSim.State.LANDING: PackedVector3Array([at.call(&"Touchdown"), exit]),
		FlightSim.State.TAXI_IN: PackedVector3Array([exit, east, join, back, spot]),
		FlightSim.State.PUSHBACK: PackedVector3Array([spot, back]),
		FlightSim.State.TAXI_OUT: PackedVector3Array([back, join, west, entry]),
		FlightSim.State.TAKEOFF:
		PackedVector3Array([entry, at.call(&"Liftoff"), points[&"ClimbEnd"]]),
	}
