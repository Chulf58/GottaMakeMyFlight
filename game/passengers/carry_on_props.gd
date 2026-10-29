class_name CarryOnProps
extends Node3D
## The carry-on bags of every drawn passenger, and the trays at security
## lanes (Security 7/8; decisions passengers-carry-their-carry-on-bags-for-
## the-whole-visit-fro, carried-bags-stay-gripped-in-the-hand-clear-body-
## contact-by and carry-on-bag-kinds-backpack-shoulder-or-tote-bag-small-
## rolle). SecurityLooks says where each bag is (in hand, in a tray or on the
## floor) and what kind it is. sync() runs on each tick after PassengerViews
## has posed its characters: it takes or returns pooled props, one pool per
## kind, and moves each pulled roller's trailing axle. draw() runs each frame
## after the characters are placed: it poses each character's CarryArms and
## puts every prop in place from them, so a tray riding the X-ray belt keeps
## pace with its passenger between ticks.
##
## While its home is HAND a bag is carried its kind's way (SecurityLooks.Carry):
## - HAND, the hard case: upright with its top edge in the hand, just past the
##   knuckles (the Fingers bone) of the hand SecurityLooks.hand_of() names, its
##   thin side to the leg; in a cell closed on both sides it turns about the
##   grip to a front carry (the arm with it).
## - BACK, the backpack: worn, its back panel BACK_FROM_SPINE_M behind the
##   Spine_03 bone and leaning with it; the arms are left to the animation.
## - SHOULDER, the tote: hung on the shoulder of SecurityLooks.worn_side(), its
##   strap stretched (Strap_Reach, Strap_Top) from the bag's top edge to a bar
##   STRAP_OVER_ARM_M over the Arm bone, the bag outside the hip; that arm holds
##   the strap at the chest (CarryArm's front pose with a raised forearm).
## - PULL, the roller: pulled by its grip bar in the hand, its wheels on the
##   floor at an axle TRAIL_M back along the line the body walked (trail()),
##   moved once per tick in sync() and drawn with the clock's alpha, so it
##   takes each corner where the body did instead of swinging with the body's
##   instant turn; the rods (Pull_Reach) stretch to the hand.
## A roller is lifted by its handle and carried as the hard case is while its
## walker is at security (narrow lane cells and tables) or runs (a long stride
## kicks back into a trailing case); it goes between pull and lift over the
## head. Worn bags keep their carry in a narrow cell: only a hand-carried bag
## turns to the front (worn bags stay inside the body's width).
##
## A bag that changes home (or hand) moves there over TRANSFER_TICKS of sim
## time (the clock's tick plus its alpha), lifted and kept out from the body; a
## backpack going to or from the back, and a roller going to or from the pull,
## take the overhead route (overhead()), along the body's centre plane, over
## the head (a roller taken round the side met the legs and, in a narrow cell,
## the wall). Straps and rods retract while a
## bag is off the body and stretch as it arrives. It reads the sim and the views
## and never writes either.

enum Arm { FREE, HAND, PULL, STRAP }
## Which bags _place_bags() places.
enum Placing { HAND, NOT_HAND }

const TRAY_MOUNTS := {
	SecurityLooks.Tray.IN: [SecurityLanes.TRAY_TABLE, "Mount_TrayIn"],
	SecurityLooks.Tray.OUT: [SecurityLanes.PICKUP_TABLE, "Mount_TrayOut"],
}
const SCAN_MOUNT := [SecurityLanes.XRAY_BELT, "Mount_TrayScan"]
## A bag in a tray rests on the tray's floor, this far above its mount.
const TRAY_FLOOR_M := 0.012
## The grip sits this far past the knuckles along the hand's own axis.
const GRIP_ALONG_M := 0.03
## In front, a bag's handle sits this far under the knuckles, in the palm.
const FRONT_PALM_M := 0.04
## In front, how far from the centre line each hand holds: the hand with one
## bag, each hand with two, and the free hand (measured with the Toon walk and
## run: no body contact, the bags within 0.32 m of the centre line).
const FRONT_ONE_BAG_M := 0.10
const FRONT_TWO_BAGS_M := 0.17
const FRONT_FREE_HAND_M := 0.33
const TRANSFER_TICKS := 6.0
## How high a moving bag rises midway, so it goes over a table edge.
const TRANSFER_LIFT_M := 0.3
## A moving bag's path keeps its middle this far from the body's centre line.
const TRANSFER_CLEAR_M := 0.38
## How high a bag picked up from below rises over the walker's knee.
const KNEE_LIFT_M := 0.3
const GRIP_BONES: Array[String] = ["Fingers.R", "Fingers.L"]
const ARM_BONES: Array[String] = ["Arm.R", "Arm.L"]
const SPINE_BONE := "Spine_03"
## Worn backpack: its back panel this far behind the Spine_03 bone (clear of
## the back, a skirt and long hair), its top this far above the bone.
const BACK_FROM_SPINE_M := 0.175
const BACK_TOP_OVER_SPINE_M := 0.06
## It leans in at the top by this much, its bottom out clear of the hips.
const BACK_LEAN_DEGREES := 10.0
## Shoulder bag: the strap this far out from the body's centre line, its bar
## this far over the Arm bone (the shoulder joint), and this long from the bar
## to the bag's top edge (the bag hangs outside the hip, its top about the hip
## bone's height, under the elbow).
const STRAP_OUT_M := 0.32
const STRAP_OVER_ARM_M := 0.06
const STRAP_M := 0.45
## The strap hand: at the chest just inside the strap (so the forearm stays
## clear of the strap), this far from the centre line, the forearm raised this
## much.
const STRAP_HAND_M := 0.15
const STRAP_HAND_UP_DEGREES := 45.0
## A pulled roller's axle trails this far behind the body's centre, measured
## back along the line the body walked (so it takes each corner where the body
## did and clears the heel of a long stride).
const TRAIL_M := 1.0
## The walked line it follows is this far out on the pulling hand's side, so
## the rods from the hand pass outside the thigh.
const TRAIL_SIDE_M := 0.3
## How far to the pulling hand's side the axle may be, from the body's centre
## line, and how far behind it at least: a walked line that kinks at each
## heading change (a diagonal zig-zag) puts the spot 1 m of walk back nearer
## than 1 m, and with the axle 0.28-0.30 m out an axle 0.85 m or less behind
## meets the trailing foot (windowed contact bench, 2026-10-29: none at 0.9 m).
const TRAIL_SIDE_MIN_M := 0.28
const TRAIL_SIDE_MAX_M := 0.6
const TRAIL_BEHIND_MIN_M := 0.95
## The drawn axle follows its place behind the body at a limited speed in sim
## time, round the pulling hand's side about the body's centre, at least
## SWING_RADIUS_M from it: when the place jumps (the body turned sharply, or
## walked back past its roller) the roller swings there, never in an instant.
## SWING_TURN is radians per tick, SWING_REACH_M metres per tick of radius.
const SWING_TURN := PI / 10.0
const SWING_REACH_M := 0.2
const SWING_RADIUS_M := 0.55
## The probe's snap threshold: a drawn axle moving more than this a sim tick
## (the walk is about 0.07 m a tick; a swing at most SWING_TURN of arc).
const SWING_JUMP_M := 0.6
## The pulling arm: turned out a little, less swing, leaning back.
const PULL_OUT_DEGREES := 12.0
const PULL_SWING_KEPT := 0.2
const PULL_LEAN_DEGREES := 12.0
## The roller's axle in its own frame at scale 1 (build_carry_on_kit.py: on
## the rod line, at the wheels), and how far the grip bar's middle is past
## Pull_Top's origin.
const ROLLER_AXLE := Vector3(0.0, 0.03, -0.19)
const ROLLER_GRIP_PAST_TOP_M := 0.015
## The roller's carry handle (build_carry_on_kit.py Roller_Handle), where a
## lifted roller is held.
const ROLLER_HANDLE := Vector3(0.0, 0.225, 0.165)
## A stretchable strip or rod as built (build_carry_on_kit.py REACH_BUILT).
const REACH_BUILT_M := 0.02
## Kind -> [the stretched node, the node moved to its end].
const REACH_NODES := {
	SecurityLooks.Kind.SHOULDER: ["Strap_Reach", "Strap_Top"],
	SecurityLooks.Kind.ROLLER: ["Pull_Reach", "Pull_Top"],
}
## The overhead route: the bag's lowest point is this high while it crosses
## over the head, and its origin keeps this far in front of or behind the
## body's centre while it rises or comes down.
const OVERHEAD_M := 2.05
const ROUTE_FRONT_M := 0.45
const ROUTE_BACK_M := 0.2
## A roller on the overhead route is down by this much of the move; its rods
## then come out to the hand.
const ROLLER_LAND := 0.85

