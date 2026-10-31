class_name RollerPark
extends RefCounted
## A roller laid on the floor from the pull, and taken off the floor into the
## pull, outside a toilet stall (decision roller-laid-on-the-floor-stand-it-
## up-by-the-bar-park-it-upri, board 5b0fa979). Its grip bar and its carry
## handle are 0.215 m apart even with the rods in, more than twice the probes'
## GRIP_ON reach of either, so the hand changes grip while the bag stands
## parked on its wheels beside the passenger, on the hand's side, and every
## frame a hand holds it, it holds the bar or the handle. CarryLead.plan()
## hands such a move (stamped "park", stamp()) to plan() here, which writes
## nothing but the moment the hand took a lying bag ("park_took", _taken()).
##
## pull>floor goes in four parts of TICKS_DOWN:
## - stand (to STAND_END): the hand on the bar, the rods going in, the bag rolls
##   on its axle to the park and stands up on its wheels;
## - park (to PARK_END): no hand on the bag, which stands still at the park,
##   while the empty hand goes over its top from the bar to the carry handle;
## - lay down (to LAY_END): the hand on the handle, the bag lifted out and laid
##   down ahead (CarryLead.path());
## - let go: the bag on the floor, the hand coming back.
## floor>pull (TICKS_UP) is the same backwards: the hand reaches the lying
## bag's handle (taking it from REACH_END, once there), lifts it to the park,
## lets go while the hand goes from the handle over the top to the bar
## (up_ends()), and holds the bar as the bag tips back on its axle into the
## pull, its rods running out.
## What it does not guarantee: the hand reaching its target (CarryArm's reach
## is limited; held, the bag is placed from where the grip is), or the park
## being clear of anything beside the passenger (a chair, a neighbour).

## A move that parks the roller takes this many sim ticks (not
## CarryOnProps.TRANSFER_TICKS), the parked part 3 ticks or more, so a game at
## 3x (one tick a frame) draws the bag standing alone on 3 frames.
const TICKS_DOWN := 13.0
const TICKS_UP := 16.0
## pull>floor: the ends of the stand, the park and the lay down (k).
const STAND_END := 0.37
const PARK_END := 0.6
const LAY_END := 0.83
## floor>pull: the ends of the reach, the lift and the park (k), and how many
## ticks before the stand-up ends it starts (SecurityLooks): the hand takes
## the lying bag about 20 ticks into the stand-up (the body comes 0.4 m forward
## over its last 7 ticks, and only then is the bag in reach), and the park ends
## 3 to 4 ticks into the walk off, beside the walker's way (UP_PARK_AHEAD_M).
const REACH_END := 0.25
const TAKE_BY := 0.4
const LIFT_END := 0.55
const UP_PARK_END := 0.74
const UP_LEAD_TICKS := 9
## The park: the axle this far out on the hand's side of the body's centre
## line and this far ahead of it, in the body's frame when the move began:
## under the hand's shoulder, so the hand reaches its bar down beside the hip
## (0.42 m out the hand stopped up to 0.3 m short as the walker sat down).
## Taken off the floor it parks further ahead (UP_PARK_AHEAD_M), where the
## walker comes past it stepping off: parked 0.45 m ahead, the walker had gone
## on and the hand was 0.16 m off the bar at 3x as it took it again.
const PARK_SIDE_M := 0.32
const PARK_AHEAD_M := 0.15
const UP_PARK_AHEAD_M := 0.7
## Laying it down and letting go, the stoop bends the back first and the hips
## go down only as far as that leaves the hand short, not back (CarryStoop.
## drops): with the hips going back as well, the hand of a walker sitting down
## stopped 6 to 9 cm over the handle on the floor ahead, and the bag let go
## dropped that far.
const LAY_HIPS := Vector3(1.0, 0.0, 1.0)
## The empty hand goes from the bar to the handle over the bag's top through
## this point (own frame, scale 1): over the top end and out past the front
## panel (0.2 m), so it comes down onto the handle from outside the shell.
const OVER_TOP := Vector3(0.0, 0.22, 0.33)
## Off the floor the hand takes the lying bag once its grip is this close to
## the handle (body["grips"]), from REACH_END on, and at TAKE_BY whatever: the
## bag waits on the floor until then. The lift then runs to LIFT_END, or for
## UP_PART of the move when it was taken late, and the park for UP_PART more
## (up_ends()): taken late at 3x, a lift squeezed into 1.8 ticks drew the hand
## 0.24 m from one frame to the next.
## Taken at REACH_END on the clock, a walker still standing up had its hand
## 0.18-0.29 m short, and the bag jumped that far into it.
const TAKE_M := 0.05
const UP_PART := 0.19
## Lifted off the floor to the park, the bag rises this much midway.
const LIFT_M := 0.12
## Off the floor, the walker moving this far from where it stood as the park
## began ends the park early: the empty hand goes the rest of its way over the
## top to the bar in UP_CUT_TICKS (up_ends()), there by CUT_ON of it (the last
## frame alone must not leave the hand short of the bar). Held again by the bar, the bag
## tips into the pull in the body's frame (_followed()), never left standing in
## the world as the walker goes: a late walker runs off, and its hand was 0.31
## m from one frame to the next at 1x, 1.0 m at 3x, reaching back for it. Left
## by the hand, the bag stands still in the world, never sliding on the floor
## (conductor ruling 2026-10-31 on board 5b0fa979).
const MOVED_M := 0.01
const UP_CUT_TICKS := 2.0
const CUT_ON := 0.7
## Taken again by the bar, the bag goes with the body from this share of the
## way from the last frame it stood alone to now (_followed()): the hand on the
## bar moves that share of the walker's step against the body, the bag the rest
## in the world, on top of what the hand was short of the bar.
const FOLLOW_SPLIT := 0.7


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


