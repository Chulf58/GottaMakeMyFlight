extends RefCounted
## The FLOAT check of the carry probes (decision carry-on-bags-stay-in-the-
## hand-during-every-move-no-overhead, board ed9d379c): every drawn carry-on
## bag, every frame, moving or not, is HELD (one of its grip points within
## HELD_M of a hand's grip), WORN (a backpack on the back, a shoulder bag on
## the shoulder or a pulled roller on its wheels with its bar in the hand,
## worn_gap() at GRIP_REACH_M), RESTING (its lowest point within RESTING_M of
## a support under it: the floor, or its tray's floor) or FLOAT. Ported from
## the floating-bag WIP (2b44136, carry_probe_checks.gd); a bag's grip points
## are read here from main's drawing (grip_points()).
## Load with preload(); no class_name.

const HELD_M := 0.05
const ON_BAG_M := 0.06
const RESTING_M := 0.01
const GRIP_REACH_M := 0.06
const FLOAT_PRINTS := 40
## The old overhead route's crossing over the head, for the control.
const OLD_OVERHEAD_M := 2.05
const OLD_OVERHEAD_AHEAD_M := 0.12

## GRIP_ON: while a hand holds a bag, its grip is this close to the bag's own
## grip point (own_grips()), plus the palm offset a kind is held by on purpose
## (a roller's bar BAR_PALM_M off the grip, a hard case in front FRONT_PALM_M
## under it). HELD alone takes a point placed from the hand anywhere within
## ON_BAG_M of the bag, so a pack hung 15 cm off its loop read as held
## (anti-pattern a-float-hand-gap-of-0-does-not-prove-a-carried-bag-is-grippe).
const GRIP_ON_M := 0.03
const GRIP_ON_PRINTS := 40


## The points of bag `i` of passenger `id` a hand holds it by, as drawn now
## (world): a backpack's grab loop (its top), a shoulder bag's strap bar, a
## roller's grip bar and carry handle, a hard case's handle edge and, carried
## in front, the top of its handle under the palm.
static func own_grips(props: CarryOnProps, id: int, i: int) -> Array[Vector3]:
	var bag: Node3D = props.props_of(id)["bags"][i]
	var kind: SecurityLooks.Kind = props.props_of(id)["kinds"][i]
	var xf := bag.global_transform
	match kind:
		SecurityLooks.Kind.BACKPACK:
			return [xf * CarryOnProps.BACKPACK_LOOP]
		SecurityLooks.Kind.SHOULDER:
			return [(bag.find_child("Strap_Top", true, false) as Node3D).global_position]
		SecurityLooks.Kind.ROLLER:
			var top := bag.find_child("Pull_Top", true, false) as Node3D
			var bar := top.global_transform * Vector3(0.0, 0.0, CarryOnProps.ROLLER_GRIP_PAST_TOP_M)
			return [bar, xf * CarryOnProps.ROLLER_HANDLE]
	var handle := case_handle_points(bag)
	return [xf * handle[0], xf * handle[1]]


## A hard case's handle edge and the top of its handle, in the case's own frame
## (scale 1), read from its drawn body mesh: the top face's edge on its handle
## side and the middle of that face. Never from a CarryOnProps placement
## function: a point derived from the placement moves with a wrong placement,
## and the grip then reads as on it.
static func case_handle_points(bag: Node3D) -> Array[Vector3]:
	var body := bag.find_child("CarryOnBag_Body", true, false) as MeshInstance3D
	var box := (bag.global_transform.affine_inverse() * body.global_transform) * body.get_aabb()
	var middle := box.get_center()
	return [Vector3(middle.x, box.end.y, box.end.z), Vector3(middle.x, box.end.y, middle.z)]


## How far the grip of the hand holding bag `i` of passenger `id` is from the
## bag's nearest own grip point (own_grips(); a hard case's, the segment
## between its two, conductor ruling 2026-10-30), and the limit for its kind:
## [gap, limit], gap INF when no hand holds it.
static func grip_on_gap(props: CarryOnProps, id: int, i: int, body: Node3D) -> Array:
	var holder: int = props.bag_state(id, i).get("held_by", -1)
	if holder < 0 or body == null:
		return [INF, GRIP_ON_M]
	var kind: SecurityLooks.Kind = props.props_of(id)["kinds"][i]
	var limit := GRIP_ON_M
	if kind == SecurityLooks.Kind.ROLLER:
		limit += CarryOnProps.BAR_PALM_M
	elif kind == SecurityLooks.Kind.CASE:
		limit += CarryOnProps.FRONT_PALM_M
	var grip := props.grip_of(body, holder)
	var own := own_grips(props, id, i)
	if kind == SecurityLooks.Kind.CASE:
		# Turning between the side and the front carry the palm slides along the
		# case's top from its handle edge to its front palm point (CarryOnProps.
		# _case_transform): anywhere on that segment is on its grip.
		var on := Geometry3D.get_closest_point_to_segment(grip, own[0], own[1])
		return [on.distance_to(grip), limit]
	var gap := INF
	for at in own:
		gap = minf(gap, at.distance_to(grip))
	return [gap, limit]


