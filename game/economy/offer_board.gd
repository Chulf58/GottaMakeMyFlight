# gdlint:disable = max-public-methods
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
##
## Given the FlightSim, ensure_day fits the new day's departures to it (decision
## airline-offers-2-a-day-fit-the-free-gate-slots-1-needs-more): two offers at
## slots the gates have room for, one where another gate is needed. The fitted
## minute is the offer's saved departure, so a load never fits again.
##
## Each offer carries the term "traits" (OfferTraits): two of a day's offers are
## paired with an upside and a downside, one is plain. The traits come from
## OfferTraits.draw_day, a stream of their own seeded from the rng's seed (the
## run seed) and the day, so `rng` advances exactly as it did without traits.
## The fee and booking traits are folded into the offer's fee_per_passenger and
## booked_passengers when it is drawn; those stored terms are what a contract
## pays and books.
##
## Loyal airline: the board counts, per airline, the days on which one of its
## contracts with OfferTraits.LOYAL_AIRLINE had a flight depart (note_flown,
## called by OfferDesk from the flights' departures). Once an airline has
## OfferTraits.LOYAL_DAYS of them, each offer it is drawn after that has its fee
## raised by OfferTraits.loyal_fee_of, after the fee traits, and is marked
## "loyal" for the card. The count is saved; it never stacks past one raise.

## Fires when offers arrive, one is accepted or declined, or a save is loaded.
signal changed

const OPEN := "open"
const ACCEPTED := "accepted"
const DECLINED := "declined"
const EXPIRED := "expired"
const STATUSES := [OPEN, ACCEPTED, DECLINED, EXPIRED]

## 2: small flights carry 8-16 passengers (was 12-24), so a version 1 save may
## hold a count no small offer can have now.
## 3: tier 2 airlines offer medium planes while large is held back
## (PlaneClasses.max_offer_class), so the offers a board saves changed. A
## version 2 save is refused; there is no migration.
## 4: every offer has its "traits" term (OfferTraits), and a traited fee or
## booking may lie outside the plain draw ranges. A version 3 save is refused;
## there is no migration.
## 5: the Loyal airline count ("loyalty": airline -> {"days", "last_day"}) and
## each offer's "loyal" mark. A version 4 save is refused; there is no migration.
## 6: offers may carry Odd hours (departing at 06:00 or 22:00) and Exit fee, and
## the traits are drawn from OfferTraits seed version 3. A version 5 save is
## refused; there is no migration.
## 7: small offers carry 4-8 passengers and 30-70 base fees (were 8-16 and
## 15-35, ruling small-plane-passenger-count-and-fare-balance-4-8-passengers).
## A version 6 save is refused; there is no migration.
## 8: dedicated "charters" array for same-day one-off charter offers (P4).
## A version 7 save is refused; there is no migration.
const SAVE_VERSION := 8
const SAVE_KEYS := ["save_version", "offers", "loyalty", "charters"]
const CHARTER_SEED_VERSION := 1
const CHARTER_PREFIX := "CH"
## Cutoff ticks before departure (= FlightTimetable.departure_offset at BASE for
## CHARTER_BOARDING_TICKS = 380 -> 1840 ticks / 92 min).
const CHARTER_CUTOFF_LEAD_TICKS := 1840
const CHARTER_MIN_LEAD_MINUTES := 105
const CHARTER_MAX_LEAD_MINUTES := 240
const CHARTER_GAP_MARGIN_TICKS := 300
const CHARTER_COOLDOWN_MINUTES := 150
const MAX_CHARTERS_PER_DAY := 3
## Active daytime window for charter offers (06:00..19:30), so overnight fast-
## forward ticks never open or consume daily charter caps before morning.
const CHARTER_FIRST_OFFER_MINUTE := GameCalendar.START_MINUTE
const CHARTER_LAST_OFFER_MINUTE := 19 * 60 + 30
## Sorted, so a saved count's keys can be compared with it.
const LOYALTY_KEYS := ["days", "last_day"]
const LOYAL_KEY := "loyal"
const OFFER_KEYS := [
	"id",
	"day",
	"airline",
	"destination",
	"departure_minute",
	"plane_size",
	"booked_passengers",
	"fee_per_passenger",
	FlightContract.TRAITS_KEY,
	LOYAL_KEY,
	"status",
]
const CHARTER_KEYS := [
	"id",
	"day",
	"airline",
	"destination",
	"departure_minute",
	"plane_size",
	"booked_passengers",
	"fee_per_passenger",
	FlightContract.TRAITS_KEY,
	LOYAL_KEY,
	"status",
	FlightContract.ONE_OFF_DAY_KEY,
	"cutoff_tick",
]

## Tuning values. A few offers a day; the starter tier has small and medium
## planes only (larger ones wait for reputation). AIRLINES, STARTER_SIZES and
## FEE_MIN..FEE_MAX are tier 0 of the tier tables below (small planes draw
## SMALL_FEE_MIN..SMALL_FEE_MAX). Every size's passenger range sits inside its
## plane class's range (PlaneClasses.CLASSES, decision runway-upgrade-works-wait-
## for-a-timetable-gap-passengers-per-plane-class); FlightContract.problem
## refuses a count outside the class's range.
const OFFERS_PER_DAY := 3
## Mid-day refills on a day (ruling day-1-pacing-fit-day-1-offers-into-same-day-
## afternoon-evenin): at most MAX_REFILLS_PER_DAY batches of OFFERS_PER_DAY
## follow the day's initial draw.
const MAX_REFILLS_PER_DAY := 4
const MAX_DAY_OFFERS := OFFERS_PER_DAY * (1 + MAX_REFILLS_PER_DAY)
const REFILL_SEED_VERSION := 1
const AIRLINES := ["Gotta Air", "Nordic Wing", "Blue Fjord", "Sunhop"]
const DESTINATIONS := ["Oslo", "Berlin", "Lisbon", "Rome", "Dublin", "Athens"]
## Plane size -> [fewest, most] booked passengers.
const STARTER_SIZES := {"small": [4, 8], "medium": [24, 48]}
const FEE_MIN := 15
const FEE_MAX := 35
const SMALL_FEE_MIN := 30
const SMALL_FEE_MAX := 70
## Airline tiers, unlocked by the airport rating (RatingFormula.tier): tier t
## draws from the airlines of tiers 0..t. An airline's own tier decides the
## plane sizes it flies (size -> [fewest, most] booked passengers) and its fee
## per passenger [lowest, highest]: bigger airlines, better offers. TIER_SIZES is
## what a tier's airlines will fly once every class is on offer; what is drawn
## now is offered_sizes(), which PlaneClasses.max_offer_class() limits. Tier 2
## lists medium too, so its airlines stay on the board while large is held back.
const TIER_AIRLINES: Array = [
	AIRLINES, ["Polar Jet", "Aegean Sky"], ["Skyline Global", "Meridian Air"]
]
const TIER_SIZES: Array = [
	STARTER_SIZES,
	{"medium": [24, 48], "large": [48, 96]},
	{"medium": [24, 48], "large": [64, 120]},
]
const TIER_FEES: Array = [[FEE_MIN, FEE_MAX], [25, 45], [40, 60]]
const MAX_TIER := 2
## Scheduled departures fall on a quarter hour from 07:00 to 21:00, the plain
## contract window; an Odd hours offer departs at 06:00 or 22:00, the ends of
## its wider window (FlightContract.window, slots_of). DEPARTURE_SLOTS is the plain window's
## last slot index.
const DEPARTURE_FIRST_MINUTE := FlightContract.FIRST_DEPARTURE_MINUTE
const DEPARTURE_LAST_MINUTE := FlightContract.LAST_DEPARTURE_MINUTE
const DEPARTURE_STEP := 15
@warning_ignore("integer_division")
const DEPARTURE_SLOTS := (DEPARTURE_LAST_MINUTE - DEPARTURE_FIRST_MINUTE) / DEPARTURE_STEP
## With flights to fit to, a day's first FIT_OFFERS offers depart at slots the
## gates have room for and the others where another gate is needed (decision
## airline-offers-2-a-day-fit-the-free-gate-slots-1-needs-more).
const FIT_OFFERS := 2