## Kind -> its bounds at scale 1, all meshes with their transforms in the piece
## (read once).
static var _sizes := {}
## Mount name -> its transform relative to its kit piece's root.
static var _mounts := {}

var sim: PassengerSim
var views: PassengerViews
## Sim time for bag moves; without one a move is instant.
var clock: SimClock

## Passenger id -> {"tray": Node3D or null, "tray_at": SecurityLooks.Tray,
## "bags": Array of {"node", "kind", "place", "changed", "axle"} (set by
## sync()) and "home", "was", "from", "since", "reach_from" (set by draw()),
## "homes", "hands", "kinds", "lane", "scale", "floor": Array of Transform3D,
## "front", "front_from", "front_since", "weight"}.
var _held := {}
var _free_trays: Array[Node3D] = []
## Character node -> the passenger id it draws now (for _on_pose).
var _body_ids := {}
## Kit piece -> pooled bag nodes of that kind.
var _free_bags := {}


## A mount's transform relative to its piece (read once from the kit scene).
static func mount_local(piece: StringName, mount: String) -> Transform3D:
	if not _mounts.has(mount):
		var node := InteriorKit.instantiate(piece)
		var found := node.find_child(mount, true, false) as Node3D
		_mounts[mount] = _in_piece(found, node)
		node.free()
	return _mounts[mount]


## A bag kind's bounds at scale 1, handle included (read once): every mesh with
## its full transform in the piece.
static func bag_box(kind := SecurityLooks.Kind.CASE) -> AABB:
	if not _sizes.has(kind):
		var node := InteriorKit.instantiate(SecurityLooks.KIND_PIECES[kind])
		var box := AABB()
		var first := true
		for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			var b := _in_piece(mi, node) * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		node.free()
		_sizes[kind] = box
	return _sizes[kind]


## A bag kind's size at scale 1, handle included.
static func bag_size(kind := SecurityLooks.Kind.CASE) -> Vector3:
	return bag_box(kind).size


## The world transform of a lane's mount on `piece`.
static func mount_world(
	grid: BuildGrid, lane: Dictionary, piece: StringName, mount: String
) -> Transform3D:
	var cells: Array[Vector2i] = [lane[piece]]
	return BuildView.object_transform(grid, cells, lane["facing"]) * mount_local(piece, mount)


## Where a riding tray is when its passenger is drawn at `body`: from the tray
## table over the belt to the pickup table, by the body's progress along the
## passage from the unpack cell to the pickup cell.
static func ride(grid: BuildGrid, lane: Dictionary, body: Vector3) -> Transform3D:
	var unpack := grid.cell_to_world(lane["unpack"])
	var pickup := grid.cell_to_world(lane["pickup"])
	var along := pickup - unpack
	var t := clampf((body - unpack).dot(along) / along.length_squared(), 0.0, 1.0)
	var start := mount_world(grid, lane, SecurityLanes.TRAY_TABLE, "Mount_TrayIn")
	var mid := mount_world(grid, lane, SCAN_MOUNT[0], SCAN_MOUNT[1])
	var end := mount_world(grid, lane, SecurityLanes.PICKUP_TABLE, "Mount_TrayOut")
	if t < 0.5:
		return start.interpolate_with(mid, t * 2.0)
	return mid.interpolate_with(end, (t - 0.5) * 2.0)


## A carried hard case's transform for a grip at `grip` on a body drawn with
## yaw `yaw` at `centre`: upright (its length vertical), its handle face toward
## the body, its top edge at the grip, its body outward from the hand.
static func carried(
	grip: Vector3, centre: Vector3, yaw: float, scale_by: float, kind := SecurityLooks.Kind.CASE
) -> Transform3D:
	var lateral := Basis(Vector3.UP, yaw) * Vector3.RIGHT
	var out := lateral if (grip - centre).dot(lateral) >= 0.0 else -lateral
	var inward := -out
	var hang := Basis(inward.cross(Vector3.UP), inward, Vector3.UP).scaled(Vector3.ONE * scale_by)
	return Transform3D(hang, grip - hang * grip_anchor(kind))


## The point of a hand-carried bag (in its own frame, scale 1) held at the grip
## in the side carry: a hard case's top edge on its handle face, a lifted
## roller's carry handle.
static func grip_anchor(kind: SecurityLooks.Kind) -> Vector3:
	if kind == SecurityLooks.Kind.ROLLER:
		return ROLLER_HANDLE
	var box := bag_box(kind)
	return Vector3(0.0, box.end.y, box.end.z)


## A hard case carried in front of the body (a cell closed on both sides):
## lying flat across the body, its handle on top just under the hand at `grip`
## (FRONT_PALM_M below the knuckles).
static func carried_in_front(
	grip: Vector3, yaw: float, scale_by: float, kind := SecurityLooks.Kind.CASE
) -> Transform3D:
	var size := bag_size(kind)
	var flat := _flat(yaw, scale_by)
	return Transform3D(flat, grip - Vector3.UP * (size.y * scale_by + FRONT_PALM_M))


## A backpack worn on a body turned to `yaw` whose Spine_03 bone is at `spine`
## (world): its length along the bone leaning in at the top by
## BACK_LEAN_DEGREES, the top of its back panel BACK_FROM_SPINE_M behind the
## bone and BACK_TOP_OVER_SPINE_M above it.
static func worn_back(spine: Transform3D, yaw: float, scale_by: float) -> Transform3D:
	var up := spine.basis.y.normalized()
	var behind := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var out := (behind - up * behind.dot(up)).normalized()
	var anchor := spine.origin + out * BACK_FROM_SPINE_M + up * BACK_TOP_OVER_SPINE_M
	var lean := deg_to_rad(BACK_LEAN_DEGREES)
	var along := up * cos(lean) - out * sin(lean)
	var back := out * cos(lean) + up * sin(lean)
	var basis := Basis(back.cross(along), back, along).scaled(Vector3.ONE * scale_by)
	var top := bag_box(SecurityLooks.Kind.BACKPACK).end.z * scale_by
	return Transform3D(basis, anchor - along * top)


