class_name TestShopVisits
extends GdUnitTestSuite
## Kiosk visits (Boredom 2/5; decision boredom-and-shops-design-boredom-need-
## while-waiting-kiosk-sh, point 2): a bored passenger detours to the nearest
## free browse slot of a ready kiosk, browses there for ShopSim.BROWSE_TICKS
## and pays on completion (base spend nudged by mood, the airside bonus), which
## resets its boredom; there is no checkout queue. A visit reserves its slot
## from the commit on, so with every slot held the passenger carries on and
## tries again later. An interrupted browse pays nothing and leaves boredom as
## it was. A passenger with spare time walking past a kiosk drops in too.

var _world: PassengerTestWorld
var _ids: Dictionary
## Passenger id -> stage names in the order they were entered.
var _stages: Dictionary = {}
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
	_stages.clear()
	_paid.clear()


func _kiosk_world(sides: Array = ["air"], displays := 2) -> PassengerTestWorld:
	var grid := BuildGrid.new()
	_ids = ShopTestLayout.build(grid, sides, displays)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var sim := _world.sim
	sim.stage_changed.connect(
		func(id: int, stage: Passenger.Stage) -> void:
			if not _stages.has(id):
				_stages[id] = []
			_stages[id].append(Passenger.Stage.keys()[stage])
	)
	sim.shops.paid.connect(
		func(id: int, room: int, amount: int) -> void: _paid.append([id, room, amount])
	)
	# Staff come on duty on the first ticks.
	_world.run_to(10)
	return _world


func _run_while_visiting(p: Passenger, limit := 3000) -> void:
	var until := _world.clock.tick + limit
	while _world.sim.shops.visit_of(p.id) != null and _world.clock.tick < until:
		_world.step()


func test_a_bored_passenger_browses_a_slot_pays_and_goes_on_with_boredom_reset() -> void:
	_kiosk_world()
	var p := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
	p.mood = 60
	var balance := _world.sim.wallet.balance
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
	var visit := _world.sim.shops.visit_of(p.id)
	assert_object(visit).is_not_null()
	assert_int(visit.room).is_equal(_ids["air_room"])
	assert_bool((_ids["air_displays"] as Array).has(visit.display)).is_true()
	assert_int(visit.resume_stage).is_equal(Passenger.Stage.TO_GATE)
	assert_int(_world.sim.shops.slot_holder(visit.slot_key())).is_equal(p.id)
	assert_int(StageKinds.visit_facility(_world.sim, p)).is_equal(StageKinds.Facility.SHOP)
	assert_that(StageKinds.resume_of(_world.sim, p)["cell"]).is_equal(visit.slot["approach"])
	var browse_ticks := [0]
	var boredom_before_pay := [-1]
	var expected := ShopSim.spend(RoomTypes.get_type(&"kiosk").base_spend, p.mood, true)
	while _world.sim.shops.visit_of(p.id) != null and _world.clock.tick < 3000:
		if p.stage == Passenger.Stage.SHOP_BROWSE:
			boredom_before_pay[0] = p.boredom
		_world.step()
		if p.stage == Passenger.Stage.SHOP_BROWSE:
			browse_ticks[0] += 1
			assert_that(p.at).is_equal(visit.slot["approach"])
			assert_that(_world.sim.shops.browse_facing(p)).is_equal(Vector2i(0, -1))
	print(
		(
			"stages %s, browsed %d ticks, paid %s, boredom %d -> %d"
			% [_stages[p.id], browse_ticks[0], _paid, boredom_before_pay[0], p.boredom]
		)
	)
	assert_array((_stages[p.id] as Array).slice(0, 3)).is_equal(
		["SHOP_WALK", "SHOP_BROWSE", "TO_GATE"]
	)
	assert_int(browse_ticks[0]).is_equal(ShopSim.BROWSE_TICKS)
	assert_int(expected).is_greater(RoomTypes.get_type(&"kiosk").base_spend)
	assert_array(_paid).is_equal([[p.id, _ids["air_room"], expected]])
	assert_int(_world.sim.wallet.balance - balance).is_equal(expected)
	assert_int(boredom_before_pay[0]).is_equal(BoredomSim.MAX)
	assert_int(p.boredom).is_equal(0)
	assert_int(_world.sim.shops.slot_holder(visit.slot_key())).is_equal(0)
	# It goes on to the plane.
	var doors := _world.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	while not p.is_done() and _world.clock.tick <= doors:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)


func test_the_spend_is_the_base_nudged_by_mood_with_the_airside_bonus() -> void:
	var base := RoomTypes.get_type(&"kiosk").base_spend
	assert_int(base).is_greater(0)
	assert_int(ShopSim.spend(base, 50, false)).is_equal(base)
	assert_int(ShopSim.spend(base, 0, false)).is_less(base)
	assert_int(ShopSim.spend(base, 100, false)).is_greater(base)
	assert_int(ShopSim.spend(base, 50, true)).is_greater(base)


