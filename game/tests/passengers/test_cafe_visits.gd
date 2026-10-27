class_name TestCafeVisits
extends GdUnitTestSuite
## Cafe queues, seat reservations, the visit's stages and cleanup (decision
## cafe-visit-design-forecast-the-whole-itinerary-abandon-by-a, points 2-4, 8
## and 9), landside and airside, in the reference terminal with two cafes.

const VISIT_STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.CAFE_WALK,
	Passenger.Stage.CAFE_QUEUE,
	Passenger.Stage.CAFE_ORDER,
	Passenger.Stage.CAFE_TO_SEAT,
	Passenger.Stage.CAFE_SITTING_DOWN,
	Passenger.Stage.CAFE_SEATED,
	Passenger.Stage.CAFE_STANDING_UP,
]

var _world: PassengerTestWorld
var _ids: Dictionary
## Passenger id -> stages entered, in order.
var _stages: Dictionary = {}


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null
	_stages.clear()


## The default flight, or with `roomy` one that boards at 1500 and closes at
## 4000, so several guests fit in a visit before it.
func _make(extra_tables := false, roomy := false) -> void:
	var grid := BuildGrid.new()
	_ids = CafeTestLayout.build(grid, extra_tables)
	var starts := FlightSim.schedule_starts(0)
	if roomy:
		starts = PassengerTestWorld.starts_with(1500, 4000)
	_world = PassengerTestWorld.make(grid, starts)
	_world.sim.stage_changed.connect(_on_stage)


func _on_stage(id: int, stage: Passenger.Stage) -> void:
	if not _stages.has(id):
		_stages[id] = []
	(_stages[id] as Array).append(stage)


func _cafes() -> CafeSim:
	return _world.sim.cafes


## Spawns a passenger and runs until it reaches `stage` (or `limit`).
func _spawn_to(stage: Passenger.Stage, limit := 900) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while p.stage != stage and _world.clock.tick < limit:
		_world.step()
	assert_int(p.stage).is_equal(stage)
	return p


## Spawns `count` passengers at once and starts a visit for each the tick it
## heads for the gate. Returns those whose visit started, in that order.
func _visit_from_gate(count: int) -> Array[Passenger]:
	var waiting: Array[Passenger] = []
	for i in count:
		waiting.append(_world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT)))
	var started: Array[Passenger] = []
	while not waiting.is_empty() and _world.clock.tick < 600:
		_world.step()
		for p in waiting.duplicate():
			if p.stage == Passenger.Stage.TO_GATE:
				waiting.erase(p)
				if _cafes().try_visit(p):
					started.append(p)
	return started


func _run_until_resumed(p: Passenger, limit: int) -> void:
	while _cafes().visit_of(p.id) != null and _world.clock.tick < limit:
		_world.step()


func _visit_stages(id: int) -> Array:
	var out := []
	for stage in _stages.get(id, []):
		if VISIT_STAGES.has(stage) and (out.is_empty() or out.back() != stage):
			out.append(stage)
	return out


func test_both_cafes_are_usable_with_a_lane_and_two_seats() -> void:
	_make()
	_cafes().refresh()
	var layout := _cafes().layout
	assert_int(layout.cafes.size()).is_equal(2)
	for room in [_ids["air_room"], _ids["land_room"]]:
		var cafe := layout.cafe(room)
		assert_int((cafe["counters"] as Array).size()).is_equal(1)
		assert_int((cafe["counters"][0]["lane"] as Array).size()).is_equal(CafeLayout.LANE_SLOTS)
		assert_int((cafe["seats"] as Array).size()).is_equal(2)
	var air_lane: Array = layout.cafe(_ids["air_room"])["counters"][0]["lane"]
	assert_vector(air_lane[0]).is_equal(CafeTestLayout.AIR_COUNTER + Vector2i(0, 1))
	_world.grid.apply(BuildEdit.remove_object(_ids["air_table"]))
	_cafes().refresh()
	assert_bool(layout.cafe(_ids["air_room"]).is_empty()).is_true()
	assert_int(layout.cafes.size()).is_equal(1)


