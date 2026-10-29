class_name TestStoreCounters
extends GdUnitTestSuite
## The counter of a pharmacy and the tills of a duty free and a fashion store
## are shop stations (F4-5; ruling store-mechanics-draw-a-room-then-furnish-it-
## required-pieces, point 3, 'a server per counter'), as a kiosk counter is:
## each counts while it stands in a ready room of its own type, gets a staff
## spot, and a hired shop server walks to it and opens the store.

const SHOP := StaffMember.Role.SHOP
const LIMIT_TICKS := 1500


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func test_a_store_counter_counts_only_in_a_ready_room_of_its_own_type() -> void:
	for type: StringName in StoreTestLayout.STORES:
		var grid := BuildGrid.new()
		var ids := StoreTestLayout.build(grid, type)
		var counter: int = ids["air_counter"]
		assert_bool(ShopCounters.is_counter(grid, counter)).is_true()
		(
			assert_bool(ShopCounters.usable(grid, counter))
			. override_failure_message(str(type))
			. is_true()
		)
		assert_array(ShopCounters.counters(grid)).is_equal([counter])
		assert_that(ShopCounters.spot(grid, counter)).is_not_equal(BuildObjectDef.NO_CELL)
		# Without its browse pieces the room is not ready and the counter does not count.
		for piece: int in ids["air_pieces"]:
			assert_bool(grid.apply(BuildEdit.remove_object(piece)).ok).is_true()
		assert_bool(ShopCounters.usable(grid, counter)).is_false()
		assert_array(ShopCounters.counters(grid)).is_empty()


func test_a_store_counter_in_another_shop_type_does_not_count() -> void:
	var grid := BuildGrid.new()
	var ids := ShopTestLayout.build(grid, ["air"])
	var till := grid.apply(BuildEdit.place_object(&"fashion_till", Vector2i(22, 6), 0))
	assert_bool(till.ok).is_true()
	assert_bool(ShopCounters.usable(grid, ids["air_counter"])).is_true()
	assert_bool(ShopCounters.usable(grid, till.object_id)).is_false()


func test_a_hired_server_walks_to_a_store_counter_and_opens_the_store() -> void:
	for type: StringName in StoreTestLayout.STORES:
		var grid := BuildGrid.new()
		var ids := StoreTestLayout.build(grid, type, ["land"])
		var w := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
		w.auto_staff = false
		assert_bool(ShopCounters.room_open(w.sim, ids["land_room"])).is_false()
		w.staff.hire(SHOP)
		var until := w.clock.tick + LIMIT_TICKS
		while not ShopCounters.room_open(w.sim, ids["land_room"]) and w.clock.tick < until:
			w.step()
		print("%s opened at tick %d" % [type, w.clock.tick])
		(
			assert_bool(ShopCounters.room_open(w.sim, ids["land_room"]))
			. override_failure_message(str(type))
			. is_true()
		)
		assert_array(w.staff.stations_of(SHOP)).is_equal([ids["land_counter"]])
		w.free_all()
