class_name TestMoneySnapshot
extends GdUnitTestSuite
## Exchange and ATM visits (F4-5b) in the passenger save, as other store visits
## are (ShopSnapshot): a save taken as a spare-time visit sets off and on the
## first tick it browses loads with the visit at its room's slot and plays on
## tick for tick, the fee and the unchanged boredom included, like the game it
## came from.

const MONEY_TYPES: Array[StringName] = [&"exchange", &"atm"]
const REPLAY_TICKS := 300
const START_BOREDOM := 40

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


## Starts a spare-time `type` visit, saving as it sets off and on the first
## tick it browses, then replays each save against the trace.
func _round_trip(type: StringName) -> void:
	var grid := BuildGrid.new()
	var ids := MoneyTestLayout.build(grid, type)
	_a = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 4242)
	_a.run_to(10)
	var p := ShopTestLayout.airside_guest(_a, START_BOREDOM, Vector2i(19, 5))
	p.set_path(_a.grid.find_path(p.at, Vector2i(21, 5)))
	var paid := [0]
	_a.sim.shops.paid.connect(func(_id: int, _room: int, _amount: int) -> void: paid[0] += 1)
	assert_int(NeedsPolicy.arbitrate(_a.sim, p)).is_equal(NeedsPolicy.Need.SHOP_BROWSE)
	var saves := {"SHOP_WALK": _save(_a)}
	var trace := {_a.clock.tick: _signature(_a)}
	var until := _a.clock.tick + 2000
	while _a.sim.shops.visit_of(p.id) != null and _a.clock.tick < until:
		_a.step()
		if p.stage == Passenger.Stage.SHOP_BROWSE and p.stage_tick == _a.clock.tick:
			saves["SHOP_BROWSE"] = _save(_a)
		trace[_a.clock.tick] = _signature(_a)
	var end := _a.clock.tick + REPLAY_TICKS
	while _a.clock.tick < end:
		_a.step()
		trace[_a.clock.tick] = _signature(_a)
	print("%s: saved in %s, %d paid, boredom %d" % [type, saves.keys(), paid[0], p.boredom])
	assert_int(paid[0]).override_failure_message(str(type)).is_equal(1)
	assert_int(p.boredom).is_greater_equal(START_BOREDOM)
	for stage in ["SHOP_WALK", "SHOP_BROWSE"]:
		assert_bool(saves.has(stage)).override_failure_message("%s %s" % [type, stage]).is_true()
		_b = _load(saves[stage])
		var start := _b.clock.tick
		assert_str(_signature(_b)).is_equal(trace[start])
		assert_int(_b.sim.shops.visit_ids().size()).is_equal(1)
		assert_int(_b.sim.shops.visit_of(p.id).room).is_equal(ids["air_room"])
		var first_bad := -1
		while _b.clock.tick < start + REPLAY_TICKS and first_bad < 0:
			_b.step()
			if _signature(_b) != trace[_b.clock.tick]:
				first_bad = _b.clock.tick
		print("%s %s saved at %d: first differing tick %d" % [type, stage, start, first_bad])
		assert_int(first_bad).override_failure_message("%s %s" % [type, stage]).is_equal(-1)
		_b.free_all()
		_b = null
	_free()


func test_an_exchange_visit_saves_and_plays_on_alike() -> void:
	_round_trip(&"exchange")


func test_an_atm_visit_saves_and_plays_on_alike() -> void:
	_round_trip(&"atm")
