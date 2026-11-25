class_name FlightContract
extends RefCounted
## An accepted airline offer: the terms captured at acceptance, which never
## change afterwards. A contract is a read-only Dictionary, so writing to one
## is an engine error rather than a silent change. FlightSim makes contracts
## with make() and adds first_day, the day of the first occurrence.
##
## departure_minute is the scheduled departure (the start of PUSHBACK) in
## minutes past midnight; every other deadline of an occurrence derives from
## it by the phase lengths in FlightSim.PHASE_TICKS, with the contract's own
## taxi pair (TAXI_KEY) for TAXI_IN and TAXI_OUT.
##
## The gate is the one term that may change (user ruling gates-are-placed-
## gate-desks-each-desk-links-automatically-to): it is not a term the airline
## agreed to. FlightSim gives a contract its gate on accept and
## FlightSim.reassign_gate replaces the contract with a copy at another gate.
## The gate and the taxi pair it needs (TaxiTimes, ruling taxi-time-follows-
## each-gate-s-route-length-far-side-gates-ta) are the contract's assignment,
## always set together by assigned(), the one constructor every accept, trial,
## reassignment and move goes through. The pair is a frozen copy; the
## occurrences already issued keep the times they were issued with.
##
## The offer's trade-off traits (OfferTraits, decision offer-traits-technical-
## design-offertraits-table-frozen-trait) are the term TRAITS_KEY: {} for a plain
## offer, {"up", "down", "level"} for a paired one. Offer terms may leave it out
## (plain); a stored contract always has it, so make() adds {} when it is
## missing, and the nested dictionary is a frozen copy like the contract itself.

## The terms an offer carries. No gate: FlightSim picks one on accept.
const TERM_KEYS := [
	"id",
	"airline",
	"destination",
	"departure_minute",
	"plane_size",
	"booked_passengers",
	"fee_per_passenger",
]
## A stored contract: the terms plus its gate, first_day and taxi pair.
const KEYS := [
	"id",
	"airline",
	"destination",
	"departure_minute",
	"gate",
	"plane_size",
	"booked_passengers",
	"fee_per_passenger",
	"first_day",
	"traits",
	"taxi",
]
## The traits term: optional in offer terms (TERM_KEYS), required in KEYS.
const TRAITS_KEY := "traits"
## The taxi pair [TAXI_IN, TAXI_OUT] of the gate the contract is assigned to
## (TaxiTimes): never in offer terms, required in KEYS.
const TAXI_KEY := "taxi"
## Calendar day (>= 0) for a one-off same-day charter, or -1 for a repeating
## daily contract. Optional in TERM_KEYS and KEYS; stored as int by make().
const ONE_OFF_DAY_KEY := "one_off_day"
## True for a Gold Hub Contract (Stage 2 S2-C). Optional in TERM_KEYS and KEYS;
## stored as bool by make().
const IS_HUB_KEY := "is_hub"
## Stand ID assigned to the contract ("A", "R1", ...); defaults to "gate".
const STAND_KEY := "stand"
const TEXT_KEYS := ["airline", "destination", "gate", "plane_size"]
const PLANE_SIZES := ["small", "medium", "large"]
const MAX_BOOKED := 999
## Keeps booked_passengers * fee_per_passenger far below Wallet.MAX_BALANCE.
const MAX_FEE := 1_000_000
## Contract days stay small enough that every derived tick fits a JSON number.
const MAX_DAY := 1_000_000_000
## The departure window (decision odd-hours-technical-design-contract-
## validation-allows-06-00): 07:00 to 21:00, widened at each end by
## OfferTraits.window_widening for an Odd hours contract (06:00 to 22:00).
## window_problem checks it from the frozen traits; FlightSim asks it on accept
## and in every fit trial, and FlightSnapshot on load.
const FIRST_DEPARTURE_MINUTE := 7 * 60
const LAST_DEPARTURE_MINUTE := 21 * 60
const QUIET_NIGHT_TEXT := "it departs in the quiet night, outside 07:00 to 21:00"
const ODD_HOURS_NIGHT_TEXT := "it departs in the quiet night, outside 06:00 to 22:00"

