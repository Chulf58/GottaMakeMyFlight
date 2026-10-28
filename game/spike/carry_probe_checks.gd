extends RefCounted
## Contact helpers for the carry-on kinds in security_visuals_plates_probe.gd
## (decision carry-on-bag-kinds-backpack-shoulder-or-tote-bag-small-rolle):
## node-based versions of CarryContact's bag checks, so every kind's own
## meshes (straps and rods included, as drawn now) are tested. Load with
## preload(); no class_name.

const CarryContact := preload("res://spike/carry_contact.gd")

## Metres a roller's axle may move beyond its speed limit between two looks
## (float noise and the walker's own step), and the most it may move when no
## sim time passed (the clock paused, or two looks in one frame).
const SNAP_SLACK_M := 0.02
const STILL_M := 0.001
const CONTROL_FRAMES := 5
const CONTROL_DT := 0.1


## The hands holding something of `p` now (".R", ".L"): a hard case's and a
## roller's grip, a shoulder strap's hand; a backpack holds none.
static func gripping(sim: PassengerSim, p: Passenger) -> Array:
	var out: Array = []
	var homes := SecurityLooks.bag_homes(sim, p)
	for i in homes.size():
		if homes[i] != SecurityLooks.Home.HAND:
			continue
		match SecurityLooks.carry_of(p, i):
			SecurityLooks.Carry.HAND, SecurityLooks.Carry.PULL:
				out.append([".R", ".L"][SecurityLooks.hand_of(sim, p, i)])
			SecurityLooks.Carry.SHOULDER:
				out.append([".R", ".L"][SecurityLooks.worn_side(i)])
	return out


