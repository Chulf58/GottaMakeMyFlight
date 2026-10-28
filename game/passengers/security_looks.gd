class_name SecurityLooks
extends RefCounted
## What a passenger at security looks like on this tick, read from its
## SecurityRuntime phase (Security 7/8). Pure: it reads the sim and the lane
## geometry (SecurityLanes) and returns where the passenger wants to stand,
## which way it faces, where its tray is and where each carry-on bag is.
## PassengerViews and CarryOnProps draw from it; nothing here keeps state.
##
## At a lane: UNPACK steps toward the tray table and faces it; the bags move
## from the hands into a tray on the tray table, one by one as the unpack work
## runs. ARCH on the first pass: the tray rides the X-ray belt beside the
## passenger. PICKUP steps toward the pickup table, the tray waits there and
## the bags go back to the hands one by one. TO_BERTH, RETURN and LEAVE carry
## the bags. REPACK puts them on the floor in front of the passenger, who faces
## the helper's spot. On the second pass, after a repack, the passenger puts
## its bags on a tray again once it reaches the unpack cell, and they ride the
## belt as on the first pass. At the basic scanner: SCAN carries the bags,
## REPACK puts them on the floor where the passenger stands, which holds the
## scanner. Outside security the bags are carried, and set down while seated
## (bag_homes(), floor_spot()).
##
## Shared cells: the next queue front walks onto the unpack cell while the
## passenger before it still unpacks there, and a returner crosses the unpack
## cell on its second pass. A queue front of a lane therefore stops at the
## unpack cell's queue-side edge (QUEUE_EDGE_M from its centre) while another
## admitted passenger of that lane unpacks or is in ARCH within CLEAR_M of the
## unpack centre.

enum Home { NONE, HAND, TRAY, FLOOR }
enum Tray { NONE, IN, RIDE, OUT }

## How far an unpacking or picking-up passenger steps toward its table.
const STEP_M := 0.15
## Where a held-back queue front stands, from the unpack cell's centre.
const QUEUE_EDGE_M := 0.5
## A passenger in ARCH this near the unpack centre still holds the queue back:
## past the arch for one leaving, and the whole crossing for a returner, who
## starts its ARCH one cell to the side of the unpack cell.
const CLEAR_M := 1.05
## Two bags are drawn at this scale so both fit one tray.
const TWO_BAG_SCALE := 0.55
## A floor bag's centre, in front of the passenger.
const FLOOR_AHEAD_M := 0.56
## Two floor bags stand this far either side of the passenger's line.
const FLOOR_APART_M := 0.16
## A bag at a gate chair lies at the sitter's feet, this far ahead.
const SEAT_AHEAD_M := 0.62
## A bag at a cafe seat lies beside the chair, this far to the sitter's right.
const CAFE_BESIDE_M := 0.45


## The lane geometry of the station `p` is admitted at or queues for, or {}
## at a basic scanner or anywhere else.
static func lane_of(sim: PassengerSim, p: Passenger) -> Dictionary:
	var lanes := sim.layout.security_lanes
	if p.station == 0 or not lanes.is_complete(p.station):
		return {}
	return lanes.lane(p.station)


## A grid step as a world direction.
static func world_dir(step: Vector2i) -> Vector3:
	return Vector3(step.x, 0.0, step.y)


## Where `p` wants to be drawn, from its sim position: a step toward the table
## at UNPACK and PICKUP, held back at the queue edge as the header says, and
## zero otherwise. PassengerViews moves the drawn offset toward it at walking
## speed.
static func target_offset(sim: PassengerSim, p: Passenger) -> Vector3:
	var lane := lane_of(sim, p)
	if lane.is_empty():
		return Vector3.ZERO
	if p.stage == Passenger.Stage.SECURITY_QUEUE:
		return _queue_hold(sim, p, lane)
	if p.stage != Passenger.Stage.SECURITY:
		return Vector3.ZERO
	match p.security_phase:
		SecurityRuntime.Phase.UNPACK, SecurityRuntime.Phase.PICKUP:
			return world_dir(lane["side"]) * STEP_M
	return Vector3.ZERO