## Offers in the order they were drawn.
var _offers: Array[Dictionary] = []
## Dedicated one-off same-day charters in the order they were drawn.
var _charters: Array[Dictionary] = []
## Airline -> {"days": flown days counted (1..LOYAL_DAYS), "last_day": the last}.
var _loyalty: Dictionary = {}
## True while from_snapshot() emits `changed`, so listeners do not treat a load
## as a player action that triggers a refill.
var _loading := false


## The [lowest, highest] base fee per passenger drawn for `plane_size` at `tier`.
static func fee_range_for(tier: int, plane_size: String) -> Array:
	if plane_size == PlaneClasses.SMALL:
		return [SMALL_FEE_MIN, SMALL_FEE_MAX]
	return TIER_FEES[tier]


## The airline tier of `airline` (0 for a starter airline), or -1 if no tier has it.
static func tier_of(airline: String) -> int:
	for tier in TIER_AIRLINES.size():
		if TIER_AIRLINES[tier].has(airline):
			return tier
	return -1


## The plane sizes (size -> [fewest, most] booked passengers) an airline of
## `tier` is offered flying now: its TIER_SIZES without any class above
## PlaneClasses.max_offer_class() or above `runway_class`, the biggest class the
## runway takes (Runway.size_takes). The one place the offer gate is applied. An
## airline whose sizes are all above the runway offers none.
static func offered_sizes(tier: int, runway_class := PlaneClasses.LARGE) -> Dictionary:
	var sizes := {}
	for size: String in TIER_SIZES[tier]:
		if PlaneClasses.is_offered(size) and Runway.size_takes(runway_class, size):
			sizes[size] = TIER_SIZES[tier][size]
	return sizes


## The departure minutes an offer of `traits` may be drawn or fitted at,
## earliest first: the 57 quarter hours from 07:00 to 21:00, or for an Odd hours
## offer only the two ends of its FlightContract.window, 06:00 and 22:00 (user
## ruling odd-hours-and-exit-fee-offer-traits-odd-hours-widens-the-dep: "Odd
## hours offers draw 06:00 or 22:00, and the card says so up front").
static func slots_of(traits: Dictionary) -> Array[int]:
	var span := FlightContract.window(traits)
	var out: Array[int] = []
	if OfferTraits.window_widening(traits) > 0:
		out.append_array([span[0], span[1]])
		return out
	for minute in range(span[0], span[1] + 1, DEPARTURE_STEP):
		out.append(minute)
	return out


## The contract terms of `offer`, its traits included, ready for
## FlightSim.accept_contract.
static func terms_of(offer: Dictionary) -> Dictionary:
	var terms := {}
	for key in FlightContract.TERM_KEYS:
		terms[key] = offer[key]
	terms[FlightContract.TRAITS_KEY] = offer[FlightContract.TRAITS_KEY]
	if offer.has(FlightContract.ONE_OFF_DAY_KEY):
		terms[FlightContract.ONE_OFF_DAY_KEY] = int(offer[FlightContract.ONE_OFF_DAY_KEY])
	return terms


## Starts `day`: every offer still open from an earlier day expires, then the
## offers for `day` are drawn from `rng` and their ids returned, or [] without
## touching `rng` when the day already has offers. `tier` (0..MAX_TIER, the
## airport rating's RatingFormula.tier) picks which airlines the new offers may
## come from; it does not change how far `rng` advances. `runway_class` (the
## runway's size, Runway.size) limits the plane classes the offers may have to
## those the runway takes, and drops the airlines that fly none of them; it
## does not change how far `rng` advances either, so a seed replays whatever
## the runway. With `flights`, the drawn departures are then fitted to it
## (_fit), which does not touch `rng` either; without, they stay as drawn.
## The offers' traits are drawn by OfferTraits.draw_day from `rng`'s seed, at
## levels by `tier`, leaving out traits whose need `live` ({OfferTraits.NEEDS_BAGS:
## bool, OfferTraits.NEEDS_SHOPS: bool}, a missing need is not live) does not
## hold; that does not touch `rng` either.
## `changed` fires once when anything expired or was drawn. A day
## outside 0..FlightContract.MAX_DAY, a tier outside 0..MAX_TIER or a runway
## class that is not a plane class pushes an error and changes nothing.
func ensure_day(
	day: int,
	rng: RandomNumberGenerator,
	tier := 0,
	runway_class := PlaneClasses.LARGE,
	flights: FlightSim = null,
	live := {},
	min_minute := -1
) -> Array[String]:
	var ids: Array[String] = []
	if not _draw_args_valid(day, tier, runway_class):
		return ids
	var expired := _expire_before(day)
	expired = _expire_charters_before(day) or expired
	var drawn := not _has_day(day)
	if drawn:
		var fresh: Array[Dictionary] = []
		var traits := OfferTraits.draw_day(rng.seed, day, OFFERS_PER_DAY, tier, live)
		for number in range(1, OFFERS_PER_DAY + 1):
			var offer := _draw(day, number, rng, tier, runway_class, traits[number - 1])
			_give_traits(offer, traits[number - 1], is_loyal(offer["airline"]))
			fresh.append(offer)
		if flights != null:
			_fit(fresh, flights, min_minute)
		for offer in fresh:
			_offers.append(offer)
			ids.append(offer["id"])
	if expired or drawn:
		changed.emit()
	return ids


## How many offers have been drawn for `day` so far (initial plus refills).
func day_offer_count(day: int) -> int:
	var count := 0
	for offer in _offers:
		if offer["day"] == day:
			count += 1
	return count


