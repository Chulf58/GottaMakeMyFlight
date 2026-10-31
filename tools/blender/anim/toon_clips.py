"""Walk, run, sit and shower clips for the Toon City People characters, baked in place.

Called by tools/blender/convert_toon_batch.py from build_character, after the idle
bake and after the armature's 90 degree X rotation is applied, so armature space is
world space (Z up, the character faces -Y). Adds five actions next to "idle", six on a
passenger body:

- walk, run (loop): retargeted from the Mixamo locomotion packs downloaded for Dome
  Farmer. Rotations are copied as world-space deltas from the Mixamo T-pose; each
  limb bone is first swung so it points where its Mixamo bone points. The forward
  travel is removed as a pure linear ramp, so a planted source foot becomes a foot
  moving back at one constant speed. Hips and ankles are placed at the Mixamo
  offsets scaled by the leg-length ratio, and the legs are solved by two-bone IK to
  those ankles. The speed the sim must move a passenger at is printed as SPEED.
- sit_down, sit_idle (loop), stand_up: no source clip exists in any downloaded pack,
  so these are authored on the toon rig. The origin stays at the feet: the passenger
  stands in front of the seat facing away from it, and the hips move back and down
  onto the seat. The seat the clip implies is printed as SIT_CONTRACT.
- shower (loop, 5 s), passenger bodies only (staff never shower): authored on the toon
  rig in tools/blender/anim/toon_shower.py.
  The passenger stands with planted feet and washes the hair, the shoulders, the back
  of the head, the chest and the belly; the run prints a SHOWER line with its checks.

Every clip keys every bone on every frame at the characters' own 25 fps, so a later
vertex-animation bake can sample any clip the same way.
"""

import json
import math
import os

import bpy
from mathutils import Matrix, Vector

FPS = 25
MIXAMO = "C:\\Users\\chulf\\Dome Farmer\\Animations"
# tools/blender/out/anim_clips of the checkout this file sits in, so a worktree run
# writes its own reports.
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "out", "anim_clips")
SOURCES = {
    "male": {"walk": ("Male Locomotion Pack", "walking.fbx"), "run": ("Male Locomotion Pack", "standard run.fbx")},
    "female": {"walk": ("Female Locomotion Pack", "walking.fbx"), "run": ("Female Locomotion Pack", "running.fbx")},
}
# Every character's clips. Passenger bodies also carry "shower" (see clip_names).
CLIPS = ("idle", "walk", "run", "sit_down", "sit_idle", "stand_up")
LOOPING = ("idle", "walk", "run", "sit_idle", "shower")

# toon bone -> Mixamo bone (without the "mixamorig:" prefix)
MAP = {"Hips": "Hips", "Spine_01": "Spine", "Spine_02": "Spine1", "Spine_03": "Spine2", "Neck": "Neck", "Head": "Head"}
# bone -> the child whose head gives the bone's pointing direction (toon, Mixamo)
TOON_DIR = {}
MX_DIR = {}
for _s, _m in ((".L", "Left"), (".R", "Right")):
    MAP.update(
        {
            "Clavicle" + _s: _m + "Shoulder",
            "Arm" + _s: _m + "Arm",
            "Forearm" + _s: _m + "ForeArm",
            "Hand" + _s: _m + "Hand",
            "Fingers" + _s: _m + "HandMiddle1",
            "Fingertips" + _s: _m + "HandMiddle2",
            "Thumb" + _s: _m + "HandThumb1",
            "Thumb_Tip" + _s: _m + "HandThumb2",
            "Quad" + _s: _m + "UpLeg",
            "Shin" + _s: _m + "Leg",
            "Foot" + _s: _m + "Foot",
            "Toes" + _s: _m + "ToeBase",
        }
    )
    TOON_DIR.update(
        {
            "Clavicle" + _s: "Arm" + _s,
            "Arm" + _s: "Forearm" + _s,
            "Forearm" + _s: "Hand" + _s,
            "Hand" + _s: "Fingers" + _s,
            "Fingers" + _s: "Fingertips" + _s,
            "Fingertips" + _s: "Fingertips" + _s + "_end",
            "Thumb" + _s: "Thumb_Tip" + _s,
            "Thumb_Tip" + _s: "Thumb_Tip" + _s + "_end",
            "Quad" + _s: "Shin" + _s,
            "Shin" + _s: "Foot" + _s,
            "Foot" + _s: "Toes" + _s,
            "Toes" + _s: "Toes" + _s + "_end",
        }
    )
    MX_DIR.update(
        {
            _m + "Shoulder": _m + "Arm",
            _m + "Arm": _m + "ForeArm",
            _m + "ForeArm": _m + "Hand",
            _m + "Hand": _m + "HandMiddle1",
            _m + "HandMiddle1": _m + "HandMiddle2",
            _m + "HandMiddle2": _m + "HandMiddle3",
            _m + "HandThumb1": _m + "HandThumb2",
            _m + "HandThumb2": _m + "HandThumb3",
            _m + "UpLeg": _m + "Leg",
            _m + "Leg": _m + "Foot",
            _m + "Foot": _m + "ToeBase",
            _m + "ToeBase": _m + "Toe_End",
        }
    )
