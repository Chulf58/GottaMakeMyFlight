class_name ShellCutaway
extends RefCounted
## The Toon terminal shell's cutaway rule (Shell 3/4), as levels ShellView
## draws. View only: it changes no node, grid or path.
##
## Roof: the roof group (Upper, Canopy, Lights_Upper, Poles) has a level from 0
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
## Doorways: once a side is cut at least DOORWAY_OPEN_AT, its doorways open:
## the squashed door and porch are hidden, a hole over the opening drops the
## door bay's lintel (squashed into a bridge across the kerb), and two short
## jambs stand at the opening's edges so it reads as a door frame (user ruling
## 2026-10-26, "Short door-frame stubs").
##
## Gate: a side is cut by its level times the roof level, so while the roof is
## drawn all four sides stand full and the airport looks finished from afar
## (user ruling 2026-10-26, "Cut only when roof is gone").

enum Side { NORTH, SOUTH, EAST, WEST }

## The shell's floor height and its ground storey's height, in shell space.
const FLOOR_Y := 0.3
const FACADE_HEIGHT := 5.2
const STUB_FACTOR := InteriorKit.STUB_HEIGHT / FACADE_HEIGHT
const SIDE_LETTERS := {"N": Side.NORTH, "S": Side.SOUTH, "E": Side.EAST, "W": Side.WEST}
## A side's doorways open once it is cut this far.
const DOORWAY_OPEN_AT := 0.5
## Each jamb is a kit wall piece: this wide along the facade, this tall above
## the floor (the kerb is InteriorKit.STUB_HEIGHT), and across the kerb this
## deep (the facade bays are 0.5 m deep).
const JAMB_WIDTH := 0.15
const JAMB_HEIGHT := 0.6
const JAMB_DEPTH := 0.6
## The hole stops this far inside each opening edge, so the wall jamb faces
## that close the kerb at the edges stay; it reaches this far either side of
## the doorway line and up to this height, past any part of the bay.
const HOLE_INSET := 0.01
const HOLE_REACH := 1.5
const HOLE_TOP := 6.0
## A porch sign's hole starts this high (above the porch's door opening, 3.8)
## and reaches this far past the porch's footprint.
const SIGN_FLOOR := 3.9
const SIGN_MARGIN := 0.3

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


## Whether the doorways on `side` are open (see the class notes).
func doorway_open(side: int) -> bool:
	return cut(side) >= DOORWAY_OPEN_AT


## The box over a doorway's opening, in shell space, whose door-bay fragments
## are dropped while the doorway is open. `centre` is the doorway's floor
## centre on the doorway line, `outward` its outward direction.
static func hole_box(centre: Vector3, outward: Vector3, width: float) -> AABB:
	var along := _along(outward)
	var half := width * 0.5 - HOLE_INSET
	var lo := centre - along * half - outward.abs() * HOLE_REACH
	var hi := centre + along * half + outward.abs() * HOLE_REACH
	lo.y = FLOOR_Y - 1.0
	hi.y = HOLE_TOP
	return AABB(lo, hi - lo)


## The box over a porch's letter sign, in shell space: the sign is in the Lot
## mesh (on the porch's front edge, y 4.08 to 5.0 at Porch_6), so it stays
## when the porch is hidden; Lot's fragments in this box are dropped while the
## doorway is open. The porch footprint grown by SIGN_MARGIN, from SIGN_FLOOR up.
static func sign_box(porch_box: AABB) -> AABB:
	var lo := porch_box.position - Vector3(SIGN_MARGIN, 0.0, SIGN_MARGIN)
	var hi := porch_box.end + Vector3(SIGN_MARGIN, 0.0, SIGN_MARGIN)
	lo.y = SIGN_FLOOR
	hi.y = HOLE_TOP
	return AABB(lo, hi - lo)


## The two jambs of an open doorway, in shell space, as transforms of the kit
## wall piece (1 m long on its x, WALL_HEIGHT tall, pivot at its foot).
static func jamb_transforms(centre: Vector3, outward: Vector3, width: float) -> Array[Transform3D]:
	var along := _along(outward)
	var basis := Basis(along, Vector3.UP, along.cross(Vector3.UP))
	basis = basis.scaled_local(
		Vector3(
			JAMB_WIDTH, JAMB_HEIGHT / InteriorKit.WALL_HEIGHT, JAMB_DEPTH / BuildView.WALL_THICKNESS
		)
	)
	var offset := width * 0.5 + JAMB_WIDTH * 0.5
	var out: Array[Transform3D] = []
	for end in [-1.0, 1.0]:
		var at: Vector3 = centre + along * offset * end
		at.y = FLOOR_Y
		out.append(Transform3D(basis, at))
	return out


## The unit direction along a facade whose outward direction is `outward`.
static func _along(outward: Vector3) -> Vector3:
	if absf(outward.x) > absf(outward.z):
		return Vector3(0.0, 0.0, 1.0)
	return Vector3(1.0, 0.0, 0.0)


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
