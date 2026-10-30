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
## A roller is lifted and carried in the hand while its walker is at security
## (narrow lane cells and tables) or runs (a long stride kicks back into a
## trailing case), hung by its grip bar, rods in, and it goes between that and
## the pull by the bar (_swap_transform: the rods run out or in from the hand
## as the axle goes between under the hand and behind the walker). Worn bags
## keep their carry in a narrow cell: only a hand-carried bag turns to the
## front. At a toilet stall (StallCarry) a roller and a backpack are taken in
## the hand too (the backpack by its grab loop) and every hand-carried bag is
## held in front, from just before the stall until the walker is clear of it;
## inside, a bag goes between the hand and the floor without the lift and the
## push out: set down it turns round with the body already upright against the
## door and goes straight down; picked up it rises upright first.
##
## A bag that changes home (or hand) moves there over TRANSFER_TICKS of sim
## time (the clock's tick plus its alpha; CarryLead.ticks_of(): a roller that
## parks on its wheels, RollerPark.TICKS), led by the hand outside a stall
## (CarryLead: the hand reaches a bag on the floor, in a tray, on the back or
## the shoulder first, bending down for a low one (CarryStoop), the bag is
## placed from the grip along its path, and the hand lets go once it is down);
## the path is lifted and kept out from the body, and a bag picked up from the
## floor ahead passes outside the thigh (CarryMoves). There is no overhead
## route (decision carry-on-bags-stay-in-the-hand-during-every-move-no-
## overhead). In a turn between side and front carry the holding arm reaches
## further forward, so the turning bag passes ahead of the thighs, and at a
## basic scanner the bags go to the front BoothCarry.LEAD_M before the booth.
## It reads the sim and the views and never writes either.

enum Arm { FREE, HAND, PULL, STRAP }
## Which bags _place_bags() places.
enum Placing { HAND, NOT_HAND }

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
## How much further forward the holding upper arm reaches half way through a
## turn between the side and the front carry (_pose_arms).
const TURN_REACH_DEGREES := 45.0
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
## A roller going between the hand and the pull by its bar (_swap_transform)
## swings out this far on the hand's side midway, clear of the trailing leg
## (0.15 m put it into a neighbouring stall's partition end from the row); at
## security it goes round the hand's side instead (CarryLead.swap_axle).
const SWAP_OUT_M := 0.08
## A roller held by its bar for a stall has the bar this far from the grip
## point, toward the bag's front (in the palm, a grip offset along the hand's
## axes): hung at the side the bag is that much further from the leg, across
## the front that much lower, under the holding forearm. Pulled, none.
const BAR_PALM_M := 0.06
## How far a roller held by its bar rolls up across the front (_barred): 60
## degrees, not lying flat, so its far end stays short of the free forearm.
const FRONT_ROLL := PI / 3.0
## A bag picked up from a stall's floor goes this much further ahead of the
## walker while it rises (the leading foot reaches 0.3-0.35 m ahead of the
## body's centre, the bag stands 0.29 m ahead).
const PICK_AHEAD_M := 0.2
## The roller's carry handle (build_carry_on_kit.py Roller_Handle), where a
## lifted roller is held.
const ROLLER_HANDLE := Vector3(0.0, 0.225, 0.165)
## The backpack's grab loop (build_carry_on_kit.py Pack_Loop), its top, where
## a backpack taken in hand at a toilet stall is held (StallCarry).
const BACKPACK_LOOP := Vector3(0.0, 0.082, 0.235)
## A stretchable strip or rod as built (build_carry_on_kit.py REACH_BUILT).
const REACH_BUILT_M := 0.02
## Kind -> [the stretched node, the node moved to its end].
const REACH_NODES := {
	SecurityLooks.Kind.SHOULDER: ["Strap_Reach", "Strap_Top"],
	SecurityLooks.Kind.ROLLER: ["Pull_Reach", "Pull_Top"],
}
## A roller going to the pull (not hand-led, _reach_blend) has its rods in for
## this much of the move; they then come out to the hand.
const ROLLER_LAND := 0.85
## A shoulder bag going to the shoulder is in place by this much of the move,
## when its strap starts to stretch (_reach_blend).
const STRAP_PLACED := 0.85

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
## Passenger id -> the tick its record was last released (release()), so a
## record made again on that tick (after a load) is told from a new one.
var _released_at := {}
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
## roller's carry handle, a backpack's grab loop.
static func grip_anchor(kind: SecurityLooks.Kind) -> Vector3:
	if kind == SecurityLooks.Kind.ROLLER:
		return ROLLER_HANDLE
	if kind == SecurityLooks.Kind.BACKPACK:
		return BACKPACK_LOOP
	var box := bag_box(kind)
	return Vector3(0.0, box.end.y, box.end.z)