## Re-fits the still-open offers of `day` against `flights` (used when the
## airport opens so Day-1 offers fit behind the starter contract at slots >=
## `min_minute`). Touches no RNG; returns true and emits `changed` when any
## open offer's departure moved.
func refit_day(day: int, flights: FlightSim, min_minute := -1) -> bool:
	if flights == null:
		return false
	var open: Array[Dictionary] = []
	var before: Array[int] = []
	for offer in _offers:
		if offer["day"] == day and offer["status"] == OPEN:
			open.append(offer)
			before.append(int(offer["departure_minute"]))
	if open.is_empty():
		return false
	_fit(open, flights, min_minute)
	var moved := false
	for i in open.size():
		if int(open[i]["departure_minute"]) != before[i]:
			moved = true
			break
	if moved:
		changed.emit()
	return moved


## True when `flights` has at least one plain departure slot at or after
## `min_minute` for any plane size drawable at `tier` on `runway_class`.
static func has_fitting_slot(
	flights: FlightSim, tier: int, runway_class := PlaneClasses.LARGE, min_minute := -1
) -> bool:
	if not _draw_args_valid(0, tier, runway_class) or flights == null:
		return false
	var sizes := {}
	for unlocked in range(tier + 1):
		for size: String in offered_sizes(unlocked, runway_class):
			sizes[size] = true
	if sizes.is_empty():
		return false
	var slots := slots_of({})
	for size: String in sizes:
		var terms := {
			"id": "FITCHECK",
			"airline": AIRLINES[0],
			"destination": DESTINATIONS[0],
			"departure_minute": slots[0],
			"plane_size": size,
			"booked_passengers": PlaneClasses.passenger_range(size)[0],
			"fee_per_passenger": FEE_MIN,
			FlightContract.TRAITS_KEY: {},
		}
		for minute: int in slots:
			if min_minute >= 0 and minute < min_minute:
				continue
			terms["departure_minute"] = minute
			if flights.free_gates(terms).is_empty():
				continue
			if FlightFit.fits(flights, terms):
				return true
	return false


## Draws one mid-day refill batch of OFFERS_PER_DAY offers on `day` from a
## deterministic stream keyed by (`world_seed`, `day`, wave) without mutating
## SimClock.rng, expiring any leftover open offers on `day`. Refused (returns [])
## when `day` has no initial draw yet, reached MAX_REFILLS_PER_DAY, or no free
## slot >= `min_minute` remains on `flights`.
func refill_day(
	day: int,
	world_seed: int,
	tier := 0,
	runway_class := PlaneClasses.LARGE,
	flights: FlightSim = null,
	live := {},
	min_minute := -1
) -> Array[String]:
	var ids: Array[String] = []
	if not _draw_args_valid(day, tier, runway_class) or flights == null or not _has_day(day):
		return ids
	var count := day_offer_count(day)
	@warning_ignore("integer_division")
	var wave := count / OFFERS_PER_DAY
	if count % OFFERS_PER_DAY != 0 or wave < 1 or wave > MAX_REFILLS_PER_DAY:
		return ids
	if not has_fitting_slot(flights, tier, runway_class, min_minute):
		return ids
	_expire_day(day)
	var refill_seed := _refill_seed(world_seed, day, wave)
	var refill_rng := RandomNumberGenerator.new()
	refill_rng.seed = refill_seed
	var traits := OfferTraits.draw_day(refill_seed, day, OFFERS_PER_DAY, tier, live)
	var fresh: Array[Dictionary] = []
	for offset in range(1, OFFERS_PER_DAY + 1):
		var offer := _draw(day, count + offset, refill_rng, tier, runway_class, traits[offset - 1])
		_give_traits(offer, traits[offset - 1], is_loyal(offer["airline"]))
		fresh.append(offer)
	_fit(fresh, flights, min_minute)
	for offer in fresh:
		_offers.append(offer)
		ids.append(offer["id"])
	changed.emit()
	return ids


## Copies of the offers still waiting for an answer, in the order drawn.
func open_offers() -> Array[Dictionary]:
	var open: Array[Dictionary] = []
	for offer in _offers:
		if offer["status"] == OPEN:
			open.append(offer.duplicate())
	return open


## Copies of the one-off charters still waiting for an answer, in the order drawn.
func open_charters() -> Array[Dictionary]:
	var open: Array[Dictionary] = []
	for charter in _charters:
		if charter["status"] == OPEN:
			open.append(charter.duplicate())
	return open


## A copy of the offer with this id, whatever its status, or {} if unknown.
func offer_of(id: String) -> Dictionary:
	var index := _index_of(id)
	return _offers[index].duplicate() if index >= 0 else {}


## A copy of the charter with this id, whatever its status, or {} if unknown.
func charter_of(id: String) -> Dictionary:
	var index := _charter_index_of(id)
	return _charters[index].duplicate() if index >= 0 else {}


## A copy of the daily offer or charter with this id, or {} if unknown.
func any_offer_of(id: String) -> Dictionary:
	var found := offer_of(id)
	return found if not found.is_empty() else charter_of(id)


## How many charters have been drawn for `day` so far.
func day_charter_count(day: int) -> int:
	var count := 0
	for charter in _charters:
		if charter["day"] == day:
			count += 1
	return count


## True when `minute` of day (0..1439) lies in the active daytime charter window.
static func is_charter_offer_minute(minute: int) -> bool:
	return minute >= CHARTER_FIRST_OFFER_MINUTE and minute <= CHARTER_LAST_OFFER_MINUTE


## Opens at most one small-plane same-day charter on `day` if the airport is open,
## now is within active daytime hours, no charter is currently open, and at least
## one gate has a quiet daytime gap with enough lead time before departure. Uses
## an independent deterministic seed path so SimClock.rng never advances. Returns
## the new charter id or "".
func ensure_charter_for_gap(
	day: int, now: int, epoch: int, world_seed: int, runway_class: String, flights: FlightSim
) -> String:
	if (
		not _draw_args_valid(day, 0, runway_class)
		or flights == null
		or flights.opened_tick < 0
		or not is_charter_offer_minute(GameCalendar.minute_of_day(now, epoch))
		or not Runway.size_takes(runway_class, PlaneClasses.SMALL)
		or not open_charters().is_empty()
	):
		return ""
	var count := day_charter_count(day)
	if count >= MAX_CHARTERS_PER_DAY:
		return ""
	var candidates := _quiet_gap_slots(day, now, epoch, flights)
	if candidates.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = _charter_seed(world_seed, day, count + 1)
	var minute: int = candidates[rng.randi_range(0, candidates.size() - 1)]
	var airline: String = AIRLINES[rng.randi_range(0, AIRLINES.size() - 1)]
	var destination: String = DESTINATIONS[rng.randi_range(0, DESTINATIONS.size() - 1)]
	var pax_range: Array = STARTER_SIZES[PlaneClasses.SMALL]
	var fees: Array = fee_range_for(0, PlaneClasses.SMALL)
	var charter := {
		"id": "%s%dN%d" % [CHARTER_PREFIX, day, count + 1],
		"day": day,
		FlightContract.ONE_OFF_DAY_KEY: day,
		"cutoff_tick": GameCalendar.tick_at(day, minute, epoch) - CHARTER_CUTOFF_LEAD_TICKS,
		"airline": airline,
		"destination": destination,
		"departure_minute": minute,
		"plane_size": PlaneClasses.SMALL,
		"booked_passengers": rng.randi_range(pax_range[0], pax_range[1]),
		"fee_per_passenger": rng.randi_range(fees[0], fees[1]),
		FlightContract.TRAITS_KEY: OfferTraits.frozen({}),
		LOYAL_KEY: false,
		"status": OPEN,
	}
	_charters.append(charter)
	changed.emit()
	return charter["id"]


