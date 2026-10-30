class_name CarryLead
extends RefCounted
## Hand-led carry-on moves (decision carry-on-bags-stay-in-the-hand-during-
## every-move-no-overhead; rebuilt narrowly from main, decision floating-bag-
## fix-rebuilt-narrower-from-main-hand-led-moves-only-where-bags-float). Pure:
## CarryOnProps asks it how a move of a bag between two homes goes at `k` (0
## to 1) of the move.
##
## An end of a move is HELD when a hand holds the bag there (a bag carried in
## the hand, a roller pulled by its bar), WORN (on the back or the shoulder)
## or REST (on the floor, in a tray). A move goes in up to three parts:
## - reach: from a WORN or REST start the bag stays where it is while the
##   leading hand goes to it (REACH_SHARE of the move);
## - carry: the bag is placed from the leading hand's grip, along the path
##   (path()), while the hand is aimed at the path's grip point;
## - let go: at a WORN or REST end the bag is where it ends while the hand
##   goes back (REACH_SHARE of the move).
## A move from one hand to the other is carried by the old hand to half way,
## where the new hand has come to it, and by the new hand after.
## What it does not guarantee: the hand reaching its target (CarryArm's reach
## and CarryStoop's bend are limited; the bag is placed from where the grip is,
## so a short reach shortens the path, it never leaves the bag in the air).

enum End { HELD, WORN, REST }

## The share of a move the hand takes to reach a bag that is not in a hand at
## the start, and to come back from one it leaves.
const REACH_SHARE := 0.25
## A backpack goes on and off the back through a hang at the leading hand's
## side, at shoulder height, this far out from the centre line, over this
## share of the carry.
const BACK_SIDE_M := 0.42
const BACK_SHARE := 0.4
## A backpack in a hand-led move is held this far from its grab loop (its own
## frame, the loop mid-depth at y 0.082, the bag 0 to 0.177 deep, its top face
## at z 0.21 and the loop's top at 0.235): past the face hung toward the body
## and over the top (a grip offset), so less of the fingers, which curl 3 to 12
## cm down and 7 to 13 cm back from the grip (measured, board item 5ed915b0),
## reach into the top. No further: the probes' FLOAT check needs the grip within
## 6 cm of the bag's bounds (z 0.295, y 0.237).
const LOOP_OFFSET := Vector3(0.0, 0.15, 0.05)
## Off the floor a bag turns to hang from the hand over this share of its
## carry (off a tray, 0.35: the table is under it).
const UPRIGHT_FROM_FLOOR := 0.2
## Lifting a bag off the floor the stoop is kept on (CarryStoop.keeps) to this
## share of the carry and gone KEEP_FADE later, so the hand reaches the bag's
## path ahead of the knees, not short of it in front of the thighs; setting
## one down, from as far before the end.
const KEEP_T := 0.35
const KEEP_FADE := 0.25
## How high a bag set down on the floor rises midway: the full TRANSFER_LIFT_M
## put the case top against the face of a body stooping to set it down, and
## none put the hand low beside the case's top corner, palm out, not on it.
const SET_DOWN_LIFT_M := 0.15
## Setting a bag down in a toilet stall the back bends first and the hips go
## down (and back) only as far as the bent back leaves the hand short
## (CarryStoop.drops): the hips dropping with every stoop brought the knees
## forward into the bag by the door, the back alone left the hand up to 0.45 m
## short of it (board item c7b0e7be).
const STALL_HIPS := Vector3(1.0, 1.0, 1.0)
## Set down from the hand in a toilet stall, the hand comes back from the bag
## over this last share of the move (not REACH_SHARE): the body shuffles back
## to the seat as it sits (0.4 m over 12 ticks), and a bag let go at the usual
## k 0.75 was out of the hand's reach by then.
const STALL_LET_GO := 0.55
## A bag picked up from a stall's floor goes out this far to its hand's side
## midway (the walker steps out past it).
const STALL_PICK_SIDE_M := 0.12
## A bag picked up in a stall rises toward its carry with the hand no lower than
## this over the feet (the front carry holds it about 1.2 m up).
const STALL_CARRY_GRIP_M := 1.0
## A tote set down in a toilet stall rises this much midway, over the thighs.
const STALL_TOTE_LIFT_M := 0.25
## And it is held this far short of its place by the door until it goes down.
const STALL_TOTE_BACK_M := 0.05
## A backpack set down in a stall is held this far over its grab loop (its own
## frame), the fingers over the top, not in it.
const STALL_LOOP_UP := Vector3(0.0, 0.0, 0.06)


