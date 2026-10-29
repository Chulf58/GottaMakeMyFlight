class_name TestLandsideEmptyAndCapped
extends GdUnitTestSuite
## Two edges of parking (Sol review of 9050e9b). A car meaning to park whose
## passengers all missed their flight before it reached the lot's turn
## drops its plan: it never turns in, reserves no slot and pays nothing, so
## the next live car gets the slot. And the parking fee follows the shops'
## income pattern (CafeSim/ShopSim._settle): when the wallet refuses the
## credit (at Wallet.MAX_BALANCE) an error says so and nothing is settled,
## so the car parks and its passengers get out, but no `parked` event fires
## without its PARKING transaction.

## The flight closes its doors at 25, before a car on the road from tick 1
## reaches the lot's turn (30 ticks in).
const BOARDING := 10
const DOORS := 25
const BOOKED := 12

var _land: LandsideTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _land != null:
		_land.free_all()
	_land = null


func _park_cars(sim: LandsideSim) -> Array[int]:
	var ids: Array[int] = []
	for id in sim.vehicle_ids():
		if sim.get_vehicle(id).intent == LandsideVehicle.Intent.PARK:
			ids.append(id)
	return ids


func test_a_car_emptied_at_doors_close_never_turns_into_the_lot() -> void:
	_land = LandsideTestWorld.make(null, PassengerTestWorld.starts_with(BOARDING, DOORS), 2)
	var landside := _land.landside
	assert_bool(landside.build_lot(0)).is_true()
	var parked := []
	landside.parked.connect(func(id: int, _lot: int) -> void: parked.append(id))
	var fees := []
	_land.sim.wallet.transaction.connect(
		func(amount: int, category: int, _claimed: Dictionary, _tick: int) -> void:
			if category == Wallet.Category.PARKING:
				fees.append(amount)
	)
	_land.schedule(BOOKED)
	_land.run_to(DOORS - 1)
	var emptied := _park_cars(landside)
	print("cars meaning to park before the doors close: %s" % [emptied])
	assert_int(emptied.size()).is_greater(0)
	for id in emptied:
		var v := landside.get_vehicle(id)
		assert_int(v.lane).is_equal(LandsideVehicle.Lane.ROAD_IN)
		assert_int(v.pos_mm).is_less(LandsideTestWorld.STARTER.lots[0].branch_mm)
	_land.step()
	assert_int(_land.sim.arrivals.missed_total).is_equal(BOOKED)
	# Play on until every emptied car is past the lot's turn.
	var turned := {}
	var past := false
	while _land.sim.tick < DOORS + 800 and not past:
		_land.step()
		past = true
		for id in emptied:
			var v := landside.get_vehicle(id)
			if v != null and v.lane in [LandsideVehicle.Lane.ACCESS, LandsideVehicle.Lane.SLOT]:
				turned[id] = true
			past = past and (v == null or v.lane != LandsideVehicle.Lane.ROAD_IN)
	assert_bool(past).is_true()
	assert_int(landside.free_slots(0)).is_equal(LandsideTestWorld.STARTER.lots[0].slots.size())
	# A live car that means to park follows; the road is stepped on its own,
	# holding its passenger aboard, since the world has no booking for it.
	var live: Array[int] = [999]
	var follower := landside.add_vehicle(
		LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK, live
	)
	var rng := RandomNumberGenerator.new()
	var t := _land.sim.tick
	while landside.get_vehicle(follower).stage != LandsideVehicle.Stage.PARKED and t < DOORS + 2000:
		t += 1
		landside.step(t, false, rng)
	var after := landside.get_vehicle(follower)
	print(
		(
			"emptied cars that turned in %s; follower lane %d slot %d; parked %s fees %s"
			% [turned.keys(), after.lane, after.stop, parked, fees]
		)
	)
	assert_dict(turned).is_empty()
	assert_array(parked).is_equal([follower])
	assert_array(fees).is_equal([LandsideSim.SURFACE_LOT_FEE])
	assert_int(after.stage).is_equal(LandsideVehicle.Stage.PARKED)
	assert_int(after.stop).is_equal(0)
	assert_int(landside.free_slots(0)).is_equal(LandsideTestWorld.STARTER.lots[0].slots.size() - 1)