## Expires any open charter whose day has passed or whose cutoff tick passed.
func expire_charters(now: int, day: int) -> bool:
	var any := false
	for charter in _charters:
		if charter["status"] != OPEN:
			continue
		if int(charter["day"]) < day or now > int(charter["cutoff_tick"]):
			charter["status"] = EXPIRED
			any = true
	if any:
		changed.emit()
	return any


## Turns an open offer or charter into a contract in `sim`. False (with an error)
## for an unknown or settled offer, or when the sim refuses the terms; a refused
## offer stays open.
func accept(id: String, sim: FlightSim) -> bool:
	var index := _index_of(id)
	if index >= 0:
		if _offers[index]["status"] != OPEN:
			push_error("OfferBoard.accept: '%s' is not an open offer" % id)
			return false
		if not sim.accept_contract(terms_of(_offers[index])):
			return false
		_offers[index]["status"] = ACCEPTED
		QuitLog.note("offer_accepted")
		changed.emit()
		return true
	var charter_index := _charter_index_of(id)
	if charter_index < 0 or _charters[charter_index]["status"] != OPEN:
		push_error("OfferBoard.accept: '%s' is not an open offer" % id)
		return false
	if not sim.accept_contract(terms_of(_charters[charter_index])):
		return false
	_charters[charter_index]["status"] = ACCEPTED
	QuitLog.note("charter_accepted")
	changed.emit()
	return true


## Removes an open offer or charter from the open list. False (with an error)
## for an unknown or settled offer.
func decline(id: String) -> bool:
	var index := _index_of(id)
	if index >= 0:
		if _offers[index]["status"] != OPEN:
			push_error("OfferBoard.decline: '%s' is not an open offer" % id)
			return false
		_offers[index]["status"] = DECLINED
		changed.emit()
		return true
	var charter_index := _charter_index_of(id)
	if charter_index < 0 or _charters[charter_index]["status"] != OPEN:
		push_error("OfferBoard.decline: '%s' is not an open offer" % id)
		return false
	_charters[charter_index]["status"] = DECLINED
	changed.emit()
	return true


## Counts `day` as a day on which a Loyal airline contract of `airline` flew.
## True when it counted: a day already counted (or one before it) and an
## airline that already has OfferTraits.LOYAL_DAYS are not, and an airline the
## board never draws pushes an error.
func note_flown(airline: String, day: int) -> bool:
	if tier_of(airline) < 0:
		push_error("OfferBoard.note_flown: '%s' is not an airline the board draws" % airline)
		return false
	var entry: Dictionary = _loyalty.get(airline, {"days": 0, "last_day": -1})
	if day <= entry["last_day"] or entry["days"] >= OfferTraits.LOYAL_DAYS:
		return false
	_loyalty[airline] = {"days": entry["days"] + 1, "last_day": day}
	return true


## The Loyal airline days counted for `airline`, 0 to OfferTraits.LOYAL_DAYS.
func loyal_days(airline: String) -> int:
	return _loyalty.get(airline, {"days": 0})["days"]


## Whether `airline`'s offers drawn from now on pay the loyal raise.
func is_loyal(airline: String) -> bool:
	return loyal_days(airline) >= OfferTraits.LOYAL_DAYS


## JSON-safe state for a save: every offer with its day and status, the Loyal
## airline count, and any same-day charters.
func to_snapshot() -> Dictionary:
	var list := []
	for offer in _offers:
		list.append(offer.duplicate())
	var charter_list := []
	for charter in _charters:
		charter_list.append(charter.duplicate())
	return {
		"save_version": SAVE_VERSION,
		"offers": list,
		"loyalty": _loyalty.duplicate(true),
		"charters": charter_list,
	}


## True while from_snapshot() is emitting `changed`.
func is_loading() -> bool:
	return _loading


## Restores a to_snapshot() dictionary, including one that went through JSON.
## Pushes an error and returns false, leaving the board unchanged, when
## anything is missing, mistyped or invalid, including an offer the board
## could not have drawn and a day that does not hold its whole offer set.
func from_snapshot(data: Dictionary) -> bool:
	var loaded: Array[Dictionary] = []
	var loaded_charters: Array[Dictionary] = []
	var loyalty := {}
	var problem := _load_problem(data, loaded, loaded_charters)
	if problem == "":
		problem = _loyalty_problem(data["loyalty"], loyalty)
	if problem == "":
		problem = _loyal_marks_problem(loaded, loyalty)
	if problem != "":
		push_error("OfferBoard.from_snapshot: %s" % problem)
		return false
	_loading = true
	_offers = loaded
	_charters = loaded_charters
	_loyalty = loyalty
	changed.emit()
	_loading = false
	return true


## Every draw is made for every offer, in this order, so the RNG advances by
## the same amount whatever the values turn out to be. The departure is one
## draw over the slots of the offer's `traits` (slots_of), so an Odd hours offer
## draws from its 2 slots and every other from 57: one call either way.
func _draw(
	day: int,
	number: int,
	rng: RandomNumberGenerator,
	tier: int,
	runway_class: String,
	traits: Dictionary
) -> Dictionary:
	var airlines: Array = []
	for unlocked in range(tier + 1):
		# A tier whose airlines fly nothing the runway takes stays off the board;
		# the pick below is still one draw.
		if not offered_sizes(unlocked, runway_class).is_empty():
			airlines.append_array(TIER_AIRLINES[unlocked])
	var airline: String = airlines[rng.randi_range(0, airlines.size() - 1)]
	var own := tier_of(airline)
	var sizes := offered_sizes(own, runway_class)
	var destination: String = DESTINATIONS[rng.randi_range(0, DESTINATIONS.size() - 1)]
	var slots := slots_of(traits)
	var minute: int = slots[rng.randi_range(0, slots.size() - 1)]
	# A pick among one size would skip its draw, so the range is never below two and
	# the RNG advances the same whatever the offered sizes are.
	var size: String = sizes.keys()[rng.randi_range(0, maxi(sizes.size(), 2) - 1) % sizes.size()]
	var booked_range: Array = sizes[size]
	var fees: Array = fee_range_for(own, size)
	return {
		"id": "O%dN%d" % [day, number],
		"day": day,
		"airline": airline,
		"destination": destination,
		"departure_minute": minute,
		"plane_size": size,
		"booked_passengers": rng.randi_range(booked_range[0], booked_range[1]),
		"fee_per_passenger": rng.randi_range(fees[0], fees[1]),
		"status": OPEN,
	}