## The points of bag `i` of passenger `id` a hand can hold it by, as drawn
## now (world): its kind's grip anchor (a hard case's top edge, a roller's
## carry handle, a backpack's grab loop, a shoulder bag's top edge), where
## CarryOnProps holds it now (held_point, through the front carry), and a
## roller's grip bar or a shoulder bag's strap bar.
##
## The point CarryOnProps placed at a hand's grip (hand_point) makes a HELD
## verdict true by construction for a bag in a hand-led move: the bag was placed
## from that grip. It counts only when on_bag() holds (the point within the
## bag's mesh bounds as drawn, ON_BAG_M out), and that is the independent guard
## against a bag placed from a grip point off its own body.
static func grip_points(props: CarryOnProps, id: int, i: int) -> Array[Vector3]:
	var bag: Node3D = props.props_of(id)["bags"][i]
	var kind: SecurityLooks.Kind = props.props_of(id)["kinds"][i]
	var out: Array[Vector3] = [bag.global_transform * CarryOnProps.grip_anchor(kind)]
	var held := props.held_point(id, i)
	if held.is_finite():
		out.append(held)
	# The point CarryOnProps placed at a hand's grip, counted only when it lies
	# on the bag (its meshes' bounds as drawn, ON_BAG_M out).
	var placed := props.hand_point(id, i)
	if placed.is_finite() and on_bag(bag, placed):
		out.append(placed)
	if kind == SecurityLooks.Kind.ROLLER:
		var top := bag.find_child("Pull_Top", true, false) as Node3D
		out.append(top.global_transform * Vector3(0.0, 0.0, CarryOnProps.ROLLER_GRIP_PAST_TOP_M))
	elif kind == SecurityLooks.Kind.SHOULDER:
		out.append((bag.find_child("Strap_Top", true, false) as Node3D).global_position)
	return out


## Whether `at` (world) lies within ON_BAG_M of `bag`'s meshes' bounds, in the
## bag's own frame (a roller's rods and a strap as stretched now).
static func on_bag(bag: Node3D, at: Vector3) -> bool:
	var to_bag := bag.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in bag.find_children("*", "MeshInstance3D", true, false):
		var part := (to_bag * mi.global_transform) * mi.get_aabb()
		box = part if first else box.merge(part)
		first = false
	var grow := ON_BAG_M / bag.global_transform.basis.get_scale().x
	return not first and box.grow(grow).has_point(to_bag * at)


## How far a bag of `kind` worn its kind's way is from its place on `body` at
## `reach` (0 when on it): a pulled roller's bar from its hand and its axle
## from the floor, a shoulder bag's strap bar from its shoulder joint, a
## backpack's middle from the Spine_03 bone. Read from CarryOnProps' bone
## attachments, which follow the pose as drawn.
static func worn_gap(
	props: CarryOnProps, id: int, i: int, body: Node3D, reach: float, kind: SecurityLooks.Kind
) -> float:
	var bag: Node3D = props.props_of(id)["bags"][i]
	var scale_by := bag.global_transform.basis.get_scale().x
	var rig: Dictionary = body.get_meta(&"carry_rig", {})
	if rig.is_empty():
		return INF
	match kind:
		SecurityLooks.Kind.ROLLER:
			var top := bag.find_child("Pull_Top", true, false) as Node3D
			var bar := top.global_transform * Vector3(0.0, 0.0, CarryOnProps.ROLLER_GRIP_PAST_TOP_M)
			var grip := minf(
				bar.distance_to(props.grip_of(body, 0)), bar.distance_to(props.grip_of(body, 1))
			)
			var axle := bag.global_transform * CarryOnProps.ROLLER_AXLE
			var off_floor := absf(
				axle.y - CarryOnProps.ROLLER_AXLE.y * scale_by - body.global_position.y
			)
			return maxf(0.0, maxf(grip - reach, off_floor - 0.01))
		SecurityLooks.Kind.SHOULDER:
			var side := SecurityLooks.worn_side(i)
			var shoulder: Vector3 = (rig["shoulders"][side] as Node3D).global_position
			var top := bag.find_child("Strap_Top", true, false) as Node3D
			# The bar is STRAP_OUT_M out and STRAP_OVER_ARM_M over the joint, about
			# 0.1 m from it with the arm's own lean.
			return maxf(0.0, top.global_position.distance_to(shoulder) - 0.2)
		SecurityLooks.Kind.BACKPACK:
			var spine: Vector3 = (rig["spine"] as Node3D).global_position
			var near := bag.global_transform * CarryOnProps.bag_box(kind).get_center()
			return maxf(0.0, near.distance_to(spine) - 0.45)
	return INF


