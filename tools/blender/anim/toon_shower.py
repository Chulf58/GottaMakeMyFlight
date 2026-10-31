"""The "shower" clip for the Toon City People characters, authored on the toon rig.

Called by toon_clips.add_clips with the idle's first pose. No pack has a washing clip,
so this one is authored the way the sit clips are: torso rotations on top of the idle's
first pose, legs by two-bone IK to the idle's planted ankles, arms by two-bone IK.

One loop of SHOWER_FRAMES at 25 fps: both hands lather the hair (elbows up), slide back
over the crown while the head tilts back under the water, go round the head to scrub
each its own shoulder, then the back of the head behind the ears with the elbows up,
then both hands scrub the chest and the belly and go back up to the hair. No hand
reaches across the body. The hips sway once per loop.

Where a hand touches the body, its target comes from the body's own skin: a ray is cast
onto the posed mesh of the idle's first pose, in the local frame of the bone that carries
that skin, so the target follows the head when it tilts. The palm faces the skin and sits
a clearance off it. A fitting pass then pushes each hand off the skin until the skinned
hand no longer intersects the head, the torso or the other arm, and smooths the pushes
over time. Hands below the shoulders stay near SHOWER_RADIUS_MAX_M of the body's centre
line, inside the shower foam column. The clip stops the run on a moving foot, an arm out
of reach, a hand intersecting the body, a hand leaving the column or a loop that does not
close.
"""

import math

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

import toon_clips as tc

SHOWER_FRAMES = 125
PERIOD_S = SHOWER_FRAMES / tc.FPS
SHOWER_PALM_CLEAR_M = 0.032  # wrist off the hair; the curled fingers reach down onto it
TORSO_CLEAR_M = 0.055  # flat fingers on the chest and belly, the thumb below the palm
ARM_CLEAR_M = 0.036
SHOWER_RADIUS_MAX_M = 0.30
SHOWER_HIPS_DROP_M = 0.012
SHOWER_SWAY_M = 0.018
SCRUB_HZ = 2.0  # an integer number of scrubs per loop, so the loop closes
FINGER_CURL_DEG = 12.0
THUMB_TUCK_DEG = 35.0
ARM_CLAMP_TOLERANCE_M = 0.02
SHOWER_RADIUS_FAIL_M = SHOWER_RADIUS_MAX_M + 0.05
# A hand that still touches the skin is pushed off it (against its palm) in steps, up
# to PUSH_MAX_M, and the pushes are smoothed over PUSH_SMOOTH_FRAMES either side.
PUSH_STEP_M = 0.005
PUSH_MAX_M = 0.10
PUSH_SMOOTH_FRAMES = 4
NUDGE_STEPS = 8  # after smoothing, at most 8 x PUSH_STEP_M more on a frame that still touches

HEAD = ("Head",)
TORSO = ("Hips", "Spine_01", "Spine_02", "Spine_03", "Neck", "Clavicle.L", "Clavicle.R")


def rot_axis(axis, deg):
    return Matrix.Rotation(math.radians(deg), 3, axis)


