class_name SecurityTestWorld
extends RefCounted
## Test support for security service: one basic scanner or one security lane
## on the same cells, passengers sent straight to security with chosen
## carry-on, and the tick each was admitted and cleared.
##
## The grid is 12 x 16 with floor everywhere: an entrance at (5, 15), an exit
## door at (5, 0), and either a lane rooted at an arch on (5, 6) facing 0
## (unpack (5, 7), pickup (5, 5), exit (5, 4), berth (4, 5)) or a basic
## scanner anchored on (5, 5) facing 0 (passage (5, 7) to (5, 4)). Both queue
## from (5, 7) down to (5, 12) and clear their passengers on (5, 4). The
## lane's arch is staffed by StaffTestKit.staff_all() like any scanner: its
## member is on duty on the lane's primary officer spot (7, 6).

const ARCH_AT := Vector2i(5, 6)
const SCANNER_AT := Vector2i(5, 5)
const START := Vector2i(5, 15)
## Ticks between two passengers sent to security, so they join in id order.
const SPACING := 12

var world: PassengerTestWorld
var station := 0
var lane := false
## Passenger id -> tick it was admitted (entered Stage.SECURITY), the first time.
var admitted := {}
## Passenger id -> tick it was cleared (left security for the gate).
var cleared := {}
## Passenger ids in the order they joined the security queue.
var joined: Array[int] = []


## `use_lane` true builds the lane, false the basic scanner.
static func make(use_lane: bool, seed := 7) -> SecurityTestWorld:
	var out := SecurityTestWorld.new()
	out.lane = use_lane
	var grid := build_grid(use_lane)
	out.world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(3000, 6000), seed)
	out.station = out.world.sim.layout.scanners[0]
	out.world.sim.stage_changed.connect(out._on_stage)
	return out


static func build_grid(use_lane: bool) -> BuildGrid:
	var grid := PassengerTestWorld.floored(Vector2i(12, 16))
	PassengerTestWorld.place(grid, &"entrance_door", START, 2)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(5, 0), 0)
	if use_lane:
		SecurityLaneBuilder.build(grid, ARCH_AT, 0, SecurityLanes.RIGHT)
	else:
		PassengerTestWorld.place(grid, &"security_scanner", SCANNER_AT, 0)
	return grid


## Spawns a passenger at the entrance, already checked in and walking to
## security, with these traits; returns its id.
func send(bags: int, liquids := false, alarm := false) -> int:
	var id := world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := world.passenger(id)
	p.carry_on = bags
	p.liquids = liquids
	p.alarm = alarm
	p.hunger = 0
	p.apron = []
	p.apron_mm = 0
	p.stage = Passenger.Stage.TO_SECURITY
	p.clear_path()
	return id


## Sends one passenger per trait entry [bags, liquids, alarm], SPACING ticks
## apart; returns their ids.
func send_all(traits: Array) -> Array[int]:
	var ids: Array[int] = []
	for entry: Array in traits:
		ids.append(send(entry[0], entry[1], entry[2]))
		world.run_to(world.clock.tick + SPACING)
	return ids


## Steps until every id is cleared or `limit` ticks pass; returns whether all
## were cleared.
func run_until_cleared(ids: Array[int], limit := 3000) -> bool:
	var stop := world.clock.tick + limit
	while world.clock.tick < stop:
		if ids.all(func(id: int) -> bool: return cleared.has(id)):
			return true
		world.step()
	return ids.all(func(id: int) -> bool: return cleared.has(id))


## A version 8 passenger save written as version 7 wrote it: no security
## key, no phase fields, and a basic scanner's passenger in service as the
## scanner's "serving" with a service end of the save tick plus its remaining
## work. Neither the toilet nor the kiosk part existed yet: no "toilet" or
## "shop" block, and no toilet, boredom or kiosk cooldown field on a record.
## Only a basic scanner in SCAN can be written this way.
static func as_v7(data: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	out["save_version"] = 7
	var tick := str(out["tick"]).to_int()
	var by_id := {}
	for record: Dictionary in out["passengers"]:
		by_id[int(record["id"])] = record
	for entry: Dictionary in out["security"]:
		var id := int(entry["admitted"][0])
		var record: Dictionary = by_id[id]
		assert(
			(
				entry["admitted"].size() == 1
				and int(record["security_phase"]) == SecurityRuntime.Phase.SCAN
			)
		)
		record["service_end"] = tick + int(record["security_work"])
		for queue: Dictionary in out["queues"]:
			if int(queue["station"]) == int(entry["station"]):
				queue["serving"] = id
	out.erase("security")
	out.erase("toilet")
	out.erase("shop")
	for record: Dictionary in out["passengers"]:
		for field in [
			"security_phase",
			"security_work",
			"incident_resolved",
			"toilet_need",
			"toilet_cooldown",
			"boredom",
			"shop_cooldown"
		]:
			record.erase(field)
	return out


func runtime_record() -> Dictionary:
	return world.sim.security.record_of(station)


## Everything security decides on, per passenger and per station.
func signature() -> String:
	var parts := PackedStringArray([world.signature()])
	for id in world.sim.passenger_ids():
		var p := world.passenger(id)
		parts.append(
			(
				"%d:%d:%d:%d:%d"
				% [id, p.security_phase, p.security_work, int(p.incident_resolved), p.station]
			)
		)
	parts.append(str(world.sim.security.to_list()))
	parts.append(str(world.sim.queue_of(station)) + str(world.sim.holding_of(station)))
	return "|".join(parts)


func _on_stage(id: int, stage: Passenger.Stage) -> void:
	if stage == Passenger.Stage.SECURITY_QUEUE and not joined.has(id):
		joined.append(id)
	elif stage == Passenger.Stage.SECURITY and not admitted.has(id):
		admitted[id] = world.sim.tick
	elif stage == Passenger.Stage.TO_GATE and not cleared.has(id):
		cleared[id] = world.sim.tick
