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
## Before each tick, staff are seated at once at every desk, scanner and shop
## counter without any (StaffTestKit.staff_all), so tests that are not about
## staffing find the stations open. Staff tests set it false and hire.
var auto_staff := true
## The roles auto_staff seats; every role when empty. A test of an unstaffed
## counter seats only the desk and scanner roles.
var auto_staff_roles: Array[StaffMember.Role] = []
var _tracked := false


## The tick the reference flight (FlightSim.schedule_starts(0)) opens boarding and
## the tick it closes its doors, which tests that run the default flight wait for.
static func boarding_tick() -> int:
	return FlightSim.schedule_starts(0)[FlightSim.State.BOARDING]


## The tick the reference flight's usual arrival window opens (ArrivalTypes): a
## test that schedules passengers at the start of that window runs to it first.
static func arrival_opens_tick() -> int:
	return (
		FlightSim.schedule_starts(0)[FlightSim.State.PUSHBACK]
		- ArrivalTypes.ARRIVAL_OPENS_BEFORE_DEPARTURE_TICKS
	)


static func doors_tick() -> int:
	return FlightSim.schedule_starts(0)[FlightSim.State.DOORS_CLOSED]


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
				StaffTestKit.staff_all(world.staff, world.auto_staff_roles)
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


## A PassengerViews whose need icon toggle reads an isolated settings path (never
## the player's user://hud_settings.cfg, where N may have turned the icons off), as
## every test view must be made. Set its clock and sim, then add_child() it.
static func views() -> PassengerViews:
	var made := PassengerViews.new()
	made.need_icons_toggle.settings_path = SaveTestKit.run_path("test_views_hud_settings")
	return made


## A grid of `size` with floor on every cell, walled in along the grid border
## (EnclosureKit.close_floor()), so all the floor is indoor. A door place()s
## on the border takes down the plain wall on its way out, as the build tools
## do (DoorPlacement.edits_for()).
static func floored(size: Vector2i) -> BuildGrid:
	var on_grid := BuildGrid.new(size)
	var edits: Array[BuildEdit] = []
	for y in size.y:
		for x in size.x:
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	on_grid.apply_batch(edits)
	EnclosureKit.close_floor(on_grid)
	return on_grid


## Places `def_id` through the grid; an entrance or exit first takes down a
## plain wall on its way out (DoorPlacement.edits_for()). Asserts it is
## accepted and returns the object id.
static func place(on_grid: BuildGrid, def_id: StringName, anchor: Vector2i, facing: int) -> int:
	var result := BuildResult.accepted()
	for edit in DoorPlacement.edits_for(on_grid, BuildEdit.place_object(def_id, anchor, facing)):
		result = on_grid.apply(edit)
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
