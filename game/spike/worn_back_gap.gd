extends RefCounted
## How far a worn backpack's back panel stands off the body it is worn on
## (anti-pattern the-worn-backpack-float-check-passes-a-backpack-hanging-in-t,
## board 4af10dd0): the body's own vertices (skinned by hand, so headless runs
## read the same pose as windowed ones) that lie behind the panel, inside its
## outline, and the least distance from them to the panel's face (the pack's
## y 0 face, CarryWorn.worn_back()). Measured against the body mesh, never
## against a placement constant, so a pack placed wrong cannot move its own
## yardstick. Load with preload(); no class_name.

## A worn pack this close to the back reads as resting on it (its straps
## implied by the contact).
const WORN_GAP_M := 0.03
## Vertices owned mostly by these bones (by name, either side) are left out:
## arms and legs swing past the pack's sides and are not the back it rests on.
const LIMBS: Array[String] = ["Quad", "Shin", "Foot", "Toes", "Arm", "Forearm", "Hand"]
const LIMB_TIPS: Array[String] = ["Fingers", "Fingertips", "Thumb", "Thumb_Tip"]

## Mesh instance id -> [vertices, bones, weights, influences per vertex] of
## its vertices not owned by a limb.
static var _torso := {}


## The panel gap of a pack drawn at `bag_xf` (world, its scale included) on
## the body points `points` (world): [the least distance (m) from a point
## behind the panel inside its outline to the panel's face (negative when a
## point is through it), the point, how many points were inside the
## outline]. INF when none is. `grow` (m) widens the outline on every side, so
## a vertex that moves along its edge (a shoulder at the pack's top corner) is
## counted on both sides of it.
static func panel_gap(points: PackedVector3Array, bag_xf: Transform3D, grow := 0.0) -> Array:
	var box := CarryOnProps.bag_box(SecurityLooks.Kind.BACKPACK)
	var to_bag := bag_xf.affine_inverse()
	var scale_by := bag_xf.basis.get_scale().y
	var wider := grow / scale_by
	box = AABB(box.position - Vector3(wider, 0.0, wider), box.size + Vector3(wider, 0.0, wider) * 2.0)
	var best := INF
	var at := Vector3.ZERO
	var seen := 0
	for p in points:
		var local := to_bag * p
		if local.x < box.position.x or local.x > box.end.x:
			continue
		if local.z < box.position.z or local.z > box.end.z or local.y > box.end.y:
			continue
		seen += 1
		var gap := (box.position.y - local.y) * scale_by
		if gap < best:
			best = gap
			at = p
	return [best, at, seen]


## The world points of `body`'s back as drawn now: its body mesh's vertices
## not owned by a limb, skinned by hand from its skeleton's pose. When the
## body carries a carry rig (CarryOnProps._rig()), they are moved with its
## Spine_03 attachment as drawn (with CarryStoop's bend, which the skeleton's
## own pose may not hold).
static func back_points(body: Node3D) -> PackedVector3Array:
	var mi := PassengerLooks.body_mesh(body)
	var out := PackedVector3Array()
	if mi == null or mi.skin == null:
		return out
	var skeleton := mi.get_node(mi.skeleton) as Skeleton3D
	var to_world := skeleton.global_transform
	var rig: Dictionary = body.get_meta(&"carry_rig", {})
	if rig.has("spine"):
		var bone := skeleton.find_bone(CarryOnProps.SPINE_BONE)
		var posed := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
		to_world = (rig["spine"] as Node3D).global_transform * posed.affine_inverse() * to_world
	var mats: Array[Transform3D] = []
	for bind in mi.skin.get_bind_count():
		var name := mi.skin.get_bind_name(bind)
		var bone := skeleton.find_bone(name) if name != "" else mi.skin.get_bind_bone(bind)
		mats.append(to_world * skeleton.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bind))
	var torso := _torso_of(mi, skeleton)
	var verts: PackedVector3Array = torso[0]
	var bones: PackedInt32Array = torso[1]
	var weights: PackedFloat32Array = torso[2]
	var per: int = torso[3]
	out.resize(verts.size())
	for k in verts.size():
		var v := Vector3.ZERO
		for j in per:
			var w := weights[k * per + j]
			if w > 0.0:
				v += (mats[bones[k * per + j]] * verts[k]) * w
		out[k] = v
	return out


## The panel gap (panel_gap()) of `bag`, a backpack worn on `body`, as drawn.
static func gap(body: Node3D, bag: Node3D) -> Array:
	return panel_gap(back_points(body), bag.global_transform)


## [vertices, bones, weights, per] of `mi`'s mesh, limbs left out (cached).
static func _torso_of(mi: MeshInstance3D, skeleton: Skeleton3D) -> Array:
	var key := mi.mesh.get_instance_id()
	if _torso.has(key):
		return _torso[key]
	var limb := {}
	for bind in mi.skin.get_bind_count():
		var name := mi.skin.get_bind_name(bind)
		if name == "":
			name = skeleton.get_bone_name(mi.skin.get_bind_bone(bind))
		var part := name.get_slice(".", 0)
		if part in LIMBS or part in LIMB_TIPS:
			limb[bind] = true
	var verts := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var per := 4
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bs: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var ws: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		per = bs.size() / vs.size()
		for k in vs.size():
			var top := 0
			for j in per:
				if ws[k * per + j] > ws[k * per + top]:
					top = j
			if limb.has(bs[k * per + top]):
				continue
			verts.append(vs[k])
			for j in per:
				bones.append(bs[k * per + j])
				weights.append(ws[k * per + j])
	_torso[key] = [verts, bones, weights, per]
	return _torso[key]