## The ground direction (x, z) `p` faces while it works, or ZERO to keep its
## heading: the tray table at UNPACK, the pickup table at PICKUP, the helper's
## spot at a lane's REPACK, and the lane while a queue front is held back.
static func face(sim: PassengerSim, p: Passenger) -> Vector2:
	var lane := lane_of(sim, p)
	if lane.is_empty():
		return Vector2.ZERO
	if p.stage == Passenger.Stage.SECURITY_QUEUE:
		var held := _queue_hold(sim, p, lane) != Vector3.ZERO
		return -Vector2(lane["front"]) if held else Vector2.ZERO
	if p.stage != Passenger.Stage.SECURITY:
		return Vector2.ZERO
	match p.security_phase:
		SecurityRuntime.Phase.UNPACK, SecurityRuntime.Phase.PICKUP:
			return Vector2(lane["side"])
		SecurityRuntime.Phase.REPACK:
			return -Vector2(lane["front"])
	return Vector2.ZERO


## Where the tray of `p` is: on the tray table at UNPACK, riding the belt in
## ARCH, on the pickup table at PICKUP. A returner's ARCH starts beside the
## unpack cell, so its tray appears once it reaches the unpack cell.
static func tray(sim: PassengerSim, p: Passenger) -> Tray:
	if p.stage != Passenger.Stage.SECURITY or lane_of(sim, p).is_empty():
		return Tray.NONE
	match p.security_phase:
		SecurityRuntime.Phase.UNPACK:
			return Tray.IN
		SecurityRuntime.Phase.ARCH:
			return Tray.RIDE if _on_passage(p) else Tray.NONE
		SecurityRuntime.Phase.PICKUP:
			return Tray.OUT
	return Tray.NONE


## Where each of the carry-on bags of `p` is (Home), one entry per bag, for
## the whole visit: in hand, on the floor while seated at a gate chair or a
## cafe seat, and at security as the header says.
static func bag_homes(sim: PassengerSim, p: Passenger) -> Array[Home]:
	var out: Array[Home] = []
	if p.stage == Passenger.Stage.SECURITY:
		for i in p.carry_on:
			out.append(_security_home(sim, p, i))
		return out
	var home := Home.FLOOR if _seated(sim, p) else Home.HAND
	for i in p.carry_on:
		out.append(home)
	return out


## Which hand holds bag `index` of `p` when it is carried: 0 the right, 1 the
## left. Two bags take one hand each. One bag is in the right hand, except at
## a lane (queuing or inside it) when the right hand is on the side of the
## lane's parts and arch for the way the passenger walks: then the left, so
## the bag passes the arch and tables on the open side.
static func hand_of(sim: PassengerSim, p: Passenger, index: int) -> int:
	if p.carry_on > 1:
		return index
	var lane := lane_of(sim, p)
	if lane.is_empty() or p.path.size() < 2:
		return 0
	var at := clampi(p.path_index, 0, p.path.size() - 2)
	var step := p.path[at + 1] - p.path[at]
	if step == Vector2i.ZERO:
		return 0
	var ahead := world_dir(step)
	var right := ahead.cross(Vector3.UP)
	return 1 if right.dot(world_dir(lane["side"])) > 0.0 else 0


## The scale every bag of `p` is drawn at.
static func bag_scale(p: Passenger) -> float:
	return TWO_BAG_SCALE if p.carry_on > 1 else 1.0


## Bag `index` of `count`, relative to the tray's mount: centred for one bag,
## end to end along the tray's length for two.
static func in_tray(index: int, count: int, bag_length: float) -> Vector3:
	if count < 2:
		return Vector3.ZERO
	var half := bag_length * TWO_BAG_SCALE * 0.5 + 0.003
	return Vector3(0.0, 0.0, half if index == 0 else -half)


