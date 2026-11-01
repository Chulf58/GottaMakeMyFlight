class_name RoofCutaway
extends RefCounted
## The player-built roof's level rule (RoofView): ShellCutaway's roof rule
## without its facade parts. View only: it changes no node, grid or path.
##
## The roof has a level from 0 (drawn) to 1 (gone). Its target turns 1 once
## the camera's zoom distance is below roof_hide_below and 0 once it is above
## roof_show_above; in between it keeps its last target, so the roof does not
## flicker at the threshold. The level moves to its target at a constant
## rate, a full change taking roof_fade_seconds (user ruling toon-terminal-
## roof-shows-from-far-away-and-fades-out-when-th; the threshold is a tuning
## value).

## Tuning values, ShellCutaway's defaults.
var roof_hide_below := 100.0
var roof_show_above := 120.0
var roof_fade_seconds := 0.4

var roof_target := 0.0
var roof_level := 0.0


## Sets the target from the camera's distance and jumps the level to it, with
## no fade: for the first frame. A distance inside the band draws the roof.
func snap(distance: float) -> void:
	roof_target = 1.0 if distance < roof_hide_below else 0.0
	roof_level = roof_target


## Updates the target from the camera's distance and moves the level toward
## it by `delta` seconds of fade.
func step(distance: float, delta: float) -> void:
	if distance < roof_hide_below:
		roof_target = 1.0
	elif distance > roof_show_above:
		roof_target = 0.0
	roof_level = ShellCutaway.approach(roof_level, roof_target, delta, roof_fade_seconds)


## Whether any of the roof is drawn (the level is below 1).
func is_drawn() -> bool:
	return roof_level < 1.0


## What is wrong with the tuning values, or "" when they are usable.
func tuning_error() -> String:
	if roof_fade_seconds <= 0.0:
		return "roof fade time must be above 0 (got %s s)" % roof_fade_seconds
	if roof_hide_below <= 0.0 or roof_hide_below > roof_show_above:
		return (
			"need 0 < roof_hide_below <= roof_show_above (got %s, %s)"
			% [roof_hide_below, roof_show_above]
		)
	return ""
