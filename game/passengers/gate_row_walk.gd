class_name GateRowWalk
extends RefCounted
## The walk of a guest to its gate chair front (user ruling gate-chair-row-
## walk-guests-walk-one-cell-out-from-the-chair, board 11922532): every other
## gate seat's front costs FRONT_COST times its step for that one query
## (BuildGrid.find_path_costed()), so a guest coming along a row of fronts
## walks one cell further out and turns in only at its own. A neighbour's
## roller lies beside its front, 0.07 m ahead of it (GateRoller.spot()), on the
## line along the fronts, and a guest walking that line put its legs through it.
## The fronts of one row are next to each other, so the gaps between them are
## front cells too. Only GateCapacity's seat claim and PassengerEdits' replan of
## a guest bound for its seat walk so; every other route, the staff graph and
## RouteCache's walk lengths are the plain graph's (a seat walk's forecast
## under-reads the turn round the row a little). Nothing is saved.

## How much a step onto another guest's chair front costs, against a plain
## step: along three fronts that is about 9, one cell out and back in about 5.8.
const FRONT_COST := 3.0


## Every gate seat front of `sim`'s layout but `own` (the guest's own front).
static func costly_fronts(sim: PassengerSim, own: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for seat: Dictionary in sim.layout.seats:
		var front: Vector2i = seat["front"]
		if front != own and front not in out:
			out.append(front)
	return out


## The walk from `from` to the chair front `front` of a guest seating there.
static func path(sim: PassengerSim, from: Vector2i, front: Vector2i) -> Array[Vector2i]:
	return sim.grid.find_path_costed(from, front, costly_fronts(sim, front), FRONT_COST)
