class_name AirportCertification
extends Node
## Persistent 1-to-5 star airport certification ladder (Stage 2 S2-D, decision
## stage-2-s2d-1-5-star-airport-certification-milestones-ladder-grants-
## prestige-bonus). Tracks earned milestones, one-time cash grants, and a
## permanent contract fee prestige bonus (+5% per star past 1★, up to +20%),
## without ever altering rolling AirportRating stars.

signal changed
signal certified(award: Dictionary)

const MAX_STAR := 5
const DEMO_MAX_STAR := DemoMode.MAX_CERTIFICATION_STAR
const SAVE_VERSION := 1
const MAX_DEPARTED := 1_000_000_000
const SNAPSHOT_KEYS := ["save_version", "earned_star", "medium_departed", "large_departed"]
const RATE_EPSILON := 1e-9

const LEVELS := [
	{
		"star": 1,
		"title": "Local Strip",
		"grant": 1500,
		"bonus_percent": 0,
		"require_opened": true,
		"min_rating": 0.0,
		"min_passengers": 10,
		"require_security_lane": false,
		"require_bag_room": false,
		"min_medium_departed": 0,
		"min_large_departed": 0,
		"min_made_rate": -1.0,
	},
	{
		"star": 2,
		"title": "Regional Terminal",
		"grant": 3000,
		"bonus_percent": 5,
		"require_opened": false,
		"min_rating": 2.0,
		"min_passengers": 50,
		"require_security_lane": true,
		"require_bag_room": false,
		"min_medium_departed": 0,
		"min_large_departed": 0,
		"min_made_rate": -1.0,
	},
	{
		"star": 3,
		"title": "National Hub",
		"grant": 6000,
		"bonus_percent": 10,
		"require_opened": false,
		"min_rating": 3.0,
		"min_passengers": 150,
		"require_security_lane": false,
		"require_bag_room": true,
		"min_medium_departed": 1,
		"min_large_departed": 0,
		"min_made_rate": -1.0,
	},
	{
		"star": 4,
		"title": "International Gateway",
		"grant": 12000,
		"bonus_percent": 15,
		"require_opened": false,
		"min_rating": 4.0,
		"min_passengers": 400,
		"require_security_lane": false,
		"require_bag_room": false,
		"min_medium_departed": 0,
		"min_large_departed": 1,
		"min_made_rate": 0.85,
	},
	{
		"star": 5,
		"title": "World-Class Airport",
		"grant": 25000,
		"bonus_percent": 20,
		"require_opened": false,
		"min_rating": 4.5,
		"min_passengers": 800,
		"require_security_lane": false,
		"require_bag_room": false,
		"min_medium_departed": 0,
		"min_large_departed": 0,
		"min_made_rate": 0.90,
	},
]

@export var flights: FlightSim
@export var rating: AirportRating
@export var passengers: PassengerSim
@export var baggage: BaggageSim
@export var unlocks: BuildUnlocks
@export var finances: Finances
@export var clock: SimClock

## Optional live celebration callback: func(award: Dictionary) -> void.
var celebrate_handler := Callable()

var _earned_star := 0
var _medium_departed := 0
var _large_departed := 0
var _bound := false
var _loading := false


## Info dictionary for `star` (1..MAX_STAR), or {} if out of range.
static func level_info(star: int) -> Dictionary:
	if star < 1 or star > LEVELS.size():
		return {}
	return (LEVELS[star - 1] as Dictionary).duplicate()


## Empty string if `data` is a valid saved certification state, else the refusal reason.
static func validation_problem(data: Variant) -> String:
	if typeof(data) != TYPE_DICTIONARY:
		return "certification must be a dictionary"
	var dict := data as Dictionary
	for key in dict.keys():
		if not SNAPSHOT_KEYS.has(key):
			return "unknown key '%s'" % key
	for key in SNAPSHOT_KEYS:
		if not dict.has(key):
			return "missing key '%s'" % key
		if not WholeNumber.is_whole(dict[key]):
			return "'%s' must be a whole number" % key
	if int(dict["save_version"]) != SAVE_VERSION:
		return "save_version must be %d" % SAVE_VERSION
	return _bounds_problem(
		int(dict["earned_star"]), int(dict["medium_departed"]), int(dict["large_departed"])
	)