## A hard case carried in front of the body (a cell closed on both sides):
## lying flat across the body, its handle on top just under the hand at `grip`
## (FRONT_PALM_M below the knuckles). A backpack hangs from its grab loop at the
## grip, its back panel to the body (CarryWorn.loop_in_front).
static func carried_in_front(
	grip: Vector3, yaw: float, scale_by: float, kind := SecurityLooks.Kind.CASE
) -> Transform3D:
	if kind == SecurityLooks.Kind.BACKPACK:
		return CarryWorn.loop_in_front(grip, yaw, scale_by)
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


## A roller pulled by its grip at `grip` with its axle at `axle` (on the floor,
## the wheels' radius up): its length along the line from the axle to the grip,
## its back panel (rods, wheels) down toward the walker: its front faces `ref`
## (up, or out to the side for one hung from the hand by its bar) as far as
## the line allows.
static func pulled(grip: Vector3, axle: Vector3, scale_by: float, ref := Vector3.UP) -> Transform3D:
	var along := (grip - axle).normalized()
	var up := ref - along * along.dot(ref)
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
	for id: int in _released_at.keys():
		if _released_at[id] < _tick():
			_released_at.erase(id)
	for id in sim.passenger_ids():
		var node := views.node_for(id)
		if node == null:
			continue
		var p := sim.get_passenger(id)
		var homes := SecurityLooks.bag_homes(sim, p)
		var tray_at := SecurityLooks.tray(sim, p)
		# A basic scanner booth tucks the free arms in, with bags or without
		# (decision basic-scanner-booth-passengers-carry-their-bags-in-front-
		# and), so a passenger with none is kept until its arms are back out.
		var booth := SecurityLooks.in_booth_passage(sim, p)
		# Bags go to the front (a roller into the hand first) before the booth.
		var booth_bags := booth or BoothCarry.approaching(sim, p)
		# A lane's arch tucks the arms too, its bags in the tray.
		var tuck_in := booth or SecurityLooks.in_arch_passage(sim, p)
		var tucked := tuck_in or BoothCarry.tuck_weight(_held.get(id, {}), _tick()) > 0.0
		if homes.is_empty() and not tucked:
			_arms_off(node)
		if homes.is_empty() and tray_at == SecurityLooks.Tray.NONE and not tucked:
			continue
		seen[id] = true
		var hands: Array[int] = []
		var kinds: Array[SecurityLooks.Kind] = []
		var lifts: Array[bool] = []
		var at_stall := StallCarry.held_by_hand(sim, p)
		# A roller is taken in hand before the turn to the front (StallCarry).
		var lift_stall := StallCarry.held_by_hand(sim, p, StallCarry.LIFT_LEAD_M)
		for i in homes.size():
			kinds.append(SecurityLooks.bag_kind(p, i))
			var roller := kinds[i] == SecurityLooks.Kind.ROLLER
			lifts.append(_lifted(kinds[i], p, lift_stall if roller else at_stall, booth_bags))
			# A worn bag keeps its side, so a narrow cell never moves it across.
			var worn: bool = (
				not lifts[i]
				and (
					SecurityLooks.KIND_CARRY[kinds[i]]
					in [SecurityLooks.Carry.BACK, SecurityLooks.Carry.SHOULDER]
				)
			)
			hands.append(SecurityLooks.worn_side(i) if worn else SecurityLooks.hand_of(sim, p, i))
		# A stall is closed on both sides, its approach as good as (StallCarry).
		var front := SecurityLooks.carry_front(sim, p) or at_stall or booth_bags
		var held: Dictionary = _held.get(id, {"tray": null, "bags": []})
		_held[id] = held
		# A tray kept for a bag still moving out of it stays where it was, on the
		# lane it was on: its passenger may have lost the lane (finished, sent
		# back, the station closed), and lane_of() is then empty.
		if tray_at != SecurityLooks.Tray.NONE or held["tray"] == null:
			held["tray_at"] = tray_at
			held["lane"] = SecurityLooks.lane_of(sim, p)
		held["homes"] = homes
		held["hands"] = hands
		held["kinds"] = kinds
		held["in_stall"] = StallCarry.in_stall(p)
		held["security"] = p.stage in [Passenger.Stage.SECURITY_QUEUE, Passenger.Stage.SECURITY]
		held["stall"] = StallCarry.stall_of(sim, p)
		# At a booth a roller's lift into the hand ends before the front turn.
		if booth_bags and BoothCarry.roller_rising(held, kinds, lifts, _tick()):
			front = false
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
		# A record made again after a load (PassengerViews.snap() releases every
		# record, then syncs on the same tick) starts in the tuck it needs.
		BoothCarry.update_tuck(held, tuck_in, _released_at.get(id, -1.0) == _tick(), _tick())
		# A roller held by its bar for a stall stays in hand until the turn back
		# from the front has finished, so it goes to the pull from the side, and,
		# held in the hand the walk would not pull it in, until it is clear of
		# the stalls by StallCarry.LIFT_LEAD_M more, so it is pulled in that hand
		# away from them. The front itself follows the stall alone.
		var was: Array = held["bags"]
		# A roller lifted at a booth stays in hand until the turn back has ended.
		var kept := BoothCarry.kept_lifted(
			held,
			kinds,
			lifts,
			_front_weight(held, _tick()),
			BoothCarry.tuck_weight(held, _tick()),
			booth_bags
		)
		for i in kinds.size():
			lifts[i] = lifts[i] or kept[i]
		for i in mini(was.size(), kinds.size()):
			if (
				not lifts[i]
				and was[i]["kind"] == kinds[i]
				and was[i].get("by_bar", false)
				and (
					_front_weight(held, _tick()) > 0.0
					or (
						SecurityLooks.hand_of(sim, p, i) != (int(was[i]["place"]) / 2) % 2
						and StallCarry.leaving(sim, p, StallCarry.LIFT_LEAD_M)
					)
				)
			):
				lifts[i] = true
			# A roller going between the hand and the pull by its bar keeps its
			# hand until it is there, and one held by its bar keeps its hand while
			# it is, so the pull starts in that hand (a change of hand would be a
			# move of its own, off the bar).
			if (
				was[i]["kind"] == kinds[i]
				and (
					(
						was[i].get("by_bar", false)
						and (lift_stall or StallCarry.leaving(sim, p, StallCarry.LIFT_LEAD_M))
					)
					or (
						was[i].get("swap", false)
						and (
							_tick() - float(was[i].get("changed", -INF))
							< CarryLead.ticks_of(was[i])
						)
					)
				)
			):
				hands[i] = (int(was[i]["place"]) / 2) % 2
		held["scale"] = SecurityLooks.bag_scale(p)
		var spots: Array[Transform3D] = []
		for i in homes.size():
			spots.append(SecurityLooks.floor_spot(sim, p, i, homes.size()))
		held["floor"] = spots
		if tray_at != SecurityLooks.Tray.NONE and held["tray"] == null:
			held["tray"] = _take("security_tray")
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
			var lifted := lifts[i]
			var carry: SecurityLooks.Carry = (
				SecurityLooks.Carry.HAND if lifted else SecurityLooks.KIND_CARRY[kinds[i]]
			)
			var place: int = (homes[i] * 2 + hands[i]) * 2 + int(lifted)
			# A lifted roller hangs by its grip bar (_case_transform) and goes
			# between the hand and the pull by the bar (decision carry-on-bags-
			# stay-in-the-hand-during-every-move-no-overhead).
			var by_bar: bool = lifted and kinds[i] == SecurityLooks.Kind.ROLLER
			# A roller lifted before and now that stops or starts being held by its
			# bar for a stall (its walker turns late, or reaches security) moves
			# between the two grips, not snaps: a new move, not a swap.
			var was_lifted: bool = int(bags[i].get("place", 0)) % 2 == 1
			if lifted and was_lifted and bags[i].get("by_bar", by_bar) != by_bar:
				bags[i]["place"] = -2
			if bags[i].get("place", -2) != place:
				# Only the lift changed, in the same hand, on a roller held by its
				# bar before or after: it goes to or from the pull by the bar.
				var old: int = bags[i].get("place", -2)
				bags[i]["swap"] = (
					kinds[i] == SecurityLooks.Kind.ROLLER
					and homes[i] == SecurityLooks.Home.HAND
					and old >= 0
					and old / 2 == place / 2
					and (by_bar or bags[i].get("by_bar", false))
				)
				bags[i]["place"] = place
				bags[i]["changed"] = _tick()
				bags[i]["carry_was"] = bags[i].get("carry", carry)
			bags[i]["carry"] = carry
			bags[i]["by_bar"] = by_bar
			_trail(bags[i], node, id, homes[i], hands[i])
		# The tray goes once no bag is moving out of it (the hand takes a bag
		# from the tray before the tray is gone).
		var moving := bags.any(
			func(b: Dictionary) -> bool:
				return _tick() - float(b.get("changed", -INF)) < CarryLead.ticks_of(b)
		)
		if tray_at == SecurityLooks.Tray.NONE and held["tray"] != null and not moving:
			_give("security_tray", held["tray"])
			held["tray"] = null
			held["tray_at"] = tray_at
			held["lane"] = SecurityLooks.lane_of(sim, p)
	for id in _held.keys():
		if not seen.has(id):
			release(id)


