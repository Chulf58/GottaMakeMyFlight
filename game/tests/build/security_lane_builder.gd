class_name SecurityLaneBuilder
extends RefCounted
## Test helper: places a security lane's arch and parts where
## SecurityLanes.geometry() puts them.

const PARTS: Array[StringName] = [
	SecurityLanes.TRAY_TABLE, SecurityLanes.XRAY_BELT, SecurityLanes.PICKUP_TABLE
]
## A one-cell object that is no lane part and has no interaction cell.
const BLOCKER := &"baggage_belt"


## Places the arch at `anchor` and `facing` and every part not in `skip` at
## its geometry cell for `mirror`; a part in `turned` is placed a quarter turn
## off. Returns def id -> object id, the arch under SecurityLanes.ARCH.
static func build(
	grid: BuildGrid,
	anchor: Vector2i,
	facing: int,
	mirror: int,
	skip: Array[StringName] = [],
	turned: Array[StringName] = []
) -> Dictionary:
	var lane := SecurityLanes.geometry(anchor, facing, mirror)
	var ids := {
		SecurityLanes.ARCH: PassengerTestWorld.place(grid, SecurityLanes.ARCH, anchor, facing)
	}
	for part in PARTS:
		if skip.has(part):
			continue
		var turn := posmod(facing + 1, 4) if turned.has(part) else facing
		ids[part] = PassengerTestWorld.place(grid, part, lane[part], turn)
	return ids


## Puts a plain one-cell object on `cell`.
static func block(grid: BuildGrid, cell: Vector2i) -> int:
	return PassengerTestWorld.place(grid, BLOCKER, cell, 0)


static func recognise(grid: BuildGrid) -> SecurityLanes:
	var lanes := SecurityLanes.new()
	lanes.rebuild(grid)
	return lanes