static func _bounds_problem(star: int, medium: int, large: int) -> String:
	if star < 0 or star > MAX_STAR:
		return "earned_star %d is outside 0 to %d" % [star, MAX_STAR]
	if medium < 0 or medium > MAX_DEPARTED:
		return "medium_departed %d is outside 0 to %d" % [medium, MAX_DEPARTED]
	if large < 0 or large > MAX_DEPARTED:
		return "large_departed %d is outside 0 to %d" % [large, MAX_DEPARTED]
	if large > medium:
		return "large_departed %d cannot exceed medium_departed %d" % [large, medium]
	if star >= 3 and medium < 1:
		return "earned_star %d requires medium_departed >= 1" % star
	if star >= 4 and large < 1:
		return "earned_star %d requires large_departed >= 1" % star
	return ""


func earned_star() -> int:
	return _earned_star


func medium_departed() -> int:
	return _medium_departed


func large_departed() -> int:
	return _large_departed


func is_earned(star: int) -> bool:
	return star >= 1 and star <= _earned_star


func earned_title() -> String:
	if _earned_star <= 0:
		return ""
	return str(LEVELS[_earned_star - 1]["title"])


func prestige_fee_bonus_percent() -> int:
	if _earned_star <= 0:
		return 0
	return int(LEVELS[_earned_star - 1]["bonus_percent"])


## Applies the permanent prestige bonus to `base_fee`, rounded half up and clamped.
func apply_prestige_bonus(base_fee: int) -> int:
	if base_fee <= 0:
		return base_fee
	var pct := prestige_fee_bonus_percent()
	if pct <= 0:
		return mini(base_fee, Wallet.MAX_BALANCE)
	@warning_ignore("integer_division")
	return mini((base_fee * (100 + pct) + 50) / 100, Wallet.MAX_BALANCE)


## Records a departed flight of `plane_class`. Large planes count toward both
## medium_departed and large_departed so skipping straight to Large never stalls 3★.
func record_departure(plane_class: String) -> void:
	if plane_class == PlaneClasses.MEDIUM:
		_medium_departed = mini(_medium_departed + 1, MAX_DEPARTED)
		changed.emit()
	elif plane_class == PlaneClasses.LARGE:
		_medium_departed = mini(_medium_departed + 1, MAX_DEPARTED)
		_large_departed = mini(_large_departed + 1, MAX_DEPARTED)
		changed.emit()
	elif not PlaneClasses.is_plane_class(plane_class):
		push_error("AirportCertification.record_departure: unknown plane class '%s'" % plane_class)


## Evaluates criteria against `metrics` sequentially from _earned_star + 1 up to
## MAX_STAR (or DEMO_MAX_STAR when `demo_mode` is true). Never revokes earned stars.
## Returns newly awarded level dictionaries in ascending star order.
func evaluate(metrics: Dictionary, demo_mode: bool = false) -> Array[Dictionary]:
	var max_star := DEMO_MAX_STAR if demo_mode else MAX_STAR
	var awarded: Array[Dictionary] = []
	for level: Dictionary in LEVELS:
		var star: int = level["star"]
		if star <= _earned_star:
			continue
		if star > max_star:
			break
		if not _level_met(level, metrics):
			break
		_earned_star = star
		(
			awarded
			. append(
				{
					"star": star,
					"title": level["title"],
					"grant": level["grant"],
					"bonus_percent": level["bonus_percent"],
				}
			)
		)
	if not awarded.is_empty():
		changed.emit()
		for award in awarded:
			certified.emit(award)
	return awarded


