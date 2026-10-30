class_name TestActivityAdmission
extends GdUnitTestSuite
## An activity or rest room admits a passenger only when the whole stay fits
## the lateness forecast, and the passenger it admits still makes the flight
## (F4-7; decision food-and-drink-cafe-bar-sit-down-restaurant-and-grab-and-go-
## st, point 2). The stay is the room type's own dwell, so the last tick a
## guest is admitted is the deadline less the walk and the dwell, and a longer
## stay has an earlier last tick. Nothing sets a deadline by hand.

var _worlds: Array[PassengerTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in _worlds:
		world.free_all()
	_worlds.clear()


func _world_of(type: StringName) -> PassengerTestWorld:
	var grid := BuildGrid.new()
	ActivityTestLayout.build(grid, type)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	world.auto_staff_roles = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]
	world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	_worlds.append(world)
	return world


## The plan a fresh airside guest of `world` would get now, or empty. The guest
## is parked (no visit of its own) afterwards.
func _plan_now(world: PassengerTestWorld) -> Dictionary:
	var p := ShopTestLayout.airside_guest(world, 40)
	var plan := world.sim.shops.plan_visit(p)
	p.shop_cooldown = 1000000
	return plan


## The last tick a guest at the airside cell is admitted to `type`, worked out
## from the deadline a probe guest would leave the slot by.
func _last_start(world: PassengerTestWorld, type: StringName) -> int:
	var probe := ShopTestLayout.airside_guest(world, 40)
	var plan := world.sim.shops.plan_visit(probe)
	assert_bool(plan.is_empty()).override_failure_message(str(type)).is_false()
	probe.shop_cooldown = 1000000
	var slot: Dictionary = plan["slot"]
	var deadline := VisitForecast.deadline(
		world.sim, probe, slot["approach"], 0, Passenger.Stage.TO_GATE
	)
	var stay := (
		JourneyForecast.walk_ticks(plan["route"]["mm"])
		+ ShopSim.ARRIVE_TICKS
		+ RoomTypes.get_type(type).dwell_ticks
	)
	return deadline - stay


func test_a_guest_is_admitted_up_to_the_last_tick_the_whole_stay_fits_and_not_after() -> void:
	var last := {}
	for type in ActivityTestLayout.TYPES:
		var world := _world_of(type)
		world.run_to(10)
		last[type] = _last_start(world, type)
		world.run_to(last[type])
		var fits := not _plan_now(world).is_empty()
		world.step()
		var later := _plan_now(world)
		print(
			(
				"%s: last admitted tick %d (fits %s), next tick refused %s"
				% [type, last[type], fits, later.is_empty()]
			)
		)
		assert_bool(fits).override_failure_message("%s at its last tick" % type).is_true()
		assert_bool(later.is_empty()).override_failure_message("%s a tick later" % type).is_true()
	# A longer stay has an earlier last tick: the dwell is what the forecast counts.
	assert_int(last[&"nap_pod"]).is_less(last[&"lounge"])
	assert_int(last[&"lounge"]).is_less(last[&"shower"])
	assert_int(last[&"shower"]).is_less(last[&"play_area"])


func test_a_guest_admitted_on_the_last_tick_still_makes_the_flight() -> void:
	for type in ActivityTestLayout.TYPES:
		var world := _world_of(type)
		world.run_to(10)
		var start := _last_start(world, type)
		world.run_to(start)
		var outcome := {}
		world.sim.outcome.connect(func(id: int, made: bool) -> void: outcome[id] = made)
		var p := ShopTestLayout.airside_guest(world, BoredomSim.MAX)
		assert_int(NeedsPolicy.arbitrate(world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
		var visit := world.sim.shops.visit_of(p.id)
		assert_object(visit).override_failure_message(str(type)).is_not_null()
		var until := world.clock.tick + 6000
		while not outcome.has(p.id) and world.clock.tick < until:
			world.step()
		print(
			(
				"%s: admitted at %d, outcome made=%s at %d"
				% [type, start, outcome.get(p.id), world.clock.tick]
			)
		)
		assert_bool(outcome.get(p.id, false)).override_failure_message(str(type)).is_true()
		assert_int(p.boredom).is_equal(0)
