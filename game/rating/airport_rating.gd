class_name AirportRating
extends Node
## The airport's 1 to 5 star rating over a rolling three in-game days, as
## plain data (decision airport-rating-1-5-stars-over-a-rolling-3-days-mostly-
## made-o; the numbers are RatingFormula's).
##
## It keeps its own per-day totals, because PassengerSim.flight_results and
## no_shows are pruned about a game hour after a flight departs: every
## passenger is recorded the tick they make or miss their flight (from
## PassengerSim.outcome), and a closed flight's no-shows one tick after its
## doors close, once PassengerSim has finalized them. Days are
## GameCalendar days; the window is the current day and the two before it,
## pooled, so a busy day weighs more than a quiet one.
##
## Missed bags (Baggage B4) lower the stars too: every bag BaggageSim settles
## (bag_settled) is recorded on the day it settles, whether or not its passenger
## made the flight, because a bag the belt could not load is the belt's miss.
## RatingFormula.WEIGHT_BAGS says how much they weigh. Set `baggage` before
## bind() (the scene wires it); without it no bag is recorded.
##
## For the HUD: stars(), parts(), has_data() and the changed signal. For the
## offer board: stars() against RatingFormula.TIER_STARS (RatingFormula.tier).
## For contracts: warning() while the rating is below RatingFormula.WARN_BELOW,
## low_days() and contract_ends() for the end of an airline's contract.

## Emitted when the totals, the day or the low-day count change.
signal changed

const SAVE_VERSION := 1

@export var clock: SimClock
@export var flights: FlightSim
@export var passengers: PassengerSim
@export var baggage: BaggageSim

## Day -> {"made", "missed", "mood_sum", "bags", "bags_missed"}; only days with
## a record are listed.
var _days: Dictionary = {}
## The last tick the rating has seen; its day is the current day.
var _tick := 0
## Consecutive day ends (up to now) at which the rating was below WARN_BELOW.
var _low_days := 0
## Flights whose doors have closed and whose no-shows are not yet recorded:
## {"flight": String, "tick": int}.
var _pending: Array[Dictionary] = []
## True while the signals of clock, flights and passengers are connected.
var _bound := false


func _ready() -> void:
	if clock != null and flights != null and passengers != null:
		bind(clock, flights, passengers)


## Listens to the clock, the flights' door closes and the passengers' outcomes.
## Binding the same three again does nothing; binding others first lets go of
## the ones bound before, so no signal reaches the rating twice. The bag sim in
## `baggage`, if set, is listened to as well, also on a repeated bind.
func bind(with_clock: SimClock, with_flights: FlightSim, with_passengers: PassengerSim) -> void:
	if _bound and clock == with_clock and flights == with_flights and passengers == with_passengers:
		_bind_baggage()
		return
	_unbind()
	clock = with_clock
	flights = with_flights
	passengers = with_passengers
	clock.ticked.connect(on_tick)
	flights.doors_closed.connect(_on_doors_closed)
	passengers.outcome.connect(_on_outcome)
	_bind_baggage()
	_bound = true


## Records the no-shows of flights that closed on an earlier tick, each on the
## day its doors closed, then rolls the day over when `tick` is in a later day:
## a flight closing on a day's last tick counts for that day, before the day
## is checked against WARN_BELOW.
func on_tick(tick: int) -> void:
	_record_finished_no_shows(tick)
	_roll_to(tick)


## One passenger made or missed their flight at `tick`, leaving at `mood`
## (0 to PassengerSim.MOOD_MAX). Only the mood of those who made it is kept.
func record_passenger(tick: int, made: bool, mood: int) -> void:
	if mood < 0 or mood > PassengerSim.MOOD_MAX:
		push_error("AirportRating.record_passenger: mood %d is out of range" % mood)
		return
	var totals := _today_after_rolling(tick)
	if totals["made"] + totals["missed"] >= RatingFormula.MAX_DAY_COUNT:
		push_error("AirportRating.record_passenger: the day is full")
		return
	if made:
		totals["made"] += 1
		totals["mood_sum"] += mood
	else:
		totals["missed"] += 1
	changed.emit()


## One bag settled at `tick`, loaded or missed (a missed bag counts for the
## rating whatever became of its passenger).
func record_bag(tick: int, loaded: bool) -> void:
	var totals := _today_after_rolling(tick)
	if totals["bags"] >= RatingFormula.MAX_DAY_COUNT:
		push_error("AirportRating.record_bag: the day is full of bags")
		return
	totals["bags"] += 1
	if not loaded:
		totals["bags_missed"] += 1
	changed.emit()


