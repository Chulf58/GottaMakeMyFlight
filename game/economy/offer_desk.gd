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

var board := OfferBoard.new()

var _day := -1
var _bound: SimClock


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
	_day = GameCalendar.day_of(clock.tick)
	if flights != null and not flights.state_changed.is_connected(on_flight_state):
		flights.state_changed.connect(on_flight_state)
	_draw(_day)
	clock.ticked.connect(on_tick)


## FlightSim.state_changed: a departed flight of a contract with the Loyal
## airline trait counts its day toward that airline's loyalty on the board
## (OfferBoard.note_flown counts each day once). A load emits no departure, and
## the saved count already holds the days flown before it.
func on_flight_state(flight_id: String, state: int) -> void:
	if state != FlightSim.State.DEPARTED:
		return
	var contract := flights.contract_of(flights.flight_contract_id(flight_id))
	if contract.is_empty() or not OfferTraits.builds_loyalty(contract[FlightContract.TRAITS_KEY]):
		return
	board.note_flown(contract["airline"], FlightTimetable.parse_occurrence(flight_id)["day"])


## A new day first ends a contract the low rating has made due, then draws the
## day's offers, so they are fitted to the timetable as midnight leaves it
## (decision airline-offers-2-a-day-fit-the-free-gate-slots-1-needs-more,
## point 4). Ending a contract draws nothing from the RNG, so the order does
## not change the draws.
func on_tick(tick: int) -> void:
	var day := GameCalendar.day_of(tick)
	if day == _day:
		return
	_day = day
	_end_contract_if_due()
	_draw(day)


## When the rating's low days have run out, the oldest contract still running
## ends (the first accepted: FlightSim lists them in acceptance order) and the
## rating's count starts again, so at most one airline leaves per day end. The
## count is used up even with no contract left to end. The rating must have
## ticked first, so it has closed the day that just ended.
func _end_contract_if_due() -> void:
	if rating == null or flights == null or not rating.contract_ends():
		return
	var running := flights.active_contract_ids()
	rating.note_contract_ended()
	if running.is_empty():
		return
	var contract := flights.contract_of(running[0])
	if flights.end_contract(contract["id"]):
		contract_ended.emit(contract)


## Draws `day`'s offers for the biggest plane class the runway takes, fitted to
## the flights' timetable when the desk has flights, or pushes an error and
## draws nothing when the desk has no runway to ask.
func _draw(day: int) -> void:
	var source := runway
	if source == null and flights != null:
		source = flights.runway
	if source == null:
		push_error("OfferDesk: no runway set, so no offers are drawn")
		return
	board.ensure_day(day, clock.rng, _tier(), source.size, flights, live_needs())


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
	return live


## The airline tier the rating has unlocked, 0 with no rating.
func _tier() -> int:
	if rating == null:
		return 0
	return RatingFormula.tier(rating.stars())