## A shoulder bag hung on the shoulder of `side` (0 right, 1 left) of a body
## turned to `yaw` at `centre`, whose Arm bone is at `joint`: upright, its inner
## face to the hip, the strap's bar STRAP_OVER_ARM_M over the joint and
## STRAP_OUT_M out from the centre line. `strap_base` is Strap_Reach's position
## in the bag. Returns [transform, the strap length in the bag's units].
static func worn_shoulder(
	joint: Vector3, centre: Vector3, yaw: float, side: int, scale_by: float, strap_base: Vector3
) -> Array:
	var turn := Basis(Vector3.UP, yaw)
	var out := turn * (Vector3.LEFT if side == 0 else Vector3.RIGHT)
	var forward := turn * Vector3.BACK
	var bar := centre + out * STRAP_OUT_M + forward * (joint - centre).dot(forward)
	bar.y = joint.y + STRAP_OVER_ARM_M
	var basis := Basis(out.cross(Vector3.UP), out, Vector3.UP).scaled(Vector3.ONE * scale_by)
	var length := STRAP_M / scale_by
	var at := bar - basis * (strap_base + Vector3(0.0, 0.0, length))
	return [Transform3D(basis, at), length]


## A roller pulled by its grip at `grip` with its axle at `axle` (on the floor,
## the wheels' radius up): its length along the line from the axle to the grip,
## its back panel (rods, wheels) down toward the walker.
static func pulled(grip: Vector3, axle: Vector3, scale_by: float) -> Transform3D:
	var along := (grip - axle).normalized()
	var up := Vector3.UP - along * along.dot(Vector3.UP)
	up = up.normalized() if up.length() > 0.001 else Vector3.BACK
	var basis := Basis(up.cross(along), up, along).scaled(Vector3.ONE * scale_by)
	return Transform3D(basis, axle - basis * ROLLER_AXLE)


## How long a pulled roller's rods are (in its units) for its grip bar to be
## at `grip` with the axle at `axle`; `reach_base` is Pull_Reach's z in the bag.
static func _pull_length(grip: Vector3, axle: Vector3, scale_by: float, reach_base: float) -> float:
	var past := reach_base + ROLLER_GRIP_PAST_TOP_M - ROLLER_AXLE.z
	return maxf(REACH_BUILT_M, grip.distance_to(axle) / scale_by - past)


## The point TRAIL_M back along `walked` (the body's positions, oldest first,
## the last one now); past the oldest it goes on straight, along the first
## step walked or along `back` before any step.
static func trail(walked: Array, back: Vector3) -> Vector3:
	var left := TRAIL_M
	var at: Vector3 = walked[-1]
	for i in range(walked.size() - 2, -1, -1):
		var step: Vector3 = walked[i] - at
		if step.length() >= left:
			return at + step.normalized() * left
		left -= step.length()
		at = walked[i]
	var on := back
	if walked.size() > 1:
		on = (walked[0] - walked[1]).normalized()
	return at + on * left


## The drawn axle `dt` sim ticks on from `at` toward `to`, both in the body's
## frame (x across, +z ahead): its angle about the body's centre turns at most
## SWING_TURN a tick, round the pulling hand's side (`hand` 0 right, 1 left),
## its distance changes at most SWING_REACH_M a tick and stays at least
## SWING_RADIUS_M, so it passes beside the body clear of the legs.
static func follow(at: Vector3, to: Vector3, dt: float, hand: int) -> Vector3:
	var out := -1.0 if hand == 0 else 1.0
	# Angle from straight behind (0) toward the hand's side (PI / 2).
	var a0 := atan2(at.x * out, -at.z)
	var a1 := atan2(to.x * out, -to.z)
	if a0 < -PI / 2.0:
		a0 += TAU
	var a := a0 + clampf(a1 - a0, -SWING_TURN * dt, SWING_TURN * dt)
	var r0 := Vector2(at.x, at.z).length()
	var r1 := Vector2(to.x, to.z).length()
	var r := maxf(r0 + clampf(r1 - r0, -SWING_REACH_M * dt, SWING_REACH_M * dt), SWING_RADIUS_M)
	return Vector3(out * r * sin(a), to.y, -r * cos(a))


## The overhead route at `k` (0 to 1) from `from` to `to`, both in the body's
## frame (x across, +z ahead), down by `land` (it then waits there, turned): it
## rises in front of or behind the body, crosses
## over the head with its lowest point (of `box`, the bag's bounds in its own
## frame) at OVERHEAD_M, turning there, and comes down on the other side.
static func overhead(
	from: Transform3D, to: Transform3D, k: float, box: AABB, land := 1.0
) -> Transform3D:
	# It turns only while it is up over the head: rising and coming down it
	# keeps its start and end pose, so it swings into nothing beside the body.
	var turned := clampf(k * 3.0 - 1.0, 0.0, 1.0)
	var turn := from.basis.get_rotation_quaternion().slerp(
		to.basis.get_rotation_quaternion(), turned
	)
	var basis := Basis(turn).scaled(from.basis.get_scale().lerp(to.basis.get_scale(), turned))
	var lowest := INF
	for i in 8:
		lowest = minf(lowest, (basis * box.get_endpoint(i)).y)
	var high := OVERHEAD_M - lowest
	var rise := _route_end(from.origin)
	var fall := _route_end(to.origin)
	var at: Vector3
	if k < 1.0 / 3.0:
		var t := k * 3.0
		at = from.origin.lerp(rise, t)
		at.y = lerpf(from.origin.y, high, t)
	elif k < 2.0 / 3.0:
		at = rise.lerp(fall, k * 3.0 - 1.0)
		at.y = high
	else:
		var t := minf((k - 2.0 / 3.0) / (land - 2.0 / 3.0), 1.0)
		at = fall.lerp(to.origin, t)
		at.y = lerpf(high, to.origin.y, t)
	return Transform3D(basis, at)


## Where the overhead route leaves or joins the body's centre plane: in front
## or behind, at least ROUTE_FRONT_M / ROUTE_BACK_M out.
static func _route_end(at: Vector3) -> Vector3:
	var z := maxf(at.z, ROUTE_FRONT_M) if at.z >= 0.0 else minf(at.z, -ROUTE_BACK_M)
	return Vector3(0.0, at.y, z)


## A bag lying flat with its length across a body turned to `yaw`.
static func _flat(yaw: float, scale_by: float) -> Basis:
	var forward := Basis(Vector3.UP, yaw) * Vector3.BACK
	return Basis(forward, Vector3.UP, forward.cross(Vector3.UP)).scaled(Vector3.ONE * scale_by)