## Structured progress rows for all 5 certification levels (for RatingBadge UI).
func progress_rows(metrics: Dictionary, demo_mode: bool = false) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for level: Dictionary in LEVELS:
		var star: int = level["star"]
		var demo_locked := demo_mode and star > DEMO_MAX_STAR
		(
			rows
			. append(
				{
					"star": star,
					"title": level["title"],
					"earned": star <= _earned_star,
					"demo_locked": demo_locked,
					"grant": level["grant"],
					"bonus_percent": level["bonus_percent"],
					"criteria": _criteria_for(level, metrics),
				}
			)
		)
	return rows


## Reads live metrics from the wired scene sims without mutating any state.
func current_metrics() -> Dictionary:
	var opened := flights != null and flights.opened_tick >= 0
	var made_total := 0
	if unlocks != null:
		made_total = unlocks.made_total()
	elif passengers != null:
		made_total = passengers.made_count()
	var rating_stars := rating.stars() if rating != null else 0.0
	var made_ratio := -1.0
	if rating != null and rating.has_data():
		made_ratio = float(rating.parts().get("made_share", -1.0))
	var has_security_lane := false
	if (
		passengers != null
		and passengers.layout != null
		and passengers.layout.security_lanes != null
	):
		has_security_lane = not passengers.layout.security_lanes.complete_arches().is_empty()
	var has_bag_room := baggage != null and baggage.has_ready_bag_room()
	return {
		"opened": opened,
		"made_total": made_total,
		"rating_stars": rating_stars,
		"made_ratio": made_ratio,
		"has_security_lane": has_security_lane,
		"has_bag_room": has_bag_room,
	}


## Evaluates live metrics, pays one-time grants to Wallet, and fires celebration UI.
func evaluate_live() -> Array[Dictionary]:
	if _loading:
		return []
	var awarded := evaluate(current_metrics(), DemoMode.is_demo())
	for award in awarded:
		if finances != null and finances.wallet != null and int(award["grant"]) > 0:
			finances.wallet.credit(int(award["grant"]), Wallet.Category.GRANT)
		if celebrate_handler.is_valid():
			celebrate_handler.call(award)
	return awarded


## Connects live scene signals so departures, outcomes, and ticks update certifications.
func bind(
	with_flights: FlightSim,
	with_rating: AirportRating,
	with_passengers: PassengerSim,
	with_baggage: BaggageSim,
	with_unlocks: BuildUnlocks,
	with_finances: Finances,
	with_clock: SimClock
) -> void:
	if (
		_bound
		and flights == with_flights
		and rating == with_rating
		and passengers == with_passengers
		and baggage == with_baggage
		and unlocks == with_unlocks
		and finances == with_finances
		and clock == with_clock
	):
		return
	_unbind()
	flights = with_flights
	rating = with_rating
	passengers = with_passengers
	baggage = with_baggage
	unlocks = with_unlocks
	finances = with_finances
	clock = with_clock
	if flights != null and not flights.state_changed.is_connected(_on_flight_state):
		flights.state_changed.connect(_on_flight_state)
	if rating != null and not rating.changed.is_connected(_on_rating_changed):
		rating.changed.connect(_on_rating_changed)
	if passengers != null and not passengers.outcome.is_connected(_on_passenger_outcome):
		passengers.outcome.connect(_on_passenger_outcome)
	if clock != null and not clock.ticked.is_connected(_on_clock_ticked):
		clock.ticked.connect(_on_clock_ticked)
	_bound = true


func set_loading(loading: bool) -> void:
	_loading = loading


func reset() -> void:
	_earned_star = 0
	_medium_departed = 0
	_large_departed = 0
	changed.emit()


func to_save_dict() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"earned_star": _earned_star,
		"medium_departed": _medium_departed,
		"large_departed": _large_departed,
	}


func from_save_dict(data: Variant) -> bool:
	var problem := validation_problem(data)
	if problem != "":
		push_error("AirportCertification.from_save_dict: %s" % problem)
		return false
	var dict := data as Dictionary
	var max_star := DEMO_MAX_STAR if DemoMode.is_demo() else MAX_STAR
	_earned_star = mini(int(dict["earned_star"]), max_star)
	_medium_departed = int(dict["medium_departed"])
	_large_departed = int(dict["large_departed"])
	changed.emit()
	return true


