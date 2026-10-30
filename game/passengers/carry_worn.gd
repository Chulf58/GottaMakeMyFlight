class_name CarryWorn
extends RefCounted
## Where a worn shoulder bag hangs on its walker (CarryOnProps draws it; kept
## out of carry_on_props.gd, which is at its line cap).


## A shoulder bag hung on the shoulder of `side` (0 right, 1 left) of a body
## turned to `yaw` at `centre`, whose Arm bone is at `joint`: its inner face to
## the hip, its strap's root CarryOnProps.STRAP_M under a point STRAP_OUT_M out
## from the centre line and STRAP_OVER_ARM_M over the joint, the strap running
## from there to its bar, which is that high and moved in by as far as the
## stoop drew the joint in (`shift`, stoop_shift(); none when the body is not
## stooping, at any pose of its own): upright then, tilted about the strap's
## root with its bottom out when the joint leans in. Kept STRAP_OUT_M out, the
## bar was 0.23 m off a joint the stoop drew 0.11 m in (board item a-shoulder-
## tote-floats-0-39-m-from-the-hand-at-the-end-of-a). `strap_base` is
## Strap_Reach's position in the bag. Returns [transform, the strap length in
## the bag's units].
static func shoulder(
	joint: Vector3,
	centre: Vector3,
	yaw: float,
	side: int,
	scale_by: float,
	strap_base: Vector3,
	shift := Vector3.ZERO
) -> Array:
	var turn := Basis(Vector3.UP, yaw)
	var out := turn * (Vector3.LEFT if side == 0 else Vector3.RIGHT)
	var forward := turn * Vector3.BACK
	var hang := centre + out * CarryOnProps.STRAP_OUT_M + forward * (joint - centre).dot(forward)
	hang.y = joint.y + CarryOnProps.STRAP_OVER_ARM_M
	var root := hang - Vector3.UP * CarryOnProps.STRAP_M
	var bar := hang + out * minf(shift.dot(out), 0.0)
	var upright := Basis(out.cross(Vector3.UP), out, Vector3.UP)
	var along := (bar - root).normalized()
	var basis := (Basis(Quaternion(Vector3.UP, along)) * upright).scaled(Vector3.ONE * scale_by)
	var length := root.distance_to(bar) / scale_by
	var at := root - basis * strap_base
	return [Transform3D(basis, at), length]


## How far (world) `stoop` (CarryStoop, as it last bent its skeleton) moved a
## point `at` of the upper body (world, as drawn): the back's turn about the
## Spine_01 bone, drawn at `pivot` (world; a bone attachment, as `at`: the
## skeleton's own pose may be read back without the stoop), undone
## (CarryStoop.turn()); zero when it is not stooping. The hips' drop moves
## nothing across the body, so the shift's part across it is the stoop's lean.
static func stoop_shift(stoop: CarryStoop, pivot: Vector3, at: Vector3) -> Vector3:
	var skeleton := stoop.get_skeleton() if stoop != null else null
	if skeleton == null or stoop.drawn <= 0.0 or stoop.targets.is_empty():
		return Vector3.ZERO
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var from := to_skeleton * pivot
	var aim := Vector3.ZERO
	for target in stoop.targets:
		aim += to_skeleton * target / stoop.targets.size()
	var rel := to_skeleton * at - from
	# Turned toward the target from where the pivot was before the hips went down
	# and back (STOOP_DROP and HIP_BACK_M of the stoop, all hips; CarryStoop).
	var drop: Vector3 = stoop.drops[0] if not stoop.drops.is_empty() else CarryStoop.HIPS_ALL
	var before := from
	if drop.z <= 0.0:
		var hips := Vector2(CarryStoop.STOOP_DROP * drop.x, CarryStoop.HIP_BACK_M * drop.y)
		hips *= stoop.drawn / skeleton.global_transform.basis.get_scale().x
		before += Vector3(0.0, hips.x, hips.y)
	var unbent := CarryStoop.turn(before, aim, stoop.drawn).inverse() * rel
	return skeleton.global_transform.basis * (rel - unbent)