## Letters and digits only, so "<id>-d<day>" occurrence ids parse one way.
static var _id_pattern := RegEx.create_from_string("^[A-Za-z0-9]+$")


## "" when `data` has exactly `keys` (TERM_KEYS or KEYS) with valid values;
## otherwise what is wrong. TERM_KEYS data may also hold TRAITS_KEY. JSON whole
## floats count as whole numbers.
static func problem(data: Variant, keys: Array) -> String:
	if typeof(data) != TYPE_DICTIONARY:
		return "a contract must be a dictionary"
	for key in data.keys():
		var allowed: bool = (
			keys.has(key)
			or key == TRAITS_KEY
			or key == ONE_OFF_DAY_KEY
			or key == IS_HUB_KEY
			or (keys.has("gate") and key == STAND_KEY)
		)
		if not allowed:
			return "unknown contract key '%s'" % key
	for key in keys:
		if not data.has(key):
			return "missing contract key '%s'" % key
	var id: Variant = data["id"]
	if typeof(id) != TYPE_STRING or _id_pattern.search(id) == null:
		return "contract id must be letters and digits"
	for key in TEXT_KEYS:
		if keys.has(key) and (typeof(data[key]) != TYPE_STRING or data[key] == ""):
			return "%s must be a non-empty string" % key
	if not PLANE_SIZES.has(data["plane_size"]):
		return "plane_size must be one of %s" % [PLANE_SIZES]
	var problem := _number_problem(data, keys)
	if problem == "" and data.has(ONE_OFF_DAY_KEY):
		var one_off: Variant = data[ONE_OFF_DAY_KEY]
		if not WholeNumber.is_whole(one_off) or int(one_off) < -1 or int(one_off) > MAX_DAY:
			problem = "one_off_day must be -1 or a whole number from 0 to %d" % MAX_DAY
	if problem == "" and data.has(IS_HUB_KEY):
		if typeof(data[IS_HUB_KEY]) != TYPE_BOOL:
			problem = "is_hub must be a boolean"
		elif bool(data[IS_HUB_KEY]) and is_charter(data):
			problem = "a one-off charter cannot be a hub contract"
	if problem == "" and data.has(STAND_KEY):
		if typeof(data[STAND_KEY]) != TYPE_STRING or String(data[STAND_KEY]) == "":
			problem = "stand must be a non-empty string"
	if problem == "" and data.has(TRAITS_KEY):
		problem = OfferTraits.problem(data[TRAITS_KEY])
	if problem == "" and keys.has(TAXI_KEY):
		problem = TaxiTimes.problem(data[TAXI_KEY])
	if problem == "" and not _fits_class(data):
		var limits := PlaneClasses.passenger_range(data["plane_size"])
		return (
			"booked_passengers must be %d to %d for a %s plane"
			% [limits[0], limits[1], data["plane_size"]]
		)
	return problem


## A read-only copy of checked `data`, whole numbers as ints, with a frozen copy
## of its traits ({} when it has none) and of its taxi pair when it has one.
static func make(data: Dictionary) -> Dictionary:
	var contract := {}
	for key in data.keys():
		var value: Variant = data[key]
		contract[key] = int(value) if typeof(value) == TYPE_FLOAT else value
	contract[TRAITS_KEY] = OfferTraits.frozen(data.get(TRAITS_KEY, {}))
	contract[ONE_OFF_DAY_KEY] = int(data.get(ONE_OFF_DAY_KEY, -1))
	contract[IS_HUB_KEY] = bool(data.get(IS_HUB_KEY, false))
	if data.has("gate"):
		contract[STAND_KEY] = String(data.get(STAND_KEY, data["gate"]))
	if data.has(TAXI_KEY):
		contract[TAXI_KEY] = TaxiTimes.frozen(data[TAXI_KEY])
	contract.make_read_only()
	return contract


static func is_hub(data: Dictionary) -> bool:
	return bool(data.get(IS_HUB_KEY, false))