## Where a bag of `kind` standing in a stall is held to set it down: its top
## (`loose` its kind's grip point: a case's top edge, a roller's bar), a
## backpack STALL_LOOP_UP over its grab loop.
static func stall_top(kind: SecurityLooks.Kind, loose: Vector3) -> Vector3:
	if kind == SecurityLooks.Kind.BACKPACK:
		return CarryOnProps.BACKPACK_LOOP + STALL_LOOP_UP
	return loose


## The kind of end a bag's place (`place`, CarryOnProps' (home * 2 + hand) * 2
## + lifted, or -1) carried `carry` is.
static func end_of(place: int, carry: SecurityLooks.Carry) -> End:
	if place < 0 or place / 4 != SecurityLooks.Home.HAND:
		return End.REST
	if carry in [SecurityLooks.Carry.HAND, SecurityLooks.Carry.PULL]:
		return End.HELD
	return End.WORN


## The start of a move of `bag` (CarryOnProps' record): [its End, its hand].
## A move that starts while the last one was still in a hand
## ("from_holder") starts HELD in that hand, wherever the bag was going.
static func start_of(bag: Dictionary) -> Array:
	var holder: int = bag.get("from_holder", -1)
	if holder >= 0:
		return [End.HELD, holder]
	return [end_of(bag["was"], bag["carry_from"]), hand_of(bag["was"])]


## Whether a hand-led move of `bag` (CarryOnProps' record, "led") drawn last
## at `k` has not left its start: the hand was still reaching for the bag (a
## move that starts HELD leaves at once). A move that interrupts it starts
## where the bag is, at that start (CarryOnProps._stamp).
static func at_start(bag: Dictionary, k: float) -> bool:
	return bag.get("led", false) and k < span(start_of(bag)[0], End.HELD).x


## The hand of a place (0 right, 1 left).
static func hand_of(place: int) -> int:
	return (maxi(place, 0) / 2) % 2


## The hand that leads a move: the one it ends in, else the one it starts in,
## else `fallback` (the bag's own hand or side).
static func lead_hand(from: End, to: End, from_hand: int, to_hand: int, fallback: int) -> int:
	if to == End.HELD:
		return to_hand
	if from == End.HELD:
		return from_hand
	return fallback


## The part of the move (`x` the start, `y` the end of k) the bag is carried;
## the hand comes back from a bag it leaves over the last `let_go` of it.
static func span(from: End, to: End, let_go := REACH_SHARE) -> Vector2:
	return Vector2(
		0.0 if from == End.HELD else REACH_SHARE, 1.0 if to == End.HELD else 1.0 - let_go
	)


## How far along the carry a move of `bag` (CarryOnProps' record) is at `k`,
## 0 to 1 (0 while it waits at its start, 1 once it is at its end).
static func carry_t(k: float, bag: Dictionary) -> float:
	var s := span(start_of(bag)[0], end_of(bag["home"], bag["carry"]))
	return clampf((k - s.x) / maxf(s.y - s.x, 0.0001), 0.0, 1.0)


## The move at `k`: {"t": how far along the carry (below 0 before it, above 1
## after it), "holder": the hand the bag is placed from (-1 while it rests or
## is worn at an end), "weights": [right, left] how far each hand is aimed at
## its target (CarryArm.reach_weight), "targets_at": [right, left] the carry
## progress each hand aims at (-1 the start, 2 the end)}. `let_go` as for
## span().
static func phase(
	k: float, from: End, to: End, from_hand: int, lead: int, let_go := REACH_SHARE
) -> Dictionary:
	var s := span(from, to, let_go)
	var t := (k - s.x) / maxf(s.y - s.x, 0.0001)
	var weights := [0.0, 0.0]
	var aims := [0.0, 0.0]
	var holder := lead
	var lead_w := 1.0
	if k < s.x:
		holder = -1
		lead_w = smoothstep(0.0, 1.0, k / s.x)
		aims[lead] = -1.0
	elif k > s.y:
		holder = -1
		lead_w = smoothstep(0.0, 1.0, (1.0 - k) / (1.0 - s.y))
		aims[lead] = 2.0
	else:
		aims[lead] = t
		var swap := from == End.HELD and from_hand != lead
		if from == End.HELD:
			# From the carry pose of the hand it starts in (or the new hand
			# coming to it, by half way).
			lead_w = smoothstep(0.0, 0.5 if swap else 0.4, t)
		if to == End.HELD:
			# Into the carry pose of the hand it ends in.
			lead_w *= 1.0 - smoothstep(0.6, 1.0, t)
		if swap:
			var old := 1 - lead
			weights[old] = 1.0 - smoothstep(0.5, 1.0, t)
			aims[old] = t
			if t < 0.5:
				holder = old
	weights[lead] = lead_w
	return {"t": clampf(t, 0.0, 1.0), "holder": holder, "weights": weights, "targets_at": aims}


