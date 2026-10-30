class_name TestActivityVisits
extends GdUnitTestSuite
## Visits to the play area, the lounge, the shower and the nap pod (F4-7;
## decisions furniture-set-modelled-on-copenhagen-airport-decor-calms-pas and
## food-and-drink-cafe-bar-sit-down-restaurant-and-grab-and-go-st, point 3): a
## bored passenger stays at the piece for the room type's dwell, its boredom is
## reset and it gains the type's mood bonus. The shower and the nap pod charge
## their fee through ShopSim.spend(); the play area and the lounge are free and
## credit nothing. Cap, wish and the three-way pay are covered here too.

var _world: PassengerTestWorld
var _ids: Dictionary
## [passenger id, room id, amount] per paid signal.
var _paid: Array = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	_free()


func _free() -> void:
	if _world != null:
		_world.free_all()
		_world = null
	_paid.clear()


func _activity_world(type: StringName) -> void:
	var grid := BuildGrid.new()
	_ids = ActivityTestLayout.build(grid, type)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	# Nobody has a shopping wish unless a test pins one.
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	_world.sim.shops.paid.connect(
		func(id: int, room: int, amount: int) -> void: _paid.append([id, room, amount])
	)
	# No staff are needed: the room is self-service.
	_world.auto_staff_roles = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]
	_world.run_to(10)


func _run_while_visiting(p: Passenger, limit := 3000) -> void:
	var until := _world.clock.tick + limit
	while _world.sim.shops.visit_of(p.id) != null and _world.clock.tick < until:
		_world.step()


func test_each_piece_lowers_boredom_and_gives_its_mood_bonus_after_its_own_dwell() -> void:
	for type in ActivityTestLayout.TYPES:
		_activity_world(type)
		var room_type := RoomTypes.get_type(type)
		var p := ShopTestLayout.airside_guest(_world, 80)
		p.mood = 50
		assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
		var visit := _world.sim.shops.visit_of(p.id)
		assert_object(visit).override_failure_message(str(type)).is_not_null()
		assert_int(visit.room).is_equal(_ids["room"])
		assert_int(visit.display).is_equal(_ids["use"])
		var committed := _world.clock.tick
		var walk := JourneyForecast.walk_ticks(p.remaining_mm())
		_run_while_visiting(p)
		var took := _world.clock.tick - committed
		print("%s: boredom 80 -> %d, mood 50 -> %d, took %d" % [type, p.boredom, p.mood, took])
		assert_int(p.boredom).override_failure_message(str(type)).is_equal(0)
		assert_int(p.mood).override_failure_message(str(type)).is_equal(50 + room_type.mood_bonus)
		assert_int(took).is_equal(walk + ShopSim.ARRIVE_TICKS + room_type.dwell_ticks)
		assert_int(took).is_greater(ShopSim.BROWSE_TICKS)
		assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
		_free()


func test_the_mood_bonus_is_capped_at_the_most_a_passenger_can_have() -> void:
	_activity_world(&"nap_pod")
	var p := ShopTestLayout.airside_guest(_world, 80)
	p.mood = PassengerSim.MOOD_MAX - 1
	NeedsPolicy.arbitrate(_world.sim, p)
	_run_while_visiting(p)
	assert_int(p.mood).is_equal(PassengerSim.MOOD_MAX)


func test_showers_and_nap_pods_charge_their_fee_and_the_play_area_and_lounge_do_not() -> void:
	var fees := {
		&"play_area": 0,
		&"lounge": 0,
		&"shower": PriceTable.SHOWER_FEE,
		&"nap_pod": PriceTable.NAP_POD_FEE
	}
	for type in ActivityTestLayout.TYPES:
		_activity_world(type)
		var p := ShopTestLayout.airside_guest(_world, 80)
		p.mood = 50
		var balance := _world.sim.wallet.balance
		NeedsPolicy.arbitrate(_world.sim, p)
		_run_while_visiting(p)
		var charged := _world.sim.wallet.balance - balance
		print("%s: fee %d, charged %d, paid signals %s" % [type, fees[type], charged, _paid])
		assert_int(RoomTypes.get_type(type).base_spend).is_equal(fees[type])
		if fees[type] > 0:
			var expected := ShopSim.spend(fees[type], 50, true)
			assert_int(expected).is_greater(0)
			assert_int(charged).override_failure_message(str(type)).is_equal(expected)
			assert_array(_paid).is_equal([[p.id, _ids["room"], expected]])
		else:
			# Control: the visit did happen (boredom reset) and credited nothing.
			assert_int(p.boredom).override_failure_message(str(type)).is_equal(0)
			assert_int(charged).override_failure_message(str(type)).is_equal(0)
			assert_array(_paid).is_empty()
		_free()


func test_a_wisher_takes_an_activity_room_with_no_fallback_penalty() -> void:
	_activity_world(&"lounge")
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return &"duty_free"
	var p := ShopTestLayout.airside_guest(_world, 80)
	p.mood = 50
	var plan := _world.sim.shops.plan_visit(p)
	# The only relief shop is the lounge, which is no substitute for duty free:
	# it is not a fallback, so it costs no mood and the visit pays the bonus.
	assert_bool(plan.is_empty()).is_false()
	assert_bool(plan["fallback"]).is_false()
	NeedsPolicy.arbitrate(_world.sim, p)
	_run_while_visiting(p)
	assert_int(p.mood).is_equal(50 + RoomTypes.get_type(&"lounge").mood_bonus)


func test_an_unfinished_visit_gives_no_mood_bonus() -> void:
	_activity_world(&"shower")
	var p := ShopTestLayout.airside_guest(_world, 80)
	p.mood = 50
	NeedsPolicy.arbitrate(_world.sim, p)
	var until := _world.clock.tick + 2000
	while p.stage != Passenger.Stage.SHOP_BROWSE and _world.clock.tick < until:
		_world.step()
	var visit := _world.sim.shops.visit_of(p.id)
	visit.deadline = _world.clock.tick + 1
	_world.step()
	assert_object(_world.sim.shops.visit_of(p.id)).is_null()
	assert_int(p.mood).is_equal(50)
	assert_int(p.boredom).is_greater_equal(80)
	assert_array(_paid).is_empty()
