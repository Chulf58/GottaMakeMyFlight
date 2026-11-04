class_name TestFoodVenuePieces
extends GdUnitTestSuite
## The food rooms use their own pieces (user-ruled 2026-11-04, "Make them
## work"; decision food-venues-as-built-stall-cafe-bar-and-restaurant-are-
## food): the bar its bar counter, the restaurant its dining table and booth,
## the grab-and-go stall its grab stall. Each room still accepts the cafe
## counter and table, and a cafe takes only its own.

var _worlds: Array[PassengerTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in _worlds:
		world.free_all()
	_worlds.clear()


## A world with both rooms of the reference layout set to `venue`, built from
## the `counter` and `table` pieces (`table` empty places none).
func _world(venue: StringName, counter: StringName, table: StringName) -> Array:
	var grid := BuildGrid.new()
	var tables := table != &""
	var ids := CafeTestLayout.build(
		grid, false, venue, tables, counter, table if tables else &"cafe_table"
	)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_worlds.append(world)
	return [world, ids]


## A passenger who has not been hungry or browsing, taken to the gate walk.
func _guest(world: PassengerTestWorld) -> Passenger:
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.cafe_cooldown = 1000000
	p.hunger = 30
	p.mood = 50
	while p.stage != Passenger.Stage.TO_GATE and world.clock.tick < 900:
		world.step()
	return p


## One visit run to its end: {"visit": the CafeVisit, "stages": the stages
## seen, "counter_def", "table_def" (empty for a walk-on visit)}.
func _ride(world: PassengerTestWorld) -> Dictionary:
	var p := _guest(world)
	assert_bool(world.sim.cafes.try_visit(p)).override_failure_message("visit refused").is_true()
	var visit := world.sim.cafes.visit_of(p.id)
	var seen := {}
	while world.sim.cafes.visit_of(p.id) != null and world.clock.tick < 3000:
		seen[p.stage] = true
		world.step()
	var table_def := ""
	if not visit.seat_key.is_empty():
		var table := int(visit.seat_key.split(":")[0])
		table_def = String(world.grid.get_object(table)["def"])
	return {
		"visit": visit,
		"stages": seen,
		"counter_def": String(world.grid.get_object(visit.counter)["def"]),
		"table_def": table_def,
	}


func _seats_of(world: PassengerTestWorld) -> int:
	var seats := 0
	for cafe in world.sim.cafes.layout.cafes:
		seats += cafe["seats"].size()
	return seats


func test_a_bar_with_only_a_bar_counter_and_a_table_is_ready_and_usable() -> void:
	var made := _world(&"bar", &"bar_counter", &"cafe_table")
	var world: PassengerTestWorld = made[0]
	var ids: Dictionary = made[1]
	for room in [ids["air_room"], ids["land_room"]]:
		var status := RoomRules.status(world.grid, room)
		assert_array(Array(status.notes)).is_empty()
		assert_bool(status.ok).is_true()
		assert_int(status.seats).is_equal(2)
	world.sim.cafes.refresh()
	var cafes := world.sim.cafes.layout.cafes
	print("bar with a bar counter: %d cafes, %d seats" % [cafes.size(), _seats_of(world)])
	assert_int(cafes.size()).is_equal(2)
	assert_int(_seats_of(world)).is_equal(4)
	for cafe in cafes:
		assert_array(cafe["counters"]).is_not_empty()
	# The server of a bar counter has a spot, so the counter can open.
	assert_array(ShopCounters.counters(world.grid)).contains([ids["air_counter"]])


func test_a_bar_with_a_bar_counter_and_no_table_still_needs_a_table() -> void:
	var made := _world(&"bar", &"bar_counter", &"")
	var world: PassengerTestWorld = made[0]
	var status := RoomRules.status(world.grid, made[1]["air_room"])
	assert_bool(status.ok).is_false()
	assert_array(Array(status.notes)).contains(["Needs a table"])
	assert_array(Array(status.notes)).not_contains(["Needs a counter"])


func test_the_cafe_counter_and_table_still_make_a_bar_ready() -> void:
	var made := _world(&"bar", &"cafe_counter", &"cafe_table")
	var world: PassengerTestWorld = made[0]
	var status := RoomRules.status(world.grid, made[1]["air_room"])
	assert_bool(status.ok).is_true()
	world.sim.cafes.refresh()
	assert_int(world.sim.cafes.layout.cafes.size()).is_equal(2)


func test_a_bar_guest_orders_at_the_bar_counter_and_sits_at_the_table() -> void:
	var made := _world(&"bar", &"bar_counter", &"cafe_table")
	var ride := _ride(made[0])
	var visit: CafeVisit = ride["visit"]
	print(
		(
			"bar visit: counter %s, table %s, paid %d"
			% [ride["counter_def"], ride["table_def"], visit.amount]
		)
	)
	assert_str(ride["counter_def"]).is_equal("bar_counter")
	assert_str(ride["table_def"]).is_equal("cafe_table")
	assert_bool(ride["stages"].has(Passenger.Stage.CAFE_SEATED)).is_true()
	assert_int(visit.outcome).is_equal(CafeVisit.Outcome.COMPLETE)
	assert_int(visit.amount).is_greater(0)


func test_a_restaurant_with_a_dining_table_or_a_booth_is_ready_with_four_seats() -> void:
	for table in [&"restaurant_table", &"restaurant_booth"]:
		var made := _world(&"restaurant", &"cafe_counter", table)
		var world: PassengerTestWorld = made[0]
		for room in [made[1]["air_room"], made[1]["land_room"]]:
			var status := RoomRules.status(world.grid, room)
			assert_array(Array(status.notes)).is_empty()
			assert_int(status.seats).is_equal(4)
		world.sim.cafes.refresh()
		var cafes := world.sim.cafes.layout.cafes
		print("restaurant with a %s: %d cafes, %d seats" % [table, cafes.size(), _seats_of(world)])
		assert_int(cafes.size()).is_equal(2)
		# Every chair has an approach cell a guest can use.
		assert_int(_seats_of(world)).is_equal(8)


func test_a_restaurant_guest_sits_at_the_dining_table_and_at_the_booth() -> void:
	for table in [&"restaurant_table", &"restaurant_booth"]:
		var made := _world(&"restaurant", &"cafe_counter", table)
		var ride := _ride(made[0])
		var visit: CafeVisit = ride["visit"]
		print("restaurant visit at a %s: seat %s, paid %d" % [table, visit.seat_key, visit.amount])
		assert_str(ride["table_def"]).is_equal(String(table))
		assert_bool(ride["stages"].has(Passenger.Stage.CAFE_SEATED)).is_true()
		assert_int(visit.outcome).is_equal(CafeVisit.Outcome.COMPLETE)
		assert_int(visit.amount).is_greater(0)


func test_the_cafe_table_and_counter_still_make_a_restaurant_and_a_cafe_work() -> void:
	for venue in [&"restaurant", &"cafe"]:
		var made := _world(venue, &"cafe_counter", &"cafe_table")
		var world: PassengerTestWorld = made[0]
		assert_bool(RoomRules.status(world.grid, made[1]["air_room"]).ok).is_true()
		var ride := _ride(world)
		print(
			(
				"%s visit on cafe pieces: counter %s, table %s"
				% [venue, ride["counter_def"], ride["table_def"]]
			)
		)
		assert_str(ride["table_def"]).is_equal("cafe_table")
		assert_bool(ride["stages"].has(Passenger.Stage.CAFE_SEATED)).is_true()
		assert_int(ride["visit"].outcome).is_equal(CafeVisit.Outcome.COMPLETE)


func test_a_cafe_takes_only_its_own_pieces() -> void:
	# The controls: the bar's and the restaurant's pieces do not make a cafe.
	var with_bar := _world(&"cafe", &"bar_counter", &"cafe_table")
	var bar_status := RoomRules.status(with_bar[0].grid, with_bar[1]["air_room"])
	assert_array(Array(bar_status.notes)).contains(["Needs a counter"])
	var with_dining := _world(&"cafe", &"cafe_counter", &"restaurant_table")
	var dining_status := RoomRules.status(with_dining[0].grid, with_dining[1]["air_room"])
	assert_array(Array(dining_status.notes)).contains(["Needs a table"])
	var bar_in_restaurant := _world(&"restaurant", &"bar_counter", &"restaurant_table")
	var restaurant_status := RoomRules.status(
		bar_in_restaurant[0].grid, bar_in_restaurant[1]["air_room"]
	)
	assert_array(Array(restaurant_status.notes)).contains(["Needs a counter"])


func test_a_grab_stall_alone_makes_a_stall_room_ready_and_serves_a_guest() -> void:
	var made := _world(&"stall", &"grab_and_go_stall", &"")
	var world: PassengerTestWorld = made[0]
	var ids: Dictionary = made[1]
	for room in [ids["air_room"], ids["land_room"]]:
		assert_bool(RoomRules.status(world.grid, room).ok).is_true()
	world.sim.cafes.refresh()
	assert_int(world.sim.cafes.layout.cafes.size()).is_equal(2)
	assert_array(ShopCounters.counters(world.grid)).contains([ids["air_counter"]])
	var ride := _ride(world)
	var visit: CafeVisit = ride["visit"]
	print("stall visit: counter %s, paid %d" % [ride["counter_def"], visit.amount])
	assert_str(ride["counter_def"]).is_equal("grab_and_go_stall")
	assert_str(visit.seat_key).is_empty()
	assert_int(visit.outcome).is_equal(CafeVisit.Outcome.COMPLETE)
	assert_int(visit.amount).is_greater(0)


func test_which_counter_works_in_which_room() -> void:
	var works := {
		[&"cafe_counter", &"cafe"]: true,
		[&"cafe_counter", &"bar"]: true,
		[&"cafe_counter", &"restaurant"]: true,
		[&"cafe_counter", &"stall"]: true,
		[&"bar_counter", &"bar"]: true,
		[&"bar_counter", &"cafe"]: false,
		[&"bar_counter", &"restaurant"]: false,
		[&"grab_and_go_stall", &"stall"]: true,
		[&"grab_and_go_stall", &"bar"]: false,
		[&"grab_and_go_stall", &"cafe"]: false,
	}
	for key: Array in works:
		(
			assert_bool(ShopCounters.works_in(key[0], key[1]))
			. override_failure_message("%s in %s" % key)
			. is_equal(works[key])
		)
