class_name SimClock
extends Node
## Fixed-tick simulation clock. Real frame time is scaled by the speed and
## consumed in fixed STEP-second steps; views interpolate with `alpha`.
## Also owns the sim's RandomNumberGenerator, kept apart from cosmetic
## randomness so a save can restore it (see seed_rng and restore_rng).
##
## Quiet-night fast-forward (decision quiet-nights-fast-forward-automatically-
## when-nothing-is-due): once a frame, before any step, fast_forward_source
## (QuietNight) names the tick a fast-forward may run to. Until that tick the
## clock runs at FAST_FORWARD_SPEED instead of `speed`, still one tick at a time
## and within MAX_STEPS_PER_FRAME, and it stops on that exact tick; the rest of
## the frame runs at `speed`. `speed` itself never changes, and nothing of the
## fast-forward is saved: a load ends it.
##
## Pause is two things (decision daily-incidents-technical-design-
## incidentdirector-shared-clo): the player's own pause (set_paused: Space, the
## speed buttons) and the holds that dialogs and build mode take (`holds`, a
## ClockHolds). `paused` is true while either pauses the clock; `speed` is only
## ever the player's. Releasing a hold restores nothing: with no hold left, the
## player's pause and speed apply again. Resuming or picking another speed
## while held ends the pause of the holds that give way to the player (build
## mode, the Offers sheet, which keeps its exclusive turn until it closes); a
## modal dialog's hold keeps the clock paused, and the
## player's choice applies once it closes. Installing a snapshot (a load)
## drops every hold.
##
## A ticked listener that pauses the clock (UnlockGuide opening at midnight)
## ends the frame on that tick, at any speed; the steps the frame still owed
## are dropped, as the step cap drops a backlog.

signal ticked(tick: int)

const TICK_RATE := 20
const STEP := 1.0 / TICK_RATE
const SPEEDS: Array[int] = [1, 2, 3]
## Most steps one frame may run. Past this the backlog is dropped, so a long
## stall does not make the next frame run even longer.
const MAX_STEPS_PER_FRAME := 10
## Times the 1x rate a quiet-night fast-forward runs at: 600 ticks a second,
## which is MAX_STEPS_PER_FRAME at 60 frames a second, so a faster rate would
## only feed the backlog the cap drops. A 13.5-hour night (16,200 ticks, about
## 270 s at 3x) then passes in about 27 s.
const FAST_FORWARD_SPEED := 30
const SAVE_VERSION := 1
const SNAPSHOT_KEYS := [
	"save_version", "tick", "speed", "paused", "accumulator", "rng_seed", "rng_state"
]

var tick: int = 0
var speed: int = 1
## True while the player paused the clock or any hold is held. Setting it is
## set_paused(): it sets the player's pause only.
var paused: bool:
	get:
		return _player_paused or holds.is_holding()
	set(value):
		set_paused(value)
## The player's own pause, apart from the holds. Read it only; set_paused()
## sets it.
var player_paused: bool:
	get:
		return _player_paused
## Every dialog's and build mode's hold on the clock.
var holds := ClockHolds.new()
var rng := RandomNumberGenerator.new()
## Asked once a frame while running: returns the tick a fast-forward may run
## to, or -1 for none. Unset, the clock never fast-forwards. Not saved.
var fast_forward_source := Callable()
## The tick the running fast-forward stops on, or -1. Not saved.
var fast_forward_until := -1

## Leftover accumulator over the step, in [0, 1). Views draw between the last
## two ticks with it.
var alpha: float:
	get:
		return _accumulator / STEP

var _accumulator: float = 0.0
var _player_paused := false
## True while `ticked` is being emitted, so SaveGame can refuse to save or
## load from inside a tick.
var _in_tick := false


func _init() -> void:
	rng.randomize()


func _process(delta: float) -> void:
	advance(delta)


func advance(real_delta: float) -> void:
	if paused:
		fast_forward_until = -1
		return
	fast_forward_until = -1
	if fast_forward_source.is_valid():
		fast_forward_until = int(fast_forward_source.call())
	var fast := is_fast_forwarding()
	_accumulator += real_delta * (FAST_FORWARD_SPEED if fast else speed)
	var steps := 0
	while _accumulator >= STEP and steps < MAX_STEPS_PER_FRAME:
		_accumulator -= STEP
		tick += 1
		steps += 1
		_in_tick = true
		ticked.emit(tick)
		_in_tick = false
		if fast and (paused or tick >= fast_forward_until):
			# The stop: what is left of the frame is player-speed time.
			fast = false
			_accumulator *= float(speed) / FAST_FORWARD_SPEED
		# A listener paused (UnlockGuide at midnight): no tick runs under it.
		if paused:
			break
	if _accumulator >= STEP:
		_accumulator = fposmod(_accumulator, STEP)


## True from the moment a tick is emitted until every listener has returned.
func is_in_tick() -> bool:
	return _in_tick


## True while a quiet-night fast-forward runs: running, with its stop ahead.
func is_fast_forwarding() -> bool:
	return not paused and fast_forward_until > tick


## Sets the player's pause. Resuming (false) also ends every hold that gives
## way to the player.
func set_paused(value: bool) -> void:
	_player_paused = value
	if not value:
		holds.yield_to_player()


## Returns false and leaves the speed unchanged when `value` is not in SPEEDS.
## A new speed also ends every hold that gives way to the player.
func set_speed(value: int) -> bool:
	if not SPEEDS.has(value):
		push_error("SimClock: unsupported speed %d" % value)
		return false
	var changed := value != speed
	speed = value
	if changed:
		holds.yield_to_player()
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
## or value. A restored snapshot is a replaced world: every hold is dropped and
## the saved "paused" becomes the player's pause.
func from_snapshot(data: Dictionary) -> bool:
	var problem := _snapshot_problem(data)
	if problem != "":
		push_error("SimClock.from_snapshot: %s" % problem)
		return false
	tick = str(data["tick"]).to_int()
	speed = int(data["speed"])
	holds.clear()
	_player_paused = data["paused"]
	_accumulator = float(data["accumulator"])
	fast_forward_until = -1
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
