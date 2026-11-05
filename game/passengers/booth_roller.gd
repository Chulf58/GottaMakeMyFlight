class_name BoothRoller
extends RefCounted
## Which side of a booth seat's approach cell a guest's roller lies on, and a
## roller set down at any seat kept clear of walls (clear_of_walls())
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


## Pushes the start of a sit-down set-down (RollerPark.stamp(): "seat_start",
## its "from_world" fixed where the pull's trail was) out of any wall on the
## edges of the cell under it, along the wall's normal, until the roller
## clears the wall's face however it turns about its axle: the move rolls it on
## its axle from there to its park (RollerPark.rolled()), and with only its box
## (CarryOnProps.bag_box()) clear of the face at the start it turned 24-36 mesh
## points back into the wall a tick later. It covers every seat a walker turns
## to on the spot with its roller (a gate chair, a cafe or booth seat, an
## activity seat), not only a booth: a walker that came along a wall trailed
## its roller into it, and the fixed start kept it there for the move's first
## ticks (food_seats_probe BAG_IN_WALL at alt_13-1, k0-k2).
static func clear_of_walls(bag: Dictionary, grid: BuildGrid) -> void:
	if not bag.get("seat_start", false) or not bag.has("from_world"):
		return
	var start: Transform3D = bag["from_world"]
	var box := CarryOnProps.bag_box(bag["kind"])
	var axle := start * CarryOnProps.ROLLER_AXLE
	# The furthest the box reaches across the floor from its axle, any way round.
	var reach := 0.0
	for k in 8:
		var arm := start * box.get_endpoint(k) - axle
		reach = maxf(reach, Vector2(arm.x, arm.z).length())
	var cell := grid.world_to_cell(axle)
	var centre := grid.cell_to_world(cell)
	var push := Vector3.ZERO
	for side in 4:
		if not grid.has_wall(cell, side):
			continue
		var step: Vector2i = BuildGrid.SIDE_STEP[side]
		var out := Vector3(step.x, 0.0, step.y)
		var deepest := maxf(0.0, (axle - centre).dot(out) + reach - WALL_FACE_M)
		push -= out * deepest
	if push != Vector3.ZERO:
		start.origin += push
		bag["from_world"] = start