func test_an_airside_visit_runs_every_stage_and_resumes_to_the_gate() -> void:
	_make()
	var p := _spawn_to(Passenger.Stage.TO_GATE)
	assert_bool(_cafes().try_visit(p)).is_true()
	var visit := _cafes().visit_of(p.id)
	assert_int(visit.room).is_equal(_ids["air_room"])
	assert_int(visit.resume_stage).is_equal(Passenger.Stage.TO_GATE)
	assert_int(_cafes().seat_holder(visit.seat_key)).is_equal(p.id)
	assert_array(_cafes().queue_of(_ids["air_counter"])).is_equal([p.id])
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_WALK)
	var started := _world.clock.tick
	_run_until_resumed(p, 1400)
	print("visit %d..%d stages %s" % [started, _world.clock.tick, _visit_stages(p.id)])
	assert_array(_visit_stages(p.id)).is_equal(VISIT_STAGES)
	assert_int(visit.outcome).is_equal(CafeVisit.Outcome.COMPLETE)
	# Back to the gate, or straight on to the exit once boarding has started.
	assert_int(p.stage).is_in([Passenger.Stage.TO_GATE, Passenger.Stage.TO_EXIT])
	assert_int(_cafes().seat_holder(visit.seat_key)).is_equal(0)
	assert_array(_cafes().queue_of(_ids["air_counter"])).is_empty()
	_world.run_to(1900)
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)


func test_a_landside_visit_starts_after_check_in_and_resumes_to_security() -> void:
	_make()
	var p := _spawn_to(Passenger.Stage.TO_SECURITY)
	assert_bool(_cafes().try_visit(p)).is_true()
	assert_int(_cafes().visit_of(p.id).room).is_equal(_ids["land_room"])
	assert_int(p.station).is_equal(0)
	_run_until_resumed(p, 1400)
	assert_array(_visit_stages(p.id)).is_equal(VISIT_STAGES)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_SECURITY)
	assert_bool(p.cleared).is_false()
	_world.run_to(1900)
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)


func test_a_seated_gate_passenger_stands_up_first_and_frees_its_gate_seat() -> void:
	_make()
	var p := _spawn_to(Passenger.Stage.SEATED)
	var gate_seat := p.seat_object
	assert_int(gate_seat).is_not_equal(0)
	assert_bool(_cafes().try_visit(p)).is_true()
	assert_int(p.stage).is_equal(Passenger.Stage.STANDING_UP)
	for i in PassengerSim.STAND_UP_TICKS + 1:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_WALK)
	assert_int(p.seat_object).is_equal(0)
	_run_until_resumed(p, 1400)
	assert_array(_visit_stages(p.id)).is_equal(VISIT_STAGES)
	assert_int(p.stage).is_in([Passenger.Stage.TO_GATE, Passenger.Stage.TO_EXIT])


func test_guests_are_served_in_the_order_they_joined_the_queue() -> void:
	_make(true, true)
	var guests := _visit_from_gate(3)
	assert_int(guests.size()).is_equal(3)
	var ids := guests.map(func(g: Passenger) -> int: return g.id)
	assert_array(_cafes().queue_of(_ids["air_counter"])).is_equal(ids)
	var order := []
	while order.size() < 3 and _world.clock.tick < 1400:
		_world.step()
		var serving := _cafes().serving_at(_ids["air_counter"])
		if serving != 0 and not order.has(serving):
			order.append(serving)
	assert_array(order).is_equal(ids)


func test_each_guest_reserves_its_own_seat_and_a_full_cafe_refuses() -> void:
	_make(false, true)
	var guests := _visit_from_gate(2)
	assert_int(guests.size()).is_equal(2)
	var a: Passenger = guests[0]
	var b: Passenger = guests[1]
	assert_str(_cafes().visit_of(a.id).seat_key).is_not_equal(_cafes().visit_of(b.id).seat_key)
	# Two seats in the airside cafe, and the landside one cannot be reached.
	var c := _spawn_to(Passenger.Stage.TO_GATE)
	assert_bool(_cafes().visit_of(a.id) != null and _cafes().visit_of(b.id) != null).is_true()
	assert_bool(_cafes().try_visit(c)).is_false()
	assert_object(_cafes().visit_of(c.id)).is_null()
	assert_int(c.stage).is_equal(Passenger.Stage.TO_GATE)


func test_a_guest_past_its_deadline_before_service_gives_up_and_goes_on() -> void:
	_make()
	var p := _spawn_to(Passenger.Stage.TO_GATE)
	assert_bool(_cafes().try_visit(p)).is_true()
	var visit := _cafes().visit_of(p.id)
	visit.deadline = _world.clock.tick + 1
	_world.step()
	_world.step()
	assert_object(_cafes().visit_of(p.id)).is_null()
	assert_bool(visit.served).is_false()
	assert_int(visit.outcome).is_equal(CafeVisit.Outcome.NONE)
	assert_int(_cafes().seat_holder(visit.seat_key)).is_equal(0)
	assert_array(_cafes().queue_of(_ids["air_counter"])).is_empty()
	assert_int(p.stage).is_not_equal(Passenger.Stage.CAFE_WALK)
	assert_bool(Passenger.in_cafe(p.stage)).is_false()


