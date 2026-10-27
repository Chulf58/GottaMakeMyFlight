class_name FlightContract
extends RefCounted
## An accepted airline offer: the terms captured at acceptance, which never
## change afterwards. A contract is a read-only Dictionary, so writing to one
## is an engine error rather than a silent change. FlightSim makes contracts
## with make() and adds first_day, the day of the first occurrence.
##
## departure_minute is the scheduled departure (the start of PUSHBACK) in
## minutes past midnight; every other deadline of an occurrence derives from
## it by the fixed phase lengths in FlightSim.PHASE_TICKS.

## The terms an offer carries.
const TERM_KEYS := [
	"id",
	"airline",
	"destination",
	"departure_minute",
	"gate",
	"plane_size",
	"booked_passengers",
	"fee_per_passenger",
]
## A stored contract: the terms plus first_day.
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
]
const TEXT_KEYS := ["airline", "destination", "gate", "plane_size"]
const PLANE_SIZES := ["small", "medium", "large"]
const MAX_BOOKED := 999
## Keeps booked_passengers * fee_per_passenger far below Wallet.MAX_BALANCE.
const MAX_FEE := 1_000_000
## Contract days stay small enough that every derived tick fits a JSON number.
const MAX_DAY := 1_000_000_000

## Letters and digits only, so "<id>-d<day>" occurrence ids parse one way.
static var _id_pattern := RegEx.create_from_string("^[A-Za-z0-9]+$")


## "" when `data` has exactly `keys` (TERM_KEYS or KEYS) with valid values;
## otherwise what is wrong. JSON whole floats count as whole numbers.
static func problem(data: Variant, keys: Array) -> String:
	if typeof(data) != TYPE_DICTIONARY:
		return "a contract must be a dictionary"
	for key in data.keys():
		if not keys.has(key):
			return "unknown contract key '%s'" % key
	for key in keys:
		if not data.has(key):
			return "missing contract key '%s'" % key
	var id: Variant = data["id"]
	if typeof(id) != TYPE_STRING or _id_pattern.search(id) == null:
		return "contract id must be letters and digits"
	for key in TEXT_KEYS:
		if typeof(data[key]) != TYPE_STRING or data[key] == "":
			return "%s must be a non-empty string" % key
	if not PLANE_SIZES.has(data["plane_size"]):
		return "plane_size must be one of %s" % [PLANE_SIZES]
	return _number_problem(data, keys)


## A read-only copy of checked `data`, whole numbers as ints.
static func make(data: Dictionary) -> Dictionary:
	var contract := {}
	for key in data.keys():
		var value: Variant = data[key]
		contract[key] = int(value) if typeof(value) == TYPE_FLOAT else value
	contract.make_read_only()
	return contract


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
