class_name RollerHandover
extends RefCounted
## A roller moved between its grip bar and its carry handle outside a toilet
## stall changes grip by a two-hand handover (decision roller-tray-moves-use-a-
## two-hand-handover-the-free-hand-take, board a365cb0b G3): into a security
## tray or onto the floor from the pull or the hand (pull>tray, hand>tray,
## hand>floor), the free hand comes to the carry handle while the bar hand
## still holds the bar, takes the roller at half way of the carry
## (CarryLead.phase()) and sets it down, and the bar hand lets go; out of a
## tray into the hand or the pull (tray>hand, tray>pull), the reverse: the
## free hand lifts it by the carry handle, and the hand it ends in takes the
## bar by half way. Each hand holds its own grip throughout, so the held point
## never slides through the air between the two (before: CarryLead.plan()
## blended it from the bar to the handle, up to 0.31 m off either grip).
##
## Fallback, when the free hand is busy (it holds another bag, or another bag
## goes into it or is set down from it as the move starts; free_hand_busy()):
## no handover is stamped and the move goes as it did before. At a lane tray a
## roller carried beside a hard case goes in last and comes out first
## (SecurityLooks.tray_turn()), freeing that hand for the handover.
##
## A roller parked on its wheels (RollerPark), passed between the pulling
## hands (CarryLead.is_pull_swap(), is_hand_pull_swap()) or picked up off the
## floor is not handed over. What it does not guarantee: the free hand
## reaching the handle (CarryArm's reach is limited; the bag is placed from
## the holding hand's grip, so a short reach moves the bag, it never leaves the
## grip).

## Lifted out of a tray, the body leans in to it (CarryLead.plan(), keeps) to
## this share of the carry, fading by the second: the roller rises first and
## comes in toward the body late (CarryLead.path()), and with the lean gone at
## CarryLead.KEEP_T the hands fell 0.15 to 0.3 m short of it (crossing probe
## --lane, seed 1106001, passenger 4 tray>hand.R).
const TRAY_KEEP := Vector2(0.6, 0.95)

## Lifting a roller out of a tray by its carry handle, the first hand holds
## this far (world up) over the handle, within the probes' GRIP_ON limit for a
## roller (9 cm): on the handle itself, the left hand's fingers went into the
## roller's top as it reached (crossing probe --lane, seed 1106001, passenger 4
## tray>hand.R, Fingertips.L 88 to 174 points in the roller at k 0.18 to 0.22).
const TRAY_PALM_M := 0.04

## Handed over to or from the pull, the middle of the roller's two grips comes
## this far ahead of the body's centre at hip height, upright (its 0.32 m width
## along +Z keeps 0.19 m ahead of the pelvis), its bar swung PULL_BAR_OUT_M
## wider and its axle at least PULL_AXLE_CLEAR_M out round the pulling side so
## the shell passes outside the leg instead of pitching back into the pelvis
## (g3_verify plates, passenger 4 pull.R>tray at k 0.33 and 0.50).
const PULL_FRONT_M := 0.35
const PULL_BAR_OUT_M := 0.14
const PULL_AXLE_CLEAR_M := 0.62
const TRAY_LIFT_M := 0.12
const PULL_HAND_IN := Vector2(0.22, 0.45)
const PULL_HAND_OUT := Vector2(0.5, 0.72)


## Stamps on `bag` (bag `i` of `held`, CarryPlace's record of a move just
## stamped: "was", "home", "carry" and "led" set) "handover", the hand that
## holds the roller first, when its move is a handover with the free hand
## free at `now`; else erases it. From the move's stamp and the bags' records
## only, never from the hands drawn (anti-pattern d655fcc9).
static func stamp(bag: Dictionary, held: Dictionary, i: int, now: float) -> void:
	bag.erase("handover")
	var first := first_hand(bag, held.get("in_stall", false))
	if first < 0:
		return
	var started := CarryLead.start_of(bag)
	var free := 1 - first if started[0] == CarryLead.End.HELD else first
	if free_hand_busy(held, i, free, now):
		return
	bag["handover"] = first


## The hand that holds a roller first in a handover move of `bag` (CarryPlace's
## record), or -1 when the move is not one: from a hand (its bar) into a tray
## or onto the floor, that hand; out of a tray into a hand, the other hand,
## which lifts it by its carry handle.
static func first_hand(bag: Dictionary, in_stall: bool) -> int:
	if bag.get("kind", -1) != SecurityLooks.Kind.ROLLER or in_stall:
		return -1
	if bag.get("park", false) or not bag.get("led", false) or not bag.has("was"):
		return -1
	var started := CarryLead.start_of(bag)
	var to_end := CarryLead.end_of(bag["home"], bag["carry"])
	if started[0] == CarryLead.End.HELD and to_end == CarryLead.End.REST:
		return started[1]
	var was: int = bag["was"]
	var off_tray := was >= 0 and was / 4 == SecurityLooks.Home.TRAY
	if started[0] == CarryLead.End.REST and to_end == CarryLead.End.HELD and off_tray:
		return 1 - CarryLead.hand_of(bag["home"])
	return -1


