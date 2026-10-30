class_name RollerPark
extends RefCounted
## A roller laid on the floor from the pull, and taken off the floor into the
## pull, outside a toilet stall (decision roller-laid-on-the-floor-stand-it-
## up-by-the-bar-park-it-upri, board 5b0fa979). Its grip bar and its carry
## handle are 0.215 m apart even with the rods in, more than twice the probes'
## GRIP_ON reach of either, so the hand changes grip while the bag stands
## parked on its wheels beside the passenger, on the hand's side, and every
## frame a hand holds it, it holds the bar or the handle. Pure: CarryLead.plan()
## hands such a move (stamped "park", stamp()) to plan() here.
##
## pull>floor goes in four parts of TICKS:
## - stand (to STAND_END): the hand on the bar, the rods going in, the bag rolls
##   on its axle to the park and stands up on its wheels;
## - park (to PARK_END): no hand on the bag, which stands still at the park,
##   while the empty hand goes over its top from the bar to the carry handle;
## - lay down (to LAY_END): the hand on the handle, the bag lifted out and laid
##   down ahead (CarryLead.path());
## - let go: the bag on the floor, the hand coming back.
## floor>pull is the same backwards: the hand reaches the lying bag's handle
## (to REACH_END), lifts it to the park (to LIFT_END), lets go while the hand
## goes from the handle over the top to the bar (to UP_PARK_END), and holds the
## bar as the bag tips back on its axle into the pull, its rods running out.
## What it does not guarantee: the hand reaching its target (CarryArm's reach
## is limited; held, the bag is placed from where the grip is), or the park
## being clear of anything beside the passenger (a chair, a neighbour).

## A move that parks the roller takes this many sim ticks (not
## CarryOnProps.TRANSFER_TICKS): four parts, the parked one over 3 ticks, so
## a game at 3x (one tick a frame) draws the bag standing alone on 3 frames.
## Short enough that a walker sitting down still reaches the floor with it
## (at 20 ticks the lay down ended 9 cm short of the floor).
const TICKS := 16.0
## pull>floor: the ends of the stand, the park and the lay down (k).
const STAND_END := 0.35
const PARK_END := 0.55
const LAY_END := 0.8
## floor>pull: the ends of the reach, the lift and the park (k).
const REACH_END := 0.25
const LIFT_END := 0.41
const UP_PARK_END := 0.625
## The park: the axle this far out on the hand's side of the body's centre
## line and this far ahead of it, in the body's frame when the move began:
## under the hand's shoulder, so the hand reaches its bar down beside the hip
## (0.42 m out the hand stopped up to 0.3 m short as the walker sat down).
const PARK_SIDE_M := 0.32
const PARK_AHEAD_M := 0.15
## The empty hand goes from the bar to the handle over the bag's top through
## this point (own frame, scale 1): over the top end and out past the front
## panel (0.2 m), so it comes down onto the handle from outside the shell.
const OVER_TOP := Vector3(0.0, 0.22, 0.33)
## Lifted off the floor to the park, the bag rises this much midway.
const LIFT_M := 0.12


## Whether a hand-led move of `bag` (CarryOnProps' record, its "was",
## "carry_from" and "carry" stamped, going to `home`, a SecurityLooks.Home) is
## a roller's from the pull onto the floor or off the floor into the pull,
## outside a stall (`in_stall`).
static func parks(bag: Dictionary, in_stall: bool, home: int) -> bool:
	if bag["kind"] != SecurityLooks.Kind.ROLLER or in_stall or not bag.get("led", false):
		return false
	var started := CarryLead.start_of(bag)
	if started[0] == CarryLead.End.HELD:
		return bag["carry_from"] == SecurityLooks.Carry.PULL and home == SecurityLooks.Home.FLOOR
	var was: int = bag["was"]
	var off_floor := was >= 0 and was / 4 == SecurityLooks.Home.FLOOR
	return (
		off_floor and home == SecurityLooks.Home.HAND and bag["carry"] == SecurityLooks.Carry.PULL
	)


