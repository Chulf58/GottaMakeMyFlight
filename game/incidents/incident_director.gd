class_name IncidentDirector
extends Node
## Rolls the day's incident (decisions daily-incidents-small-ones-just-happen-
## with-a-card-and-a-cau and daily-incidents-technical-design-incidentdirector-
## shared-clo). At most one roll per day boundary, and none before the day
## after the airport opened: when SimClock enters a new day (GameCalendar.
## day_of), the director draws from that day's own stream (IncidentRoll, never
## SimClock.rng) one kind from the tier-gated catalogue, weighted by what is
## built, "none" included so some days stay quiet. A major may come at most
## once every 2 to 3 days (next_major_day); there are no majors yet.
##
## Everything the roll decides is saved as ticks. A spill's fire tick lands in
## that day's busy window, from BUSY_LEAD_TICKS before its first departure to
## its last, so it never happens unseen at night. When the fire tick comes the
## spill picks its place (a check-in desk's or a scanner's passenger spot, from
## its own stream) and leaves a SPILL mess there (MessSim.add); it is active
## until that mess is gone, then done. A minor never pauses the game; the card
## naming its cause is IncidentCards', which listens to started and ended.
##
## Incidents are on or off per game, saved with it. A world no new-game dialog
## made (tests, probes, playtests) starts with them off; the dialog and the
## settings menu (slice E) call set_enabled(). Turned off, no roll happens and
## a scheduled incident is dropped; one already on the floor plays out.
## next_event_tick() feeds the quiet-night fast-forward stop (QuietNight).

## An incident happened (a spill is on the floor). A copy of its record.
signal started(incident: Dictionary)
## An active incident is over (its mess is gone). A copy of its record.
signal ended(incident: Dictionary)
## A load replaced every incident; the cards are posted again.
signal restored

## A spill may come this long before the day's first departure: two hours.
const BUSY_LEAD_TICKS := 2 * 60 * GameCalendar.TICKS_PER_MINUTE
const CHECKIN_PLACE := "Check-in"
const SECURITY_PLACE := "Security"

## The clock whose day boundaries roll. A scene must set it, with the flights
## and passengers; tests call bind().
@export var clock: SimClock
## The rating whose airline tier gates the catalogue. Without one every roll
## is at tier 0.
@export var rating: AirportRating
## Says when the airport opened and when the day's flights depart.
@export var flights: FlightSim
## The grid, its desks and scanners, the messes and the staff.
@export var passengers: PassengerSim

## Debug only (PlaytestHook): every roll is this kind. Not saved.
var forced_kind := ""

var _enabled := false
var _last_rolled_day := -1
var _next_major_day := 0
var _next_id := 1
var _incidents: Array[Dictionary] = []
## The day the clock was last seen on. Derived from the tick, never saved.
var _day := -1
var _bound: SimClock


func _ready() -> void:
	if clock == null or flights == null or passengers == null:
		push_error("IncidentDirector: clock, flights or passengers unset, so no incident rolls")
		return
	bind(clock, flights, passengers)


## Follows `with_clock`'s ticks. Binding again lets go of the clock bound before.
func bind(with_clock: SimClock, with_flights: FlightSim, with_passengers: PassengerSim) -> void:
	if _bound != null and _bound.ticked.is_connected(on_tick):
		_bound.ticked.disconnect(on_tick)
	clock = with_clock
	flights = with_flights
	passengers = with_passengers
	_bound = clock
	_day = GameCalendar.day_of(clock.tick)
	clock.ticked.connect(on_tick)


func is_enabled() -> bool:
	return _enabled


## Turns incidents on or off for this game. Off drops the scheduled ones.
func set_enabled(value: bool) -> void:
	_enabled = value
	if value:
		return
	for incident in _incidents:
		if incident["state"] == IncidentCatalogue.SCHEDULED:
			incident["state"] = IncidentCatalogue.DONE


## A new day rolls, then what is due fires and what is over ends.
func on_tick(tick: int) -> void:
	var day := GameCalendar.day_of(tick)
	if day != _day:
		_day = day
		if _roll_due(day):
			_roll(day, tick)
	for incident in _incidents:
		if incident["state"] == IncidentCatalogue.SCHEDULED and incident["fire_tick"] <= tick:
			_fire(incident)
		elif incident["state"] == IncidentCatalogue.ACTIVE and _is_over(incident):
			incident["state"] = IncidentCatalogue.DONE
			ended.emit(incident.duplicate())


## The next tick something of the incidents is due after `now`: a scheduled
## fire or, while incidents are on and the airport open, the next day boundary,
## where a roll may schedule one. -1 for none.
func next_event_tick(now: int) -> int:
	var next := -1
	for incident in _incidents:
		if incident["state"] == IncidentCatalogue.SCHEDULED:
			next = _earliest(next, incident["fire_tick"])
	if _enabled and flights.opened_tick >= 0:
		next = _earliest(next, GameCalendar.day_start(GameCalendar.day_of(now) + 1))
	return next


## Copies of every incident kept, oldest first.
func incidents() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for incident in _incidents:
		out.append(incident.duplicate())
	return out


## Copies of the incidents happening now, oldest first.
func active_incidents() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for incident in _incidents:
		if incident["state"] == IncidentCatalogue.ACTIVE:
			out.append(incident.duplicate())
	return out


func last_rolled_day() -> int:
	return _last_rolled_day


## Whether a cleaner is on the staff, for the card's words.
func cleaner_hired() -> bool:
	var staff := passengers.staff
	return staff != null and staff.count(StaffMember.Role.CLEANER) > 0


