class_name FlightGround
extends RefCounted
## The ground FlightSim plans taxi bookings on (decision runway-and-taxi-
## technical-design-movement-plan-analytic-bookings-planned-pauses, sections 5
## and 6): the fixed Airside waypoints of main.tscn, read once from the saved
## scene, and each phase's path for a plane at a stand from TaxiRoutes, the
## source Airside.phase_path() draws from too. Pure: no node is built.
##
## A gate's ground is {"stand": StandPlacement stand, "max_class": the largest
## plane class it holds} (FlightSim.stand_source, from GateDesks). With no
## source set (tests, the one-stand airport) every gate stands on fallback():
## the scene's one Stand for gate C, and the other letters FALLBACK_SPACING_M
## apart along the same row, each taking any class.

const MAIN_SCENE := "res://main/main.tscn"
const AIRSIDE_PATH := "./Airside"
const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
## Fallback stands sit this far apart, the medium exit spacing (StandEnvelope),
## so two medium planes at neighbouring fallback gates never meet parked.
const FALLBACK_SPACING_M := 42.0

## Waypoint name -> position, read from main.tscn on first use.
static var _points := {}


## The Airside waypoints of main.tscn: name -> position.
static func points() -> Dictionary:
	if _points.is_empty():
		var state: SceneState = (load(MAIN_SCENE) as PackedScene).get_state()
		for i in state.get_node_count():
			if String(state.get_node_path(i, true)) != AIRSIDE_PATH:
				continue
			if state.get_node_type(i) != &"Marker3D":
				continue
			for k in state.get_node_property_count(i):
				if state.get_node_property_name(i, k) == &"transform":
					var at: Transform3D = state.get_node_property_value(i, k)
					_points[state.get_node_name(i)] = at.origin
	return _points


## A planner on the stub hold lines HoldIn and HoldRunway.
static func planner() -> GroundPlanner:
	var p := points()
	return GroundPlanner.new(p[&"HoldIn"], p[&"HoldRunway"])


## The stand main.tscn's Stand waypoint is the plane point of.
static func scene_stand() -> Dictionary:
	var spot: Vector3 = points()[&"Stand"]
	return StandPlacement.make(
		0,
		spot.x + StandPlacement.DOOR_SIDE_M,
		spot.z + StandPlacement.NOSE_GAP_M + StandPlacement.NOSE_M
	)


## Gate `gate`'s ground while FlightSim has no stand_source: scene_stand() for
## FlightSim.DEFAULT_GATE, moved FALLBACK_SPACING_M east per letter after it
## (west per letter before it), taking any class. {} for a name that is not one
## letter.
static func fallback(gate: String) -> Dictionary:
	var index := LETTERS.find(gate) if gate.length() == 1 else -1
	if index < 0:
		return {}
	var stand := scene_stand()
	stand["x"] = (
		float(stand["x"]) + (index - LETTERS.find(FlightSim.DEFAULT_GATE)) * FALLBACK_SPACING_M
	)
	return {"stand": stand, "max_class": PlaneClasses.LARGE}


## The lane layout routes() builds on (TaxiRoutes): the north lane alone; a
## side stand carries its own spur (lane_x). With the stands it is the route
## context of a plan and of a taxi pair, so FlightSim keys its cached plans and
## planning_changed on it too.
static func layout() -> Dictionary:
	return TaxiRoutes.north_only(points())


## Each phase's path, by FlightSim.State, for a plane of `plane_class` at
## `stand`: APPROACH, LANDING, TAXI_IN, PUSHBACK, TAXI_OUT and TAKEOFF, as
## TaxiRoutes builds them on layout().
static func routes(stand: Dictionary, plane_class: String) -> Dictionary:
	return TaxiRoutes.phase_paths(points(), TaxiRoutes.stand_ends(stand), plane_class, layout())


## A GroundPlanner request for flight `id`.
static func request(
	id: String, plane_class: String, stand: Dictionary, starts: Array, epoch: int
) -> Dictionary:
	return GroundPlanner.request(id, plane_class, stand, starts, routes(stand, plane_class), epoch)


## Whether a plane of `plane_class` fits a gate whose largest class is
## `max_class` ("" holds none).
static func class_fits(plane_class: String, max_class: String) -> bool:
	var size := PlaneClasses.ORDER.find(plane_class)
	return max_class != "" and size >= 0 and size <= PlaneClasses.ORDER.find(max_class)
