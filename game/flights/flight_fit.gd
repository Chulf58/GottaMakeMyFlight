class_name FlightFit
extends RefCounted
## Whether an airline offer fits the airport now, and why not, as one read-only
## assessment per departure (decision airline-offers-2-a-day-fit-the-free-gate-
## slots-1-needs-more, point 2). The offer board fits its daily offers with it
## and the offer cards word their fit line from it. It asks FlightSim.
## trial_assignment, the same assignment accept_contract makes, so the R7 check
## that no existing flight is left without a taxi plan holds here too. It is
## advice: Accept still asks FlightSim.accept_problem at the click.
##
## An assessment is {"fits": bool, "blocker": "" or a FlightSim.BLOCKER_ value,
## "gate": the gate it would get or "", "problem": FlightSim's words or "",
## "another_gate_helps": bool}. A gate clash does not prove that another gate
## would help (FlightSim skips the taxi plan when the gate clashes), so for a
## gate blocker the assignment runs again with the gate overlap ignored, at the
## stands the airport has now and at one spare stand the player could build
## (FlightSim.spare_stand_source, SpareStand): another gate helps when the
## runway and lane would then take the flight.

## The card's fit line for each kind of answer.
const FITS_TEXT := "Fits a free gate at this time"
const ANOTHER_GATE_TEXT := "No gate free at this time: build another gate"
const GATE_AND_TAXI_TEXT := "No gate free, and the taxi lane is busy then"
const TAXI_TEXT := "Taxi lane busy at this time"
const NIGHT_TEXT := "Departs in the quiet night"
## Formatted with the plane class.
const RUNWAY_TEXT := "Runway too short for a %s plane"
const STAND_TEXT := "No gate takes a %s plane"
const NO_STAND_TEXT := "No gate has a stand yet"


## The assessment of `terms` (FlightContract.TERM_KEYS) in `sim` now, with the
## terms of `before` accepted first, in order, on copies of its planning state.
## Without `look_again` a gate blocker is not looked at again and
## another_gate_helps stays false (the offer board's fit lists need no more).
static func assess(
	sim: FlightSim, terms: Dictionary, before: Array = [], look_again := true
) -> Dictionary:
	var trial := sim.trial_assignment(terms, before)
	var helps := false
	if look_again and trial["blocker"] == FlightSim.BLOCKER_GATE:
		helps = another_gate_helps(sim, terms, before)
	return {
		"fits": trial["gate"] != "",
		"blocker": trial["blocker"],
		"gate": trial["gate"],
		"problem": trial["problem"],
		"another_gate_helps": helps,
	}


## Whether a free gate would make `terms` acceptable in `sim` after `before`:
## the assignment with the gate overlap ignored, and a spare stand offered, finds
## a gate. Asked of a gate blocker; for terms that fit it is true as well.
static func another_gate_helps(sim: FlightSim, terms: Dictionary, before: Array = []) -> bool:
	return sim.trial_assignment(terms, before, true)["gate"] != ""


## Whether `terms` would be accepted in `sim` now after `before`, without the
## second look assess() takes at a gate clash.
static func fits(sim: FlightSim, terms: Dictionary, before: Array = []) -> bool:
	return sim.trial_assignment(terms, before)["gate"] != ""


## The card's fit line for `assessment` of an offer with `plane_size`.
static func text(assessment: Dictionary, plane_size: String) -> String:
	if assessment["fits"]:
		return FITS_TEXT
	var problem: String = assessment["problem"]
	var words := {
		FlightSim.BLOCKER_GATE:
		ANOTHER_GATE_TEXT if assessment["another_gate_helps"] else GATE_AND_TAXI_TEXT,
		FlightSim.BLOCKER_TAXI: TAXI_TEXT,
		FlightSim.BLOCKER_NIGHT: NIGHT_TEXT,
		FlightSim.BLOCKER_RUNWAY: RUNWAY_TEXT % plane_size,
		FlightSim.BLOCKER_STAND:
		NO_STAND_TEXT if problem == "no gate has a stand" else STAND_TEXT % plane_size,
	}
	return words.get(assessment["blocker"], problem.left(1).to_upper() + problem.substr(1))