## Whether a bag of `kind` is lifted by its handle and carried as the hard
## case is: a roller through security (narrow lane cells, tables) and while
## its walker runs (a long stride kicks back into a trailing case), and a
## roller or a backpack at a toilet stall (`at_stall`, StallCarry). A roller
## is also lifted through a basic scanner booth's passage (`at_booth`,
## SecurityLooks.in_booth_passage), from the queue front at its entry.
static func _lifted(
	kind: SecurityLooks.Kind, p: Passenger, at_stall: bool, at_booth := false
) -> bool:
	var roller := kind == SecurityLooks.Kind.ROLLER
	if roller and (p.stage == Passenger.Stage.SECURITY or p.late or at_booth):
		return true
	return at_stall and kind in [SecurityLooks.Kind.ROLLER, SecurityLooks.Kind.BACKPACK]


## Returns every prop of passenger `id` to the pool.
func release(id: int) -> void:
	_released_at[id] = _tick()
	# Its pooled body goes back with no reach or stoop of this passenger's
	# moves: the next passenger it draws may have no bag to reach for.
	for body: Node3D in _body_ids.keys():
		if _body_ids[body] == id:
			_arms_off(body)
			_body_ids.erase(body)
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
	return _progress_of(bags[index], _now())


## How far passenger `id` has turned to the front carry: 0 side, 1 front.
## The turn runs for every passenger in a narrow cell; only a hard case (and
## the free arm beside it) follows it.
func front_weight_of(id: int) -> float:
	return _front_weight(_held.get(id, {}), _now())


