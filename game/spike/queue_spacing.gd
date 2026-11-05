extends RefCounted
## How near the passengers round a subject are drawn to it (board 34b0c378):
## body to body, each body to the other's roller, and each body to the
## subject's holding hand and bar top. Distances are horizontal, in m, from a
## body's origin (its feet, on its centre line) to the other thing. Only
## passengers within NEAR_M of the subject are measured. inside() counts body
## points inside the other's roller meshes, which only a windowed run draws
## right (anti-pattern a-headless-count-of-body-points-inside-a-carried-bag).
## Load with preload(); no class_name.

const CarryContact := preload("res://spike/carry_contact.gd")
const NEAR_M := 1.6
## A roller's surface is sampled this fine for the distance to a body.
const STEP_M := 0.05


## The nearest passengers to `id` as drawn now: {"body": [m, other id],
## "roller": [m, other id, "its" (the subject's roller) or "theirs"], "hand":
## [m, other id]}, each [INF, 0, ...] with nobody near.
static func nearest(views: PassengerViews, sim: PassengerSim, id: int) -> Dictionary:
	var out := {"body": [INF, 0], "roller": [INF, 0, ""], "hand": [INF, 0]}
	var body := views.node_for(id)
	if body == null:
		return out
	var own := rollers(views, sim, id)
	var own_points: Array[PackedVector3Array] = []
	for node in own:
		own_points.append(surface(node))
	var reach := _reach(views, sim, id)
	for other in near(views, sim, id):
		var at := views.node_for(other).global_position
		var d := flat(at, body.global_position)
		if d < out["body"][0]:
			out["body"] = [d, other]
		for points in own_points:
			var r := least(points, at)
			if r < out["roller"][0]:
				out["roller"] = [r, other, "its"]
		for node in rollers(views, sim, other):
			var r := least(surface(node), body.global_position)
			if r < out["roller"][0]:
				out["roller"] = [r, other, "theirs"]
		for point in reach:
			var h := flat(at, point)
			if h < out["hand"][0]:
				out["hand"] = [h, other]
	return out


## Body points of the passengers near `id` inside its rollers, plus its own
## body points inside theirs (CarryContact, as drawn in this window).
static func inside(views: PassengerViews, sim: PassengerSim, id: int) -> int:
	var count := 0
	var body := views.node_for(id)
	if body == null:
		return 0
	var own := rollers(views, sim, id)
	var own_points := PackedVector3Array()
	for other in near(views, sim, id):
		var theirs := rollers(views, sim, other)
		if own.is_empty() and theirs.is_empty():
			continue
		var points := CarryContact.body_points(views.node_for(other), [])
		for node in own:
			count += CarryContact.inside_meshes(points, node)
		if theirs.is_empty():
			continue
		if own_points.is_empty():
			own_points = CarryContact.body_points(body, [])
		for node in theirs:
			count += CarryContact.inside_meshes(own_points, node)
	return count


## Ids of the drawn passengers within NEAR_M of `id`, `id` left out.
static func near(views: PassengerViews, sim: PassengerSim, id: int) -> Array[int]:
	var out: Array[int] = []
	var body := views.node_for(id)
	for other in sim.passenger_ids():
		var node := views.node_for(other)
		if other == id or node == null or not node.is_visible_in_tree():
			continue
		if flat(node.global_position, body.global_position) <= NEAR_M:
			out.append(other)
	return out


## The roller nodes passenger `id` has drawn.
static func rollers(views: PassengerViews, sim: PassengerSim, id: int) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var p := sim.get_passenger(id)
	var bags: Array = views.carry_on_props().props_of(id).get("bags", [])
	for i in bags.size():
		var node := bags[i] as Node3D
		if p != null and node != null and node.is_visible_in_tree():
			if SecurityLooks.bag_kind(p, i) == SecurityLooks.Kind.ROLLER:
				out.append(node)
	return out


## World points covering every mesh of `node`, STEP_M apart or closer.
static func surface(node: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var faces := mi.mesh.get_faces()
		for i in range(0, faces.size() - 2, 3):
			var a := mi.global_transform * faces[i]
			var ab := mi.global_transform * faces[i + 1] - a
			var ac := mi.global_transform * faces[i + 2] - a
			var n := maxi(1, ceili(maxf(ab.length(), ac.length()) / STEP_M))
			for u in n + 1:
				for v in n + 1 - u:
					out.append(a + ab * (u / float(n)) + ac * (v / float(n)))
	return out


## The least horizontal distance from `at` to any of `points`.
static func least(points: PackedVector3Array, at: Vector3) -> float:
	var best := INF
	for p in points:
		best = minf(best, flat(p, at))
	return best


static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## The subject's holding hand and its roller's bar top, while a hand holds it.
static func _reach(views: PassengerViews, sim: PassengerSim, id: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var props := views.carry_on_props()
	var body := views.node_for(id)
	var nodes := rollers(views, sim, id)
	var bags: Array = props.props_of(id).get("bags", [])
	for i in bags.size():
		var node := bags[i] as Node3D
		if not node in nodes:
			continue
		var hand := int(props.bag_state(id, i).get("held_by", -1))
		if hand < 0:
			continue
		out.append(props.grip_of(body, hand))
		var top := node.find_child(
			CarryOnProps.REACH_NODES[SecurityLooks.Kind.ROLLER][1], true, false
		)
		if top != null:
			out.append((top as Node3D).global_position)
	return out
