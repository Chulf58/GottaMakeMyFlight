class_name BoothRoller
extends RefCounted
## Where a booth guest's roller lies and how its set-down keeps out of walls
## (board 5dc41129). The roller lies fixed at the approach cell
## (RollerPark.chair_front()), along the guest's line, side_m() across from its
## centre: the guest's own seat side (RollerPark.SEAT_SIDE_M, by body and hand),
## no nearer the bench's end panel than panel_room() leaves. At the old
## RollerPark.PARK_SIDE_M (0.32 m) its inner edge was 0.156 m from the guest's
## centre line and a male guest's near leg (left foot 0.15 m out, the leg's
## mesh to 0.258 m) was inside it: food_seats_probe booth 13-3, seed
## 1885947358, BODY_IN_BAG up to 112 points standing and 78 to 88 lying (board
## 8a6068aa). At SecurityLooks.CAFE_BESIDE_M (0.45 m) towards the booth it lay
## 0.035 m inside the end panel. On an open side a male guest's roller reaches
## 0.06 to 0.09 m past the approach cell's edge.
##
## It lies on its hand's side, where the set-down parks it standing
## (RollerPark.park()), unless a wall stands on the approach cell's edge there:
## the wall's face is WALL_FACE_M from the cell's centre, inside the roller's
## outer edge, and the roller cannot come nearer the guest without lying under
## its feet (at 0.255 m its inner edge is 0.09 m from the guest's centre line).
## Then it lies on the other side, still inside the approach cell. Laid on the
## open side from a park on the booth's side it crossed 0.8 m in front of the
## feet in two frames (food_seats_probe BAG_STEP at 13-2, k9).

## A wall's face from the centre of a cell it bounds (BuildView.WALL_THICKNESS
## about the cell's edge).
const WALL_FACE_M := 0.5 - BuildView.WALL_THICKNESS / 2.0
## A set-down that starts with the roller in a wall moves it out over this
## many ticks (drawn()).
const EASE_TICKS := 2.0
## The bench's end panel's outer face (towards the approach cell), across from
## the seat root (tools/blender/interior/build_services_kit.py: the panel at
## x 0.86-0.92 m, the roots at x 0.5 m): 0.58 m from the approach cell's centre.
const PANEL_FACE_M := 0.42
## A roller beside the end panel keeps this far off its outer face.
const PANEL_GAP_M := 0.005


## How far out (m, across the approach cell's frame) booth guest `p`'s roller
## stands or lies on the side of `hand` (0 the right): RollerPark.seat_side()
## for its body, capped by panel_room() on the end panel's side. At booth 13-3
## the panel is on the left at 0.58 m and a room wall on the right edge, so
## the male left leg's 0.43 m is had on neither side: it gets 0.411 m. Away
## from a booth seat, the body's seat side.
static func side_m(sim: PassengerSim, p: Passenger, hand: int) -> float:
	var side := RollerPark.seat_side(PassengerLooks.body_of(p.id, p.variant), hand)
	if not sim.cafes.booth_roller(p):
		return side
	var front: Variant = RollerPark.chair_front(sim, p, SecurityLooks.Kind.ROLLER)
	if front == null:
		return side
	return minf(side, panel_room(sim, p, front as Transform3D, -1.0 if hand == 0 else 1.0))


## The farthest out (m, along `front`'s x from its origin, the approach cell's
## centre facing out of the seat) a booth guest's roller axle may be on its
## `towards` side and keep PANEL_GAP_M off the end panel, where the seat of
## `p`'s visit lies that way; INF on the other side or with no seat.
static func panel_room(
	sim: PassengerSim, p: Passenger, front: Transform3D, towards: float
) -> float:
	var visit := sim.cafes.visit_of(p.id)
	if visit == null or visit.seat.is_empty():
		return INF
	var root := BuildObjectDef.seat_root_world(sim.grid, visit.seat)
	var across := (root - front.origin).dot(front.basis.x) * towards
	return panel_cap(across) if across > 0.0 else INF


## panel_room() with the seat root `across` (m) out from the approach cell's
## centre: the end panel's outer face PANEL_FACE_M nearer, less PANEL_GAP_M and
## half the roller's width (CarryOnProps.bag_box()).
static func panel_cap(across: float) -> float:
	var box := CarryOnProps.bag_box(SecurityLooks.Kind.ROLLER)
	return across - PANEL_FACE_M - maxf(-box.position.x, box.end.x) - PANEL_GAP_M


## +1 or -1: the side (along `front`'s x, the approach cell's frame facing out
## of the seat) a booth guest's roller lies on: its hand's (`hand`, 0 the
## right, as RollerPark.park() takes it) unless that edge is walled.
static func side(sim: PassengerSim, front: Transform3D, hand: int) -> float:
	var own := -1.0 if hand == 0 else 1.0
	return -own if walled(sim, front, own) else own


## Whether a wall stands on the edge of the cell under `front` on its `towards`
## side (along its x).
static func walled(sim: PassengerSim, front: Transform3D, towards: float) -> bool:
	var out := front.basis.x * towards
	var step := Vector2i(roundi(out.x), roundi(out.z))
	var edge := BuildGrid.SIDE_STEP.find(step)
	return edge >= 0 and sim.grid.has_wall(sim.grid.world_to_cell(front.origin), edge)