## Whether hand `free` (0 right) of `held` is busy with a bag other than bag
## `i` at `now`: the sim has another bag in that hand, carried in it (not worn),
## or another bag's record is in that hand or on its way into it, or was set
## down from it less than half way through its move (its hand lets go at
## CarryLead.REACH_SHARE from the end, after this move's handover).
static func free_hand_busy(held: Dictionary, i: int, free: int, now: float) -> bool:
	var bags: Array = held["bags"]
	for j in bags.size():
		if j == i:
			continue
		var other: Dictionary = bags[j]
		var in_hand: bool = (
			other.get("carry", -1) in [SecurityLooks.Carry.HAND, SecurityLooks.Carry.PULL]
		)
		var homes: Array = held["homes"]
		var hands: Array = held["hands"]
		if (
			j < homes.size()
			and homes[j] == SecurityLooks.Home.HAND
			and hands[j] == free
			and in_hand
		):
			return true
		if not other.has("home") or int(other["home"]) < 0:
			continue
		var ends := CarryLead.end_of(other["home"], other.get("carry", -1))
		if ends == CarryLead.End.HELD and CarryLead.hand_of(other["home"]) == free:
			return true
		if not other.has("was"):
			continue
		var started := CarryLead.start_of(other)
		var early := CarryPlace.progress_of(other, now) < 0.5
		if started[0] == CarryLead.End.HELD and started[1] == free and early:
			return true
	return false


## Places a handed-over roller on its path (`on_path`, between `start` and
## `goal`, world) at `t` of the carry, the body drawn at `frame`, `bag` its
## CarryPlace record: the middle of its two grips (`grip_a`, `grip_b`, its own
## frame) comes ahead of the body's centre at hip height (CarryLead.
## SWAP_HIP_BELOW_M under "start_shoulder_y", NAN: not moved) at half way, where
## the hands change. To or from the pull (`pull>tray`, `tray>pull`) it swings
## round the pulling hand's side (-X right, +X left) and stands upright at half
## way, wheels down and carry handle toward the other hand, before tipping into
## or out of the tray: shifted without turning upright, `start`'s 45-degree pull
## tilt thrust the suitcase back through the pelvis at k 0.33 to 0.50. Pure,
## never from a drawn hand (anti-pattern d655fcc9).
static func to_front(
	on_path: Transform3D,
	start: Transform3D,
	goal: Transform3D,
	frame: Transform3D,
	t: float,
	bag: Dictionary,
	grip_a: Vector3,
	grip_b: Vector3
) -> Transform3D:
	var shoulder_y := float(bag.get("start_shoulder_y", NAN))
	if is_nan(shoulder_y):
		return on_path
	var from_pull := _is_from_pull(bag)
	var to_pull := _is_to_pull(bag)
	if not from_pull and not to_pull:
		var w := smoothstep(0.0, 0.5, t) if t < 0.5 else 1.0 - smoothstep(0.5, 1.0, t)
		var front := Vector3(0.0, shoulder_y - CarryLead.SWAP_HIP_BELOW_M, CarryLead.SWAP_FRONT_M)
		var middle := on_path * ((grip_a + grip_b) * 0.5)
		return on_path.translated((frame * front - middle) * w)
	var first := int(bag.get("handover", 0))
	var bar_hand := first if from_pull else 1 - first
	var local := frame.affine_inverse()
	var start_l := local * start
	var goal_l := local * goal
	var scale_at := start_l.basis.get_scale().lerp(goal_l.basis.get_scale(), t)
	var up_b := _upright(bar_hand).scaled(scale_at)
	var front_p := Vector3(0.0, shoulder_y - CarryLead.SWAP_HIP_BELOW_M, PULL_FRONT_M)
	var mid_xf := Transform3D(up_b, front_p - up_b * ((grip_a + grip_b) * 0.5))
	if from_pull and t <= 0.5:
		return frame * _pull_half(start_l, mid_xf, grip_a, smoothstep(0.0, 0.5, t), bar_hand)
	if from_pull:
		var u := smoothstep(0.5, 1.0, t)
		return frame * _tray_half(goal_l, mid_xf, grip_b, u, smoothstep(0.65, 1.0, t), false)
	if t <= 0.5:
		var u := smoothstep(0.0, 0.5, t)
		return frame * _tray_half(start_l, mid_xf, grip_a, u, smoothstep(0.0, 0.35, t), true)
	return frame * _pull_half(goal_l, mid_xf, grip_b, 1.0 - smoothstep(0.5, 1.0, t), bar_hand)


## Keeps the carry-handle hand at its side while a pulled roller is still behind
## the hip (`pull>tray` before PULL_HAND_IN, `tray>pull` after PULL_HAND_OUT),
## so that arm does not reach across the body before the roller comes round.
static func adjust_weights(
	weights: Array, bag: Dictionary, t: float, first: int, lead: int
) -> void:
	if _is_from_pull(bag) and t < 0.5:
		weights[lead] = smoothstep(PULL_HAND_IN.x, PULL_HAND_IN.y, t)
	elif _is_to_pull(bag) and t > 0.5:
		weights[first] = 1.0 - smoothstep(PULL_HAND_OUT.x, PULL_HAND_OUT.y, t)