## How far passenger `id` has tucked its free arms in for a booth or an arch:
## 0 swinging, 1 tucked (BoothCarry.tuck_weight).
func tuck_of(id: int) -> float:
	return BoothCarry.tuck_weight(_held.get(id, {}), _now())


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


## A copy of the record of bag `index` of passenger `id` (_held's "bags"
## entry), for checks; {} when there is none.
func bag_state(id: int, index: int) -> Dictionary:
	return _bag_of(id, index).duplicate()


## Where bag `index` of passenger `id` was placed from a hand's grip, as drawn
## now (world; the point of the bag that was at the grip), or Vector3.INF when
## it was not placed from a hand (resting, worn).
func hand_point(id: int, index: int) -> Vector3:
	var bag := _bag_of(id, index)
	if int(bag.get("held_by", -1)) < 0:
		return Vector3.INF
	return (bag["node"] as Node3D).global_transform * (bag["held_at"] as Vector3)


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


## How far the grip bar of roller `index` of passenger `id` is from its hand as
## drawn now, while the hand holds it by the bar (pulled, in hand for a stall
## (_barred), or going between the two), or -1 (not a roller, or not held by
## the bar).
func bar_gap_of(id: int, index: int) -> float:
	var held: Dictionary = _held.get(id, {})
	var bags: Array = held.get("bags", [])
	var body := views.node_for(id)
	if index >= bags.size() or body == null or held["homes"][index] != SecurityLooks.Home.HAND:
		return -1.0
	var bag: Dictionary = bags[index]
	if bag["kind"] != SecurityLooks.Kind.ROLLER:
		return -1.0
	var by_bar: bool = bag.get("by_bar", false)
	if not (bag["carry"] == SecurityLooks.Carry.PULL or by_bar or swapping(id, index)):
		return -1.0
	var node: Node3D = bag["node"]
	var bar := Vector3(0.0, ROLLER_AXLE.y, _bar_z(node, _reach_of(node, bag["kind"])))
	return (node.global_transform * bar).distance_to(grip_of(body, held["hands"][index]))


## Whether roller `index` of passenger `id` is going between the hand and the
## pull by its grip bar now (_swap_transform).
func swapping(id: int, index: int) -> bool:
	var bag := _bag_of(id, index)
	return bag.get("swap", false) and transfer_progress(id, index) < 1.0


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
		held["tuck_weight"] = BoothCarry.tuck_weight(held, now)
		held["bag_weight"] = _bag_weight(held, now)
		_body_ids[body] = id
		# Bags first: a new move is stamped there, and the arms follow it.
		held["left_to_pose"] = Engine.get_process_frames()
		held["draw_seq"] = int(held.get("draw_seq", 0)) + 1
		_place_bags(held, body, tray_xf, now, Placing.NOT_HAND)
		_step_hand_bags(held, body)
		_lead_arms(held, body, now)
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