## Gives a freshly drawn `offer` its frozen `traits` and its `loyal` mark, and
## folds the fee and booking traits, then the loyal raise, into its
## fee_per_passenger and booked_passengers.
static func _give_traits(offer: Dictionary, traits: Dictionary, loyal: bool) -> void:
	var booked_range: Array = TIER_SIZES[tier_of(offer["airline"])][offer["plane_size"]]
	offer[FlightContract.TRAITS_KEY] = traits
	offer[LOYAL_KEY] = loyal
	offer["fee_per_passenger"] = _fee_of(offer["fee_per_passenger"], traits, loyal)
	offer["booked_passengers"] = OfferTraits.booked_of(
		offer["booked_passengers"], booked_range[1], traits
	)


## Moves the departures of a day's freshly drawn `offers` (in draw order) onto
## the slots `flights` has room for now (decision airline-offers-2-a-day-fit-
## the-free-gate-slots-1-needs-more, points 1 to 3). The first FIT_OFFERS get
## slots they fit at, the rest a slot where only a free gate is missing
## (FlightFit.another_gate_helps). Each offer's drawn slot index r among its d
## slots (slots_of: 57, or 2 with Odd hours) picks from its n candidate slots,
## earliest first, by floor(r * n / d), so nothing is drawn again. The two fit
## offers must also fit together, whichever is accepted first: from their
## picks on, the first slot of the second that joins the first's is taken,
## and only when none does is the first's next slot tried, so a pair is found
## whenever one exists. An offer with no candidate slot keeps the slot it was
## drawn with, and its card says why it does not fit. Read-only on `flights`:
## every check is a trial on copies of its planning state.
static func _fit(offers: Array[Dictionary], flights: FlightSim, min_minute := -1) -> void:
	if offers.is_empty():
		return
	# Per offer: [drawn slot index, how many slots it was drawn from].
	var drawn: Array[Array] = []
	for offer in offers:
		var slots := slots_of(offer[FlightContract.TRAITS_KEY])
		drawn.append([slots.find(int(offer["departure_minute"])), slots.size()])
	var cache := {}
	var first: Dictionary = offers[0]
	var firsts := _slots_where(flights, first, cache, true, min_minute)
	if offers.size() == 1:
		if not firsts.is_empty():
			first["departure_minute"] = firsts[_pick(drawn[0], firsts.size())]
		return
	var second: Dictionary = offers[1]
	var seconds := _slots_where(flights, second, cache, true, min_minute)
	var paired := false
	if not firsts.is_empty():
		var start := _pick(drawn[0], firsts.size())
		first["departure_minute"] = firsts[start]
		if not seconds.is_empty():
			var first_key := _slot_key(first, min_minute)
			var second_key := _slot_key(second, min_minute)
			var first_cache: Dictionary = cache[first_key]
			var second_cache: Dictionary = cache[second_key]
			var free_cache := {}
			var first_free := _free_gate_map(flights, first, firsts, free_cache)
			var second_free := _free_gate_map(flights, second, seconds, free_cache)
			for step in firsts.size():
				var minute: int = firsts[(start + step) % firsts.size()]
				var joined := _joined_slot(
					flights,
					_terms_at(first, minute),
					first_cache[minute]["gate"],
					first_free[minute],
					second,
					seconds,
					drawn[1],
					second_cache,
					second_free
				)
				if joined >= 0:
					first["departure_minute"] = minute
					second["departure_minute"] = joined
					paired = true
					break
	if not paired and not seconds.is_empty():
		second["departure_minute"] = seconds[_pick(drawn[1], seconds.size())]
	for index in range(FIT_OFFERS, offers.size()):
		var pushes := _slots_where(flights, offers[index], cache, false, min_minute)
		if not pushes.is_empty():
			offers[index]["departure_minute"] = pushes[_pick(drawn[index], pushes.size())]


static func _slot_key(offer: Dictionary, min_minute: int) -> String:
	var traits: Dictionary = offer[FlightContract.TRAITS_KEY]
	return "%s|%s|%d" % [offer["plane_size"], FlightContract.window(traits), min_minute]


static func _free_gate_map(
	flights: FlightSim, offer: Dictionary, minutes: Array[int], free_cache: Dictionary
) -> Dictionary:
	var size: String = offer["plane_size"]
	var window := FlightContract.window(offer[FlightContract.TRAITS_KEY])
	var out := {}
	for minute in minutes:
		var cache_key := "%s|%s|%d" % [size, window, minute]
		if not free_cache.has(cache_key):
			free_cache[cache_key] = flights.free_gates(_terms_at(offer, minute))
		out[minute] = free_cache[cache_key]
	return out


## The departure minutes, earliest first, at which `offer` fits `flights` now
## (`fitting`), or at which only a free gate is missing (not `fitting`).
## `cache` keeps the FlightFit assessments per minute for each plane size and
## departure window: an offer's fit depends only on its plane size, its
## departure and the window its traits allow (FlightContract.window), not its
## other terms. The second look at a gate blocker is taken only when a push slot
## is asked for.
static func _slots_where(
	flights: FlightSim, offer: Dictionary, cache: Dictionary, fitting: bool, min_minute := -1
) -> Array[int]:
	var traits: Dictionary = offer[FlightContract.TRAITS_KEY]
	var key := _slot_key(offer, min_minute)
	if not cache.has(key):
		var by_minute := {}
		for minute in slots_of(traits):
			if min_minute >= 0 and minute < min_minute:
				continue
			by_minute[minute] = FlightFit.assess(flights, _terms_at(offer, minute), [], false)
		cache[key] = by_minute
	var out: Array[int] = []
	for minute: int in cache[key]:
		var assessment: Dictionary = cache[key][minute]
		if fitting:
			if assessment["fits"]:
				out.append(minute)
		elif assessment["blocker"] == FlightSim.BLOCKER_GATE:
			if not assessment.has("looked_again"):
				assessment["looked_again"] = true
				assessment["another_gate_helps"] = FlightFit.another_gate_helps(
					flights, _terms_at(offer, minute)
				)
			if assessment["another_gate_helps"]:
				out.append(minute)
	return out


## The first minute of `seconds` (where `second` fits alone), from the one
## drawn slot `drawn` ([index, slot count], as _pick takes it) picks on and
## round, at which `second` and the contract of `first_terms` both fit,
## whichever is accepted first; -1 for none.
static func _joined_slot(
	flights: FlightSim,
	first_terms: Dictionary,
	first_gate: String,
	first_free: Array[String],
	second: Dictionary,
	seconds: Array[int],
	drawn: Array,
	second_cache: Dictionary,
	second_free: Dictionary
) -> int:
	var start := _pick(drawn, seconds.size())
	for step in seconds.size():
		var minute: int = seconds[(start + step) % seconds.size()]
		var second_terms := _terms_at(second, minute)
		var second_gate: String = second_cache[minute]["gate"]
		if not flights.gates_pair_compatible(
			first_terms, first_gate, first_free, second_terms, second_gate, second_free[minute]
		):
			continue
		if flights.trial_pair_fits(first_terms, first_gate, second_terms, second_gate):
			return minute
	return -1


