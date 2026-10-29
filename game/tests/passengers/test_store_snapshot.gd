class_name TestStoreSnapshot
extends GdUnitTestSuite
## Visits to the pharmacy, duty free and fashion stores (F4-5) in the passenger
## save, as kiosk visits are (ShopSnapshot): a save taken while a store visit
## is walking and while it is browsing loads with the visit in its room and
## plays on tick for tick, payments included, like the game it came from.

const REPLAY_TICKS := 300

var _a: PassengerTestWorld
var _b: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	_free()


func _free() -> void:
	for world in [_a, _b]:
		if world != null:
			world.free_all()
	_a = null
	_b = null


## Passengers 1 to 3 are bored from spawn; nobody needs anything else.
static func _needs_in(world: PassengerTestWorld) -> void:
	world.sim.passenger_spawned.connect(
		func(id: int) -> void:
			var p := world.passenger(id)
			ToiletTestLayout.calm(p)
			p.boredom = BoredomSim.MAX if id <= 3 else 0
			p.shop_cooldown = 0 if id <= 3 else 1000000
	)


func _save(world: PassengerTestWorld) -> String:
	return (
		JSON
		. stringify(
			{
				"clock": world.clock.to_snapshot(),
				"flights": world.flights.to_snapshot(),
				"grid": world.grid.to_snapshot(),
				"passengers": world.sim.to_snapshot(),
			}
		)
	)


func _load(text: String) -> PassengerTestWorld:
	var data: Dictionary = JSON.parse_string(text)
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	assert_bool(world.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(world.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(world.sim.from_snapshot(data["passengers"])).is_true()
	_needs_in(world)
	return world


## The passenger signature plus boredom, the wallet and every shop visit.
func _signature(world: PassengerTestWorld) -> String:
	var shops := world.sim.shops
	var parts := PackedStringArray([world.signature(), str(world.sim.wallet.balance)])
	for id in world.sim.passenger_ids():
		var p := world.passenger(id)
		parts.append("%d:%d:%d" % [id, p.boredom, p.shop_cooldown])
	for id in shops.visit_ids():
		var v := shops.visit_of(id)
		parts.append("v%d|%d|%s|%d" % [id, v.room, v.slot_key(), v.deadline])
	return ";".join(parts)


## Plays a flight in a `type` store world, saving on the first tick a visit
## walks and the first it browses, then replays each save against the trace.
func _round_trip(type: StringName) -> void:
	var grid := BuildGrid.new()
	var ids := StoreTestLayout.build(grid, type, ["air", "land"])
	_a = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 4242)
	_needs_in(_a)
	assert_bool(_a.sim.schedule_flight(PassengerTestWorld.FLIGHT, 12)).is_true()
	var doors := _a.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	var saves := {}
	var trace := {}
	var paid := [0]
	_a.sim.shops.paid.connect(func(_id: int, _room: int, _amount: int) -> void: paid[0] += 1)
	while _a.clock.tick <= doors:
		_a.step()
		for id in _a.sim.shops.visit_ids():
			var p := _a.passenger(id)
			var stage: String = Passenger.Stage.keys()[p.stage]
			if not saves.has(stage) and p.stage_tick == _a.clock.tick:
				saves[stage] = _save(_a)
		trace[_a.clock.tick] = _signature(_a)
	print("%s: saved in %s, %d paid" % [type, saves.keys(), paid[0]])
	assert_int(paid[0]).override_failure_message(str(type)).is_greater(0)
	for stage in ["SHOP_WALK", "SHOP_BROWSE"]:
		assert_bool(saves.has(stage)).override_failure_message("%s %s" % [type, stage]).is_true()
		_b = _load(saves[stage])
		var start := _b.clock.tick
		assert_str(_signature(_b)).is_equal(trace[start])
		var rooms := [ids["air_room"], ids["land_room"]]
		for id in _b.sim.shops.visit_ids():
			assert_bool(rooms.has(_b.sim.shops.visit_of(id).room)).is_true()
		var first_bad := -1
		while _b.clock.tick <= mini(doors, start + REPLAY_TICKS) and first_bad < 0:
			_b.step()
			if _signature(_b) != trace[_b.clock.tick]:
				first_bad = _b.clock.tick
		print("%s %s saved at %d: first differing tick %d" % [type, stage, start, first_bad])
		assert_int(first_bad).override_failure_message("%s %s" % [type, stage]).is_equal(-1)
		_b.free_all()
		_b = null
	_free()


func test_a_pharmacy_visit_saves_and_plays_on_alike() -> void:
	_round_trip(&"pharmacy")


func test_a_duty_free_visit_saves_and_plays_on_alike() -> void:
	_round_trip(&"duty_free")


func test_a_fashion_visit_saves_and_plays_on_alike() -> void:
	_round_trip(&"fashion")
