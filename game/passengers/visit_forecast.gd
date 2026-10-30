class_name VisitForecast
extends RefCounted
## The forecast every facility visit is admitted and abandoned by (decision
## toilet-design-queue-free-reservable-stalls-per-stall-daily-u, point 3). A
## visit is described by how long it keeps the passenger from now
## (`duration`), the cell it sets off from afterwards (`cell`), the ticks it
## takes to set off there (`delay`, such as standing up) and the stage the
## journey resumes at (`resume`, TO_SECURITY landside, TO_GATE airside).
##
## The journey after the visit is forecast on the grid's real routes
## (JourneyForecast.arrival_from() routed): the walk to a scanner and the walk
## to the exit follow paths, not octile distance, so a wall that makes the way
## out longer than the straight line is counted and a detour cannot admit a
## visit that would make the passenger miss. A scanner or exit with no path to
## it does not count; with none left there is no way to the plane (NEVER).
##
## The deadline is the last tick the passenger can set off from `cell` and
## still arrive MARGIN_TICKS before the doors close. The doors close before
## passengers step, so it is strictly before the closing tick.
##
## Not covered: before boarding, a guest resuming TO_GATE first takes a gate
## seat and stands up from it at boarding; the forecast walks it straight from
## `cell` to the exit, as JourneyForecast does for a passenger with no seat.

## Ticks a visit must leave spare before the doors close. Its own tuning value,
## kept above JourneyForecast.RUN_ON_SLACK so a passenger who leaves on the
## deadline still walks.
const MARGIN_TICKS := 100
## How many times leave_ticks() takes the boarding file wait again.
const FILE_TRIES := 4


## The tick `p` would reach the plane door, at a walk, after a visit that
## keeps it `duration` ticks from now and then sets off from `cell` after
## `delay` more, with the boarding wait counted once.
static func arrival(
	sim: PassengerSim,
	p: Passenger,
	duration: int,
	cell: Vector2i,
	delay: int,
	resume: Passenger.Stage
) -> int:
	var after := _leaving(p, cell, resume)
	var leave := sim.tick + duration + delay
	return mini(JourneyForecast.arrival_from(sim, after, leave, true), JourneyForecast.NEVER)


## Ticks from starting to set off at `cell` (the `delay` included) to the
## plane door, with no boarding wait but with the wait in the boarding files
## behind the walkers known now (BoardingFiles.queued()) when setting off as
## late as the margin allows. Setting off earlier can put more walkers ahead,
## so that latest start is moved back by the wait and the wait taken again,
## up to FILE_TRIES times.
static func leave_ticks(
	sim: PassengerSim, p: Passenger, cell: Vector2i, delay: int, resume: Passenger.Stage
) -> int:
	var after := _leaving(p, cell, resume)
	after.boarding_tick = 0
	var ticks := JourneyForecast.arrival_from(sim, after, 0, true, false)
	if ticks >= JourneyForecast.NEVER:
		return JourneyForecast.NEVER
	var latest := sim.flights.doors_close_tick(p.flight_id) - MARGIN_TICKS - ticks
	var wait := 0
	for i in FILE_TRIES:
		var leave := latest - wait
		var queued := JourneyForecast.arrival_from(sim, after, leave, true) - leave - ticks
		if queued <= wait:
			break
		wait = queued
	return mini(ticks + wait + delay, JourneyForecast.NEVER)


## The last tick `p` can start to set off at `cell` and arrive MARGIN_TICKS
## before its doors close.
static func deadline(
	sim: PassengerSim, p: Passenger, cell: Vector2i, delay: int, resume: Passenger.Stage
) -> int:
	return (
		sim.flights.doors_close_tick(p.flight_id)
		- MARGIN_TICKS
		- leave_ticks(sim, p, cell, delay, resume)
	)


## The deadline of a visit under way, forecast again with the queues and
## stations as they are now: the earlier of setting off from `cell` (after
## `delay`) and leaving at once, with no delay, from where `p` stands.
static func live_deadline(
	sim: PassengerSim, p: Passenger, cell: Vector2i, delay: int, resume: Passenger.Stage
) -> int:
	var from_cell := deadline(sim, p, cell, delay, resume)
	if p.at == cell:
		return from_cell
	return mini(from_cell, deadline(sim, p, p.at, 0, resume))


## Whether an arrival forecast leaves the margin before `p`'s doors close.
static func admits(sim: PassengerSim, p: Passenger, arrival_tick: int) -> bool:
	return arrival_tick + MARGIN_TICKS <= sim.flights.doors_close_tick(p.flight_id)


## `p` as it will be after the visit: standing at `cell`, in `resume`, with no
## station chosen yet.
static func _leaving(p: Passenger, cell: Vector2i, resume: Passenger.Stage) -> Passenger:
	var after := Passenger.new()
	after.id = p.id
	after.flight_id = p.flight_id
	after.boarding_tick = p.boarding_tick
	after.cleared = p.cleared
	# Security forecasts this passenger as the candidate, with its carry-on.
	after.carry_on = p.carry_on
	after.liquids = p.liquids
	after.alarm = p.alarm
	after.incident_resolved = p.incident_resolved
	after.stage = resume
	after.at = cell
	after.clear_path()
	return after
