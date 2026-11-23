class_name BuildSession
extends Node
## Build mode as the player lives it (decision
## build-mode-auto-pause-restored-while-offers-planner-stay-unpaused,
## 9e86b858, partial override of ea4411e6): it lasts while a build tray is
## open or a build tool is picked. BuildMenu says when (set_building). While
## active it acquires a yielding hold on SimClock.holds so entering build mode
## pauses the clock and closing it releases the hold; Space or a speed key can
## still unpause manually while building (the hold yields without ending build
## mode). Undo history persists across build sessions and sim ticks; only a
## load (abandon()) ends the session and drops the history.

signal changed(active: bool)

## Processes ahead of every default-priority node, SimClock included.
const PROCESS_PRIORITY := -1000

@export var build_mode: BuildMode
## Paused while building; null leaves the clock alone.
@export var clock: SimClock

## True from the moment build mode starts until it ends.
var active := false

var _hold_pending := false
var _hold := ClockHolds.NONE


func _init() -> void:
	# Before everything else in the frame, so a deferred hold lands before SimClock
	# (earlier in the tree than the menu) processes.
	process_priority = PROCESS_PRIORITY


func _process(_delta: float) -> void:
	sync()


## Starts or ends build mode. Starting acquires a yielding hold on the clock;
## ending releases it. Undo history stays intact until abandon().
func set_building(on: bool) -> void:
	if on == active:
		return
	active = on
	if on:
		_acquire_hold()
	else:
		_hold_pending = false
		_release_clock()
	changed.emit(active)


## Ends build mode after a load and clears the undo history for the new world.
## Installing the loaded clock dropped every hold already, so releasing finds
## nothing to end and the clock stays as loaded.
func abandon() -> void:
	_hold_pending = false
	set_building(false)
	if build_mode != null:
		build_mode.clear_undo()


## Re-syncs deferred holds (when clock or tree membership arrived after
## set_building(true)) and clears _hold once it yielded to the player.
func sync() -> void:
	if not active or clock == null:
		return
	if _hold != ClockHolds.NONE and not clock.holds.has(_hold):
		_hold = ClockHolds.NONE
	elif _hold_pending and is_inside_tree():
		_hold_pending = false
		_hold = clock.holds.acquire(self, true)


## A session that leaves the tree while building must not leave the game paused.
func _exit_tree() -> void:
	_hold_pending = false
	_release_clock()


func _acquire_hold() -> void:
	if clock != null and is_inside_tree() and _hold == ClockHolds.NONE:
		_hold_pending = false
		_hold = clock.holds.acquire(self, true)
	else:
		_hold_pending = true


## Nothing is restored: with no hold left, the player's own pause applies.
func _release_clock() -> void:
	if is_instance_valid(clock):
		clock.holds.release(_hold)
	_hold = ClockHolds.NONE
