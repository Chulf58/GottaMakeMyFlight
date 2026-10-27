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
## out again after a layout edit. The doors close before passengers step, so
## the deadline is strictly before the closing tick.
##
## A visit's legs: "pre_ticks" (getting up from a gate seat first),
## "to_queue_mm" (the walk to the queue), "order_ticks" (the queue wait and the
## order), "to_seat_mm" (the counter to the seat's approach cell),
## "dwell_ticks", "leave_cell" (the seat's approach cell) and "resume_stage"
## (TO_SECURITY landside, TO_GATE airside).

## Ticks a visit must leave spare before the doors close. Its own tuning value,
## kept above JourneyForecast.RUN_ON_SLACK so a guest who leaves on the
## deadline still walks.
const MARGIN_TICKS := 100


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
	var after := _leaving(p, legs["leave_cell"], legs["resume_stage"])
	var leave := visit_end(sim, legs) + PassengerSim.STAND_UP_TICKS
	return mini(JourneyForecast.arrival_from(sim, after, leave), JourneyForecast.NEVER)


## Ticks from standing up at `cell` to the plane door, with no boarding wait.
static func leave_ticks(
	sim: PassengerSim, p: Passenger, cell: Vector2i, resume: Passenger.Stage
) -> int:
	var after := _leaving(p, cell, resume)
	after.boarding_tick = 0
	var ticks := JourneyForecast.arrival_from(sim, after, 0)
	return mini(ticks + PassengerSim.STAND_UP_TICKS, JourneyForecast.NEVER)


## The last tick `p` can stand up at `cell` and arrive MARGIN_TICKS early.
static func deadline(
	sim: PassengerSim, p: Passenger, cell: Vector2i, resume: Passenger.Stage
) -> int:
	return (
		sim.flights.doors_close_tick(p.flight_id) - MARGIN_TICKS - leave_ticks(sim, p, cell, resume)
	)


## The deadline of a visit under way, forecast again with the queues and
## stations as they are now: the earlier of leaving from the seat (`approach`,
## standing up first) and leaving at once from where the guest stands. CafeSim
## asks for it once a simulated second per guest and after every grid edit,
## so a queue that grows during the visit brings the deadline forward.
static func live_deadline(
	sim: PassengerSim, p: Passenger, approach: Vector2i, resume: Passenger.Stage
) -> int:
	var from_seat := deadline(sim, p, approach, resume)
	if p.at == approach:
		return from_seat
	var now := _leaving(p, p.at, resume)
	now.boarding_tick = 0
	var ticks := mini(JourneyForecast.arrival_from(sim, now, 0), JourneyForecast.NEVER)
	var from_here := sim.flights.doors_close_tick(p.flight_id) - MARGIN_TICKS - ticks
	return mini(from_seat, from_here)


## Whether an arrival forecast leaves the margin before `p`'s doors close.
static func admits(sim: PassengerSim, p: Passenger, arrival: int) -> bool:
	return arrival + MARGIN_TICKS <= sim.flights.doors_close_tick(p.flight_id)


## `p` as it will be after the visit: standing at `cell`, in `resume`, with no
## station chosen yet.
static func _leaving(p: Passenger, cell: Vector2i, resume: Passenger.Stage) -> Passenger:
	var after := Passenger.new()
	after.id = p.id
	after.flight_id = p.flight_id
	after.boarding_tick = p.boarding_tick
	after.cleared = p.cleared
	after.stage = resume
	after.at = cell
	after.clear_path()
	return after