SIDES = (".L", ".R")
# Only the arm chain is swung onto the Mixamo rest directions. Feet and fingers keep their
# own rest shape (both rigs stand flat-footed in their rest), and legs come from IK.
ALIGNED = ("Clavicle", "Arm", "Forearm", "Hand")
FORWARD = Vector((0.0, -1.0, 0.0))

# Contact: a source foot marker is planted while it moves slower than this in the
# unstripped source and sits within CONTACT_HEIGHT_M of its own rest height.
CONTACT_SPEED_MPS = 0.25
CONTACT_HEIGHT_M = 0.04
CONTACT_TOLERANCE_M = 0.03
IK_CLAMP_TOLERANCE_M = 0.01
LOOP_TOLERANCE = 1e-3
# Heel lift over which the ankle hands its placement to the ball of the foot.
ROLL_BAND_M = 0.03

# Sit pose, authored. Thigh slope below level and the pelvis tilt are the only shape
# inputs; the seat they imply is measured off the posed mesh and printed.
SIT_THIGH_SLOPE_DEG = 4.0
SIT_PELVIS_TILT_DEG = 10.0
SIT_SPINE_LEAN_DEG = 6.0
SIT_DOWN_FRAMES = 30
SIT_IDLE_FRAMES = 100
SIT_LEAN_BUMP_DEG = 24.0
SIT_BREATH_DEG = 3.0
# The game's seat pans are at this height (gate chairs, cafe chairs). A body whose seated
# pose rests higher (the female 03/04/05/08/11 bodies' thighs sit about 5 cm above it)
# has its hips lowered by the difference, the legs re-solved to the same planted feet, so
# it rests on the pan; one that rests lower is left as it is (a skirt hangs below the seat).
SEAT_TOP_M = 0.53
SEAT_FIT_TOLERANCE_M = 0.01


class Fail(Exception):
    pass


def log(*a):
    print("TOON_ANIM", *a, flush=True)


def rot_x(deg):
    return Matrix.Rotation(math.radians(deg), 3, "X")


def swing(u, v):
    return u.rotation_difference(v).to_matrix()


def smooth(u):
    return u * u * (3.0 - 2.0 * u)


