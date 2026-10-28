extends RefCounted
## Contact helpers for the carry-on kinds in security_visuals_plates_probe.gd
## (decision carry-on-bag-kinds-backpack-shoulder-or-tote-bag-small-rolle):
## node-based versions of CarryContact's bag checks, so every kind's own
## meshes (straps and rods included, as drawn now) are tested. Load with
## preload(); no class_name.

const CarryContact := preload("res://spike/carry_contact.gd")


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


## Each pulled roller's drawn axle this frame against the last: a body turn
## of more than 60 degrees counts as a sharp turn (turns[0]), an axle move of
## more than CarryOnProps.SWING_JUMP_M a sim tick (a 60 fps frame at 1x is
## a third of a tick) counts as a snap (turns[1]).
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
			var last: Array = pulled[id]
			turns[0] += int(absf(angle_difference(last[1], body.rotation.y)) > PI / 3.0)
			# Per sim tick: a slow frame runs several ticks, and the roller
			# keeps pace with its walker through them.
			var ticks := maxf(now - float(last[2]), 0.34)
			if axle.distance_to(last[0]) > CarryOnProps.SWING_JUMP_M * ticks:
				turns[1] += 1
				print(
					(
						"SWEEP snap id=%d moved=%.2f ticks=%.2f"
						% [id, axle.distance_to(last[0]), now - float(last[2])]
					)
				)
		seen[id] = [axle, body.rotation.y, now]
	pulled.clear()
	pulled.merge(seen)
