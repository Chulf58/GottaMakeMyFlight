class_name TestShopWishes
extends GdUnitTestSuite
## Shopping wishes in relief planning and settle (decision shopping-wish-
## technical-design-id-hash-wish-admissible-wished-slot-then-fallback, points
## 2, 4 and 5): a bored passenger with a wish goes to the nearest admissible
## free slot of its wished kind, else settles for the nearest admissible shop
## that relieves boredom, pays FALLBACK_SHARE of the spend of the lower of the
## two base spends and loses FALLBACK_MOOD; a wished shop it cannot fit in
## never blocks a fallback it can. Each test pins the wish through
## ShopSim.wishes.

var _world: PassengerTestWorld
var _ids: Dictionary
## [passenger id, room id, amount] per paid signal.
var _paid: Array = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null
	_paid.clear()


## A world of WishTestLayout `types` in which every passenger wishes `wish`.
func _wish_world(types: Array, wish: StringName) -> PassengerTestWorld:
	if _world != null:
		_world.free_all()
	_paid.clear()
	var grid := BuildGrid.new()
	_ids = WishTestLayout.build(grid, types)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_wish(wish)
	_world.sim.shops.paid.connect(
		func(id: int, room: int, amount: int) -> void: _paid.append([id, room, amount])
	)
	# Staff come on duty on the first ticks.
	_world.run_to(10)
	return _world


func _wish(wish: StringName) -> void:
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return wish


func _room(i: int) -> int:
	return _ids["rooms"][i]


func _run_while_visiting(p: Passenger, limit := 3000) -> void:
	var until := _world.clock.tick + limit
	while _world.sim.shops.visit_of(p.id) != null and _world.clock.tick < until:
		_world.step()


func test_a_wisher_passes_a_nearer_shop_for_its_wished_kind_and_pays_in_full() -> void:
	_wish_world([&"kiosk", &"pharmacy"], &"pharmacy")
	var shops := _world.sim.shops
	var p := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
	p.mood = 70
	assert_str(shops.wish_of(p)).is_equal("pharmacy")
	assert_int(shops.visit_wish_state(p.id)).is_equal(WishTable.State.WANTED)
	var plan := shops.plan_visit(p)
	assert_int(plan["slot"]["room"]).is_equal(_room(1))
	assert_bool(plan["fallback"]).is_false()
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
	var visit := shops.visit_of(p.id)
	assert_int(visit.room).is_equal(_room(1))
	assert_bool(visit.fallback).is_false()
	assert_int(shops.visit_wish_state(p.id)).is_equal(WishTable.State.FULFILLED)
	var expected := ShopSim.spend(RoomTypes.get_type(&"pharmacy").base_spend, p.mood, true)
	_run_while_visiting(p)
	print("wished pharmacy: paid %s, mood %d, boredom %d" % [_paid, p.mood, p.boredom])
	assert_array(_paid).is_equal([[p.id, _room(1), expected]])
	assert_int(p.mood).is_equal(70)
	assert_int(p.boredom).is_equal(0)
	assert_int(shops.visit_wish_state(p.id)).is_equal(WishTable.State.NONE)
	# Control: with no wish the same passenger plans the nearer kiosk, as before.
	_wish(WishTable.NONE)
	var calm := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
	assert_int(shops.plan_visit(calm)["slot"]["room"]).is_equal(_room(0))
	assert_bool(shops.plan_visit(calm)["fallback"]).is_false()
	assert_int(shops.visit_wish_state(calm.id)).is_equal(WishTable.State.NONE)


func test_with_no_shop_of_its_kind_a_wisher_settles_for_less_and_loses_mood() -> void:
	# [shops, wish, mood]: a fashion wisher at a kiosk pays half the kiosk's
	# spend; a pharmacy wisher at fashion pays half the pharmacy's, not the
	# dearer fashion store's; the mood loss stops at 0.
	for case: Array in [[[&"kiosk"], &"fashion", 70], [[&"fashion"], &"pharmacy", 2]]:
		_wish_world(case[0], case[1])
		var shops := _world.sim.shops
		var p := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
		p.mood = case[2]
		assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
		var visit := shops.visit_of(p.id)
		assert_int(visit.room).is_equal(_room(0))
		assert_bool(visit.fallback).is_true()
		assert_int(shops.visit_wish_state(p.id)).is_equal(WishTable.State.SUBSTITUTED)
		var visited := RoomTypes.get_type(case[0][0]).base_spend
		var wished := RoomTypes.get_type(case[1]).base_spend
		var full := ShopSim.spend(mini(visited, wished), p.mood, true)
		var expected := int(full * ShopSim.FALLBACK_SHARE)
		var balance := _world.sim.wallet.balance
		_run_while_visiting(p)
		print(
			(
				"%s wisher at %s: paid %s (full %d, visited base %d, wished base %d), mood %d"
				% [case[1], case[0][0], _paid, full, visited, wished, p.mood]
			)
		)
		assert_int(expected).is_greater(0)
		assert_int(expected).is_less(ShopSim.spend(visited, case[2], true))
		assert_array(_paid).is_equal([[p.id, _room(0), expected]])
		assert_int(_world.sim.wallet.balance - balance).is_equal(expected)
		assert_int(p.mood).is_equal(maxi(int(case[2]) - ShopSim.FALLBACK_MOOD, 0))
		assert_int(p.boredom).is_equal(0)
	assert_int(ShopSim.FALLBACK_MOOD).is_greater(2)


