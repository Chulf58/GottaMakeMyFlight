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
## the return route it walks next, so it picks them up ahead of it rather
## than behind (from where a bag would pass through the body). On the second
## pass, after a repack, the passenger puts its bags on a tray again when it
## reaches the unpack cell, and they ride the belt as on the first pass. At
## the basic scanner: SCAN carries the bags, REPACK puts them on the floor
## where the passenger stands, which holds the scanner. Outside security the
## bags are carried, and set down while seated (bag_homes(), floor_spot()).
##
## Shared cells: the next queue front walks onto the unpack cell while the
## passenger before it still unpacks there, and a returner crosses the unpack
## cell on its second pass. A queue front of a lane therefore stops at the
## unpack cell's queue-side edge (QUEUE_EDGE_M from its centre) while another
## admitted passenger of that lane unpacks or is in ARCH within CLEAR_M of the
## unpack centre.

enum Home { NONE, HAND, TRAY, FLOOR }
enum Tray { NONE, IN, RIDE, OUT }
## The kinds of carry-on bag (decision carry-on-bag-kinds-backpack-shoulder-or-
## tote-bag-small-rolle): looks only, the sim never reads them.
enum Kind { CASE, BACKPACK, SHOULDER, ROLLER }
## How a kind is carried while its home is HAND: the hard case in the hand,
## the backpack worn on the back, the tote on one shoulder, the roller pulled.
enum Carry { HAND, BACK, SHOULDER, PULL }

## The interior kit piece that draws each kind.
const KIND_PIECES := {
	Kind.CASE: "carry_on_bag",
	Kind.BACKPACK: "carry_backpack",
	Kind.SHOULDER: "carry_shoulder_bag",
	Kind.ROLLER: "carry_roller",
}
const KIND_CARRY := {
	Kind.CASE: Carry.HAND,
	Kind.BACKPACK: Carry.BACK,
	Kind.SHOULDER: Carry.SHOULDER,
	Kind.ROLLER: Carry.PULL,
}

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
## A bag in a toilet stall lies this far out from the stall's footprint centre:
## clear of the seated knees (about 0.21 m) and inside the closed door (0.92 m).
const STALL_BAG_M := 0.6


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
## heading: the tray table at UNPACK, the pickup table at PICKUP, the return
## route at a lane's REPACK, and the lane while a queue front is held back.
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
			return Vector2(lane["front"])
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
## the whole visit: in hand, on the floor while seated at a gate chair, a
## cafe seat or in a toilet stall, and at security as the header says.
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
## left. Two bags take one hand each. One bag is in the right hand, unless
## the cell beside the passenger on its right, for the way it walks (or last
## walked), is closed off by a wall or holds an object (a lane part, a desk)
## and the left is open: then the left, so the bag passes on the open side.
static func hand_of(sim: PassengerSim, p: Passenger, index: int) -> int:
	if p.carry_on > 1:
		return index
	if p.path.size() < 2:
		return 0
	var at := clampi(p.path_index, 0, p.path.size() - 2)
	var step := p.path[at + 1] - p.path[at]
	if step == Vector2i.ZERO:
		return 0
	var right := world_dir(step).cross(Vector3.UP)
	var right_step := Vector2i(signi(roundi(right.x)), signi(roundi(right.z)))
	var cell := p.at
	if _closed(sim.grid, cell, right_step) and not _closed(sim.grid, cell, -right_step):
		return 1
	return 0


## The kind of carry-on bag `index` of `p`: a fixed hash of the passenger's id
## and the bag's index, so a save, a load and a replay draw the same bags
## without any saved state, and the sim RNG is not drawn from. A second bag
## never repeats a backpack or a roller (one back, one trailer).
static func bag_kind(p: Passenger, index: int) -> Kind:
	var first := _mix(p.id * 2) % Kind.size() as Kind
	if index == 0:
		return first
	var second := _mix(p.id * 2 + 1) % Kind.size() as Kind
	if second == first and (first == Kind.BACKPACK or first == Kind.ROLLER):
		second = (first + 1 + _mix(p.id * 2 + 7) % (Kind.size() - 1)) % Kind.size() as Kind
	return second


## How bag `index` of `p` is carried while in hand (Carry).
static func carry_of(p: Passenger, index: int) -> Carry:
	return KIND_CARRY[bag_kind(p, index)]


## The side a worn shoulder bag hangs on: 0 the right, 1 the left, by its
## index (stable, so a narrow cell never moves it across).
static func worn_side(index: int) -> int:
	return index % 2


## A 32-bit integer mixer (a non-negative result).
static func _mix(value: int) -> int:
	var x := value & 0xFFFFFFFF
	x = ((x >> 16) ^ x) * 0x45D9F3B & 0xFFFFFFFF
	x = ((x >> 16) ^ x) * 0x45D9F3B & 0xFFFFFFFF
	return (x >> 16) ^ x


