class_name AirportAwards
extends Node
## Persistent Annual Airport Awards tracker (Stage 3 Pillar 3, decision d5e50843).
## Tracks annual metrics across each 10-day Airport Year (GameCalendar.DAYS_PER_YEAR),
## evaluates 5 cozy award categories at each 10-day rollover (skipping DemoMode),
## pays cash prizes once via Wallet.Category.GRANT, and grants free placeable
## `award_trophy` Decor items.

signal changed
signal trophies_changed
signal ceremony_due(report: Dictionary)

const SAVE_VERSION := 1
const TROPHY_DEF_ID := &"award_trophy"
const MIN_MADE := 20
const ON_TIME_PERCENT := 85
const MAX_MESSES_LEFT := 10
const MIN_AVG_MOOD := 72
const MIN_HOSPITALITY := 500
const MIN_SUB_AWARDS := 3
const MIN_RATING_STARS := 3.5
const RATING_EPSILON := 1e-9

const PRIZE_ON_TIME := 2000
const PRIZE_SPOTLESS := 1500
const PRIZE_HAPPIEST := 2000
const PRIZE_HOSPITALITY := 2500
const PRIZE_AIRPORT_OF_YEAR := 5000

const MAX_YEAR := 1_000_000
const MAX_COUNT := 1_000_000_000
const MAX_HOSPITALITY := 1_000_000_000_000

const CATEGORIES := [
	{"id": &"on_time", "title": "On-Time Champion", "prize": PRIZE_ON_TIME},
	{"id": &"spotless", "title": "Spotless Terminal", "prize": PRIZE_SPOTLESS},
	{"id": &"happiest", "title": "Happiest Passengers", "prize": PRIZE_HAPPIEST},
	{"id": &"hospitality", "title": "Best Hospitality", "prize": PRIZE_HOSPITALITY},
	{"id": &"airport_of_the_year", "title": "Airport of the Year", "prize": PRIZE_AIRPORT_OF_YEAR},
]

const SNAPSHOT_KEYS := [
	"save_version",
	"last_ceremony_year",
	"last_counted_day",
	"year_made",
	"year_missed",
	"year_mood_sum",
	"year_messes_left",
	"year_hospitality_earned",
	"trophies_earned",
	"pending_flights",
]

@export var clock: SimClock
@export var flights: FlightSim
@export var passengers: PassengerSim
@export var rating: AirportRating
@export var finances: Finances

## Optional live celebration callback: func(report: Dictionary) -> void.
var ceremony_handler := Callable()

var _last_ceremony_year := 0
var _last_counted_day := 0
var _year_made := 0
var _year_missed := 0
var _year_mood_sum := 0
var _year_messes_left := 0
var _year_hospitality_earned := 0
var _trophies_earned := 0
var _pending_flights: Array[Dictionary] = []
var _last_report := {}
var _bound := false
var _loading := false
var _bound_wallet: Wallet


func _exit_tree() -> void:
	_unbind()


## Empty string if `data` is a valid saved awards state, else the refusal reason.
static func validation_problem(data: Variant) -> String:
	if typeof(data) != TYPE_DICTIONARY:
		return "awards must be a dictionary"
	var dict := data as Dictionary
	for key in dict.keys():
		if not SNAPSHOT_KEYS.has(key):
			return "unknown key '%s'" % key
	for key in SNAPSHOT_KEYS:
		if not dict.has(key):
			return "missing key '%s'" % key
	for key in [
		"save_version",
		"last_ceremony_year",
		"last_counted_day",
		"year_made",
		"year_missed",
		"year_mood_sum",
		"year_messes_left",
		"year_hospitality_earned",
		"trophies_earned",
	]:
		if not WholeNumber.is_whole(dict[key]):
			return "'%s' must be a whole number" % key
	if int(dict["save_version"]) != SAVE_VERSION:
		return "save_version must be %d" % SAVE_VERSION
	return _bounds_problem(dict)


static func _bounds_problem(dict: Dictionary) -> String:
	var last_year := int(dict["last_ceremony_year"])
	var last_day := int(dict["last_counted_day"])
	var made := int(dict["year_made"])
	var missed := int(dict["year_missed"])
	var mood_sum := int(dict["year_mood_sum"])
	var messes := int(dict["year_messes_left"])
	var hospitality := int(dict["year_hospitality_earned"])
	var trophies := int(dict["trophies_earned"])
	if last_year < 0 or last_year > MAX_YEAR:
		return "last_ceremony_year %d is outside 0 to %d" % [last_year, MAX_YEAR]
	if last_day < 0 or last_day > MAX_COUNT:
		return "last_counted_day %d is outside 0 to %d" % [last_day, MAX_COUNT]
	for pair in [
		["year_made", made],
		["year_missed", missed],
		["year_messes_left", messes],
		["trophies_earned", trophies],
	]:
		if int(pair[1]) < 0 or int(pair[1]) > MAX_COUNT:
			return "%s %d is outside 0 to %d" % [pair[0], int(pair[1]), MAX_COUNT]
	if mood_sum < 0 or mood_sum > made * PassengerSim.MOOD_MAX:
		return "year_mood_sum %d is outside 0 to %d" % [mood_sum, made * PassengerSim.MOOD_MAX]
	if hospitality < 0 or hospitality > MAX_HOSPITALITY:
		return "year_hospitality_earned %d is outside 0 to %d" % [hospitality, MAX_HOSPITALITY]
	return _pending_problem(dict["pending_flights"])


