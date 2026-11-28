class_name OfferDesk
extends Node
## The scene's one OfferBoard, and the day-boundary hook that feeds it: on a new
## game the clock's current day gets its offers, and each time SimClock enters
## a new day (GameCalendar.day_of) OfferBoard.ensure_day expires yesterday's
## open offers and draws today's from SimClock.rng. The calendar is derived
## from the tick, so the desk keeps no day of its own that a save would hold:
## the whole-world save (Economy 8/8) saves board.to_snapshot() beside SimClock's
## snapshot, whose rng seed and state the next day's draw continues from.

## An airline ended its contract because the rating stayed low (decision low-
## rating-ends-one-airline-contract-per-low-day): the ended contract, whose
## airline and destination the player is told.
signal contract_ended(contract: Dictionary)
## Emitted once in DemoMode on Day 4 when the Big Jet Showcase charter offer opens.
signal showcase_offered(info: Dictionary)

const CHARTER_CHECK_INTERVAL_TICKS := 300
const SHOWCASE_DAY := 3
const SHOWCASE_MIN_MINUTE := GameCalendar.START_MINUTE
const SHOWCASE_MIN_LEAD_MINUTES := 180
const SHOWCASE_DAY5_MAX_MINUTE := 19 * 60
const SHOWCASE_ID := "BJSHOW4"
const SHOWCASE_AIRLINE := "Polar Jet"
const SHOWCASE_DESTINATION := "Rome"
const SHOWCASE_PASSENGERS := 32
const SHOWCASE_FEE := 55
const SHOWCASE_BONUS := 1500

## The clock to follow when this node enters a scene. A scene must set it: a
## desk with no clock pushes an error and never draws. Tests call bind_clock.
@export var clock: SimClock
## The airport rating whose tier (RatingFormula.tier of its stars) decides which
## airlines a new day's offers may come from. Read when a day is drawn, so the
## rating must tick before the desk does (it sits earlier in the scene): the
## new day then counts. Without one every day is drawn at the starter tier.
@export var rating: AirportRating
## The flights whose contracts a low rating ends, and whose departures count the
## Loyal airline days (on_flight_state). Without it nothing ends or counts.
@export var flights: FlightSim
## The bags whose ready bag room (BaggageSim.has_ready_bag_room) lets a day's
## offers carry the bag traits, and whose grid's ready shop or food rooms let
## them carry Shoppers (OfferTraits needs). Read when a day is drawn. Without it
## those traits are never drawn.
@export var baggage: BaggageSim
## The runway whose size limits the offers drawn. Unset, the scene's flights
## give it (FlightSim.runway); a desk with neither draws nothing and says so.
var runway: Runway
## Optional wallet override (resolved via sibling Finances in main.tscn when unset).
var wallet: Wallet

var board := OfferBoard.new()

var _day := -1
var _bound: SimClock
var _bound_gate: AirportGate
var _was_open := false


func _ready() -> void:
	if clock == null:
		push_error("OfferDesk: no clock set, so no offers will ever be drawn")
		return
	if rating == null:
		push_error("OfferDesk: no rating set, so every day is drawn at the starter tier")
	if flights == null:
		push_error("OfferDesk: no flights set, so no contract will ever end")
	if baggage == null:
		push_error("OfferDesk: no baggage set, so no offer carries a bag or shopper trait")
	bind_clock(clock)


## Follows `sim_clock` and draws offers for its current day if the board has
## none. Binding the clock already followed does nothing; binding another lets
## go of the first, so only the clock bound last drives the desk.
func bind_clock(sim_clock: SimClock) -> void:
	if sim_clock == _bound:
		return
	if _bound != null:
		_bound.ticked.disconnect(on_tick)
	_bound = sim_clock
	clock = sim_clock
	_day = GameCalendar.day_of(clock.tick, clock.epoch)
	_connect_flights()
	_was_open = flights != null and flights.opened_tick >= 0
	_draw(_day)
	clock.ticked.connect(on_tick)