## How far (0 to 1) the leading hand's stoop is kept on (CarryStoop.keeps) at
## `k` of a move from `from` to `to`: lifting a bag off the floor
## (`from_floor`), through the reach and the carry to KEEP_T, gone by KEEP_T +
## KEEP_FADE; setting one down on it (`to_floor`), the same from the end back.
static func floor_keep(k: float, from: End, to: End, from_floor: bool, to_floor: bool) -> float:
	var s := span(from, to)
	var t := (k - s.x) / maxf(s.y - s.x, 0.0001)
	var keep := 0.0
	if from == End.REST and from_floor:
		keep = 1.0 - smoothstep(KEEP_T, KEEP_T + KEEP_FADE, t)
	if to == End.REST and to_floor:
		keep = maxf(keep, smoothstep(1.0 - KEEP_T - KEEP_FADE, 1.0 - KEEP_T, t))
	return keep


## The grip point (in the bag's own frame) of a bag of `kind` that is not in
## a hand: a hard case's top edge, a backpack's grab loop, a shoulder bag's
## top edge; a roller's grip bar at `bar_z` along it.
static func anchor(kind: SecurityLooks.Kind, bar_z: float) -> Vector3:
	if kind == SecurityLooks.Kind.ROLLER:
		return Vector3(0.0, CarryOnProps.ROLLER_AXLE.y, bar_z)
	if kind == SecurityLooks.Kind.BACKPACK:
		# Held by the loop, the fingers outside the bag's face (LOOP_OFFSET).
		return CarryOnProps.BACKPACK_LOOP + LOOP_OFFSET
	return CarryOnProps.grip_anchor(kind)


## A backpack hanging from the leading hand (`hand` 0 right, 1 left) by its
## grab loop at the side, at `height` (world), of a body drawn at `frame`.
static func back_side(
	centre: Vector3, yaw: float, hand: int, height: float, scale_by: float
) -> Transform3D:
	var out := Vector3.LEFT if hand == 0 else Vector3.RIGHT
	var grip := centre + Basis(Vector3.UP, yaw) * (out * BACK_SIDE_M)
	grip.y = height
	return CarryOnProps.carried(grip, centre, yaw, scale_by, SecurityLooks.Kind.BACKPACK)


## The leading hand's target `at` at `k` of a move of a backpack on or off the
## back (`from` to `to`), body drawn at `frame` turned to `yaw`, `lead` the
## hand, `body` as for plan(): while the hand reaches for the pack on the back
## it comes by the side hang (BACK_SIDE_M out, under the shoulder) and only then
## to the loop, and letting go of it there it goes back out by the side, so
## the arm's blend to and from its own pose does not pass the hand through the
## pack (measured: fingers and the hand inside it, board item 5ed915b0).
static func by_side(
	at: Vector3,
	k: float,
	from: End,
	to: End,
	frame: Transform3D,
	yaw: float,
	lead: int,
	body: Dictionary
) -> Vector3:
	var out := Vector3.LEFT if lead == 0 else Vector3.RIGHT
	var side := frame.origin + Basis(Vector3.UP, yaw) * (out * BACK_SIDE_M)
	side.y = body["shoulders_y"][lead] - 0.1
	var s := span(from, to)
	if from == End.WORN and k < s.x:
		return side.lerp(at, smoothstep(0.3, 1.0, k / s.x))
	if to == End.WORN and k > s.y:
		return at.lerp(side, smoothstep(0.0, 0.35, (k - s.y) / (1.0 - s.y)))
	return at