class ToonRig:
    """Rest data of the toon armature and the FK that turns world rotations into keys."""

    def __init__(self, arm):
        if any(abs(arm.matrix_world[i][j] - (1.0 if i == j else 0.0)) > 1e-5 for i in range(4) for j in range(4)):
            raise Fail("armature transform must be applied before clips are added")
        self.arm = arm
        bones = arm.data.bones
        self.order = sorted((b.name for b in bones), key=lambda n: len(bones[n].parent_recursive))
        self.parent = {b.name: (b.parent.name if b.parent else None) for b in bones}
        self.rest = {b.name: b.matrix_local.copy() for b in bones}
        self.rest_r = {n: m.to_3x3().normalized() for n, m in self.rest.items()}
        self.rest_head = {n: m.translation.copy() for n, m in self.rest.items()}
        self.rel = {}
        for n, p in self.parent.items():
            self.rel[n] = self.rest[n] if p is None else self.rest[p].inverted() @ self.rest[n]
        self.dir_local = {}
        for n, c in TOON_DIR.items():
            if n in bones and c in bones:
                d = (self.rest_head[c] - self.rest_head[n]).normalized()
                self.dir_local[n] = self.rest_r[n].inverted() @ d
        self.length = {n: (self.rest_head[TOON_DIR[n]] - self.rest_head[n]).length for n in self.dir_local}

    def direction(self, name, r):
        return r @ self.dir_local[name]

    def fk(self, rots, hips_head, ref_r=None):
        """World matrices for every bone. Bones missing from rots follow their parent
        rigidly, relative to ref_r (default: the rest pose)."""
        ref_r = ref_r or self.rest_r
        mats = {}
        for n in self.order:
            p = self.parent[n]
            if n in rots:
                r = rots[n]
            elif p is None:
                r = self.rest_r[n]
            else:
                r = mats[p].to_3x3() @ ref_r[p].inverted() @ ref_r[n]
            if p is None:
                head = self.rest_head[n]
            elif n == "Hips":
                head = hips_head
            else:
                head = (mats[p] @ self.rel[n]).translation
            m = r.to_4x4()
            m.translation = head
            mats[n] = m
        return mats

    def key(self, mats, frame, prev):
        for n in self.order:
            p = self.parent[n]
            parent_m = Matrix.Identity(4) if p is None else mats[p]
            basis = (parent_m @ self.rel[n]).inverted() @ mats[n]
            pb = self.arm.pose.bones[n]
            pb.rotation_mode = "QUATERNION"
            loc, q, _scale = basis.decompose()
            if n in prev:
                q.make_compatible(prev[n])
            prev[n] = q
            pb.location = loc
            pb.rotation_quaternion = q
            pb.scale = (1.0, 1.0, 1.0)
            pb.keyframe_insert("location", frame=frame)
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            pb.keyframe_insert("scale", frame=frame)

    def solve_limb(self, upper, lower, end_name, rots, mats, target, hint):
        """Two-bone IK: swing upper and lower (keeping their twist) so the chain ends at
        target with the bend towards hint. Returns how far the target was out of reach."""
        a = mats[upper].translation
        l1, l2 = self.length[upper], self.length[lower]
        d = target - a
        dist = d.length
        reach = min(dist, (l1 + l2) * 0.9995)
        dn = d.normalized()
        p = hint - a
        p = p - dn * p.dot(dn)
        if p.length < 1e-5:
            p = FORWARD - dn * FORWARD.dot(dn)
        pn = p.normalized()
        cos_a = max(-1.0, min(1.0, (l1 * l1 + reach * reach - l2 * l2) / (2.0 * l1 * reach)))
        sin_a = math.sqrt(max(0.0, 1.0 - cos_a * cos_a))
        knee = a + dn * (l1 * cos_a) + pn * (l1 * sin_a)
        end = a + dn * reach
        r_up = rots[upper]
        rots[upper] = swing(self.direction(upper, r_up), (knee - a).normalized()) @ r_up
        r_lo = rots[lower]
        rots[lower] = swing(self.direction(lower, r_lo), (end - knee).normalized()) @ r_lo
        return dist - reach


# ---------------------------------------------------------------- Mixamo retarget


def mixamo_bone(src, name):
    for b in src.data.bones:
        if b.name.split(":")[-1] == name:
            return b.name
    raise Fail("Mixamo rig has no bone %s" % name)