## `node`'s transform relative to `root`, through every parent between them.
static func _in_piece(node: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != root:
		xf = (at as Node3D).transform * xf
		at = at.get_parent()
	return xf


## Takes and returns props to match each drawn passenger's look on this tick.
func sync() -> void:
	var seen := {}
	for id in sim.passenger_ids():
		var node := views.node_for(id)
		if node == null:
			continue
		var p := sim.get_passenger(id)
		var homes := SecurityLooks.bag_homes(sim, p)
		var tray_at := SecurityLooks.tray(sim, p)
		if homes.is_empty():
			_arms_off(node)
		if homes.is_empty() and tray_at == SecurityLooks.Tray.NONE:
			continue
		seen[id] = true
		var hands: Array[int] = []
		var kinds: Array[SecurityLooks.Kind] = []
		for i in homes.size():
			kinds.append(SecurityLooks.bag_kind(p, i))
			# A worn bag keeps its side, so a narrow cell never moves it across.
			var worn: bool = (
				SecurityLooks.KIND_CARRY[kinds[i]]
				in [SecurityLooks.Carry.BACK, SecurityLooks.Carry.SHOULDER]
			)
			hands.append(SecurityLooks.worn_side(i) if worn else SecurityLooks.hand_of(sim, p, i))
		var front := SecurityLooks.carry_front(sim, p)
		var held: Dictionary = _held.get(id, {"tray": null, "bags": []})
		_held[id] = held
		held["tray_at"] = tray_at
		held["homes"] = homes
		held["hands"] = hands
		held["kinds"] = kinds
		if not held.has("front"):
			# A new record (a new passenger, or after a load) starts in the
			# carry it needs, with no turn to play.
			held["front"] = front
		elif front != held["front"]:
			# Turning between side and front carry starts from where it is now,
			# at this tick: a frame that runs several ticks stamps each one.
			held["front_from"] = _front_weight(held, _tick())
			held["bag_from"] = _bag_weight(held, _tick())
			held["front_since"] = _tick()
			held["front"] = front
		held["lane"] = SecurityLooks.lane_of(sim, p)
		held["scale"] = SecurityLooks.bag_scale(p)
		var spots: Array[Transform3D] = []
		for i in homes.size():
			spots.append(SecurityLooks.floor_spot(sim, p, i, homes.size()))
		held["floor"] = spots
		if tray_at != SecurityLooks.Tray.NONE and held["tray"] == null:
			held["tray"] = _take("security_tray")
		elif tray_at == SecurityLooks.Tray.NONE and held["tray"] != null:
			_give("security_tray", held["tray"])
			held["tray"] = null
		var bags: Array = held["bags"]
		while bags.size() > homes.size():
			var gone: Dictionary = bags.pop_back()
			_give(SecurityLooks.KIND_PIECES[gone["kind"]], gone["node"])
		for i in homes.size():
			if i < bags.size() and bags[i]["kind"] != kinds[i]:
				_give(SecurityLooks.KIND_PIECES[bags[i]["kind"]], bags[i]["node"])
				bags[i] = {"node": _take(SecurityLooks.KIND_PIECES[kinds[i]]), "home": -1}
			elif i >= bags.size():
				bags.append({"node": _take(SecurityLooks.KIND_PIECES[kinds[i]]), "home": -1})
			bags[i]["kind"] = kinds[i]
		# A change of home or hand is stamped with this tick; draw() starts the
		# move from where the bag was drawn last.
		for i in bags.size():
			# A roller is lifted by its handle and carried as the hard case is
			# through security (narrow lane cells, tables) and while its walker
			# runs (a long stride kicks back into a trailing case).
			var lifted: bool = (
				kinds[i] == SecurityLooks.Kind.ROLLER
				and (p.stage == Passenger.Stage.SECURITY or p.late)
			)
			var carry: SecurityLooks.Carry = (
				SecurityLooks.Carry.HAND if lifted else SecurityLooks.KIND_CARRY[kinds[i]]
			)
			var place: int = (homes[i] * 2 + hands[i]) * 2 + int(lifted)
			if bags[i].get("place", -2) != place:
				bags[i]["place"] = place
				bags[i]["changed"] = _tick()
				bags[i]["carry_was"] = bags[i].get("carry", carry)
			bags[i]["carry"] = carry
			_trail(bags[i], node, id, homes[i], hands[i])
	for id in _held.keys():
		if not seen.has(id):
			release(id)


## Returns every prop of passenger `id` to the pool.
func release(id: int) -> void:
	var held: Dictionary = _held.get(id, {})
	if held.is_empty():
		return
	if held["tray"] != null:
		_give("security_tray", held["tray"])
	for bag: Dictionary in held["bags"]:
		_give(SecurityLooks.KIND_PIECES[bag["kind"]], bag["node"])
	_held.erase(id)


## Props of passenger `id`: {"tray": Node3D or null, "bags": Array[Node3D],
## "kinds": Array of SecurityLooks.Kind, "carries": the SecurityLooks.Carry
## each is held with while in hand}.
func props_of(id: int) -> Dictionary:
	var held: Dictionary = _held.get(id, {})
	var bags: Array[Node3D] = []
	var kinds: Array = []
	var carries: Array = []
	for bag: Dictionary in held.get("bags", []):
		bags.append(bag["node"])
		kinds.append(bag["kind"])
		carries.append(bag.get("carry", SecurityLooks.KIND_CARRY[bag["kind"]]))
	return {"tray": held.get("tray"), "bags": bags, "kinds": kinds, "carries": carries}


## How far bag `index` of passenger `id` is through its move to its home,
## 0 to 1 (1 when it is not moving).
func transfer_progress(id: int, index: int) -> float:
	var bags: Array = _held.get(id, {}).get("bags", [])
	if index >= bags.size() or not bags[index].has("since"):
		return 1.0
	return clampf((_now() - bags[index]["since"]) / TRANSFER_TICKS, 0.0, 1.0)


## How far passenger `id` has turned to the front carry: 0 side, 1 front.
## The turn runs for every passenger in a narrow cell; only a hard case (and
## the free arm beside it) follows it.
func front_weight_of(id: int) -> float:
	return _front_weight(_held.get(id, {}), _now())


## How far the hard case (or lifted roller) of passenger `id` has turned to
## the front carry: 0 side, 1 front (_bag_weight).
func bag_turn_of(id: int) -> float:
	return _bag_weight(_held.get(id, {}), _now())


## How many times bag `index` of passenger `id` has been put in place (a move
## only stamped, not placed, does not count): a bag in a hand once for each
## skeleton report after a draw, or once before the frame is drawn.
func placements_of(id: int, index: int) -> int:
	return int(_bag_of(id, index).get("placed", 0))


## How many draws bag `index` of passenger `id` has been taken a step on while
## going to a hand (_step_hand_bags): one per draw.
func steps_of(id: int, index: int) -> int:
	return int(_bag_of(id, index).get("steps", 0))


## How many steps the axle follower of bag `index` of passenger `id` (a pulled
## roller) has taken (_axle_drawn): one per draw while it is pulled.
func follows_of(id: int, index: int) -> int:
	return int(_bag_of(id, index).get("follows", 0))


func _bag_of(id: int, index: int) -> Dictionary:
	var bags: Array = _held.get(id, {}).get("bags", [])
	return bags[index] if index < bags.size() else {}


## How many times passenger `id`'s props have been drawn (draw()): once a
## frame, twice on a frame PassengerViews.snap() also draws.
func draws_of(id: int) -> int:
	return int(_held.get(id, {}).get("draw_seq", 0))


## Where the hand holds bag `index` of passenger `id` as the bag is drawn now
## (a hard case or lifted roller in hand: its point at the grip, through the
## side and front carry), or Vector3.INF for a bag not held that way. A check
## compares it with grip_of() before the frame is drawn, to see that the bag
## was placed from the hand's final pose.
func held_point(id: int, index: int) -> Vector3:
	var held: Dictionary = _held.get(id, {})
	var bags: Array = held.get("bags", [])
	if index >= bags.size() or held["homes"][index] != SecurityLooks.Home.HAND:
		return Vector3.INF
	var bag: Dictionary = bags[index]
	if bag.get("carry") != SecurityLooks.Carry.HAND:
		return Vector3.INF
	var ahead := carried_in_front(Vector3.ZERO, 0.0, held["scale"], bag["kind"])
	var held_ahead := ahead.affine_inverse() * Vector3.ZERO
	var at := grip_anchor(bag["kind"]).lerp(held_ahead, held.get("bag_weight", 0.0))
	return (bag["node"] as Node3D).global_transform * at


## How many bag and tray nodes are drawn now.
func drawn_count() -> int:
	var count := 0
	for held: Dictionary in _held.values():
		count += (held["bags"] as Array).size() + int(held["tray"] != null)
	return count


func _ready() -> void:
	RenderingServer.frame_pre_draw.connect(_unposed)


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_unposed):
		RenderingServer.frame_pre_draw.disconnect(_unposed)


