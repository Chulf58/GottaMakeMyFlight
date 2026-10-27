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
## The flights whose contracts a low rating ends. Without it nothing ends.
@export var flights: FlightSim

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
	board.ensure_day(_day, clock.rng, _tier())
	clock.ticked.connect(on_tick)


func on_tick(tick: int) -> void:
	var day := GameCalendar.day_of(tick)
	if day == _day:
		return
	_day = day
	board.ensure_day(day, clock.rng, _tier())
	_end_contract_if_due()


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


## The airline tier the rating has unlocked, 0 with no rating.
func _tier() -> int:
	if rating == null:
		return 0
	return RatingFormula.tier(rating.stars())