## Where a roller's axle is at `t` (0 under the hand at `hung`, 1 at
## `trailing`, both world) of a swap between the hand and the pull at
## security, the body drawn at `frame`, `hand` 0 right: round the hand's side
## of the body (its angle about the body's centre turns from the one to the
## other through the hand's side, as CarryOnProps.follow() swings a pulled
## roller), at least `clear` from the centre midway, so it passes outside the
## legs. A straight blend with a 0.2 m swing out took it behind the shins of a
## walker standing at a lane (board item 5ed915b0).
static func swap_axle(
	frame: Transform3D, hung: Vector3, trailing: Vector3, t: float, hand: int, clear: float
) -> Vector3:
	var a := frame.affine_inverse() * hung
	var b := frame.affine_inverse() * trailing
	var out := -1.0 if hand == 0 else 1.0
	# Angle from straight behind (0) toward the hand's side (PI / 2).
	var a0 := atan2(a.x * out, -a.z)
	var a1 := atan2(b.x * out, -b.z)
	if a1 < -PI / 2.0:
		a1 += TAU
	var angle := lerpf(a0, a1, t)
	var r := lerpf(Vector2(a.x, a.z).length(), Vector2(b.x, b.z).length(), t)
	r = maxf(r, clear * 4.0 * t * (1.0 - t))
	return frame * Vector3(out * r * sin(angle), lerpf(a.y, b.y, t), -r * cos(angle))


