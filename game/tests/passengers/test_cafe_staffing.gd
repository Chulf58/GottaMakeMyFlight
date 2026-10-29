class_name TestCafeStaffing
extends GdUnitTestSuite
## A cafe counter serves only while a shop server is on duty at it
## (StaffSim.is_open(); ruling store-mechanics-draw-a-room-then-furnish-it-
## required-pieces, point 3). With nobody there no visit is planned. A server
## fired while a guest is ordering stays until that order is made (decision
## firing-a-staff-member-mid-service-takes-effect-when-the-serv); meanwhile the
## counter takes nobody new and the rest of its queue gives up, unpaid.

const SHOP := StaffMember.Role.SHOP

var _world: PassengerTestWorld
var _ids: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


## The two cafes, a roomy flight, desks and scanners staffed and the counters
## only when `servers`.
func _make(servers: bool) -> void:
	var grid := BuildGrid.new()
	_ids = CafeTestLayout.build(grid, true)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(1500, 4000))
	if not servers:
		_world.auto_staff_roles = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]


func _cafes() -> CafeSim:
	return _world.sim.cafes


## A passenger who never starts a visit by itself, run until it heads for the
## gate.
func _to_gate() -> Passenger:
	var p := _spawn()
	while p.stage != Passenger.Stage.TO_GATE and _world.clock.tick < 900:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
	return p


func _spawn() -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 0
	p.cafe_cooldown = 1000000
	return p


## Spawns `count` passengers at once and starts a visit for each the tick it
## heads for the gate; returns them in the order their visits started.
func _visit_from_gate(count: int) -> Array[Passenger]:
	var waiting: Array[Passenger] = []
	for i in count:
		waiting.append(_spawn())
	var started: Array[Passenger] = []
	while not waiting.is_empty() and _world.clock.tick < 900:
		_world.step()
		for p in waiting.duplicate():
			if p.stage == Passenger.Stage.TO_GATE:
				waiting.erase(p)
				assert_bool(_cafes().try_visit(p)).is_true()
				started.append(p)
	assert_int(started.size()).is_equal(count)
	return started


func test_with_no_server_a_cafe_plans_no_visit_and_with_one_it_does() -> void:
	_make(false)
	var p := _to_gate()
	assert_bool(_world.staff.is_open(_ids["air_counter"])).is_false()
	assert_bool(_cafes().plan_visit(p).is_empty()).is_true()
	StaffTestKit.seat_server(_world.staff, _ids["air_counter"])
	var plan := _cafes().plan_visit(p)
	print("plan counter %s" % [plan.get("counter", {}).get("id", 0)])
	assert_int(plan["counter"]["id"]).is_equal(_ids["air_counter"])


func test_a_passenger_skips_the_nearer_unstaffed_counter_for_a_staffed_one() -> void:
	_make(false)
	var p := _to_gate()
	StaffTestKit.seat_server(_world.staff, _ids["air_counter"])
	assert_int(_cafes().plan_visit(p)["counter"]["id"]).is_equal(_ids["air_counter"])
	assert_bool(_world.staff.fire(StaffMember.Role.SHOP)).is_true()
	StaffTestKit.seat_server(_world.staff, _ids["land_counter"])
	# The staff door in the divider lets the airside passenger reach the
	# landside cafe, the only one with a server now.
	assert_int(_cafes().plan_visit(p)["counter"]["id"]).is_equal(_ids["land_counter"])


func test_a_server_fired_mid_order_stays_until_the_order_is_made() -> void:
	_make(false)
	var counter: int = _ids["air_counter"]
	var server := _world.staff.get_member(StaffTestKit.seat_server(_world.staff, counter))
	var guests := _visit_from_gate(3)
	while _cafes().serving_at(counter) == 0 and _world.clock.tick < 1400:
		_world.step()
	var ordering := _world.passenger(_cafes().serving_at(counter))
	var queued := guests.filter(func(g: Passenger) -> bool: return g != ordering)
	var balance := _world.sim.wallet.balance
	assert_bool(_world.staff.fire(SHOP)).is_true()
	assert_bool(server.leaving).is_true()
	assert_bool(_world.staff.is_open(counter)).is_false()
	_world.step()
	print(
		"ordering %d stage %d queue %s" % [ordering.id, ordering.stage, _cafes().queue_of(counter)]
	)
	assert_array(_cafes().queue_of(counter)).is_equal([ordering.id])
	for g: Passenger in queued:
		assert_object(_cafes().visit_of(g.id)).is_null()
		assert_int(g.stage).is_in([Passenger.Stage.TO_GATE, Passenger.Stage.TO_EXIT])
	assert_int(_world.sim.wallet.balance).is_equal(balance)
	while ordering.stage == Passenger.Stage.CAFE_ORDER and _world.clock.tick < 1400:
		assert_int(server.state).is_equal(StaffMember.State.ON_DUTY)
		_world.step()
	assert_int(ordering.stage).is_equal(Passenger.Stage.CAFE_TO_SEAT)
	assert_bool(_cafes().visit_of(ordering.id).served).is_true()
	_world.step()
	assert_int(server.state).is_equal(StaffMember.State.WALKING_OUT)
	assert_int(_cafes().serving_at(counter)).is_equal(0)


func test_firing_the_last_server_turns_new_guests_away() -> void:
	_make(false)
	StaffTestKit.seat_server(_world.staff, _ids["air_counter"])
	var p := _to_gate()
	assert_bool(_cafes().plan_visit(p).is_empty()).is_false()
	assert_bool(_world.staff.fire(SHOP)).is_true()
	assert_bool(_cafes().plan_visit(p).is_empty()).is_true()
