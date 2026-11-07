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
## - BACK, the backpack: worn, its back panel CarryWorn.BACK_FROM_SPINE_M behind the
##   Spine_03 bone and leaning with it; the arms are left to the animation.
## - SHOULDER, the tote: hung on the shoulder of SecurityLooks.worn_side(), its
##   strap stretched (Strap_Reach, Strap_Top) from the bag's top edge to a bar
##   STRAP_OVER_ARM_M over the Arm bone, the bag outside the hip; that arm holds
##   the strap at the chest (CarryArm's front pose with a raised forearm).
## - PULL, the roller: pulled by its grip bar in the hand, its wheels on the
##   floor at an axle RollerPull.TRAIL_M back along the line the body walked (RollerPull.trail()),
##   moved once per tick in sync() and drawn with the clock's alpha, so it
##   takes each corner where the body did instead of swinging with the body's
##   instant turn; the rods (Pull_Reach) stretch to the hand.
## A roller is lifted and carried in the hand while its walker is at security
## (narrow lane cells and tables) or runs (a long stride kicks back into a
## trailing case), hung by its grip bar, rods in, and it goes between that and
## the pull by the bar (CarryHand.swap_transform: the rods run out or in from the hand
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

## Which bags CarryPlace.place_bags() places.
enum Placing { HAND, NOT_HAND }

## The grip sits this far past the knuckles along the hand's own axis.
const GRIP_ALONG_M := 0.03
## In front, a bag's handle sits this far under the knuckles, in the palm.
const FRONT_PALM_M := 0.04
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
## Shoulder bag: the strap this far out from the body's centre line, its bar
## this far over the Arm bone (the shoulder joint), and this long from the bar
## to the bag's top edge (the bag hangs outside the hip, its top about the hip
## bone's height, under the elbow).
const STRAP_OUT_M := 0.32
const STRAP_OVER_ARM_M := 0.06
const STRAP_M := 0.45
## The roller's axle in its own frame at scale 1 (build_carry_on_kit.py: on
## the rod line, at the wheels), and how far the grip bar's middle is past
## Pull_Top's origin.
const ROLLER_AXLE := Vector3(0.0, 0.03, -0.19)
const ROLLER_GRIP_PAST_TOP_M := 0.015
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