## FlightSim.state_changed: a departed flight counts its day toward that
## airline's loyalty on the board (+1 normally, +2 with LOYAL_AIRLINE trait).
func on_flight_state(flight_id: String, state: int) -> void:
	if state != FlightSim.State.DEPARTED:
		return
	var contract := flights.contract_of(flights.flight_contract_id(flight_id))
	if contract.is_empty():
		return
	var day: int = FlightTimetable.parse_occurrence(flight_id)["day"]
	var gain := OfferTraits.loyalty_day_gain(contract[FlightContract.TRAITS_KEY])
	board.note_flown(contract["airline"], day, gain)
	_pay_showcase_bonus_if_due(String(contract["id"]))


## A new day first ends a contract the low rating has made due, then draws the
## day's offers, so they are fitted to the timetable as midnight leaves it
## (decision airline-offers-pick-1-of-3-side-by-side-spin-away-discard). Ending
## a contract draws nothing from the RNG, so the order does not change the
## draws. On the tick the airport opens, Day-1 offers are fitted behind the
## starter contract; no automatic mid-day refills are drawn after the day's
## pick or pass.
func on_tick(tick: int) -> void:
	if flights != null and flights.gate != null:
		_connect_gate(flights.gate)
	if not _was_open and flights != null and flights.opened_tick >= 0:
		_on_airport_opened()
	var day := GameCalendar.day_of(tick, clock.epoch)
	if day != _day:
		_day = day
		board.expire_charters(tick, day)
		_end_contract_if_due()
		_draw(day)
		_maybe_offer_showcase(day, tick)
		return
	board.expire_charters(tick, day)
	_maybe_offer_showcase(day, tick)
	if tick % CHARTER_CHECK_INTERVAL_TICKS == 0:
		try_open_charter()


## Opens at most one same-day charter if the airport is open and a gate has a
## quiet daytime gap. Deterministic from clock seed/day/count; returns id or "".
func try_open_charter() -> String:
	var source := _runway_source()
	if clock == null or flights == null or flights.opened_tick < 0 or source == null:
		return ""
	if not OfferBoard.is_charter_offer_minute(GameCalendar.minute_of_day(clock.tick, clock.epoch)):
		return ""
	var day := GameCalendar.day_of(clock.tick, clock.epoch)
	return board.ensure_charter_for_gap(
		day, clock.tick, clock.epoch, clock.rng.seed, source.size, flights
	)


## True when an open charter can currently land at a gate before its cutoff.
func has_fitting_charter() -> bool:
	if flights == null or flights.opened_tick < 0:
		return false
	for charter in board.open_charters():
		if clock != null and clock.tick > int(charter["cutoff_tick"]):
			continue
		if FlightFit.fits(flights, OfferBoard.terms_of(charter)):
			return true
	return false


## Returns the pending Day-4 Big Jet Showcase offer dictionary, or {} if none.
func pending_showcase() -> Dictionary:
	return board.showcase() if board.has_pending_showcase() else {}


## Applies the player's decision on the Day-4 Big Jet Showcase offer.
func answer_showcase(accepted: bool) -> bool:
	if not board.has_pending_showcase():
		return false
	if not accepted:
		board.set_showcase_state(OfferBoard.DECLINED)
		return true
	var info := board.showcase()
	if flights != null and not _commit_showcase_contract(info):
		return false
	board.set_showcase_state(OfferBoard.ACCEPTED)
	return true


func _commit_showcase_contract(info: Dictionary) -> bool:
	var terms := _showcase_terms(info)
	var slot_ok := (
		flights.find_showcase_slot(
			terms, int(info["day"]), int(info["departure_minute"]), int(info["departure_minute"])
		)
		>= 0
	)
	if not slot_ok:
		var fallback := _find_showcase_slot(
			int(info["day"]), clock.tick if clock != null else 0, info
		)
		if fallback.is_empty():
			return false
		info["day"] = fallback["day"]
		info["departure_minute"] = fallback["minute"]
		terms = _showcase_terms(info)
	var prev_size := flights.runway.size
	var prev_works := flights.runway.works.to_snapshot()
	var upgraded := flights.grant_medium_runway()
	if not flights.accept_contract(terms):
		if upgraded:
			flights.runway.size = prev_size
			flights.runway.works.from_snapshot(prev_works)
			flights.check_planning_changed()
		return false
	board.set_showcase(info)
	return true