## A flight's doors closed at `tick`; its no-shows are recorded on a later tick.
func note_doors_closed(flight_id: String, tick: int) -> void:
	for entry in _pending:
		if entry["flight"] == flight_id:
			return
	_pending.append({"flight": flight_id, "tick": tick})


## The stars over the window, 1 to 5 in half steps; STARTING_STARS with no data.
func stars() -> float:
	var window := _window(current_day())
	return _stars_of(window)


## False until a passenger (or no-show) is inside the window.
func has_data() -> bool:
	var window := _window(current_day())
	return window["made"] + window["missed"] > 0


## The parts the HUD tooltip shows: {"stars", "made", "missed", "passengers",
## "made_share" 0..1, "mood_avg" 0..100 of those who made it, "bags" settled,
## "bags_missed" of them and their "bags_missed_share" 0..1, "days" with data}.
func parts() -> Dictionary:
	var window := _window(current_day())
	var total: int = window["made"] + window["missed"]
	var made_share := 0.0
	if total > 0:
		made_share = float(window["made"]) / total
	var mood_avg := 0.0
	if window["made"] > 0:
		mood_avg = float(window["mood_sum"]) / window["made"]
	var bags_missed_share := 0.0
	if window["bags"] > 0:
		bags_missed_share = float(window["bags_missed"]) / window["bags"]
	return {
		"stars": stars(),
		"made": window["made"],
		"missed": window["missed"],
		"passengers": total,
		"made_share": made_share,
		"mood_avg": mood_avg,
		"bags": window["bags"],
		"bags_missed": window["bags_missed"],
		"bags_missed_share": bags_missed_share,
		"days": window["days"],
	}


## True while the rating is below RatingFormula.WARN_BELOW: airlines warn.
func warning() -> bool:
	return _is_low(_window(current_day()))


## Consecutive day ends at which the rating was below WARN_BELOW.
func low_days() -> int:
	return _low_days


## True once the low count reaches RatingFormula.LOW_DAYS_TO_END: an airline
## that warned ends its contract.
func contract_ends() -> bool:
	return _low_days >= RatingFormula.LOW_DAYS_TO_END


## An airline ended its contract: the low-day count starts again from
## RatingFormula.LOW_DAYS_AFTER_END. False (with an error) unless contract_ends().
func note_contract_ended() -> bool:
	if not contract_ends():
		push_error("AirportRating.note_contract_ended: no contract is due to end")
		return false
	_low_days = RatingFormula.LOW_DAYS_AFTER_END
	changed.emit()
	return true


func current_day() -> int:
	return GameCalendar.day_of(_tick)


## What `day` holds: {"made", "missed", "mood_sum", "bags", "bags_missed"},
## zeros when it has nothing.
func day_totals(day: int) -> Dictionary:
	if _days.has(day):
		return (_days[day] as Dictionary).duplicate()
	return _empty_day()


## Days that hold a record, ascending.
func days_held() -> Array[int]:
	var held: Array[int] = []
	for day in _days.keys():
		held.append(day)
	held.sort()
	return held


## JSON-safe state for a save.
func to_snapshot() -> Dictionary:
	return RatingSnapshot.save(_tick, _days, _low_days, _pending)


## Restores a to_snapshot() dictionary, including one that went through JSON.
## Pushes an error and returns false, leaving the rating unchanged, when
## anything is missing, mistyped or inconsistent.
func from_snapshot(data: Dictionary) -> bool:
	var loaded := RatingSnapshot.load(data)
	if loaded.has("error"):
		push_error("AirportRating.from_snapshot: %s" % loaded["error"])
		return false
	_tick = loaded["tick"]
	_days = loaded["days"]
	_low_days = loaded["low_days"]
	_pending = loaded["pending"]
	changed.emit()
	return true


func _bind_baggage() -> void:
	if baggage != null and not baggage.bag_settled.is_connected(_on_bag_settled):
		baggage.bag_settled.connect(_on_bag_settled)


func _unbind() -> void:
	if is_instance_valid(baggage) and baggage.bag_settled.is_connected(_on_bag_settled):
		baggage.bag_settled.disconnect(_on_bag_settled)
	if not _bound:
		return
	if is_instance_valid(clock) and clock.ticked.is_connected(on_tick):
		clock.ticked.disconnect(on_tick)
	if is_instance_valid(flights) and flights.doors_closed.is_connected(_on_doors_closed):
		flights.doors_closed.disconnect(_on_doors_closed)
	if is_instance_valid(passengers) and passengers.outcome.is_connected(_on_outcome):
		passengers.outcome.disconnect(_on_outcome)
	_bound = false


