class_name HoldLineKit
extends RefCounted
## Test support for the full-queue design (decision full-queue-design-a-
## derived-hold-line-behind-each-lane-gives): worlds whose station lines run
## on behind the lane (TerminalLayout.line_of()), and passengers placed
## straight into a queue or on their way to one.

## The desk hall's desk anchor, and its entrance.
const DESK_AT := Vector2i(4, 1)
const HALL_DOOR := Vector2i(4, 21)
## Ticks a held front's service is kept going.
const LONG := 100000


## A hall 10 x 22 with floor everywhere: one desk at (4, 1) facing 0, whose
## lane runs (4, 2) to (4, 7) and whose hold line runs straight on from
## (4, 8) to (4, 19), and an entrance on (4, 21). The desk id is meta "desk".
static func desk_hall(seed := 1) -> PassengerTestWorld:
	var grid := PassengerTestWorld.floored(Vector2i(10, 22))
	var desk := PassengerTestWorld.place(grid, &"checkin_desk", DESK_AT, 0)
	PassengerTestWorld.place(grid, &"entrance_door", HALL_DOOR, 2)
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000), seed)
	world.sim.set_meta(&"desk", desk)
	return world


## A new calm passenger standing on `cell` in `stage`, with no path and no
## bags unless `bags` says so; returns it.
static func passenger(
	world: PassengerTestWorld, cell: Vector2i, stage: Passenger.Stage, bags := 0
) -> Passenger:
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.boredom = 0
	p.shop_cooldown = LONG
	p.liquids = false
	p.alarm = false
	p.carry_on = bags
	p.apron = []
	p.apron_mm = 0
	p.stage = stage
	p.stage_tick = world.sim.tick
	p.at = cell
	p.clear_path()
	return p


## Puts a new passenger at the back of `station`'s queue, standing on its
## place in the line; a desk's first member is in service for LONG ticks.
static func member(world: PassengerTestWorld, station: int, bags := 0) -> Passenger:
	var sim := world.sim
	var desk := not sim.layout.passages.has(station)
	var q: Dictionary = sim._queue(station)
	var index := (q["lane"] as Array).size() + (q["holding"] as Array).size()
	var stage := Passenger.Stage.CHECKIN_QUEUE if desk else Passenger.Stage.SECURITY_QUEUE
	var p := passenger(world, sim.layout.line_of(station)[index], stage, bags)
	p.station = station
	if index < (sim.layout.lanes[station] as Array).size():
		(q["lane"] as Array).append(p.id)
	else:
		(q["holding"] as Array).append(p.id)
		p.stuck = Passenger.Stuck.QUEUE_FULL
	if desk and index == 0:
		q["serving"] = p.id
		p.stage = Passenger.Stage.CHECKIN
		p.service_end = sim.tick + LONG
	return p


## The cells of `ids` that stand still, and how many of them share a cell
## with another: [cells, shared].
static func standing_cells(world: PassengerTestWorld, ids: Array) -> Array:
	var cells := {}
	var shared := 0
	for id: int in ids:
		var p := world.passenger(id)
		if p.is_moving():
			continue
		if cells.has(p.at):
			shared += 1
		cells[p.at] = true
	return [cells.keys(), shared]


## Whether every member of `station`'s queue stands still on its own place.
static func settled(world: PassengerTestWorld, station: int) -> bool:
	var line: Array = world.sim.layout.line_of(station)
	var members := world.sim.queue_of(station) + world.sim.holding_of(station)
	for i in members.size():
		var p := world.passenger(members[i])
		if p.is_moving() or p.at != line[i]:
			return false
	return true


## Steps until `station`'s queue is settled or `limit` ticks pass; returns
## whether it settled.
static func run_until_settled(world: PassengerTestWorld, station: int, limit := 600) -> bool:
	for i in limit:
		if settled(world, station):
			return true
		world.step()
	return settled(world, station)