## Whether `p` carries its bags in front of the body: when the cell it stands
## on, or the next cell it walks into, is closed on both flanks for the way it
## walks (decision in-a-cell-closed-on-both-sides-a-passenger-carries-their-
## bag). A side-carried bag reaches about 0.55-0.6 m out, more than such a
## cell leaves. Standing still, the cell it stands on and its last step count.
static func carry_front(sim: PassengerSim, p: Passenger) -> bool:
	if p.path.size() < 2:
		return false
	var at := clampi(p.path_index, 0, p.path.size() - 2)
	var step := p.path[at + 1] - p.path[at]
	if step == Vector2i.ZERO:
		return false
	var right := world_dir(step).cross(Vector3.UP)
	var flank := Vector2i(signi(roundi(right.x)), signi(roundi(right.z)))
	var cells: Array[Vector2i] = [p.at]
	if p.is_moving():
		cells.append(p.path[at + 1])
	for cell in cells:
		if _closed(sim.grid, cell, flank) and _closed(sim.grid, cell, -flank):
			return true
	return false


## Whether either straight part of a (possibly diagonal) step out of `cell`
## is closed (_side_closed).
static func _closed(grid: BuildGrid, cell: Vector2i, toward: Vector2i) -> bool:
	if toward.x != 0 and _side_closed(grid, cell, Vector2i(toward.x, 0)):
		return true
	return toward.y != 0 and _side_closed(grid, cell, Vector2i(0, toward.y))


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
## a cafe seat (the table is ahead), by the door inside a toilet stall
## (_stall_spot()), and ahead of a repacking passenger. One
## bag lies across the passenger's line, two lie along it side by side.
static func floor_spot(sim: PassengerSim, p: Passenger, index: int, count: int) -> Transform3D:
	var across := Basis(Vector3.UP, PI / 2.0) if count < 2 else Basis.IDENTITY
	var side := 0.0 if count < 2 else (FLOOR_APART_M if index == 0 else -FLOOR_APART_M)
	var where := StageKinds.location(p.stage)
	if where == StageKinds.Location.FACILITY_SEAT and _in_stall(sim, p):
		# On the stall's floor by the door, ahead of the knees.
		return Transform3D(across, _stall_spot(sim, p) + Vector3(side, 0.0, 0.0))
	if where == StageKinds.Location.FACILITY_SEAT:
		# Beside the chair, lying along it.
		var along := 0.0 if count < 2 else side
		return Transform3D(Basis.IDENTITY, Vector3(-CAFE_BESIDE_M, 0.0, along))
	if where == StageKinds.Location.GATE_SEAT:
		return Transform3D(across, Vector3(side, 0.0, SEAT_AHEAD_M))
	return Transform3D(across, Vector3(side, 0.0, FLOOR_AHEAD_M))


## Whether the edge of `cell` toward `toward` (a straight grid step) has a
## wall, or the cell beyond holds an object.
static func _side_closed(grid: BuildGrid, cell: Vector2i, toward: Vector2i) -> bool:
	var side := BuildGrid.SIDE_STEP.find(toward)
	if side < 0:
		return false
	return grid.has_wall(cell, side) or grid.object_at(cell + toward) != 0


## Whether `p` sits at a gate chair, a cafe seat or in a toilet stall (or is
## sitting down or standing up there). Stepping into or out of a stall is not
## seated: the bags stay in hand.
static func _seated(sim: PassengerSim, p: Passenger) -> bool:
	var where := StageKinds.location(p.stage)
	if where == StageKinds.Location.GATE_SEAT and p.seat_object != 0:
		return true
	if where != StageKinds.Location.FACILITY_SEAT:
		return false
	return sim.cafes.seat_facing(p) != Vector2i.ZERO or _in_stall(sim, p)


## Whether `p` sits down, sits or stands up in a toilet stall, facing out of
## its door.
static func _in_stall(sim: PassengerSim, p: Passenger) -> bool:
	return sim.toilets.use_facing(p) != Vector2i.ZERO


## Where the bags of a passenger in a stall lie: on the floor between the
## seated knees and the closed door, a point fixed in the stall (the body
## shuffles between Mount_Turn and Mount_Use under it), given in the
## passenger's frame, which faces out of the door. The view draws the body
## between two ticks while this is worked out from the tick's own position, so
## during the shuffle a bag is off by at most one tick's step.
static func _stall_spot(sim: PassengerSim, p: Passenger) -> Vector3:
	var stall := sim.toilets.visit_of(p.id).stall
	var front: Vector2i = stall["front"]
	var out := world_dir(front)
	var centre: Vector3 = stall["use"] - out * ToiletLayout.USE_M
	var spot := centre + out * STALL_BAG_M
	return Vector3(0.0, 0.0, (spot - sim.world_position(p)).dot(out))


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