def retarget(rig, stem, clip, pack, fbx):
    scene = bpy.context.scene
    before = set(bpy.data.objects)
    actions_before = set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=os.path.join(MIXAMO, pack, fbx))
    src_fps = scene.render.fps / scene.render.fps_base
    scene.render.fps, scene.render.fps_base = FPS, 1.0  # the FBX importer sets the scene rate
    new = [o for o in bpy.data.objects if o not in before]
    src = next(o for o in new if o.type == "ARMATURE")
    take = next(a for a in bpy.data.actions if a not in actions_before)
    src.animation_data.action = take
    if take.slots:
        src.animation_data.action_slot = take.slots[0]
    f0, f1 = take.frame_range
    names = {t: mixamo_bone(src, m) for t, m in MAP.items()}
    mw = src.matrix_world
    mx_rest = {t: (mw @ src.data.bones[s].matrix_local) for t, s in names.items()}
    mx_rest_r = {t: m.to_3x3().normalized() for t, m in mx_rest.items()}
    # Rest alignment: swing each limb bone from the toon rest direction to the Mixamo rest
    # direction, so at the Mixamo T-pose the toon bone points where the Mixamo bone points.
    align = {}
    worst = (0.0, None)
    for t, s in names.items():
        mname = s.split(":")[-1]
        if not t.startswith(ALIGNED) or t not in rig.dir_local or mname not in MX_DIR:
            align[t] = Matrix.Identity(3)
            continue
        child = mixamo_bone(src, MX_DIR[mname])
        d_mx = ((mw @ src.data.bones[child].head_local) - (mw @ src.data.bones[s].head_local)).normalized()
        d_toon = rig.direction(t, rig.rest_r[t])
        align[t] = swing(d_toon, d_mx)
        ang = math.degrees(d_toon.angle(d_mx))
        log("ALIGN %s %s %s deg=%.1f" % (stem, clip, t, ang))
        if ang > worst[0]:
            worst = (ang, t)

    def leg_len(side):
        up = mixamo_bone(src, side + "UpLeg")
        kn = mixamo_bone(src, side + "Leg")
        an = mixamo_bone(src, side + "Foot")
        h = [mw @ src.data.bones[b].head_local for b in (up, kn, an)]
        return (h[1] - h[0]).length + (h[2] - h[1]).length

    mx_leg = 0.5 * (leg_len("Left") + leg_len("Right"))
    toon_leg = 0.5 * sum(rig.length["Quad" + s] + rig.length["Shin" + s] for s in SIDES)
    scale = toon_leg / mx_leg

    n_frames = max(2, round((f1 - f0) / src_fps * FPS))
    samples = []
    for k in range(n_frames + 1):
        f = f0 + (f1 - f0) * k / n_frames
        scene.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
        smp = {}
        for t, s in names.items():
            pm = mw @ src.pose.bones[s].matrix
            smp[t] = (pm.to_3x3().normalized(), pm.translation.copy())
        for side, m in (("L", "Left"), ("R", "Right")):
            for marker, bone in (("ankle", m + "Foot"), ("toe", m + "ToeBase")):
                b = mixamo_bone(src, bone)
                smp[marker + side] = (mw @ src.pose.bones[b].head).copy()
        samples.append(smp)
    travel = samples[-1]["Hips"][1] - samples[0]["Hips"][1]
    travel.z = 0.0
    duration = n_frames / FPS
    speed = scale * travel.length / duration
    src_rest_head = {t: mx_rest[t].translation for t in names}
    src_rest_marker = {}
    for side, m in (("L", "Left"), ("R", "Right")):
        for marker, bone in (("ankle", m + "Foot"), ("toe", m + "ToeBase")):
            src_rest_marker[marker + side] = mw @ src.data.bones[mixamo_bone(src, bone)].head_local

    # Contact windows from the UNSTRIPPED source, so a target slide cannot hide itself.
    dt = duration / n_frames
    contacts = []
    for side in ("L", "R"):
        for marker in ("ankle", "toe"):
            key = marker + side
            planted = []
            for k in range(n_frames + 1):
                a, b = max(0, k - 1), min(n_frames, k + 1)
                v = (samples[b][key] - samples[a][key]).length / ((b - a) * dt)
                h = samples[k][key].z - src_rest_marker[key].z
                planted.append(v < CONTACT_SPEED_MPS and h < CONTACT_HEIGHT_M)
            k = 0
            while k <= n_frames:
                if planted[k]:
                    j = k
                    while j + 1 <= n_frames and planted[j + 1]:
                        j += 1
                    if j > k:
                        contacts.append({"marker": key, "start": k, "end": j})
                    k = j + 1
                else:
                    k += 1

    toon_marker_bone = {"ankle": "Foot", "toe": "Toes"}
    worst_clamp = 0.0
    poses = []
    def solve(drop, out):
        clamp_max = 0.0
        for k, smp in enumerate(samples):
            ramp = travel * (k / n_frames)
            rots = {}
            for t in names:
                r_mx = smp[t][0]
                rots[t] = r_mx @ mx_rest_r[t].inverted() @ align[t] @ rig.rest_r[t]
            hips = rig.rest_head["Hips"] + scale * (smp["Hips"][1] - ramp - src_rest_head["Hips"])
            hips.z -= drop
            mats = rig.fk(rots, hips)
            for s, side in ((".L", "L"), (".R", "R")):
                off = smp["ankle" + side] - ramp - src_rest_marker["ankle" + side]
                ankle = rig.rest_head["Foot" + s] + scale * off
                # While the heel is up and the ball is down (toe roll), place the ankle from
                # the ball instead, through the toon foot's own length, so the ball stays on
                # its mark. The weight is continuous, so the ankle never jumps.
                toe_off = smp["toe" + side] - ramp - src_rest_marker["toe" + side]
                toe = rig.rest_head["Toes" + s] + scale * toe_off
                heel_lift = smp["ankle" + side].z - src_rest_marker["ankle" + side].z
                toe_lift = smp["toe" + side].z - src_rest_marker["toe" + side].z
                w = min(1.0, max(0.0, heel_lift / ROLL_BAND_M)) * min(1.0, max(0.0, 1.0 - toe_lift / ROLL_BAND_M))
                foot = "Foot" + s
                foot_vec = rots[foot] @ rig.rest_r[foot].inverted() @ (rig.rest_head["Toes" + s] - rig.rest_head[foot])
                ankle = ankle.lerp(toe - foot_vec, w)
                knee_hint = mats["Shin" + s].translation
                clamp = rig.solve_limb("Quad" + s, "Shin" + s, "Foot" + s, rots, mats, ankle, knee_hint)
                clamp_max = max(clamp_max, clamp)
            out.append(rig.fk(rots, hips))
        return clamp_max

    # The toon legs are not an exact scale of the Mixamo legs, so a straight source leg
    # can overreach. Lower the pelvis by the worst overreach rather than let the IK clamp
    # pull a planted ankle off its mark.
    hips_drop = solve(0.0, [])
    hips_drop = hips_drop + 0.003 if hips_drop > 0.0 else 0.0
    worst_clamp = solve(hips_drop, poses)

    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        if a not in actions_before:
            bpy.data.actions.remove(a)

    # Contact check on the target: carry each pose forward by the reported speed and
    # require each planted marker to stay put and on the floor.
    direction = travel.normalized()
    worst_slide = 0.0
    worst_height = 0.0
    for c in contacts:
        side = "." + c["marker"][-1]
        bone = toon_marker_bone[c["marker"][:-1]] + side
        rest_z = rig.rest_head[bone].z
        pts = []
        for k in range(c["start"], c["end"] + 1):
            p = poses[k][bone].translation + direction * (speed * k * dt)
            pts.append(p)
            worst_height = max(worst_height, abs(p.z - rest_z))
        for p in pts:
            worst_slide = max(worst_slide, Vector((p.x - pts[0].x, p.y - pts[0].y)).length)
        c["bone"] = bone
        c["rest_height_m"] = rest_z
        log("WINDOW %s %s %s frames=%d..%d slide_m=%.4f height_err_m=%.4f..%.4f" % (stem, clip, bone, c["start"], c["end"], max(Vector((p.x - pts[0].x, p.y - pts[0].y)).length for p in pts), min(p.z for p in pts) - rest_z, max(p.z for p in pts) - rest_z))
    log(
        "RETARGET %s %s source=%s/%s src_frames=%.0f..%.0f src_fps=%.0f baked_frames=%d duration_s=%.4f "
        "leg_scale=%.4f rest_align_worst_deg=%.1f (%s) hips_drop_m=%.4f ik_clamp_worst_m=%.4f"
        % (stem, clip, pack, fbx, f0, f1, src_fps, n_frames + 1, duration, scale, worst[0], worst[1], hips_drop, worst_clamp)
    )
    log(
        "SPEED %s %s m_per_s=%.3f stride_travel_m=%.3f per %.4f s (source %.3f m/s unscaled)"
        % (stem, clip, speed, scale * travel.length, duration, travel.length / ((f1 - f0) / src_fps))
    )
    log(
        "CONTACT %s %s windows=%d markers=%s worst_slide_m=%.4f worst_height_err_m=%.4f"
        % (stem, clip, len(contacts), sorted({c["marker"] for c in contacts}), worst_slide, worst_height)
    )
    if worst_clamp > IK_CLAMP_TOLERANCE_M:
        raise Fail("%s %s: ankle target out of reach by %.3f m" % (stem, clip, worst_clamp))
    if not {c["marker"][-1] for c in contacts} >= {"L", "R"}:
        raise Fail("%s %s: no contact window for both feet" % (stem, clip))
    if worst_slide > CONTACT_TOLERANCE_M or worst_height > CONTACT_TOLERANCE_M:
        raise Fail("%s %s: planted foot slides %.3f m or floats %.3f m" % (stem, clip, worst_slide, worst_height))
    info = {
        "frames": n_frames,
        "duration_s": duration,
        "speed_mps": speed,
        "forward_blender": list(direction),
        "contacts": contacts,
    }
    return poses, info


