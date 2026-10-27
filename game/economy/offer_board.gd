class_name OfferBoard
extends RefCounted
## The airline offers the player can take. Each game day a few offers are drawn
## from the sim RNG (SimClock.rng), starter tier only; the player accepts one,
## which makes it a FlightSim contract with the offer's terms, or declines it,
## which removes it from the open list. Plain data: no nodes, no clock.
##
## An offer is {id, day, <FlightContract.TERM_KEYS>, status}: its terms are
## exactly what a contract needs, and day is the day it was drawn. Offers stay
## on the board with their status (OPEN, ACCEPTED, DECLINED or EXPIRED) and are
## saved that way, so a day that has offers is never drawn again, whether the
## board was opened twice or loaded from a save.
##
## Decision airline-offers-expire-at-the-end-of-their-day: an offer still OPEN
## when a later day starts becomes EXPIRED, so the open list is always today's
## choices. ensure_day does it, being the call made at each day boundary.

## Fires when offers arrive, one is accepted or declined, or a save is loaded.
signal changed

const OPEN := "open"
const ACCEPTED := "accepted"
const DECLINED := "declined"
const EXPIRED := "expired"
const STATUSES := [OPEN, ACCEPTED, DECLINED, EXPIRED]

const SAVE_VERSION := 1
const SAVE_KEYS := ["save_version", "offers"]
const OFFER_KEYS := [
	"id",
	"day",
	"airline",
	"destination",
	"departure_minute",
	"gate",
	"plane_size",
	"booked_passengers",
	"fee_per_passenger",
	"status",
]

## Tuning values. A few offers a day; the starter tier has small and medium
## planes only (larger ones wait for reputation).
const OFFERS_PER_DAY := 3
const AIRLINES := ["Gotta Air", "Nordic Wing", "Blue Fjord", "Sunhop"]
const DESTINATIONS := ["Oslo", "Berlin", "Lisbon", "Rome", "Dublin", "Athens"]
## Plane size -> [fewest, most] booked passengers.
const STARTER_SIZES := {"small": [12, 24], "medium": [24, 48]}
const FEE_MIN := 15
const FEE_MAX := 35
## Scheduled departures fall on a quarter hour from 07:00 to 21:00.
const DEPARTURE_FIRST_MINUTE := 7 * 60
const DEPARTURE_LAST_MINUTE := 21 * 60
const DEPARTURE_STEP := 15
@warning_ignore("integer_division")
const DEPARTURE_SLOTS := (DEPARTURE_LAST_MINUTE - DEPARTURE_FIRST_MINUTE) / DEPARTURE_STEP

## Offers in the order they were drawn.
var _offers: Array[Dictionary] = []


## The contract terms of `offer`, ready for FlightSim.accept_contract.
static func terms_of(offer: Dictionary) -> Dictionary:
	var terms := {}
	for key in FlightContract.TERM_KEYS:
		terms[key] = offer[key]
	return terms


## Starts `day`: every offer still open from an earlier day expires, then the
## offers for `day` are drawn from `rng` and their ids returned, or [] without
## touching `rng` when the day already has offers. `changed` fires once when
## anything expired or was drawn. A day outside 0..FlightContract.MAX_DAY pushes
## an error and changes nothing.
func ensure_day(day: int, rng: RandomNumberGenerator) -> Array[String]:
	var ids: Array[String] = []
	if day < 0 or day > FlightContract.MAX_DAY:
		push_error("OfferBoard: day %d is outside 0..%d" % [day, FlightContract.MAX_DAY])
		return ids
	var expired := _expire_before(day)
	var drawn := not _has_day(day)
	if drawn:
		for number in range(1, OFFERS_PER_DAY + 1):
			var offer := _draw(day, number, rng)
			_offers.append(offer)
			ids.append(offer["id"])
	if expired or drawn:
		changed.emit()
	return ids


## Copies of the offers still waiting for an answer, in the order drawn.
func open_offers() -> Array[Dictionary]:
	var open: Array[Dictionary] = []
	for offer in _offers:
		if offer["status"] == OPEN:
			open.append(offer.duplicate())
	return open


## A copy of the offer with this id, whatever its status, or {} if unknown.
func offer_of(id: String) -> Dictionary:
	var index := _index_of(id)
	return _offers[index].duplicate() if index >= 0 else {}