## Puts the bags of one passenger in place: those going to a hand, and those
## in a hand-led move (CarryLead), which follow the hand, from the pose
## (_on_pose(), _unposed()); all but the settled ones going to a hand in
## draw(), which works out each moving bag's plan (its hand's targets) before
## the arms are posed. Every bag's new move is stamped, whichever are placed.
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
		if not stamp and not _leading(bag, now) and (placing == Placing.HAND) != hand_home:
			continue
		# A bag going to a hand is only stamped here (draw()), so its place
		# (and a roller's follower) is worked out once, when it is placed; one
		# in a hand-led move is placed here too, for its hand's targets.
		var stamp_only: bool = placing == Placing.NOT_HAND and hand_home
		var want_reach := [REACH_BUILT_M]
		var want := node.global_transform
		if not stamp_only or _leading(bag, now):
			want = _bag_transform(held, body, tray_xf, i, homes[i], want_reach)
		# A change of hand moves the bag across like a change of home.
		if stamp:
			_stamp(held, bag, body, want, i)
			if stamp_only and not _leading(bag, now):
				continue
			if stamp_only:
				want = _bag_transform(held, body, tray_xf, i, homes[i], want_reach)
		bag["placed"] = int(bag.get("placed", 0)) + 1
		var k := _progress_of(bag, now)
		# The body this placement goes with, for the next move's start.
		bag["body_at"] = body.global_transform
		bag["settled"] = k >= 1.0
		bag["placed_k"] = k
		bag["carry_placed"] = bag["carry"]
		var to_hand: bool = homes[i] == SecurityLooks.Home.HAND
		var reach: float = want_reach[0]
		if k < 1.0:
			var to_pull: bool = to_hand and bag["carry"] == SecurityLooks.Carry.PULL
			var blend := _reach_blend(
				kind, k, to_pull if kind == SecurityLooks.Kind.ROLLER else to_hand
			)
			# Hand-led: a strap or rods as they were while the bag waits at its
			# start, as they end up once it is at its end.
			if _leading(bag, now):
				blend = CarryLead.carry_t(k, bag)
			reach = lerpf(bag["reach_from"], reach, blend)
		_set_reach(node, kind, reach)
		# A shoulder bag is in place by STRAP_PLACED of its move, so its strap
		# stretches (_reach_blend) from a bag already on the shoulder, not
		# through the strap hand raised at the chest.
		if to_hand and kind == SecurityLooks.Kind.SHOULDER and not _leading(bag, now):
			k = minf(k / STRAP_PLACED, 1.0)
		var holder := -1
		if k >= 1.0:
			node.global_transform = want
			if to_hand and bag["carry"] in [SecurityLooks.Carry.HAND, SecurityLooks.Carry.PULL]:
				holder = held["hands"][i]
		elif bag.get("swap", false):
			var swapped := _swap_transform(held, body, i, k)
			_set_reach(node, kind, swapped[1])
			node.global_transform = swapped[0]
			holder = held["hands"][i]
		else:
			var frame := body.global_transform
			var start_now: Transform3D = bag.get("from_world", frame * (bag["from"] as Transform3D))
			if _leading(bag, now) and CarryLead.start_of(bag)[0] == CarryLead.End.WORN:
				# A worn bag waits on the body as posed now (one sitting down moves it).
				start_now = _carry_transform(held, body, i, [REACH_BUILT_M], bag["carry_from"])
			var hand: int = held["hands"][i]
			var in_stall: bool = held.get("in_stall", false)
			var flags := {
				"in_stall": in_stall,
				"hand_carry": bag["carry"] == SecurityLooks.Carry.HAND,
				"from_floor": int(bag.get("was", -1)) / 4 == SecurityLooks.Home.FLOOR,
				"to_floor": homes[i] == SecurityLooks.Home.FLOOR,
				"hand": SecurityLooks.worn_side(i) if kind == SecurityLooks.Kind.SHOULDER else hand,
				"clear": StallCarry.STALL_CLEAR_M if in_stall else TRANSFER_CLEAR_M,
				"yaw": body.rotation.y,
			}
			if not _leading(bag, now):
				node.global_transform = CarryLead.path(
					start_now, want, k, frame, bag["from"], flags
				)
			else:
				var drawn := {
					"hand": hand,
					"grips": [grip_of(body, 0), grip_of(body, 1)],
					"shoulders_y": [_shoulder_of(body, 0).y, _shoulder_of(body, 1).y],
					"bar_z":
					(
						_bar_z(node, _reach_of(node, kind))
						if kind == SecurityLooks.Kind.ROLLER
						else 0.0
					),
					"scale": held["scale"],
					"strap_top":
					(
						_in_piece(_part(node, "Strap_Top"), node).origin
						if kind == SecurityLooks.Kind.SHOULDER
						else Vector3.ZERO
					),
				}
				var plan := CarryLead.plan(bag, k, start_now, want, frame, flags, drawn)
				bag["lead"] = plan
				holder = plan["holder"]
				var placed: Transform3D = plan["xf"]
				if holder >= 0:
					var at: Vector3 = placed.basis * (plan["anchor"] as Vector3)
					placed = Transform3D(placed.basis, grip_of(body, holder) - at)
				node.global_transform = placed
		bag["held_by"] = holder
		if holder >= 0:
			bag["held_at"] = node.global_transform.affine_inverse() * grip_of(body, holder)