## Stamps a parking move on `bag` (parks()): "park", its length, and
## "park_frame", the body's frame (`body`, the frame its "from" is in; yaw only)
## the park is placed in; a floor>pull also its reach (CarryLead.reach_of(),
## for CarryLead.at_start()) and its start fixed in the world ("from_world"):
## held in the body's frame the lying bag swung round with a walker turning to
## walk off, 0.7 m in a third of a tick.
static func stamp(bag: Dictionary, body: Transform3D) -> void:
	bag["park"] = true
	bag["ticks"] = TICKS
	if CarryLead.start_of(bag)[0] == CarryLead.End.REST:
		bag["reach"] = REACH_END
		bag["from_world"] = body * (bag["from"] as Transform3D)
	var ahead := body.basis.z
	var yaw := atan2(ahead.x, ahead.z)
	bag["park_frame"] = Transform3D(Basis(Vector3.UP, yaw), body.origin)


## The roller parked (world) for a move led by `hand` (0 right, 1 left), in
## `frame` (stamp()'s), drawn at `scale_by`: standing on its wheels PARK_SIDE_M
## out on the hand's side, its front panel to the back of the body (as it
## stands up from the pull behind, turning about its axle only), upright, its
## axle the wheels' radius up: the wheels (build_carry_on_kit.py, 0.03 m past
## the shell's bottom end) on the floor. Not leaning onto its front panel's
## bottom edge: the probes' rest check reads the lowest corner of the bag's
## mesh bounds, and leaning puts that corner (under the carry handle) through
## the floor by more than its 1 cm.
static func park(frame: Transform3D, hand: int, scale_by: float) -> Transform3D:
	var out := -1.0 if hand == 0 else 1.0
	var axle := frame * Vector3(out * PARK_SIDE_M, 0.0, PARK_AHEAD_M)
	axle.y = frame.origin.y + CarryOnProps.ROLLER_AXLE.y * scale_by
	var front := frame.basis * Vector3.FORWARD
	var basis := Basis(front.cross(Vector3.UP), front, Vector3.UP).scaled(Vector3.ONE * scale_by)
	return Transform3D(basis, axle - basis * CarryOnProps.ROLLER_AXLE)


## How far a parking move of `bag` has run its rods from their old length to
## their new one at `k`: in while it stands up, out while it tips into the pull.
static func rods_t(k: float, bag: Dictionary) -> float:
	if CarryLead.start_of(bag)[0] == CarryLead.End.REST:
		return smoothstep(UP_PARK_END, 1.0, k)
	return smoothstep(0.0, STAND_END, k)