static func _pending_problem(entries: Variant) -> String:
	if typeof(entries) != TYPE_ARRAY:
		return "'pending_flights' must be a list"
	var seen := {}
	for entry: Variant in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			return "pending flight must be a dictionary"
		var dict := entry as Dictionary
		if dict.size() != 2 or not dict.has("flight") or not dict.has("tick"):
			return "pending flight must hold 'flight' and 'tick'"
		if typeof(dict["flight"]) != TYPE_STRING or str(dict["flight"]) == "":
			return "pending flight id must be a non-empty string"
		if not WholeNumber.is_whole(dict["tick"]) or int(dict["tick"]) < 0:
			return "pending flight tick must be a whole number of 0 or more"
		var fid := str(dict["flight"])
		if seen.has(fid):
			return "pending flight '%s' is listed twice" % fid
		seen[fid] = true
	return ""


func last_ceremony_year() -> int:
	return _last_ceremony_year


func trophies_earned() -> int:
	return _trophies_earned


## Available free placeable award trophies on `grid`: earned minus placed.
func trophies_available(grid: BuildGrid) -> int:
	var placed := grid.count_objects(TROPHY_DEF_ID) if grid != null else 0
	return maxi(0, _trophies_earned - placed)


func set_loading(loading: bool) -> void:
	_loading = loading


func reset() -> void:
	var had_trophies := _trophies_earned != 0
	_last_ceremony_year = 0
	_last_counted_day = 0
	_year_made = 0
	_year_missed = 0
	_year_mood_sum = 0
	_year_messes_left = 0
	_year_hospitality_earned = 0
	_trophies_earned = 0
	_pending_flights.clear()
	_last_report = {}
	changed.emit()
	if had_trophies:
		trophies_changed.emit()


## Records a passenger flight outcome (`made` and `mood` for made passengers).
func record_passenger(made: bool, mood: int = PassengerSim.MOOD_MAX) -> void:
	if _loading:
		return
	if made:
		var clamped := clampi(mood, 0, PassengerSim.MOOD_MAX)
		_year_made = mini(_year_made + 1, MAX_COUNT)
		_year_mood_sum = mini(_year_mood_sum + clamped, _year_made * PassengerSim.MOOD_MAX)
	else:
		_year_missed = mini(_year_missed + 1, MAX_COUNT)
	changed.emit()


## Adds unresolved messes left on the terminal floor to the annual penalty total.
func record_messes_left(count: int) -> void:
	if _loading or count <= 0:
		return
	_year_messes_left = mini(_year_messes_left + count, MAX_COUNT)
	changed.emit()


## Adds positive food/shop/service revenue to the annual hospitality total.
func record_hospitality(amount: int) -> void:
	if _loading or amount <= 0:
		return
	_year_hospitality_earned = mini(_year_hospitality_earned + amount, MAX_HOSPITALITY)
	changed.emit()


