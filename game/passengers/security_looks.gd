class_name SecurityLooks
extends RefCounted
## What a passenger at security looks like on this tick, read from its
## SecurityRuntime phase (Security 7/8). Pure: it reads the sim and the lane
## geometry (SecurityLanes) and returns where the passenger wants to stand,
## which way it faces, where its tray is and where each carry-on bag is.
## PassengerViews and SecurityProps draw from it; nothing here keeps state.
##
## At a lane: UNPACK steps toward the tray table and faces it; the bags move
## from the hands into a tray on the tray table, one by one as the unpack work
## runs. ARCH on the first pass: the tray rides the X-ray belt beside the
## passenger. PICKUP steps toward the pickup table, the tray waits there and
## the bags go back to the hands one by one. TO_BERTH, RETURN and LEAVE carry
## the bags. REPACK puts them on the floor in front of the passenger, who faces
## the helper's spot. The second pass through the arch, after a repack, keeps
## the bags in hand and has no tray. At the basic scanner: SCAN carries the
## bags, REPACK puts them on the floor where the passenger stands, which holds
## the scanner. Bags show only inside Stage.SECURITY.
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
const FLOOR_AHEAD_M := 0.5
## Two floor bags stand this far either side of the passenger's line.
const FLOOR_APART_M := 0.16


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


## Where the tray of `p` is: on the tray table at UNPACK, riding the belt on
## the first ARCH pass, on the pickup table at PICKUP after a first pass.
static func tray(sim: PassengerSim, p: Passenger) -> Tray:
	if p.stage != Passenger.Stage.SECURITY or lane_of(sim, p).is_empty():
		return Tray.NONE
	if p.incident_resolved:
		return Tray.NONE
	match p.security_phase:
		SecurityRuntime.Phase.UNPACK:
			return Tray.IN
		SecurityRuntime.Phase.ARCH:
			return Tray.RIDE
		SecurityRuntime.Phase.PICKUP:
			return Tray.OUT
	return Tray.NONE


## Where each of the carry-on bags of `p` is (Home), one entry per bag.
static func bag_homes(sim: PassengerSim, p: Passenger) -> Array[Home]:
	var out: Array[Home] = []
	if p.stage != Passenger.Stage.SECURITY:
		return out
	var on_lane := not lane_of(sim, p).is_empty()
	var phase := p.security_phase as SecurityRuntime.Phase
	var done := SecurityRuntime.work_for(phase, p) - p.security_work
	for i in p.carry_on:
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
				home = Home.HAND if p.incident_resolved else Home.TRAY
			SecurityRuntime.Phase.PICKUP:
				var out_of_tray := (
					SecurityRuntime.LANE_PICKUP_TICKS + i * SecurityRuntime.LANE_PICKUP_BAG_TICKS
				)
				var waiting := not p.incident_resolved and done < out_of_tray
				home = Home.TRAY if waiting else Home.HAND
		if not on_lane and home == Home.TRAY:
			home = Home.HAND
		out.append(home)
	return out


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


## Bag `index` of `count` on the floor, in the passenger's frame (+z ahead).
static func on_floor(index: int, count: int) -> Vector3:
	if count < 2:
		return Vector3(0.0, 0.0, FLOOR_AHEAD_M)
	return Vector3(FLOOR_APART_M if index == 0 else -FLOOR_APART_M, 0.0, FLOOR_AHEAD_M)


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