## Before the frame is drawn: bags going to a hand, which draw() leaves to
## _on_pose, are placed now when their skeleton did not report after the
## latest draw.
func _unposed() -> void:
	var now := _now()
	for id in _held:
		var held: Dictionary = _held[id]
		var body := views.node_for(id)
		if body == null or held.get("left_to_pose", -1) != Engine.get_process_frames():
			continue
		if held.get("posed_seq", -1) != held["draw_seq"]:
			held["posed_seq"] = held["draw_seq"]
			_place_bags(held, body, _tray_transform(held, body), now, Placing.HAND)


## Places every prop for this frame but the bags going to a hand, and takes
## those a step (_step_hand_bags: once per draw). They are placed from the hand
## each time the character's skeleton reports after this draw (_on_pose), so
## the last report of the frame wins and they never trail the hand, or before
## the frame is drawn (_unposed) if the skeleton did not report after it.
func draw() -> void:
	var now := _now()
	for id in _held:
		var held: Dictionary = _held[id]
		var body := views.node_for(id)
		if body == null:
			continue
		var tray_xf := _tray_transform(held, body)
		if held["tray"] != null:
			(held["tray"] as Node3D).global_transform = tray_xf
		held["weight"] = _front_weight(held, now)
		held["bag_weight"] = _bag_weight(held, now)
		_body_ids[body] = id
		# Bags first: a new move is stamped there, and the arms follow it.
		held["left_to_pose"] = Engine.get_process_frames()
		held["draw_seq"] = int(held.get("draw_seq", 0)) + 1
		_place_bags(held, body, tray_xf, now, Placing.NOT_HAND)
		_step_hand_bags(held, body)
		_pose_arms(held, body, now)


## The once-per-draw part of the bags going to a hand (their moves are stamped
## and the turn weights set in draw() already): each counts the draw, and a
## pulled roller's axle takes its one follower step here (_axle_drawn), so
## placing the bag again on a later report of the same frame never moves it on.
## Placing (_place_bags, Placing.HAND) is then a function of the pose alone.
func _step_hand_bags(held: Dictionary, body: Node3D) -> void:
	var bags: Array = held["bags"]
	for i in bags.size():
		if held["homes"][i] != SecurityLooks.Home.HAND:
			continue
		var bag: Dictionary = bags[i]
		bag["steps"] = int(bag.get("steps", 0)) + 1
		if bag["carry"] == SecurityLooks.Carry.PULL:
			bag["axle_now"] = _axle_drawn(bag, body, held["scale"], held["hands"][i])


## Puts the bags of one passenger in place: only those going to a hand
## (_on_pose(), _unposed()) or all but those (draw()). Every bag's new move is
## stamped, whichever are placed.
func _place_bags(
	held: Dictionary, body: Node3D, tray_xf: Transform3D, now: float, placing: Placing
) -> void:
	var bags: Array = held["bags"]
	var homes: Array = held["homes"]
	for i in bags.size():
		var bag: Dictionary = bags[i]
		var node: Node3D = bag["node"]
		var kind: SecurityLooks.Kind = bag["kind"]
		var hand_home: bool = homes[i] == SecurityLooks.Home.HAND
		var stamp: bool = bag["home"] != bag["place"]
		if (
			not stamp
			and (
				(placing == Placing.HAND and not hand_home)
				or (placing == Placing.NOT_HAND and hand_home)
			)
		):
			continue
		# A bag going to a hand is only stamped here (draw()), so its place
		# (and a roller's follower) is worked out once, when it is placed.
		var stamp_only: bool = placing == Placing.NOT_HAND and hand_home
		var want_reach := [REACH_BUILT_M]
		var want := node.global_transform
		if not stamp_only:
			want = _bag_transform(held, body, tray_xf, i, homes[i], want_reach)
		# A change of hand moves the bag across like a change of home.
		if stamp:
			# The move starts where the bag is, held in the passenger's frame,
			# so a bag picked up while walking stays ahead of the legs. Its clock
			# is the tick sync() saw the change on, not the frame it is drawn in.
			# A new bag's move is over at once, so its start is never drawn.
			var start := want if bag["home"] == -1 else node.global_transform
			bag["from"] = body.global_transform.affine_inverse() * start
			bag["since"] = bag["changed"] - (TRANSFER_TICKS if bag["home"] == -1 else 0.0)
			bag["was"] = bag["home"]
			bag["home"] = bag["place"]
			bag["reach_from"] = _reach_of(node, kind)
			if stamp_only:
				continue
		bag["placed"] = int(bag.get("placed", 0)) + 1
		var k := clampf((now - bag["since"]) / TRANSFER_TICKS, 0.0, 1.0)
		var to_hand: bool = homes[i] == SecurityLooks.Home.HAND
		var from_hand: bool = int(bag.get("was", -1)) / 4 == SecurityLooks.Home.HAND
		var reach: float = want_reach[0]
		if k < 1.0:
			var to_pull: bool = to_hand and bag["carry"] == SecurityLooks.Carry.PULL
			reach = lerpf(
				bag["reach_from"],
				reach,
				_reach_blend(kind, k, to_pull if kind == SecurityLooks.Kind.ROLLER else to_hand)
			)
		_set_reach(node, kind, reach)
		if k >= 1.0:
			node.global_transform = want
			continue
		var frame := body.global_transform
		var pull := SecurityLooks.Carry.PULL
		var overhead_route: bool = (
			(kind == SecurityLooks.Kind.BACKPACK and (to_hand or from_hand))
			or (to_hand and bag["carry"] == pull)
			or (from_hand and bag.get("carry_was", pull) == pull)
		)
		if overhead_route:
			var box := bag_box(kind)
			node.global_transform = (
				frame
				* overhead(
					bag["from"],
					frame.affine_inverse() * want,
					k,
					box,
					ROLLER_LAND if kind == SecurityLooks.Kind.ROLLER else 1.0
				)
			)
			continue
		var start_now := frame * (bag["from"] as Transform3D)
		var placed := start_now.interpolate_with(want, k)
		# A bag going up rises first and then comes across (picked up from
		# the floor, it clears the legs); one going down is lifted on the
		# way, over a table edge rather than through it. Either way it is
		# kept TRANSFER_CLEAR_M from the body's centre line, on its hand's side.
		var arc := 4.0 * k * (1.0 - k)
		if want.origin.y > start_now.origin.y:
			var across := start_now.origin.lerp(want.origin, k * k)
			placed.origin.x = across.x
			placed.origin.z = across.z
			placed.origin.y = lerpf(start_now.origin.y, want.origin.y, 1.0 - pow(1.0 - k, 4.0))
			# Over the knee that steps forward, early in the move, and gone
			# before the bag comes in under the arm that will hold it.
			var early := 6.75 * k * (1.0 - k) * (1.0 - k) * pow(1.0 - k * k, 4.0)
			placed.origin.y += KNEE_LIFT_M * early
		else:
			placed.origin.y += TRANSFER_LIFT_M * arc
		var hand: int = held["hands"][i]
		if kind == SecurityLooks.Kind.SHOULDER:
			hand = SecurityLooks.worn_side(i)
		placed.origin += _keep_out(placed.origin, body, hand) * minf(arc * 2.0, 1.0)
		node.global_transform = placed