## 0 to 1 over `t` (0 to 1), still at both ends (smootherstep): a stand that
## eased out with smoothstep still moved 0.19 m on the last tick before the park.
static func _eased(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


## The roller turning on its axle from `from` to `to` (world, both on their
## wheels) at `u`: its axle rolls straight across the floor between theirs.
static func rolled(from: Transform3D, to: Transform3D, u: float) -> Transform3D:
	var axle := (from * CarryOnProps.ROLLER_AXLE).lerp(to * CarryOnProps.ROLLER_AXLE, u)
	var q := from.basis.get_rotation_quaternion().slerp(to.basis.get_rotation_quaternion(), u)
	var basis := Basis(q).scaled(from.basis.get_scale().lerp(to.basis.get_scale(), u))
	return Transform3D(basis, axle - basis * CarryOnProps.ROLLER_AXLE)


## The empty hand's point (own frame) at `v` of its way from `from` (the bar or
## the handle) to `to` over the bag's top (OVER_TOP).
static func over_top(from: Vector3, to: Vector3, v: float) -> Vector3:
	return from.lerp(OVER_TOP, v).lerp(OVER_TOP.lerp(to, v), v)


## A parking move of `bag` at `k`, as CarryLead.plan() returns it (same
## arguments; `body` gives "bar_z", the bar as the rods are drawn now, and
## "scale").
static func plan(
	bag: Dictionary,
	k: float,
	start: Transform3D,
	want: Transform3D,
	frame: Transform3D,
	flags: Dictionary,
	body: Dictionary
) -> Dictionary:
	var started := CarryLead.start_of(bag)
	var off_floor: bool = started[0] == CarryLead.End.REST
	var lead: int = CarryLead.hand_of(bag["home"]) if off_floor else started[1]
	var parked := park(bag["park_frame"], lead, body["scale"])
	var bar := Vector3(0.0, CarryOnProps.ROLLER_AXLE.y, body["bar_z"])
	var handle := CarryOnProps.ROLLER_HANDLE
	var go := flags.duplicate()
	go["hand"] = lead
	# [holder (-1 none), the bag, the point held, the hand's target (own frame of
	# the bag), the hand's weight]. The stoop is kept on through
	# the whole move (CarryStoop bends only as far as the reach needs): with the
	# height fade alone the hand reaching the bar 0.6 m up beside a walker sitting
	# down stopped 0.3 m short, the bag rising off its wheels with it.
	var at: Array
	if not off_floor:
		at = _onto_floor(k, start, want, parked, frame, go, bar, handle)
	else:
		at = _off_floor(k, start, want, parked, frame, go, bar, handle)
	var xf: Transform3D = at[1]
	var targets := [Vector3.ZERO, Vector3.ZERO]
	var weights := [0.0, 0.0]
	var keeps := [0.0, 0.0]
	targets[lead] = xf * (at[3] as Vector3)
	weights[lead] = at[4]
	keeps[lead] = 1.0
	return {
		"holder": lead if at[0] else -1,
		"xf": xf,
		"anchor": at[2],
		"targets": targets,
		"weights": weights,
		"keeps": keeps,
		"drops": [CarryStoop.HIPS_ALL, CarryStoop.HIPS_ALL],
	}


## pull>floor at `k` (plan()): [held, xf, anchor, target, weight].
static func _onto_floor(
	k: float,
	start: Transform3D,
	want: Transform3D,
	parked: Transform3D,
	frame: Transform3D,
	go: Dictionary,
	bar: Vector3,
	handle: Vector3
) -> Array:
	if k < STAND_END:
		var u := _eased(k / STAND_END)
		# Aimed at the bar from the start, where the pull put it: eased in from the
		# pull's arm pose, the bag placed from the hand rose off its wheels with it.
		return [true, rolled(start, parked, u), bar, bar, 1.0]
	if k < PARK_END:
		var v := smoothstep(0.0, 1.0, (k - STAND_END) / (PARK_END - STAND_END))
		return [false, parked, handle, over_top(bar, handle, v), 1.0]
	if k <= LAY_END:
		# Still at both ends: path()'s set-down comes down fastest at its end, and
		# the bag reached the floor 8 cm a third of a tick.
		var t := _eased((k - PARK_END) / (LAY_END - PARK_END))
		var laid := CarryLead.path(parked, want, t, frame, frame.affine_inverse() * parked, go)
		return [true, laid, handle, handle, 1.0]
	var back := smoothstep(0.0, 1.0, (1.0 - k) / (1.0 - LAY_END))
	return [false, want, handle, handle, back]


## floor>pull at `k` (plan()): [held, xf, anchor, target, weight].
static func _off_floor(
	k: float,
	start: Transform3D,
	want: Transform3D,
	parked: Transform3D,
	_frame: Transform3D,
	_go: Dictionary,
	bar: Vector3,
	handle: Vector3
) -> Array:
	if k < REACH_END:
		return [false, start, handle, handle, smoothstep(0.0, 1.0, k / REACH_END)]
	if k < LIFT_END:
		var t := (k - REACH_END) / (LIFT_END - REACH_END)
		var lifted := start.interpolate_with(parked, smoothstep(0.0, 1.0, t))
		lifted.origin.y += LIFT_M * 4.0 * t * (1.0 - t)
		return [true, lifted, handle, handle, 1.0]
	if k < UP_PARK_END:
		var v := smoothstep(0.0, 1.0, (k - LIFT_END) / (UP_PARK_END - LIFT_END))
		return [false, parked, bar, over_top(handle, bar, v), 1.0]
	var u := smoothstep(0.0, 1.0, (k - UP_PARK_END) / (1.0 - UP_PARK_END))
	# Into the pull's arm pose as the bag comes onto the trail.
	return [true, rolled(parked, want, u), bar, bar, 1.0 - smoothstep(0.3, 1.0, u)]
