class_name TestShopSnapshot
extends GdUnitTestSuite
## Kiosk visits in the passenger save (ShopSnapshot, PassengerSim save version
## 11): a save taken in each phase of a visit loads and plays on tick for tick
## like the game it came from; a shop state no play could reach is refused and
## changes nothing.

const REPLAY_TICKS := 400

var _a: PassengerTestWorld
var _b: PassengerTestWorld
## Tick -> _signature(_a) after that tick.
var _trace: Dictionary = {}


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
	_trace.clear()


## Passengers 1 to 3 are bored from spawn; nobody needs anything else. Every
## world that plays the flight needs it, as passengers still spawn after a save.
static func _needs_in(world: PassengerTestWorld) -> void:
	world.sim.passenger_spawned.connect(
		func(id: int) -> void:
			var p := world.passenger(id)
			ToiletTestLayout.calm(p)
			p.boredom = BoredomSim.MAX if id <= 3 else 0
			p.shop_cooldown = 0 if id <= 3 else 1000000
	)


func _kiosk_world(seed: int) -> PassengerTestWorld:
	var grid := BuildGrid.new()
	ShopTestLayout.build(grid, ["air", "land"])
	return PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), seed)


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


## The passenger signature plus boredom, the shop cooldown, the wallet and
## every shop visit.
func _signature(world: PassengerTestWorld) -> String:
	var shops := world.sim.shops
	var parts := PackedStringArray([world.signature(), str(world.sim.wallet.balance)])
	for id in world.sim.passenger_ids():
		var p := world.passenger(id)
		parts.append("%d:%d:%d:%d" % [id, p.boredom, p.shop_cooldown, p.stage_tick])
	for id in shops.visit_ids():
		var v := shops.visit_of(id)
		parts.append(
			(
				"v%d|%d|%s|%d|%d|%d"
				% [
					id,
					v.room,
					v.slot_key(),
					v.resume_stage,
					v.deadline,
					shops.slot_holder(v.slot_key())
				]
			)
		)
	return ";".join(parts)


## World A plays a flight to its doors closing; a save is taken on the first
## tick each visit phase starts, and A's signature is traced every tick.
func _play_and_save() -> Dictionary:
	_a = _kiosk_world(4242)
	_needs_in(_a)
	var saves := {}
	var sim := _a.sim
	assert_bool(sim.schedule_flight(PassengerTestWorld.FLIGHT, 12)).is_true()
	var doors := _a.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	while _a.clock.tick <= doors:
		_a.step()
		for id in sim.shops.visit_ids():
			var p := _a.passenger(id)
			var stage: String = Passenger.Stage.keys()[p.stage]
			if not saves.has(stage) and p.stage_tick == _a.clock.tick:
				saves[stage] = _save(_a)
		_trace[_a.clock.tick] = _signature(_a)
	return saves


func test_a_save_in_every_phase_of_a_visit_loads_and_plays_on_alike() -> void:
	var saves := _play_and_save()
	print("saved in %s" % [saves.keys()])
	for stage in ["SHOP_WALK", "SHOP_BROWSE"]:
		assert_bool(saves.has(stage)).override_failure_message("no save in %s" % stage).is_true()
	var doors := _a.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	for stage: String in saves:
		_b = _load(saves[stage])
		_needs_in(_b)
		var start := _b.clock.tick
		assert_str(_signature(_b)).is_equal(_trace[start])
		var first_bad := -1
		while _b.clock.tick <= mini(doors, start + REPLAY_TICKS) and first_bad < 0:
			_b.step()
			if _signature(_b) != _trace[_b.clock.tick]:
				first_bad = _b.clock.tick
		print("%s saved at %d: first differing tick %d" % [stage, start, first_bad])
		assert_int(first_bad).override_failure_message("%s differs" % stage).is_equal(-1)
		_b.free_all()
		_b = null