## How far a strap or rod has gone from its old length to its new one at `k`
## of a move: a shoulder strap stretches in the last 15% of the move, as the
## bag comes in from outside the hip with the hand already up (_pose_arms), and
## goes slack early; a roller's rods come out only once it is down behind the
## body and go in before it rises.
static func _reach_blend(kind: SecurityLooks.Kind, k: float, to_hand: bool) -> float:
	if kind == SecurityLooks.Kind.ROLLER:
		# The rods stay in until the roller is down behind (ROLLER_LAND) and go
		# in before it rises.
		if to_hand:
			return clampf((k - ROLLER_LAND) / (1.0 - ROLLER_LAND), 0.0, 1.0)
		return clampf(k * 3.0, 0.0, 1.0)
	if kind != SecurityLooks.Kind.SHOULDER:
		return k
	if to_hand:
		return clampf((k - 0.85) / 0.15, 0.0, 1.0)
	return clampf(k / 0.4, 0.0, 1.0)


## How far to push a moving bag at `at` out to TRANSFER_CLEAR_M from the
## body's centre line (zero when it is already that far out); a bag on the
## centre line goes out on the side of `hand` (0 right, 1 left).
func _keep_out(at: Vector3, body: Node3D, hand: int) -> Vector3:
	var away := at - body.global_position
	away.y = 0.0
	var gap := away.length()
	if gap >= TRANSFER_CLEAR_M:
		return Vector3.ZERO
	if gap < 0.05:
		away = Basis(Vector3.UP, body.rotation.y) * (Vector3.LEFT if hand == 0 else Vector3.RIGHT)
	return away.normalized() * (TRANSFER_CLEAR_M - gap)


## How far passenger `held` has turned to the front carry at sim time `now`,
## 0 (side) to 1 (front), over TRANSFER_TICKS.
func _front_weight(held: Dictionary, now: float) -> float:
	var target := 1.0 if held.get("front", false) else 0.0
	if not held.has("front_since"):
		return target
	var k := clampf((now - held["front_since"]) / TRANSFER_TICKS, 0.0, 1.0)
	# Fast at first: a side-carried bag is the widest thing, so it comes in
	# before the passenger reaches the narrow cell.
	return lerpf(held["front_from"], target, 1.0 - (1.0 - k) * (1.0 - k))


## How far a hard case in hand (or a lifted roller) has turned to the front
## carry at sim time `now`, 0 to 1. To the front it eases as the arm does
## (_front_weight); back to the side it turns faster, upright ahead of the arm
## (from the front, the arm's weight squared), so its lower end is not swung
## through the thigh as the hand comes out (the arm's own pace measured 5 body
## points inside the case, its square none: windowed bench, 2026-10-29). A
## turn that reverses starts from where the bag is (bag_from).
func _bag_weight(held: Dictionary, now: float) -> float:
	var front: bool = held.get("front", false)
	if not held.has("front_since"):
		return 1.0 if front else 0.0
	var k := clampf((now - held["front_since"]) / TRANSFER_TICKS, 0.0, 1.0)
	if front:
		return lerpf(held["bag_from"], 1.0, 1.0 - (1.0 - k) * (1.0 - k))
	return lerpf(held["bag_from"], 0.0, 1.0 - pow(1.0 - k, 4.0))


## The skeleton of `body` reported a pose: its bags going to a hand are put on
## the hand as it is now. A report before this frame's draw() (a pose set
## before the views draw, such as a seek) is not the final one: the draw moves
## the body and sets the arms, and the skeleton reports again after it, so it
## places nothing. Every report after a draw places them again, from the pose
## it reports, so the frame's last report wins; placing only reads the pose and
## what draw() stepped (_step_hand_bags), so a repeat moves nothing on. A draw
## no report followed has them placed before the frame is drawn (_unposed).
func _on_pose(body: Node3D) -> void:
	var id: int = _body_ids.get(body, 0)
	var held: Dictionary = _held.get(id, {})
	if held.is_empty() or views.node_for(id) != body:
		return
	if held.get("left_to_pose", -1) != Engine.get_process_frames():
		return
	held["posed_seq"] = held["draw_seq"]
	_place_bags(held, body, _tray_transform(held, body), _now(), Placing.HAND)


## Where hand `i` (right, then left) of a character grips a bag now.
func grip_of(body: Node3D, i: int) -> Vector3:
	var grips: Array = _rig(body)["grips"]
	var grip: BoneAttachment3D = grips[i % grips.size()]
	return grip.global_position + grip.global_basis.y.normalized() * GRIP_ALONG_M


## Where the Arm bone (shoulder joint) of side `i` of a character is now.
func _shoulder_of(body: Node3D, i: int) -> Vector3:
	return (_rig(body)["shoulders"][i] as Node3D).global_position


## The Spine_03 bone of a character now (world).
func _spine_of(body: Node3D) -> Transform3D:
	return (_rig(body)["spine"] as Node3D).global_transform


func _now() -> float:
	return clock.tick + clock.alpha if clock != null else 0.0


## The sim tick a change seen in sync() happened on.
func _tick() -> float:
	return float(clock.tick) if clock != null else 0.0