## Bag `i` of passenger `id` as drawn now: [state ("held", "worn", "resting"
## or "float"), hand gap, rest gap].
static func float_state(sim: PassengerSim, views: PassengerViews, id: int, i: int) -> Array:
	var props := views.carry_on_props()
	var body := views.node_for(id)
	var bag: Node3D = props.props_of(id)["bags"][i]
	var kind: SecurityLooks.Kind = props.props_of(id)["kinds"][i]
	var hand_gap := INF
	for at in grip_points(props, id, i):
		for hand in 2:
			hand_gap = minf(hand_gap, at.distance_to(props.grip_of(body, hand)))
	var rest := rest_gap(sim, props.props_of(id)["tray"], bag)
	if hand_gap <= HELD_M:
		return ["held", hand_gap, rest]
	if kind != SecurityLooks.Kind.CASE:
		if worn_gap(props, id, i, body, GRIP_REACH_M, kind) <= 0.0:
			return ["worn", hand_gap, rest]
	return ["resting" if rest <= RESTING_M else "float", hand_gap, rest]


## How far the lowest point of `bag` (its meshes' bounds as drawn) is from the
## nearest support under it: the floor, or the floor of `tray` when the bag's
## centre is over the tray. INF when it is lower than every support by more
## than RESTING_M.
static func rest_gap(sim: PassengerSim, tray: Node3D, bag: Node3D) -> float:
	var lowest := INF
	var centre := Vector3.ZERO
	var meshes := bag.find_children("*", "MeshInstance3D", true, false)
	for mi: MeshInstance3D in meshes:
		var box := mi.global_transform * mi.get_aabb()
		lowest = minf(lowest, box.position.y)
		centre += box.get_center() / meshes.size()
	var supports: Array[float] = [sim.grid.origin.y]
	if tray != null and tray.visible:
		var top := tray.global_transform * Vector3(0.0, CarryOnProps.TRAY_FLOOR_M, 0.0)
		for mi: MeshInstance3D in tray.find_children("*", "MeshInstance3D", true, false):
			var box := mi.global_transform * mi.get_aabb()
			if box.grow(0.02).has_point(Vector3(centre.x, box.get_center().y, centre.z)):
				supports.append(top.y)
				break
	var gap := INF
	for y in supports:
		if lowest >= y - RESTING_M:
			gap = minf(gap, lowest - y)
	return absf(gap)


## Bag `i` of passenger `id` while it moves: "from>to", each end its home or,
## in a hand, its carry and hand (as "pull.R>hand.R"); "" when it is not.
static func move_of(props: CarryOnProps, id: int, i: int) -> String:
	var bag := props.bag_state(id, i)
	if props.transfer_progress(id, i) >= 1.0 or not bag.has("was"):
		return ""
	var ends := []
	var kind: SecurityLooks.Kind = bag["kind"]
	for end in [
		[bag["was"], bag.get("carry_from", SecurityLooks.KIND_CARRY[kind])],
		[bag["home"], bag["carry"]]
	]:
		var place: int = end[0]
		if place < 0 or place / 4 != SecurityLooks.Home.HAND:
			ends.append(SecurityLooks.Home.keys()[maxi(place, 0) / 4].to_lower())
		else:
			var carry: String = SecurityLooks.Carry.keys()[maxi(end[1], 0)].to_lower()
			ends.append(carry + [".R", ".L"][(place / 2) % 2])
	return "%s>%s" % ends


