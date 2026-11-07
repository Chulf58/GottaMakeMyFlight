class_name ParkSide
extends RefCounted
## The hand a one-roller guest holds its roller in at a seat where it parks
## the roller beside it: the open side when a wall stands on its hand's side
## (user ruling a-guest-pulling-a-roller-through-a-doorway-tucks-it-in-line:
## "A parked or stood roller beside a wall goes on the open side, following
## the hand-swap ruling b05a0fab and the booth precedent (BoothRoller.side)";
## boards a40fdbaf, cfe95aad). SecurityLooks.hand_of() asks it, so the hand,
## the park (RollerPark.park(), on the hand's side), the floor spot and the
## pick-up all take one side. Every seat where RollerPark stamps a faced park
## counts: a gate chair, a cafe table seat, a booth seat, a sofa or nap pod
## seat. It answers from NEAR_CELLS out on the way in, so PullSide has the
## roller in that hand (hand_of() is its "first") before the set-down starts:
## a set-down from the other hand parks on the walled side and lays the roller
## across in front of the feet.
##
## The hand is chosen once per seat and kept (stamp()) until the guest is no
## longer bound for or at that seat: chosen from the walls live on every call,
## a wall built mid-stay, or a route in and out of NEAR_CELLS, changed the hand
## with the roller lying on the floor. The stamp lives on the sim object as
## metadata, never saved: after a load the first call chooses again from the
## walls as they are, the same choice unless a wall changed meanwhile.
##
## A side is walled when the park on it (RollerPark.park(), scale 1) reaches
## into a wall (ParkWalls.inside(), PullSide.walls_near()) where the guest
## stands to park it: at a gate chair its front cell; at a cafe table seat or
## a sofa or nap pod seat the approach (slot) cell and the seat root; at a
## booth seat a wall on that edge of the approach cell (BoothRoller.walled()),
## as BoothRoller.side() lays the roller. Walled on both sides or neither, the
## hand is hand_of()'s own (`fallback`) as it chooses, kept like any other,
## and ParkWalls moves the park and the lying roller out of any wall.

## A guest this many cells or fewer from where it parks chooses its hand.
const NEAR_CELLS := 3
## The sim metadata holding the stamps: passenger id -> [seat key, hand]. A
## loaded snapshot clears it (PassengerSimSave.from_snapshot()).
const STAMPS := &"park_side_hands"
const GATE_STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.TO_GATE,
	Passenger.Stage.SITTING_DOWN,
	Passenger.Stage.SEATED,
	Passenger.Stage.STANDING_UP,
]
const CAFE_STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.CAFE_TO_SEAT,
	Passenger.Stage.CAFE_SITTING_DOWN,
	Passenger.Stage.CAFE_SEATED,
	Passenger.Stage.CAFE_STANDING_UP,
]
const SHOP_STAGES: Array[Passenger.Stage] = [Passenger.Stage.SHOP_WALK, Passenger.Stage.SHOP_BROWSE]
## stand_hand() tries the way out to a queue stand at this many shares of its
## side distance: the step (0.14 m or less) is under the roller's width (0.33 m).
const STAND_SAMPLES := 3
## A gate stander's step from its cell's middle onto its spot shorter than this
## (m) is no step (stand_face()): spots sit 0, 0.2 or 0.4 m off the middle.
const SPOT_STEP_M := 0.05
## The way a gate stander faces with no step onto its spot and none walked to
## its cell (stand_face()): south, yaw 0, as a body drawn new faces.
const GATE_FACE := Vector2(0.0, 1.0)


## The hand (0 right, 1 left) one-bag guest `p` holds its roller in: the open
## side's at a seat with a wall on one side only, as stamped for the seat,
## else `fallback`.
static func hand(sim: PassengerSim, p: Passenger, fallback: int) -> int:
	var stamps: Dictionary = sim.get_meta(STAMPS, {})
	var seat := _seat(sim, p) if SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER else {}
	if seat.is_empty():
		if stamps.has(p.id):
			stamps.erase(p.id)
		return fallback
	var stamp: Array = stamps.get(p.id, [])
	if stamp.is_empty() or stamp[0] != seat["key"]:
		if not _near(p, seat["cell"]):
			return fallback
		# Walled on both sides or neither: hand_of()'s own hand now, kept as
		# well, so it cannot change mid-stay either.
		var chosen := _open(sim, seat)
		stamp = [seat["key"], chosen if chosen >= 0 else fallback]
		stamps[p.id] = stamp
		sim.set_meta(STAMPS, stamps)
	return stamp[1]


