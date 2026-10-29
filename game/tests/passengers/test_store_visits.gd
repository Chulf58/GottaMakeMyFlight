class_name TestStoreVisits
extends GdUnitTestSuite
## The pharmacy, duty free and fashion stores (F4-5; ruling
## shops-and-food-stalls-earn-per-visit-toilets-and-screens-cos) run on the
## kiosk's visit pipeline (ShopLayout, ShopSim): a bored passenger browses a
## slot of the store's browse piece, pays the store type's base spend nudged by
## mood with the airside bonus, and its boredom is reset. A store with no
## server at its counter or till is closed and gets no visit.

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


func _store_world(type: StringName, staffed := true) -> PassengerTestWorld:
	var grid := BuildGrid.new()
	_ids = StoreTestLayout.build(grid, type)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	if not staffed:
		_world.auto_staff_roles = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]
	_world.sim.shops.paid.connect(
		func(id: int, room: int, amount: int) -> void: _paid.append([id, room, amount])
	)
	# Staff come on duty on the first ticks.
	_world.run_to(10)
	return _world


func test_each_store_lays_out_the_browse_slots_of_its_browse_pieces() -> void:
	for type: StringName in StoreTestLayout.STORES:
		_store_world(type)
		var layout := _world.sim.shops.layout
		_world.sim.shops.refresh()
		assert_int(layout.shops.size()).override_failure_message(str(type)).is_equal(1)
		var shop: Dictionary = layout.shops[0]
		var per_piece: int = StoreTestLayout.STORES[type][2]
		var keys: Array = []
		for slot: Dictionary in shop["slots"]:
			keys.append(slot["key"])
			assert_int(slot["room"]).is_equal(_ids["air_room"])
			assert_that(slot["facing"]).is_equal(Vector2i(0, -1))
		print("%s slots %s" % [type, keys])
		assert_int(shop["room"]).is_equal(_ids["air_room"])
		assert_int(keys.size()).override_failure_message(str(type)).is_equal(2 * per_piece)
		for piece: int in _ids["air_pieces"]:
			for i in per_piece:
				assert_array(keys).contains([ShopLayout.key_of(piece, i)])
		_world.free_all()
		_world = null


func test_a_visit_to_each_store_pays_its_base_spend_with_mood_and_airside_bonus() -> void:
	var spends := {}
	for type: StringName in StoreTestLayout.STORES:
		_store_world(type)
		var p := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
		p.mood = 70
		var balance := _world.sim.wallet.balance
		assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
		var visit := _world.sim.shops.visit_of(p.id)
		assert_object(visit).override_failure_message(str(type)).is_not_null()
		assert_int(visit.room).is_equal(_ids["air_room"])
		var base := RoomTypes.get_type(type).base_spend
		var expected := ShopSim.spend(base, p.mood, true)
		var until := _world.clock.tick + 3000
		while _world.sim.shops.visit_of(p.id) != null and _world.clock.tick < until:
			_world.step()
		print("%s: base %d, paid %s, boredom %d" % [type, base, _paid, p.boredom])
		assert_int(expected).is_greater(base)
		assert_array(_paid).is_equal([[p.id, _ids["air_room"], expected]])
		assert_int(_world.sim.wallet.balance - balance).is_equal(expected)
		assert_int(p.boredom).is_equal(0)
		spends[type] = _paid[0][2]
		_world.free_all()
		_world = null
		_paid.clear()
	# Each store pays its own type's spend, not the kiosk's.
	assert_int(spends[&"fashion"]).is_greater(spends[&"duty_free"])
	assert_int(spends[&"duty_free"]).is_greater(spends[&"pharmacy"])


func test_an_unstaffed_store_is_closed_and_gets_no_visit_until_a_server_comes() -> void:
	for type: StringName in StoreTestLayout.STORES:
		_store_world(type, false)
		var p := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
		assert_bool(ShopCounters.room_open(_world.sim, _ids["air_room"])).is_false()
		assert_array(ShopCounters.closed(_world.sim)).contains([_ids["air_counter"]])
		(
			assert_bool(_world.sim.shops.plan_visit(p).is_empty())
			. override_failure_message(str(type))
			. is_true()
		)
		assert_bool(_world.sim.shops.wants_relief(p)).is_true()
		NeedsPolicy.arbitrate(_world.sim, p)
		assert_object(_world.sim.shops.visit_of(p.id)).is_null()
		StaffTestKit.seat_server(_world.staff, _ids["air_counter"])
		assert_bool(ShopCounters.room_open(_world.sim, _ids["air_room"])).is_true()
		var plan := _world.sim.shops.plan_visit(p)
		assert_bool(plan.is_empty()).override_failure_message(str(type)).is_false()
		assert_int(plan["slot"]["room"]).is_equal(_ids["air_room"])
		_world.free_all()
		_world = null
