class_name PassengerTestWorld
extends RefCounted
## A clock, one flight, a grid, a PassengerSim and its StaffSim wired together
## without a scene, for the passenger tests. Call free_all() when done.

const FLIGHT := "GMF101"

## When set (in a suite's before()), new worlds hand their nodes to the
## suite's auto_free, so gdUnit4 frees them with the test and sees no orphans.
static var tracker: GdUnitTestSuite

var clock: SimClock
var flights: FlightSim
var grid: BuildGrid
var sim: PassengerSim
var staff: StaffSim
## Before each tick, staff are seated at once at every desk and scanner without
## any (StaffTestKit.staff_all), so tests that are not about staffing find the
## stations open. Staff tests set it false and hire.
var auto_staff := true
var _tracked := false


## Start ticks for a flight that starts boarding at `boarding` and closes its
## doors at `doors`.
static func starts_with(boarding: int, doors: int) -> Array[int]:
	var starts: Array[int] = [0, 1, 2, 3, boarding - 1, boarding, doors]
	starts.append_array([doors + 60, doors + 180, doors + 480, doors + 680])
	return starts


static func make(on_grid: BuildGrid, starts: Array[int], seed := 1) -> PassengerTestWorld:
	var world := PassengerTestWorld.new()
	world.clock = SimClock.new()
	world.clock.seed_rng(seed)
	world.flights = FlightSim.new()
	world.flights.bind_clock(world.clock)
	world.flights.add_flight(FLIGHT, starts)
	world.grid = on_grid
	world.sim = PassengerSim.new()
	world.sim.wallet = Wallet.new()
	world.staff = StaffSim.new()
	world.sim.staff = world.staff
	# Connected before the sim binds, so it runs before the passenger tick.
	world.clock.ticked.connect(
		func(_tick: int) -> void:
			if world.auto_staff:
				StaffTestKit.staff_all(world.staff)
	)
	world.sim.bind(world.clock, world.flights, on_grid)
	if tracker != null:
		tracker.auto_free(world.clock)
		tracker.auto_free(world.flights)
		tracker.auto_free(world.sim)
		tracker.auto_free(world.staff)
		world._tracked = true
	return world


## The reference terminal on the default grid with the default flight timing.
static func reference_world(seed := 1) -> PassengerTestWorld:
	var on_grid := BuildGrid.new()
	ReferenceTerminal.build(on_grid)
	return make(on_grid, FlightSim.schedule_starts(0), seed)


## A grid of `size` with floor on every cell.
static func floored(size: Vector2i) -> BuildGrid:
	var on_grid := BuildGrid.new(size)
	for y in size.y:
		for x in size.x:
			on_grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	return on_grid


static func place(on_grid: BuildGrid, def_id: StringName, anchor: Vector2i, facing: int) -> int:
	var result := on_grid.apply(BuildEdit.place_object(def_id, anchor, facing))
	assert(result.ok, "test layout placement refused: %s" % result.reason_text())
	return result.object_id


func run_to(target: int) -> void:
	while clock.tick < target:
		clock.advance(SimClock.STEP)


func step() -> void:
	clock.advance(SimClock.STEP)


func passenger(id: int) -> Passenger:
	return sim.get_passenger(id)


## Everything that decides what happens next, one line per passenger.
func signature() -> String:
	var parts := PackedStringArray()
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		parts.append(
			(
				"%d|%d|%d|%s|%d|%d|%d|%d|%d|%d|%d|%d"
				% [
					id,
					p.stage,
					p.stuck,
					p.at,
					p.path_index,
					p.path.size(),
					p.seg_mm,
					p.apron_mm,
					int(p.late),
					p.mood,
					p.station,
					p.seat_object
				]
			)
		)
	return "%d:%d:%s" % [sim.made_count(), sim.missed_count(), ";".join(parts)]


## Frees the nodes unless a suite's auto_free already owns them.
func free_all() -> void:
	if _tracked:
		return
	sim.free()
	staff.free()
	flights.free()
	clock.free()
