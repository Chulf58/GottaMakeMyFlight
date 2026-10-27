class_name PlaytestState
extends RefCounted
## JSON-safe summaries of the sim for the playtest hook's snapshot() and log
## lines: no vectors or objects, only numbers, strings, arrays and dictionaries.

const ENTRANCE_DEF := &"entrance_door"
const EXIT_DEF := &"exit_door"


## The name of an enum value, or the number as a string when it is out of range.
static func enum_name(keys: Array, value: int) -> String:
	if value >= 0 and value < keys.size():
		return keys[value]
	return str(value)


static func cell(at: Vector2i) -> Array[int]:
	return [at.x, at.y]


static func point(at: Vector3) -> Array[float]:
	return [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]


## What an edit asks for: its kind and cell, plus the fields that kind uses. A
## room removal names its room id instead of a cell.
static func edit_data(edit: BuildEdit) -> Dictionary:
	var data := {"kind": enum_name(BuildEdit.Kind.keys(), edit.kind), "cell": cell(edit.cell)}
	match edit.kind:
		BuildEdit.Kind.PAINT_FLOOR:
			data["floor_type"] = edit.floor_type
			data["zone"] = edit.zone_id
		BuildEdit.Kind.PLACE_WALL:
			data["side"] = enum_name(BuildGrid.Side.keys(), edit.side)
			data["wall_kind"] = enum_name(BuildGrid.WallKind.keys(), edit.wall_kind)
		BuildEdit.Kind.REMOVE_WALL:
			data["side"] = enum_name(BuildGrid.Side.keys(), edit.side)
		BuildEdit.Kind.PLACE_OBJECT:
			data["def"] = String(edit.def_id)
			data["facing"] = edit.facing
		BuildEdit.Kind.REMOVE_OBJECT:
			data["object_id"] = edit.object_id
		BuildEdit.Kind.PLACE_ROOM:
			data["room_type"] = String(edit.room_type)
			data["rect"] = [edit.cell.x, edit.cell.y, edit.room_size.x, edit.room_size.y]
		BuildEdit.Kind.REMOVE_ROOM:
			data.erase("cell")
			data["room_id"] = edit.room_id
	return data


## Floor cells, walls by kind (each edge counted once), objects by type, the
## entrances and exits with their ids and anchor cells, and the rooms with
## their type, rectangle and RoomRules status.
static func grid_summary(grid: BuildGrid) -> Dictionary:
	var floors := 0
	var walls := {}
	for y in grid.size.y:
		for x in grid.size.x:
			var at := Vector2i(x, y)
			if grid.floor_at(at) != BuildGrid.FLOOR_NONE:
				floors += 1
			var sides: Array[int] = [BuildGrid.Side.NORTH, BuildGrid.Side.WEST]
			if y == grid.size.y - 1:
				sides.append(BuildGrid.Side.SOUTH)
			if x == grid.size.x - 1:
				sides.append(BuildGrid.Side.EAST)
			for side in sides:
				var kind := grid.wall_kind(at, side)
				if kind != BuildGrid.WallKind.NONE:
					var name := enum_name(BuildGrid.WallKind.keys(), kind)
					walls[name] = walls.get(name, 0) + 1
	var objects := {}
	var entrances: Array[Dictionary] = []
	var exits: Array[Dictionary] = []
	for object_id in grid.object_ids():
		var record := grid.get_object(object_id)
		var def := String(record["def"])
		objects[def] = objects.get(def, 0) + 1
		var door := {"id": object_id, "cell": cell(record["anchor"]), "facing": record["facing"]}
		if record["def"] == ENTRANCE_DEF:
			entrances.append(door)
		elif record["def"] == EXIT_DEF:
			exits.append(door)
	return {
		"size": cell(grid.size),
		"origin": point(grid.origin),
		"floor_cells": floors,
		"walls": walls,
		"objects": objects,
		"entrances": entrances,
		"exits": exits,
		"rooms": _rooms(grid),
	}


static func _rooms(grid: BuildGrid) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for room_id in grid.room_ids():
		var room := grid.get_room(room_id)
		var area: Rect2i = room["rect"]
		var status := RoomRules.status(grid, room_id)
		var entry := {
			"id": room_id,
			"type": String(room["type"]),
			"rect": [area.position.x, area.position.y, area.size.x, area.size.y],
			"ready": status.ok,
			"notes": Array(status.notes),
		}
		out.append(entry)
	return out


## Passenger counts: total listed (settled passengers are retired shortly after
## their outcome), by stage name (stages with none left out), made and missed
## (durable totals), still active and still to spawn.
static func passenger_summary(sim: PassengerSim) -> Dictionary:
	var by_stage := {}
	var ids := sim.passenger_ids()
	for id in ids:
		var name := enum_name(Passenger.Stage.keys(), sim.get_passenger(id).stage)
		by_stage[name] = by_stage.get(name, 0) + 1
	return {
		"total": ids.size(),
		"by_stage": by_stage,
		"made": sim.made_count(),
		"missed": sim.missed_count(),
		"active": sim.active_count(),
		"pending_spawns": sim.pending_spawns(),
	}


## Every flight with its state name.
static func flights_summary(flights: FlightSim) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in flights.flight_ids():
		out.append({"id": id, "state": enum_name(FlightSim.State.keys(), flights.state_of(id))})
	return out