## The candidate of `count` that drawn slot `drawn` ([r, d]: index r of the d
## slots the offer was drawn from) maps to: floor(r * count / d), which spreads
## the draws evenly over the candidates (a remainder would favour the first
## ones), and reaches the last candidate from the last slot of either window.
static func _pick(drawn: Array, count: int) -> int:
	@warning_ignore("integer_division")
	return int(drawn[0]) * count / int(drawn[1])


## The contract terms of `offer` departing at `minute` instead.
static func _terms_at(offer: Dictionary, minute: int) -> Dictionary:
	var terms := terms_of(offer)
	terms["departure_minute"] = minute
	return terms


## Marks every open offer drawn before `day` expired; true if any was.
func _expire_before(day: int) -> bool:
	var any := false
	for offer in _offers:
		if offer["status"] == OPEN and offer["day"] < day:
			offer["status"] = EXPIRED
			any = true
	return any


## Marks every open charter drawn before `day` expired; true if any was.
func _expire_charters_before(day: int) -> bool:
	var any := false
	for charter in _charters:
		if charter["status"] == OPEN and int(charter["day"]) < day:
			charter["status"] = EXPIRED
			any = true
	return any


func _quiet_gap_slots(day: int, now: int, epoch: int, flights: FlightSim) -> Array[int]:
	var out: Array[int] = []
	var min_tick := now + CHARTER_MIN_LEAD_MINUTES * GameCalendar.TICKS_PER_MINUTE
	var max_tick := now + CHARTER_MAX_LEAD_MINUTES * GameCalendar.TICKS_PER_MINUTE
	for minute in slots_of({}):
		var dep_tick := GameCalendar.tick_at(day, minute, epoch)
		if dep_tick < min_tick or dep_tick > max_tick:
			continue
		if _near_existing_charter(day, minute):
			continue
		if _is_quiet_gap_slot(flights, day, minute, epoch):
			out.append(minute)
	return out


func _near_existing_charter(day: int, minute: int) -> bool:
	for charter in _charters:
		if int(charter["day"]) == day:
			if absi(int(charter["departure_minute"]) - minute) < CHARTER_COOLDOWN_MINUTES:
				return true
	return false


static func _is_quiet_gap_slot(flights: FlightSim, day: int, minute: int, epoch: int) -> bool:
	var terms := {
		"id": "CHGAPCHECK",
		"airline": AIRLINES[0],
		"destination": DESTINATIONS[0],
		"departure_minute": minute,
		"plane_size": PlaneClasses.SMALL,
		"booked_passengers": STARTER_SIZES[PlaneClasses.SMALL][0],
		"fee_per_passenger": SMALL_FEE_MIN,
		FlightContract.TRAITS_KEY: {},
		FlightContract.ONE_OFF_DAY_KEY: day,
	}
	var grounds := flights.gate_grounds()
	for gate: String in flights.gate_ids():
		var ground: Dictionary = grounds.get(gate, {})
		if ground.is_empty():
			continue
		var candidate := FlightContract.assigned(
			terms.merged({"first_day": day}), gate, ground["stand"]
		)
		if candidate.is_empty():
			continue
		var c_starts := FlightTimetable.starts_for(candidate, day, epoch)
		var c_hold := FlightTimetable.gate_hold_span(c_starts, PlaneClasses.SMALL)
		var win_start := c_hold[0] - CHARTER_GAP_MARGIN_TICKS
		var win_end := c_hold[1] + CHARTER_GAP_MARGIN_TICKS
		if not _gate_quiet_over(flights, gate, day, epoch, win_start, win_end):
			continue
		if flights.trial_assignment(terms, [], false, gate)["gate"] == gate:
			return true
	return false


static func _gate_quiet_over(
	flights: FlightSim, gate: String, day: int, epoch: int, win_start: int, win_end: int
) -> bool:
	for fid in flights.flight_ids():
		if flights.flight_gate(fid) != gate:
			continue
		var starts: Array[int] = []
		for s in FlightSim.STATE_COUNT:
			starts.append(flights.state_start(fid, s))
		var cid := flights.flight_contract_id(fid)
		var p_size: String = (
			flights.contract_of(cid).get("plane_size", PlaneClasses.MEDIUM)
			if cid != ""
			else PlaneClasses.MEDIUM
		)
		var hold := FlightTimetable.gate_hold_span(starts, p_size)
		if FlightTimetable.holds_overlap(hold[0], hold[1], win_start, win_end):
			return false
	var start_days := flights.start_days
	for cid in flights.contract_ids():
		var other := flights.contract_of(cid)
		if other["gate"] != gate or flights.contract_end_day(cid) >= 0:
			continue
		var check_days: Array[int] = [day - 1, day, day + 1]
		if FlightContract.is_charter(other):
			check_days = [FlightContract.one_off_day(other)]
		for d in check_days:
			if d < int(start_days.get(cid, 0)):
				continue
			if flights.state_of(FlightTimetable.occurrence_id(cid, d)) >= 0:
				continue
			var hold := FlightTimetable.gate_hold_span(
				FlightTimetable.starts_for(other, d, epoch), other["plane_size"]
			)
			if FlightTimetable.holds_overlap(hold[0], hold[1], win_start, win_end):
				return false
	return true


static func _charter_seed(world_seed: int, day: int, number: int) -> int:
	var text := (
		"gmmf-charter|%s|%s|%s|%s"
		% [str(CHARTER_SEED_VERSION), str(world_seed), str(day), str(number)]
	)
	var value := IncidentRoll.fnv1a_32(text.to_utf8_buffer())
	return value if value != 0 else 1


static func _charter_number(id: String) -> int:
	var split := id.find("N")
	if split < 3 or not id.begins_with(CHARTER_PREFIX):
		return -1
	var number_text := id.substr(split + 1)
	return number_text.to_int() if number_text.is_valid_int() else -1


func _charter_index_of(id: String) -> int:
	for i in _charters.size():
		if _charters[i]["id"] == id:
			return i
	return -1


## Marks every open offer on `day` expired when a mid-day refill replaces them.
func _expire_day(day: int) -> void:
	for offer in _offers:
		if offer["status"] == OPEN and offer["day"] == day:
			offer["status"] = EXPIRED


static func _draw_args_valid(day: int, tier: int, runway_class: String) -> bool:
	if day < 0 or day > FlightContract.MAX_DAY:
		push_error("OfferBoard: day %d is outside 0..%d" % [day, FlightContract.MAX_DAY])
		return false
	if tier < 0 or tier > MAX_TIER:
		push_error("OfferBoard: tier %d is outside 0..%d" % [tier, MAX_TIER])
		return false
	if not PlaneClasses.is_plane_class(runway_class):
		push_error("OfferBoard: runway class '%s' is not a plane class" % runway_class)
		return false
	return true


static func _refill_seed(world_seed: int, day: int, wave: int) -> int:
	var text := (
		"gmmf-offer-refill|%s|%s|%s|%s"
		% [str(REFILL_SEED_VERSION), str(world_seed), str(day), str(wave)]
	)
	var value := IncidentRoll.fnv1a_32(text.to_utf8_buffer())
	return value if value != 0 else 1


