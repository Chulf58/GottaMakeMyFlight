class_name LandsideTestWorld
extends RefCounted
## A PassengerTestWorld inside the Toon terminal shell (the reference terminal
## on landside door B and gate C) with a LandsideSim on the starter road, for
## the landside tests. Records each booking's unload tick when the flight is
## scheduled and its release tick when its passenger gets out. Call free_all()
## when done (or set PassengerTestWorld.tracker in the suite's before()).

const SHELL := preload("res://build/toon_terminal_shell.tres")
const STARTER := preload("res://landside/starter_landside.tres")

var world: PassengerTestWorld
var sim: PassengerSim
var landside: LandsideSim
## Booking id -> the tick it meant to get out.
var unload := {}
## Booking id -> the tick its passenger got out.
var released := {}
## Booking id -> its passenger id.
var passenger_of := {}


## `definition` defaults to the starter road; `starts` to a flight whose
## first state is at tick 4000, so every party has the notice its drive needs;
## `grid` to the reference terminal in the shell.
static func make(
	definition: LandsideDefinition = null,
	starts: Array[int] = [],
	seed := 1,
	grid: BuildGrid = null
) -> LandsideTestWorld:
	if grid == null:
		grid = BuildGrid.new(SHELL.grid_size, SHELL.grid_origin)
		ReferenceTerminal.build(grid, SHELL)
	var out := LandsideTestWorld.new()
	out.world = PassengerTestWorld.make(
		grid, starts if not starts.is_empty() else FlightSim.schedule_starts(4000), seed
	)
	out.sim = out.world.sim
	out.sim.shell = SHELL
	out.landside = LandsideSim.new()
	out.landside.use_definition(definition if definition != null else STARTER)
	out.landside.wallet = out.sim.wallet
	out.sim.landside = out.landside
	if PassengerTestWorld.tracker != null:
		PassengerTestWorld.tracker.auto_free(out.landside)
	out.sim.arrivals.released.connect(out._on_released)
	return out


## A copy of the starter road whose curb has only `berths` berths.
static func with_berths(berths: int) -> LandsideDefinition:
	var definition: LandsideDefinition = STARTER.duplicate(true)
	definition.curb.berths = definition.curb.berths.slice(0, berths)
	definition.curb.get_out = definition.curb.get_out.slice(0, berths)
	return definition


## Schedules `count` passengers on the world's flight and notes their
## unload ticks.
func schedule(count: int) -> void:
	sim.schedule_flight(PassengerTestWorld.FLIGHT, count)
	for id in sim.arrivals.booking_ids():
		unload[id] = sim.arrivals.get_booking(id).unload_tick


func run_to(target: int) -> void:
	world.run_to(target)


func step() -> void:
	world.step()


## Release tick less unload tick, per released booking, in booking order.
func delays() -> Array[int]:
	var ids: Array = released.keys()
	ids.sort()
	var out: Array[int] = []
	for id in ids:
		out.append(int(released[id]) - int(unload[id]))
	return out


func free_all() -> void:
	if PassengerTestWorld.tracker == null:
		landside.free()
	world.free_all()


func _on_released(booking_id: int, passenger_id: int) -> void:
	released[booking_id] = sim.tick
	passenger_of[booking_id] = passenger_id