func _maybe_offer_showcase(day: int, tick: int) -> void:
	if (
		not DemoMode.is_demo()
		or day != SHOWCASE_DAY
		or board.has_showcase()
		or flights == null
		or flights.opened_tick < 0
		or clock == null
	):
		return
	var minute := GameCalendar.minute_of_day(tick, clock.epoch)
	if minute < SHOWCASE_MIN_MINUTE:
		return
	var info := {
		"id": SHOWCASE_ID,
		"day": day,
		"departure_minute": 0,
		"airline": SHOWCASE_AIRLINE,
		"destination": SHOWCASE_DESTINATION,
		"booked_passengers": SHOWCASE_PASSENGERS,
		"fee_per_passenger": SHOWCASE_FEE,
		"bonus": SHOWCASE_BONUS,
		"needs_runway": not flights.runway.takes(PlaneClasses.MEDIUM),
		"state": OfferBoard.OPEN,
	}
	var chosen := _find_showcase_slot(day, tick, info)
	if chosen.is_empty():
		return
	info["day"] = chosen["day"]
	info["departure_minute"] = chosen["minute"]
	board.set_showcase(info)
	showcase_offered.emit(info.duplicate())


func _find_showcase_slot(day: int, tick: int, info: Dictionary) -> Dictionary:
	if flights == null or clock == null:
		return {}
	var terms := _showcase_terms(info)
	var now_minute := GameCalendar.minute_of_day(tick, clock.epoch)
	var min_today := maxi(
		FlightContract.FIRST_DEPARTURE_MINUTE,
		_ceil_quarter_minute(now_minute + SHOWCASE_MIN_LEAD_MINUTES)
	)
	var slot := flights.find_showcase_slot(
		terms, day, min_today, FlightContract.LAST_DEPARTURE_MINUTE
	)
	if slot >= 0:
		return {"day": day, "minute": slot}
	var next_day := day + 1
	slot = flights.find_showcase_slot(
		terms, next_day, FlightContract.FIRST_DEPARTURE_MINUTE, SHOWCASE_DAY5_MAX_MINUTE
	)
	if slot >= 0:
		return {"day": next_day, "minute": slot}
	return {}


static func _ceil_quarter_minute(minute: int) -> int:
	@warning_ignore("integer_division")
	return (
		((minute + OfferBoard.DEPARTURE_STEP - 1) / OfferBoard.DEPARTURE_STEP)
		* OfferBoard.DEPARTURE_STEP
	)


static func _showcase_terms(info: Dictionary) -> Dictionary:
	return {
		"id": String(info["id"]),
		"airline": String(info["airline"]),
		"destination": String(info["destination"]),
		"departure_minute": int(info["departure_minute"]),
		"plane_size": PlaneClasses.MEDIUM,
		"booked_passengers": int(info["booked_passengers"]),
		"fee_per_passenger": int(info["fee_per_passenger"]),
		FlightContract.TRAITS_KEY: OfferTraits.frozen({}),
		FlightContract.ONE_OFF_DAY_KEY: int(info["day"]),
	}


func _pay_showcase_bonus_if_due(contract_id: String) -> void:
	if contract_id != SHOWCASE_ID:
		return
	var info := board.showcase()
	if info.get("state", "") != OfferBoard.ACCEPTED:
		return
	var target_wallet := _resolve_wallet()
	if target_wallet != null:
		target_wallet.credit(int(info["bonus"]), Wallet.Category.INCIDENT)
	else:
		push_warning("OfferDesk: no wallet set, so showcase bonus is not paid")
	board.set_showcase_state(OfferBoard.SHOWCASE_PAID)


func _resolve_wallet() -> Wallet:
	if wallet != null:
		return wallet
	for host in [self, flights]:
		if host != null and host.get_parent() != null:
			var fin := host.get_parent().get_node_or_null("Finances") as Finances
			if fin != null:
				return fin.wallet
	return null


## When the rating's low days have run out, the oldest contract still running
## ends (unless it is a Hub contract with its +1 grace day still unused).
func _end_contract_if_due() -> void:
	if rating == null or flights == null:
		return
	if rating.low_days() == 0:
		board.clear_hub_grace_used()
	if not rating.contract_ends():
		return
	var running := flights.active_contract_ids()
	rating.note_contract_ended()
	if running.is_empty():
		return
	var contract := flights.contract_of(running[0])
	if FlightContract.is_hub(contract) and not board.has_hub_grace_used(contract["id"]):
		board.note_hub_grace_used(contract["id"])
		return
	board.clear_hub_grace_used(contract["id"])
	if flights.end_contract(contract["id"]):
		contract_ended.emit(contract)