## Where floor bag `index` of `count` of `p` lies, in the passenger's frame
## (+z ahead, +x its left, on the floor): at the feet of a gate chair, beside
## a cafe seat (the table is ahead), and ahead of a repacking passenger. One
## bag lies across the passenger's line, two lie along it side by side.
static func floor_spot(_sim: PassengerSim, p: Passenger, index: int, count: int) -> Transform3D:
	var across := Basis(Vector3.UP, PI / 2.0) if count < 2 else Basis.IDENTITY
	var side := 0.0 if count < 2 else (FLOOR_APART_M if index == 0 else -FLOOR_APART_M)
	if p.stage in Passenger.CAFE_SEAT_STAGES:
		# Beside the chair, lying along it.
		var along := 0.0 if count < 2 else side
		return Transform3D(Basis.IDENTITY, Vector3(-CAFE_BESIDE_M, 0.0, along))
	if p.stage in PassengerSim.SEAT_STAGES:
		return Transform3D(across, Vector3(side, 0.0, SEAT_AHEAD_M))
	return Transform3D(across, Vector3(side, 0.0, FLOOR_AHEAD_M))


## Whether `p` sits at a gate chair or a cafe seat (or is sitting down or
## standing up there).
static func _seated(sim: PassengerSim, p: Passenger) -> bool:
	if p.stage in PassengerSim.SEAT_STAGES and p.seat_object != 0:
		return true
	return p.stage in Passenger.CAFE_SEAT_STAGES and sim.cafes.seat_facing(p) != Vector2i.ZERO


static func _security_home(sim: PassengerSim, p: Passenger, i: int) -> Home:
	var on_lane := not lane_of(sim, p).is_empty()
	var phase := p.security_phase as SecurityRuntime.Phase
	var done := SecurityRuntime.work_for(phase, p) - p.security_work
	var home := Home.HAND
	match phase:
		SecurityRuntime.Phase.REPACK:
			home = Home.FLOOR
		SecurityRuntime.Phase.UNPACK:
			var in_tray := (
				SecurityRuntime.LANE_UNPACK_TICKS + i * SecurityRuntime.LANE_UNPACK_BAG_TICKS
			)
			home = Home.TRAY if done >= in_tray else Home.HAND
		SecurityRuntime.Phase.ARCH:
			home = Home.TRAY if _on_passage(p) else Home.HAND
		SecurityRuntime.Phase.PICKUP:
			var out_of_tray := (
				SecurityRuntime.LANE_PICKUP_TICKS + i * SecurityRuntime.LANE_PICKUP_BAG_TICKS
			)
			home = Home.TRAY if done < out_of_tray else Home.HAND
	if not on_lane and home == Home.TRAY:
		home = Home.HAND
	return home


## Whether a lane passenger in ARCH has reached the passage: always on the
## first pass; on a returner's second pass once it stands on the unpack cell
## (its path runs from the return route's end through the passage).
static func _on_passage(p: Passenger) -> bool:
	return not p.incident_resolved or p.path_index >= 1


## A queue front of a lane stops at the unpack cell's queue-side edge while
## another admitted passenger of the lane unpacks or is in ARCH near the
## unpack centre. The offset grows as it walks in, so the hold is continuous.
static func _queue_hold(sim: PassengerSim, p: Passenger, lane: Dictionary) -> Vector3:
	var unpack := sim.grid.cell_to_world(lane["unpack"])
	var front := world_dir(lane["front"])
	var rel := sim.world_position(p) - unpack
	var ahead := rel.dot(front)
	if ahead >= QUEUE_EDGE_M or (rel - front * ahead).length() > 0.3:
		return Vector3.ZERO
	if not _crossing_busy(sim, p, unpack):
		return Vector3.ZERO
	return front * (QUEUE_EDGE_M - ahead)


static func _crossing_busy(sim: PassengerSim, p: Passenger, unpack: Vector3) -> bool:
	var record := sim.security.record_of(p.station)
	for id: int in record.get("admitted", []):
		if id == p.id:
			continue
		var other := sim.get_passenger(id)
		match other.security_phase:
			SecurityRuntime.Phase.UNPACK:
				return true
			SecurityRuntime.Phase.ARCH:
				if sim.world_position(other).distance_to(unpack) < CLEAR_M:
					return true
	return false