## How a hand-led move of `bag` (CarryOnProps' record) goes at `k`, from
## `start` (world now) to `want`, its body drawn at `frame`; `flags` as for
## path(), `body` the body as drawn now: {"hand": the bag's own hand or side,
## "grips": [right, left] grip points (CarryOnProps.grip_of), "shoulders_y":
## [right, left] shoulder joint heights, "bar_z": a roller's grip bar along it,
## "scale": the bag's scale}. Returns {"holder", "xf" (the bag at a resting or
## worn end, or on its path), "anchor" (the point of the bag in the holder's
## grip, its own frame), "targets", "weights", "keeps", "drops" (each hand's,
## right then left; keeps floor_keep(), flags "from_floor" and "to_floor";
## drops CarryStoop.drops)}.
## A backpack goes on and off the back through a hang at the leading hand's
## side (back_side()).
static func plan(
	bag: Dictionary,
	k: float,
	start: Transform3D,
	want: Transform3D,
	frame: Transform3D,
	flags: Dictionary,
	body: Dictionary
) -> Dictionary:
	var started := start_of(bag)
	var from_end: End = started[0]
	var to_end := end_of(bag["home"], bag["carry"])
	var from_hand: int = started[1]
	var to_hand := hand_of(bag["home"])
	var lead := lead_hand(from_end, to_end, from_hand, to_hand, body["hand"])
	var stall: bool = flags.get("in_stall", false)
	var set_down := from_end == End.HELD and to_end == End.REST
	# Set down from the hand in a toilet stall it is down and let go early
	# (STALL_LET_GO): the body shuffles back to the seat as it sits.
	var let_go := STALL_LET_GO if stall and set_down else REACH_SHARE
	var ph := phase(k, from_end, to_end, from_hand, lead, let_go)
	var t: float = ph["t"]
	if stall and set_down and k <= span(from_end, to_end, let_go).y:
		# And the hand is on the bag's path at once: the body turns round to sit
		# in one frame, and the bag eased out of the carry pose went through the
		# door ahead (StallCarry.set_down_start).
		ph["weights"][lead] = 1.0
	var loose := anchor(bag["kind"], body["bar_z"])
	if bag["kind"] == SecurityLooks.Kind.SHOULDER:
		# A shoulder bag is lifted on and off the shoulder by its strap's top.
		loose = body["strap_top"]
	# A roller is held by its bar, which moves with its rods (in a stall they
	# stay in, so it is held where the hand had it, BAR_PALM_M off the bar).
	var roller: bool = bag["kind"] == SecurityLooks.Kind.ROLLER
	var anchor_from: Vector3 = loose
	if from_end == End.HELD and (not roller or flags.get("in_stall", false)):
		anchor_from = bag["anchor_from"]
	# Lying in a tray or on the floor a roller is taken (and left) by its carry
	# handle on top, not by its bar down at the rod line (the forearm went
	# through it, board item 5ed915b0); the hand slides to the bar as it lifts.
	# Standing on its wheels in a toilet stall its bar is on top, and it is held
	# by the bar throughout (decision stall-bag-poses-as-built-bags-stand-
	# upright-against-the-insi).
	var by_handle: bool = roller and not flags.get("in_stall", false)
	if by_handle and from_end == End.REST:
		anchor_from = CarryOnProps.ROLLER_HANDLE
	var anchor_to := loose
	if to_end == End.HELD:
		anchor_to = want.affine_inverse() * (body["grips"][to_hand] as Vector3)
		if roller:
			# Along the rods, on the bar as the rods are drawn now (they run out
			# or in through the move), not where the end's rods put it: blending
			# the two lengths again took the bar up to 8 cm off the hand passing
			# a pulled roller between hands (crossing probe FLOAT, pull.R>pull.L).
			anchor_to.z = loose.z
	elif by_handle and to_end == End.REST:
		anchor_to = CarryOnProps.ROLLER_HANDLE
	# In a toilet stall (board item c7b0e7be) a bag is set down by its top as it
	# stands, the highest point the hand can hold (a case's top edge, a
	# backpack's grab loop, a roller's bar), from the start: the body turns
	# round to sit in that frame. A hard case or a backpack is picked up by the
	# point it is carried by in front (a case by its handle), the hand not
	# sliding over it.
	if stall and set_down:
		anchor_from = stall_top(bag["kind"], loose)
		anchor_to = anchor_from
	elif stall and from_end == End.REST and to_end == End.HELD and not roller:
		anchor_from = anchor_to
	var held_at := anchor_from.lerp(anchor_to, t)
	var off_back: bool = from_end == End.WORN and bag["carry_from"] == SecurityLooks.Carry.BACK
	var on_back: bool = to_end == End.WORN and bag["carry"] == SecurityLooks.Carry.BACK
	var on_path: Transform3D
	if off_back or on_back:
		var side := back_side(
			frame.origin, flags["yaw"], lead, body["shoulders_y"][lead] - 0.1, body["scale"]
		)
		if off_back and t < BACK_SHARE:
			on_path = start.interpolate_with(side, smoothstep(0.0, 1.0, t / BACK_SHARE))
		elif off_back:
			var u := (t - BACK_SHARE) / (1.0 - BACK_SHARE)
			on_path = path(side, want, u, frame, frame.affine_inverse() * side, flags)
		elif t > 1.0 - BACK_SHARE:
			var u := (t - 1.0 + BACK_SHARE) / BACK_SHARE
			on_path = side.interpolate_with(want, smoothstep(0.0, 1.0, u))
		else:
			on_path = path(start, side, t / (1.0 - BACK_SHARE), frame, bag["from"], flags)
	else:
		# A bag picked up off a stall's floor rises, whatever its origin does (a case
		# stood on its end has its origin higher than flat in the hand).
		var lift := flags
		var goal := want
		if stall and from_end == End.REST and to_end == End.HELD:
			lift = flags.duplicate()
			lift["rising"] = true
			# One bag out to its side midway; two stand on their hands' sides already.
			lift["side"] = STALL_PICK_SIDE_M if body["scale"] >= 1.0 else 0.0
			# It rises to where the hand carries it, not to where the stooping hand
			# is now: the carry end follows the hand, and a path to it led the hand
			# down with it, under the floor (board item c7b0e7be). Not a roller: held by
			# its bar on top it stood up into the stooping head.
			var low: float = frame.origin.y + STALL_CARRY_GRIP_M
			if not roller:
				goal = want.translated(Vector3.UP * maxf(low - (want * anchor_to).y, 0.0))
		on_path = path(start, goal, t, frame, bag["from"], lift)
		# (In a stall path() turns it: upright, tipped late into the carry.)
		if (from_end == End.REST or to_end == End.REST) and not stall:
			# Off the floor or a tray it turns to hang from the hand soon after it
			# rises (off the floor sooner: lying flat it met the thighs); onto one
			# it hangs until it is nearly down (the arm above it).
			var up := UPRIGHT_FROM_FLOOR if flags.get("from_floor", false) else 0.35
			var w := smoothstep(0.0, up, t) if from_end == End.REST else smoothstep(0.65, 1.0, t)
			var q := start.basis.get_rotation_quaternion().slerp(
				want.basis.get_rotation_quaternion(), w
			)
			on_path.basis = Basis(q).scaled(start.basis.get_scale().lerp(want.basis.get_scale(), w))
	var targets := [Vector3.ZERO, Vector3.ZERO]
	for hand in 2:
		match float(ph["targets_at"][hand]):
			-1.0:
				targets[hand] = start * anchor_from
			2.0:
				targets[hand] = want * anchor_to
			_:
				targets[hand] = on_path * held_at
	if off_back or on_back:
		targets[lead] = by_side(targets[lead], k, from_end, to_end, frame, flags["yaw"], lead, body)
	var xf := on_path
	if ph["holder"] < 0:
		xf = start if k < span(from_end, to_end).x else want
	# Only a hard case, which lies flat on the floor across the feet: a shoulder
	# bag or a backpack lifted with the stoop kept bent the walker deep after a
	# target far ahead (into a lane arch's post). In a stall every kind, stood
	# by the door (a roller lifted with the back straightening early was held
	# short, into the thighs).
	var keeps := [0.0, 0.0]
	if bag["kind"] == SecurityLooks.Kind.CASE or stall:
		keeps[lead] = floor_keep(
			k, from_end, to_end, flags.get("from_floor", false), flags.get("to_floor", false)
		)
	# Sitting down in a stall to set a bag down by the door, the back bends
	# first (STALL_HIPS, CarryStoop.drops), as far as the reach needs at any
	# height (kept on).
	var hips := CarryStoop.HIPS_ALL
	if stall and to_end == End.REST:
		keeps[lead] = 1.0
		hips = STALL_HIPS
	return {
		"holder": ph["holder"],
		"xf": xf,
		"anchor": held_at,
		"targets": targets,
		"weights": ph["weights"],
		"keeps": keeps,
		"drops": [hips, hips],
	}


