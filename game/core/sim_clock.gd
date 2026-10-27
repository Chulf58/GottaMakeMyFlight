class_name SimClock
extends Node
## Fixed-tick simulation clock. Real frame time is scaled by the speed and
## consumed in fixed STEP-second steps; views interpolate with `alpha`.
## Also owns the sim's RandomNumberGenerator, kept apart from cosmetic
## randomness so a save can restore it (see seed_rng and restore_rng).

signal ticked(tick: int)

const TICK_RATE := 20
const STEP := 1.0 / TICK_RATE
const SPEEDS: Array[int] = [1, 2, 3]
## Most steps one frame may run. Past this the backlog is dropped, so a long
## stall does not make the next frame run even longer.
const MAX_STEPS_PER_FRAME := 10
const SAVE_VERSION := 1
const SNAPSHOT_KEYS := [
	"save_version", "tick", "speed", "paused", "accumulator", "rng_seed", "rng_state"
]

var tick: int = 0
var speed: int = 1
var paused: bool = false
var rng := RandomNumberGenerator.new()

## Leftover accumulator over the step, in [0, 1). Views draw between the last
## two ticks with it.
var alpha: float:
	get:
		return _accumulator / STEP

var _accumulator: float = 0.0


func _init() -> void:
	rng.randomize()


func _process(delta: float) -> void:
	advance(delta)


func advance(real_delta: float) -> void:
	if paused:
		return
	_accumulator += real_delta * speed
	var steps := 0
	while _accumulator >= STEP and steps < MAX_STEPS_PER_FRAME:
		_accumulator -= STEP
		tick += 1
		steps += 1
		ticked.emit(tick)
	if _accumulator >= STEP:
		_accumulator = fposmod(_accumulator, STEP)


func set_paused(value: bool) -> void:
	paused = value


## Returns false and leaves the speed unchanged when `value` is not in SPEEDS.
func set_speed(value: int) -> bool:
	if not SPEEDS.has(value):
		push_error("SimClock: unsupported speed %d" % value)
		return false
	speed = value
	return true


func seed_rng(new_seed: int) -> void:
	rng.seed = new_seed


## Setting the seed resets the state, so the state is applied second.
func restore_rng(saved_seed: int, saved_state: int) -> void:
	rng.seed = saved_seed
	rng.state = saved_state


## JSON-safe state for a save. The tick and the RNG seed and state are
## decimal strings because JSON numbers are doubles and lose 64-bit integers
## above 2^53.
func to_snapshot() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"tick": str(tick),
		"speed": speed,
		"paused": paused,
		"accumulator": _accumulator,
		"rng_seed": str(rng.seed),
		"rng_state": str(rng.state),
	}


## Restores a to_snapshot() dictionary, including one that went through JSON
## (which turns ints into floats). Pushes an error and returns false, leaving
## the clock unchanged, when any key is missing or unknown, or has a bad type
## or value.
func from_snapshot(data: Dictionary) -> bool:
	var problem := _snapshot_problem(data)
	if problem != "":
		push_error("SimClock.from_snapshot: %s" % problem)
		return false
	tick = str(data["tick"]).to_int()
	speed = int(data["speed"])
	paused = data["paused"]
	_accumulator = float(data["accumulator"])
	restore_rng(str(data["rng_seed"]).to_int(), str(data["rng_state"]).to_int())
	return true


func _snapshot_problem(data: Dictionary) -> String:
	for key in data.keys():
		if not SNAPSHOT_KEYS.has(key):
			return "unknown key '%s'" % key
	for key in SNAPSHOT_KEYS:
		if not data.has(key):
			return "missing key '%s'" % key
	if not _is_whole_number(data["save_version"]) or int(data["save_version"]) != SAVE_VERSION:
		return "save_version must be %d" % SAVE_VERSION
	var problem := _clock_field_problem(data)
	if problem != "":
		return problem
	for key in ["rng_seed", "rng_state"]:
		if not is_int64_string(data[key]):
			return "%s must be a decimal string within 64-bit range" % key
	return ""


func _clock_field_problem(data: Dictionary) -> String:
	if not is_int64_string(data["tick"]) or str(data["tick"]).begins_with("-"):
		return "tick must be a decimal string, 0 or more"
	if not _is_whole_number(data["speed"]) or not SPEEDS.has(int(data["speed"])):
		return "speed must be one of %s" % [SPEEDS]
	if typeof(data["paused"]) != TYPE_BOOL:
		return "paused must be a bool"
	var acc: Variant = data["accumulator"]
	if typeof(acc) not in [TYPE_INT, TYPE_FLOAT] or acc < 0.0 or acc >= STEP:
		return "accumulator must be a number in [0, STEP)"
	return ""


## Exact: a float must hold a whole number with no tolerance.
func _is_whole_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_finite(value) and value == floorf(value)


## A canonical decimal string of a 64-bit integer. String.to_int() clamps a
## value past the limits instead of failing, so the string must read back
## exactly as written; that also refuses "+5" and "007".
static func is_int64_string(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or not (value as String).is_valid_int():
		return false
	return str((value as String).to_int()) == value
