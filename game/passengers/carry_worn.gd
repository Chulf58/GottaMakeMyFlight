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
## Measured by game/spike/worn_back_sweep_probe.gd (every body, both clips at
## 64 moments, the least gap read on an outline 1 cm wider, EDGE_M; the rows of
## male 04 and 05 and female 06, 09 and 12 added for board 3fcd8e5a, of male 10
## and female 02 for board a1c067fc). The sweep
## reads the torso only, so the one-bag rows of female_05 and female_11 put the
## pack's bottom in the left buttock (skinned to Quad.L) at the walk's stride,
## and so did those of female_06, _09, _12 and _02 (female_02 sweeps as female_05
## and takes her row); they are set from the stride
## instead, 1 cm clear of the legs with the panel resting on the back
## (test_worn_back_stride_clear.gd, boards 0dd2c787 and 3fcd8e5a; female_09's
## rests at 0.0296 m, under the 0.03 m limit). The one-bag rows of female_01,
## _03, _04 and _08 put the left buttock in the pack too (the crossing probe
## saw female_08's, board bcad1dd0, once the test checked every body): set
## from the stride the same way (female_01 rests at 0.0296 m). The two-bag
## rows (z, w) go with TWO_BAG_LEAN_DEGREES (board 2e43591b).
const BACK_ON_SPINE_M: Array[Vector4] = [
	Vector4(0.086, -0.09, 0.112, 0.00),
	Vector4(0.082, -0.06, 0.127, 0.06),
	Vector4(0.081, -0.06, 0.127, 0.06),
	Vector4(0.081, -0.06, 0.121, 0.03),
	Vector4(0.081, -0.06, 0.127, 0.06),
	Vector4(0.086, -0.09, 0.112, 0.00),
	Vector4(0.086, -0.09, 0.112, 0.00),
	Vector4(0.081, -0.06, 0.127, 0.06),
	Vector4(0.081, -0.06, 0.127, 0.06),
	Vector4(0.090, 0.03, 0.108, 0.09),
	Vector4(0.085, 0.03, 0.121, 0.12),
	Vector4(0.085, 0.03, 0.121, 0.12),
	Vector4(0.088, 0.03, 0.121, 0.12),
	Vector4(0.085, 0.03, 0.119, 0.15),
	Vector4(0.088, 0.03, 0.116, 0.12),
	Vector4(0.088, 0.03, 0.116, 0.12),
	Vector4(0.090, 0.03, 0.123, 0.12),
	Vector4(0.088, 0.03, 0.116, 0.12),
	Vector4(0.088, 0.03, 0.121, 0.12),
]
## The least panel gap BACK_ON_SPINE_M is measured for.
const BACK_CLEAR_M := 0.004
## It leans in at the top by this much, its bottom out clear of the hips.
const BACK_LEAN_DEGREES := 10.0
## Per body (PassengerLooks.BODIES): two bags' lean in place of
## BACK_LEAN_DEGREES (negative: the bottom in, toward the lower back). At 10
## degrees the two-bag pack rested its top on the back and stood its bottom
## half 5-11 cm off the lower back on every body (male_06 10.8 cm; board
## 2e43591b, anti-pattern 7e41ab22). Set with the row's z and w from the
## least of the larger of the top and bottom half gaps over the walk and idle
## clips (test_worn_back_stride_clear.gd's halves; lean in 2.5 degree steps,
## height in 3 cm steps, the distance behind the closest that keeps the torso
## out of the pack by about BACK_CLEAR_M and the legs LEG_CLEAR_M out).
const TWO_BAG_LEAN_DEGREES: Array[float] = [
	-17.5,
	-15.0,
	-15.0,
	-17.5,
	-15.0,
	-17.5,
	-17.5,
	-15.0,
	-15.0,
	-7.5,
	-15.0,
	-15.0,
	-15.0,
	-10.0,
	-12.5,
	-12.5,
	-15.0,
	-12.5,
	-15.0,
]
## The bones a one-bag pack's bottom rests on (hip_joints(), in this order):
## the two hip joints (the Quad bones' heads) and the pelvis.
const HIP_BONES: Array[String] = ["Quad.L", "Quad.R", "Hips"]
## The least drop of the rest point under the top of the panel the lean is
## taken over (a stoop deep enough to lift the hips to the pack's top).
const HIP_DROP_LEAST_M := 0.05
## Per body (PassengerLooks.BODIES): one bag worn on its hips
## (worn_back_on_hips(); board e22e90c2). x and y put the top of the panel
## behind and above the Spine_03 bone, as BACK_ON_SPINE_M's x and y do; the
## panel runs from there through a point z behind the rest point, which is
## the hip joint furthest back moved toward the Hips bone by w (0 the joint, 1
## the pelvis). Hung on the spine alone the pack's bottom half stood 3.9-8.1
## cm off the lower back, as the hips swing under it through the stride, and
## no rigid placement got it under 3 cm with the legs 1 cm clear. Set from
## test_worn_back_stride_clear.gd's halves over the walk and idle clips: the
## least of the larger half gap with the legs LEG_CLEAR_M out of the pack
## and the torso out of it (x in 2.5 mm steps, y in 1.5-3 cm steps no higher
## than BACK_ON_SPINE_M's, z in 1-2.5 mm steps, w in quarters).
const ON_HIPS_M: Array[Vector4] = [
	Vector4(0.081, -0.06, 0.143, 0.0),
	Vector4(0.092, -0.06, 0.145, 0.5),
	Vector4(0.081, -0.06, 0.143, 0.0),
	Vector4(0.081, -0.06, 0.143, 0.0),
	Vector4(0.081, -0.06, 0.143, 0.0),
	Vector4(0.081, -0.06, 0.143, 0.0),
	Vector4(0.081, -0.06, 0.143, 0.0),
	Vector4(0.086, -0.09, 0.143, 0.0),
	Vector4(0.081, -0.06, 0.143, 0.0),
	Vector4(0.085, -0.03, 0.174, 0.5),
	Vector4(0.085, 0.03, 0.174, 1.0),
	Vector4(0.085, 0.03, 0.173, 1.0),
	Vector4(0.085, 0.03, 0.174, 1.0),
	Vector4(0.095, 0.03, 0.173, 1.0),
	Vector4(0.078, 0.00, 0.173, 1.0),
	Vector4(0.085, -0.03, 0.174, 0.5),
	Vector4(0.085, 0.03, 0.184, 1.0),
	Vector4(0.083, -0.03, 0.173, 1.0),
	Vector4(0.085, 0.03, 0.174, 1.0),
]


