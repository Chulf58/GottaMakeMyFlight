class_name BuildSession
extends Node
## Build mode as the player lives it (ruling
## player-owns-clock-and-persistent-build-undo-no-auto-pause-on-trays-offers-planner-direct-delete):
## it lasts while a build tray is open or a build tool is picked. BuildMenu says
## when (set_building). Opening or closing build mode never pauses or resumes
## the sim clock and never clears the undo history; only a load (abandon())
## ends the session and drops the history.

signal changed(active: bool)

@export var build_mode: BuildMode
## Kept for scene/test wiring compatibility; BuildSession leaves the clock alone.
@export var clock: SimClock

## True from the moment build mode starts until it ends.
var active := false


## Starts or ends build mode without touching the sim clock or undo history.
func set_building(on: bool) -> void:
	if on == active:
		return
	active = on
	changed.emit(active)


## Ends build mode after a load and clears the undo history for the new world.
func abandon() -> void:
	set_building(false)
	if build_mode != null:
		build_mode.clear_undo()


## Kept for callers that previously flushed pending clock holds; now a no-op.
func sync() -> void:
	pass