def cyc(keys, t, stops=None):
    """Cyclic cubic Hermite through (time, value) keys over one PERIOD_S. Tangents are
    Catmull-Rom, or zero at a key whose stops entry is True (a hold, so the curve never
    overshoots between two equal keys)."""
    n = len(keys)
    t = t % PERIOD_S
    i = max(k for k in range(n) if keys[k][0] <= t) if t >= keys[0][0] else n - 1

    def at(k):
        tk, v = keys[k % n]
        return tk + PERIOD_S * (k // n), v

    t0, p0 = at(i)
    t1, p1 = at(i + 1)
    if t < t0:
        t += PERIOD_S
    tm, pm = at(i - 1)
    t2, p2 = at(i + 2)
    dt = t1 - t0
    u = (t - t0) / dt

    def tangent(k, ta, pa, tb, pb):
        if stops and stops[k % n]:
            return pa * 0.0
        return (pb - pa) * (1.0 / (tb - ta))

    m0 = tangent(i, tm, pm, t1, p1)
    m1 = tangent(i + 1, t0, p0, t2, p2)
    h00 = 2 * u ** 3 - 3 * u ** 2 + 1
    h10 = u ** 3 - 2 * u ** 2 + u
    h01 = -2 * u ** 3 + 3 * u ** 2
    h11 = u ** 3 - u ** 2
    return p0 * h00 + m0 * (h10 * dt) + p1 * h01 + m1 * (h11 * dt)


def segment(keys, t):
    """Index of the key at or before t, and the eased fraction to the next key."""
    n = len(keys)
    t = t % PERIOD_S
    i = max(k for k in range(n) if keys[k][0] <= t) if t >= keys[0][0] else n - 1
    t0 = keys[i][0]
    t1 = keys[(i + 1) % n][0] + (PERIOD_S if i + 1 >= n else 0.0)
    if t < t0:
        t += PERIOD_S
    return i, tc.smooth((t - t0) / (t1 - t0))


class Skin:
    """The skinned mesh: BVH trees of the idle's first pose in bone-local frames (for the
    hand targets), and the hand-against-body intersection test of any pose."""

    def __init__(self, rig, stand):
        self.rig = rig
        self.action = bpy.data.actions.new("_shower_measure")
        rig.arm.animation_data.action = self.action
        self.body = next(o for o in bpy.context.scene.objects if o.type == "MESH")
        names = {g.index: g.name for g in self.body.vertex_groups}
        self.group = []
        for v in self.body.data.vertices:
            g = max(v.groups, key=lambda g: g.weight) if v.groups else None
            self.group.append(names[g.group] if g else None)
        self.verts = self.posed(stand)
        self.polys = [tuple(p.vertices) for p in self.body.data.polygons]
        self.stand = stand
        self.trees = {}
        self.hand_polys = {}
        self.obstacle_polys = {}
        for s, o in ((".L", ".R"), (".R", ".L")):
            hand = {n + s for n in ("Hand", "Fingers", "Fingertips", "Thumb", "Thumb_Tip")}
            # The head, the torso and the other arm: everything a hand may touch but not enter.
            solid = set(HEAD + TORSO) | {"Arm" + o, "Forearm" + o}
            self.hand_polys[s] = [p for p in self.polys if any(self.group[i] in hand for i in p)]
            self.obstacle_polys[s] = [p for p in self.polys if any(self.group[i] in solid for i in p)]

    def posed(self, mats):
        self.rig.key(mats, 0, {})
        bpy.context.scene.frame_set(0)
        dg = bpy.context.evaluated_depsgraph_get()
        ev = self.body.evaluated_get(dg)
        mesh = ev.to_mesh()
        verts = [self.body.matrix_world @ v.co for v in mesh.vertices]
        ev.to_mesh_clear()
        return verts

    def hand_hits(self, mats):
        """Per hand, how many hand triangles intersect the head, torso or the other arm."""
        verts = self.posed(mats)
        out = {}
        self.last_hit = {}
        for s in tc.SIDES:
            hand = BVHTree.FromPolygons(verts, self.hand_polys[s])
            solid = BVHTree.FromPolygons(verts, self.obstacle_polys[s])
            pairs = hand.overlap(solid)
            out[s] = len(pairs)
            # Which bones' skin the hand enters, for the fit log.
            self.last_hit[s] = sorted({self.group[i] for _a, b in pairs for i in self.obstacle_polys[s][b]} - {None})
        return out

    def close(self):
        self.rig.arm.animation_data.action = None
        bpy.data.actions.remove(self.action)

    def tree(self, bone, groups):
        key = (bone, groups)
        if key not in self.trees:
            inv = self.stand[bone].inverted()
            polys = [p for p in self.polys if any(self.group[i] in groups for i in p)]
            if not polys:
                raise tc.Fail("shower: no skin for %s" % (groups,))
            used = sorted({i for p in polys for i in p})
            index = {v: k for k, v in enumerate(used)}
            verts = [inv @ self.verts[i] for i in used]
            self.trees[key] = BVHTree.FromPolygons(verts, [tuple(index[i] for i in p) for p in polys])
        return self.trees[key]

    def bounds(self, groups):
        pts = [self.verts[i] for i, g in enumerate(self.group) if g in groups]
        lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
        hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
        return lo, hi


class Touch:
    """A hand key on the skin: a ray cast onto the skin of one bone. The ray and the finger
    direction are given in the stand world and carried by the bone, or, with world=True,
    stay fixed in the world (a hand coming from above onto a forearm the pose has turned)."""

    def __init__(self, skin, bone, groups, inner, ray, fingers, scrub, hint, clear=SHOWER_PALM_CLEAR_M, curl=0.0, world=False, normal_weight=0.0):
        inv = skin.stand[bone].inverted()
        self.bone = bone
        self.clear = clear
        self.curl = curl  # fingers curl onto a round surface (the head), not a flat one
        self.tree = skin.tree(bone, groups)
        self.inner = inv @ inner
        self.world = world
        self.normal_weight = normal_weight
        rot = Matrix.Identity(3) if world else inv.to_3x3()
        self.ray = (rot @ ray).normalized()
        self.fingers = rot @ fingers
        self.scrub = scrub
        self.hint = hint  # offset from the shoulder (Arm bone head), stand world
        self.stop = True
        if not world:
            # A body with a gap in its skin there (between clothing parts) gets the key
            # moved towards the bone until the whole scrub circle lands on skin, once, so
            # the hand never jumps between frames.
            a = self.ray.orthogonal().normalized()
            b = self.ray.cross(a).normalized()
            ring = [(a * math.cos(w) + b * math.sin(w)) * scrub for w in (math.tau * i / 16 for i in range(16))]
            for pull in (1.0, 0.8, 0.6, 0.4, 0.2):
                p = self.inner * pull
                if all(self.tree.ray_cast(p + d - self.ray * 0.6, self.ray, 1.0)[0] is not None for d in ring):
                    self.inner = p
                    break

    def place(self, rig, mats, side, t, phase):
        m = mats[self.bone]
        rot = m.to_3x3().normalized()
        ray = rot.inverted() @ self.ray if self.world else self.ray
        w = 2.0 * math.pi * SCRUB_HZ * t + phase
        a = ray.orthogonal().normalized()
        b = ray.cross(a).normalized()
        inner = self.inner + (a * math.cos(w) + b * math.sin(w)) * self.scrub
        hit, normal, _i, _d = self.tree.ray_cast(inner - ray * 0.6, ray, 1.0)
        if hit is None:
            raise tc.Fail("shower: a hand ray on %s misses the skin" % self.bone)
        # The palm faces between the ray and the hit face's normal. The normal alone can
        # turn sideways from one frame to the next on a hair strand's edge; the ray alone
        # tilts the hand into a sloped surface.
        n = -(rot @ ray).normalized()
        face = (rot @ normal).normalized()
        if face.dot(n) > 0.2:
            n = (n * (1.0 - self.normal_weight) + face * self.normal_weight).normalized()
        f = self.fingers if self.world else rot @ self.fingers
        f = (f - n * f.dot(n)).normalized()
        reach = rig.length["Hand" + side] * 0.6
        wrist = (m @ hit) + n * self.clear - f * reach
        return wrist, f, -n, mats["Arm" + side].translation + self.hint


class Free:
    """A hand key in the air, given in the stand world and carried by the hips."""

    def __init__(self, stand, pos, fingers, palm, hint, stop=False):
        self.rel = pos - stand["Hips"].translation
        self.fingers = fingers.normalized()
        self.palm = (palm - self.fingers * palm.dot(self.fingers)).normalized()
        self.hint = hint
        self.scrub = 0.0
        self.curl = 0.0
        self.stop = stop

    def place(self, rig, mats, side, t, phase):
        return mats["Hips"].translation + self.rel, self.fingers, self.palm, mats["Arm" + side].translation + self.hint


def palm_local(rig, skin, stand, side):
    """The palm normal in the Hand bone's frame, from the mesh: the hand's thinnest axis
    (the idle's hands are turned differently, so no fixed axis fits both), signed to the
    side the thumb tip sits on."""
    name = "Hand" + side
    inv = stand[name].inverted()
    pts = [inv @ skin.verts[i] for i, g in enumerate(skin.group) if g == name]
    thumb = [inv @ skin.verts[i] for i, g in enumerate(skin.group) if g == "Thumb_Tip" + side]
    if len(pts) < 8 or not thumb:
        raise tc.Fail("shower: %s has too little mesh to find the palm" % name)
    d_l = rig.dir_local[name]
    c = sum(pts, Vector()) / len(pts)
    best = None
    for k in range(180):
        a = math.pi * k / 180.0
        e = d_l.orthogonal().normalized()
        n = (e * math.cos(a) + d_l.cross(e).normalized() * math.sin(a)).normalized()
        spread = sum(((p - c).dot(n)) ** 2 for p in pts)
        if best is None or spread < best[0]:
            best = (spread, n)
    n = best[1]
    if (sum(thumb, Vector()) / len(thumb) - c).dot(n) < 0.0:
        n = -n
    return n


def hand_rot(rig, side, p_l, f, palm):
    """The world rotation of a Hand bone whose fingers point along f with the palm to palm."""
    d_l = rig.dir_local["Hand" + side]
    bl = Matrix((d_l, p_l, d_l.cross(p_l).normalized())).transposed()
    palm = (palm - f * palm.dot(f)).normalized()
    bw = Matrix((f, palm, f.cross(palm).normalized())).transposed()
    return bw @ bl.transposed()


def build_tracks(rig, skin, stand):
    """Per hand: [(time_s, key)], one loop."""
    hips = stand["Hips"].translation
    head_lo, head_hi = skin.bounds(HEAD)
    torso_lo, _ = skin.bounds(("Spine_02",))
    shoulder_z = 0.5 * (stand["Arm.L"].translation.z + stand["Arm.R"].translation.z)
    chest_y = torso_lo.y
    centre = (head_lo + head_hi) * 0.5
    centre.y = min(max(centre.y, stand["Head"].translation.y - 0.05), stand["Head"].translation.y + 0.05)
    tracks = {}
    for side, out in ((".L", 1.0), (".R", -1.0)):

        def hair(dx, dy, dz, scrub):
            d = Vector((dx * out, dy, dz)).normalized()
            fingers = Vector((-out, 0.25, 0.6))
            hint = Vector((out * 0.45, -0.10, 0.12))
            return Touch(skin, "Head", HEAD, centre, -d, fingers, scrub, hint, curl=FINGER_CURL_DEG, normal_weight=0.7)

        def chest(z_up, scrub):
            inner = stand["Spine_02"].translation + Vector((out * 0.095, 0.05, z_up))
            return Touch(skin, "Spine_02", TORSO, inner, Vector((0.0, 1.0, 0.0)), Vector((-out * 0.15, 0.0, 1.0)), scrub, Vector((out * 0.42, -0.12, -0.30)), clear=TORSO_CLEAR_M)

        def belly(scrub):
            inner = stand["Spine_01"].translation + Vector((out * 0.09, 0.05, 0.03))
            return Touch(skin, "Spine_01", TORSO, inner, Vector((0.0, 1.0, 0.0)), Vector((-out * 0.6, 0.0, 0.6)), scrub, Vector((out * 0.45, -0.15, -0.28)), clear=TORSO_CLEAR_M)

        def free(pos, fingers, palm, hint, stop=False):
            return Free(stand, pos, fingers, palm, hint, stop)

        # Beside the head and beside the jaw: the hands go round the head, never through it.
        by_head = free(
            Vector((centre.x + out * 0.30, centre.y, centre.z - 0.02)),
            Vector((-out * 0.2, 0.2, 1.0)),
            Vector((-out, 0.0, 0.0)),
            Vector((out * 0.45, 0.0, -0.05)),
        )
        by_jaw = free(
            Vector((hips.x + out * 0.26, centre.y - 0.14, shoulder_z + 0.10)),
            Vector((-out * 0.3, 0.0, 1.0)),
            Vector((-out, 0.3, 0.0)),
            Vector((out * 0.40, 0.0, -0.20)),
        )
        keys = [
            (0.00, hair(0.55, 0.0, 0.85, 0.030)),
            (0.95, hair(0.55, 0.05, 0.85, 0.030)),
            (1.35, hair(0.42, 0.45, 0.80, 0.015)),
            (1.90, hair(0.42, 0.50, 0.78, 0.004)),
            (2.12, by_head),
        ]
        # Each hand on its own side only (no reach across the chest): the top of its own
        # shoulder and the side of the neck, then the back of the neck with the elbow up.
        own_shoulder = Touch(
            skin, "Clavicle" + side, ("Clavicle" + side, "Arm" + side, "Spine_03", "Neck"),
            stand["Arm" + side].translation + Vector((-out * 0.03, 0.0, -0.02)), Vector((0.0, 1.0, -0.6)),
            Vector((out, 0.0, 0.3)), 0.02, Vector((out * 0.30, -0.30, -0.15)), clear=ARM_CLEAR_M,
        )
        nape = Touch(
            skin, "Head", HEAD + ("Neck",), Vector((centre.x, centre.y, centre.z)),
            -Vector((out * 0.8, 0.6, -0.1)), Vector((-out * 0.1, 0.3, 1.0)), 0.010, Vector((out * 0.45, 0.0, 0.18)), clear=ARM_CLEAR_M,
        )
        behind_ear = free(
            Vector((centre.x + out * 0.28, centre.y + 0.10, centre.z - 0.08)),
            Vector((-out * 0.2, 0.0, 1.0)),
            Vector((-out, -0.5, 0.0)),
            Vector((out * 0.45, 0.0, 0.10)),
        )
        keys += [
            (2.38, own_shoulder),
            (2.80, own_shoulder),
            (2.93, behind_ear),
            (3.10, nape),
            (3.40, nape),
            (3.52, behind_ear),
            (3.65, by_jaw),
        ]
        keys += [
            (3.80, chest(0.0, 0.025)),
            (4.05, chest(-0.03, 0.025)),
            (4.25, belly(0.022)),
            (4.50, belly(0.022)),
            (4.63, free(Vector((hips.x + out * 0.17, chest_y - 0.07, hips.z + 0.32)), Vector((-out * 0.2, 0.0, 1.0)), Vector((-out * 0.3, 1.0, 0.0)), Vector((out * 0.42, 0.0, -0.25)))),
            (4.75, by_jaw),
            (4.86, by_head),
        ]
        tracks[side] = keys
    return tracks


def scalar_keys():
    """Torso deltas in degrees and the hips' scrub bounce, one loop."""
    head_pitch = [(0.0, 0.0), (1.05, 0.0), (1.6, -22.0), (2.1, -4.0), (2.55, 14.0), (3.4, 14.0), (3.75, 10.0), (4.4, 15.0), (4.8, 0.0)]
    # A small head roll from side to side while the hands scrub the shoulders and neck.
    head_yaw = [(0.0, 0.0), (2.3, 0.0), (2.6, 4.0), (3.0, -4.0), (3.4, 2.0), (3.7, 0.0)]
    spine_pitch = [(0.0, 1.0), (1.05, 1.0), (1.6, -4.0), (2.1, 0.0), (3.0, 2.0), (4.4, 5.0), (4.8, 1.0)]
    spine_yaw = [(0.0, 0.0), (2.5, 0.0)]
    bounce = [(0.0, 1.0), (1.0, 1.0), (1.35, 0.0), (3.6, 0.0), (3.8, 0.7), (4.5, 0.7), (4.75, 0.3)]
    return head_pitch, head_yaw, spine_pitch, spine_yaw, bounce



def solve_frame(rig, stand, s_r, tracks, curves, palms, k, push):
    """The pose at frame k. push holds, per hand, how far the wrist is moved off the skin
    (against the palm) beyond its key. Returns (mats, {side: away}, clamps)."""
    head_pitch, head_yaw, spine_pitch, spine_yaw, bounce = curves
    t = PERIOD_S * k / SHOWER_FRAMES
    bob = cyc(bounce, t) * math.sin(2.0 * math.pi * 2.0 * SCRUB_HZ * t)
    sway = math.sin(2.0 * math.pi * t / PERIOD_S)
    hips = stand["Hips"].translation + Vector((SHOWER_SWAY_M * sway, 0.0, -SHOWER_HIPS_DROP_M + 0.004 * bob))
    rots = dict(s_r)
    rots["Hips"] = rot_axis("Y", 2.5 * sway) @ s_r["Hips"]
    sp, sy = cyc(spine_pitch, t), cyc(spine_yaw, t)
    for i, n in enumerate(("Spine_01", "Spine_02", "Spine_03")):
        share = (i + 1) / 3.0
        rots[n] = rot_axis("Z", sy * share) @ tc.rot_x(sp * share) @ rot_axis("Y", -2.5 * sway * share) @ s_r[n]
    chest_delta = rots["Spine_03"] @ s_r["Spine_03"].inverted()
    for s in tc.SIDES:
        rots["Clavicle" + s] = chest_delta @ s_r["Clavicle" + s]
    hp, hy = cyc(head_pitch, t) + 2.5 * bob, cyc(head_yaw, t)
    rots["Neck"] = rot_axis("Z", 0.4 * hy) @ tc.rot_x(0.4 * hp) @ rot_axis("Z", sy) @ tc.rot_x(sp) @ s_r["Neck"]
    rots["Head"] = rot_axis("Z", hy) @ tc.rot_x(hp) @ rot_axis("Z", sy) @ tc.rot_x(sp) @ s_r["Head"]
    mats = rig.fk(rots, hips, ref_r=s_r)
    clamps = {"leg": 0.0, "arm": 0.0}
    for s in tc.SIDES:
        c = rig.solve_limb("Quad" + s, "Shin" + s, "Foot" + s, rots, mats, stand["Foot" + s].translation, mats["Shin" + s].translation)
        clamps["leg"] = max(clamps["leg"], c)
    mats = rig.fk(rots, hips, ref_r=s_r)
    away = {}
    for s, phase in ((".L", 0.0), (".R", math.pi)):
        keys = tracks[s]
        n_keys = len(keys)
        i, u = segment(keys, t)
        near = [keys[(i + j) % n_keys] for j in (-1, 0, 1, 2)]
        placed = [key.place(rig, mats, s, t, phase) for _tk, key in near]
        pts = [(tk + PERIOD_S * ((i + j) // n_keys), p[0]) for (tk, _key), p, j in zip(near, placed, (-1, 0, 1, 2))]
        wrist = hermite4(pts, [key.stop for _tk, key in near], t % PERIOD_S)
        r0 = hand_rot(rig, s, palms[s], placed[1][1], placed[1][2]).to_quaternion()
        r1 = hand_rot(rig, s, palms[s], placed[2][1], placed[2][2]).to_quaternion()
        r1.make_compatible(r0)
        r_hand = r0.slerp(r1, u).to_matrix()
        palm = r_hand @ palms[s]
        away[s] = -palm
        wrist = wrist + away[s] * push[s]
        hint = placed[1][3].lerp(placed[2][3], u)
        rots["Arm" + s] = s_r["Arm" + s]
        rots["Forearm" + s] = s_r["Forearm" + s]
        c = rig.solve_limb("Arm" + s, "Forearm" + s, "Hand" + s, rots, mats, wrist, hint)
        clamps["arm"] = max(clamps["arm"], c)
        rots["Hand" + s] = r_hand
        axis = (r_hand @ rig.dir_local["Hand" + s]).cross(palm).normalized()
        for n in list(rots):
            if s in n and n.startswith(("Fingers", "Fingertips", "Thumb")):
                del rots[n]
        mats = rig.fk(rots, hips, ref_r=s_r)
        bend = near[1][1].curl + (near[2][1].curl - near[1][1].curl) * u
        for n, curl in (("Fingers" + s, bend), ("Fingertips" + s, 2.0 * bend)):
            rots[n] = Matrix.Rotation(math.radians(curl), 3, axis) @ mats[n].to_3x3().normalized()
        # The relaxed thumb sticks out on the palm side; tuck it towards the palm plane.
        thumb = "Thumb" + s
        t_dir = rig.direction(thumb, mats[thumb].to_3x3().normalized())
        t_axis = t_dir.cross(palm)
        if t_axis.length > 1e-4:
            rots[thumb] = Matrix.Rotation(math.radians(-THUMB_TUCK_DEG), 3, t_axis.normalized()) @ mats[thumb].to_3x3().normalized()
    return rig.fk(rots, hips, ref_r=s_r), away, clamps


def cyclic_smooth(values, reach):
    """A cyclic max filter, then a cyclic box average, over +-reach frames: never below
    the input and without steps."""
    n = len(values)
    peak = [max(values[(k + d) % n] for d in range(-reach, reach + 1)) for k in range(n)]
    return [sum(peak[(k + d) % n] for d in range(-reach, reach + 1)) / (2 * reach + 1) for k in range(n)]


def shower_clip(rig, stem, stand):
    """Poses for one loop (SHOWER_FRAMES + 1, the last equal to the first).

    Pass 1 poses every frame from the keys and pushes each hand off the skin, 5 mm at a
    time, until the skinned hand no longer intersects the head, the torso or the other
    arm. Pass 2 smooths the pushes over time, so a hand never jumps, and poses again."""
    s_r = {n: m.to_3x3().normalized() for n, m in stand.items()}
    skin = Skin(rig, stand)
    tracks = build_tracks(rig, skin, stand)
    curves = scalar_keys()
    palms = {s: palm_local(rig, skin, stand, s) for s in tc.SIDES}
    tc.log("SHOWER_PALM %s L=%s R=%s" % (stem, tuple(round(v, 3) for v in palms[".L"]), tuple(round(v, 3) for v in palms[".R"])))
    pushes = {s: [0.0] * SHOWER_FRAMES for s in tc.SIDES}
    for k in range(SHOWER_FRAMES):
        push = {s: 0.0 for s in tc.SIDES}
        first = None
        while True:
            mats, _away, _c = solve_frame(rig, stand, s_r, tracks, curves, palms, k, push)
            hits = skin.hand_hits(mats)
            first = first or dict(hits)
            grow = [s for s in tc.SIDES if hits[s] and push[s] < PUSH_MAX_M]
            if not grow:
                break
            for s in grow:
                push[s] += PUSH_STEP_M
        for s in tc.SIDES:
            pushes[s][k] = push[s]
        if any(first.values()):
            tc.log(
                "SHOWER_FIT %s frame=%d hits_before L=%d R=%d push_m L=%.3f R=%.3f hits_after L=%d R=%d into=%s"
                % (stem, k, first[".L"], first[".R"], push[".L"], push[".R"], hits[".L"], hits[".R"], skin.last_hit)
            )
    for s in tc.SIDES:
        pushes[s] = cyclic_smooth(pushes[s], PUSH_SMOOTH_FRAMES)
    poses = []
    worst = {"leg_clamp": 0.0, "arm_clamp": 0.0, "radius": 0.0, "hits": 0, "hit_frames": 0}
    for k in range(SHOWER_FRAMES + 1):
        f = k % SHOWER_FRAMES
        push = {s: pushes[s][f] for s in tc.SIDES}
        mats, _away, clamps = solve_frame(rig, stand, s_r, tracks, curves, palms, k, push)
        hits = skin.hand_hits(mats)
        # A smoothed push can land a hand on other skin; nudge it on, a few mm at most.
        for _step in range(NUDGE_STEPS):
            if not any(hits.values()):
                break
            push = {s: push[s] + (PUSH_STEP_M if hits[s] else 0.0) for s in tc.SIDES}
            mats, _away, clamps = solve_frame(rig, stand, s_r, tracks, curves, palms, k, push)
            hits = skin.hand_hits(mats)
        worst["leg_clamp"] = max(worst["leg_clamp"], clamps["leg"])
        worst["arm_clamp"] = max(worst["arm_clamp"], clamps["arm"])
        worst["hits"] = max(worst["hits"], max(hits.values()))
        worst["hit_frames"] += 1 if any(hits.values()) else 0
        hips = mats["Hips"].translation
        for s in tc.SIDES:
            for n in ("Hand" + s, "Fingertips" + s):
                p = mats[n].translation
                r = Vector((p.x - hips.x, p.y - hips.y)).length
                if p.z < mats["Arm" + s].translation.z and r > worst["radius"]:
                    worst["radius"], worst["radius_at"] = r, "%s@%d" % (n, k)
        poses.append(mats)
    skin.close()
    slide = max((poses[k]["Foot" + s].translation - stand["Foot" + s].translation).length for k in range(len(poses)) for s in tc.SIDES)
    rot, pos = tc.loop_wrap(rig, poses)
    tc.log(
        "SHOWER %s frames=%d duration_s=%.3f leg_clamp_m=%.4f arm_clamp_m=%.4f foot_slide_m=%.5f "
        "hand_radius_below_shoulder_max_m=%.3f (%s) push_max_m L=%.3f R=%.3f hand_skin_hits_max=%d frames_with_hits=%d "
        "loop_rot_deg=%.4f loop_pos_m=%.5f"
        % (
            stem, SHOWER_FRAMES, PERIOD_S, worst["leg_clamp"], worst["arm_clamp"], slide, worst["radius"], worst.get("radius_at"),
            max(pushes[".L"]), max(pushes[".R"]), worst["hits"], worst["hit_frames"], math.degrees(rot), pos,
        )
    )
    if worst["leg_clamp"] > tc.IK_CLAMP_TOLERANCE_M or slide > 0.005:
        raise tc.Fail("%s shower: a planted foot moves (clamp %.3f, slide %.3f)" % (stem, worst["leg_clamp"], slide))
    if worst["arm_clamp"] > ARM_CLAMP_TOLERANCE_M:
        raise tc.Fail("%s shower: a hand target is out of reach by %.3f m" % (stem, worst["arm_clamp"]))
    if worst["radius"] > SHOWER_RADIUS_FAIL_M:
        raise tc.Fail("%s shower: a hand leaves the foam column (%.3f m)" % (stem, worst["radius"]))
    if worst["hits"]:
        raise tc.Fail("%s shower: a hand intersects the body (%d triangles)" % (stem, worst["hits"]))
    if pos > tc.LOOP_TOLERANCE or rot > tc.LOOP_TOLERANCE:
        raise tc.Fail("%s shower does not loop" % stem)
    return poses, {"frames": SHOWER_FRAMES, "duration_s": PERIOD_S, "hand_radius_max_m": worst["radius"]}



def hermite4(pts, stops, t):
    """Cubic Hermite between pts[1] and pts[2] (each (time, Vector)), Catmull-Rom
    tangents, zero at a stop key."""
    (tm, pm), (t0, p0), (t1, p1), (t2, p2) = pts
    if t < t0:
        t += PERIOD_S
    dt = t1 - t0
    u = (t - t0) / dt
    m0 = Vector() if stops[1] else (p1 - pm) / (t1 - tm)
    m1 = Vector() if stops[2] else (p2 - p0) / (t2 - t0)
    h00 = 2 * u ** 3 - 3 * u ** 2 + 1
    h10 = u ** 3 - 2 * u ** 2 + u
    h01 = -2 * u ** 3 + 3 * u ** 2
    h11 = u ** 3 - u ** 2
    return p0 * h00 + m0 * (h10 * dt) + p1 * h01 + m1 * (h11 * dt)