static func _offer_number(id: String) -> int:
	var split := id.find("N")
	if split < 2 or not id.begins_with("O"):
		return -1
	var number_text := id.substr(split + 1)
	return number_text.to_int() if number_text.is_valid_int() else -1


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


## "" and `into` filled with the saved offers and `into_charters` with saved
## charters, or what is wrong with `data`.
func _load_problem(
	data: Dictionary, into: Array[Dictionary], into_charters: Array[Dictionary]
) -> String:
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
		offer[FlightContract.TRAITS_KEY] = OfferTraits.frozen(entry[FlightContract.TRAITS_KEY])
		if seen.has(offer["id"]):
			return "offer id '%s' appears twice" % offer["id"]
		seen[offer["id"]] = true
		per_day[offer["day"]] = per_day.get(offer["day"], 0) + 1
		into.append(offer)
	# Ids are unique and canonical for their day, so a contiguous multiple of
	# OFFERS_PER_DAY holds every batch of that day.
	for day in per_day:
		var count := int(per_day[day])
		if count % OFFERS_PER_DAY != 0 or count > MAX_DAY_OFFERS:
			return "day %d must hold a whole set of %d offers" % [day, OFFERS_PER_DAY]
		for number in range(1, count + 1):
			if not seen.has("O%dN%d" % [day, number]):
				return "day %d is missing offer O%dN%d" % [day, day, number]
	problem = _status_problem(into, per_day)
	if problem == "":
		problem = _charters_load_problem(data.get("charters", []), into, into_charters)
	return problem


func _charters_load_problem(
	entries: Array, offers: Array[Dictionary], into: Array[Dictionary]
) -> String:
	var seen := {}
	var per_day := {}
	var latest_offer_day := -1
	for offer in offers:
		latest_offer_day = maxi(latest_offer_day, int(offer["day"]))
	var open_count := 0
	var problem := ""
	for entry in entries:
		problem = _charter_problem(entry)
		if problem != "":
			break
		var charter := {}
		for key in CHARTER_KEYS:
			var value: Variant = entry[key]
			charter[key] = int(value) if typeof(value) == TYPE_FLOAT else value
		charter[FlightContract.TRAITS_KEY] = OfferTraits.frozen(entry[FlightContract.TRAITS_KEY])
		if seen.has(charter["id"]):
			problem = "charter id '%s' appears twice" % charter["id"]
			break
		seen[charter["id"]] = true
		per_day[charter["day"]] = per_day.get(charter["day"], 0) + 1
		if charter["status"] == OPEN:
			open_count += 1
			if latest_offer_day >= 0 and int(charter["day"]) < latest_offer_day:
				problem = (
					"charter %s is open but day %d has started" % [charter["id"], latest_offer_day]
				)
				break
		into.append(charter)
	if problem == "" and open_count > 1:
		problem = "at most one charter may be open"
	if problem == "":
		problem = _charter_days_problem(per_day, seen)
	return problem


func _charter_days_problem(per_day: Dictionary, seen: Dictionary) -> String:
	for day in per_day:
		var count := int(per_day[day])
		if count > MAX_CHARTERS_PER_DAY:
			return "day %d has more than %d charters" % [day, MAX_CHARTERS_PER_DAY]
		for number in range(1, count + 1):
			if not seen.has("%s%dN%d" % [CHARTER_PREFIX, day, number]):
				return "day %d is missing charter %s%dN%d" % [day, CHARTER_PREFIX, day, number]
	return ""


func _charter_problem(entry: Variant) -> String:
	if typeof(entry) != TYPE_DICTIONARY:
		return "a charter must be a dictionary"
	var problem := ""
	for key in entry.keys():
		if not CHARTER_KEYS.has(key):
			problem = "unknown charter key '%s'" % key
			break
	for key in CHARTER_KEYS:
		if problem == "" and not entry.has(key):
			problem = "missing charter key '%s'" % key
	if problem == "" and not STATUSES.has(entry["status"]):
		problem = "status must be one of %s" % [STATUSES]
	var day: Variant = entry.get("day")
	if (
		problem == ""
		and (not WholeNumber.is_whole(day) or int(day) < 0 or int(day) > FlightContract.MAX_DAY)
	):
		problem = "day must be a whole number from 0 to %d" % FlightContract.MAX_DAY
	if problem == "" and int(entry[FlightContract.ONE_OFF_DAY_KEY]) != int(day):
		problem = "charter %s one_off_day must match day" % entry["id"]
	if (
		problem == ""
		and (not WholeNumber.is_whole(entry["cutoff_tick"]) or int(entry["cutoff_tick"]) < 0)
	):
		problem = "charter %s cutoff_tick must be a non-negative whole number" % entry["id"]
	if problem == "":
		problem = FlightContract.problem(terms_of(entry), FlightContract.TERM_KEYS)
	if problem == "":
		problem = _charter_drawable_problem(entry)
	return problem


func _charter_drawable_problem(entry: Dictionary) -> String:
	var day := int(entry["day"])
	var number := _charter_number(str(entry["id"]))
	var problem := ""
	if str(entry["id"]) != "%s%dN%d" % [CHARTER_PREFIX, day, number] or number < 1:
		problem = "charter id '%s' is not a valid id for day %d" % [entry["id"], day]
	elif number > MAX_CHARTERS_PER_DAY:
		problem = "charter id '%s' exceeds daily cap" % entry["id"]
	elif not AIRLINES.has(entry["airline"]) or not DESTINATIONS.has(entry["destination"]):
		problem = "charter %s has an airline or destination the board never draws" % entry["id"]
	elif entry["plane_size"] != PlaneClasses.SMALL:
		problem = "charter %s must be a small plane" % entry["id"]
	elif typeof(entry[LOYAL_KEY]) != TYPE_BOOL or entry[LOYAL_KEY]:
		problem = "charter %s loyal must be false" % entry["id"]
	elif not (entry[FlightContract.TRAITS_KEY] as Dictionary).is_empty():
		problem = "charter %s must have plain traits" % entry["id"]
	return problem if problem != "" else _charter_range_problem(entry)


static func _charter_range_problem(entry: Dictionary) -> String:
	var pax_range: Array = STARTER_SIZES[PlaneClasses.SMALL]
	var booked := int(entry["booked_passengers"])
	if booked < int(pax_range[0]) or booked > int(pax_range[1]):
		return "charter %s books %d passengers outside small range" % [entry["id"], booked]
	var fees: Array = fee_range_for(0, PlaneClasses.SMALL)
	var fee := int(entry["fee_per_passenger"])
	if fee < int(fees[0]) or fee > int(fees[1]):
		return "charter %s fee %d is outside small range" % [entry["id"], fee]
	if not slots_of({}).has(int(entry["departure_minute"])):
		return "charter %s departs off the board's departure slots" % entry["id"]
	return ""


