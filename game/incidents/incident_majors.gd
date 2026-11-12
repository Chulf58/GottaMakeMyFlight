class_name IncidentMajors
extends RefCounted
## What the four major incidents do (decisions daily-incidents-small-ones-just-
## happen-with-a-card-and-a-cau, daily-incidents-technical-design-incidentdirector-
## shared-clo and incident-rating-effects-are-penalties-only-incident-rewards).
## The IncidentDirector owns the records and calls in here; every method takes
## the director's own record and changes it. Nothing here draws from
## SimClock.rng (the inspector's visit tick is a draw of its own stream) and
## everything decided is written into the record's saved "plan".
##
## - Inspector (announced on day D): the visit lands inside the busy window of
##   day D+1. At the visit tick it counts the messes on the floor and the
##   passengers stuck in a full queue; within IncidentTuning's limits it pays
##   INCIDENT money (passed), else it adds a rating penalty (failed).
## - Holiday rush (announced on day D): extra passengers are booked on up to
##   RUSH_MAX_FLIGHTS of day D+1's flights not yet issued, RUSH_EXTRA each,
##   capped by the plane class maximum (PassengerSim.set_booking_override). The
##   plan keeps the exact counts the panel shows.
## - VIP (offer): the plan names the next flight not yet issued. Accepted, the
##   first passenger spawned for it is marked (plan "target"); an ordinary
##   passenger otherwise. A made flight with mood at least VIP_GOOD_MOOD pays
##   VIP_BONUS_MONEY; a miss adds a penalty; the passenger's ordinary made or
##   missed record is the sim's own and is not written again.
## - Airline favour (offer): the plan names the next flight with headroom and
##   how many extra passengers fit. Accepted, they are booked at once (capped by
##   headroom) and the money is paid. Declined, nothing happens.

const NOT_HELD := "not_held"
const APPLIED := "applied"
const PASSED := "passed"
const FAILED := "failed"
const BONUS := "bonus"
const NEUTRAL := "neutral"
const PENALTY := "penalty"
## How many days ahead a VIP or favour flight is looked for.
const LOOK_DAYS := 2

var _director: IncidentDirector


func _init(director: IncidentDirector) -> void:
	_director = director


## Decides what a scheduled major will do and does what is done at once (a
## rush books its passengers): its plan, or {} when it cannot be held (no
## flight to land on, no window for a visit).
func prepare(incident: Dictionary, tick: int) -> Dictionary:
	match incident["kind"]:
		IncidentCatalogue.INSPECTOR:
			return _inspector_plan(incident, tick)
		IncidentCatalogue.RUSH:
			return _rush_plan(tick)
		IncidentCatalogue.VIP:
			return _vip_plan(tick)
		IncidentCatalogue.FAVOUR:
			return _favour_plan(tick)
	return {}


## The player accepted the offer.
func accepted(incident: Dictionary) -> void:
	var plan: Dictionary = incident["plan"]
	match incident["kind"]:
		IncidentCatalogue.FAVOUR:
			var added := _add_extra(plan["flight"], plan["extra"])
			if added < 1:
				_done(incident, NOT_HELD)
				return
			plan["extra"] = added
			_pay(plan["bonus"])
			_done(incident, APPLIED)
		IncidentCatalogue.VIP:
			if _director.flights.state_of(plan["flight"]) >= 0:
				_done(incident, NOT_HELD)


## A passenger spawned: the first one for an accepted VIP's flight is the VIP.
func spawned(incident: Dictionary, passenger_id: int) -> void:
	if not _waiting_vip(incident) or incident["plan"]["target"] != 0:
		return
	var p := _director.passengers.get_passenger(passenger_id)
	if p != null and p.flight_id == incident["plan"]["flight"]:
		incident["plan"]["target"] = passenger_id


## A passenger finished its flight (made or missed).
func finished(incident: Dictionary, passenger_id: int, made: bool, tick: int) -> void:
	if not _waiting_vip(incident) or incident["plan"]["target"] != passenger_id:
		return
	var p := _director.passengers.get_passenger(passenger_id)
	if made and p.mood >= IncidentTuning.VIP_GOOD_MOOD:
		_pay(incident["plan"]["bonus"])
		_done(incident, BONUS)
	elif made:
		_done(incident, NEUTRAL)
	else:
		_penalize(incident, tick, IncidentTuning.VIP_MISS_HALF_STARS)
		_done(incident, PENALTY)


## One tick of a major that already happened: the inspector's visit, the end of
## the rush's day, a VIP whose flight left unmarked.
func step(incident: Dictionary, tick: int) -> void:
	var plan: Dictionary = incident["plan"]
	match [incident["kind"], incident["state"]]:
		[IncidentCatalogue.INSPECTOR, IncidentCatalogue.ANNOUNCED]:
			if tick >= plan["visit_tick"]:
				_visit(incident, tick)
		[IncidentCatalogue.RUSH, IncidentCatalogue.ANNOUNCED]:
			if tick >= plan["until"]:
				_done(incident, APPLIED)
		[IncidentCatalogue.VIP, IncidentCatalogue.ACCEPTED]:
			if plan["target"] == 0 and _director.flights.is_doors_closed(plan["flight"]):
				_done(incident, NOT_HELD)


## The next tick an announced major is due (the inspector's visit), or -1.
func due_tick(incident: Dictionary) -> int:
	if incident["kind"] == IncidentCatalogue.INSPECTOR:
		if incident["state"] == IncidentCatalogue.ANNOUNCED:
			return incident["plan"]["visit_tick"]
	return -1