## The inclusive tick range a fire on `day` may land in, from BUSY_LEAD_TICKS
## before its first departure to its last, never at or before `now`; x > y
## when the day has no departure left.
func busy_window(day: int, now: int) -> Vector2i:
	var first := -1
	var last := -1
	for departure in _departures(day):
		first = departure if first < 0 else mini(first, departure)
		last = maxi(last, departure)
	if first < 0:
		return Vector2i(1, 0)
	return Vector2i(maxi(first - BUSY_LEAD_TICKS, now + 1), last)


## The places a spill can happen now: each check-in desk's and scanner's
## passenger spot that has floor and a way for a cleaner to reach it, in
## object id order. [{"place", "cell"}].
func spill_places() -> Array[Dictionary]:
	var grid := passengers.grid
	var out: Array[Dictionary] = []
	for group: Array in [
		[passengers.layout.desks, CHECKIN_PLACE], [passengers.layout.scanners, SECURITY_PLACE]
	]:
		var ids: Array = (group[0] as Array).duplicate()
		ids.sort()
		for station: int in ids:
			var cell := grid.interaction_cell(station)
			if cell == BuildObjectDef.NO_CELL or grid.floor_at(cell) == BuildGrid.FLOOR_NONE:
				continue
			if MessSim.approach_for(grid, cell) != MessSim.NO_CELL:
				out.append({"place": group[1], "cell": cell})
	return out


func to_snapshot() -> Dictionary:
	var saved: Array[Dictionary] = []
	for incident in _incidents:
		saved.append(IncidentSnapshot.save_incident(incident))
	return {
		"save_version": IncidentSnapshot.SAVE_VERSION,
		"enabled": _enabled,
		"last_rolled_day": _last_rolled_day,
		"next_major_day": _next_major_day,
		"next_id": _next_id,
		"incidents": saved,
	}


## Restores a to_snapshot() dictionary, also one that went through JSON.
## Pushes an error and returns false, changing nothing, when it is refused.
func from_snapshot(data: Dictionary) -> bool:
	var loaded := IncidentSnapshot.load(data)
	if loaded.has("error"):
		push_error("IncidentDirector.from_snapshot: %s" % loaded["error"])
		return false
	_enabled = loaded["enabled"]
	_last_rolled_day = loaded["last_rolled_day"]
	_next_major_day = loaded["next_major_day"]
	_next_id = loaded["next_id"]
	_incidents = loaded["incidents"]
	if clock != null:
		_day = GameCalendar.day_of(clock.tick)
	restored.emit()
	return true


func _roll_due(day: int) -> bool:
	if not _enabled or flights.opened_tick < 0 or day <= _last_rolled_day:
		return false
	return day > GameCalendar.day_of(flights.opened_tick)


func _roll(day: int, tick: int) -> void:
	_last_rolled_day = day
	_incidents = _incidents.filter(
		func(incident: Dictionary) -> bool: return incident["state"] != IncidentCatalogue.DONE
	)
	var world := {"tier": _tier(), "places": spill_places().size()}
	var candidates := IncidentCatalogue.candidates(world)
	if forced_kind != "":
		candidates = [
			{"kind": forced_kind, "weight": 1, "major": IncidentCatalogue.is_major(forced_kind)}
		]
	var draws := IncidentRoll.stream(clock.rng.seed, day, IncidentCatalogue.VERSION, "roll")
	var result := IncidentRoll.roll(draws, candidates, day, _next_major_day, busy_window(day, tick))
	_next_major_day = result["next_major_day"]
	if result["kind"] == IncidentCatalogue.NONE:
		return
	(
		_incidents
		. append(
			{
				"id": _next_id,
				"kind": result["kind"],
				"roll_day": day,
				"state": IncidentCatalogue.SCHEDULED,
				"fire_tick": result["fire_tick"],
				"cell": IncidentSnapshot.NO_CELL,
				"mess_id": 0,
				"place": "",
			}
		)
	)
	_next_id += 1


## A spill picks its place from its own stream and leaves its mess there. With
## no place left, or a mess refused at the cap, it is done without happening.
func _fire(incident: Dictionary) -> void:
	var places := spill_places()
	if places.is_empty():
		incident["state"] = IncidentCatalogue.DONE
		return
	var purpose := "place:%d" % incident["id"]
	var draws := IncidentRoll.stream(
		clock.rng.seed, incident["roll_day"], IncidentCatalogue.VERSION, purpose
	)
	var chosen: Dictionary = places[draws.below(places.size())]
	var mess := passengers.messes.add(MessSim.Kind.SPILL, chosen["cell"])
	if mess == 0:
		incident["state"] = IncidentCatalogue.DONE
		return
	incident["cell"] = chosen["cell"]
	incident["mess_id"] = mess
	incident["place"] = chosen["place"]
	incident["state"] = IncidentCatalogue.ACTIVE
	started.emit(incident.duplicate())


func _is_over(incident: Dictionary) -> bool:
	return passengers.messes.get_mess(incident["mess_id"]).is_empty()


## The departure ticks on `day`: each running contract's, from its first day
## on, and each listed flight's that departs that day.
func _departures(day: int) -> Array[int]:
	var out: Array[int] = []
	for id in flights.active_contract_ids():
		var contract := flights.contract_of(id)
		if int(contract["first_day"]) <= day:
			out.append(GameCalendar.tick_at(day, int(contract["departure_minute"])))
	for id in flights.flight_ids():
		var departs := flights.state_start(id, FlightSim.State.PUSHBACK)
		if departs >= 0 and GameCalendar.day_of(departs) == day:
			out.append(departs)
	return out


func _tier() -> int:
	if rating == null:
		return 0
	return RatingFormula.tier(rating.stars())


static func _earliest(a: int, b: int) -> int:
	return b if a < 0 else mini(a, b)