## Whether the lift of `bag` (CarryOnProps' record, a roller, of a bag of
## `kind` now, going to `home`) is held as it is at `now` (sim tick). A walker
## turning late lifts its roller into the hand (CarryOnProps._lifted); stamped
## as a new move in the middle of a park, that move started held in the hand by
## the bar, not the carry handle the hand had or the park it stood at, and the
## bag jumped up to 0.215 m. So a parking move keeps its lift to its end (let go
## at the bar regrasp, floor>pull, the swap into the hand started from the pull's
## pose behind, not the park, and the bag jumped 0.2 m). A
## roller staying on the floor keeps it too: lying there it is carried no way
## (CarryOnProps' floor spot), and a new lift was a pick-up and set-down on the
## spot, the hand 0.36 m from one frame to the next.
static func holds_lift(bag: Dictionary, kind: SecurityLooks.Kind, home: int, now: float) -> bool:
	if kind != SecurityLooks.Kind.ROLLER or bag.get("kind", -1) != kind:
		return false
	var place: int = bag.get("place", -2)
	if home == SecurityLooks.Home.FLOOR and place >= 0 and place / 4 == home:
		return true
	if not bag.get("park", false):
		return false
	return now - float(bag.get("since", INF)) < CarryLead.ticks_of(bag)


## Stamps a parking move on `bag` (parks()): "park", its length, and
## "park_frame", the body's frame (`body`, the frame its "from" is in; yaw only)
## the park is placed in; a floor>pull also its reach (CarryLead.reach_of(),
## for CarryLead.at_start()) and its start fixed in the world ("from_world"):
## held in the body's frame the lying bag swung round with a walker turning to
## walk off, 0.7 m in a third of a tick.
static func stamp(bag: Dictionary, body: Transform3D) -> void:
	bag["park"] = true
	bag["ticks"] = TICKS_DOWN
	for key in [
		"park_took", "park_at", "park_cut", "park_last", "park_rel", "lift_last", "park_tip"
	]:
		bag.erase(key)
	if CarryLead.start_of(bag)[0] == CarryLead.End.REST:
		bag["ticks"] = TICKS_UP
		bag["reach"] = REACH_END
		bag["from_world"] = body * (bag["from"] as Transform3D)
	bag["park_frame"] = _yawed(body)


