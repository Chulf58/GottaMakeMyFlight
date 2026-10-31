class_name MessTestKit
extends RefCounted
## Support for the mess tests (MessSim): an open floored world like
## TestDecorEffect's, cafe visits at made-up seats to report uses with, guests
## held standing on a cell, and use counters set through a save round trip.

const SIZE := Vector2i(30, 20)
const BOARDING := 40000
const DOORS := 45000
const START_MOOD := 50


## A 30 x 20 floored grid with an exit and an entrance and nothing else, run
## to tick 10 so the staff are on duty. Its flight boards late, so one world
## lasts a whole test file.
static func open_world(seed := 1) -> PassengerTestWorld:
	var grid := PassengerTestWorld.floored(SIZE)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(2, 0), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(2, 19), 2)
	var world := PassengerTestWorld.make(
		grid, PassengerTestWorld.starts_with(BOARDING, DOORS), seed
	)
	world.sim.apron_waypoints = PackedVector3Array()
	world.run_to(10)
	return world


## A settled cafe visit at a seat keyed `seat_key` whose approach cell is
## `cell`.
static func cafe_visit(cell: Vector2i, seat_key := "900:0", venue := &"cafe") -> CafeVisit:
	var visit := CafeVisit.new()
	visit.venue = venue
	visit.seat_key = seat_key
	visit.seat = {"approach": cell}
	return visit


## Reports MessSim.CAFE_EVERY settled visits at one seat whose approach is
## `cell`: exactly one litter, on the floor or in a bin.
static func litter(world: PassengerTestWorld, cell: Vector2i, seat_key := "900:0") -> void:
	var visit := cafe_visit(cell, seat_key)
	for i in MessSim.CAFE_EVERY:
		world.sim.messes.cafe_used(visit)


## A calm cleared passenger standing on `cell` with START_MOOD, held there:
## with no standing spot it stays until boarding.
static func guest(world: PassengerTestWorld, cell: Vector2i) -> Passenger:
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.STANDING
	p.stage_tick = world.clock.tick
	p.at = cell
	p.clear_path()
	p.mood = START_MOOD
	return p


## Steps `world` over `p`'s next `beats` beats, its needs held at 0 so only
## what the test measures moves its mood.
static func run_beats(world: PassengerTestWorld, p: Passenger, beats: int) -> void:
	for i in beats:
		ToiletTestLayout.calm(p)
		var t := world.clock.tick + 1
		while posmod(t, PassengerSim.BEAT_TICKS) != posmod(p.id, PassengerSim.BEAT_TICKS):
			t += 1
		world.run_to(t)


## Sets the use counter of every source in `sources` to `count`, through the
## sim's own save and load.
static func set_uses(world: PassengerTestWorld, sources: Array, count: int) -> bool:
	var data := world.sim.messes.to_snapshot()
	for source: String in sources:
		data["counters"][source] = count
	return world.sim.messes.from_snapshot(data)


## Empties `world`'s MessSim through its own load: no messes, bin fill, use
## counters or diagnostics, ids from 1.
static func clear(world: PassengerTestWorld) -> bool:
	var empty := {
		"save_version": MessSim.SAVE_VERSION,
		"tick": world.sim.tick,
		"next_id": 1,
		"messes": [],
		"bins": {},
		"counters": {},
		"overflow": 0,
		"merged": 0,
		"caught": 0,
	}
	return world.sim.messes.from_snapshot(empty)


## Applies each edit in `edits` to `world`'s grid in reverse order, results
## ignored: the undo list a test built as it changed the shared grid (an undo
## of something the test removed itself is refused and changes nothing).
static func undo(world: PassengerTestWorld, edits: Array[BuildEdit]) -> void:
	for i in range(edits.size() - 1, -1, -1):
		world.grid.apply(edits[i])
	edits.clear()


## A save that went through JSON, as a file would.
static func through_json(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))


## The same state, in a form two runs can be compared by.
static func text_of(data: Dictionary) -> String:
	return JSON.stringify(data, "", true)