## A new move of `bag` (bag `i`) to `want`: it starts where the bag is, held in
## the passenger's frame (so a bag picked up while walking stays ahead of the
## legs), or fixed in the world when it starts on the floor or in a tray (the
## hand reaches it there, CarryLead). Its clock is the tick sync() saw the
## change on, not the frame it is drawn in; a new bag's move is over at once,
## so its start is never drawn.
func _stamp(held: Dictionary, bag: Dictionary, body: Node3D, want: Transform3D, i: int) -> void:
	var node: Node3D = bag["node"]
	var kind: SecurityLooks.Kind = bag["kind"]
	var start := want if bag["home"] == -1 else node.global_transform
	bag["from"] = _start_frame(bag, body).affine_inverse() * start
	# A hand-led move whose hand was still reaching for the bag has not left
	# its start: the new move starts there, as that one did (its "was",
	# "carry_from" and "from_holder" kept), not in the hand it was going to,
	# and on that move's clock, so the reach is not started again (a bag
	# stamped again every few ticks would wait at its start for ever).
	var unmoved := CarryLead.at_start(bag, bag.get("placed_k", 1.0))
	if not unmoved:
		# The carry it was drawn with last, not one sync() saw in between (a
		# frame can run several ticks).
		bag["carry_from"] = bag.get(
			"carry_placed", bag.get("carry_was", SecurityLooks.KIND_CARRY[kind])
		)
		# Where the hand held it at the start, in its own frame, and the hand
		# still holding it when its last move had not ended (CarryLead.start_of).
		bag["anchor_from"] = bag.get("held_at", grip_anchor(kind))
		bag["from_holder"] = -1 if bag.get("settled", true) else int(bag.get("held_by", -1))
		bag["was"] = bag["home"]
	var at: int = bag["was"]
	bag.erase("from_world")
	bag.erase("lead")
	var homes: Array = held["homes"]
	if held.get("in_stall", false) and homes[i] == SecurityLooks.Home.FLOOR:
		# Set down in a toilet stall, a bag starts fixed in the stall: the body
		# shuffles back to the seat as it sits and would drag a start held in
		# its frame through its knees. One from the hand starts upright over its
		# place by the door (StallCarry.set_down_start).
		bag["from_world"] = body.global_transform * bag["from"]
		if bag["carry"] == SecurityLooks.Carry.HAND:
			var box := bag_box(kind)
			bag["from_world"] = StallCarry.set_down_start(want, box, StallCarry.lowest(start, box))
	elif at >= 0 and at / 4 == SecurityLooks.Home.TRAY:
		# A bag in a tray waits there for the hand; one on the floor keeps its
		# place by the walker, so a walker never steps into it.
		bag["from_world"] = start
	if not unmoved:
		bag["since"] = bag["changed"] - (TRANSFER_TICKS if bag["home"] == -1 else 0.0)
	# Hand-led or not is decided now and kept to the end of the move (and so is
	# its reach and length, CarryLead.stamp_move).
	bag["led"] = _leads(held, bag)
	CarryLead.stamp_move(bag, held.get("in_stall", false), homes[i], body.global_transform)
	bag["home"] = bag["place"]
	bag["reach_from"] = _reach_of(node, kind)


## Whether a move of `bag` stamped now is hand-led (CarryLead): every move but
## a roller's between the hand and the pull by its bar (_swap_transform, held
## by the bar throughout), in a toilet stall too (board item c7b0e7be). Kept in
## the bag's "led" to the move's end, so a move never changes mode.
static func _leads(_held: Dictionary, bag: Dictionary) -> bool:
	return not bag.get("swap", false)


## Whether `bag` is in a hand-led move now (_leads(), as stamped): moving.
static func _leading(bag: Dictionary, now: float) -> bool:
	return bag.has("since") and _progress_of(bag, now) < 1.0 and bag.get("led", false)


## Aims each hand of `body` at its target for the hand-led moves of its bags
## (CarryArm.reach_weight) and bends it down as far as a low one needs
## (CarryStoop). A hand in no move reaches for nothing.
func _lead_arms(held: Dictionary, body: Node3D, now: float) -> void:
	var weights := [0.0, 0.0]
	var targets := [Vector3.ZERO, Vector3.ZERO]
	var keeps := [0.0, 0.0]
	var drops := [CarryStoop.HIPS_ALL, CarryStoop.HIPS_ALL]
	for bag: Dictionary in held["bags"]:
		if not _leading(bag, now) or not bag.has("lead"):
			continue
		var plan: Dictionary = bag["lead"]
		for hand in 2:
			if plan["weights"][hand] > weights[hand]:
				weights[hand] = plan["weights"][hand]
				targets[hand] = plan["targets"][hand]
				keeps[hand] = plan["keeps"][hand]
				drops[hand] = plan["drops"][hand]
	held["reach_on"] = [weights[0] > 0.0, weights[1] > 0.0]
	var rig := _rig(body)
	var stoop: CarryStoop = rig["stoop"]
	for list: Array in [stoop.targets, stoop.sides, stoop.weights, stoop.keeps, stoop.drops]:
		list.clear()
	for hand in 2:
		var arm := rig["arms"][hand] as CarryArm
		arm.reach_weight = weights[hand]
		arm.reach_target = targets[hand]
		if weights[hand] > 0.0:
			stoop.targets.append(targets[hand])
			stoop.sides.append(hand)
			stoop.weights.append(weights[hand])
			stoop.keeps.append(keeps[hand])
			stoop.drops.append(drops[hand])


