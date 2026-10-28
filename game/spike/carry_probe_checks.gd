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
