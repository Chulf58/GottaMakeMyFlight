class_name ParkSide
extends RefCounted
## The hand a one-roller guest holds its roller in at a seat where it parks
## the roller beside it: the open side when a wall stands on its hand's side
## (user ruling a-guest-pulling-a-roller-through-a-doorway-tucks-it-in-line:
## "A parked or stood roller beside a wall goes on the open side, following
## the hand-swap ruling b05a0fab and the booth precedent (BoothRoller.side)";
## boards a40fdbaf, cfe95aad). SecurityLooks.hand_of() asks it, so the hand,
## the park (RollerPark.park(), on the hand's side), the floor spot and the
## pick-up all take one side. It answers from NEAR_CELLS out on the way in,
## so PullSide has the roller in that hand (hand_of() is its "first") before
## the set-down starts: a set-down from the other hand parked on the walled
## side and laid the roller across in front of the feet (food_seats_probe
## BAG_STEP 0.432 m in a frame at booth seat 13-1).
##
## At a booth seat (CafeSim.booth_roller()) a side is walled when a wall stands
## on that edge of the approach cell (BoothRoller.walled()), as
## BoothRoller.side() lays the roller. At a sofa or nap pod a side is walled
## when the park on it (RollerPark.park(), scale 1) reaches into a wall
## (ParkWalls.inside(), PullSide.walls_near()) standing at the slot cell to set
## it down or at the seat root to pick it up: at the lounge sofa's west seat
## the right-hand park stood 0.04 m into the end of the wall beside the door,
## off the slot cell's own edges. Walled on both sides or neither, the hand is
## hand_of()'s own (`fallback`), and ParkWalls moves the park out of any wall.
## What it does not guarantee: a gate chair or a cafe table chair (neither was
## seen parking into a wall) keeps hand_of()'s own hand.

## A guest this many cells or fewer from where it parks takes the open hand.
const NEAR_CELLS := 3
const CAFE_STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.CAFE_TO_SEAT,
	Passenger.Stage.CAFE_SITTING_DOWN,
	Passenger.Stage.CAFE_SEATED,
	Passenger.Stage.CAFE_STANDING_UP,
]
const SHOP_STAGES: Array[Passenger.Stage] = [Passenger.Stage.SHOP_WALK, Passenger.Stage.SHOP_BROWSE]


## The hand (0 right, 1 left) one-bag guest `p` holds its roller in: the open
## side's at a booth seat or a sofa or nap pod with a wall on one side only,
## else `fallback`.
static func hand(sim: PassengerSim, p: Passenger, fallback: int) -> int:
	if SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.ROLLER:
		return fallback
	var walled := _walled(sim, p)
	if walled.is_empty() or walled[0] == walled[1]:
		return fallback
	return 1 if walled[0] else 0


## [right walled, left walled] for `p` near its booth seat or activity seat;
## empty anywhere else.
static func _walled(sim: PassengerSim, p: Passenger) -> Array:
	if p.stage in CAFE_STAGES and sim.cafes.booth_roller(p):
		var seat: Dictionary = sim.cafes.visit_of(p.id).seat
		var front := _frame(sim, seat["approach"], seat["facing"])
		if not _near(p, seat["approach"]):
			return []
		return [BoothRoller.walled(sim, front, -1.0), BoothRoller.walled(sim, front, 1.0)]
	if p.stage not in SHOP_STAGES:
		return []
	var visit := sim.shops.visit_of(p.id)
	if visit == null or visit.slot.is_empty():
		return []
	var record := visit.piece if not visit.piece.is_empty() else sim.grid.get_object(visit.display)
	var kind: int = ActivityPoses.KINDS.get(record.get("def", &""), ActivityPoses.Kind.NONE)
	if kind != ActivityPoses.Kind.SEAT and kind != ActivityPoses.Kind.RECLINE:
		return []
	var cell: Vector2i = visit.slot["approach"]
	if not _near(p, cell):
		return []
	var out := TerminalLayout.front_of(record["facing"])
	var root := ActivityPoses.spot_of(sim.grid, record, visit.index)
	var spots := [_frame(sim, cell, out), Transform3D(_frame(sim, cell, out).basis, root)]
	var walled := [false, false]
	for at: Transform3D in spots:
		var walls := PullSide.walls_near(sim.grid, at.origin)
		for h in 2:
			if ParkWalls.inside(RollerPark.park(at, h, 1.0), walls):
				walled[h] = true
	return walled


## Whether `p` is NEAR_CELLS or fewer from `cell` (either way on the grid).
static func _near(p: Passenger, cell: Vector2i) -> bool:
	var d := (p.at - cell).abs()
	return maxi(d.x, d.y) <= NEAR_CELLS


## The frame (world, on the floor) at `cell` facing grid way `out`.
static func _frame(sim: PassengerSim, cell: Vector2i, out: Vector2i) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, atan2(out.x, out.y)), sim.grid.cell_to_world(cell))
