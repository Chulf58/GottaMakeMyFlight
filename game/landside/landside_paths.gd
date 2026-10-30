class_name LandsidePaths
extends RefCounted
## The routes a car drives into and out of a curb berth or a parking slot, and
## the walk out of a car park, built once from a LandsideDefinition. A berth
## or a slot has one path through it: in from the lane the car leaves, the
## stand where it stops, and out to the start of the lane it joins next.
## LandsideSim keeps a car in a berth or a slot as a position in whole mm along
## that path, so the car moves at most a lane step a tick and never jumps.
##
## A berth's path starts at road_in's start and follows road_in (carried on
## past its end along its last segment) to BERTH_APPROACH_MM before the berth,
## so a car leaving road_in for it keeps its position. It tapers in to
## BERTH_STRAIGHT_MM before the berth and runs straight in; out it runs
## straight on, tapers back to the road line BERTH_APPROACH_MM past the berth
## and drives along it to road_out's start.
##
## A slot's path starts with its lot's access lane, so a car at the gate keeps
## its position: then through a multi-storey's entrance, on the ground to the
## aisle front or up the ramps of the decks below the slot's (each deck's way
## down, reversed), along the deck's aisle to the stall and into it, nose
## first. Out, the car backs into the aisle and drives the same way back out,
## through the entrance or, when the lot has one, its own way_out beside it,
## and on to the exit lane's start. A car that reaches the gate empty turns
## round there, in front of the entrance or at the aisle front. A passenger
## from an upper deck walks the aisle, every ramp down and out through the
## entrance to the gate, never straight through a floor.

const BERTH_APPROACH_MM := 4750
const BERTH_STRAIGHT_MM := 1500
## A slot is on the deck whose aisle height is this close to its own.
const DECK_TOLERANCE := 0.5
## A walk out of a car park climbs or drops at most this much between two of
## its points; a longer ramp segment gets points in between.
const WALK_STEP_M := 0.4

var definition: LandsideDefinition
## How far along road_in, carried on past its end, road_out starts.
var out_mm := 0
## Per berth: its path and the path's length, where on it the car stands,
## where it leaves the road line going in (also its distance along road_in),
## where it is back on the road line coming out and that point's distance
## along road_in, and how much longer the way out to there is than the road
## line beside it.
var berth_path: Array[PackedVector3Array] = []
var berth_end: Array[int] = []
var berth_stand: Array[int] = []
var berth_split: Array[int] = []
var berth_join: Array[int] = []
var berth_join_mm: Array[int] = []
var berth_slack: Array[int] = []
## Per lot spot, per slot: its path, the path's length, where the car stands
## and where backing out of the stall ends.
var slot_path: Array = []
var slot_end: Array = []
var slot_stand: Array = []
var slot_back: Array = []
## Per lot spot: the turn round at the gate, and its length.
var turn_path: Array[PackedVector3Array] = []
var turn_end: Array[int] = []


func _init(with_definition: LandsideDefinition) -> void:
	definition = with_definition
	out_mm = LandsideDefinition.mm_along(definition.road_in, definition.road_out[0])
	for i in definition.berth_count():
		_add_berth(i)
	for spot in definition.lots:
		_add_lot(spot)


## The deck a slot of `lot` stands on: 0 for the ground, k for the deck whose
## way down is ramps[k - 1]; -1 when it is on no deck.
static func deck_of(lot: LandsideLotSpot, slot: Vector3) -> int:
	if absf(slot.y - lot.aisle_front.y) <= DECK_TOLERANCE:
		return 0
	for k in lot.ramps.size():
		if absf(slot.y - lot.ramps[k][0].y) <= DECK_TOLERANCE:
			return k + 1
	return -1


## The polyline a car on `lane` follows (lot spot `lot`, berth or slot
## `stop`; a car on a lot's slot lane with no slot is turning round).
func path(lane: LandsideVehicle.Lane, lot: int, stop: int) -> PackedVector3Array:
	match lane:
		LandsideVehicle.Lane.ROAD_OUT:
			return definition.road_out
		LandsideVehicle.Lane.ACCESS:
			return definition.lots[lot].access
		LandsideVehicle.Lane.LOT_EXIT:
			return definition.lots[lot].exit
		LandsideVehicle.Lane.BERTH:
			return berth_path[stop]
		LandsideVehicle.Lane.SLOT:
			return slot_path[lot][stop] if stop >= 0 else turn_path[lot]
	return definition.road_in


