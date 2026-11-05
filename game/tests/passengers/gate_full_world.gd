class_name GateFullWorld
extends RefCounted
## Test support for a gate that fills up (decision gate-full-design-passengers-
## reserve-a-gate-seat-or-standing): SecurityTestWorld's basic scanner grid
## with the airside walled down to a corridor one cell wide, from the scanner
## exit (5, 4) to the exit door on (5, 0). Its cells (5, 1) to (5, 3) hold the
## only standing spots (SPOTS of them), and there are no seats, so the
## SPOTS + 1st passenger sent through security finds the gate full. Records
## the tick each passenger was first admitted.

## The standing spots the corridor holds; TestGateCapacityAdmission checks
## the count against the derived spots.
const SPOTS := 8
const SCANNER_EXIT := Vector2i(5, 4)
const BOARDING := 3000
const DOORS := 6000

var world: PassengerTestWorld
var station := 0
## Passenger id -> the tick it was first admitted to security.
var admitted := {}


static func make(seed := 7) -> GateFullWorld:
	var out := GateFullWorld.new()
	var grid := build_grid()
	out.world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(BOARDING, DOORS), seed)
	out.station = out.world.sim.layout.scanners[0]
	out.world.sim.stage_changed.connect(out._on_stage)
	return out


static func build_grid() -> BuildGrid:
	var grid := SecurityTestWorld.build_grid(false)
	for y in range(0, 5):
		for side in [BuildGrid.Side.WEST, BuildGrid.Side.EAST]:
			var wall := grid.apply(BuildEdit.place_wall(Vector2i(5, y), side))
			assert(wall.ok, "corridor wall refused: %s" % wall.reason_text())
	return grid


## Spawns a calm passenger at the entrance, checked in, with no bags, walking
## to security; returns its id.
func send() -> int:
	var id := world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := world.passenger(id)
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.apron = []
	p.apron_mm = 0
	p.stage = Passenger.Stage.TO_SECURITY
	p.clear_path()
	return id


## Sends `count` passengers SecurityTestWorld.SPACING ticks apart.
func send_many(count: int) -> Array[int]:
	var ids: Array[int] = []
	for i in count:
		ids.append(send())
		world.run_to(world.clock.tick + SecurityTestWorld.SPACING)
	return ids


## Steps until `done` holds, at most `limit` ticks; returns whether it did.
func run_until(done: Callable, limit := 3000) -> bool:
	for i in limit:
		if done.call():
			return true
		world.step()
	return done.call()


## The passenger at the front of the scanner's lane, or null.
func front() -> Passenger:
	var lane := world.sim.queue_of(station)
	return null if lane.is_empty() else world.passenger(lane[0])


func standing_count() -> int:
	var count := 0
	for id in world.sim.passenger_ids():
		count += int(world.passenger(id).stage == Passenger.Stage.STANDING)
	return count


func _on_stage(id: int, stage: Passenger.Stage) -> void:
	if stage == Passenger.Stage.SECURITY and not admitted.has(id):
		admitted[id] = world.sim.tick