## The open side's hand at `seat` (_seat()): 0 or 1 when one side only is
## walled, -1 when both or neither.
static func _open(sim: PassengerSim, seat: Dictionary) -> int:
	var walled := [false, false]
	if seat.has("booth"):
		var front: Transform3D = seat["booth"]
		walled = [BoothRoller.walled(sim, front, -1.0), BoothRoller.walled(sim, front, 1.0)]
	else:
		for at: Transform3D in seat["spots"]:
			var walls := PullSide.walls_near(sim.grid, at.origin)
			for h in 2:
				if ParkWalls.inside(RollerPark.park(at, h, 1.0), walls):
					walled[h] = true
	if walled[0] == walled[1]:
		return -1
	return 1 if walled[0] else 0


## The seat `p` is bound for or at with its roller: {"key": the seat's
## identity, "cell": where it parks, and "spots": the frames it parks from
## (facing out of the seat), or "booth": the approach frame}; empty when none.
static func _seat(sim: PassengerSim, p: Passenger) -> Dictionary:
	if p.stage in GATE_STAGES and p.seat_cell != Passenger.NO_CELL:
		if p.seat_front == Passenger.NO_CELL:
			return {}
		var front := _frame(sim, p.seat_front, p.seat_front - p.seat_cell)
		return {"key": "gate %s" % p.seat_cell, "cell": p.seat_front, "spots": [front]}
	if p.stage in CAFE_STAGES:
		var visit := sim.cafes.visit_of(p.id)
		if visit == null or visit.seat.is_empty():
			return {}
		var cell: Vector2i = visit.seat["approach"]
		var approach := _frame(sim, cell, visit.seat["facing"])
		var key := "cafe %s %s" % [visit.seat["cell"], cell]
		if sim.cafes.booth_roller(p):
			return {"key": key, "cell": cell, "booth": approach}
		var root := BuildObjectDef.seat_root_world(sim.grid, visit.seat)
		return {"key": key, "cell": cell, "spots": [approach, Transform3D(approach.basis, root)]}
	if p.stage not in SHOP_STAGES:
		return {}
	var shop := sim.shops.visit_of(p.id)
	if shop == null or shop.slot.is_empty():
		return {}
	var record := shop.piece if not shop.piece.is_empty() else sim.grid.get_object(shop.display)
	var kind: int = ActivityPoses.KINDS.get(record.get("def", &""), ActivityPoses.Kind.NONE)
	if kind != ActivityPoses.Kind.SEAT and kind != ActivityPoses.Kind.RECLINE:
		return {}
	var slot: Vector2i = shop.slot["approach"]
	var out := TerminalLayout.front_of(record["facing"])
	var at := _frame(sim, slot, out)
	var root := ActivityPoses.spot_of(sim.grid, record, shop.index)
	return {
		"key": "shop %d %d" % [shop.display, shop.index],
		"cell": slot,
		"spots": [at, Transform3D(at.basis, root)],
	}


## Whether `p` is NEAR_CELLS or fewer from `cell` (either way on the grid).
static func _near(p: Passenger, cell: Vector2i) -> bool:
	var d := (p.at - cell).abs()
	return maxi(d.x, d.y) <= NEAR_CELLS


## The frame (world, on the floor) at `cell` facing grid way `out`.
static func _frame(sim: PassengerSim, cell: Vector2i, out: Vector2i) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, atan2(out.x, out.y)), sim.grid.cell_to_world(cell))


## The hand (0 right, 1 left) a roller pulled in `hand` is stood up with in a
## queue (RollerPark.queue_stand(); decision a-roller-stood-in-a-queue-beside-
## a-wall-goes-on-the-passenge): the other hand when the way out to the stand
## on `hand`'s side (RollerPark.queue_park() in `frame`, at `scale_by`, body
## look `look`) meets one of `boxes` (walls and furniture, PullSide's boxes)
## and the way to the other side's does not; else `hand`. The way is the stand
## at STAND_SAMPLES shares of its side distance, each step less than the
## roller's width, so a wall the stand would stand wholly past (a body 0.1 m
## from a wall's face, the stand's near edge 0.27 m out) counts as well as one
## it stands in. Walled on both sides or neither, the usual side stands, and
## RollerPark.plan() moves the stand out of the walls it stands in (ParkWalls).
static func stand_hand(
	frame: Transform3D, hand: int, scale_by: float, look: int, boxes: Array
) -> int:
	var walled := [false, false]
	var side := RollerPark.queue_side(look)
	for h in 2:
		for n in range(1, STAND_SAMPLES + 1):
			var out := side * n / float(STAND_SAMPLES)
			var at := RollerPark.park(frame, h, scale_by, RollerPark.PARK_AHEAD_M, out)
			walled[h] = walled[h] or ParkWalls.inside(at, boxes)
	return 1 - hand if walled[hand] and not walled[1 - hand] else hand