## "" when the statuses are ones a run could have saved: offers expire when a
## later day starts, and on the latest day an earlier batch may expire when a
## refill replaces it while only the latest batch may remain open.
func _status_problem(offers: Array[Dictionary], per_day: Dictionary) -> String:
	var latest := -1
	for offer in offers:
		latest = maxi(latest, offer["day"])
	if latest < 0:
		return ""
	var latest_batch_start := int(per_day[latest]) - OFFERS_PER_DAY + 1
	for offer in offers:
		if offer["day"] < latest:
			if offer["status"] == OPEN:
				return "offer %s is open but day %d has started" % [offer["id"], latest]
		else:
			var number := _offer_number(offer["id"])
			if offer["status"] == OPEN and number < latest_batch_start:
				return "offer %s is open from an earlier batch on day %d" % [offer["id"], latest]
			if offer["status"] == EXPIRED and number >= latest_batch_start:
				return "offer %s is expired but no later day is recorded" % offer["id"]
	return ""


## "" when `data` holds SAVE_KEYS ("charters" optional) with the current version and arrays.
func _top_problem(data: Dictionary) -> String:
	for key in data.keys():
		if not SAVE_KEYS.has(key):
			return "unknown key '%s'" % key
	for key in ["save_version", "offers", "loyalty"]:
		if not data.has(key):
			return "missing key '%s'" % key
	if not WholeNumber.is_whole(data["save_version"]) or data["save_version"] != SAVE_VERSION:
		return "save_version must be %d" % SAVE_VERSION
	if typeof(data["offers"]) != TYPE_ARRAY:
		return "offers must be an array"
	if data.has("charters") and typeof(data["charters"]) != TYPE_ARRAY:
		return "charters must be an array"
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
	var number := _offer_number(entry["id"])
	if str(entry["id"]) != "O%dN%d" % [day, number] or number < 1 or number > MAX_DAY_OFFERS:
		return "offer id '%s' is not a valid id for day %d" % [entry["id"], day]
	var tier := tier_of(entry["airline"])
	if tier < 0 or not DESTINATIONS.has(entry["destination"]):
		return "offer %s has an airline or destination the board never draws" % entry["id"]
	if not TIER_SIZES[tier].has(entry["plane_size"]):
		return "offer %s has a plane size the board never draws" % entry["id"]
	if typeof(entry[LOYAL_KEY]) != TYPE_BOOL:
		return "'%s' must be true or false" % LOYAL_KEY
	return _range_problem(entry)


## "" when the passengers, fee and departure are values _draw and its traits
## (_give_traits) can produce for the entry's airline tier.
func _range_problem(entry: Dictionary) -> String:
	var tier := tier_of(entry["airline"])
	var traits: Dictionary = entry[FlightContract.TRAITS_KEY]
	var booked_range: Array = TIER_SIZES[tier][entry["plane_size"]]
	var fewest := OfferTraits.fewest_booked(booked_range[0], booked_range[1], traits)
	var booked := int(entry["booked_passengers"])
	if booked < fewest or booked > booked_range[1]:
		return "offer %s books %d passengers outside its size's range" % [entry["id"], booked]
	var fee := int(entry["fee_per_passenger"])
	if not _fee_drawable(fee, fee_range_for(tier, entry["plane_size"]), traits, entry[LOYAL_KEY]):
		return "offer %s has a fee no drawn fee of its tier gives" % entry["id"]
	if not slots_of(traits).has(int(entry["departure_minute"])):
		return "offer %s departs off the board's departure slots" % entry["id"]
	return ""


## The fee an offer of drawn fee `fee` pays with `traits`, from a loyal airline
## when `loyal`: the fee traits first, then the loyal raise.
static func _fee_of(fee: int, traits: Dictionary, loyal: bool) -> int:
	return OfferTraits.loyal_fee_of(OfferTraits.fee_of(fee, traits), loyal)


## Whether some drawn fee in `fees` ([lowest, highest]) gives `fee` through
## _fee_of. The rounding leaves gaps between the lowest and highest result, so
## each drawn fee is tried rather than the two ends.
static func _fee_drawable(fee: int, fees: Array, traits: Dictionary, loyal: bool) -> bool:
	for drawn in range(fees[0], fees[1] + 1):
		if _fee_of(drawn, traits, loyal) == fee:
			return true
	return false


## "" when every offer's loyal mark is the one the saved count gives it: an
## offer is loyal exactly when its airline's count is OfferTraits.LOYAL_DAYS
## (the count only grows and stops there) and the offer's day is after the last
## counted day (a day's offers are drawn at its start, before any of its flights
## depart). Both a loyal mark the count cannot explain and a missing one are
## refused.
static func _loyal_marks_problem(offers: Array[Dictionary], loyalty: Dictionary) -> String:
	for offer in offers:
		var entry: Dictionary = loyalty.get(offer["airline"], {"days": 0, "last_day": -1})
		var full: bool = entry["days"] >= OfferTraits.LOYAL_DAYS
		if _offer_number(offer["id"]) > OFFERS_PER_DAY:
			var may_be_loyal: bool = full and offer["day"] >= entry["last_day"]
			var must_be_loyal: bool = full and offer["day"] > entry["last_day"]
			if (offer[LOYAL_KEY] and not may_be_loyal) or (not offer[LOYAL_KEY] and must_be_loyal):
				return (
					"offer %s is marked loyal %s but %s's count makes it invalid on day %d"
					% [offer["id"], offer[LOYAL_KEY], offer["airline"], offer["day"]]
				)
			continue
		var loyal: bool = full and offer["day"] > entry["last_day"]
		if offer[LOYAL_KEY] != loyal:
			return (
				"offer %s is marked loyal %s but %s's count makes it %s on day %d"
				% [offer["id"], offer[LOYAL_KEY], offer["airline"], loyal, offer["day"]]
			)
	return ""


## "" and `into` filled with the saved Loyal airline count, or what is wrong.
static func _loyalty_problem(saved: Variant, into: Dictionary) -> String:
	if typeof(saved) != TYPE_DICTIONARY:
		return "loyalty must be a dictionary"
	for airline: Variant in saved:
		if typeof(airline) != TYPE_STRING or tier_of(airline) < 0:
			return "loyalty names '%s', not an airline the board draws" % [airline]
		var entry: Variant = saved[airline]
		if typeof(entry) != TYPE_DICTIONARY:
			return "loyalty of %s must be a dictionary" % airline
		var keys: Array = (entry as Dictionary).keys()
		keys.sort()
		if keys != LOYALTY_KEYS:
			return "loyalty of %s holds exactly %s, not %s" % [airline, LOYALTY_KEYS, keys]
		var days: Variant = entry["days"]
		if not WholeNumber.is_whole(days) or days < 1 or days > OfferTraits.LOYAL_DAYS:
			return "loyalty days of %s must be 1 to %d" % [airline, OfferTraits.LOYAL_DAYS]
		var last: Variant = entry["last_day"]
		# Each counted day is a different day from 0 on, so the last is at least days - 1.
		if not WholeNumber.is_whole(last) or last < days - 1 or last > FlightContract.MAX_DAY:
			return "loyalty last_day of %s must be a day from %d" % [airline, days - 1]
		into[airline] = {"days": int(days), "last_day": int(last)}
	return ""