## The point of a hand-carried bag (in its own frame, scale 1) held at the grip
## in the side carry: a hard case's top edge on its handle face, read from its
## mesh (CaseGrip.edge()), a lifted roller's carry handle, a backpack's loop.
static func grip_anchor(kind: SecurityLooks.Kind) -> Vector3:
	if kind == SecurityLooks.Kind.ROLLER:
		return ROLLER_HANDLE
	if kind == SecurityLooks.Kind.BACKPACK:
		return BACKPACK_LOOP
	return CaseGrip.anchor(kind)


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
			CarryArmPose.arms_off(self, node)
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
		held["sit_face"] = RollerPark.sit_face(sim, p)
		# At its booth seat (BoothRoller.fix_start()), not queuing for it.
		held["booth"] = sim.cafes.booth_roller(p) and not is_nan(held["sit_face"])
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
			held["front_from"] = CarryHand.front_weight(held, _tick())
			held["bag_from"] = CarryHand.bag_weight(held, _tick())
			held["front_since"] = _tick()
			held["front"] = front
		# A record made again after a load (PassengerViews.snap() releases every
		# record, then syncs on the same tick) starts in the tuck it needs.
		BoothCarry.update_tuck(held, tuck_in, _released_at.get(id, -1.0) == _tick(), _tick())
		# A roller held by its bar for a stall stays so (StallCarry.keeps_bar()).
		var was: Array = held["bags"]
		PullSide.resolve(was, sim, views, p, kinds, homes, lifts, hands, _tick())
		var near_row := StallCarry.beside_row(sim, p)
		# Standing still in a queue, not turned to a front carry (RollerPark.queue_stand()).
		var queue_still := (
			RollerPark.queue_still(sim, p)
			and not front
			and views.tick_position(id, true).distance_to(views.tick_position(id, false)) < 0.001
		)
		# A roller lifted at a booth stays in hand until the turn back has ended.
		var kept := BoothCarry.kept_lifted(
			held,
			kinds,
			lifts,
			CarryHand.front_weight(held, _tick()),
			BoothCarry.tuck_weight(held, _tick()),
			booth_bags
		)
		for i in kinds.size():
			lifts[i] = lifts[i] or kept[i]
		for i in mini(was.size(), kinds.size()):
			if StallCarry.keeps_bar(
				was[i], kinds[i], CarryHand.front_weight(held, _tick()), near_row
			):
				lifts[i] = true
			# A roller going between the hand and the pull by its bar keeps its
			# hand until it is there, and one held by its bar keeps its hand while
			# it is, so the pull starts in that hand (a change of hand would be a
			# move of its own, off the bar).
			if (
				was[i]["kind"] == kinds[i]
				and (
					(was[i].get("by_bar", false) and (lift_stall or near_row))
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
			# A roller pulled by a walker standing still in a queue is stood up beside it.
			var stands := queue_still and homes[i] == SecurityLooks.Home.HAND and not lifts[i]
			var turn := RollerPark.tip_wait(node.rotation.y, views.walk_heading(p))
			RollerPark.queue_stand(
				was[i], kinds[i], stands, _tick(), RollerPark.still_wait(p), turn
			)
			# Its side, from the sim (ParkSide.choose_stand()), before hold_park() holds it.
			ParkSide.choose_stand(sim, p, was[i])
			# A parking roller keeps home, hand and lift to the park's end; one lying, its lift.
			RollerPark.hold_park(was[i], kinds[i], homes, hands, i, _tick(), p.collect_tick != 0)
			if RollerPark.holds_lift(was[i], kinds[i], homes[i], _tick()):
				lifts[i] = int(was[i].get("place", 0)) % 2 == 1
		held["scale"] = SecurityLooks.bag_scale(p)
		var spots: Array[Transform3D] = []
		var frames: Array = []
		for i in homes.size():
			spots.append(RollerPark.floor_spot(sim, p, kinds[i], hands[i], i, homes.size()))
			frames.append(RollerPark.chair_front(sim, p, kinds[i]))
		held["floor"] = spots
		held["floor_at"] = frames
		ActivityCarry.sync(held, sim, p, homes.size())
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
		PassengerLooks.paint_bags(bags, p.id)
		# A change of home or hand is stamped with this tick; draw() starts the
		# move from where the bag was drawn last.
		for i in bags.size():
			var lifted := lifts[i]
			var carry: SecurityLooks.Carry = (
				SecurityLooks.Carry.HAND if lifted else SecurityLooks.KIND_CARRY[kinds[i]]
			)
			var place: int = (homes[i] * 2 + hands[i]) * 2 + int(lifted)
			# A lifted roller hangs by its grip bar (CarryHand.case_transform) and goes
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
				bags[i]["changed"] = CarrySwap.start(bags[i], lifted, node, _tick())
				bags[i]["carry_was"] = bags[i].get("carry", carry)
			bags[i]["carry"] = carry
			bags[i]["by_bar"] = by_bar
			RollerPull.step(self, bags[i], node, id, homes[i], hands[i])
		StallCarry.stamp_bar_turn(held, near_row, _tick())
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
			CarryArmPose.arms_off(self, body)
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
	return CarryPlace.progress_of(bags[index], _now())


## How far passenger `id` has turned to the front carry: 0 side, 1 front.
## The turn runs for every passenger in a narrow cell; only a hard case (and
## the free arm beside it) follows it.
func front_weight_of(id: int) -> float:
	return CarryHand.front_weight(_held.get(id, {}), _now())


## How far passenger `id` has tucked its free arms in for a booth or an arch:
## 0 swinging, 1 tucked (BoothCarry.tuck_weight).
func tuck_of(id: int) -> float:
	return BoothCarry.tuck_weight(_held.get(id, {}), _now())


## How far the hard case (or lifted roller) of passenger `id` has turned to
## the front carry: 0 side, 1 front (CarryHand.bag_weight).
func bag_turn_of(id: int) -> float:
	return CarryHand.bag_weight(_held.get(id, {}), _now())


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
## roller) has taken (RollerPull.drawn): one per draw while it is pulled.
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
	var ahead := CarryHand.carried_in_front(Vector3.ZERO, 0.0, held["scale"], bag["kind"])
	var held_ahead := ahead.affine_inverse() * Vector3.ZERO
	var at := grip_anchor(bag["kind"]).lerp(held_ahead, held.get("bag_weight", 0.0))
	return (bag["node"] as Node3D).global_transform * at


## How far the grip bar of roller `index` of passenger `id` is from its hand as
## drawn now, while the hand holds it by the bar (pulled, in hand for a stall
## (CarryHand.barred), or going between the two), or -1 (not a roller, or not held by
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
	var bar := Vector3(
		0.0, ROLLER_AXLE.y, CarryHand.bar_z(self, node, _reach_of(node, bag["kind"]))
	)
	return (node.global_transform * bar).distance_to(grip_of(body, held["hands"][index]))


## Whether roller `index` of passenger `id` is going between the hand and the
## pull by its grip bar now (CarryHand.swap_transform).
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
			CarryPlace.place_bags(
				self, held, body, CarryPlace.tray_transform(self, held, body), now, Placing.HAND
			)


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
		var tray_xf := CarryPlace.tray_transform(self, held, body)
		if held["tray"] != null:
			(held["tray"] as Node3D).global_transform = tray_xf
		held["weight"] = CarryHand.front_weight(held, now)
		held["tuck_weight"] = BoothCarry.tuck_weight(held, now)
		held["bag_weight"] = CarryHand.bag_weight(held, now)
		_body_ids[body] = id
		# Bags first: a new move is stamped there, and the arms follow it.
		held["left_to_pose"] = Engine.get_process_frames()
		held["draw_seq"] = int(held.get("draw_seq", 0)) + 1
		CarryPlace.place_bags(self, held, body, tray_xf, now, Placing.NOT_HAND)
		_step_hand_bags(held, body)
		CarryArmPose.lead_arms(self, held, body, now)
		CarryArmPose.pose_arms(self, held, body, now)


## The once-per-draw part of the bags going to a hand (their moves are stamped
## and the turn weights set in draw() already): each counts the draw, and a
## pulled roller's axle takes its one follower step here (RollerPull.drawn), so
## placing the bag again on a later report of the same frame never moves it on.
## Placing (CarryPlace.place_bags, Placing.HAND) is then a function of the pose alone.
func _step_hand_bags(held: Dictionary, body: Node3D) -> void:
	var bags: Array = held["bags"]
	for i in bags.size():
		if held["homes"][i] != SecurityLooks.Home.HAND:
			continue
		var bag: Dictionary = bags[i]
		bag["steps"] = int(bag.get("steps", 0)) + 1
		if bag["carry"] == SecurityLooks.Carry.PULL:
			bag["axle_now"] = RollerPull.drawn(self, bag, body, held["scale"], held["hands"][i])


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
	CarryPlace.place_bags(
		self, held, body, CarryPlace.tray_transform(self, held, body), _now(), Placing.HAND
	)


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