func test_with_every_slot_held_a_bored_passenger_carries_on_and_retries_later() -> void:
	_kiosk_world(["air"], 1)
	var first := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
	var second := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
	var third := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
	assert_int(NeedsPolicy.arbitrate(_world.sim, first)).is_equal(NeedsPolicy.Need.BOREDOM)
	assert_int(NeedsPolicy.arbitrate(_world.sim, second)).is_equal(NeedsPolicy.Need.BOREDOM)
	# One display, two slots, both held.
	assert_int(NeedsPolicy.arbitrate(_world.sim, third)).is_equal(NeedsPolicy.Need.NONE)
	assert_object(_world.sim.shops.visit_of(third.id)).is_null()
	assert_int(third.shop_cooldown).is_equal(_world.clock.tick + ShopSim.RETRY_TICKS)
	assert_bool(_world.sim.shops.wants_relief(third)).is_false()
	_world.run_to(third.shop_cooldown)
	assert_bool(_world.sim.shops.wants_relief(third)).is_true()


func test_an_interrupted_browse_pays_nothing_and_leaves_boredom_as_it_was() -> void:
	_kiosk_world(["air"], 1)
	var p := ShopTestLayout.airside_guest(_world, 80)
	var balance := _world.sim.wallet.balance
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
	var until := _world.clock.tick + 2000
	while p.stage != Passenger.Stage.SHOP_BROWSE and _world.clock.tick < until:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_BROWSE)
	_world.run_to(_world.clock.tick + ShopSim.BROWSE_TICKS / 2)
	var display: int = (_ids["air_displays"] as Array)[0]
	assert_bool(_world.grid.apply(BuildEdit.remove_object(display)).ok).is_true()
	_world.step()
	print("after removal: stage %s, boredom %d, paid %s" % [p.stage, p.boredom, _paid])
	assert_object(_world.sim.shops.visit_of(p.id)).is_null()
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
	assert_array(_paid).is_empty()
	assert_int(_world.sim.wallet.balance).is_equal(balance)
	assert_int(p.boredom).is_equal(80)


func test_past_its_deadline_a_browser_leaves_unpaid() -> void:
	_kiosk_world()
	var p := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
	var until := _world.clock.tick + 2000
	while p.stage != Passenger.Stage.SHOP_BROWSE and _world.clock.tick < until:
		_world.step()
	var visit := _world.sim.shops.visit_of(p.id)
	visit.deadline = _world.clock.tick + 1
	_world.step()
	print("left at %d, deadline %d, paid %s" % [_world.clock.tick, visit.deadline, _paid])
	assert_object(_world.sim.shops.visit_of(p.id)).is_null()
	assert_array(_paid).is_empty()
	assert_int(p.boredom).is_equal(BoredomSim.MAX)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)


func test_a_landside_passenger_uses_the_landside_kiosk_and_goes_on_to_security() -> void:
	_kiosk_world(["air", "land"])
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.stage = Passenger.Stage.TO_SECURITY
	p.stage_tick = _world.clock.tick
	p.at = Vector2i(20, 14)
	p.clear_path()
	p.boredom = BoredomSim.MAX
	p.shop_cooldown = 0
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
	var visit := _world.sim.shops.visit_of(p.id)
	assert_int(visit.room).is_equal(_ids["land_room"])
	assert_int(visit.resume_stage).is_equal(Passenger.Stage.TO_SECURITY)
	_run_while_visiting(p)
	var base := RoomTypes.get_type(&"kiosk").base_spend
	assert_array(_paid).is_equal([[p.id, _ids["land_room"], ShopSim.spend(base, p.mood, false)]])
	assert_int(p.stage).is_equal(Passenger.Stage.TO_SECURITY)


func test_a_passenger_with_spare_time_walking_past_a_kiosk_drops_in() -> void:
	_kiosk_world()
	var p := ShopTestLayout.airside_guest(_world, 0, Vector2i(19, 5))
	# Walking east along the airside floor, past the kiosk's door.
	p.set_path(_world.grid.find_path(p.at, Vector2i(21, 5)))
	assert_bool(p.is_moving()).is_true()
	assert_bool(_world.sim.shops.wants_relief(p)).is_false()
	assert_bool(_world.sim.shops.wants_browse(p)).is_true()
	var choice := NeedsPolicy.choose(_world.sim, p)
	assert_int(choice["need"]).is_equal(NeedsPolicy.Need.SHOP_BROWSE)
	NeedsPolicy.arbitrate(_world.sim, p)
	_run_while_visiting(p)
	print("browser stages %s paid %s" % [_stages[p.id], _paid])
	assert_int(_paid.size()).is_equal(1)
	assert_int(p.shop_cooldown).is_equal(_world.clock.tick + ShopSim.BROWSE_COOLDOWN_TICKS)
	# Calm and not walking: no browse.
	var still := ShopTestLayout.airside_guest(_world, 0, Vector2i(19, 5))
	assert_bool(_world.sim.shops.wants_browse(still)).is_false()


func test_a_kiosk_that_is_not_ready_gives_no_visit() -> void:
	_kiosk_world()
	assert_bool(_world.grid.apply(BuildEdit.remove_object(_ids["air_counter"])).ok).is_true()
	_world.step()
	var p := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
	assert_dict(_world.sim.shops.plan_visit(p)).is_empty()
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.NONE)