static func _is_from_pull(bag: Dictionary) -> bool:
	return (
		bag.get("carry_from", -1) == SecurityLooks.Carry.PULL
		and bag.has("was")
		and CarryLead.start_of(bag)[0] == CarryLead.End.HELD
	)


static func _is_to_pull(bag: Dictionary) -> bool:
	var carry: int = bag.get("carry", -1)
	return (
		carry == SecurityLooks.Carry.PULL
		and bag.has("home")
		and CarryLead.end_of(bag["home"], SecurityLooks.Carry.PULL) == CarryLead.End.HELD
	)


## Upright basis in the body's frame (+Z ahead, -X right) for a roller whose bar
## hand is `bar_hand` (0 right, 1 left): wheels down (+Z_bag = UP) and front
## carry handle (+Y_bag) facing inward toward the other hand.
static func _upright(bar_hand: int) -> Basis:
	var inward := Vector3.RIGHT if bar_hand == 0 else Vector3.LEFT
	return Basis(inward.cross(Vector3.UP), inward, Vector3.UP)


## The pull half (body's frame) between `pull_xf` (`s` = 0) and upright `mid_xf`
## (`s` = 1), anchored at `bar_anchor` on `bar_hand`'s side (0 right, -X).
static func _pull_half(
	pull_xf: Transform3D, mid_xf: Transform3D, bar_anchor: Vector3, s: float, bar_hand: int
) -> Transform3D:
	var out := -1.0 if bar_hand == 0 else 1.0
	var scale_at := pull_xf.basis.get_scale().lerp(mid_xf.basis.get_scale(), s)
	var bar_now := _round_side(
		pull_xf * bar_anchor, mid_xf * bar_anchor, s, out, 0.0, PULL_BAR_OUT_M
	)
	var axle_aim := _round_side(
		pull_xf * CarryOnProps.ROLLER_AXLE,
		mid_xf * CarryOnProps.ROLLER_AXLE,
		s,
		out,
		PULL_AXLE_CLEAR_M,
		0.0
	)
	var outward := Vector3(out, 0.0, 0.0)
	var ref_mid := outward.lerp(-outward, smoothstep(0.45, 0.95, s)).normalized()
	var ref := pull_xf.basis.y.normalized().lerp(ref_mid, smoothstep(0.0, 0.35, s)).normalized()
	var aimed := RollerPull.pulled(bar_now, axle_aim, 1.0, ref).basis.get_rotation_quaternion()
	var pull_q := pull_xf.basis.orthonormalized().get_rotation_quaternion()
	var up_q := mid_xf.basis.orthonormalized().get_rotation_quaternion()
	var q := pull_q.slerp(aimed, smoothstep(0.0, 0.2, s)).slerp(up_q, smoothstep(0.65, 1.0, s))
	var b := Basis(q).scaled(scale_at)
	return Transform3D(b, bar_now - b * bar_anchor)


## The tray half (body's frame) between `tray_xf` and upright `mid_xf`, held at
## `handle` (`ROLLER_HANDLE`), `u` 0 to 1 along the move and `w_rot` the turn.
static func _tray_half(
	tray_xf: Transform3D,
	mid_xf: Transform3D,
	handle: Vector3,
	u: float,
	w_rot: float,
	from_tray: bool
) -> Transform3D:
	var a_xf := tray_xf if from_tray else mid_xf
	var b_xf := mid_xf if from_tray else tray_xf
	var scale_at := a_xf.basis.get_scale().lerp(b_xf.basis.get_scale(), u)
	var qa := a_xf.basis.orthonormalized().get_rotation_quaternion()
	var qb := b_xf.basis.orthonormalized().get_rotation_quaternion()
	var b := Basis(qa.slerp(qb, w_rot)).scaled(scale_at)
	var h := (
		(a_xf * handle).lerp(b_xf * handle, u) + Vector3.UP * (TRAY_LIFT_M * 4.0 * u * (1.0 - u))
	)
	return Transform3D(b, h - b * handle)


## Swings from `from` to `to` (body's frame, +Z ahead) round `out` (-1 right,
## +1 left), at least `min_r * sin(PI * s)` out and `out_arc` wider midway.
static func _round_side(
	from: Vector3, to: Vector3, s: float, out: float, min_r: float, out_arc: float
) -> Vector3:
	var a0 := atan2(from.x * out, from.z)
	if a0 < -0.2:
		a0 += TAU
	var angle := lerpf(a0, atan2(to.x * out, to.z), s)
	var r := lerpf(Vector2(from.x, from.z).length(), Vector2(to.x, to.z).length(), s)
	r = maxf(r, min_r * sin(PI * s)) + out_arc * sin(PI * s)
	return Vector3(out * r * sin(angle), lerpf(from.y, to.y, s), r * cos(angle))