## A seated gate passenger made bored commits a visit and stands up first; a
## save in that STANDING_UP phase holds the visit with no walk yet. A and B
## then play side by side to the end of the replay.
func test_a_save_while_standing_up_from_the_gate_seat_plays_on_alike() -> void:
	_a = _kiosk_world(4242)
	var p := ShopTestLayout.airside_guest(_a, 0)
	p.shop_cooldown = 1000000
	var until := _a.clock.tick + 3000
	while p.stage != Passenger.Stage.SEATED and _a.clock.tick < until:
		_a.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SEATED)
	p.boredom = BoredomSim.MAX
	p.shop_cooldown = 0
	var visiting := func() -> bool: return _a.sim.shops.visit_of(p.id) != null
	while (
		not (p.stage == Passenger.Stage.STANDING_UP and visiting.call()) and _a.clock.tick < until
	):
		_a.step()
	assert_int(p.stage).is_equal(Passenger.Stage.STANDING_UP)
	var text := _save(_a)
	var start := _a.clock.tick
	var balance := _a.sim.wallet.balance
	_trace[start] = _signature(_a)
	for i in REPLAY_TICKS:
		_a.step()
		_trace[_a.clock.tick] = _signature(_a)
	_b = _load(text)
	assert_str(_signature(_b)).is_equal(_trace[start])
	assert_int(_b.passenger(p.id).stage).is_equal(Passenger.Stage.STANDING_UP)
	assert_object(_b.sim.shops.visit_of(p.id)).is_not_null()
	var first_bad := -1
	var browsed := false
	while _b.clock.tick < start + REPLAY_TICKS and first_bad < 0:
		_b.step()
		browsed = browsed or _b.passenger(p.id).stage == Passenger.Stage.SHOP_BROWSE
		if _signature(_b) != _trace[_b.clock.tick]:
			first_bad = _b.clock.tick
	print("saved standing up at %d: first differing tick %d" % [start, first_bad])
	assert_int(first_bad).is_equal(-1)
	assert_bool(browsed).is_true()
	assert_int(_b.sim.wallet.balance).is_greater(balance)


func test_a_shop_state_no_play_could_reach_is_refused_and_changes_nothing() -> void:
	var saves := _play_and_save()
	var good: Dictionary = JSON.parse_string(saves["SHOP_BROWSE"])["passengers"]
	var visit: Dictionary = good["shop"]["visits"][0]
	var guest := int(visit["passenger"])
	var cases: Array = []
	var copy := func() -> Dictionary: return good.duplicate(true)
	var record_of := func(data: Dictionary) -> Dictionary:
		for record: Dictionary in data["passengers"]:
			if int(record["id"]) == guest:
				return record
		return {}
	var d: Dictionary = copy.call()
	d["shop"]["visits"][0]["display"] = 9999
	cases.append(["no such browse slot", d])
	d = copy.call()
	d["shop"]["visits"][0]["slot"] = 7
	cases.append(["no such browse slot", d])
	d = copy.call()
	d["shop"]["visits"] = []
	cases.append(["at a shop with no visit", d])
	d = copy.call()
	record_of.call(d)["stage"] = Passenger.Stage.TO_GATE
	cases.append(["has a shop visit but is not at a shop", d])
	d = copy.call()
	var side := int(visit["resume_stage"])
	d["shop"]["visits"][0]["resume_stage"] = (
		Passenger.Stage.TO_GATE
		if side == Passenger.Stage.TO_SECURITY
		else Passenger.Stage.TO_SECURITY
	)
	cases.append(["other side of security", d])
	d = copy.call()
	var at: Array = record_of.call(d)["at"]
	record_of.call(d)["at"] = [at[0], int(at[1]) + 1]
	cases.append(["browsing but not on its slot", d])
	d = copy.call()
	record_of.call(d)["stage_tick"] = int(str(d["tick"])) - ShopSim.BROWSE_TICKS
	cases.append(["the browse does not run past the saved tick", d])
	d = copy.call()
	d["shop"]["visits"].append(d["shop"]["visits"][0].duplicate())
	cases.append(["malformed or repeated", d])
	d = copy.call()
	(
		d["toilet"]["visits"]
		. append(
			{
				"passenger": guest,
				"room": 1,
				"stall": 1,
				"resume_stage": visit["resume_stage"],
				"deadline": visit["deadline"],
			}
		)
	)
	# A second visit of another facility for the guest is refused too.
	cases.append(["toilet visit", d])
	d = copy.call()
	d.erase("shop")
	cases.append(["missing key 'shop'", d])
	d = copy.call()
	record_of.call(d).erase("shop_cooldown")
	cases.append(["malformed or repeated", d])
	_b = _load(saves["SHOP_WALK"])
	var before := _signature(_b)
	for case: Array in cases:
		var problem: String = PassengerSnapshot.load(case[1], _b.grid).get("error", "")
		print("%s -> %s" % [case[0], problem])
		assert_str(problem).is_not_empty()
		assert_str(problem).contains(case[0])
		assert_bool(_b.sim.from_snapshot(case[1])).is_false()
		assert_str(_signature(_b)).is_equal(before)
