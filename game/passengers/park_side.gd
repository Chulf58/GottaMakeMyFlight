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
