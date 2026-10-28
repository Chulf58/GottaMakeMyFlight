class_name StageKinds
extends RefCounted
## The one place that classifies passenger stages (decision
## toilet-design-queue-free-reservable-stalls-per-stall-daily-u, point 4).
## Every Passenger.Stage has one row in KINDS saying which facility owns it,
## where the passenger is and how its body is posed, so a stage added to the
## enum without a row fails test_stage_kinds. The enum's order is not the
## journey's order for the facility stages appended after MISSED: ask this
## class instead of comparing stages with < or >.
##
## A facility visit is also owned while the passenger is still getting up
## from a gate seat for it (Stage.STANDING_UP), so visit_facility() asks the
## facility sims, not the stage; resume_of() says how the journey goes on
## after the visit.

## Which facility runs a stage; NONE for the journey's own stages.
enum Facility { NONE, CAFE }

## Where a passenger in a stage is. ROAD: walking in from the road, holding
## the entrance cell. FLOOR: on the grid, walking, queuing or in service.
## GATE_SEAT and FACILITY_SEAT: sitting down, seated or standing up at a gate
## seat or a facility seat. APRON: the walk out to the plane. SETTLED: made
## or missed.
enum Location { ROAD, FLOOR, GATE_SEAT, FACILITY_SEAT, APRON, SETTLED }

## How the body is drawn: upright (standing or walking), or one of the three
## seat poses.
enum Pose { UPRIGHT, SITTING_DOWN, SEATED, STANDING_UP }

## Stage -> [Facility, Location, Pose].
const KINDS := {
	Passenger.Stage.SPAWNED: [Facility.NONE, Location.ROAD, Pose.UPRIGHT],
	Passenger.Stage.TO_CHECKIN: [Facility.NONE, Location.FLOOR, Pose.UPRIGHT],
	Passenger.Stage.CHECKIN_QUEUE: [Facility.NONE, Location.FLOOR, Pose.UPRIGHT],
	Passenger.Stage.CHECKIN: [Facility.NONE, Location.FLOOR, Pose.UPRIGHT],
	Passenger.Stage.TO_SECURITY: [Facility.NONE, Location.FLOOR, Pose.UPRIGHT],
	Passenger.Stage.SECURITY_QUEUE: [Facility.NONE, Location.FLOOR, Pose.UPRIGHT],
	Passenger.Stage.SECURITY: [Facility.NONE, Location.FLOOR, Pose.UPRIGHT],
	Passenger.Stage.TO_GATE: [Facility.NONE, Location.FLOOR, Pose.UPRIGHT],
	Passenger.Stage.SITTING_DOWN: [Facility.NONE, Location.GATE_SEAT, Pose.SITTING_DOWN],
	Passenger.Stage.SEATED: [Facility.NONE, Location.GATE_SEAT, Pose.SEATED],
	Passenger.Stage.STANDING: [Facility.NONE, Location.FLOOR, Pose.UPRIGHT],
	Passenger.Stage.STANDING_UP: [Facility.NONE, Location.GATE_SEAT, Pose.STANDING_UP],
	Passenger.Stage.TO_EXIT: [Facility.NONE, Location.FLOOR, Pose.UPRIGHT],
	Passenger.Stage.APRON: [Facility.NONE, Location.APRON, Pose.UPRIGHT],
	Passenger.Stage.MADE: [Facility.NONE, Location.SETTLED, Pose.UPRIGHT],
	Passenger.Stage.MISSED: [Facility.NONE, Location.SETTLED, Pose.UPRIGHT],
	Passenger.Stage.CAFE_WALK: [Facility.CAFE, Location.FLOOR, Pose.UPRIGHT],
	Passenger.Stage.CAFE_QUEUE: [Facility.CAFE, Location.FLOOR, Pose.UPRIGHT],
	Passenger.Stage.CAFE_ORDER: [Facility.CAFE, Location.FLOOR, Pose.UPRIGHT],
	Passenger.Stage.CAFE_TO_SEAT: [Facility.CAFE, Location.FLOOR, Pose.UPRIGHT],
	Passenger.Stage.CAFE_SITTING_DOWN: [Facility.CAFE, Location.FACILITY_SEAT, Pose.SITTING_DOWN],
	Passenger.Stage.CAFE_SEATED: [Facility.CAFE, Location.FACILITY_SEAT, Pose.SEATED],
	Passenger.Stage.CAFE_STANDING_UP: [Facility.CAFE, Location.FACILITY_SEAT, Pose.STANDING_UP],
}


static func facility(stage: Passenger.Stage) -> Facility:
	return KINDS[stage][0]


static func location(stage: Passenger.Stage) -> Location:
	return KINDS[stage][1]


static func pose(stage: Passenger.Stage) -> Pose:
	return KINDS[stage][2]


## Whether the stage belongs to a facility visit.
static func in_visit(stage: Passenger.Stage) -> bool:
	return facility(stage) != Facility.NONE


## Whether the passenger is outside the terminal: on the road in, on the
## apron walk or settled. Its drawn spot then follows its walk outside.
static func is_outside(stage: Passenger.Stage) -> bool:
	return location(stage) in [Location.ROAD, Location.APRON, Location.SETTLED]


## Whether `at` holds the grid cell the passenger stands on or walks from:
## every stage but the apron walk and settled ones (on the road in, it holds
## the entrance cell).
static func on_grid(stage: Passenger.Stage) -> bool:
	return not location(stage) in [Location.APRON, Location.SETTLED]


## The facility holding `p`'s active visit, NONE when it has none. A
## passenger getting up from a gate seat for a visit already has it.
static func visit_facility(sim: PassengerSim, p: Passenger) -> Facility:
	if sim.cafes.visit_of(p.id) != null:
		return Facility.CAFE
	return Facility.NONE


## How `p`'s journey goes on after its active visit: {"stage": the stage it
## resumes at, "cell": the cell it sets off from when the visit has one
## (a cafe seat's approach), else Passenger.NO_CELL}. Empty with no visit.
static func resume_of(sim: PassengerSim, p: Passenger) -> Dictionary:
	match visit_facility(sim, p):
		Facility.CAFE:
			var visit := sim.cafes.visit_of(p.id)
			return {
				"stage": visit.resume_stage,
				"cell": visit.seat.get("approach", Passenger.NO_CELL),
			}
	return {}
