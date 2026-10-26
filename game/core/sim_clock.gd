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
