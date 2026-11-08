class_name FlightPlans
extends RefCounted
## FlightSim's taxi plans (decision runway-and-taxi-technical-design-movement-
## plan-analytic-bookings-planned-pauses, sections 5 and 6, wired by Runway R7):
## GroundPlanner run over one calendar day at a time. Departures lie between
## 07:00 and 21:00, so every flight of a day books only between about 04:47 and
## 22:02 and no day's plan depends on another's: the planner restarts each quiet
## night anyway.
##
## A world is {"contracts", "start_day", "next_day", "ended", "reserving",
## "flights", "landed", "grounds"}: FlightSim's contracts and their days, its live flights,
## the occurrences of today it has pruned (landed, kept so a prune never changes
## a plan), and each gate's ground (FlightGround: stand and max_class). A day's
## flights are its landed and live occurrences, each at the stand it was issued
## at (one-off flights, tests and debug only, are not planned),
## and every running contract's days not yet issued, at its gate's stand now. So
## issuing or pruning an occurrence changes no plan; accepting, reassigning,
## moving and ending contracts do, but only for flights that start after them.
##
## Greedy time-order planning is not monotone: taking a flight away can leave a
## later one with no plan. So an ended contract that FlightSim marks reserving
## (FlightSim.end_contract()) is planned as if it still ran: its days not
## issued book their ground as unrendered reservations, never flown, and every
## surviving occurrence keeps the plan it had.

## One planner, so its booking cache serves every re-plan.
var planner := FlightGround.planner()


## The plane class of `flight` in `world`: its contract's, or the starter's for
## a one-off (as GateDesks.booked_class() reads it).
static func flight_class(world: Dictionary, flight: Dictionary) -> String:
	for contract: Dictionary in world["contracts"]:
		if contract["id"] == flight["contract"]:
			return contract["plane_size"]
	return FlightSim.STARTER_TERMS["plane_size"]


## The calendar day a flight with `starts` departs on.
static func day_of(starts: Array) -> int:
	return GameCalendar.day_of(starts[FlightSim.State.PUSHBACK])


## Every flight of calendar day `day` as a GroundPlanner request.
static func requests(world: Dictionary, day: int) -> Array:
	var out := []
	for list: String in ["landed", "flights"]:
		for flight: Dictionary in world[list]:
			if flight["contract"] != "" and day_of(flight["starts"]) == day:
				out.append(
					FlightGround.request(
						flight["id"], flight_class(world, flight), flight["stand"], flight["starts"]
					)
				)
	var grounds: Dictionary = world["grounds"]
	for contract: Dictionary in world["contracts"]:
		var id: String = contract["id"]
		if not runs(world, id) or day < int(world["next_day"][id]):
			continue
		if not grounds.has(contract["gate"]):
			continue
		var stand: Dictionary = grounds[contract["gate"]]["stand"]
		var starts := FlightTimetable.starts_for(contract, day)
		var occurrence := FlightTimetable.occurrence_id(id, day)
		out.append(FlightGround.request(occurrence, contract["plane_size"], stand, starts))
	return out


## Whether contract `id`'s days not yet issued are planned: it runs, or it
## ended and still reserves its ground.
static func runs(world: Dictionary, id: String) -> bool:
	return not world["ended"].has(id) or world["reserving"].has(id)


## id -> GroundPlanner result for every flight of day `day`.
func plan_day(world: Dictionary, day: int) -> Dictionary:
	return planner.plan_all(requests(world, day))


## The days from `from_day` on whose plans can differ, sorted: `from_day`, each
## live or landed flight's day and the day after it, and each running or
## reserving contract's next day (the days on which the set of requests
## changes). Every other day plans exactly as the nearest one before it: it has
## the same contracts and no flight, and a day's plan depends on no other day's.
## A reserving contract's next day never advances (FlightSim._issue_due() skips
## ended contracts), so a gap of years between it and a running contract costs
## no more days than a gap of one.
static func days_from(world: Dictionary, from_day: int) -> Array[int]:
	var seen := {from_day: true}
	for contract: Dictionary in world["contracts"]:
		if runs(world, contract["id"]):
			var next := int(world["next_day"][contract["id"]])
			if next >= from_day:
				seen[next] = true
	for day in live_days(world):
		for sampled in [day, day + 1]:
			if sampled >= from_day:
				seen[sampled] = true
	var out: Array[int] = []
	out.assign(seen.keys())
	out.sort()
	return out


## Every day a sim in `world` can fly or plan: from the earliest of the live and
## landed flights' days and the running and reserving contracts' next days, as
## days_from() samples them; none for a world with neither.
static func horizon(world: Dictionary) -> Array[int]:
	var first := -1
	var days := live_days(world)
	if not days.is_empty():
		first = days[0]
	for contract: Dictionary in world["contracts"]:
		if runs(world, contract["id"]):
			var next := int(world["next_day"][contract["id"]])
			first = next if first < 0 else mini(first, next)
	var out: Array[int] = []
	if first >= 0:
		out = days_from(world, first)
	return out


## The days of the live and landed flights, sorted.
static func live_days(world: Dictionary) -> Array[int]:
	var seen := {}
	for list: String in ["landed", "flights"]:
		for flight: Dictionary in world[list]:
			seen[day_of(flight["starts"])] = true
	var out: Array[int] = []
	out.assign(seen.keys())
	out.sort()
	return out


## The first flight on `days` that `changed` refuses: {"id", "reason"} for an
## occurrence of a contract in `subjects` (or a flight id in it) that does not
## plan, or for a flight that planned in `base` (day -> its plan) and no longer
## does (reason TAXI_BUSY); {} when there is none. A flight that did not plan
## in `base` either is left alone.
func refusal(changed: Dictionary, base: Callable, days: Array[int], subjects: Array) -> Dictionary:
	for day in days:
		var plans := plan_day(changed, day)
		var before: Dictionary = base.call(day)
		var ids := plans.keys()
		ids.sort()
		for id: String in ids:
			var result: Dictionary = plans[id]
			if result["ok"]:
				continue
			var parts := FlightTimetable.parse_occurrence(id)
			if subjects.has(id) or (not parts.is_empty() and subjects.has(parts["contract"])):
				return {"id": id, "reason": result["reason"]}
			if before.has(id) and before[id]["ok"]:
				return {"id": id, "reason": GroundPlanner.TAXI_BUSY}
	return {}