## Draws `day`'s offers for the biggest plane class the runway takes, fitted to
## the flights' timetable once the airport is open, or pushes an error and
## draws nothing when the desk has no runway to ask.
func _draw(day: int) -> void:
	var source := _runway_source()
	if source == null:
		push_error("OfferDesk: no runway set, so no offers are drawn")
		return
	var fit_sim := flights if flights != null and flights.opened_tick >= 0 else null
	var min_minute := _min_minute(day) if fit_sim != null else -1
	var stars := rating.stars() if rating != null else RatingFormula.STARTING_STARS
	board.ensure_day(day, clock.rng, _tier(), source.size, fit_sim, live_needs(), min_minute, stars)


func _connect_flights() -> void:
	if flights == null:
		return
	if not flights.state_changed.is_connected(on_flight_state):
		flights.state_changed.connect(on_flight_state)
	if not flights.snapshot_loaded.is_connected(_on_snapshot_loaded):
		flights.snapshot_loaded.connect(_on_snapshot_loaded)
	if not flights.ended_by_player.is_connected(_on_ended_by_player):
		flights.ended_by_player.connect(_on_ended_by_player)
	_connect_gate(flights.gate)


func _on_ended_by_player(contract_id: String, _fee: int) -> void:
	var contract := flights.contract_of(contract_id)
	if contract.is_empty():
		return
	board.demote_loyalty(String(contract["airline"]))
	board.clear_hub_grace_used(contract_id)


func _connect_gate(gate: AirportGate) -> void:
	if gate == null or gate == _bound_gate:
		return
	if is_instance_valid(_bound_gate) and _bound_gate.opened.is_connected(_on_airport_opened):
		_bound_gate.opened.disconnect(_on_airport_opened)
	_bound_gate = gate
	if not gate.opened.is_connected(_on_airport_opened):
		gate.opened.connect(_on_airport_opened)


func _on_airport_opened(_opened_tick := -1) -> void:
	if _was_open or clock == null or flights == null or flights.opened_tick < 0:
		return
	_was_open = true
	var day := GameCalendar.day_of(clock.tick, clock.epoch)
	_day = day
	if board.day_offer_count(day) > 0:
		board.refit_day(day, flights, _min_minute(day))
	else:
		_draw(day)


func _on_snapshot_loaded() -> void:
	_was_open = flights != null and flights.opened_tick >= 0
	if clock != null:
		_day = GameCalendar.day_of(clock.tick, clock.epoch)


func _min_minute(day: int) -> int:
	if clock == null:
		return -1
	var min_tick := clock.tick + FlightTimetable.issue_lead()
	var since_day := min_tick - GameCalendar.day_start(day, clock.epoch)
	if since_day <= 0:
		return 0
	return -GameCalendar.floor_div(-since_day, GameCalendar.TICKS_PER_MINUTE)


func _runway_source() -> Runway:
	if runway != null:
		return runway
	if flights != null:
		return flights.runway
	return null


## Which trait needs (OfferTraits.NEEDS_BAGS, NEEDS_SHOPS) the airport meets
## now: a ready bag room, and a ready shop or food room. Neither without baggage.
func live_needs() -> Dictionary:
	var live := {OfferTraits.NEEDS_BAGS: false, OfferTraits.NEEDS_SHOPS: false}
	if baggage == null or baggage.grid == null:
		return live
	live[OfferTraits.NEEDS_BAGS] = baggage.has_ready_bag_room()
	for room_id in baggage.grid.room_ids():
		var type := RoomTypes.get_type(baggage.grid.get_room(room_id)["type"])
		if type != null and (type.shop or type.food):
			if RoomRules.status(baggage.grid, room_id).ok:
				live[OfferTraits.NEEDS_SHOPS] = true
				break
	if not live[OfferTraits.NEEDS_SHOPS]:
		for object_id in baggage.grid.object_ids():
			var def_id := StringName(baggage.grid.get_object(object_id).get("def", &""))
			if ServiceTypes.is_standalone(def_id):
				live[OfferTraits.NEEDS_SHOPS] = true
				break
	return live


## The airline tier the rating has unlocked, 0 with no rating.
func _tier() -> int:
	if rating == null:
		return 0
	return RatingFormula.tier(rating.stars())