static func one_off_day(data: Dictionary) -> int:
	return int(data.get(ONE_OFF_DAY_KEY, -1))


static func is_charter(data: Dictionary) -> bool:
	return one_off_day(data) >= 0


## Why no contract can be assigned to gate `gate_id` on StandPlacement stand
## `stand`: its join does not reach the taxi lane or its routes need a taxi
## pair past TaxiTimes' bounds (an issue after the first state, or a flight in
## the quiet night); "" when they do not. Every path that assigns a gate
## (accept, trials, reassign, moves) asks it first and refuses with these
## words, so assigned() never stores a stand or pair that is not valid.
static func assignment_problem(gate_id: String, stand: Dictionary) -> String:
	var layout := FlightGround.layout()
	match StandPlacement.side_of(stand):
		StandPlacement.WEST:
			layout["west_x"] = minf(layout["west_x"], StandPlacement.lane_x_of(stand))
		StandPlacement.EAST:
			layout["east_x"] = maxf(layout["east_x"], StandPlacement.lane_x_of(stand))
	if (
		not StandPlacement.reaches_lane(stand)
		or not TaxiRoutes.joins_lane(StandPlacement.lane_join(stand), layout)
	):
		return "gate %s's stand does not join the taxi lane" % gate_id
	var pair := TaxiTimes.for_stand(stand)
	if TaxiTimes.problem(pair) == "":
		return ""
	return (
		"gate %s's taxi route is too long: it needs %s ticks, more than %d in or %d out"
		% [gate_id, pair, TaxiTimes.MAX_IN, TaxiTimes.MAX_OUT]
	)


## The assignment constructor: a read-only copy of checked `data` (terms or a
## stored contract) at gate `gate_id`, whose StandPlacement stand is `stand`,
## with the taxi pair that stand's routes need (TaxiTimes.for_stand()). Any
## first_day in `data` is kept; FlightSim sets a new contract's. The caller has
## checked assignment_problem(); a stand it refuses is a defect, pushed as an
## error and answered with {} (nothing to store).
static func assigned(
	data: Dictionary, gate_id: String, stand: Dictionary, stand_id := ""
) -> Dictionary:
	var problem := assignment_problem(gate_id, stand)
	if problem != "":
		push_error("FlightContract.assigned: %s" % problem)
		return {}
	var fields := data.duplicate()
	fields["gate"] = gate_id
	fields[STAND_KEY] = gate_id if stand_id == "" else stand_id
	fields[TAXI_KEY] = TaxiTimes.for_stand(stand)
	return make(fields)


## The first and last departure minute a contract of `traits` may have.
static func window(traits: Dictionary) -> Array[int]:
	var widening := OfferTraits.window_widening(traits)
	var span: Array[int] = [FIRST_DEPARTURE_MINUTE - widening, LAST_DEPARTURE_MINUTE + widening]
	return span


## "" when checked `data` departs inside the window of its traits ({} when it
## has none); otherwise the player's words for the quiet night it departs in.
static func window_problem(data: Dictionary) -> String:
	var traits: Dictionary = data.get(TRAITS_KEY, {})
	var span := window(traits)
	var minute := int(data["departure_minute"])
	if minute >= span[0] and minute <= span[1]:
		return ""
	return ODD_HOURS_NIGHT_TEXT if OfferTraits.window_widening(traits) > 0 else QUIET_NIGHT_TEXT


static func _fits_class(data: Dictionary) -> bool:
	return PlaneClasses.passengers_fit(data["plane_size"], int(data["booked_passengers"]))


static func _number_problem(data: Dictionary, keys: Array) -> String:
	var ranges := {
		"departure_minute": GameCalendar.MINUTES_PER_DAY - 1,
		"booked_passengers": MAX_BOOKED,
		"fee_per_passenger": MAX_FEE,
	}
	if keys.has("first_day"):
		ranges["first_day"] = MAX_DAY
	for key in ranges:
		var value: Variant = data[key]
		if not WholeNumber.is_whole(value) or value < 0 or value > ranges[key]:
			return "%s must be a whole number from 0 to %d" % [key, ranges[key]]
	return ""
