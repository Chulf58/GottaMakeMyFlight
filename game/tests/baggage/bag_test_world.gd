class_name BagTestWorld
extends RefCounted
## A clock, one flight, a floored grid and a BaggageSim wired together without
## a scene or passengers, for the baggage tests. Bags are checked in with
## sim.check_in(). Every bag_settled emission is logged in `settled`.
##
## The standard layout (line()): a check-in desk at (2, 8) facing 0, whose
## belt outlet points up into (3, 7); a belt from (3, 7) to (10, 7); a 3x3 bag
## room at (10, 6) holding the belt's end at (10, 7). A bag checked in on tick
## 0 enters (3, 7) on tick 1 half a cell from its centre and reaches the end's
## centre on tick 150 (10 ticks, then 7 cells of 20).

const FLIGHT := "GMF101"
const SIZE := Vector2i(16, 12)
const DESK := Vector2i(2, 8)
const ENTRY := Vector2i(3, 7)
const END := Vector2i(10, 7)
const ROOM := Rect2i(10, 6, 3, 3)
## A bag checked in on tick 0 rests on the standard line's end on this tick.
const ARRIVAL := 150

var clock: SimClock
var flights: FlightSim
var grid: BuildGrid
var sim: BaggageSim
## [bag id, passenger, flight, loaded, tick] per bag_settled emission.
var settled: Array = []


## A world whose flight closes its doors at `doors` (cutoff doors - 200).
static func make(suite: GdUnitTestSuite, doors := 4000) -> BagTestWorld:
	var world := BagTestWorld.new()
	world.clock = suite.auto_free(SimClock.new())
	world.clock.seed_rng(1)
	world.flights = suite.auto_free(FlightSim.new())
	world.flights.bind_clock(world.clock)
	world.flights.add_flight(FLIGHT, PassengerTestWorld.starts_with(doors - 100, doors))
	world.grid = PassengerTestWorld.floored(SIZE)
	world.sim = suite.auto_free(BaggageSim.new())
	world.sim.bind(world.clock, world.flights, world.grid)
	world.sim.bag_settled.connect(
		func(id: int, passenger: int, flight: String, loaded: bool) -> void:
			world.settled.append([id, passenger, flight, loaded, world.clock.tick])
	)
	return world


## The standard desk, belt line and bag room. Returns the desk id.
func line() -> int:
	room(ROOM)
	var desk_id := desk(DESK)
	lay(ENTRY, END)
	return desk_id


## Places a check-in desk and reshapes the belts round it, as BuildMode does.
func desk(anchor: Vector2i, facing := 0) -> int:
	var desk_id := PassengerTestWorld.place(grid, &"checkin_desk", anchor, facing)
	var cells: Array[Vector2i] = []
	for port in BuildCatalog.belt_ports(&"checkin_desk", anchor, facing):
		cells.append(port["cell"] + port["side"])
	grid.apply_batch(BeltShaper.reshape_edits(grid, cells))
	return desk_id


func room(area: Rect2i) -> int:
	var result := grid.apply(BuildEdit.place_room(area, &"bag_room"))
	assert(result.ok, "test bag room refused: %s" % result.reason_text())
	return grid.room_at(area.position)


## Lays and shapes a belt line the way the Belt tool does, with no wallet.
func lay(from: Vector2i, to: Vector2i) -> void:
	var plan := BeltShaper.plan_line(grid, from, to, 0)
	assert(plan.result.ok, "test belt refused: %s" % plan.result.reason_text())
	for result in grid.apply_batch(plan.edits):
		assert(result.ok, "test belt edit refused: %s" % result.reason_text())


## Takes the belt off `cell` and reshapes its neighbours, as BuildMode does.
func unlay(cell: Vector2i) -> void:
	assert(grid.apply(BuildEdit.remove_object(grid.object_at(cell))).ok)
	grid.apply_batch(BeltShaper.reshape_edits(grid, BeltShaper.around([cell])))


func step() -> void:
	clock.advance(SimClock.STEP)


func run_to(target: int) -> void:
	while clock.tick < target:
		clock.advance(SimClock.STEP)


func bag(id: int) -> Bag:
	return sim.get_bag(id)


## Every bag's state, cell, edge and progress, one line, for comparisons.
func signature() -> String:
	var parts := PackedStringArray()
	for b in sim.bags():
		parts.append(
			(
				"%d|%d|%d|%s|%s|%d|%d|%d|%d|%d"
				% [
					b.id,
					b.state,
					b.cause,
					b.cell,
					b.from_step,
					b.remain_mm,
					int(b.from_desk),
					b.wait_tick,
					b.rest_tick,
					b.outcome_tick
				]
			)
		)
	return "%d:%d:%s" % [sim.loaded_total, sim.missed_total, ";".join(parts)]


## "" or the first cell two bags on belts share (owned or under their body).
func overlap() -> String:
	var taken := {}
	for b in sim.bags():
		if not b.on_belt():
			continue
		for cell in [b.cell, b.physical_cell()]:
			if taken.get(cell, b.id) != b.id:
				return "bags %d and %d share %s on tick %d" % [taken[cell], b.id, cell, clock.tick]
			taken[cell] = b.id
	return ""