## The path of a moving bag at `k` from `start` (world now) to `want` (world),
## the body drawn at `frame`: a bag going up rises first and then comes across
## (picked up from the floor ahead, CarryMoves.pick_up(), `from_local` its
## start in the body's frame); one going down is lifted on the way, over a
## table edge, and one set down on the floor (`to_floor`) goes out ahead first
## and down late; either way kept `clear` from the body's centre line on the side
## of `hand`. In a toilet stall (`in_stall`) a bag in the hand (`hand_carry`)
## goes between the floor and the front carry ahead of the body with no lift
## or push out: set down straight down, picked up upright first (decision
## stall-bag-poses-as-built-bags-stand-upright-against-the-insi); a tote there
## goes as it does outside (pushed out to its side at the hip, it lay against
## the thigh of a walker sitting down, board item c7b0e7be). A bag goes up
## when its origin does, or with flag "rising" (plan(): a stall pick-up, which
## also goes flag "side" out to its hand's side midway). Moved
## from CarryOnProps._place_bags; the floor set-down added for board item 5ed915b0.
static func path(
	start: Transform3D,
	want: Transform3D,
	k: float,
	frame: Transform3D,
	from_local: Transform3D,
	flags: Dictionary
) -> Transform3D:
	var in_stall: bool = flags.get("in_stall", false)
	var hand_in_stall: bool = in_stall and flags.get("hand_carry", false)
	var placed := start.interpolate_with(want, k)
	var arc := 0.0 if hand_in_stall else 4.0 * k * (1.0 - k)
	var rising: bool = flags.get("rising", want.origin.y > start.origin.y)
	if hand_in_stall and rising:
		# Up fast: hand-led, it rises only after the hand has reached it, and the
		# walker stepping out caught it low with a foot.
		var soon := 1.0 - pow(1.0 - k, 4.0)
		var across := start.origin.lerp(want.origin, k * k)
		var tip := clampf((k - 0.4) / 0.6, 0.0, 1.0)
		# Out ahead of the walker's stride as it rises, back to the hand as it
		# tips over, and out to its hand's side midway, off the leg stepping past
		# it (hand-led it hangs where the hand can take it, short of the path).
		var ahead := (
			minf(k * 4.0, 1.0) * (1.0 - smoothstep(0.5, 1.0, k)) * CarryOnProps.PICK_AHEAD_M
		)
		var turn := Basis(Vector3.UP, flags.get("yaw", 0.0))
		var side := Vector3.LEFT if flags.get("hand", 0) == 0 else Vector3.RIGHT
		var out: float = flags.get("side", 0.0) * 4.0 * k * (1.0 - k)
		across += turn * (Vector3.BACK * ahead + side * out)
		placed = Transform3D(
			start.interpolate_with(want, tip).basis,
			Vector3(across.x, lerpf(start.origin.y, want.origin.y, soon), across.z)
		)
	elif hand_in_stall:
		pass
	elif rising and flags.get("from_floor", false) and CarryMoves.picks_up_ahead(from_local):
		placed = frame * CarryMoves.pick_up(from_local, frame.affine_inverse() * want, k)
	elif rising:
		var across := start.origin.lerp(want.origin, k * k)
		placed.origin.x = across.x
		placed.origin.z = across.z
		placed.origin.y = lerpf(start.origin.y, want.origin.y, 1.0 - pow(1.0 - k, 4.0))
		# Over the knee that steps forward, early in the move, and gone before
		# the bag comes in under the arm that will hold it.
		var early := 6.75 * k * (1.0 - k) * (1.0 - k) * pow(1.0 - k * k, 4.0)
		placed.origin.y += CarryOnProps.KNEE_LIFT_M * early
	elif flags.get("to_floor", false) and in_stall:
		# A tote set down by a stall's door: out ahead first, up over the thighs
		# of the walker sitting down, then down in front of the knees (straight out
		# ahead at the hip it met the right thigh, board item c7b0e7be), turned to
		# stand as it will by the door as it goes out and held STALL_TOTE_BACK_M
		# short of its place until it goes down (up and turning, it reached into
		# the door's leaves).
		var down := smoothstep(0.55, 1.0, k)
		var out := smoothstep(0.0, 0.35, k)
		var short := Basis(Vector3.UP, flags.get("yaw", 0.0)) * Vector3.BACK * STALL_TOTE_BACK_M
		var ahead := start.origin.lerp(want.origin - short * (1.0 - down), out)
		placed.basis = start.interpolate_with(want, out).basis
		placed.origin = Vector3(ahead.x, lerpf(start.origin.y, want.origin.y, down), ahead.z)
		placed.origin.y += STALL_TOTE_LIFT_M * sin(PI * clampf((k - 0.1) / 0.75, 0.0, 1.0))
	elif flags.get("to_floor", false):
		# Set down on the floor: out ahead first and down late, so it is not
		# low in front of the thighs and the bent knees, lifted only
		# SET_DOWN_LIFT_M (board item 5ed915b0).
		var ahead := start.origin.lerp(want.origin, 1.0 - (1.0 - k) * (1.0 - k))
		placed.origin = Vector3(ahead.x, lerpf(start.origin.y, want.origin.y, k * k), ahead.z)
		placed.origin.y += SET_DOWN_LIFT_M * arc
	else:
		placed.origin.y += CarryOnProps.TRANSFER_LIFT_M * arc
	var clear: float = flags.get("clear", CarryOnProps.TRANSFER_CLEAR_M)
	var yaw: float = flags.get("yaw", 0.0)
	var push := keep_out(placed.origin, frame.origin, yaw, flags.get("hand", 0), clear)
	placed.origin += push * minf(arc * 2.0, 1.0)
	return placed


## How far to push a moving bag at `at` out to `clear` from the centre line of
## a body at `centre` turned to `yaw` (zero when it is already that far out); a
## bag on the centre line goes out on the side of `hand` (0 right, 1 left).
static func keep_out(at: Vector3, centre: Vector3, yaw: float, hand: int, clear: float) -> Vector3:
	var away := at - centre
	away.y = 0.0
	var gap := away.length()
	if gap >= clear:
		return Vector3.ZERO
	if gap < 0.05:
		away = Basis(Vector3.UP, yaw) * (Vector3.LEFT if hand == 0 else Vector3.RIGHT)
	return away.normalized() * (clear - gap)