## At a booth seat (`booth`, CafeSim.booth_roller()), fixes in the world the
## start of a roller's set-down from the pull (a park stamped with a face,
## RollerPark.stamp()) where the pull's trail was as the move began, as a
## floor>pull's start is: held in the body's frame it turned with the walker
## turning on the spot to its seat and swung through the booth's end panel and
## seat (board 5dc41129). Keeps, for the move, the faces of the walls on the
## edges of the cells under that start and under the walker (`body`'s origin),
## so clear_of() keeps the roller out of them. At every other seat it leaves the
## start in the body's frame, as before. At every seat (a park stamped with a
## face, RollerPark.stamp()'s "faced", a booth's too) it keeps the walls round
## the walker as finite boxes ("wall_boxes", PullSide.walls_near()), which
## RollerPark.plan() moves the park out of (ParkWalls, board a40fdbaf). A
## set-down whose turn to the seat puts the pulling hand on the walled side
## turns first (RollerPark.mark_turn_first()). Any older record is cleared
## first.
static func fix_start(bag: Dictionary, booth: bool, sim: PassengerSim, body: Transform3D) -> void:
	bag.erase("wall_faces")
	bag.erase("start_push")
	bag.erase("wall_boxes")
	# With no sim (CarryOnProps driven on its own, as tests do) there is no seat.
	if sim == null:
		return
	if bag.get("park", false) and bag.get("faced", false):
		# A floor>pull's round its park's point (the first tick's, RollerPark.stamp()),
		# not the body drawn on a late first frame.
		var at := body.origin
		if bag.get("park_up", false):
			at = (bag["park_frame"] as Transform3D).origin
		bag["wall_boxes"] = PullSide.walls_near(sim.grid, at)
	if not booth:
		return
	if not bag.get("park", false) or not bag.has("park_frame"):
		return
	var grid := sim.grid
	if CarryLead.start_of(bag)[0] != CarryLead.End.HELD:
		return
	var began: Transform3D = bag.get("start_body", body)
	var start := began * (bag["from"] as Transform3D)
	bag["from_world"] = start
	var faces: Array = []
	var seen := {}
	var under := grid.world_to_cell(body.origin)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var cell := under + Vector2i(dx, dy)
			var centre := grid.cell_to_world(cell)
			for side in 4:
				if not grid.has_wall(cell, side):
					continue
				var step: Vector2i = BuildGrid.SIDE_STEP[side]
				var out := Vector3(step.x, 0.0, step.y)
				var point := centre + out * WALL_FACE_M
				# One face per plane: the walls along one line.
				var key := "%s %.3f" % [step, point.dot(out)]
				# Only a face the walker is inside of: a neighbour's wall seen from
				# its own side faces the walker's cell and pushed the roller 1 m out
				# of it (food_seats_probe BAG_STEP 1.054 m at k13).
				if seen.has(key) or (body.origin - point).dot(out) >= 0.0:
					continue
				seen[key] = true
				faces.append([point, out])
	bag["wall_faces"] = faces
	# How far the start itself is in a wall: eased out over EASE_TICKS (drawn()).
	bag["start_push"] = clear_of(start, faces).origin - start.origin
	# Turned round to face out of the seat, a pulling hand on the walled side
	# gives the roller to the other before setting it down (RollerPark).
	RollerPark.mark_turn_first(bag)


## The roller's transform `xf` as a move of `bag` draws it at `k`, kept out of
## the walls fix_start() kept: moved back by its real depth in them on each
## frame (clear_of()), less what is left of the start's own depth, which eases
## out over EASE_TICKS so neither the roller nor the hand on it steps more than
## a walk does in a frame. A start in the wall came from the walk's pull trail
## (board 578435a7); pushed out at once it stepped 0.272 m (7648d56, by its
## reach about the axle) or 0.056 m (by its depth) in one frame.
static func drawn(xf: Transform3D, bag: Dictionary, k: float, bar: Vector3) -> Transform3D:
	if not bag.has("wall_faces"):
		return xf
	xf = clear_of(xf, bag["wall_faces"], bar)
	var ticks := k * CarryLead.ticks_of(bag)
	var left := 1.0 - smoothstep(0.0, EASE_TICKS, ticks)
	xf.origin -= (bag.get("start_push", Vector3.ZERO) as Vector3) * left
	return xf


## `xf` (the roller's transform as a move draws it) moved back along each of
## `faces` (fix_start()'s [a point on the face, its outward normal]) by as
## much as the roller's box (CarryOnProps.bag_box()) reaches past it, so no
## part of it is in the wall: its real depth on each frame, never more. The
## trail of a walker that came along a wall can start the move in it, and the
## roll to the park turned its corners back into it a tick later (24-36 mesh
## points at k1.33-2.0 when only the start was pushed).
static func clear_of(xf: Transform3D, faces: Array, bar := Vector3.ZERO) -> Transform3D:
	var box := CarryOnProps.bag_box(SecurityLooks.Kind.ROLLER)
	var points: Array[Vector3] = []
	for k in 8:
		points.append(box.get_endpoint(k))
	# The pull bar at the rods' tip as they are drawn now (RollerPark.plan()'s
	# "bar_z"): out past the box, it went 45 mesh points into the wall.
	if bar != Vector3.ZERO:
		points.append(Vector3(box.position.x, bar.y, bar.z))
		points.append(Vector3(box.end.x, bar.y, bar.z))
	for face: Array in faces:
		var out: Vector3 = face[1]
		var depth := 0.0
		for at in points:
			depth = maxf(depth, (xf * at - (face[0] as Vector3)).dot(out))
		xf.origin -= out * depth
	return xf