## Pure evaluation of the 5 award categories against `metrics`.
func evaluate_year(metrics: Dictionary) -> Dictionary:
	var made := int(metrics.get("year_made", 0))
	var missed := int(metrics.get("year_missed", 0))
	var mood_sum := int(metrics.get("year_mood_sum", 0))
	var messes := int(metrics.get("year_messes_left", 0))
	var hospitality := int(metrics.get("year_hospitality_earned", 0))
	var stars := float(metrics.get("rating_stars", 0.0))
	var year := int(metrics.get("year", _last_ceremony_year + 1))

	var total_pax := made + missed
	var won_on_time := (
		made >= MIN_MADE and total_pax > 0 and made * 100 >= ON_TIME_PERCENT * total_pax
	)
	var won_spotless := made >= MIN_MADE and messes <= MAX_MESSES_LEFT
	var won_happiest := made >= MIN_MADE and mood_sum >= MIN_AVG_MOOD * made
	var won_hospitality := hospitality >= MIN_HOSPITALITY

	var sub_won := 0
	for won_flag in [won_on_time, won_spotless, won_happiest, won_hospitality]:
		if won_flag:
			sub_won += 1
	var won_aot_year := sub_won >= MIN_SUB_AWARDS and stars + RATING_EPSILON >= MIN_RATING_STARS

	var wins := {
		&"on_time": won_on_time,
		&"spotless": won_spotless,
		&"happiest": won_happiest,
		&"hospitality": won_hospitality,
		&"airport_of_the_year": won_aot_year,
	}

	var rows: Array[Dictionary] = []
	var total_cash := 0
	var trophies_won := 0
	var won_count := 0
	for cat: Dictionary in CATEGORIES:
		var cid: StringName = cat["id"]
		var won: bool = bool(wins[cid])
		var prize := int(cat["prize"]) if won else 0
		var trophy := 1 if won else 0
		if won:
			won_count += 1
			total_cash += prize
			trophies_won += trophy
		(
			rows
			. append(
				{
					"id": cid,
					"title": cat["title"],
					"won": won,
					"prize": prize,
					"trophies": trophy,
				}
			)
		)
	return {
		"year": year,
		"categories": rows,
		"sub_won": sub_won,
		"won_count": won_count,
		"total_cash": total_cash,
		"trophies_won": trophies_won,
		"metrics":
		{
			"year_made": made,
			"year_missed": missed,
			"year_mood_sum": mood_sum,
			"year_messes_left": messes,
			"year_hospitality_earned": hospitality,
			"rating_stars": stars,
		},
	}


## Snapshot of live annual metrics plus current AirportRating stars.
func current_metrics() -> Dictionary:
	var stars := rating.stars() if rating != null else 0.0
	return {
		"year_made": _year_made,
		"year_missed": _year_missed,
		"year_mood_sum": _year_mood_sum,
		"year_messes_left": _year_messes_left,
		"year_hospitality_earned": _year_hospitality_earned,
		"rating_stars": stars,
	}


## Runs the ceremony for `year`: evaluates the 5 categories, resets annual counters,
## credits cash prizes once via Wallet.Category.GRANT, grants trophies, and notifies UI.
func evaluate_live_ceremony(year: int) -> Dictionary:
	if _loading or year <= _last_ceremony_year or DemoMode.is_demo():
		return {}
	var metrics := current_metrics()
	metrics["year"] = year
	var report := evaluate_year(metrics)
	_last_ceremony_year = year
	_year_made = 0
	_year_missed = 0
	_year_mood_sum = 0
	_year_messes_left = 0
	_year_hospitality_earned = 0
	var total_cash := int(report["total_cash"])
	var trophies_won := int(report["trophies_won"])
	var prev_trophies := _trophies_earned
	if trophies_won > 0:
		_trophies_earned = mini(_trophies_earned + trophies_won, MAX_COUNT)
	if total_cash > 0 and finances != null and finances.wallet != null:
		finances.wallet.credit(total_cash, Wallet.Category.GRANT)
	_last_report = report.duplicate(true)
	changed.emit()
	if _trophies_earned != prev_trophies:
		trophies_changed.emit()
	ceremony_due.emit(report)
	if ceremony_handler.is_valid():
		ceremony_handler.call(report)
	return report


## Connects live scene signals so ticks, flight outcomes, messes, and shop income
## accumulate deterministically across each 10-day year.
func bind(
	with_clock: SimClock,
	with_flights: FlightSim,
	with_passengers: PassengerSim,
	with_rating: AirportRating,
	with_finances: Finances
) -> void:
	var next_wallet := with_finances.wallet if with_finances != null else null
	if (
		_bound
		and clock == with_clock
		and flights == with_flights
		and passengers == with_passengers
		and rating == with_rating
		and finances == with_finances
		and _bound_wallet == next_wallet
	):
		return
	_unbind()
	clock = with_clock
	flights = with_flights
	passengers = with_passengers
	rating = with_rating
	finances = with_finances
	_bound_wallet = next_wallet
	if clock != null and not clock.ticked.is_connected(on_tick):
		clock.ticked.connect(on_tick)
	if flights != null and not flights.doors_closed.is_connected(_on_doors_closed):
		flights.doors_closed.connect(_on_doors_closed)
	if passengers != null:
		if not passengers.outcome.is_connected(_on_outcome):
			passengers.outcome.connect(_on_outcome)
		if (
			passengers.arrivals != null
			and not passengers.arrivals.missed.is_connected(_on_arrival_missed)
		):
			passengers.arrivals.missed.connect(_on_arrival_missed)
	if _bound_wallet != null and not _bound_wallet.transaction.is_connected(_on_wallet_transaction):
		_bound_wallet.transaction.connect(_on_wallet_transaction)
	_bound = true


