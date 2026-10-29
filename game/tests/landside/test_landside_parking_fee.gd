class_name TestLandsideParkingFee
extends GdUnitTestSuite
## A car that parks pays the car park's fee once, when it parks (decisions
## landside-parking-houses-earn-a-parking-fee-per-car-paid-when and
## landside-parking-stay-a-parked-car-stays-1-3-game-days-while): one
## Wallet transaction under PARKING per parked car, counted in the
## DayLedger's operating result. A save taken while cars are parked and
## others are on their way to the lot loads without crediting anything, and
## the loaded world credits exactly the cars the unsaved one parks after.

const BOOKED := 40
const SEED := 21

var _a: LandsideTestWorld
var _b: LandsideTestWorld
var _credits := {}


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
	_credits.clear()


func _world() -> LandsideTestWorld:
	var world := LandsideTestWorld.make(null, [], SEED)
	assert_bool(world.landside.build_lot(0)).is_true()
	_watch(world)
	return world


## Counts the world's PARKING credits, each as [tick, amount].
func _watch(world: LandsideTestWorld) -> void:
	_credits[world] = []
	world.sim.wallet.transaction.connect(
		func(amount: int, category: int, _claimed: Dictionary, _tick: int) -> void:
			if category == Wallet.Category.PARKING:
				(_credits[world] as Array).append([world.sim.tick, amount])
	)


func _parked_count(world: LandsideTestWorld) -> int:
	var count := 0
	for id in world.landside.vehicle_ids():
		count += int(world.landside.get_vehicle(id).stage == LandsideVehicle.Stage.PARKED)
	return count


func _save(world: LandsideTestWorld) -> String:
	return (
		JSON
		. stringify(
			{
				"clock": world.world.clock.to_snapshot(),
				"flights": world.world.flights.to_snapshot(),
				"passengers": world.sim.to_snapshot(),
				"landside": world.landside.to_snapshot(world.sim.arrivals, world.sim.tick),
				"wallet": world.sim.wallet.to_snapshot(),
			}
		)
	)


func _load(text: String) -> LandsideTestWorld:
	var data: Dictionary = JSON.parse_string(text)
	var world := LandsideTestWorld.make(null, [], 99)
	_watch(world)
	assert_bool(world.world.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(world.world.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(world.sim.from_snapshot(data["passengers"])).is_true()
	assert_bool(world.landside.from_snapshot(data["landside"], world.sim.arrivals)).is_true()
	assert_bool(world.sim.wallet.from_snapshot(data["wallet"])).is_true()
	return world


func test_one_parking_credit_per_parked_car_counted_in_the_day_ledger() -> void:
	_a = _world()
	var ledger: DayLedger = auto_free(DayLedger.new())
	_a.sim.wallet.clock = _a.world.clock
	ledger.bind(_a.sim.wallet, _a.world.clock)
	var parked := []
	_a.landside.parked.connect(func(id: int, _lot: int) -> void: parked.append(id))
	_a.schedule(BOOKED)
	var doors := _a.world.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	while _a.released.size() < BOOKED and _a.sim.tick < doors:
		_a.step()
	var credits: Array = _credits[_a]
	var counted := ledger.amount(Wallet.Category.PARKING)
	print("parked %d credits %d ledger %d" % [parked.size(), credits.size(), counted])
	assert_int(parked.size()).is_greater(0)
	assert_int(credits.size()).is_equal(parked.size())
	var distinct := {}
	for id in parked:
		distinct[id] = true
	assert_int(distinct.size()).is_equal(parked.size())
	for credit in credits:
		assert_int(credit[1]).is_equal(LandsideSim.SURFACE_LOT_FEE)
	assert_int(ledger.amount(Wallet.Category.PARKING)).is_equal(
		parked.size() * LandsideSim.SURFACE_LOT_FEE
	)
	assert_int(ledger.operating_result()).is_equal(parked.size() * LandsideSim.SURFACE_LOT_FEE)


func test_a_load_credits_nothing_and_then_credits_what_the_unsaved_world_does() -> void:
	_a = _world()
	_a.schedule(BOOKED)
	# Save once some cars are parked and another is on its way to the lot.
	var on_access := false
	while not (on_access and _parked_count(_a) > 0) and _a.sim.tick < 9000:
		_a.step()
		on_access = false
		for id in _a.landside.vehicle_ids():
			on_access = on_access or _a.landside.get_vehicle(id).lane == LandsideVehicle.Lane.ACCESS
	var saved_at := _a.sim.tick
	var before_save: int = (_credits[_a] as Array).size()
	print("saved at %d with %d parked, %d credits" % [saved_at, _parked_count(_a), before_save])
	assert_bool(on_access).is_true()
	_b = _load(_save(_a))
	assert_array(_credits[_b]).is_empty()
	assert_int(_parked_count(_b)).is_equal(_parked_count(_a))
	assert_int(_b.sim.wallet.balance).is_equal(_a.sim.wallet.balance)
	# Every car has parked or dropped off once every passenger is out.
	var doors := _a.world.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	while _a.released.size() < BOOKED and _a.sim.tick < doors:
		_a.step()
		_b.step()
	var after_save: Array = (_credits[_a] as Array).slice(before_save)
	print("credits after the save: unsaved %s, loaded %s" % [after_save, _credits[_b]])
	assert_int(after_save.size()).is_greater(0)
	assert_array(_credits[_b]).is_equal(after_save)
	assert_int(_b.sim.wallet.balance).is_equal(_a.sim.wallet.balance)