func test_a_wisher_with_every_wished_slot_held_settles_for_another_shop() -> void:
	_wish_world([&"kiosk", &"pharmacy"], &"pharmacy")
	var shops := _world.sim.shops
	var first := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
	var second := ShopTestLayout.airside_guest(_world, BoredomSim.MAX, Vector2i(19, 5))
	var third := ShopTestLayout.airside_guest(_world, BoredomSim.MAX, Vector2i(19, 7))
	for p in [first, second]:
		NeedsPolicy.arbitrate(_world.sim, p)
		assert_int(shops.visit_of(p.id).room).is_equal(_room(1))
	NeedsPolicy.arbitrate(_world.sim, third)
	var visit := shops.visit_of(third.id)
	print("pharmacy slots held by %d and %d; third went to %d" % [first.id, second.id, visit.room])
	assert_int(visit.room).is_equal(_room(0))
	assert_bool(visit.fallback).is_true()


func test_a_wished_shop_out_of_time_does_not_block_a_fallback_in_time() -> void:
	# The pharmacy is further than the kiosk. Ticks before the doors close the
	# pharmacy visit stops fitting before the kiosk visit does; in between the
	# wisher plans the kiosk as a fallback instead of nothing.
	_wish_world([&"kiosk", &"pharmacy"], &"pharmacy")
	var shops := _world.sim.shops
	var p := ShopTestLayout.airside_guest(_world, 0)
	p.shop_cooldown = 1000000
	var doors := _world.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	var rooms: Array = []
	var fallback_ticks := 0
	var first_fallback := -1
	while _world.clock.tick < doors - 1:
		_world.step()
		p.stage = Passenger.Stage.TO_GATE
		p.at = ShopTestLayout.AIRSIDE_CELL
		p.clear_path()
		var plan := shops.plan_visit(p)
		var room := 0 if plan.is_empty() else int(plan["slot"]["room"])
		if rooms.is_empty() or rooms[-1] != room:
			rooms.append(room)
			print("tick %d: plans room %d" % [_world.clock.tick, room])
		if room == _room(0):
			fallback_ticks += 1
			assert_bool(plan["fallback"]).is_true()
			if first_fallback < 0:
				first_fallback = _world.clock.tick
	print("rooms planned in order %s; kiosk fallback on %d ticks" % [rooms, fallback_ticks])
	assert_array(rooms).is_equal([_room(1), _room(0), 0])
	assert_int(fallback_ticks).is_greater(10)
	assert_int(first_fallback).is_greater(0)


func test_a_wisher_never_settles_for_a_shop_that_does_not_relieve_boredom() -> void:
	_wish_world([&"exchange", &"kiosk"], &"fashion")
	var shops := _world.sim.shops
	var p := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
	var plan := shops.plan_visit(p)
	assert_int(plan["slot"]["room"]).is_equal(_room(1))
	assert_bool(plan["fallback"]).is_true()
	# With the exchange alone there is nothing to settle for.
	_wish_world([&"exchange"], &"fashion")
	var alone := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
	assert_dict(_world.sim.shops.plan_visit(alone)).is_empty()
	# Control: a spare-time browse would take the exchange.
	assert_int(_world.sim.shops.plan_visit(alone, true)["slot"]["room"]).is_equal(_room(0))


func test_spare_time_browsing_ignores_the_wish() -> void:
	_wish_world([&"kiosk", &"pharmacy"], &"pharmacy")
	var shops := _world.sim.shops
	var p := ShopTestLayout.airside_guest(_world, 0)
	p.mood = 70
	var plan := shops.plan_visit(p, true)
	assert_int(plan["slot"]["room"]).is_equal(_room(0))
	assert_bool(plan["fallback"]).is_false()
	shops.commit_visit(p, plan)
	assert_bool(shops.visit_of(p.id).fallback).is_false()
	assert_int(shops.visit_wish_state(p.id)).is_equal(WishTable.State.NONE)
	var expected := ShopSim.spend(RoomTypes.get_type(&"kiosk").base_spend, p.mood, true)
	_run_while_visiting(p)
	assert_array(_paid).is_equal([[p.id, _room(0), expected]])
	assert_int(p.mood).is_equal(70)


func test_by_default_the_wish_is_the_tables() -> void:
	_wish_world([&"kiosk"], WishTable.NONE)
	_world.sim.shops.wishes = Callable()
	var seen := {}
	for i in 40:
		var p := ShopTestLayout.airside_guest(_world, 0)
		p.arrival_type = i % 3 as ArrivalTypes.Type
		var wish := _world.sim.shops.wish_of(p)
		assert_str(wish).is_equal(WishTable.pick(p.arrival_type, p.id))
		seen[wish] = true
	print("wishes seen over 40 passengers: %s" % [seen.keys()])
	assert_int(seen.size()).is_greater(2)
	assert_int(_world.sim.shops.visit_wish_state(999999)).is_equal(WishTable.State.NONE)