func on_tick(tick: int) -> void:
	if _loading:
		return
	_record_finished_no_shows(tick)
	if clock != null and clock.calendar_held:
		return
	var day := GameCalendar.day_of(tick, SimClock.epoch_of(clock))
	if day > _last_counted_day:
		if passengers != null and passengers.messes != null:
			var active_messes := passengers.messes.mess_count()
			if active_messes > 0:
				_year_messes_left = mini(_year_messes_left + active_messes, MAX_COUNT)
		_last_counted_day = day
	if DemoMode.is_demo():
		return
	if day < GameCalendar.DAYS_PER_YEAR:
		return
	var year := GameCalendar.year_of(day)
	if year > _last_ceremony_year:
		evaluate_live_ceremony(year)


func to_save_dict() -> Dictionary:
	var pending := []
	for entry: Dictionary in _pending_flights:
		pending.append({"flight": entry["flight"], "tick": int(entry["tick"])})
	return {
		"save_version": SAVE_VERSION,
		"last_ceremony_year": _last_ceremony_year,
		"last_counted_day": _last_counted_day,
		"year_made": _year_made,
		"year_missed": _year_missed,
		"year_mood_sum": _year_mood_sum,
		"year_messes_left": _year_messes_left,
		"year_hospitality_earned": _year_hospitality_earned,
		"trophies_earned": _trophies_earned,
		"pending_flights": pending,
	}


func from_save_dict(data: Variant) -> bool:
	var problem := validation_problem(data)
	if problem != "":
		push_error("AirportAwards.from_save_dict: %s" % problem)
		return false
	var dict := data as Dictionary
	var prev_trophies := _trophies_earned
	_last_ceremony_year = int(dict["last_ceremony_year"])
	_last_counted_day = int(dict["last_counted_day"])
	_year_made = int(dict["year_made"])
	_year_missed = int(dict["year_missed"])
	_year_mood_sum = int(dict["year_mood_sum"])
	_year_messes_left = int(dict["year_messes_left"])
	_year_hospitality_earned = int(dict["year_hospitality_earned"])
	_trophies_earned = int(dict["trophies_earned"])
	_pending_flights.clear()
	for entry: Dictionary in dict["pending_flights"]:
		_pending_flights.append({"flight": str(entry["flight"]), "tick": int(entry["tick"])})
	_last_report = {}
	changed.emit()
	if _trophies_earned != prev_trophies:
		trophies_changed.emit()
	return true


func _unbind() -> void:
	if not _bound:
		return
	if is_instance_valid(clock) and clock.ticked.is_connected(on_tick):
		clock.ticked.disconnect(on_tick)
	if is_instance_valid(flights) and flights.doors_closed.is_connected(_on_doors_closed):
		flights.doors_closed.disconnect(_on_doors_closed)
	if is_instance_valid(passengers):
		if passengers.outcome.is_connected(_on_outcome):
			passengers.outcome.disconnect(_on_outcome)
		if (
			passengers.arrivals != null
			and passengers.arrivals.missed.is_connected(_on_arrival_missed)
		):
			passengers.arrivals.missed.disconnect(_on_arrival_missed)
	if (
		is_instance_valid(_bound_wallet)
		and _bound_wallet.transaction.is_connected(_on_wallet_transaction)
	):
		_bound_wallet.transaction.disconnect(_on_wallet_transaction)
	_bound_wallet = null
	_bound = false


func _on_doors_closed(flight_id: String) -> void:
	if _loading or clock == null:
		return
	for entry in _pending_flights:
		if entry["flight"] == flight_id:
			return
	_pending_flights.append({"flight": flight_id, "tick": clock.tick})


func _record_finished_no_shows(tick: int) -> void:
	if passengers == null or _pending_flights.is_empty():
		return
	var waiting: Array[Dictionary] = []
	for entry in _pending_flights:
		if int(entry["tick"]) < tick:
			var counts: Dictionary = passengers.no_shows.get(entry["flight"], {})
			var missed := int(counts.get("no_entrance", 0)) + int(counts.get("late", 0))
			if missed > 0:
				_year_missed = mini(_year_missed + missed, MAX_COUNT)
		else:
			waiting.append(entry)
	_pending_flights = waiting


func _on_outcome(id: int, made: bool) -> void:
	if _loading:
		return
	var p := passengers.get_passenger(id) if passengers != null else null
	var mood := p.mood if p != null else PassengerSim.MOOD_MAX
	record_passenger(made, mood)


func _on_arrival_missed(_flight_id: String) -> void:
	if _loading:
		return
	if passengers != null:
		_record_finished_no_shows(passengers.tick)
	record_passenger(false, 0)


func _on_wallet_transaction(gross: int, category: int, _claimed: Dictionary, _tick: int) -> void:
	if _loading:
		return
	if gross > 0 and category == Wallet.Category.SHOP:
		record_hospitality(gross)
