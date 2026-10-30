class_name TestStallWalkOn
extends GdUnitTestSuite
## The grab-and-go stall is a walk-on venue (decision food-and-drink-cafe-bar-
## sit-down-restaurant-and-grab-and-go): a room with only a counter is ready,
## and a guest buys at the counter, pays and walks on. The visit reserves no
## seat and has no walk to a seat, sit or stand phase.

## The stages only a seated visit passes through.
const SEATED_STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.CAFE_TO_SEAT,
	Passenger.Stage.CAFE_SITTING_DOWN,
	Passenger.Stage.CAFE_SEATED,
	Passenger.Stage.CAFE_STANDING_UP,
]

var _worlds: Array[PassengerTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in _worlds:
		world.free_all()
	_worlds.clear()


func _world(venue: StringName, tables: bool) -> Array:
	var grid := BuildGrid.new()
	var ids := CafeTestLayout.build(grid, false, null, venue, tables)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_worlds.append(world)
	return [world, ids]


## A passenger who is not hungry or browsing, taken to airside walking.
func _guest(world: PassengerTestWorld) -> Passenger:
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.cafe_cooldown = 1000000
	p.hunger = 30
	p.mood = 50
	while p.stage != Passenger.Stage.TO_GATE and world.clock.tick < 900:
		world.step()
	return p


func test_a_stall_room_with_only_a_counter_is_ready_and_usable() -> void:
	var made := _world(&"stall", false)
	var world: PassengerTestWorld = made[0]
	var ids: Dictionary = made[1]
	assert_bool(ids.has("air_table")).is_false()
	for room in [ids["air_room"], ids["land_room"]]:
		var status := RoomRules.status(world.grid, room)
		assert_array(Array(status.notes)).is_empty()
		assert_bool(status.ok).is_true()
		assert_int(status.seats).is_equal(0)
	world.sim.cafes.refresh()
	var cafes := world.sim.cafes.layout.cafes
	assert_int(cafes.size()).is_equal(2)
	for cafe in cafes:
		assert_str(String(cafe["type"])).is_equal("stall")
		assert_array(cafe["seats"]).is_empty()
		assert_array(cafe["counters"]).is_not_empty()
	var type := RoomTypes.get_type(&"stall")
	assert_bool(type.walk_on).is_true()
	assert_int(type.dwell_ticks).is_equal(0)
	(
		assert_array(type.required.map(func(need: Array) -> StringName: return need[0]))
		. is_equal([&"cafe_counter"])
	)


func test_a_cafe_room_with_only_a_counter_still_needs_a_table() -> void:
	# The control: the walk-on rule is the stall's, not every food room's.
	var made := _world(&"cafe", false)
	var world: PassengerTestWorld = made[0]
	var ids: Dictionary = made[1]
	var status := RoomRules.status(world.grid, ids["air_room"])
	assert_bool(status.ok).is_false()
	assert_array(Array(status.notes)).contains(["Needs a table"])
	world.sim.cafes.refresh()
	assert_array(world.sim.cafes.layout.cafes).is_empty()


func test_a_stall_visit_reserves_no_seat_and_the_guest_walks_on_after_paying() -> void:
	var made := _world(&"stall", false)
	var world: PassengerTestWorld = made[0]
	var p := _guest(world)
	assert_bool(world.sim.cafes.try_visit(p)).is_true()
	var visit := world.sim.cafes.visit_of(p.id)
	assert_bool(visit.walk_on()).is_true()
	assert_str(visit.seat_key).is_empty()
	assert_dict(visit.seat).is_empty()
	assert_int(world.sim.cafes.seat_holder("")).is_equal(0)
	var seen := {}
	var mood := p.mood
	while world.sim.cafes.visit_of(p.id) != null and world.clock.tick < 2000:
		seen[p.stage] = true
		mood = p.mood
		world.step()
	var names := seen.keys().map(func(s: int) -> String: return Passenger.Stage.keys()[s])
	print("stall stages seen %s" % [names])
	# The positive control: the visit did run through the walk, queue and order.
	for stage in [
		Passenger.Stage.CAFE_WALK, Passenger.Stage.CAFE_QUEUE, Passenger.Stage.CAFE_ORDER
	]:
		assert_bool(seen.has(stage)).is_true()
	for stage in SEATED_STAGES:
		assert_bool(seen.has(stage)).is_false()
	# It paid in full at the counter, and was released onto its journey on the spot.
	assert_int(visit.outcome).is_equal(CafeVisit.Outcome.COMPLETE)
	assert_int(visit.amount).is_equal(
		CafeSim.spend(
			RoomTypes.get_type(&"stall").base_spend, mood, true, CafeVisit.Outcome.COMPLETE
		)
	)
	assert_int(visit.amount).is_greater(0)
	assert_int(world.sim.wallet.balance).is_equal(visit.amount)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
	assert_int(p.hunger).is_equal(0)
	assert_int(p.mood).is_equal(mood + RoomTypes.get_type(&"stall").mood_bonus)
	world.run_to(world.flights.doors_close_tick(p.flight_id) + 1)
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)


func test_a_table_in_a_stall_room_is_not_used() -> void:
	var made := _world(&"stall", true)
	var world: PassengerTestWorld = made[0]
	var p := _guest(world)
	assert_bool(world.sim.cafes.try_visit(p)).is_true()
	var visit := world.sim.cafes.visit_of(p.id)
	assert_str(visit.seat_key).is_empty()
	for cafe in world.sim.cafes.layout.cafes:
		assert_array(cafe["seats"]).is_empty()
	var sat := false
	while world.sim.cafes.visit_of(p.id) != null and world.clock.tick < 2000:
		sat = sat or p.stage == Passenger.Stage.CAFE_SEATED
		world.step()
	assert_bool(sat).is_false()
	assert_int(visit.outcome).is_equal(CafeVisit.Outcome.COMPLETE)


func test_several_guests_queue_at_a_stall_with_no_seats_and_each_pays() -> void:
	var made := _world(&"stall", false)
	var world: PassengerTestWorld = made[0]
	var guests: Array[Passenger] = []
	for i in 3:
		var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		p.cafe_cooldown = 1000000
		p.hunger = 30
		p.mood = 50
		guests.append(p)
	# Each guest is committed as it reaches the gate leg, so they share a queue.
	var visits: Array[CafeVisit] = []
	var committed := {}
	while visits.size() < guests.size() and world.clock.tick < 1500:
		world.step()
		for guest in guests:
			if guest.stage == Passenger.Stage.TO_GATE and not committed.has(guest.id):
				assert_bool(world.sim.cafes.try_visit(guest)).is_true()
				committed[guest.id] = true
				visits.append(world.sim.cafes.visit_of(guest.id))
	assert_int(visits.size()).is_equal(guests.size())
	while not world.sim.cafes.visit_ids().is_empty() and world.clock.tick < 3000:
		world.step()
	var paid := 0
	for visit in visits:
		assert_int(visit.outcome).is_equal(CafeVisit.Outcome.COMPLETE)
		paid += visit.amount
	print("three stall guests paid %d" % paid)
	assert_int(paid).is_greater(0)
	assert_int(world.sim.wallet.balance).is_equal(paid)
