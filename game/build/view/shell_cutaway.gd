class_name ShellCutaway
extends RefCounted
## The Toon terminal shell's cutaway rule (Shell 3/4), as levels ShellView
## draws. View only: it changes no node, grid or path.
##
## Roof: the roof group (Upper, Canopy, Lights_Upper) has a level from 0
## (drawn) to 1 (gone). Its target turns 1 once the camera's zoom distance is
## below roof_hide_below and 0 once it is above roof_show_above; in between it
## keeps its last target, so the roof does not flicker at the threshold. The
## level moves to its target at a constant rate, a full change taking
## roof_fade_seconds, and is drawn as a dither on the surface and its outline
## (user ruling toon-terminal-roof-shows-from-far-away-and-fades-out-when-th).
##
## Facade: every ground-storey piece belongs to the north, south, east or west
## outer face. The camera's heading, in the shell's frame, picks the side it
## looks from on each axis with WallCutaway's rule and dead band. Every outer
## wall has the shell's interior floor behind it, so WallCutaway's floor-behind
## test always passes and the sides the camera looks from (one, or two at a
## diagonal) are cut; the far sides stay full height. A cut side is squashed
## in the shell's y about the floor to a STUB_HEIGHT kerb, as the build view
## squashes a cut wall (InteriorKit.wall_parts). Its level moves in
## side_fade_seconds, so a turn drops the wall rather than popping it.
##
## Gate: with cut_only_without_roof (the default) a side is cut by its level
## times the roof level, so while the roof is drawn all four sides stand full
## and the airport looks finished from afar.

enum Side { NORTH, SOUTH, EAST, WEST }

## The shell's floor height and its ground storey's height, in shell space.
const FLOOR_Y := 0.3
const FACADE_HEIGHT := 5.2
const STUB_FACTOR := InteriorKit.STUB_HEIGHT / FACADE_HEIGHT
const SIDE_LETTERS := {"N": Side.NORTH, "S": Side.SOUTH, "E": Side.EAST, "W": Side.WEST}

## Tuning values (the user ruled the threshold is one).
var roof_hide_below := 100.0
var roof_show_above := 120.0
var roof_fade_seconds := 0.4
var side_fade_seconds := 0.25
var cut_only_without_roof := true

var roof_target := 0.0
var roof_level := 0.0
## Indexed by Side: 0 standing, 1 cut.
var side_levels: Array = [0.0, 0.0, 0.0, 0.0]

var _sides := WallCutaway.new()


## Sets every target from the camera and jumps every level to it, with no
## fade: for the first frame. A distance inside the band draws the roof.
func snap(distance: float, toward_eye: Vector3) -> void:
	roof_target = 1.0 if distance < roof_hide_below else 0.0
	roof_level = roof_target
	_sides.reset()
	_sides.update(toward_eye)
	for side in 4:
		side_levels[side] = side_target(side)


## Updates the targets from the camera and moves every level toward its own
## by `delta` seconds of fade.
func step(distance: float, toward_eye: Vector3, delta: float) -> void:
	if distance < roof_hide_below:
		roof_target = 1.0
	elif distance > roof_show_above:
		roof_target = 0.0
	roof_level = approach(roof_level, roof_target, delta, roof_fade_seconds)
	_sides.update(toward_eye)
	for side in 4:
		side_levels[side] = approach(side_levels[side], side_target(side), delta, side_fade_seconds)


## What is wrong with the tuning values, or "" when they are usable.
func tuning_error() -> String:
	if roof_fade_seconds <= 0.0 or side_fade_seconds <= 0.0:
		return (
			"fade times must be above 0 (roof %s s, side %s s)"
			% [roof_fade_seconds, side_fade_seconds]
		)
	if roof_hide_below <= 0.0 or roof_hide_below > roof_show_above:
		return (
			"need 0 < roof_hide_below <= roof_show_above (got %s, %s)"
			% [roof_hide_below, roof_show_above]
		)
	return ""


## 1 when the camera looks from `side`, else 0.
func side_target(side: int) -> float:
	match side:
		Side.NORTH:
			return 1.0 if _sides.side_z < 0 else 0.0
		Side.SOUTH:
			return 1.0 if _sides.side_z > 0 else 0.0
		Side.EAST:
			return 1.0 if _sides.side_x > 0 else 0.0
	return 1.0 if _sides.side_x < 0 else 0.0


## How far `side` is cut, 0 to 1, after the roof gate.
func cut(side: int) -> float:
	var level: float = side_levels[side]
	return level * roof_level if cut_only_without_roof else level


## `level` moved toward `target` at the rate that makes a full change take
## `seconds`; it lands on the target exactly.
static func approach(level: float, target: float, delta: float, seconds: float) -> float:
	return move_toward(level, target, delta / seconds)


## The shell-space map that squashes a side cut by `amount`: y about FLOOR_Y,
## from full height (0) to the stub (1); x and z unchanged.
static func stub_transform(amount: float) -> Transform3D:
	var factor := lerpf(1.0, STUB_FACTOR, amount)
	return Transform3D(
		Basis.from_scale(Vector3(1.0, factor, 1.0)), Vector3(0.0, FLOOR_Y * (1.0 - factor), 0.0)
	)


## The side a Facade_<side>_<bay> or Lights_<side>_<bay> node names, or -1.
static func side_of_name(node_name: String) -> int:
	var parts := node_name.split("_")
	if parts.size() != 3 or not parts[0] in ["Facade", "Lights"]:
		return -1
	return SIDE_LETTERS.get(parts[1], -1)


## The outer face of `around` (both boxes in shell space) that `box`'s centre
## sits nearest, measured in shares of the half extents.
static func side_of_box(box: AABB, around: AABB) -> int:
	var offset := box.get_center() - around.get_center()
	var x := offset.x / (around.size.x * 0.5)
	var z := offset.z / (around.size.z * 0.5)
	if absf(x) > absf(z):
		return Side.EAST if x > 0.0 else Side.WEST
	return Side.SOUTH if z > 0.0 else Side.NORTH
