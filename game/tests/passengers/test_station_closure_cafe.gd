class_name TestStationClosureCafe
extends GdUnitTestSuite
## The player closes a cafe counter (StationClosures; decision
## select-placed-items-design-click-order-gold-footprint-highli): it takes no
## new order at once, the cafe's own path sends the rest of its queue away
## unpaid, the order in progress is made, and then the server goes idle where
## it stood instead of walking out. A closed counter shows the "Closed by you"
## sign, and a template pasted from its room places an open counter.

const SHOP := StaffMember.Role.SHOP

var _world: PassengerTestWorld
var _ids: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new()
	_ids = CafeTestLayout.build(grid, true)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(1500, 4000))
	_world.auto_staff_roles = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]


func after_test() -> void:
	_world.free_all()
	_world = null


func _cafes() -> CafeSim:
	return _world.sim.cafes


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


func test_closing_a_counter_mid_order_finishes_it_and_frees_the_server() -> void:
	var counter: int = _ids["air_counter"]
	var server := _world.staff.get_member(StaffTestKit.seat_server(_world.staff, counter))
	var guests := _visit_from_gate(3)
	while _cafes().serving_at(counter) == 0 and _world.clock.tick < 1400:
		_world.step()
	var ordering := _world.passenger(_cafes().serving_at(counter))
	var queued := guests.filter(func(g: Passenger) -> bool: return g != ordering)
	assert_int(queued.size()).is_equal(2)
	var balance := _world.sim.wallet.balance
	var seen: Array = []
	_world.staff.member_state_changed.connect(
		func(id: int, state: StaffMember.State) -> void:
			if id == server.id:
				seen.append([state, server.at, server.station])
	)
	assert_bool(_world.staff.closures.set_closed(counter, true)).is_true()
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
	assert_str(_world.staff.closures.status_text(counter)).is_equal("Finishing current service")
	while ordering.stage == Passenger.Stage.CAFE_ORDER and _world.clock.tick < 1400:
		assert_int(server.state).is_equal(StaffMember.State.ON_DUTY)
		_world.step()
	assert_int(ordering.stage).is_equal(Passenger.Stage.CAFE_TO_SEAT)
	assert_bool(_cafes().visit_of(ordering.id).served).is_true()
	var spot := _world.staff.spot_of(counter)
	_world.step()
	print("server %d went %s, spot %s" % [server.id, seen, spot])
	# Idle where it stood, not walking out; the pass then sends it to the
	# landside counter, which has nobody.
	assert_that(seen[0]).is_equal([StaffMember.State.IDLE, spot, 0])
	assert_int(server.state).is_not_equal(StaffMember.State.WALKING_OUT)
	assert_int(server.station).is_equal(int(_ids["land_counter"]))
	assert_int(_world.staff.count(SHOP)).is_equal(1)
	assert_int(_cafes().serving_at(counter)).is_equal(0)
	# No new order: a hungry guest plans no visit to the closed counter.
	var p := _spawn()
	while p.stage != Passenger.Stage.TO_GATE and _world.clock.tick < 1400:
		_world.step()
	var closed_plan := _cafes().plan_visit(p)
	# Control: the same guest plans a visit there once a server is on duty and
	# the counter is open again.
	StaffTestKit.seat_server(_world.staff, counter)
	var still_closed := _cafes().plan_visit(p)
	_world.staff.closures.set_closed(counter, false)
	var open_plan := _cafes().plan_visit(p)
	print(
		(
			"plans: closed %s, staffed but closed %s, open %s"
			% [
				closed_plan.is_empty(),
				still_closed.is_empty(),
				open_plan.get("counter", {}).get("id", 0)
			]
		)
	)
	assert_bool(closed_plan.is_empty()).is_true()
	assert_bool(still_closed.is_empty()).is_true()
	assert_int(int(open_plan["counter"]["id"])).is_equal(counter)


func test_a_closed_counter_shows_closed_by_you_and_a_pasted_copy_is_open() -> void:
	var counter: int = _ids["air_counter"]
	StaffTestKit.seat_server(_world.staff, counter)
	assert_array(ShopCounters.closed(_world.sim)).not_contains([counter])
	_world.staff.closures.set_closed(counter, true)
	print(
		(
			"closed counters %s, reason '%s'"
			% [ShopCounters.closed(_world.sim), MissSignals.staff_reason(_world.sim, counter)]
		)
	)
	assert_array(ShopCounters.closed(_world.sim)).contains([counter])
	assert_str(MissSignals.staff_reason(_world.sim, counter)).is_equal("Closed by you")
	var template := RoomTemplate.capture(_world.grid, _ids["air_room"])
	var before := _world.grid.object_ids()
	for result in _world.grid.apply_batch(template.plan(Vector2i(40, 30), 0, _world.grid)):
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	var pasted := 0
	for id in _world.grid.object_ids():
		if not before.has(id) and _world.grid.get_object(id)["def"] == &"cafe_counter":
			pasted = id
	print(
		(
			"pasted counter %d closed %s; original closed %s"
			% [
				pasted,
				_world.staff.closures.is_closed(pasted),
				_world.staff.closures.is_closed(counter)
			]
		)
	)
	assert_int(pasted).is_greater(counter)
	assert_bool(_world.staff.closures.is_closed(pasted)).is_false()
	assert_bool(_world.staff.closures.is_closed(counter)).is_true()