## A berth or slot path's length in mm; the turn round's for no slot.
func end_of(lane: LandsideVehicle.Lane, lot: int, stop: int) -> int:
	if lane == LandsideVehicle.Lane.BERTH:
		return berth_end[stop]
	if stop < 0:
		return turn_end[lot]
	return slot_end[lot][stop]


## Where on a berth or slot path the car stands; -1 for the turn round.
func stand_of(lane: LandsideVehicle.Lane, lot: int, stop: int) -> int:
	if lane == LandsideVehicle.Lane.BERTH:
		return berth_stand[stop]
	if stop < 0:
		return -1
	return slot_stand[lot][stop]


## The flat way a car `mm` along its path faces: the way it drives, except
## while it backs out of a stall, and in the stall itself, nose in.
func facing(lane: LandsideVehicle.Lane, lot: int, stop: int, mm: int) -> Vector3:
	var dir := LandsideDefinition.heading_at(path(lane, lot, stop), mm)
	if lane == LandsideVehicle.Lane.SLOT and stop >= 0:
		if mm >= slot_stand[lot][stop] and mm < slot_back[lot][stop]:
			return -dir
	return dir


## How a position on the place `before` reads on the place `now` a tick
## later: the mm to take off a position on `before` to have it on `now`, 0
## when both share the coordinate (the same place, a lane and the path that
## starts with it), or -1 when `now` does not carry on from `before` (a load).
## Each place is [lane, lot spot, berth or slot].
func handover(before: Array, now: Array) -> int:
	var lane_before: LandsideVehicle.Lane = before[0]
	var lane_now: LandsideVehicle.Lane = now[0]
	var same_lot: bool = before[1] == now[1]
	var off := -1
	if before == now:
		off = 0
	elif lane_before == LandsideVehicle.Lane.ROAD_IN and lane_now == LandsideVehicle.Lane.BERTH:
		off = 0
	elif lane_before == LandsideVehicle.Lane.ROAD_IN and lane_now == LandsideVehicle.Lane.ACCESS:
		off = definition.lots[now[1]].branch_mm
	elif lane_before == LandsideVehicle.Lane.ACCESS and lane_now == LandsideVehicle.Lane.SLOT:
		off = 0 if same_lot else -1
	elif lane_before == LandsideVehicle.Lane.BERTH and lane_now == LandsideVehicle.Lane.ROAD_OUT:
		off = berth_end[before[2]]
	elif lane_before == LandsideVehicle.Lane.SLOT and lane_now == LandsideVehicle.Lane.LOT_EXIT:
		off = end_of(lane_before, before[1], before[2]) if same_lot else -1
	return off


## The walk of the passengers who get out of a car parked in slot `slot` of
## lot spot `spot`: from the slot, on an upper deck along the aisle and down
## every ramp to the aisle front, then the gate and the crossing.
func lot_walk(spot: int, slot: int) -> Array[Vector3]:
	var lot := definition.lots[spot]
	var at := lot.slots[slot]
	var walk := PackedVector3Array([at])
	var deck := deck_of(lot, at)
	if deck > 0:
		_append(walk, Vector3(lot.aisle_front.x, at.y, at.z))
		for k in range(deck - 1, -1, -1):
			_append_all(walk, lot.ramps[k])
		var out_door := lot.entrance.duplicate()
		out_door.reverse()
		_append_all(walk, out_door)
	_append(walk, lot.access[lot.access.size() - 1])
	_append_all(walk, lot.crossing)
	var out: Array[Vector3] = []
	out.append(walk[0])
	for i in range(1, walk.size()):
		var a := walk[i - 1]
		var b := walk[i]
		var parts := maxi(ceili(absf(b.y - a.y) / WALK_STEP_M), 1)
		for part in range(1, parts):
			out.append(a.lerp(b, float(part) / parts))
		out.append(b)
	return out