## One frame of the FLOAT check over every drawn bag of every passenger, into
## `counts` (float_counts()): each state counted, FLOAT also by kind and move
## ("settled" when none) and printed (the first FLOAT_PRINTS).
static func watch_float(sim: PassengerSim, views: PassengerViews, counts: Dictionary) -> void:
	var props := views.carry_on_props()
	var began := Time.get_ticks_usec()
	counts["frames"] += 1
	for id in sim.passenger_ids():
		var body := views.node_for(id)
		var p := sim.get_passenger(id)
		if body == null or p == null or not body.is_visible_in_tree():
			continue
		var bags: Array = props.props_of(id)["bags"]
		for i in bags.size():
			if not (bags[i] as Node3D).is_visible_in_tree():
				continue
			var state := float_state(sim, views, id, i)
			counts[state[0]] += 1
			_watch_grip_on(props, id, i, body, p, counts)
			if state[0] != "float":
				continue
			var kind: String = SecurityLooks.Kind.keys()[props.props_of(id)["kinds"][i]]
			var move := move_of(props, id, i)
			var key := "%s %s" % [kind, move if move != "" else "settled"]
			var by: Dictionary = counts["by_move"]
			by[key] = int(by.get(key, 0)) + 1
			if counts["float"] <= FLOAT_PRINTS:
				print(
					(
						"FLOAT id=%d bag=%d kind=%s move=%s k=%.2f hand_gap_m=%.3f rest_gap_m=%.3f stage=%d phase=%d"
						% [
							id,
							i,
							kind,
							move if move != "" else "settled",
							props.transfer_progress(id, i),
							state[1],
							state[2],
							p.stage,
							p.security_phase
						]
					)
				)
	counts["ms"] += (Time.get_ticks_usec() - began) / 1000.0


## One bag's GRIP_ON check into `counts` (watch_float()): every frame a hand
## holds it, its grip_on_gap(), the largest by kind, and a GRIP_ON_OFF line
## (the first GRIP_ON_PRINTS) when it is over its kind's limit.
static func _watch_grip_on(
	props: CarryOnProps, id: int, i: int, body: Node3D, p: Passenger, counts: Dictionary
) -> void:
	var on := grip_on_gap(props, id, i, body)
	if not (on[0] as float) < INF:
		return
	var kind: String = SecurityLooks.Kind.keys()[props.props_of(id)["kinds"][i]]
	counts["grip_held"] += 1
	var worst: Dictionary = counts["grip_max"]
	worst[kind] = snappedf(maxf(float(worst.get(kind, 0.0)), on[0]), 0.001)
	if on[0] <= on[1]:
		return
	counts["grip_off"] += 1
	if counts["grip_off"] <= GRIP_ON_PRINTS:
		var move := move_of(props, id, i)
		print(
			(
				"GRIP_ON_OFF id=%d bag=%d kind=%s move=%s k=%.2f gap_m=%.3f limit_m=%.3f stage=%d"
				% [
					id,
					i,
					kind,
					move if move != "" else "settled",
					props.transfer_progress(id, i),
					on[0],
					on[1],
					p.stage
				]
			)
		)


## A fresh tally for watch_float().
static func float_counts() -> Dictionary:
	return {
		"frames": 0,
		"ms": 0.0,
		"held": 0,
		"worn": 0,
		"resting": 0,
		"float": 0,
		"by_move": {},
		"grip_held": 0,
		"grip_off": 0,
		"grip_max": {},
	}


## The printable line of a watch_float() tally, and its GRIP_ON line.
static func float_report(counts: Dictionary) -> String:
	return (
		(
			"FLOAT_TOTAL frames=%d check_ms=%.0f held=%d worn=%d resting=%d float=%d by_move=%s"
			+ "\nGRIP_ON_TOTAL held_frames=%d off=%d max_gap_m_by_kind=%s"
		)
		% [
			counts["frames"],
			counts["ms"],
			counts["held"],
			counts["worn"],
			counts["resting"],
			counts["float"],
			counts["by_move"],
			counts["grip_held"],
			counts["grip_off"],
			counts["grip_max"],
		]
	)


## The control on a drawn bag of passenger `id` (bag 0): moved to the old
## overhead route's midpoint (its lowest point OLD_OVERHEAD_M over the floor,
## on the body's centre line OLD_OVERHEAD_AHEAD_M ahead) it must be FLOAT; put
## back, it must not. Returns [state there, state put back].
static func float_control(sim: PassengerSim, views: PassengerViews, id: int) -> Array:
	var props := views.carry_on_props()
	var body := views.node_for(id)
	var bag: Node3D = props.props_of(id)["bags"][0]
	var was := bag.global_transform
	var lowest := INF
	for mi: MeshInstance3D in bag.find_children("*", "MeshInstance3D", true, false):
		lowest = minf(lowest, (mi.global_transform * mi.get_aabb()).position.y)
	var over := body.global_transform * Vector3(0.0, 0.0, OLD_OVERHEAD_AHEAD_M)
	over.y = sim.grid.origin.y + OLD_OVERHEAD_M + (was.origin.y - lowest)
	bag.global_transform = Transform3D(was.basis, over)
	var up: Array = float_state(sim, views, id, 0)
	bag.global_transform = was
	var back: Array = float_state(sim, views, id, 0)
	print("FLOAT_CONTROL id=%d overhead=%s put_back=%s" % [id, up, back])
	return [up[0], back[0]]