## The body frame a new move of `bag` starts in: the body as it was when the
## bag was last placed, for a bag settled on the body (in the hand, on the
## back or the shoulder), so a body that turned since (as one sitting down
## in a toilet stall turns round on the spot) takes the bag round with it as
## the hand does; the body now for anything else (a bag on the floor or in a
## tray, a pulled roller on its wheels, one already moving).
func _start_frame(bag: Dictionary, body: Node3D) -> Transform3D:
	var held_by_body: bool = (
		int(bag["home"]) >= 0
		and int(bag["home"]) / 4 == SecurityLooks.Home.HAND
		and bag.get("settled", false)
		and bag.get("carry_placed", SecurityLooks.Carry.PULL) != SecurityLooks.Carry.PULL
		and bag.has("body_at")
	)
	return bag["body_at"] if held_by_body else body.global_transform


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
		return clampf((k - STRAP_PLACED) / (1.0 - STRAP_PLACED), 0.0, 1.0)
	return clampf(k / 0.4, 0.0, 1.0)


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
		# Not pulled now: the next pull starts its follower afresh behind the
		# walker, not from wherever it was last drawn (perhaps metres back).
		for key in ["axle", "walked", "drawn_axle", "drawn_at", "axle_now"]:
			bag.erase(key)
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
	# Hard cases the free hand comes to the front beside (a roller held by its
	# bar lies across the front to the free side, so that hand stays down).
	var beside := 0
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
					beside += 0 if bag.get("by_bar", false) else 1
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
	var tuck: float = held.get("tuck_weight", 0.0)
	var reach_on: Array = held.get("reach_on", [false, false])
	var key := [modes, strap, cases, beside, held["weight"], tuck, reach_on]
	if held.get("arm_key", []) == key and held.get("arm_body") == body:
		return
	held["arm_key"] = key
	held["arm_body"] = body
	var arms: Array = _rig(body)["arms"]
	for side in arms.size():
		var arm := arms[side] as CarryArm
		arm.holds = modes[side] == Arm.HAND or modes[side] == Arm.PULL
		arm.active = modes[side] != Arm.FREE or cases > 0 or tuck > 0.0 or reach_on[side]
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
				# Turning between the side and the front, the upper arm reaches
				# further forward (most at half way, none at either end), so the
				# turning bag passes ahead of the thighs.
				var w: float = held["weight"]
				arm.front_upper_degrees = 20.0 + TURN_REACH_DEGREES * 4.0 * w * (1.0 - w)
			_:
				# Beside a front-carried case, or tucked in through a booth.
				arm.front_half_width = BoothCarry.free_hand_width(beside > 0, tuck)
				arm.front_weight = maxf(held["weight"] if beside > 0 else 0.0, tuck)


## How far `bag` is through its move at sim time `now` (1 when settled or
## not started).
static func _progress_of(bag: Dictionary, now: float) -> float:
	if not bag.has("since"):
		return 1.0
	return clampf((now - bag["since"]) / CarryLead.ticks_of(bag), 0.0, 1.0)


## Turns off both CarryArms of a character with no bags (or released), with
## no reach, and its CarryStoop with no target.
func _arms_off(body: Node3D) -> void:
	if not body.has_meta(&"carry_rig"):
		return
	var rig := _rig(body)
	for arm: CarryArm in rig["arms"]:
		arm.active = false
		arm.front_weight = 0.0
		arm.reach_weight = 0.0
	var stoop: CarryStoop = rig["stoop"]
	for list: Array in [stoop.targets, stoop.sides, stoop.weights, stoop.keeps, stoop.drops]:
		list.clear()


## A character's grip, shoulder and spine attachments and CarryArm modifiers,
## made the first time and kept on the pooled character.
func _rig(body: Node3D) -> Dictionary:
	if body.has_meta(&"carry_rig"):
		return body.get_meta(&"carry_rig")
	var skeleton := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var rig := {"grips": [], "arms": [], "shoulders": [], "spine": _attach(skeleton, SPINE_BONE)}
	# The stoop's pivot as drawn (CarryWorn.stoop_shift).
	rig["pivot"] = _attach(skeleton, "Spine_01")
	# Before the arms: the stoop bends the back and the arms reach from there.
	rig["stoop"] = CarryStoop.new()
	skeleton.add_child(rig["stoop"])
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
	return CarryTray.placed(sim.grid, held["lane"], held["tray_at"], body.global_position)


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
			if not (held.get("stall", {}) as Dictionary).is_empty():
				return StallCarry.floor_place(held["stall"], bag_box(kind), scale_by, i, count)
			var spot: Transform3D = held["floor"][i]
			var placed := Transform3D(yaw, body.global_position) * spot
			placed.origin.y = sim.grid.origin.y
			return Transform3D(placed.basis.scaled(Vector3.ONE * scale_by), placed.origin)
	return _carry_transform(held, body, i, reach)


