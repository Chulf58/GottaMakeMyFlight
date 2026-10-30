class_name TestActivitySnapshot
extends GdUnitTestSuite
## An activity or rest visit in the passenger save (F4-7). The stay is longer
## than the 120-tick default browse, so a save taken well into it loads only if
## the load checks the browse against the room type's own dwell
## (ShopSnapshot), and it plays on tick for tick, the fee and the mood bonus
## included, like the game it came from.

const REPLAY_TICKS := 400
## How far into the stay the save is taken: past the default browse, inside
## every activity room's dwell.
const INTO_STAY := 130

var _a: PassengerTestWorld
var _b: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
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
	(
		assert_bool(world.sim.from_snapshot(data["passengers"]))
		. override_failure_message("load refused")
		. is_true()
	)
	return world


func _signature(world: PassengerTestWorld) -> String:
	var shops := world.sim.shops
	var parts := PackedStringArray([world.signature(), str(world.sim.wallet.balance)])
	for id in world.sim.passenger_ids():
		var p := world.passenger(id)
		parts.append("%d:%d:%d:%d" % [id, p.boredom, p.mood, p.shop_cooldown])
	for id in shops.visit_ids():
		var v := shops.visit_of(id)
		parts.append("v%d|%d|%s|%d" % [id, v.room, v.slot_key(), v.deadline])
	return ";".join(parts)


func test_a_save_well_into_a_long_stay_loads_and_plays_on_alike() -> void:
	for type in [&"lounge", &"shower", &"nap_pod"]:
		var grid := BuildGrid.new()
		var ids := ActivityTestLayout.build(grid, type)
		_a = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 4242)
		_a.run_to(10)
		var p := ShopTestLayout.airside_guest(_a, BoredomSim.MAX)
		p.mood = 50
		assert_int(NeedsPolicy.arbitrate(_a.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
		var until := _a.clock.tick + 2000
		while p.stage != Passenger.Stage.SHOP_BROWSE and _a.clock.tick < until:
			_a.step()
		_a.run_to(p.stage_tick + INTO_STAY)
		assert_int(p.stage).is_equal(Passenger.Stage.SHOP_BROWSE)
		var save := _save(_a)
		var trace := {_a.clock.tick: _signature(_a)}
		var end := _a.clock.tick + REPLAY_TICKS
		while _a.clock.tick < end:
			_a.step()
			trace[_a.clock.tick] = _signature(_a)
		var bonus := RoomTypes.get_type(type).mood_bonus
		_b = _load(save)
		var start := _b.clock.tick
		assert_str(_signature(_b)).is_equal(trace[start])
		assert_int(_b.sim.shops.visit_of(p.id).room).is_equal(ids["room"])
		var first_bad := -1
		var gained := -1
		var mood := _b.passenger(p.id).mood
		while _b.clock.tick < start + REPLAY_TICKS and first_bad < 0:
			_b.step()
			if gained < 0 and _b.sim.shops.visit_of(p.id) == null:
				gained = _b.passenger(p.id).mood - mood
			mood = _b.passenger(p.id).mood
			if _signature(_b) != trace[_b.clock.tick]:
				first_bad = _b.clock.tick
		print(
			(
				"%s saved at %d (browsing since %d): first differing tick %d, mood gained %d"
				% [type, start, p.stage_tick, first_bad, gained]
			)
		)
		assert_int(first_bad).override_failure_message(str(type)).is_equal(-1)
		# The loaded stay ends with the type's bonus, whatever else moved mood.
		assert_int(gained).override_failure_message(str(type)).is_equal(bonus)
		_a.free_all()
		_b.free_all()
		_a = null
		_b = null
