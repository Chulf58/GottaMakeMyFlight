class_name ToiletLayout
extends RefCounted
## The toilet stalls passengers can use, derived from the grid (decision
## toilet-design-queue-free-reservable-stalls-per-stall-daily-u, point 1):
## Rooms owns the room and whether it is ready; this layout owns the usable
## stalls; ToiletSim owns who holds each one. Rebuilt after every grid edit.
##
## A stall is a toilet_stall piece wholly inside a ready toilet room (the rule
## RoomRules counts pieces by) whose approach cell, its interaction cell, is
## walkable. It is 1 cell wide and 2 deep with its door at the front (decision
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
			if record["def"] != &"toilet_stall" or not _inside(grid, id, area):
				continue
			var approach := grid.interaction_cell(id)
			if not grid.is_walkable(approach):
				continue
			var front := TerminalLayout.front_of(record["facing"])
			var use_cell: Vector2i = record["anchor"]
			var turn_cell := use_cell + front
			var centre := (grid.cell_to_world(use_cell) + grid.cell_to_world(turn_cell)) / 2.0
			var out := Vector3(front.x, 0.0, front.y)
			(
				stalls
				. append(
					{
						"id": id,
						"room": room_id,
						"approach": approach,
						"turn_cell": turn_cell,
						"use_cell": use_cell,
						"front": front,
						"turn": centre + out * TURN_M,
						"use": centre + out * USE_M,
					}
				)
			)


## A stall entry by object id, or an empty dictionary when it is not usable.
func stall(stall_id: int) -> Dictionary:
	for entry in stalls:
		if entry["id"] == stall_id:
			return entry
	return {}


## Whether the whole footprint and interaction cell of an object lie in `area`.
static func _inside(grid: BuildGrid, id: int, area: Rect2i) -> bool:
	var record := grid.get_object(id)
	var def := BuildCatalog.get_def(record["def"])
	for cell in def.footprint(record["anchor"], record["facing"]):
		if not area.has_point(cell):
			return false
	return area.has_point(grid.interaction_cell(id))