## Moves a pulled roller's axle one tick on: TRAIL_M back along the line
## walked by a point TRAIL_SIDE_M out on the pulling hand's side of the body's
## tick position (tick_position, as drawn); any other bag has none.
func _trail(bag: Dictionary, body: Node3D, id: int, home: SecurityLooks.Home, hand: int) -> void:
	if bag["carry"] != SecurityLooks.Carry.PULL or home != SecurityLooks.Home.HAND:
		bag.erase("axle")
		bag.erase("walked")
		return
	var side := Vector3.LEFT if hand == 0 else Vector3.RIGHT
	# The heading the body is drawn with for this tick (PassengerViews.draw()
	# turns it to the step from the last tick position to this one).
	var at := views.tick_position(id, true)
	var step := at - views.tick_position(id, false)
	var yaw := atan2(step.x, step.z) if step.length() > 0.001 else body.rotation.y
	var turn := Basis(Vector3.UP, yaw)
	var now := at + turn * side * TRAIL_SIDE_M
	var walked: Array = bag.get("walked", [])
	if walked.is_empty() or (walked[-1] as Vector3).distance_to(now) > 0.01:
		walked.append(now)
	# Only as much of the walk as the trail needs.
	var length := 0.0
	for i in range(walked.size() - 1, 0, -1):
		length += (walked[i] as Vector3).distance_to(walked[i - 1])
		if length > TRAIL_M + 0.5:
			walked = walked.slice(i - 1)
			break
	var behind := turn * Vector3.FORWARD
	var cur := trail(walked, behind)
	if (cur - now).dot(behind) < 0.0:
		# The walker turned back past its roller (it is ahead now, not round a
		# corner beside it): the roller swings round behind it over the next
		# tick (drawn from where it was) rather than the walker crossing the
		# rods.
		walked = [now]
		cur = trail(walked, behind)
	bag["walked"] = walked
	# Kept behind the walker on the pulling hand's side, so the rods never
	# cross behind the legs to the other side (a zig-zag of diagonal steps
	# swings the walked line about the body's heading).
	var frame := Transform3D(turn, at)
	var local := frame.affine_inverse() * cur
	var out := -1.0 if hand == 0 else 1.0
	local.x = out * clampf(local.x * out, TRAIL_SIDE_MIN_M, TRAIL_SIDE_MAX_M)
	local.z = minf(local.z, -TRAIL_BEHIND_MIN_M)
	cur = frame * local
	bag["axle"] = [bag["axle"][1] if bag.has("axle") else cur, cur]


## Poses each arm of `body` for the bags it holds now (CarryArm): a hand with
## a hard case, a hand pulling a roller, a hand on a shoulder strap (as the bag
## comes onto the shoulder), or free; a free hand and a hard case's hand follow
## the front-carry turn while a hard case is carried.
func _pose_arms(held: Dictionary, body: Node3D, now: float) -> void:
	var modes := [Arm.FREE, Arm.FREE]
	var strap := [0.0, 0.0]
	var cases := 0
	var homes: Array = held["homes"]
	for i in homes.size():
		var bag: Dictionary = held["bags"][i]
		var k := _progress_of(bag, now)
		var hand: int = held["hands"][i]
		match bag["carry"]:
			SecurityLooks.Carry.HAND:
				if homes[i] == SecurityLooks.Home.HAND:
					modes[hand] = Arm.HAND
					cases += 1
			SecurityLooks.Carry.PULL:
				if homes[i] == SecurityLooks.Home.HAND:
					modes[hand] = Arm.PULL
			SecurityLooks.Carry.SHOULDER:
				var side := SecurityLooks.worn_side(i)
				var was_hand: bool = int(bag.get("was", -1)) / 4 == SecurityLooks.Home.HAND
				# The hand is on the strap before it stretches (_reach_blend) and
				# lets go after it is slack.
				var on := 0.0
				if homes[i] == SecurityLooks.Home.HAND:
					on = clampf(k / 0.6, 0.0, 1.0)
				elif was_hand:
					on = 1.0 - clampf((k - 0.4) / 0.6, 0.0, 1.0)
				if on > 0.0:
					modes[side] = Arm.STRAP
					strap[side] = on
	# The arms keep what was set until it changes (most frames nothing does).
	var key := [modes, strap, cases, held["weight"]]
	if held.get("arm_key", []) == key and held.get("arm_body") == body:
		return
	held["arm_key"] = key
	held["arm_body"] = body
	var arms: Array = _rig(body)["arms"]
	for side in arms.size():
		var arm := arms[side] as CarryArm
		arm.holds = modes[side] == Arm.HAND or modes[side] == Arm.PULL
		arm.active = modes[side] != Arm.FREE or cases > 0
		var pulling: bool = modes[side] == Arm.PULL
		arm.angle_degrees = PULL_OUT_DEGREES if pulling else 12.0
		arm.swing_kept = PULL_SWING_KEPT if pulling else 0.5
		arm.lean_back_degrees = PULL_LEAN_DEGREES if pulling else 0.0
		arm.front_upper_degrees = 0.0 if modes[side] == Arm.STRAP else 20.0
		arm.front_up_degrees = STRAP_HAND_UP_DEGREES if modes[side] == Arm.STRAP else -10.0
		match modes[side]:
			Arm.STRAP:
				arm.front_half_width = STRAP_HAND_M
				arm.front_weight = strap[side]
			Arm.PULL:
				arm.front_weight = 0.0
			Arm.HAND:
				arm.front_half_width = FRONT_ONE_BAG_M if cases < 2 else FRONT_TWO_BAGS_M
				arm.front_weight = held["weight"]
			_:
				arm.front_half_width = FRONT_FREE_HAND_M
				arm.front_weight = held["weight"] if cases > 0 else 0.0


## How far `bag` is through its move at sim time `now` (1 when settled or
## not started).
func _progress_of(bag: Dictionary, now: float) -> float:
	if not bag.has("since"):
		return 1.0
	return clampf((now - bag["since"]) / TRANSFER_TICKS, 0.0, 1.0)


## Turns off both CarryArms of a character with no bags.
func _arms_off(body: Node3D) -> void:
	if not body.has_meta(&"carry_rig"):
		return
	for arm: CarryArm in _rig(body)["arms"]:
		arm.active = false
		arm.front_weight = 0.0


## A character's grip, shoulder and spine attachments and CarryArm modifiers,
## made the first time and kept on the pooled character.
func _rig(body: Node3D) -> Dictionary:
	if body.has_meta(&"carry_rig"):
		return body.get_meta(&"carry_rig")
	var skeleton := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var rig := {"grips": [], "arms": [], "shoulders": [], "spine": _attach(skeleton, SPINE_BONE)}
	for side in GRIP_BONES.size():
		rig["grips"].append(_attach(skeleton, GRIP_BONES[side]))
		rig["shoulders"].append(_attach(skeleton, ARM_BONES[side]))
		var arm := CarryArm.new()
		arm.name = "CarryArm%d" % side
		arm.side = side
		arm.active = false
		skeleton.add_child(arm)
		rig["arms"].append(arm)
	# After the attachments (connected when added), so they are current.
	skeleton.skeleton_updated.connect(_on_pose.bind(body))
	body.set_meta(&"carry_rig", rig)
	return rig


func _attach(skeleton: Skeleton3D, bone: String) -> BoneAttachment3D:
	var at := BoneAttachment3D.new()
	at.name = "Carry_" + bone.replace(".", "_")
	at.bone_name = bone
	skeleton.add_child(at)
	return at


func _tray_transform(held: Dictionary, body: Node3D) -> Transform3D:
	var lane: Dictionary = held["lane"]
	match held["tray_at"]:
		SecurityLooks.Tray.RIDE:
			return ride(sim.grid, lane, body.global_position)
		SecurityLooks.Tray.IN, SecurityLooks.Tray.OUT:
			var mount: Array = TRAY_MOUNTS[held["tray_at"]]
			return mount_world(sim.grid, lane, mount[0], mount[1])
	return Transform3D.IDENTITY