# ---------------------------------------------------------------- sit, authored


def idle_start(rig, idle):
    arm = rig.arm
    arm.animation_data.action = idle
    if idle.slots:
        arm.animation_data.action_slot = idle.slots[0]
    bpy.context.scene.frame_set(int(idle.frame_range[0]))
    mats = {pb.name: pb.matrix.copy() for pb in arm.pose.bones}
    arm.animation_data.action = None
    return mats


def sit_pose(rig, stand, lean_extra=0.0, breath=0.0, head_yaw=0.0, hips_override=None):
    """The seated pose P (or a variation of it for sit_idle)."""
    s_r = {n: m.to_3x3().normalized() for n, m in stand.items()}
    rots = dict(s_r)
    rots["Hips"] = rot_x(-SIT_PELVIS_TILT_DEG) @ s_r["Hips"]
    for i, n in enumerate(("Spine_01", "Spine_02", "Spine_03")):
        rots[n] = rot_x(SIT_SPINE_LEAN_DEG + lean_extra + breath * (i + 1) / 3.0) @ s_r[n]
    yaw = Matrix.Rotation(math.radians(head_yaw), 3, "Z")
    rots["Neck"] = yaw @ rot_x(SIT_SPINE_LEAN_DEG * 0.5) @ s_r["Neck"]
    rots["Head"] = yaw @ s_r["Head"]
    # Hips placed so each thigh slopes SIT_THIGH_SLOPE_DEG below level over a vertical shin.
    slope = math.radians(SIT_THIGH_SLOPE_DEG)
    if hips_override is None:
        probe = rig.fk(rots, stand["Hips"].translation, ref_r=s_r)
        shift = Vector()
        for s in SIDES:
            ankle = stand["Foot" + s].translation
            quad_target = ankle + Vector(
                (0.0, rig.length["Quad" + s] * math.cos(slope), rig.length["Shin" + s] + rig.length["Quad" + s] * math.sin(slope))
            )
            shift += (quad_target - probe["Quad" + s].translation) * 0.5
        hips = stand["Hips"].translation + shift
    else:
        hips = hips_override
    return rots, hips


