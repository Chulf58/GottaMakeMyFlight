class_name TestFoodVenues
extends GdUnitTestSuite
## The food rooms (F4-6; decision food-and-drink-cafe-bar-sit-down-restaurant-
## and-grab-and-go-st): a grab-and-go stall, a cafe, a bar and a sit-down
## restaurant share the cafe counter and the CafeSim visit (the stall needs no
## table: its guest walks on after paying), and differ in how long a visit
## takes and what it pays: stall < cafe < bar < restaurant. The numbers are
## pinned here, then measured through real visits.

## Smallest to largest.
const VENUES: Array[StringName] = [&"stall", &"cafe", &"bar", &"restaurant"]

var _worlds: Array[PassengerTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in _worlds:
		world.free_all()
	_worlds.clear()


## A world with both rooms of the reference layout set to `venue`.
func _world(venue: StringName) -> PassengerTestWorld:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid, false, null, venue)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_worlds.append(world)
	return world


## A passenger who has not been hungry or browsing, taken to `stage`.
func _guest(world: PassengerTestWorld, stage: Passenger.Stage) -> Passenger:
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.cafe_cooldown = 1000000
	p.hunger = 30
	p.mood = 50
	while p.stage != stage and world.clock.tick < 900:
		world.step()
	return p


## What one airside visit to `venue` did: {"order": ticks from the start of the
## order to the guest getting up, "amount": paid, "mood": mood gained}.
func _measure(venue: StringName) -> Dictionary:
	var world := _world(venue)
	var p := _guest(world, Passenger.Stage.TO_GATE)
	(
		assert_bool(world.sim.cafes.try_visit(p))
		. override_failure_message("%s refused a guest with all the time there is" % venue)
		. is_true()
	)
	var visit := world.sim.cafes.visit_of(p.id)
	assert_str(String(visit.venue)).is_equal(String(venue))
	var gained := 0
	var ordered_at := -1
	var stood_at := -1
	while stood_at < 0 and world.clock.tick < 3000:
		var before_step := p.mood
		world.step()
		if ordered_at < 0 and p.stage == Passenger.Stage.CAFE_ORDER:
			ordered_at = world.clock.tick
		# A seated guest ends at standing up; a stall guest walks on at once.
		if p.stage == Passenger.Stage.CAFE_STANDING_UP or world.sim.cafes.visit_of(p.id) == null:
			stood_at = world.clock.tick
			gained = p.mood - before_step
	assert_int(visit.outcome).is_equal(CafeVisit.Outcome.COMPLETE)
	return {"order": stood_at - ordered_at, "amount": visit.amount, "mood": gained}


func test_the_numbers_run_stall_cafe_bar_restaurant() -> void:
	var visits: Array[int] = []
	var bases: Array[int] = []
	var moods: Array[int] = []
	for id in VENUES:
		var type := RoomTypes.get_type(id)
		assert_bool(type.food).is_true()
		visits.append(type.visit_ticks())
		bases.append(type.base_spend)
		moods.append(type.mood_bonus)
	print("visit ticks %s, base spend %s, mood %s" % [visits, bases, moods])
	for i in range(1, VENUES.size()):
		assert_int(visits[i]).is_greater(visits[i - 1])
		assert_int(bases[i]).is_greater(bases[i - 1])
		# The same guest in the same mood pays more at each, on either side.
		for airside in [false, true]:
			var lower := CafeSim.spend(bases[i - 1], 50, airside, CafeVisit.Outcome.COMPLETE)
			var higher := CafeSim.spend(bases[i], 50, airside, CafeVisit.Outcome.COMPLETE)
			assert_int(higher).is_greater(lower)
	# Pinned values: the cafe keeps the numbers it always had.
	assert_array(visits).is_equal([30, 180, 280, 480])
	assert_array(bases).is_equal([8, 15, 24, 40])
	assert_int(RoomTypes.get_type(&"cafe").order_ticks).is_equal(CafeSim.ORDER_TICKS)
	assert_int(RoomTypes.get_type(&"cafe").dwell_ticks).is_equal(CafeSim.DWELL_TICKS)
	assert_int(RoomTypes.get_type(&"cafe").mood_bonus).is_equal(CafeSim.SERVED_MOOD_BONUS)
	# The bar lifts mood the most (the ruling says so).
	assert_int(moods[2]).is_equal(moods.max())
	assert_int(moods.count(moods.max())).is_equal(1)


func test_real_visits_take_longer_and_pay_more_up_the_ladder() -> void:
	var order: Array[int] = []
	var amount: Array[int] = []
	for id in VENUES:
		var seen := _measure(id)
		order.append(seen["order"])
		amount.append(seen["amount"])
		assert_int(seen["mood"]).is_equal(RoomTypes.get_type(id).mood_bonus)
	print("measured ticks from order to getting up %s, paid %s" % [order, amount])
	for i in range(1, VENUES.size()):
		assert_int(order[i]).is_greater(order[i - 1])
		assert_int(amount[i]).is_greater(amount[i - 1])
	# Exactly the order and the dwell, plus the walk to the seat.
	for i in VENUES.size():
		assert_int(order[i]).is_greater_equal(RoomTypes.get_type(VENUES[i]).visit_ticks())


func test_a_restaurant_is_refused_where_a_cafe_still_fits() -> void:
	# Two worlds, the same guest at the same tick: step to the first tick the
	# restaurant's whole visit no longer fits and the cafe's still does.
	var cafe_world := _world(&"cafe")
	var restaurant_world := _world(&"restaurant")
	var cafe_guest := cafe_world.passenger(cafe_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	var restaurant_guest := restaurant_world.passenger(
		restaurant_world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	)
	for guest in [cafe_guest, restaurant_guest]:
		guest.hunger = 0
		guest.cafe_cooldown = 1000000
	var refused_at := -1
	var was_admitted := false
	for i in 2000:
		cafe_world.step()
		restaurant_world.step()
		if not CafeSim.START_STAGES.has(restaurant_guest.stage):
			continue
		var restaurant_plan := restaurant_world.sim.cafes.plan_visit(restaurant_guest)
		if not restaurant_plan.is_empty():
			was_admitted = true
		elif was_admitted:
			refused_at = restaurant_world.clock.tick
			break
	assert_int(refused_at).is_greater(0)
	assert_int(cafe_guest.stage).is_equal(restaurant_guest.stage)
	var cafe_plan := cafe_world.sim.cafes.plan_visit(cafe_guest)
	print("restaurant refused at %d, cafe plan empty: %s" % [refused_at, cafe_plan.is_empty()])
	assert_bool(cafe_plan.is_empty()).is_false()
