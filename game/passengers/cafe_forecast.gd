class_name CafeForecast
extends RefCounted
## The itinerary forecast for a cafe visit (decision
## cafe-visit-design-forecast-the-whole-itinerary-abandon-by-a, point 1).
## Admission forecasts the arrival at the plane door with the whole visit in
## it: the walk to the counter queue, the wait and the order, the walk to the
## reserved seat, sitting down, the dwell, standing up and the rest of the
## journey from the seat, with the boarding wait counted once. A visit is
## admitted only when that arrival leaves MARGIN_TICKS before the doors close.
##
## The deadline is the last tick a guest can start to leave (stand up) and
## still arrive MARGIN_TICKS before the doors close: the "abandon now"
## arrival from the seat. CafeSim checks it in every visit phase and works it
## out again after a layout edit.
##
## The cafe's own parts are here: the visit's legs and the stand-up from the
## seat. The journey after it, on the grid's real routes, the margin and the
## deadline rules are VisitForecast's, shared with every facility.
##
## A visit's legs: "pre_ticks" (getting up from a gate seat first),
## "to_queue_mm" (the walk to the queue), "order_ticks" (the queue wait and the
## order), "to_seat_mm" (the counter to the seat's approach cell),
## "dwell_ticks", "leave_cell" (the seat's approach cell) and "resume_stage"
## (TO_SECURITY landside, TO_GATE airside).

const MARGIN_TICKS := VisitForecast.MARGIN_TICKS


## The tick the guest stands up at the end of a visit that starts now.
static func visit_end(sim: PassengerSim, legs: Dictionary) -> int:
	return (
		sim.tick
		+ int(legs["pre_ticks"])
		+ JourneyForecast.walk_ticks(legs["to_queue_mm"])
		+ int(legs["order_ticks"])
		+ JourneyForecast.walk_ticks(legs["to_seat_mm"])
		+ PassengerSim.SIT_DOWN_TICKS
		+ int(legs["dwell_ticks"])
	)


## The tick `p` would reach the plane door after the visit, at a walk.
static func visit_arrival(sim: PassengerSim, p: Passenger, legs: Dictionary) -> int:
	return VisitForecast.arrival(
		sim,
		p,
		visit_end(sim, legs) - sim.tick,
		legs["leave_cell"],
		PassengerSim.STAND_UP_TICKS,
		legs["resume_stage"]
	)


## Ticks from standing up at `cell` to the plane door, with no boarding wait.
static func leave_ticks(
	sim: PassengerSim, p: Passenger, cell: Vector2i, resume: Passenger.Stage
) -> int:
	return VisitForecast.leave_ticks(sim, p, cell, PassengerSim.STAND_UP_TICKS, resume)


## The last tick `p` can stand up at `cell` and arrive MARGIN_TICKS early.
static func deadline(
	sim: PassengerSim, p: Passenger, cell: Vector2i, resume: Passenger.Stage
) -> int:
	return VisitForecast.deadline(sim, p, cell, PassengerSim.STAND_UP_TICKS, resume)


## The deadline of a visit under way, forecast again with the queues and
## stations as they are now: the earlier of leaving from the seat (`approach`,
## standing up first) and leaving at once from where the guest stands. CafeSim
## asks for it once a simulated second per guest and after every grid edit,
## so a queue that grows during the visit brings the deadline forward.
static func live_deadline(
	sim: PassengerSim, p: Passenger, approach: Vector2i, resume: Passenger.Stage
) -> int:
	return VisitForecast.live_deadline(sim, p, approach, PassengerSim.STAND_UP_TICKS, resume)


## Whether an arrival forecast leaves the margin before `p`'s doors close.
static func admits(sim: PassengerSim, p: Passenger, arrival: int) -> bool:
	return VisitForecast.admits(sim, p, arrival)