## A shoulder bag hung on the shoulder of `side` (0 right, 1 left) of a body
## turned to `yaw` at `centre`, whose Arm bone is at `joint`: its strap bar
## tracks `joint` directly (STRAP_SHOULDER_OUT_M out and STRAP_OVER_ARM_M up),
## while the bag's top rim hangs STRAP_M below outside the hip (using the
## upright shoulder's offset `joint - shift` plus STRAP_HIP_CLEAR_M, at least
## STRAP_OUT_M), tilting the bottom slightly outward when the shoulder is
## narrower or stoops inward (`shift`, stoop_shift()). `strap_base` is
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
	var bar := (
		joint + out * CarryOnProps.STRAP_SHOULDER_OUT_M + Vector3.UP * CarryOnProps.STRAP_OVER_ARM_M
	)
	var upright_rel := joint - shift - centre
	var hip_out := (
		maxf(upright_rel.dot(out) + CarryOnProps.STRAP_HIP_CLEAR_M, CarryOnProps.STRAP_OUT_M)
		+ maxf(shift.dot(out), 0.0)
	)
	var hang := centre + out * hip_out + forward * (joint - centre).dot(forward)
	hang.y = bar.y
	var root := hang - Vector3.UP * CarryOnProps.STRAP_M
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
## One bag on a known body given its `hips` (hip_joints(), world, as drawn)
## rests on them instead (worn_back_on_hips(), ON_HIPS_M); without them it
## keeps the spine-only placement (BACK_ON_SPINE_M, follow_tilt).
static func worn_back(
	spine: Transform3D, yaw: float, scale_by: float, body := -1, hips := PackedVector3Array()
) -> Transform3D:
	if body < 0 or body >= BACK_ON_SPINE_M.size():
		# Not measured: main's placement, the plain lean.
		var legacy := Vector2(BACK_FROM_SPINE_M, BACK_TOP_OVER_SPINE_M)
		return worn_back_at(spine, yaw, scale_by, legacy, false)
	var per := BACK_ON_SPINE_M[body]
	if scale_by >= 1.0 and hips.size() == HIP_BONES.size():
		return worn_back_on_hips(spine, yaw, scale_by, ON_HIPS_M[body], hips)
	if scale_by >= 1.0:
		return worn_back_at(spine, yaw, scale_by, Vector2(per.x, per.y), true)
	var top := Vector2(per.z, per.w)
	return worn_back_at(spine, yaw, scale_by, top, false, TWO_BAG_LEAN_DEGREES[body])