def solve_sit_limbs(rig, stand, rots, hips, fracs):
    """Legs by IK to the standing ankles, hands by IK onto the thighs. fracs holds how far
    along each thigh the hand rests: chosen once (the largest reachable) for the seated
    pose P, then reused, so breathing in sit_idle cannot make a hand hop."""
    s_r = {n: m.to_3x3().normalized() for n, m in stand.items()}
    mats = rig.fk(rots, hips, ref_r=s_r)
    clamp = 0.0
    for s in SIDES:
        ankle = stand["Foot" + s].translation
        knee_hint = mats["Quad" + s].translation + FORWARD + Vector((0.0, 0.0, 0.3))
        clamp = max(clamp, rig.solve_limb("Quad" + s, "Shin" + s, "Foot" + s, rots, mats, ankle, knee_hint))
    mats = rig.fk(rots, hips, ref_r=s_r)
    for s, out in ((".L", 1.0), (".R", -1.0)):
        quad = mats["Quad" + s].translation
        knee = mats["Shin" + s].translation
        target = None
        for frac in (fracs[s],) if s in fracs else (0.55, 0.5, 0.45, 0.4, 0.35, 0.3, 0.25, 0.2):
            t = quad + (knee - quad) * frac + Vector((out * 0.03, 0.0, 0.11))
            reach = (rig.length["Arm" + s] + rig.length["Forearm" + s]) * 0.97
            if s in fracs or (t - mats["Arm" + s].translation).length < reach:
                target = t
                fracs[s] = frac
                break
        if target is None:
            raise Fail("sit: hands cannot reach the thighs")
        hint = mats["Arm" + s].translation + Vector((out * 0.4, 0.35, -0.3))
        rots["Arm" + s] = s_r["Arm" + s]
        rots["Forearm" + s] = s_r["Forearm" + s]
        rig.solve_limb("Arm" + s, "Forearm" + s, "Hand" + s, rots, mats, target, hint)
        follow = rots["Forearm" + s] @ s_r["Forearm" + s].inverted() @ s_r["Hand" + s]
        along = (knee - quad).normalized()
        along = (along + Vector((0.0, 0.0, -0.25))).normalized()
        rots["Hand" + s] = swing(rig.direction("Hand" + s, follow), along) @ follow
        for n in list(rots):
            if s in n and n.startswith(("Fingers", "Fingertips", "Thumb")):
                del rots[n]
    return rig.fk(rots, hips, ref_r=s_r), clamp