## A pending flight is finished once `tick` is after its doors closed: PassengerSim
## has finalized its no-shows by then. They count for the day the doors closed.
func _record_finished_no_shows(tick: int) -> void:
	if passengers == null or _pending.is_empty():
		return
	var waiting: Array[Dictionary] = []
	for entry in _pending:
		if entry["tick"] < tick:
			var counts: Dictionary = passengers.no_shows.get(entry["flight"], {})
			_add_no_shows(
				entry["tick"], int(counts.get("no_entrance", 0)) + int(counts.get("late", 0))
			)
		else:
			waiting.append(entry)
	if waiting.size() != _pending.size():
		_pending = waiting
		changed.emit()


func _add_no_shows(close_tick: int, count: int) -> void:
	if count <= 0:
		return
	var day := GameCalendar.day_of(close_tick)
	if day <= current_day() - RatingFormula.WINDOW_DAYS:
		push_error("AirportRating: no-shows of day %d are older than the window" % day)
		return
	if not _days.has(day):
		_days[day] = _empty_day()
	var totals: Dictionary = _days[day]
	if totals["made"] + totals["missed"] + count > RatingFormula.MAX_DAY_COUNT:
		push_error("AirportRating: day %d is full" % day)
		return
	totals["missed"] += count


func _on_doors_closed(flight_id: String) -> void:
	note_doors_closed(flight_id, clock.tick)


func _on_outcome(id: int, made: bool) -> void:
	var p := passengers.get_passenger(id)
	if p == null:
		push_error("AirportRating: no passenger %d for its outcome" % id)
		return
	record_passenger(passengers.tick, made, p.mood)


func _on_bag_settled(_bag_id: int, _passenger_id: int, _flight_id: String, loaded: bool) -> void:
	record_bag(clock.tick, loaded)


static func _empty_day() -> Dictionary:
	return {"made": 0, "missed": 0, "mood_sum": 0, "bags": 0, "bags_missed": 0}


## Today's totals (created if need be) once the day has rolled to `tick`.
func _today_after_rolling(tick: int) -> Dictionary:
	_roll_to(tick)
	var day := current_day()
	if not _days.has(day):
		_days[day] = _empty_day()
	return _days[day]


## Pooled totals of the window ending on `last_day`.
func _window(last_day: int) -> Dictionary:
	var window := {"made": 0, "missed": 0, "mood_sum": 0, "bags": 0, "bags_missed": 0, "days": 0}
	for day in range(last_day - RatingFormula.WINDOW_DAYS + 1, last_day + 1):
		if not _days.has(day):
			continue
		var totals: Dictionary = _days[day]
		window["made"] += totals["made"]
		window["missed"] += totals["missed"]
		window["mood_sum"] += totals["mood_sum"]
		window["bags"] += totals["bags"]
		window["bags_missed"] += totals["bags_missed"]
		if totals["made"] + totals["missed"] > 0:
			window["days"] += 1
	return window


## Moves to `tick`'s day: each day that ends is checked against WARN_BELOW,
## then days that left the window are dropped. A jump of more than the window
## leaves nothing to check: the data and the low count are cleared.
func _roll_to(tick: int) -> void:
	if tick <= _tick:
		return
	var old_day := current_day()
	_tick = tick
	var new_day := current_day()
	if new_day == old_day:
		return
	if new_day - old_day > RatingFormula.WINDOW_DAYS:
		_days.clear()
		_low_days = 0
	else:
		for ended in range(old_day, new_day):
			_close_day(ended)
	for day in _days.keys():
		if day <= new_day - RatingFormula.WINDOW_DAYS:
			_days.erase(day)
	changed.emit()


func _close_day(day: int) -> void:
	_low_days = _low_days + 1 if _is_low(_window(day)) else 0


## True when a window has passengers and its stars are below WARN_BELOW.
static func _is_low(window: Dictionary) -> bool:
	var total: int = window["made"] + window["missed"]
	if total == 0:
		return false
	return _stars_of(window) < RatingFormula.WARN_BELOW


## The stars of a pooled window.
static func _stars_of(window: Dictionary) -> float:
	return RatingFormula.stars(
		window["made"], window["missed"], window["mood_sum"], window["bags"], window["bags_missed"]
	)