## A carried bag's transform, its kind's way (the header), or `carry`'s way.
func _carry_transform(
	held: Dictionary, body: Node3D, i: int, reach: Array, carry := -1
) -> Transform3D:
	var scale_by: float = held["scale"]
	var node: Node3D = held["bags"][i]["node"]
	match held["bags"][i]["carry"] if carry < 0 else carry:
		SecurityLooks.Carry.BACK:
			return worn_back(_spine_of(body), body.rotation.y, scale_by)
		SecurityLooks.Carry.SHOULDER:
			var side := SecurityLooks.worn_side(i)
			var joint := _shoulder_of(body, side)
			var hung := CarryWorn.shoulder(
				joint,
				body.global_position,
				body.rotation.y,
				side,
				scale_by,
				_reach_base(_part(node, "Strap_Reach")),
				CarryWorn.stoop_shift(
					_rig(body)["stoop"], _rig(body)["pivot"].global_position, joint
				)
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
	if held["bags"][i].get("by_bar", false):
		return _barred(held, body, i, grip, weight)
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


## A roller going between hanging from the hand by its grip bar (rods in,
## _case_transform) and the pull, at `k` of the move, held by the bar
## throughout: its axle goes between under the hand and the pull's (the
## follower's, as stepped this draw; lifted, where it was let go, held in the
## body's frame), swung out SWAP_OUT_M midway (at security round the hand's
## side), the rods running out or in to keep the bar in the hand. Returns
## [transform, rod length].
func _swap_transform(held: Dictionary, body: Node3D, i: int, k: float) -> Array:
	var bag: Dictionary = held["bags"][i]
	var scale_by: float = held["scale"]
	var hand: int = held["hands"][i]
	var grip := grip_of(body, hand)
	var outward := _outward(body, hand)
	var to_pull: bool = bag["carry"] == SecurityLooks.Carry.PULL
	var trailing: Vector3
	if to_pull:
		trailing = bag.get("axle_now", Vector3.INF)
		if not trailing.is_finite():
			trailing = _axle_drawn(bag, body, scale_by, hand)
	else:
		trailing = body.global_transform * ((bag["from"] as Transform3D) * ROLLER_AXLE)
	# How far toward the pull: 0 hung, 1 pulled.
	var s := smoothstep(0.0, 1.0, k)
	var t := s if to_pull else 1.0 - s
	var hung := _hung_axle(bag, grip, scale_by)
	var axle := hung.lerp(trailing, t) + outward * SWAP_OUT_M * 4.0 * t * (1.0 - t)
	# At security (no stall partition near) round the hand's side, clear of the
	# legs (CarryLead.swap_axle); the bar stays in the hand.
	if held.get("security", false):
		var frame := Transform3D(Basis(Vector3.UP, body.rotation.y), body.global_position)
		axle = CarryLead.swap_axle(frame, hung, trailing, t, hand, SWING_RADIUS_M)
	var ref := outward.lerp(Vector3.UP, t).normalized()
	var rods := _reach_base(_part(bag["node"], "Pull_Reach"))
	var xf := pulled(grip, axle, scale_by, ref).translated(outward * BAR_PALM_M * (1.0 - t))
	return [xf, _pull_length(grip, axle, scale_by, rods.z)]


## A roller taken in hand for a stall, held by its grip bar with its rods in,
## turned `weight` of the way to the front carry: at the side it hangs straight
## down from the bar, its back panel (rods) to the leg and its front out to
## the hand's side; turning to the front it rolls about the body's forward
## axis, its far end coming up across the body, FRONT_ROLL of the way (two
## bags: 45 degrees, so it stays clear of the other bag), its front face down.
## The bar stays in the hand throughout; the roll carries the bag's end through
## the space in front of the hips, away from the arm above the hand.
func _barred(held: Dictionary, body: Node3D, i: int, grip: Vector3, weight: float) -> Transform3D:
	var bag: Dictionary = held["bags"][i]
	var scale_by: float = held["scale"]
	var outward := _outward(body, held["hands"][i])
	var roll := weight * (FRONT_ROLL if (held["bags"] as Array).size() < 2 else PI / 4.0)
	var length := (_bar_z(bag["node"], REACH_BUILT_M) - ROLLER_AXLE.z) * scale_by
	var axle := grip - (Vector3.UP * cos(roll) + outward * sin(roll)) * length
	var ref := outward * cos(roll) + Vector3.DOWN * sin(roll)
	return pulled(grip, axle, scale_by, ref).translated(ref * BAR_PALM_M)


## Where the axle of a roller hung from the hand by its grip bar at `grip`,
## rods in, is: straight under the bar.
func _hung_axle(bag: Dictionary, grip: Vector3, scale_by: float) -> Vector3:
	return grip - Vector3.UP * (_bar_z(bag["node"], REACH_BUILT_M) - ROLLER_AXLE.z) * scale_by


## The grip bar's middle along a roller's length (its own z, scale 1) with
## rods `length` out (_pull_length() the other way round).
func _bar_z(node: Node3D, length: float) -> float:
	return length + _reach_base(_part(node, "Pull_Reach")).z + ROLLER_GRIP_PAST_TOP_M


## Out to the side of hand `hand` (0 right, 1 left) of `body`, level.
static func _outward(body: Node3D, hand: int) -> Vector3:
	return Basis(Vector3.UP, body.rotation.y) * (Vector3.LEFT if hand == 0 else Vector3.RIGHT)


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
