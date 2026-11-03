class_name ShopMoveKit
extends RefCounted
## What the room-move tests of shop and activity visits share (decision
## move-rooms-technical-design-roommove-plan-of-existing-edits, parts 4 to 6):
## moving a piece by hand as a room move moves it, and a second world loaded
## from a saved first.


## Moves object `id` to `anchor` (a cell of the world's terminal frame, so the
## reference terminal's offset is added): removed and placed again under its
## id with its paid, as RoomMove plans it.
static func move_piece(world: PassengerTestWorld, id: int, anchor: Vector2i) -> void:
	var record := world.grid.get_object(id)
	var at := ReferenceTerminal.offset_on(world.grid)
	var place := BuildEdit.place_object(record["def"], anchor + at, record["facing"])
	place.object_id = id
	place.paid = int(record.get("paid", 0))
	for result in world.grid.apply_batch([BuildEdit.remove_object(id), place]):
		assert(result.ok, "move refused: %s" % result.reason_text())


## The JSON text of a save of `world`, as a game save writes it.
static func save_text(world: PassengerTestWorld) -> String:
	return (
		JSON
		. stringify(
			{
				"clock": world.clock.to_snapshot(),
				"flights": world.flights.to_snapshot(),
				"grid": world.grid.to_snapshot(),
				"passengers": world.sim.to_snapshot(),
				"wallet": world.sim.wallet.to_snapshot(),
			}
		)
	)


## A second world loaded from `data` (JSON.parse_string(save_text())), or null
## when any part is refused.
static func load_twin(data: Dictionary) -> PassengerTestWorld:
	var grid := BuildGrid.new()
	if not grid.from_snapshot(data["grid"]):
		return null
	var twin := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	var ok: bool = (
		twin.clock.from_snapshot(data["clock"])
		and twin.flights.from_snapshot(data["flights"])
		and twin.sim.from_snapshot(data["passengers"])
		and twin.sim.wallet.from_snapshot(data["wallet"])
	)
	if not ok:
		twin.free_all()
		return null
	return twin