## Chooses the side of the queue stand asked for on roller `bag` of guest `p`
## (RollerPark.restamps()) on the sim tick it is asked, in CarryOnProps.sync(),
## and the frame it is drawn in: the frame (stand_frame()) of where `sim` has
## `p` stand (stand_at()) facing its way there (stand_face()), kept on `bag`
## ("queue_frame", [its "still_from", the frame]) for RollerPark.plan() to
## place the stand in, and RollerPark.side_first() with the open side's hand
## (stand_hand()) of the walls and furniture round it in that frame. Only sim
## state decides both, never the drawn body, so one state stands one side
## whatever way the view draws the body, and a body turning in the stand does
## not take the roller round or across with it (anti-pattern view-state-
## stepped-on-from-the-previous-draw-makes-a-carry-p; a body drawn the other
## way stood the roller chosen for its left in the wall on its right). Chosen
## once a still spell: asked again once its change of hand is made, the side
## and the frame are kept. A two-bag guest keeps a bag in each hand
## (SecurityLooks.hand_of(), PullSide), so its stand keeps its side, in the
## frame kept as well, and RollerPark.plan() moves it out of the walls
## (ParkWalls). With no way to face known the stand is drawn in the body's
## frame as before (no "queue_frame").
static func choose_stand(sim: PassengerSim, p: Passenger, bag: Dictionary) -> void:
	if not RollerPark.restamps(bag):
		return
	var spell := float(bag.get("still_from", NAN))
	var kept: Array = bag.get("queue_frame", [])
	if not kept.is_empty() and float(kept[0]) == spell:
		return
	var face := stand_face(sim, p)
	if face == Vector2.ZERO:
		bag.erase("queue_frame")
		return
	var frame := stand_frame(stand_at(sim, p), face)
	bag["queue_frame"] = [spell, frame]
	if p.carry_on > 1:
		return
	var boxes := PullSide.walls_near(sim.grid, frame.origin)
	boxes.append_array(PullSide.pieces_near(sim.grid, frame.origin))
	var look := PassengerLooks.body_of(p.id, p.variant)
	var hand := CarryLead.hand_of(bag["place"])
	hand = stand_hand(frame, hand, SecurityLooks.bag_scale(p), look, boxes)
	RollerPark.side_first(bag, hand)


## Where (world) `sim` has `p` stand while it waits still in a queue: its sim
## position and the offset it is drawn at by a held security queue front
## (SecurityLooks.target_offset(), which the drawn body walks to), the point
## PassengerViews draws a queuer at once it has stood still.
static func stand_at(sim: PassengerSim, p: Passenger) -> Vector3:
	return sim.world_position(p) + SecurityLooks.target_offset(sim, p)


## The ground way (x, z) `p` of `sim` waits facing in a queue, from sim state
## only (choose_stand()): what its body turns to there (PassengerViews), its
## security lane's front or its cafe counter; at the gate (on its standing
## spot, standing or setting off with no path yet) the way it stepped over
## from the middle of the spot's cell onto the spot (PassengerSim.world_position()
## over SHUFFLE_TICKS: the drawn body turns to that step), or with no step (a
## spot on its cell's middle) the way it walked onto that cell (Passenger.
## stand_from, kept by GateCapacity.to_spot(), which clears the path), as the
## body keeps facing; else the step of its path it walks next or walked last (a
## boarding file's way on, the way it came to its place); else at the gate
## GATE_FACE (it walked none); else ZERO. Every part is saved sim state, so a
## load faces the same way.
static func stand_face(sim: PassengerSim, p: Passenger) -> Vector2:
	var face := SecurityLooks.face(sim, p)
	if face == Vector2.ZERO:
		face = Vector2(sim.cafes.counter_facing(p))
	var spot := sim.standing.spot_of(p.id)
	var on_spot := (
		spot != StandingSpots.NO_SPOT
		and (p.stage == Passenger.Stage.STANDING or RollerPark.setting_off(sim, p))
	)
	if face == Vector2.ZERO and on_spot:
		var over := sim.standing.world_of(sim.grid, spot) - sim.grid.cell_to_world(p.at)
		if Vector2(over.x, over.z).length() > SPOT_STEP_M:
			face = Vector2(over.x, over.z)
	if face == Vector2.ZERO and on_spot and p.stand_from != Passenger.NO_CELL:
		face = Vector2(p.at - p.stand_from)
	if face == Vector2.ZERO and p.path.size() >= 2:
		var at := clampi(p.path_index, 0, p.path.size() - 2)
		face = Vector2(p.path[at + 1] - p.path[at])
	if face == Vector2.ZERO and on_spot:
		face = GATE_FACE
	return face


## The frame (world, on the floor) a queue stand is chosen and drawn in
## (stand_hand(), RollerPark.plan()): at `at`, facing ground way `face`.
static func stand_frame(at: Vector3, face: Vector2) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, atan2(face.x, face.y)), at)