## Turns an open offer into a contract in `sim`. False (with an error) for an
## unknown or settled offer, or when the sim refuses the terms, for example a
## gate clash; a refused offer stays open.
func accept(id: String, sim: FlightSim) -> bool:
	var index := _index_of(id)
	if index < 0 or _offers[index]["status"] != OPEN:
		push_error("OfferBoard.accept: '%s' is not an open offer" % id)
		return false
	if not sim.accept_contract(terms_of(_offers[index])):
		return false
	_offers[index]["status"] = ACCEPTED
	changed.emit()
	return true


## Removes an open offer from the open list. False (with an error) for an
## unknown or settled offer.
func decline(id: String) -> bool:
	var index := _index_of(id)
	if index < 0 or _offers[index]["status"] != OPEN:
		push_error("OfferBoard.decline: '%s' is not an open offer" % id)
		return false
	_offers[index]["status"] = DECLINED
	changed.emit()
	return true


## JSON-safe state for a save: every offer with its day and status.
func to_snapshot() -> Dictionary:
	var list := []
	for offer in _offers:
		list.append(offer.duplicate())
	return {"save_version": SAVE_VERSION, "offers": list}


## Restores a to_snapshot() dictionary, including one that went through JSON.
## Pushes an error and returns false, leaving the board unchanged, when
## anything is missing, mistyped or invalid, including an offer the board
## could not have drawn and a day that does not hold its whole offer set.
func from_snapshot(data: Dictionary) -> bool:
	var loaded: Array[Dictionary] = []
	var problem := _load_problem(data, loaded)
	if problem != "":
		push_error("OfferBoard.from_snapshot: %s" % problem)
		return false
	_offers = loaded
	changed.emit()
	return true


## Every draw is made for every offer, in this order, so the RNG advances by
## the same amount whatever the values turn out to be.
func _draw(day: int, number: int, rng: RandomNumberGenerator) -> Dictionary:
	var airline: String = AIRLINES[rng.randi_range(0, AIRLINES.size() - 1)]
	var destination: String = DESTINATIONS[rng.randi_range(0, DESTINATIONS.size() - 1)]
	var minute := DEPARTURE_FIRST_MINUTE + rng.randi_range(0, DEPARTURE_SLOTS) * DEPARTURE_STEP
	var gate: String = FlightSim.GATES[rng.randi_range(0, FlightSim.GATES.size() - 1)]
	var size: String = STARTER_SIZES.keys()[rng.randi_range(0, STARTER_SIZES.size() - 1)]
	var booked_range: Array = STARTER_SIZES[size]
	return {
		"id": "O%dN%d" % [day, number],
		"day": day,
		"airline": airline,
		"destination": destination,
		"departure_minute": minute,
		"gate": gate,
		"plane_size": size,
		"booked_passengers": rng.randi_range(booked_range[0], booked_range[1]),
		"fee_per_passenger": rng.randi_range(FEE_MIN, FEE_MAX),
		"status": OPEN,
	}


## Marks every open offer drawn before `day` expired; true if any was.
func _expire_before(day: int) -> bool:
	var any := false
	for offer in _offers:
		if offer["status"] == OPEN and offer["day"] < day:
			offer["status"] = EXPIRED
			any = true
	return any


func _has_day(day: int) -> bool:
	for offer in _offers:
		if offer["day"] == day:
			return true
	return false


func _index_of(id: String) -> int:
	for i in _offers.size():
		if _offers[i]["id"] == id:
			return i
	return -1


## "" and `into` filled with the saved offers, or what is wrong with `data`.
func _load_problem(data: Dictionary, into: Array[Dictionary]) -> String:
	var problem := _top_problem(data)
	if problem != "":
		return problem
	var seen := {}
	var per_day := {}
	for entry in data["offers"]:
		problem = _offer_problem(entry)
		if problem != "":
			return problem
		var offer := {}
		for key in OFFER_KEYS:
			var value: Variant = entry[key]
			offer[key] = int(value) if typeof(value) == TYPE_FLOAT else value
		if seen.has(offer["id"]):
			return "offer id '%s' appears twice" % offer["id"]
		seen[offer["id"]] = true
		per_day[offer["day"]] = per_day.get(offer["day"], 0) + 1
		into.append(offer)
	# Ids are unique and canonical for their day, so a full count is the full set.
	for day in per_day:
		if per_day[day] != OFFERS_PER_DAY:
			return "day %d must hold all %d of its offers" % [day, OFFERS_PER_DAY]
	return _status_problem(into)