## worn_back() with the top of the panel `top.x` behind the bone and `top.y`
## above it: its length along the bone leaning in at the top by `lean_degrees`
## (BACK_LEAN_DEGREES; two bags' per body, TWO_BAG_LEAN_DEGREES) about that
## top. With `follow_tilt` (one bag) the lean grows by as far as the bone tilts
## back past upright, so a back leaning back in an idle does not swing the
## pack's bottom into the hips (stooping and leaning forward unchanged); two
## bags' smaller pack keeps its plain lean, without the tilt,
## which rests it better (conductor ruling 2026-11-06, board 4af10dd0).
static func worn_back_at(
	spine: Transform3D,
	yaw: float,
	scale_by: float,
	top: Vector2,
	follow_tilt: bool,
	lean_degrees := BACK_LEAN_DEGREES
) -> Transform3D:
	var up := spine.basis.y.normalized()
	var behind := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var out := (behind - up * behind.dot(up)).normalized()
	var anchor := spine.origin + out * top.x + up * top.y
	var lean := deg_to_rad(lean_degrees)
	if follow_tilt:
		lean += maxf(0.0, asin(clampf(up.dot(behind), -1.0, 1.0)))
	var along := up * cos(lean) - out * sin(lean)
	var back := out * cos(lean) + up * sin(lean)
	var basis := Basis(back.cross(along), back, along).scaled(Vector3.ONE * scale_by)
	var length := CarryOnProps.bag_box(SecurityLooks.Kind.BACKPACK).end.z * scale_by
	return Transform3D(basis, anchor - along * length)


## worn_back() of one bag on its hips (board e22e90c2), as a strapped pack
## hangs from the shoulders and rests its bottom on the buttocks: the top of
## the panel `on.x` behind the Spine_03 bone and `on.y` above it, as
## worn_back_at() puts it, the panel running from there through a point
## `on.z` behind the rest point (the hip joint furthest back, moved toward the
## pelvis by `on.w`), in the plane of the bone and the walker's facing, so the
## pack swings with the hips under it through the stride and the idle. `hips`
## is hip_joints() (the frame of `spine`).
static func worn_back_on_hips(
	spine: Transform3D, yaw: float, scale_by: float, on: Vector4, hips: PackedVector3Array
) -> Transform3D:
	var up := spine.basis.y.normalized()
	var behind := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var out := (behind - up * behind.dot(up)).normalized()
	var anchor := spine.origin + out * on.x + up * on.y
	var joint := hips[0] if (hips[0] - hips[1]).dot(out) > 0.0 else hips[1]
	var rel := joint.lerp(hips[2], on.w) - anchor
	var lean := atan2(rel.dot(out) + on.z, maxf(-rel.dot(up), HIP_DROP_LEAST_M))
	return worn_back_at(spine, yaw, scale_by, Vector2(on.x, on.y), false, rad_to_deg(lean))


## The heads of `body`'s HIP_BONES now (world), read from its skeleton (found
## once and kept on the body), for worn_back(); empty when a bone is missing.
static func hip_joints(body: Node3D) -> PackedVector3Array:
	if not body.has_meta(&"carry_worn_hips"):
		var found := body.find_children("*", "Skeleton3D", true, false)
		var skeleton := found[0] as Skeleton3D if not found.is_empty() else null
		var bones := PackedInt32Array()
		for name in HIP_BONES:
			if skeleton != null and skeleton.find_bone(name) >= 0:
				bones.append(skeleton.find_bone(name))
		body.set_meta(&"carry_worn_hips", [skeleton, bones])
	var cached: Array = body.get_meta(&"carry_worn_hips")
	var joints := PackedVector3Array()
	if (cached[1] as PackedInt32Array).size() < HIP_BONES.size():
		return joints
	var skeleton: Skeleton3D = cached[0]
	for bone: int in cached[1]:
		joints.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin)
	return joints