func _waiting_vip(incident: Dictionary) -> bool:
	return (
		incident["kind"] == IncidentCatalogue.VIP
		and incident["state"] == IncidentCatalogue.ACCEPTED
	)


func _inspector_plan(incident: Dictionary, tick: int) -> Dictionary:
	var window := _director.busy_window(GameCalendar.day_of(tick) + 1, tick)
	if window.x > window.y:
		return {}
	var draws := IncidentRoll.stream(
		_director.clock.rng.seed,
		incident["roll_day"],
		IncidentCatalogue.VERSION,
		"visit:%d" % incident["id"]
	)
	return {
		"window_from": window.x,
		"window_to": window.y,
		"visit_tick": window.x + draws.below(window.y - window.x + 1),
	}


func _rush_plan(tick: int) -> Dictionary:
	var flights: Array[Dictionary] = []
	var total := 0
	var tomorrow := GameCalendar.day_of(tick) + 1
	for open in _open_flights(tick):
		if flights.size() >= IncidentTuning.RUSH_MAX_FLIGHTS:
			break
		if open["day"] != tomorrow:
			continue
		var added := _add_extra(open["id"], IncidentTuning.RUSH_EXTRA)
		if added > 0:
			flights.append({"flight": open["id"], "extra": added, "departs": open["departs"]})
			total += added
	if flights.is_empty():
		return {}
	return {"flights": flights, "total": total, "until": GameCalendar.day_start(tomorrow + 1)}


func _vip_plan(tick: int) -> Dictionary:
	var open := _open_flights(tick)
	if open.is_empty():
		return {}
	return {
		"flight": open[0]["id"],
		"departs": open[0]["departs"],
		"bonus": IncidentTuning.VIP_BONUS_MONEY,
		"target": 0,
	}


func _favour_plan(tick: int) -> Dictionary:
	for open in _open_flights(tick):
		var room := _room(open["id"])
		if room >= 1:
			return {
				"flight": open["id"],
				"departs": open["departs"],
				"extra": mini(IncidentTuning.FAVOUR_EXTRA, room),
				"bonus": IncidentTuning.FAVOUR_BONUS_MONEY,
			}
	return {}


## The occurrences of the running contracts not yet issued and not yet departed,
## for today and the days ahead (LOOK_DAYS), earliest first:
## [{"id", "day", "departs"}].
func _open_flights(tick: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var today := GameCalendar.day_of(tick)
	for contract_id in _director.flights.active_contract_ids():
		var contract := _director.flights.contract_of(contract_id)
		for day in range(maxi(today, int(contract["first_day"])), today + LOOK_DAYS + 1):
			var id := FlightTimetable.occurrence_id(contract_id, day)
			var departs := GameCalendar.tick_at(day, int(contract["departure_minute"]))
			if departs > tick and _director.flights.state_of(id) < 0:
				out.append({"id": id, "day": day, "departs": departs})
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (
				a["departs"] < b["departs"] or (a["departs"] == b["departs"] and a["id"] < b["id"])
			)
	)
	return out


## The extra passengers `flight_id` can still take: its headroom less what is
## already booked on top.
func _room(flight_id: String) -> int:
	var sim := _director.passengers
	return sim.booking_headroom(flight_id) - sim.booking_override_of(flight_id)


## Books up to `want` more passengers on `flight_id`, within its headroom, and
## returns how many were booked (0 when none fit or the sim refused).
func _add_extra(flight_id: String, want: int) -> int:
	var sim := _director.passengers
	var added := mini(want, _room(flight_id))
	if added < 1:
		return 0
	var booked := sim.set_booking_override(flight_id, sim.booking_override_of(flight_id) + added)
	return added if booked["ok"] else 0


func _visit(incident: Dictionary, tick: int) -> void:
	var sim := _director.passengers
	var full := 0
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		if not p.is_done() and p.stuck == Passenger.Stuck.QUEUE_FULL:
			full += 1
	var messes := sim.messes.mess_ids().size()
	if (
		messes <= IncidentTuning.INSPECTOR_MAX_MESSES
		and full <= IncidentTuning.INSPECTOR_MAX_FULL_QUEUE
	):
		_pay(IncidentTuning.INSPECTOR_PASS_MONEY)
		_done(incident, PASSED)
		return
	_penalize(incident, tick, IncidentTuning.INSPECTOR_FAIL_HALF_STARS)
	_done(incident, FAILED)


func _done(incident: Dictionary, outcome: String) -> void:
	incident["state"] = IncidentCatalogue.DONE
	incident["outcome"] = outcome


func _pay(amount: int) -> void:
	var wallet := _director.passengers.wallet
	if wallet == null:
		push_warning("IncidentMajors: no wallet, so %d money is not paid" % amount)
		return
	wallet.credit(amount, Wallet.Category.INCIDENT)


## A rating penalty of `half_stars` half stars from `tick` until its day leaves
## the rating window.
func _penalize(incident: Dictionary, tick: int, half_stars: int) -> void:
	var rating := _director.rating
	if rating == null:
		push_warning("IncidentMajors: no rating, so incident %d costs none" % incident["id"])
		return
	rating.add_adjustment(
		"incident_%d" % incident["id"], tick, RatingAdjustments.expiry_for(tick), -half_stars
	)