## "" when the statuses are ones a run could have saved: offers expire when a
## later day starts, so an earlier day has none open and an expired offer has a
## later recorded day behind it.
func _status_problem(offers: Array[Dictionary]) -> String:
	var latest := -1
	for offer in offers:
		latest = maxi(latest, offer["day"])
	for offer in offers:
		if offer["status"] == OPEN and offer["day"] < latest:
			return "offer %s is open but day %d has started" % [offer["id"], latest]
		if offer["status"] == EXPIRED and offer["day"] >= latest:
			return "offer %s is expired but no later day is recorded" % offer["id"]
	return ""


## "" when `data` is exactly SAVE_KEYS with the current version and an array.
func _top_problem(data: Dictionary) -> String:
	for key in data.keys():
		if not SAVE_KEYS.has(key):
			return "unknown key '%s'" % key
	for key in SAVE_KEYS:
		if not data.has(key):
			return "missing key '%s'" % key
	if not WholeNumber.is_whole(data["save_version"]) or data["save_version"] != SAVE_VERSION:
		return "save_version must be %d" % SAVE_VERSION
	if typeof(data["offers"]) != TYPE_ARRAY:
		return "offers must be an array"
	return ""


## "" when `entry` is exactly OFFER_KEYS with valid values.
func _offer_problem(entry: Variant) -> String:
	if typeof(entry) != TYPE_DICTIONARY:
		return "an offer must be a dictionary"
	for key in entry.keys():
		if not OFFER_KEYS.has(key):
			return "unknown offer key '%s'" % key
	for key in OFFER_KEYS:
		if not entry.has(key):
			return "missing offer key '%s'" % key
	if not STATUSES.has(entry["status"]):
		return "status must be one of %s" % [STATUSES]
	var day: Variant = entry["day"]
	if not WholeNumber.is_whole(day) or day < 0 or day > FlightContract.MAX_DAY:
		return "day must be a whole number from 0 to %d" % FlightContract.MAX_DAY
	var problem := FlightContract.problem(terms_of(entry), FlightContract.TERM_KEYS)
	if problem == "":
		problem = _undrawable_problem(entry)
	return problem


## "" when `entry`, already valid as a contract, is something _draw could have
## made: a canonical id for its day, and every term inside the draw's ranges.
## Reads the same constants _draw does, so the two cannot drift apart.
func _undrawable_problem(entry: Dictionary) -> String:
	var day := int(entry["day"])
	var ids := []
	for number in range(1, OFFERS_PER_DAY + 1):
		ids.append("O%dN%d" % [day, number])
	if not ids.has(entry["id"]):
		return "offer id '%s' is not one of day %d's %s" % [entry["id"], day, ids]
	if not AIRLINES.has(entry["airline"]) or not DESTINATIONS.has(entry["destination"]):
		return "offer %s has an airline or destination the board never draws" % entry["id"]
	if not FlightSim.GATES.has(entry["gate"]) or not STARTER_SIZES.has(entry["plane_size"]):
		return "offer %s has a gate or plane size the board never draws" % entry["id"]
	return _range_problem(entry)


## "" when the passengers, fee and departure are values _draw can produce.
func _range_problem(entry: Dictionary) -> String:
	var booked_range: Array = STARTER_SIZES[entry["plane_size"]]
	var booked := int(entry["booked_passengers"])
	if booked < booked_range[0] or booked > booked_range[1]:
		return "offer %s books %d passengers outside its size's range" % [entry["id"], booked]
	var fee := int(entry["fee_per_passenger"])
	if fee < FEE_MIN or fee > FEE_MAX:
		return "offer %s has a fee outside %d..%d" % [entry["id"], FEE_MIN, FEE_MAX]
	var offset := int(entry["departure_minute"]) - DEPARTURE_FIRST_MINUTE
	if offset < 0 or offset > DEPARTURE_SLOTS * DEPARTURE_STEP or offset % DEPARTURE_STEP != 0:
		return "offer %s departs off the board's departure slots" % entry["id"]
	return ""