def sit_clips(rig, stem, stand):
    s_r = {n: m.to_3x3().normalized() for n, m in stand.items()}
    p_rots, p_hips = sit_pose(rig, stand)
    fracs = {}
    p_mats, clamp = solve_sit_limbs(rig, stand, dict(p_rots), p_hips, fracs)
    p_r = {n: m.to_3x3().normalized() for n, m in p_mats.items()}
    if clamp > IK_CLAMP_TOLERANCE_M:
        raise Fail("%s sit: ankle out of reach by %.3f m" % (stem, clamp))
    first = measure_seat(rig, p_mats)
    drop = first["top"] - SEAT_TOP_M
    if drop > SEAT_FIT_TOLERANCE_M:
        p_hips = p_hips - Vector((0.0, 0.0, drop))
        fracs = {}
        p_mats, clamp = solve_sit_limbs(rig, stand, dict(p_rots), p_hips, fracs)
        p_r = {n: m.to_3x3().normalized() for n, m in p_mats.items()}
        fitted = measure_seat(rig, p_mats)["top"]
        log("SIT_FIT %s seat_top_before=%.3f after=%.3f hips_lowered_m=%.3f" % (stem, first["top"], fitted, drop))
        if clamp > IK_CLAMP_TOLERANCE_M or abs(fitted - SEAT_TOP_M) > SEAT_FIT_TOLERANCE_M:
            raise Fail("%s sit: lowered seat rests at %.3f m (clamp %.3f)" % (stem, fitted, clamp))

    down = []
    s_hips = stand["Hips"].translation
    for k in range(SIT_DOWN_FRAMES + 1):
        u = smooth(k / SIT_DOWN_FRAMES)
        bump = SIT_LEAN_BUMP_DEG * math.sin(math.pi * u)
        rots = {}
        for n in rig.order:
            if n.startswith(("Quad", "Shin")):
                continue
            rots[n] = s_r[n].to_quaternion().slerp(p_r[n].to_quaternion(), u).to_matrix()
        rots["Hips"] = rot_x(bump * 0.5) @ rots["Hips"]
        for n in ("Spine_01", "Spine_02", "Spine_03"):
            rots[n] = rot_x(bump / 3.0) @ rots[n]
        for n in ("Quad.L", "Quad.R", "Shin.L", "Shin.R"):
            rots[n] = s_r[n]
        hips = s_hips.lerp(p_hips, u)
        mats = rig.fk(rots, hips, ref_r=s_r)
        for s in SIDES:
            # The knee bends in the standing pose's own plane at the start, so frame 0 is the
            # idle's first pose exactly, and in the seated pose's plane at the end.
            hint = stand["Shin" + s].translation.lerp(p_mats["Shin" + s].translation, u)
            rig.solve_limb("Quad" + s, "Shin" + s, "Foot" + s, rots, mats, stand["Foot" + s].translation, hint)
        down.append(rig.fk(rots, hips, ref_r=s_r))

    idle_poses = []
    for k in range(SIT_IDLE_FRAMES + 1):
        w = 2.0 * math.pi * k / SIT_IDLE_FRAMES
        rots, hips = sit_pose(rig, stand, breath=SIT_BREATH_DEG * math.sin(2 * w), head_yaw=9.0 * math.sin(w), hips_override=p_hips)
        mats, _ = solve_sit_limbs(rig, stand, rots, hips, fracs)
        idle_poses.append(mats)
    seat = measure_seat(rig, p_mats)
    log(
        "SIT_CONTRACT %s seat_top_m=%.3f seat_contact_back_of_origin_m=%.3f knee_front_m=%.3f hips_drop_m=%.3f "
        "hips_back_m=%.3f (origin = the feet on the floor; the passenger faces away from the seat)"
        % (stem, seat["top"], seat["back"], seat["knee_front"], s_hips.z - p_hips.z, p_hips.y - s_hips.y)
    )
    return down, idle_poses, seat


def measure_seat(rig, mats):
    """Pose the mesh at P and measure the seat it rests on: the lowest skin under the
    pelvis and thighs, behind the knees."""
    arm = rig.arm
    ad = arm.animation_data
    action = bpy.data.actions.new("_sit_measure")
    ad.action = action
    rig.key(mats, 0, {})
    bpy.context.scene.frame_set(0)
    body = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    mesh = ev.to_mesh()
    knee_y = min(mats["Shin" + s].translation.y for s in SIDES)
    knee_z = min(mats["Shin" + s].translation.z for s in SIDES)
    hips_z = mats["Hips"].translation.z
    pts = [body.matrix_world @ v.co for v in mesh.vertices]
    # Near knee height or above and well behind the knees: the buttocks and the backs of
    # the thighs, not the calves.
    seat = [p for p in pts if p.y > knee_y + 0.2 and knee_z - 0.15 < p.z < hips_z and abs(p.x) < 0.3]
    ev.to_mesh_clear()
    ad.action = None
    bpy.data.actions.remove(action)
    if not seat:
        raise Fail("sit: no skin found over the seat")
    top = min(p.z for p in seat)
    near = [p for p in seat if p.z < top + 0.02]
    return {
        "top": top,
        "back": sum(p.y for p in near) / len(near),
        "knee_front": min(p.y for p in pts if p.z > top - 0.05),
    }


# ---------------------------------------------------------------- bake and stash


def bake(rig, name, poses):
    arm = rig.arm
    action = bpy.data.actions.new(name)
    arm.animation_data.action = action
    prev = {}
    for k, mats in enumerate(poses):
        rig.key(mats, k, prev)
    for fc in iter_fcurves(action):
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    arm.animation_data.action = None
    return action


