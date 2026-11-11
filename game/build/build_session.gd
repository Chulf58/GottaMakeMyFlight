class_name BuildSession
extends Node
## Build mode as the player lives it (decision build-mode-pauses-the-game-
## while-a-build-tray-is-open-closin): it lasts while a build tray is open or a
## build tool is picked. BuildMenu says when (set_building). While it lasts it
## holds the sim clock paused (a hold on SimClock.holds); when it ends the hold
## is released, so the player's own speed, paused included, applies again
## unless another hold (the Offers sheet, a dialog) still pauses the game. The
## undo history is cleared on the end, so Ctrl+Z only ever undoes this
## session's builds.
##
## The hold is taken on the next sync(), which runs ahead of SimClock in the
## frame, so no tick runs after a tray opens. The hold gives way to the player:
## resuming or picking another speed while building (Space, a speed key) ends
## it, and the next sync() then ends build mode.

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
	# Before everything else in the frame, so a pause taken here lands before SimClock
	# (earlier in the tree than the menu) processes: no tick runs after a tray opens.
	process_priority = PROCESS_PRIORITY


func _process(_delta: float) -> void:
	sync()


## Starts or ends build mode. Ending clears the undo history and releases the
## hold on the clock.
func set_building(on: bool) -> void:
	if on == active:
		return
	if on:
		active = true
		_hold_pending = clock != null
	else:
		_release_clock()
		_hold_pending = false
		active = false
		if build_mode != null:
			build_mode.clear_undo()
	changed.emit(active)


## Ends build mode after a load. Installing the loaded clock dropped every hold
## already, so the release finds nothing to end and the clock stays as loaded.
func abandon() -> void:
	_hold_pending = false
	set_building(false)


## Takes the clock once build mode has started, and ends build mode when the
## player resumed or picked another speed meanwhile (the hold gave way).
func sync() -> void:
	if not active or clock == null:
		return
	if _hold != ClockHolds.NONE and not clock.holds.has(_hold):
		_hold = ClockHolds.NONE
		if build_mode != null:
			build_mode.set_tool(BuildMode.Tool.NONE)
		set_building(false)
	elif _hold_pending:
		_hold_pending = false
		_hold = clock.holds.acquire(self, true)


## A session that leaves the tree while building must not leave the game paused
## (the holds also end a hold whose owner leaves).
func _exit_tree() -> void:
	_release_clock()


## Nothing is restored: with no hold left, the player's own pause applies.
func _release_clock() -> void:
	if is_instance_valid(clock):
		clock.holds.release(_hold)
	_hold = ClockHolds.NONE
