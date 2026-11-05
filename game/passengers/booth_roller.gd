class_name BoothRoller
extends RefCounted
## Which side of a booth seat's approach cell a guest's roller lies on
## (board 5dc41129). The roller lies fixed at the approach cell
## (RollerPark.chair_front()), RollerPark.PARK_SIDE_M (0.32 m) across from its
## centre, along the guest's line: 0.164 m either side of that, so it keeps
## inside the cell (0.484 m of 0.5) and 0.096 m clear of the end panel's outer
## face on the booth's side. At SecurityLooks.CAFE_BESIDE_M (0.45 m) towards
## the booth it lay 0.035 m inside the end panel.
##
## It lies on the open side, away from the booth, unless a wall stands on the
## approach cell's edge there: the wall's face is WALL_FACE_M from the cell's
## centre, inside the roller's outer edge, and the roller cannot come nearer
## the guest without lying under its feet (at 0.255 m its inner edge is 0.09 m
## from the guest's centre line). Then it lies on the booth's side, still
## inside the approach cell.

## A wall's face from the centre of a cell it bounds (BuildView.WALL_THICKNESS
## about the cell's edge).
const WALL_FACE_M := 0.5 - BuildView.WALL_THICKNESS / 2.0


## +1 or -1: the side (along `front`'s x, the approach cell's frame facing out
## of the seat) `p`'s roller lies on at its booth seat.
static func side(sim: PassengerSim, p: Passenger, front: Transform3D) -> float:
	var root := front.affine_inverse() * sim.cafes.seat_root(p)
	var open := 1.0 if root.x < 0.0 else -1.0
	if walled(sim, front, open):
		return -open
	return open


## Whether a wall stands on the edge of the cell under `front` on its `towards`
## side (along its x).
static func walled(sim: PassengerSim, front: Transform3D, towards: float) -> bool:
	var out := front.basis.x * towards
	var step := Vector2i(roundi(out.x), roundi(out.z))
	var edge := BuildGrid.SIDE_STEP.find(step)
	return edge >= 0 and sim.grid.has_wall(sim.grid.world_to_cell(front.origin), edge)
