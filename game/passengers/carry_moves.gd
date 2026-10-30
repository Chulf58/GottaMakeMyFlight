class_name CarryMoves
extends RefCounted
## The paths of carry-on bags moving between homes (CarryOnProps' transfer
## moves) that keep clear of the walker's own body (board item pre-existing-
## carry-self-clips-found-by-game-spike-basic-scan). Pure: every transform is
## in the body's frame (x across, +z ahead).
##
## A bag picked up from the floor ahead of the walker rises ahead of the
## stepping knee, swings out to its hand's side and comes back along the
## outside of the thigh (pick_up()). The overhead route between the pull and
## the hand is gone (decision carry-on-bags-stay-in-the-hand-during-every-move-
## no-overhead): bags move hand-led (CarryLead).

## A bag picked up from a floor spot this far or more ahead of the body takes
## pick_up()'s path.
const PICK_FROM_AHEAD_M := 0.3


## Whether a move from `from` (a floor spot) takes pick_up()'s path: it starts
## ahead of the body.
static func picks_up_ahead(from: Transform3D) -> bool:
	return from.origin.z >= PICK_FROM_AHEAD_M


## A bag picked up from the floor ahead of the walker (`from`) to `to` (a hand
## or a shoulder) at `k`: it rises early (and over the knee), out ahead of the
## stride; it comes out to its side early, turning with it, and back toward
## the body late, so it passes outside the thigh rather than across it.
static func pick_up(from: Transform3D, to: Transform3D, k: float) -> Transform3D:
	var out := 1.0 - (1.0 - k) * (1.0 - k)
	var back := k * k * k
	var at := Vector3(
		lerpf(from.origin.x, to.origin.x, out),
		lerpf(from.origin.y, to.origin.y, 1.0 - pow(1.0 - k, 4.0)),
		lerpf(from.origin.z, to.origin.z, back)
	)
	# Over the knee that steps forward, early in the move.
	at.y += CarryOnProps.KNEE_LIFT_M * 6.75 * k * (1.0 - k) * (1.0 - k) * pow(1.0 - k * k, 4.0)
	at.z += minf(k * 4.0, 1.0) * (1.0 - smoothstep(0.5, 1.0, k)) * CarryOnProps.PICK_AHEAD_M
	var turn := from.basis.get_rotation_quaternion().slerp(to.basis.get_rotation_quaternion(), out)
	var basis := Basis(turn).scaled(from.basis.get_scale().lerp(to.basis.get_scale(), out))
	return Transform3D(basis, at)