## `frame` turned about the vertical only (its yaw), at its origin.
static func _yawed(frame: Transform3D) -> Transform3D:
	var ahead := frame.basis.z
	return Transform3D(Basis(Vector3.UP, atan2(ahead.x, ahead.z)), frame.origin)


## The roller parked (world) for a move led by `hand` (0 right, 1 left), in
## `frame` (stamp()'s), drawn at `scale_by`: standing on its wheels PARK_SIDE_M
## out on the hand's side and `ahead`, its front panel to the back of the body (as it
## stands up from the pull behind, turning about its axle only), upright, its
## axle the wheels' radius up: the wheels (build_carry_on_kit.py, 0.03 m past
## the shell's bottom end) on the floor. Not leaning onto its front panel's
## bottom edge: the probes' rest check reads the lowest corner of the bag's
## mesh bounds, and leaning puts that corner (under the carry handle) through
## the floor by more than its 1 cm.
static func park(
	frame: Transform3D, hand: int, scale_by: float, ahead := PARK_AHEAD_M
) -> Transform3D:
	var out := -1.0 if hand == 0 else 1.0
	var axle := frame * Vector3(out * PARK_SIDE_M, 0.0, ahead)
	axle.y = frame.origin.y + CarryOnProps.ROLLER_AXLE.y * scale_by
	var front := frame.basis * Vector3.FORWARD
	var basis := Basis(front.cross(Vector3.UP), front, Vector3.UP).scaled(Vector3.ONE * scale_by)
	return Transform3D(basis, axle - basis * CarryOnProps.ROLLER_AXLE)


## How far a parking move of `bag` has run its rods from their old length to
## their new one at `k`: in while it stands up, out while it tips into the pull.
static func rods_t(k: float, bag: Dictionary) -> float:
	if CarryLead.start_of(bag)[0] == CarryLead.End.REST:
		return smoothstep(up_ends(bag).y, 1.0, k)
	return smoothstep(0.0, STAND_END, k)


