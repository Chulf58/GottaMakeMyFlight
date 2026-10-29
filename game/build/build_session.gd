class_name BuildSession
extends Node
## Build mode as the player lives it (decision build-mode-pauses-the-game-
## while-a-build-tray-is-open-closin): it lasts while a build tray is open or a
## build tool is picked. BuildMenu says when (set_building). While it lasts the
## sim clock is paused; when it ends the clock goes back to how the player had
## it (paused included) and the undo history is cleared, so Ctrl+Z only ever
## undoes this session's builds.
##
## The clock is taken on the next sync(), not at once, so a panel that closes
## in the same tool change (the Offers sheet gives its own hold back then) has
## already given the clock back and the hold is taken from the true state. A
## clock the player changes while building (Space, a speed key) is theirs: it
## ends build mode and is not restored.

signal changed(active: bool)

@export var build_mode: BuildMode
## Paused while building; null leaves the clock alone.
@export var clock: SimClock

## True from the moment build mode starts until it ends.
var active := false

var _hold_pending := false
var _holding := false
var _held_paused := false
var _held_speed := 1


func _process(_delta: float) -> void:
	sync()


## Starts or ends build mode. Ending clears the undo history and gives back the
## clock the player had.
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
			build_mode.undo_history().clear()
	changed.emit(active)


## Takes the clock once build mode has started, and ends build mode when the
## player changed the clock meanwhile.
func sync() -> void:
	if not active or clock == null:
		return
	if _holding and (not clock.paused or clock.speed != _held_speed):
		_holding = false
		if build_mode != null:
			build_mode.set_tool(BuildMode.Tool.NONE)
		set_building(false)
	elif _hold_pending:
		_hold_pending = false
		_held_paused = clock.paused
		_held_speed = clock.speed
		clock.set_paused(true)
		_holding = true


## A session that leaves the tree while building must not leave the game paused.
func _exit_tree() -> void:
	_release_clock()


func _release_clock() -> void:
	if not _holding:
		return
	_holding = false
	if not is_instance_valid(clock) or not clock.paused or clock.speed != _held_speed:
		return
	clock.set_paused(_held_paused)