func _level_met(level: Dictionary, metrics: Dictionary) -> bool:
	for criterion in _criteria_for(level, metrics):
		if not bool(criterion["met"]):
			return false
	return true


func _criteria_for(level: Dictionary, metrics: Dictionary) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	if bool(level["require_opened"]):
		var opened := bool(metrics.get("opened", false))
		items.append({"label": "Airport opened", "met": opened, "current": opened, "target": true})
	var min_rating := float(level["min_rating"])
	if min_rating > 0.0:
		var stars := float(metrics.get("rating_stars", 0.0))
		(
			items
			. append(
				{
					"label": "Airport rating",
					"met": stars + RATE_EPSILON >= min_rating,
					"current": stars,
					"target": min_rating,
				}
			)
		)
	var min_pax := int(level["min_passengers"])
	if min_pax > 0:
		var pax := int(metrics.get("made_total", 0))
		(
			items
			. append(
				{
					"label": "Passengers made",
					"met": pax >= min_pax,
					"current": pax,
					"target": min_pax,
				}
			)
		)
	_append_facility_and_fleet_criteria(items, level, metrics)
	return items


func _append_facility_and_fleet_criteria(
	items: Array[Dictionary], level: Dictionary, metrics: Dictionary
) -> void:
	if bool(level["require_security_lane"]):
		var has_lane := bool(metrics.get("has_security_lane", false))
		(
			items
			. append(
				{
					"label": "Security lane built",
					"met": has_lane,
					"current": has_lane,
					"target": true,
				}
			)
		)
	if bool(level["require_bag_room"]):
		var has_bag := bool(metrics.get("has_bag_room", false))
		(
			items
			. append(
				{
					"label": "Bag room built",
					"met": has_bag,
					"current": has_bag,
					"target": true,
				}
			)
		)
	var min_med := int(level["min_medium_departed"])
	if min_med > 0:
		(
			items
			. append(
				{
					"label": "Medium+ plane departed",
					"met": _medium_departed >= min_med,
					"current": _medium_departed,
					"target": min_med,
				}
			)
		)
	var min_large := int(level["min_large_departed"])
	if min_large > 0:
		(
			items
			. append(
				{
					"label": "Large plane departed",
					"met": _large_departed >= min_large,
					"current": _large_departed,
					"target": min_large,
				}
			)
		)
	var min_rate := float(level["min_made_rate"])
	if min_rate >= 0.0:
		var ratio := float(metrics.get("made_ratio", -1.0))
		(
			items
			. append(
				{
					"label": "Made / on-time rate",
					"met": ratio >= 0.0 and ratio + RATE_EPSILON >= min_rate,
					"current": ratio,
					"target": min_rate,
				}
			)
		)


func _unbind() -> void:
	if not _bound:
		return
	if is_instance_valid(flights) and flights.state_changed.is_connected(_on_flight_state):
		flights.state_changed.disconnect(_on_flight_state)
	if is_instance_valid(rating) and rating.changed.is_connected(_on_rating_changed):
		rating.changed.disconnect(_on_rating_changed)
	if is_instance_valid(passengers) and passengers.outcome.is_connected(_on_passenger_outcome):
		passengers.outcome.disconnect(_on_passenger_outcome)
	if is_instance_valid(clock) and clock.ticked.is_connected(_on_clock_ticked):
		clock.ticked.disconnect(_on_clock_ticked)
	_bound = false


func _on_flight_state(flight_id: String, state: int) -> void:
	if _loading or state != FlightSim.State.DEPARTED or flights == null:
		return
	var contract := flights.contract_of(flights.flight_contract_id(flight_id))
	var plane_class: String = str(contract.get("plane_size", FlightSim.STARTER_TERMS["plane_size"]))
	record_departure(plane_class)
	evaluate_live()


func _on_rating_changed() -> void:
	if not _loading:
		evaluate_live()


func _on_passenger_outcome(_id: int, made: bool) -> void:
	if not _loading and made:
		evaluate_live()


func _on_clock_ticked(_tick: int) -> void:
	if not _loading:
		evaluate_live()
