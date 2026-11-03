class_name ToiletLayout
extends RefCounted
## The toilet stalls passengers can use, derived from the grid (decision
## toilet-design-queue-free-reservable-stalls-per-stall-daily-u, point 1):
## Rooms owns the room and whether it is ready; this layout owns the usable
## stalls; ToiletSim owns who holds each one. Rebuilt after every grid edit.
##
## A stall is a toilet_stall piece wholly inside a ready toilet room (the rule
## RoomRules counts pieces by) whose approach cell, its interaction cell, is a
## passenger cell (BuildGrid.is_passenger_cell(): walkable and walled in).
## It is 1 cell wide and 2 deep with its door at the front (decision
## toilet-stall-kit-piece-1x2-footprint-side-partitions-out-to): the walker
## stops on the approach cell, steps in to Mount_Turn in the front cell, turns
## and sits back to Mount_Use, just inside the rear cell. The stall cells are
## not walkable, so these spots are world points the passenger is drawn at
## while its grid cell stays the approach cell.

## Mount_Turn and Mount_Use along the stall's front axis, in metres from the
## centre of its footprint (the .glb root).
const TURN_M := 0.35
const USE_M := -0.05

## One entry per usable stall, in room id order and then object id order:
## {"id": object id, "room": room id, "approach": Vector2i, "turn_cell":
## Vector2i (front footprint cell), "use_cell": Vector2i (rear footprint cell),
## "front": Vector2i (the way out of the door), "turn": Vector3, "use": Vector3}.
var stalls: Array[Dictionary] = []


func rebuild(grid: BuildGrid) -> void:
	stalls.clear()
	var rooms := grid.room_ids()
	rooms.sort()
	var ids := grid.object_ids()
	ids.sort()
	for room_id in rooms:
		var status := RoomRules.status(grid, room_id)
		if status.type_id != &"toilet" or not status.ok:
			continue
		var area: Rect2i = grid.get_room(room_id)["rect"]
		for id in ids:
			var record := grid.get_object(id)
			if record["def"] != &"toilet_stall" or not FacilitySlots.piece_inside(grid, id, area):
				continue
			var entry := entry_at(grid, id, room_id, Relocation.placement(grid, id))
			if grid.is_passenger_cell(entry["approach"]):
				stalls.append(entry)


## The stall entry of stall `id` in room `room_id` at placement `at`
## (Relocation.placement()), whether or not the grid holds it there: a stall
## that moved is still drawn and left from its old spot (Relocation).
static func entry_at(grid: BuildGrid, id: int, room_id: int, at: Dictionary) -> Dictionary:
	var def := BuildCatalog.get_def(at["def"])
	var front := TerminalLayout.front_of(at["facing"])
	var use_cell: Vector2i = at["anchor"]
	var turn_cell := use_cell + front
	var centre := (grid.cell_to_world(use_cell) + grid.cell_to_world(turn_cell)) / 2.0
	var out := Vector3(front.x, 0.0, front.y)
	return {
		"id": id,
		"room": room_id,
		"approach": def.interaction_cell(at["anchor"], at["facing"]),
		"turn_cell": turn_cell,
		"use_cell": use_cell,
		"front": front,
		"turn": centre + out * TURN_M,
		"use": centre + out * USE_M,
	}


## A stall entry by object id, or an empty dictionary when it is not usable.
func stall(stall_id: int) -> Dictionary:
	for entry in stalls:
		if entry["id"] == stall_id:
			return entry
	return {}