## 0 to 1 over `t` (0 to 1), still at both ends (smootherstep): a stand that
## eased out with smoothstep still moved 0.19 m on the last tick before the park.
static func _eased(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


## Where the lift and the park of a floor>pull move of `bag` end (k): LIFT_END
## and UP_PARK_END, later when its bag was taken late ("park_took", _taken()),
## the park sooner when the walker moved during it ("park_cut", MOVED_M).
static func up_ends(bag: Dictionary) -> Vector2:
	var lift := maxf(LIFT_END, float(bag.get("park_took", 0.0)) + UP_PART)
	var park := maxf(UP_PARK_END, lift + UP_PART)
	if bag.has("park_cut"):
		park = minf(park, (bag["park_cut"] as Vector2).x + UP_CUT_TICKS / TICKS_UP)
	return Vector2(lift, park)


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
	var ahead := UP_PARK_AHEAD_M if off_floor else PARK_AHEAD_M
	var parked := park(bag["park_frame"], lead, body["scale"], ahead)
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
		_taken(bag, k, start * handle, body, lead)
		at = _off_floor(k, bag, start, want, parked, _yawed(frame), bar, handle)
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
		"drops":
		(
			[LAY_HIPS, LAY_HIPS]
			if not off_floor and k >= PARK_END
			else [CarryStoop.HIPS_ALL, CarryStoop.HIPS_ALL]
		),
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


## The k a floor>pull move of `bag` took the lying bag at (TAKE_M, TAKE_BY), the
## hand `lead` of `body` (plan()'s) and the handle at `at` (world) as drawn now;
## -1 while it has not. Kept on the move's record ("park_took"): the hand
## reaching it is a pose, not a time.
static func _taken(bag: Dictionary, k: float, at: Vector3, body: Dictionary, lead: int) -> float:
	if bag.has("park_took"):
		return bag["park_took"]
	var grip: Vector3 = body["grips"][lead]
	if k >= TAKE_BY or (k >= REACH_END and grip.distance_to(at) <= TAKE_M):
		bag["park_took"] = k
		return k
	return -1.0


## floor>pull of `bag` at `k` (plan()), the bag taken off the floor at its
## "park_took" (_taken()), the body at `body` (yaw only): [held, xf, anchor,
## target, weight].
static func _off_floor(
	k: float,
	bag: Dictionary,
	start: Transform3D,
	want: Transform3D,
	parked: Transform3D,
	body: Transform3D,
	bar: Vector3,
	handle: Vector3
) -> Array:
	var took: float = bag.get("park_took", -1.0)
	if took < 0.0 or k < took:
		return [false, start, handle, handle, smoothstep(0.0, 1.0, k / REACH_END)]
	var ends := up_ends(bag)
	if k < ends.x:
		var t := (k - took) / (ends.x - took)
		var lifted := start.interpolate_with(parked, _eased(t))
		lifted.origin.y += LIFT_M * 4.0 * t * (1.0 - t)
		bag["lift_last"] = body
		return [true, lifted, handle, handle, 1.0]
	if k < ends.y:
		var v := smoothstep(0.0, 1.0, (k - ends.x) / (ends.y - ends.x))
		if not bag.has("park_at"):
			bag["park_at"] = body.origin
		if not bag.has("park_cut") and body.origin.distance_to(bag["park_at"]) > MOVED_M:
			bag["park_cut"] = Vector2(k, v)
		if bag.has("park_cut"):
			var cut: Vector2 = bag["park_cut"]
			ends = up_ends(bag)
			v = lerpf(cut.y, 1.0, smoothstep(cut.x, lerpf(cut.x, ends.y, CUT_ON), k))
		if k < ends.y:
			bag["park_last"] = body
			# The empty hand let go goes on with the walker by half its last step,
			# less as it comes to the bar: a hand still in the world as a walker
			# running on lets go moved 0.175 m against the body at 3x.
			var last: Transform3D = bag.get("lift_last", body)
			var hand := parked * over_top(handle, bar, v)
			hand += (body.origin - last.origin) * 0.5 * (1.0 - v)
			return [false, parked, bar, parked.affine_inverse() * hand, 1.0]
	var tipped := _followed(bag, parked, body, k)
	var from: float = bag.get("park_tip", ends.y)
	var u := smoothstep(0.0, 1.0, (k - from) / (1.0 - from))
	# Into the pull's arm pose as the bag comes onto the trail, from the frame
	# the hand took it ("park_tip"; between two frames at 3x it had rolled
	# 0.2 m toward the trail by the first).
	tipped = rolled(tipped, want, u)
	return [true, tipped, bar, bar, 1.0 - smoothstep(0.0, 1.0, u)]


## The parked bag `parked` (world) carried with the body at `body` (yaw only)
## from where the hand took it again at `k` ("park_tip"): kept on `bag`
## ("park_rel") in the body's frame FOLLOW_SPLIT of the way from the last frame
## it stood alone ("park_last") to now, so a walker going on moves the hand on
## the bar and the bag each part of its step across that frame, not one of them
## all of it (0.058 m a third of a tick for a walker running off, more than the
## 5 cm a change of grip may move; split in halves, the hand short of the bar
## by 2.6 cm put the bag 5.5 cm on).
static func _followed(
	bag: Dictionary, parked: Transform3D, body: Transform3D, k: float
) -> Transform3D:
	if not bag.has("park_rel"):
		var last: Transform3D = bag.get("park_last", body)
		var now := body.affine_inverse() * parked
		bag["park_rel"] = (last.affine_inverse() * parked).interpolate_with(now, FOLLOW_SPLIT)
		bag["park_tip"] = k
	return body * (bag["park_rel"] as Transform3D)
