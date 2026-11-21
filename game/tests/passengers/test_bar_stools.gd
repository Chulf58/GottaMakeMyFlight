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


## Both rooms of the reference layout as bars with a bar counter, and a second
## bar counter too with `extra_counter`.
func _world(extra_counter: bool) -> Array:
	var grid := BuildGrid.new()
	var ids := CafeTestLayout.build(
		grid, false, &"bar", extra_counter, &"bar_counter", &"bar_counter"
	)
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


## Each stool is stepped onto from its open side (board 64ee4dc0: from behind,
## the right stool's guest walked through the stool). A wall between the right
## stool and the cell to its right drops that stool; the left one stays.
func test_a_wall_beside_the_right_stool_drops_it_and_keeps_the_left_one() -> void:
	var made := _world(false)
	var world: PassengerTestWorld = made[0]
	var counter: int = made[1]["air_counter"]
	var before := RoomRules.reachable_seats(world.grid, counter)
	var at := ReferenceTerminal.offset_on(world.grid)
	var right_stool := CafeTestLayout.AIR_COUNTER + Vector2i(1, 1) + at
	var wall := world.grid.apply(BuildEdit.place_wall(right_stool, BuildGrid.Side.EAST))
	assert_bool(wall.ok).override_failure_message(wall.reason_text()).is_true()
	var after := RoomRules.reachable_seats(world.grid, counter)
	print(
		(
			"bar stools reachable: %d open, %d with a wall east of %s (left %s)"
			% [before.size(), after.size(), right_stool, after.map(func(s): return s["index"])]
		)
	)
	# The control: both stools are reachable before the wall.
	assert_int(before.size()).is_equal(2)
	assert_int(after.size()).is_equal(1)
	assert_int(after[0]["index"]).is_equal(0)
	assert_vector(Vector2(after[0]["approach"])).is_equal(
		Vector2(CafeTestLayout.AIR_COUNTER + Vector2i(-1, 1) + at)
	)


## Two bar counters side by side: each one's inner stool is stepped onto from
## the cell the other's inner stool stands in, so 2 of the 4 stools are
## reachable (accepted by the conductor on board 64ee4dc0; the info card shows
## "N of M seats reachable").
func test_two_bar_counters_side_by_side_seat_two_of_four() -> void:
	var made := _world(false)
	var world: PassengerTestWorld = made[0]
	var left: int = made[1]["air_counter"]
	var alone := RoomRules.reachable_seats(world.grid, left).size()
	var at := ReferenceTerminal.offset_on(world.grid)
	var placed := world.grid.apply(
		BuildEdit.place_object(&"bar_counter", CafeTestLayout.AIR_COUNTER + Vector2i(2, 0) + at, 0)
	)
	assert_bool(placed.ok).override_failure_message(placed.reason_text()).is_true()
	var mine := RoomRules.reachable_seats(world.grid, left)
	var theirs := RoomRules.reachable_seats(world.grid, placed.object_id)
	print(
		(
			"bar counter alone: %d stools; side by side: %d + %d (indices %s, %s)"
			% [
				alone,
				mine.size(),
				theirs.size(),
				mine.map(func(s): return s["index"]),
				theirs.map(func(s): return s["index"]),
			]
		)
	)
	# The control: a counter on its own has both stools.
	assert_int(alone).is_equal(2)
	assert_int(mine.size() + theirs.size()).is_equal(2)
	assert_int(mine[0]["index"]).is_equal(0)
	assert_int(theirs[0]["index"]).is_equal(1)


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


## A cafe_table placed in a bar is ignored (ruling 17fe639a): only the bar
## counter's stools are bar seats.
func test_a_cafe_table_in_a_bar_is_not_a_bar_seat() -> void:
	var grid := BuildGrid.new()
	var ids := CafeTestLayout.build(grid, false, &"bar", true, &"bar_counter", &"cafe_table")
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_worlds.append(world)
	world.sim.cafes.refresh()
	var cafe := world.sim.cafes.layout.cafe(ids["air_room"])
	assert_int(cafe["seats"].size()).is_equal(2)
	for seat in cafe["seats"]:
		assert_int(seat["object_id"]).is_equal(ids["air_counter"])


func test_once_both_stools_are_taken_the_next_bar_guest_takes_the_second_bar_counter() -> void:
	var made := _world(false)
	var world: PassengerTestWorld = made[0]
	var ids: Dictionary = made[1]
	var at := ReferenceTerminal.offset_on(world.grid)
	var waiting := _guests(world, 3, false)
	var counters_taken: Array[int] = []
	var keys_taken: Array[String] = []
	var overflow: Passenger = null
	while not waiting.is_empty() and world.clock.tick < 900:
		world.step()
		for p in waiting.duplicate():
			if p.stage != Passenger.Stage.TO_GATE:
				continue
			waiting.erase(p)
			if counters_taken.size() < 2:
				var message := "visit of guest %d refused" % p.id
				(
					assert_bool(world.sim.cafes.try_visit(p))
					. override_failure_message(message)
					. is_true()
				)
				var visit := world.sim.cafes.visit_of(p.id)
				assert_object(visit).is_not_null()
				counters_taken.append(int(visit.seat_key.split(":")[0]))
				keys_taken.append(visit.seat_key)
			else:
				overflow = p
	assert_int(counters_taken.size()).is_equal(2)
	assert_int(counters_taken[0]).is_equal(ids["air_counter"])
	assert_int(counters_taken[1]).is_equal(ids["air_counter"])
	assert_object(overflow).is_not_null()
	# With both stools of the first bar_counter taken, a third guest is refused until a second
	# bar_counter is placed.
	assert_bool(world.sim.cafes.try_visit(overflow)).is_false()
	var second := world.grid.apply(BuildEdit.place_object(&"bar_counter", Vector2i(27, 6) + at, 1))
	assert_bool(second.ok).override_failure_message(second.reason_text()).is_true()
	world.sim.cafes.refresh()
	assert_bool(world.sim.cafes.try_visit(overflow)).is_true()
	var third_visit := world.sim.cafes.visit_of(overflow.id)
	assert_object(third_visit).is_not_null()
	counters_taken.append(int(third_visit.seat_key.split(":")[0]))
	keys_taken.append(third_visit.seat_key)
	assert_int(counters_taken[2]).is_equal(second.object_id)
	var distinct := {}
	for k in keys_taken:
		distinct[k] = true
	assert_int(distinct.size()).is_equal(3)