## World points covering a bag node's surface, as drawn now (every mesh of
## it, straps and rods included), sampled at CarryContact.SAMPLE_M or finer.
static func surface(bag: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for mi: MeshInstance3D in bag.find_children("*", "MeshInstance3D", true, false):
		var faces := mi.mesh.get_faces()
		for i in range(0, faces.size() - 2, 3):
			var a := mi.global_transform * faces[i]
			var ab := mi.global_transform * faces[i + 1] - a
			var ac := mi.global_transform * faces[i + 2] - a
			var n := maxi(1, ceili(maxf(ab.length(), ac.length()) / CarryContact.SAMPLE_M))
			for u in n + 1:
				for v in n + 1 - u:
					out.append(a + ab * (u / float(n)) + ac * (v / float(n)))
	return out


## For a contact report: the bones owning the body points inside `bag`, with
## the part of the bag each point is in (Body, a strap or rod node), counted.
static func contact_bones(body: Node3D, gripping: Array, bag: Node3D) -> Dictionary:
	var named: Array = CarryContact.body_points_owned(body, gripping)
	var found := {}
	for mi: MeshInstance3D in bag.find_children("*", "MeshInstance3D", true, false):
		var to_mesh := mi.global_transform.affine_inverse()
		var faces := mi.mesh.get_faces()
		for k in (named[0] as PackedVector3Array).size():
			var lp: Vector3 = to_mesh * named[0][k]
			if mi.get_aabb().grow(0.001).has_point(lp) and CarryContact._odd(lp, faces):
				var key := "%s@%s" % [named[1][k], mi.name]
				found[key] = found.get(key, 0) + 1
	return found


## Points of each bag of a passenger inside another of its bags.
static func bag_bag(bags: Array[Node3D]) -> int:
	var count := 0
	for a in bags.size():
		for b in bags.size():
			if a != b:
				count += CarryContact.inside_meshes(surface(bags[a]), bags[b])
	return count


## How far the arch's meshes reach to its front and back above its feet.
static func arch_post_half_depth(arch: Node3D) -> float:
	var deep := 0.0
	var inv := arch.global_transform.affine_inverse()
	for mi: MeshInstance3D in arch.find_children("*", "MeshInstance3D", true, false):
		for v in mi.mesh.get_faces():
			var local := inv * (mi.global_transform * v)
			if local.y > 0.05 and absf(local.x) > 0.2:
				deep = maxf(deep, absf(local.z))
	return deep


## How far bag `i` of passenger `id` is from what holds it (0 when held): the
## hard case's grip inside its bounds (grown by reach), the roller's
## grip bar at the hand and its wheels on the floor, the strap's bar over the
## shoulder, the backpack at the spine.
static func detached(
	sim: PassengerSim, views: PassengerViews, id: int, i: int, body: Node3D, reach: float
) -> float:
	var props := views.carry_on_props()
	var p := sim.get_passenger(id)
	var bag: Node3D = props.props_of(id)["bags"][i]
	var kind := SecurityLooks.bag_kind(p, i)
	var scale_by := bag.global_transform.basis.get_scale().x
	var skeleton := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var bone := func(name: String) -> Vector3:
		return (
			skeleton.global_transform
			* skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin
		)
	var lifted: bool = props.props_of(id)["carries"][i] == SecurityLooks.Carry.HAND
	match kind if not lifted else SecurityLooks.Kind.CASE:
		SecurityLooks.Kind.ROLLER:
			var grip := props.grip_of(body, SecurityLooks.hand_of(sim, p, i))
			var top := bag.find_child("Pull_Top", true, false) as Node3D
			var bar := top.global_transform * Vector3(0.0, 0.0, CarryOnProps.ROLLER_GRIP_PAST_TOP_M)
			var axle := bag.global_transform * CarryOnProps.ROLLER_AXLE
			var off_floor := absf(
				axle.y - CarryOnProps.ROLLER_AXLE.y * scale_by - body.global_position.y
			)
			return maxf(0.0, maxf(bar.distance_to(grip) - reach, off_floor - 0.01))
		SecurityLooks.Kind.SHOULDER:
			var side: String = ["Arm.R", "Arm.L"][SecurityLooks.worn_side(i)]
			var top := bag.find_child("Strap_Top", true, false) as Node3D
			# The bar is STRAP_OUT_M out and STRAP_OVER_ARM_M over the joint, about
			# 0.1 m from it with the arm's own lean.
			return maxf(0.0, top.global_position.distance_to(bone.call(side)) - 0.2)
		SecurityLooks.Kind.BACKPACK:
			var spine: Vector3 = bone.call(CarryOnProps.SPINE_BONE)
			var near := bag.global_transform * CarryOnProps.bag_box(kind).get_center()
			return maxf(0.0, near.distance_to(spine) - 0.45)
	var grip := props.grip_of(body, SecurityLooks.hand_of(sim, p, i))
	var local := bag.global_transform.affine_inverse() * grip
	var box := CarryOnProps.bag_box(kind)
	return 0.0 if box.grow(reach / scale_by).has_point(local) else 1.0


## How far a pulled roller's axle may move in `dt` sim ticks: the speed limit
## of CarryOnProps.SWING_JUMP_M a tick over the time that really passed, plus
## SNAP_SLACK_M. Nothing but STILL_M when no time passed.
static func snap_allowance(dt: float) -> float:
	if dt <= 0.0:
		return STILL_M
	return CarryOnProps.SWING_JUMP_M * dt + SNAP_SLACK_M


## One pulled roller seen again: `last` is [axle, yaw, sim time] of the look
## before. A body turn of more than 60 degrees counts as a sharp turn
## (turns[0]); an axle move beyond snap_allowance() of the sim time between the
## two looks counts as a snap (turns[1]) and is printed.
static func judge_pulled(
	id: int, last: Array, axle: Vector3, yaw: float, now: float, turns: Array
) -> void:
	turns[0] += int(absf(angle_difference(last[1], yaw)) > PI / 3.0)
	var dt := now - float(last[2])
	var moved := axle.distance_to(last[0])
	if moved > snap_allowance(dt):
		turns[1] += 1
		print("SWEEP snap id=%d moved=%.3f ticks=%.3f" % [id, moved, dt])


## Each pulled roller's drawn axle this frame against the last (judge_pulled).
static func watch_pulled(
	sim: PassengerSim, views: PassengerViews, pulled: Dictionary, turns: Array, now: float
) -> void:
	var props := views.carry_on_props()
	var seen := {}
	for id in sim.passenger_ids():
		var body := views.node_for(id)
		var held: Dictionary = props.props_of(id)
		if body == null or not held["carries"].has(SecurityLooks.Carry.PULL):
			continue
		var i: int = held["carries"].find(SecurityLooks.Carry.PULL)
		if props.transfer_progress(id, i) < 1.0:
			continue
		var axle: Vector3 = held["bags"][i].global_transform * CarryOnProps.ROLLER_AXLE
		if pulled.has(id):
			judge_pulled(id, pulled[id], axle, body.rotation.y, now, turns)
		seen[id] = [axle, body.rotation.y, now]
	pulled.clear()
	pulled.merge(seen)


## The snap check against followers of known quality, through judge_pulled
## itself, over CONTROL_FRAMES looks CONTROL_DT ticks apart (all inside one
## tick, as at 120 fps). Returns the snaps each counted: "creeping" moves 0.2 m
## a look (the old check floored the time at a third of a tick and let it
## pass), "teleporting" jumps to its target and back, "following" is the real
## CarryOnProps.follow() with its target 0.9 m across, "still" does not move,
## "no time passed" is a 0.05 m move and then none with the same look time.
## Expected snaps: CONTROL_FRAMES, CONTROL_FRAMES, 0, 0 and 1. Each kind's
## "travelled" is how far its axle got from where it started (a follower
## that never moved would pass by accident).
static func snap_control() -> Dictionary:
	var out := {}
	var yaw := 0.0
	var steady := Vector3(0.3, 0.0, -1.0)
	var target := Vector3(-0.6, 0.0, -1.0)
	for kind in ["creeping", "teleporting", "following", "still"]:
		var turns := [0, 0]
		var axle := steady
		var now := 10.0
		for f in CONTROL_FRAMES:
			var last := [axle, yaw, now]
			now += CONTROL_DT
			match kind:
				"creeping":
					axle += Vector3(0.2, 0.0, 0.0)
				"teleporting":
					axle = target if f % 2 == 0 else steady
				"following":
					axle = CarryOnProps.follow(axle, target, CONTROL_DT, 0)
			judge_pulled(0, last, axle, yaw, now, turns)
		out[kind] = turns[1]
		out[kind + " travelled"] = axle.distance_to(steady)
	var frozen := [0, 0]
	judge_pulled(0, [steady, yaw, 10.0], steady + Vector3(0.05, 0.0, 0.0), yaw, 10.0, frozen)
	judge_pulled(0, [steady, yaw, 10.0], steady, yaw, 10.0, frozen)
	out["no time passed"] = frozen[1]
	return out


## Whether snap_control() came out as it must: both broken followers caught on
## every look, the good and the still ones never, one snap for the move with no
## time passed, and the good follower really moved.
static func snap_control_ok(control: Dictionary) -> bool:
	return (
		control["creeping"] == CONTROL_FRAMES
		and control["teleporting"] == CONTROL_FRAMES
		and control["following"] == 0
		and control["still"] == 0
		and control["no time passed"] == 1
		and control["following travelled"] > 0.05
	)