func test_a_seated_guest_past_its_deadline_leaves_early() -> void:
	_make()
	var p := _spawn_to(Passenger.Stage.TO_GATE)
	assert_bool(_cafes().try_visit(p)).is_true()
	var visit := _cafes().visit_of(p.id)
	while p.stage != Passenger.Stage.CAFE_SEATED and _world.clock.tick < 1400:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_SEATED)
	assert_bool(visit.served).is_true()
	visit.deadline = _world.clock.tick + 1
	var dwell_end := visit.dwell_end
	_world.step()
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_STANDING_UP)
	assert_int(_world.clock.tick).is_less(dwell_end)
	assert_int(visit.outcome).is_equal(CafeVisit.Outcome.SHORT)
	_run_until_resumed(p, 1400)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)


func test_the_deadline_is_worked_out_again_after_an_edit() -> void:
	_make()
	var p := _spawn_to(Passenger.Stage.TO_GATE)
	assert_bool(_cafes().try_visit(p)).is_true()
	var visit := _cafes().visit_of(p.id)
	var before_edit := visit.deadline
	visit.deadline = 0
	# Any edit marks the deadlines stale: a floor tile far from everything.
	_world.grid.apply(BuildEdit.paint_floor(Vector2i(40, 40), BuildGrid.FLOOR_TILE, 1))
	_world.step()
	assert_int(visit.deadline).is_equal(before_edit)


func test_removing_the_table_ends_the_visit_and_frees_the_queue() -> void:
	_make()
	var p := _spawn_to(Passenger.Stage.TO_GATE)
	assert_bool(_cafes().try_visit(p)).is_true()
	_world.step()
	_world.grid.apply(BuildEdit.remove_object(_ids["air_table"]))
	_world.step()
	assert_object(_cafes().visit_of(p.id)).is_null()
	assert_array(_cafes().queue_of(_ids["air_counter"])).is_empty()
	assert_bool(Passenger.in_cafe(p.stage)).is_false()
	_world.run_to(1900)
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)


func test_removing_the_counter_sends_a_queuing_guest_on() -> void:
	_make()
	var p := _spawn_to(Passenger.Stage.TO_GATE)
	assert_bool(_cafes().try_visit(p)).is_true()
	while p.stage != Passenger.Stage.CAFE_QUEUE and _world.clock.tick < 1400:
		_world.step()
	_world.grid.apply(BuildEdit.remove_object(_ids["air_counter"]))
	_world.step()
	assert_object(_cafes().visit_of(p.id)).is_null()
	assert_bool(Passenger.in_cafe(p.stage)).is_false()


func test_doors_closing_on_a_guest_drops_its_visit() -> void:
	_make()
	var p := _spawn_to(Passenger.Stage.TO_GATE)
	assert_bool(_cafes().try_visit(p)).is_true()
	var visit := _cafes().visit_of(p.id)
	while p.stage != Passenger.Stage.CAFE_SEATED and _world.clock.tick < 1400:
		_world.step()
	# Held at the table past the doors, which the deadline never allows.
	visit.deadline = 1000000
	visit.dwell_end = 1000000
	var key := visit.seat_key
	_world.run_to(1900)
	assert_int(p.stage).is_equal(Passenger.Stage.MISSED)
	assert_int(p.missed_stage).is_equal(Passenger.Stage.CAFE_SEATED)
	assert_int(visit.outcome).is_equal(CafeVisit.Outcome.SHORT)
	assert_object(_cafes().visit_of(p.id)).is_null()
	assert_int(_cafes().seat_holder(key)).is_equal(0)


func test_a_visit_that_does_not_fit_before_doors_close_is_refused() -> void:
	_make()
	_world.run_to(1000)
	var p := _spawn_to(Passenger.Stage.TO_SECURITY, 1600)
	assert_bool(_cafes().try_visit(p)).is_false()
	assert_object(_cafes().visit_of(p.id)).is_null()


func test_a_passenger_queuing_for_check_in_cannot_start_a_visit() -> void:
	_make()
	var p := _spawn_to(Passenger.Stage.CHECKIN_QUEUE)
	assert_bool(_cafes().try_visit(p)).is_false()