func _add_berth(index: int) -> void:
	var road := definition.road_in
	var b := definition.berth_mm(index)
	var at := definition.berth_position(index)
	var dir := LandsideDefinition.heading_at(road, b)
	var straight := dir * (BERTH_STRAIGHT_MM / 1000.0)
	var split := maxi(b - BERTH_APPROACH_MM, 0)
	var points := _prefix(road, split)
	_append(points, at - straight)
	_append(points, at)
	var stand := LandsideDefinition.length_mm(points)
	_append(points, at + straight)
	var join_mm := mini(b + BERTH_APPROACH_MM, out_mm)
	_append(points, LandsideDefinition.point_on(road, join_mm))
	var join := LandsideDefinition.length_mm(points)
	_append(points, definition.road_out[0])
	berth_path.append(points)
	berth_end.append(LandsideDefinition.length_mm(points))
	berth_stand.append(stand)
	berth_split.append(split)
	berth_join.append(join)
	berth_join_mm.append(join_mm)
	berth_slack.append(maxi((join - stand) - (join_mm - b), 0))


func _add_lot(lot: LandsideLotSpot) -> void:
	var paths: Array[PackedVector3Array] = []
	var ends: Array[int] = []
	var stands: Array[int] = []
	var backs: Array[int] = []
	for slot in lot.slots:
		var inside := _inside(lot, slot)
		var points := lot.access.duplicate()
		_append_all(points, inside)
		var stand := LandsideDefinition.length_mm(points)
		# Back the way it came; through the entrance in reverse, or out of the
		# entrance's own way out.
		var from := lot.entrance.size() if not lot.way_out.is_empty() else 0
		var way_out := inside.slice(from, inside.size() - 1)
		way_out.reverse()
		_append_all(points, way_out)
		_append_all(points, lot.way_out)
		_append(points, lot.exit[0])
		paths.append(points)
		ends.append(LandsideDefinition.length_mm(points))
		stands.append(stand)
		backs.append(stand + roundi(slot.distance_to(inside[inside.size() - 2]) * 1000.0))
	slot_path.append(paths)
	slot_end.append(ends)
	slot_stand.append(stands)
	slot_back.append(backs)
	var turn := lot.access.duplicate()
	_append(turn, lot.entrance[0] if not lot.entrance.is_empty() else lot.aisle_front)
	_append(turn, lot.exit[0])
	turn_path.append(turn)
	turn_end.append(LandsideDefinition.length_mm(turn))


## Inside the lot, from the gate to `slot`: through the entrance, then on the
## ground to the aisle front, or up the ramps of the decks below; along the
## aisle to the stall and into it.
static func _inside(lot: LandsideLotSpot, slot: Vector3) -> PackedVector3Array:
	var out := lot.entrance.duplicate()
	var deck := maxi(deck_of(lot, slot), 0)
	if deck == 0:
		_append(out, lot.aisle_front)
	for k in deck:
		var up := lot.ramps[k].duplicate()
		up.reverse()
		_append_all(out, up)
	_append(out, Vector3(lot.aisle_front.x, slot.y, slot.z))
	_append(out, slot)
	return out


## `points` up to `mm` along them, the last segment carried on past the end.
static func _prefix(points: PackedVector3Array, mm: int) -> PackedVector3Array:
	var out := PackedVector3Array([points[0]])
	var walked := 0
	for i in range(1, points.size()):
		var segment := roundi(points[i - 1].distance_to(points[i]) * 1000.0)
		if walked + segment >= mm:
			break
		walked += segment
		out.append(points[i])
	if mm > walked:
		out.append(LandsideDefinition.point_on(points, mm))
	return out


static func _append(points: PackedVector3Array, point: Vector3) -> void:
	if points.is_empty() or not points[points.size() - 1].is_equal_approx(point):
		points.append(point)


static func _append_all(points: PackedVector3Array, more: PackedVector3Array) -> void:
	for point in more:
		_append(points, point)
