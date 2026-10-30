class_name CarryWorn
extends RefCounted
## Where a worn shoulder bag hangs on its walker (CarryOnProps draws it; kept
## out of carry_on_props.gd, which is at its line cap). Pure.

## The bar never sits further out from the joint than this (STRAP_OUT_M less
## the upright Arm bone's 0.206 m from the centre line): a joint drawn in toward
## the centre line (the body leaning to reach low with the other hand) takes
## the bar in with it, the bag tilting about its top so its bottom stays
## outside the hip. Kept STRAP_OUT_M out from the centre line, the bar was
## 0.23 m off a joint leaning 0.11 m in (board item a-shoulder-tote-floats-
## 0-39-m-from-the-hand-at-the-end-of-a).
const STRAP_PAST_JOINT_M := CarryOnProps.STRAP_OUT_M - 0.206


## A shoulder bag hung on the shoulder of `side` (0 right, 1 left) of a body
## turned to `yaw` at `centre`, whose Arm bone is at `joint`: its inner face to
## the hip, its strap's root CarryOnProps.STRAP_M under a point STRAP_OUT_M out
## from the centre line and STRAP_OVER_ARM_M over the joint, the strap running
## from there to its bar, which is that high and at most STRAP_PAST_JOINT_M out
## past the joint (upright when the joint is where it stands upright; tilted
## about the strap's root, its bottom out, when the joint leans in).
## `strap_base` is Strap_Reach's position in the bag. Returns [transform, the
## strap length in the bag's units].
static func shoulder(
	joint: Vector3, centre: Vector3, yaw: float, side: int, scale_by: float, strap_base: Vector3
) -> Array:
	var turn := Basis(Vector3.UP, yaw)
	var out := turn * (Vector3.LEFT if side == 0 else Vector3.RIGHT)
	var forward := turn * Vector3.BACK
	var strap_out := CarryOnProps.STRAP_OUT_M
	var hang := centre + out * strap_out + forward * (joint - centre).dot(forward)
	hang.y = joint.y + CarryOnProps.STRAP_OVER_ARM_M
	var root := hang - Vector3.UP * CarryOnProps.STRAP_M
	var past := minf(strap_out, (joint - centre).dot(out) + STRAP_PAST_JOINT_M)
	var bar := hang + out * (past - strap_out)
	var upright := Basis(out.cross(Vector3.UP), out, Vector3.UP)
	var along := (bar - root).normalized()
	var basis := (Basis(Quaternion(Vector3.UP, along)) * upright).scaled(Vector3.ONE * scale_by)
	var length := root.distance_to(bar) / scale_by
	var at := root - basis * strap_base
	return [Transform3D(basis, at), length]
