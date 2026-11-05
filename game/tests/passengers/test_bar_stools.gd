class_name TestBarStools
extends GdUnitTestSuite
## Bar guests take the bar counter's two stools first and a table seat when
## both are taken, and a bar works with only a bar counter (user-ruled
## 2026-11-04, decision bar-guests-sit-at-the-bar-counter-stools-first-then-at-
## table). The bar's order cell is in front of the left stool, so no stool may
## be stepped into from it: CafeLayout gives no queue lane to a counter whose
## order cell is a seat's approach, and the bar would quietly take no orders.

var _worlds: Array[PassengerTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in _worlds:
		world.free_all()
	_worlds.clear()


## Both rooms of the reference layout as bars with a bar counter, and a cafe
## table too with `table`.
func _world(table: bool) -> Array:
	var grid := BuildGrid.new()
	var ids := CafeTestLayout.build(grid, false, &"bar", table, &"bar_counter")
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_worlds.append(world)
	return [world, ids]


## `count` passengers who have not been hungry or browsing, taken to the gate
## walk unless `walk` is false.
func _guests(world: PassengerTestWorld, count: int, walk := true) -> Array[Passenger]:
	var out: Array[Passenger] = []
	for i in count:
		var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		p.cafe_cooldown = 1000000
		p.hunger = 30
		p.mood = 50
		out.append(p)
	while walk and out[0].stage != Passenger.Stage.TO_GATE and world.clock.tick < 900:
		world.step()
	return out


## The catalog id of the piece a visit's seat belongs to.
func _seat_def(world: PassengerTestWorld, visit: CafeVisit) -> String:
	return String(world.grid.get_object(int(visit.seat_key.split(":")[0]))["def"])


func test_no_seat_of_any_piece_is_stepped_into_from_its_order_cell() -> void:
	var checked := 0
	for id in BuildCatalog.ids():
		var def := BuildCatalog.get_def(id)
		if def.seats.is_empty() or not def.has_interaction:
			continue
		for facing in 4:
			var order := Vector2(def.interaction_cell(Vector2i(10, 10), facing))
			for seat in def.seat_descriptors(Vector2i(10, 10), facing):
				var why := "%s facing %d: seat %d is entered from the order cell"
				var approach := Vector2(seat["approach"])
				var message := why % [id, facing, seat["index"]]
				assert_vector(approach).override_failure_message(message).is_not_equal(order)
				checked += 1
	print("seats checked against their piece's order cell: %d" % checked)
	# The bar counter's two stools in four facings at least.
	assert_int(checked).is_greater_equal(8)


func test_a_bar_with_only_a_bar_counter_is_ready_seats_two_and_its_order_cell_has_a_lane() -> void:
	var made := _world(false)
	var world: PassengerTestWorld = made[0]
	var ids: Dictionary = made[1]
	world.sim.cafes.refresh()
	for room in [ids["air_room"], ids["land_room"]]:
		var status := RoomRules.status(world.grid, room)
		var cafe := world.sim.cafes.layout.cafe(room)
		print(
			(
				"counter-only bar %d: notes %s, seats %d, venue %s"
				% [room, status.notes, status.seats, cafe]
			)
		)
		assert_array(Array(status.notes)).is_empty()
		assert_bool(status.ok).is_true()
		assert_int(status.seats).is_equal(2)
		assert_bool(cafe.is_empty()).is_false()
		assert_int(cafe["seats"].size()).is_equal(2)
		var counter_id: int = ids["air_counter"] if room == ids["air_room"] else ids["land_counter"]
		var counter := world.sim.cafes.layout.counter(room, counter_id)
		assert_bool(counter.is_empty()).override_failure_message("the bar got no lane").is_false()
		var lane: Array = counter["lane"]
		assert_vector(Vector2(lane[0])).is_equal(Vector2(world.grid.interaction_cell(counter_id)))
		assert_int(lane.size()).is_equal(CafeLayout.LANE_SLOTS)
		for seat in cafe["seats"]:
			assert_int(seat["object_id"]).is_equal(counter_id)
			assert_array(lane).not_contains([seat["approach"]])


func test_a_bar_guest_sits_on_a_stool_at_the_bar_counter() -> void:
	var made := _world(true)
	var world: PassengerTestWorld = made[0]
	var p: Passenger = _guests(world, 1)[0]
	assert_bool(world.sim.cafes.try_visit(p)).override_failure_message("visit refused").is_true()
	var visit := world.sim.cafes.visit_of(p.id)
	var seen := {}
	while world.sim.cafes.visit_of(p.id) != null and world.clock.tick < 3000:
		seen[p.stage] = true
		world.step()
	var seat_def := _seat_def(world, visit)
	print("bar visit: seat %s on a %s, paid %d" % [visit.seat_key, seat_def, visit.amount])
	assert_str(_seat_def(world, visit)).is_equal("bar_counter")
	assert_int(int(visit.seat_key.split(":")[0])).is_equal(visit.counter)
	assert_bool(seen.has(Passenger.Stage.CAFE_SEATED)).is_true()
	assert_int(visit.outcome).is_equal(CafeVisit.Outcome.COMPLETE)
	assert_int(visit.amount).is_greater(0)


## Nearness alone would pick the table: the seat search starts on a table
## seat's own approach cell, and a free stool still wins.
func test_a_free_stool_wins_over_a_nearer_table_seat() -> void:
	var made := _world(true)
	var world: PassengerTestWorld = made[0]
	world.sim.cafes.refresh()
	var cafe := world.sim.cafes.layout.cafe(made[1]["air_room"])
	var table_seat: Dictionary = {}
	for seat in cafe["seats"]:
		if seat["object_id"] == made[1]["air_table"]:
			table_seat = seat
	assert_bool(table_seat.is_empty()).is_false()
	var picked: Dictionary = world.sim.cafes._free_seat(cafe, table_seat["approach"])
	print(
		(
			"seat search from table seat %s's approach %s picked %s"
			% [table_seat["key"], table_seat["approach"], picked.get("key", "none")]
		)
	)
	assert_int(picked.get("object_id", 0)).is_equal(made[1]["air_counter"])


func test_once_both_stools_are_taken_the_next_bar_guest_takes_a_table_seat() -> void:
	var made := _world(true)
	var world: PassengerTestWorld = made[0]
	var waiting := _guests(world, 3, false)
	# Each guest is sent to the bar the tick it starts its gate walk, while the
	# guests before it still hold their seats.
	var seats: Array[String] = []
	while not waiting.is_empty() and world.clock.tick < 900:
		world.step()
		for p in waiting.duplicate():
			if p.stage != Passenger.Stage.TO_GATE:
				continue
			waiting.erase(p)
			var message := "visit of guest %d refused" % p.id
			assert_bool(world.sim.cafes.try_visit(p)).override_failure_message(message).is_true()
			var visit := world.sim.cafes.visit_of(p.id)
			if visit != null:
				seats.append(_seat_def(world, visit))
	print("bar seats taken in turn: %s (tick %d)" % [seats, world.clock.tick])
	assert_array(seats).is_equal(["bar_counter", "bar_counter", "cafe_table"])
