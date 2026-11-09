class_name CarryWorn
extends RefCounted
## Where a worn shoulder bag hangs on its walker, and a backpack held in front
## (CarryOnProps draws them; kept out of carry_on_props.gd, at its line cap).

## Worn backpack: the top of its back panel this far behind the Spine_03 bone
## and this far above it, for a body whose index is not known (BACK_ON_SPINE_M
## is per body).
const BACK_FROM_SPINE_M := 0.175
const BACK_TOP_OVER_SPINE_M := 0.06
## Per body (PassengerLooks.BODIES): where the top of a worn pack's panel is,
## x behind the Spine_03 bone and y above it for one bag, z and w for two
## (SecurityLooks.TWO_BAG_SCALE), so the panel rests on the back: the least gap
## from the body's own back to the panel over its idle and walk clips is about
## BACK_CLEAR_M (board 4af10dd0: 0.175 m behind and 0.06 m above for every
## body stood it 0.04-0.13 m off the back). The height is the one, of
## worn_back_sweep_probe.gd's TOPS_M, whose largest gap over the clips is
## least (a top level with the shoulders meets them as they move; the male
## shoulders reach a one-bag pack's top corners unless it hangs 6-9 cm lower).
## Measured by game/spike/worn_back_sweep_probe.gd (12 bodies, both clips at
## 64 moments, the least gap read on an outline 1 cm wider, EDGE_M). The sweep
## reads the torso only, so the one-bag rows of bodies 9 and 11 put the pack's
## bottom in the left buttock (skinned to Quad.L) at the walk's stride; they
## are set from the stride instead, 1 cm clear of the legs with the panel
## resting on the back (test_worn_back_stride_clear.gd, board 0dd2c787).
const BACK_ON_SPINE_M: Array[Vector4] = [
	Vector4(0.086, -0.09, 0.097, 0.03),
	Vector4(0.082, -0.06, 0.100, 0.00),
	Vector4(0.081, -0.06, 0.100, 0.00),
	Vector4(0.081, -0.06, 0.100, 0.00),
	Vector4(0.081, -0.06, 0.081, -0.06),
	Vector4(0.086, -0.09, 0.102, 0.00),
	Vector4(0.081, -0.03, 0.110, 0.06),
	Vector4(0.073, -0.03, 0.110, 0.06),
	Vector4(0.072, -0.03, 0.110, 0.06),
	Vector4(0.088, 0.03, 0.110, 0.06),
	Vector4(0.065, -0.03, 0.092, 0.03),
	Vector4(0.088, 0.03, 0.110, 0.06),
]
## The least panel gap BACK_ON_SPINE_M is measured for.
const BACK_CLEAR_M := 0.004
## It leans in at the top by this much, its bottom out clear of the hips.
const BACK_LEAN_DEGREES := 10.0


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
	# With the back bent first (z 1) the hips did not go with it; z between 0
	# and 1 is a blend of the two (CarryStoop.solved()), so is this: as a flag
	# a shoulder bag snapped at the end of a collecting walker's stoop ease
	# (RollerPark.drops_of()).
	var before := from
	var hips := Vector2(CarryStoop.STOOP_DROP * drop.x, CarryStoop.HIP_BACK_M * drop.y)
	hips *= stoop.drawn / skeleton.global_transform.basis.get_scale().x
	before += Vector3(0.0, hips.x, hips.y) * (1.0 - clampf(drop.z, 0.0, 1.0))
	var unbent := CarryStoop.turn(before, aim, stoop.bent).inverse() * rel
	return skeleton.global_transform.basis * (rel - unbent)


## A backpack held in front of a body turned to `yaw` by its top grab loop at
## `grip` (CarryHand.carried_in_front): hanging upright below the hand, its
## back panel (its y 0 face) toward the body, as worn on the chest (conductor
## ruling 2026-10-30: lying flat it was held over its middle, 27 cm off its
## loop).
static func loop_in_front(grip: Vector3, yaw: float, scale_by: float) -> Transform3D:
	var turn := Basis(Vector3.UP, yaw)
	var basis := Basis(turn * Vector3.LEFT, turn * Vector3.BACK, Vector3.UP)
	basis = basis.scaled(Vector3.ONE * scale_by)
	return Transform3D(basis, grip - basis * CarryOnProps.BACKPACK_LOOP)


## A backpack worn on body `body` (PassengerLooks.BODIES; -1 when not known)
## turned to `yaw` whose Spine_03 bone is at `spine` (world): the top of its
## back panel where BACK_ON_SPINE_M puts it for its size (BACK_FROM_SPINE_M
## behind and BACK_TOP_OVER_SPINE_M above the bone for -1; worn_back_at()).
static func worn_back(spine: Transform3D, yaw: float, scale_by: float, body := -1) -> Transform3D:
	if body < 0 or body >= BACK_ON_SPINE_M.size():
		# Not measured: main's placement, the plain lean.
		var legacy := Vector2(BACK_FROM_SPINE_M, BACK_TOP_OVER_SPINE_M)
		return worn_back_at(spine, yaw, scale_by, legacy, false)
	var per := BACK_ON_SPINE_M[body]
	var top := Vector2(per.x, per.y) if scale_by >= 1.0 else Vector2(per.z, per.w)
	return worn_back_at(spine, yaw, scale_by, top, scale_by >= 1.0)


## worn_back() with the top of the panel `top.x` behind the bone and `top.y`
## above it: its length along the bone leaning in at the top by
## BACK_LEAN_DEGREES about that top. With `follow_tilt` (one bag) the lean
## grows by as far as the bone tilts back past upright, so a back leaning back
## in an idle does not swing the pack's bottom into the hips (stooping and
## leaning forward unchanged); two bags' smaller pack keeps the plain lean,
## which rests it better (conductor ruling 2026-11-06, board 4af10dd0).
static func worn_back_at(
	spine: Transform3D, yaw: float, scale_by: float, top: Vector2, follow_tilt: bool
) -> Transform3D:
	var up := spine.basis.y.normalized()
	var behind := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var out := (behind - up * behind.dot(up)).normalized()
	var anchor := spine.origin + out * top.x + up * top.y
	var lean := deg_to_rad(BACK_LEAN_DEGREES)
	if follow_tilt:
		lean += maxf(0.0, asin(clampf(up.dot(behind), -1.0, 1.0)))
	var along := up * cos(lean) - out * sin(lean)
	var back := out * cos(lean) + up * sin(lean)
	var basis := Basis(back.cross(along), back, along).scaled(Vector3.ONE * scale_by)
	var length := CarryOnProps.bag_box(SecurityLooks.Kind.BACKPACK).end.z * scale_by
	return Transform3D(basis, anchor - along * length)