## Bag `i`'s transform for its home now; `reach` gets its strap or rod length.
func _bag_transform(
	held: Dictionary, body: Node3D, tray_xf: Transform3D, i: int, home: int, reach: Array
) -> Transform3D:
	var scale_by: float = held["scale"]
	var kind: SecurityLooks.Kind = held["bags"][i]["kind"]
	var yaw := Basis(Vector3.UP, body.rotation.y)
	var count: int = held["bags"].size()
	match home:
		SecurityLooks.Home.TRAY:
			var at := SecurityLooks.in_tray(i, count, bag_size(kind).z)
			# Centred by its bounds: a grab loop or a grip bar makes a kind
			# longer at one end.
			at.z -= bag_box(kind).get_center().z * scale_by
			at.y += TRAY_FLOOR_M
			return Transform3D(tray_xf.basis.scaled(Vector3.ONE * scale_by), tray_xf * at)
		SecurityLooks.Home.FLOOR:
			var spot: Transform3D = held["floor"][i]
			var placed := Transform3D(yaw, body.global_position) * spot
			placed.origin.y = sim.grid.origin.y
			return Transform3D(placed.basis.scaled(Vector3.ONE * scale_by), placed.origin)
	return _carry_transform(held, body, i, reach)


## A carried bag's transform, its kind's way (the header).
func _carry_transform(held: Dictionary, body: Node3D, i: int, reach: Array) -> Transform3D:
	var scale_by: float = held["scale"]
	var node: Node3D = held["bags"][i]["node"]
	match held["bags"][i]["carry"]:
		SecurityLooks.Carry.BACK:
			return worn_back(_spine_of(body), body.rotation.y, scale_by)
		SecurityLooks.Carry.SHOULDER:
			var side := SecurityLooks.worn_side(i)
			var hung := worn_shoulder(
				_shoulder_of(body, side),
				body.global_position,
				body.rotation.y,
				side,
				scale_by,
				_reach_base(_part(node, "Strap_Reach"))
			)
			reach[0] = hung[1]
			return hung[0]
		SecurityLooks.Carry.PULL:
			var grip := grip_of(body, held["hands"][i])
			# The axle this draw stepped to (_step_hand_bags).
			var axle: Vector3 = held["bags"][i].get("axle_now", Vector3.INF)
			if not axle.is_finite():
				axle = _axle_drawn(held["bags"][i], body, scale_by, held["hands"][i])
			var rods := _reach_base(_part(node, "Pull_Reach"))
			reach[0] = _pull_length(grip, axle, scale_by, rods.z)
			return pulled(grip, axle, scale_by)
	return _case_transform(held, body, i)


## A hard case in the hand: between side and front carry it stays in the
## hand, turning as the arm turns (_bag_weight).
func _case_transform(held: Dictionary, body: Node3D, i: int) -> Transform3D:
	var scale_by: float = held["scale"]
	var grip := grip_of(body, held["hands"][i])
	var kind: SecurityLooks.Kind = held["bags"][i]["kind"]
	var side_xf := carried(grip, body.global_position, body.rotation.y, scale_by, kind)
	var weight: float = held.get("bag_weight", 0.0)
	if weight <= 0.0:
		return side_xf
	var ahead := carried_in_front(grip, body.rotation.y, scale_by, kind)
	if weight >= 1.0:
		return ahead
	# Turned about the grip: the bag's point held in the hand moves across its
	# surface from the side carry's to the front carry's, and stays at the hand.
	var held_side := side_xf.affine_inverse() * grip
	var held_ahead := ahead.affine_inverse() * grip
	var turn := side_xf.basis.get_rotation_quaternion().slerp(
		ahead.basis.get_rotation_quaternion(), weight
	)
	var basis := Basis(turn).scaled(Vector3.ONE * scale_by)
	return Transform3D(basis, grip - basis * held_side.lerp(held_ahead, weight))


## A pulled roller's axle drawn now, on the floor under the body (the wheels'
## radius up), kept behind it on the pulling hand's side; straight behind the
## body before sync() has started one.
func _axle_drawn(bag: Dictionary, body: Node3D, scale_by: float, hand: int) -> Vector3:
	var at: Vector3
	if bag.has("axle"):
		var alpha := clock.alpha if clock != null else 1.0
		at = (bag["axle"][0] as Vector3).lerp(bag["axle"][1], alpha)
	else:
		at = body.global_position + Basis(Vector3.UP, body.rotation.y) * Vector3.FORWARD * TRAIL_M
	# Behind the body as drawn now, on the pulling hand's side: between two
	# ticks of a turning walker the blend can cross behind the legs.
	var frame := Transform3D(Basis(Vector3.UP, body.rotation.y), body.global_position)
	var local := frame.affine_inverse() * at
	var out := -1.0 if hand == 0 else 1.0
	local.x = out * clampf(local.x * out, TRAIL_SIDE_MIN_M, TRAIL_SIDE_MAX_M)
	local.z = minf(local.z, -TRAIL_BEHIND_MIN_M)
	var now := _now()
	at = frame * local
	if bag.has("drawn_axle"):
		var was := frame.affine_inverse() * (bag["drawn_axle"] as Vector3)
		at = frame * follow(was, local, maxf(now - bag["drawn_at"], 0.0), hand)
	at.y = body.global_position.y + ROLLER_AXLE.y * scale_by
	bag["drawn_axle"] = at
	bag["drawn_at"] = now
	bag["follows"] = int(bag.get("follows", 0)) + 1
	return at


## A strap or rod node's position as built (before any stretch).
func _reach_base(node: Node) -> Vector3:
	return node.get_meta(&"base", (node as Node3D).position)


## The strap or rod length of a bag node now (REACH_BUILT_M for a kind with
## none).
func _reach_of(node: Node3D, kind: SecurityLooks.Kind) -> float:
	if not REACH_NODES.has(kind):
		return REACH_BUILT_M
	var reach := _part(node, REACH_NODES[kind][0])
	return reach.scale.z * REACH_BUILT_M


## Stretches a bag's strap or rods to `length` (in the bag's units) along its
## +z and moves the bar or grip to their end.
func _set_reach(node: Node3D, kind: SecurityLooks.Kind, length: float) -> void:
	if not REACH_NODES.has(kind):
		return
	var names: Array = REACH_NODES[kind]
	var reach := _part(node, names[0])
	var top := _part(node, names[1])
	for part: Node3D in [reach, top]:
		if not part.has_meta(&"base"):
			part.set_meta(&"base", part.position)
	reach.scale = Vector3(1.0, 1.0, length / REACH_BUILT_M)
	top.position = _reach_base(top) + Vector3(0.0, 0.0, length - REACH_BUILT_M)


## A named part of a bag node (a strap or rod node), found once and kept.
func _part(node: Node3D, part: String) -> Node3D:
	var parts: Dictionary = node.get_meta(&"parts", {})
	if not parts.has(part):
		parts[part] = node.find_child(part, true, false)
		node.set_meta(&"parts", parts)
	return parts[part]


func _take(piece: String) -> Node3D:
	var pool: Array = _free_bags.get(piece, [])
	if piece == "security_tray":
		pool = _free_trays
	if not pool.is_empty():
		var reused: Node3D = pool.pop_back()
		reused.visible = true
		return reused
	var node := InteriorKit.instantiate(piece)
	add_child(node)
	return node


func _give(piece: String, node: Node3D) -> void:
	node.visible = false
	for kind in REACH_NODES:
		if SecurityLooks.KIND_PIECES[kind] == piece:
			_set_reach(node, kind, REACH_BUILT_M)
	if piece == "security_tray":
		_free_trays.append(node)
		return
	if not _free_bags.has(piece):
		_free_bags[piece] = []
	_free_bags[piece].append(node)
