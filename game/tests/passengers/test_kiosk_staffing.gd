class_name TestKioskStaffing
extends GdUnitTestSuite
## A kiosk is open only while a shop server is on duty at one of its counters
## (ruling store-mechanics-draw-a-room-then-furnish-it-required-pieces, point
## 3): with nobody there no visit is planned. When it closes, a passenger still
## walking to a browse slot gives up, unpaid; one already browsing finishes and
## pays (decision firing-a-staff-member-mid-service-takes-effect-when-the-serv:
## the service under way ends first).

const SHOP := StaffMember.Role.SHOP

var _world: PassengerTestWorld
var _ids: Dictionary
## Every ShopSim.paid emission, as [passenger id, room id, amount].
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


## The airside kiosk with desks and scanners staffed and nobody at its counter.
func _make() -> void:
	var grid := BuildGrid.new()
	_ids = ShopTestLayout.build(grid, ["air"])
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.auto_staff_roles = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]
	_world.sim.shops.paid.connect(
		func(id: int, room: int, amount: int) -> void: _paid.append([id, room, amount])
	)
	_world.run_to(10)


func _shops() -> ShopSim:
	return _world.sim.shops


func _bored_guest() -> Passenger:
	return ShopTestLayout.airside_guest(_world, BoredomSim.BORED_AT)


func test_with_no_server_a_kiosk_plans_no_visit_and_with_one_it_does() -> void:
	_make()
	var p := _bored_guest()
	assert_bool(_shops().plan_visit(p).is_empty()).is_true()
	StaffTestKit.seat_server(_world.staff, _ids["air_counter"])
	var plan := _shops().plan_visit(p)
	assert_bool(plan.is_empty()).is_false()
	assert_int(plan["slot"]["room"]).is_equal(_ids["air_room"])


func test_a_passenger_walking_to_a_kiosk_that_closes_gives_up_unpaid() -> void:
	_make()
	StaffTestKit.seat_server(_world.staff, _ids["air_counter"])
	var p := _bored_guest()
	_shops().commit_visit(p, _shops().plan_visit(p))
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_WALK)
	assert_bool(_world.staff.fire(SHOP)).is_true()
	_world.step()
	print("stage %d visit %s paid %s" % [p.stage, _shops().visit_of(p.id), _paid])
	assert_object(_shops().visit_of(p.id)).is_null()
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
	assert_int(p.boredom).is_greater_equal(BoredomSim.BORED_AT)
	assert_array(_paid).is_empty()


func test_a_passenger_browsing_when_the_kiosk_closes_finishes_and_pays() -> void:
	_make()
	StaffTestKit.seat_server(_world.staff, _ids["air_counter"])
	var p := _bored_guest()
	_shops().commit_visit(p, _shops().plan_visit(p))
	while p.stage != Passenger.Stage.SHOP_BROWSE and _world.clock.tick < 600:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_BROWSE)
	assert_bool(_world.staff.fire(SHOP)).is_true()
	assert_bool(ShopCounters.room_open(_world.sim, _ids["air_room"])).is_false()
	while _shops().visit_of(p.id) != null and _world.clock.tick < 1200:
		_world.step()
	print("paid %s" % [_paid])
	assert_int(_paid.size()).is_equal(1)
	assert_int(_paid[0][0]).is_equal(p.id)
	assert_int(p.boredom).is_equal(0)


func test_a_kiosk_with_a_server_at_any_of_its_counters_is_open() -> void:
	_make()
	assert_bool(ShopCounters.room_open(_world.sim, _ids["air_room"])).is_false()
	StaffTestKit.seat_server(_world.staff, _ids["air_counter"])
	assert_bool(ShopCounters.room_open(_world.sim, _ids["air_room"])).is_true()