## A save can hold an empty car that still means to park (nothing in the
## snapshot forbids it); loaded, it still never turns into the lot.
func test_an_empty_parking_car_loaded_from_a_save_never_turns_into_the_lot() -> void:
	var source: LandsideSim = auto_free(LandsideSim.new())
	assert_bool(source.use_definition(LandsideTestWorld.STARTER)).is_true()
	assert_bool(source.build_lot(0)).is_true()
	var aboard: Array[int] = [1]
	source.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK, aboard)
	var rng := RandomNumberGenerator.new()
	for t in range(1, 11):
		source.step(t, true, rng)
	var data: Dictionary = JSON.parse_string(
		JSON.stringify(source.to_snapshot(ArrivalBookings.new(), 10))
	)
	data["vehicles"][0]["bookings"] = []
	var loaded: LandsideSim = auto_free(LandsideSim.new())
	assert_bool(loaded.use_definition(LandsideTestWorld.STARTER)).is_true()
	loaded.wallet = Wallet.new()
	assert_bool(loaded.from_snapshot(data, ArrivalBookings.new())).is_true()
	var v := loaded.get_vehicle(1)
	assert_int(v.intent).is_equal(LandsideVehicle.Intent.PARK)
	assert_int(v.lane).is_equal(LandsideVehicle.Lane.ROAD_IN)
	assert_int(v.pos_mm).is_less(LandsideTestWorld.STARTER.lots[0].branch_mm)
	var lanes := {}
	var least_free := LandsideTestWorld.STARTER.lots[0].slots.size()
	for t in range(11, 800):
		loaded.step(t, true, rng)
		var now := loaded.get_vehicle(1)
		if now != null:
			lanes[now.lane] = true
		least_free = mini(least_free, loaded.free_slots(0))
	print("lanes used %s, fewest free slots %d" % [lanes.keys(), least_free])
	assert_bool(lanes.has(LandsideVehicle.Lane.ACCESS)).is_false()
	assert_bool(lanes.has(LandsideVehicle.Lane.SLOT)).is_false()
	assert_int(least_free).is_equal(LandsideTestWorld.STARTER.lots[0].slots.size())
	assert_int(loaded.wallet.balance).is_equal(0)


## One car parks into `wallet`; returns [parked events, PARKING credits,
## the car's stage, whether its passenger got out].
func _park_one(wallet: Wallet) -> Array:
	var sim: LandsideSim = auto_free(LandsideSim.new())
	assert_bool(sim.use_definition(LandsideTestWorld.STARTER)).is_true()
	assert_bool(sim.build_lot(0)).is_true()
	sim.wallet = wallet
	var parked := []
	sim.parked.connect(func(id: int, _lot: int) -> void: parked.append(id))
	var credits := []
	wallet.transaction.connect(
		func(amount: int, category: int, _claimed: Dictionary, _tick: int) -> void:
			if category == Wallet.Category.PARKING:
				credits.append(amount)
	)
	var aboard: Array[int] = [1]
	var id := sim.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK, aboard)
	var rng := RandomNumberGenerator.new()
	var got_out := false
	for t in range(1, 400):
		got_out = got_out or not sim.step(t, true, rng).is_empty()
	return [parked, credits, sim.get_vehicle(id).stage, got_out]


func test_at_the_wallet_cap_a_parked_car_fires_no_event_without_its_credit() -> void:
	var fee := LandsideSim.SURFACE_LOT_FEE
	var room := _park_one(Wallet.new(Wallet.MAX_BALANCE - fee))
	var full_wallet := Wallet.new(Wallet.MAX_BALANCE - fee + 1)
	var full := _park_one(full_wallet)
	print("room for the fee: %s; one short of room: %s" % [room, full])
	assert_int((room[0] as Array).size()).is_equal(1)
	assert_array(room[1]).is_equal([fee])
	assert_int(room[2]).is_equal(LandsideVehicle.Stage.PARKED)
	assert_bool(room[3]).is_true()
	# Refused: the car parks and its passenger gets out, but nothing is
	# settled: no credit, no parked event, the balance as it was.
	assert_array(full[1]).is_empty()
	assert_array(full[0]).is_equal(full[1] as Array)
	assert_int(full[2]).is_equal(LandsideVehicle.Stage.PARKED)
	assert_bool(full[3]).is_true()
	assert_int(full_wallet.balance).is_equal(Wallet.MAX_BALANCE - fee + 1)