def iter_fcurves(action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                yield from bag.fcurves


def loop_wrap(rig, poses):
    a, b = poses[0], poses[-1]
    rot = max(a[n].to_quaternion().rotation_difference(b[n].to_quaternion()).angle for n in rig.order)
    pos = max((a[n].translation - b[n].translation).length for n in rig.order)
    return rot, pos


def stash(arm, action):
    action.use_fake_user = True
    ad = arm.animation_data
    track = ad.nla_tracks.new()
    track.name = action.name
    strip = track.strips.new(action.name, int(action.frame_range[0]), action)
    if action.slots and hasattr(strip, "action_slot"):
        strip.action_slot = action.slots[0]
    track.mute = True


def clip_names(shower):
    """The clips a character carries: CLIPS, plus "shower" for a passenger body."""
    return CLIPS + (("shower",) if shower else ())


def add_clips(stem, arm, idle, shower):
    """Bake walk, run, sit_down, sit_idle and stand_up beside idle, and shower when
    shower is true (passenger bodies; staff never shower). Returns {clip: duration_s}.
    Raises Fail on any check."""
    os.makedirs(OUT_DIR, exist_ok=True)
    gender = "female" if "female" in stem else "male"
    rig = ToonRig(arm)
    if not arm.animation_data:
        arm.animation_data_create()
    # Every clip starts at time 0. The idle take starts at its source frame, which the
    # glTF export keeps as a lead-in hold that Godot would play once per loop.
    i0 = idle.frame_range[0]
    for fc in iter_fcurves(idle):
        for kp in fc.keyframe_points:
            kp.co.x -= i0
            kp.handle_left.x -= i0
            kp.handle_right.x -= i0
        fc.update()
    stand = idle_start(rig, idle)
    actions = {"idle": idle}
    report = {"stem": stem, "fps": FPS, "clips": {}}
    for clip, (pack, fbx) in SOURCES[gender].items():
        poses, info = retarget(rig, stem, clip, pack, fbx)
        rot, pos = loop_wrap(rig, poses)
        log("LOOP_WRAP %s %s max_rot_deg=%.3f max_pos_m=%.4f" % (stem, clip, math.degrees(rot), pos))
        if pos > 0.02 or math.degrees(rot) > 3.0:
            raise Fail("%s %s does not loop" % (stem, clip))
        actions[clip] = bake(rig, clip, poses)
        report["clips"][clip] = info
    down, idle_poses, seat = sit_clips(rig, stem, stand)
    start_rot = max(
        down[0][n].to_quaternion().rotation_difference(stand[n].to_quaternion()).angle for n in rig.order
    )
    start_pos = max((down[0][n].translation - stand[n].translation).length for n in rig.order)
    log("SIT_SEAM %s idle_start_vs_sit_down_start rot_deg=%.3f pos_m=%.4f" % (stem, math.degrees(start_rot), start_pos))
    if start_pos > 0.005 or math.degrees(start_rot) > 0.5:
        raise Fail("%s sit_down does not start on the idle's first pose" % stem)
    rot, pos = loop_wrap(rig, idle_poses)
    log("LOOP_WRAP %s sit_idle max_rot_deg=%.3f max_pos_m=%.4f" % (stem, math.degrees(rot), pos))
    if pos > LOOP_TOLERANCE or rot > LOOP_TOLERANCE:
        raise Fail("%s sit_idle does not loop" % stem)
    end_rot = max(
        down[-1][n].to_quaternion().rotation_difference(idle_poses[0][n].to_quaternion()).angle for n in rig.order
    )
    end_pos = max((down[-1][n].translation - idle_poses[0][n].translation).length for n in rig.order)
    log("SIT_SEAM %s sit_down_end_vs_sit_idle_start rot_deg=%.3f pos_m=%.4f" % (stem, math.degrees(end_rot), end_pos))
    if end_pos > 0.01 or math.degrees(end_rot) > 2.0:
        raise Fail("%s sit_down does not end on sit_idle" % stem)
    actions["sit_down"] = bake(rig, "sit_down", down)
    actions["sit_idle"] = bake(rig, "sit_idle", idle_poses)
    actions["stand_up"] = bake(rig, "stand_up", list(reversed(down)))
    report["clips"]["sit_down"] = {"frames": SIT_DOWN_FRAMES, "duration_s": SIT_DOWN_FRAMES / FPS}
    report["clips"]["sit_idle"] = {"frames": SIT_IDLE_FRAMES, "duration_s": SIT_IDLE_FRAMES / FPS}
    report["clips"]["stand_up"] = {"frames": SIT_DOWN_FRAMES, "duration_s": SIT_DOWN_FRAMES / FPS}
    clips = clip_names(shower)
    if shower:
        import toon_shower  # noqa: E402 (it imports this module)

        poses, report["clips"]["shower"] = toon_shower.shower_clip(rig, stem, stand)
        actions["shower"] = bake(rig, "shower", poses)
    i0, i1 = idle.frame_range
    report["clips"]["idle"] = {"frames": int(i1 - i0), "duration_s": (i1 - i0) / FPS}
    report["seat"] = seat
    report["looping"] = [c for c in LOOPING if c in clips]
    for clip in clips:
        stash(arm, actions[clip])
    arm.animation_data.action = None
    with open(os.path.join(OUT_DIR, stem + "_clips.json"), "w", newline="\n") as f:
        json.dump(report, f, indent=1)
    return {c: report["clips"][c]["duration_s"] for c in clips}
