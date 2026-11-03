class_name TestRoomMoveCafe
extends GdUnitTestSuite
## Cafe guests when their table moves (decision move-rooms-technical-design-
## roommove-plan-of-existing-edits, parts 4 to 6; ruling moving-a-room-with-
## its-furniture-is-free-and-keeps-paid-pric, points 2 and 4), on
## CafeTestLayout's airside cafe (x 22-27, y 3-8; table at 24,6 with seats on
## 24,6 and 26,6, approached from row 7). A piece moved by hand is removed and
## placed again under its id with its paid, as RoomMove does; the RoomMove
## cases turn the whole room in place.

## The longest drawn step a tick may take: a walking step (PassengerSim.WALK_MM),
## measured on the position the views record for each tick (tick_position()).
const MAX_STEP_M := PassengerSim.WALK_MM / 1000.0 + 0.002

var _world: PassengerTestWorld
var _views: PassengerViews
var _ids: Dictionary
var _stages: Dictionary = {}


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
		_views = null
	if _world != null:
		_world.free_all()
		_world = null
	_stages.clear()


func _make() -> void:
	var grid := BuildGrid.new()
	_ids = CafeTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(1500, 4000))
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	_world.sim.stage_changed.connect(
		func(id: int, stage: Passenger.Stage) -> void:
			if not _stages.has(id):
				_stages[id] = []
			_stages[id].append(stage)
	)


func _cafes() -> CafeSim:
	return _world.sim.cafes


func _at() -> Vector2i:
	return ReferenceTerminal.offset_on(_world.grid)


## A guest of the airside cafe, run until it reaches `stage`.
func _guest_to(stage: Passenger.Stage) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 0
	p.cafe_cooldown = 1000000
	var started := false
	while p.stage != stage and _world.clock.tick < 1400:
		_world.step()
		if not started and p.stage == Passenger.Stage.TO_GATE:
			started = _cafes().try_visit(p)
	assert_bool(started).is_true()
	assert_int(p.stage).is_equal(stage)
	return p


## Moves the airside table to `anchor` (terminal cells) as a room move does:
## removed and placed again under its id with its paid.
func _move_table(anchor: Vector2i) -> void:
	var id: int = _ids["air_table"]
	var record := _world.grid.get_object(id)
	var place := BuildEdit.place_object(record["def"], anchor + _at(), record["facing"])
	place.object_id = id
	place.paid = int(record.get("paid", 0))
	for result in _world.grid.apply_batch([BuildEdit.remove_object(id), place]):
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()


## Steps until `done` holds or `limit` ticks pass, failing on any tick the
## guest's drawn position jumps more than MAX_STEP_M. Returns the largest step.
## With `visit_end`, `done` is the visit ending and that last tick is not
## measured: the tick a visit ends, the journey's own walk starts as the last
## step off the seat is taken, outside relocation (reported separately).
func _walk_until(p: Passenger, done: Callable, limit := 1500, visit_end := false) -> float:
	var last := _views.tick_position(p.id, true)
	var largest := 0.0
	var worst := ""
	var until := _world.clock.tick + limit
	while not done.call() and _world.clock.tick < until:
		_world.step()
		var now := _views.tick_position(p.id, true)
		if visit_end and done.call():
			break
		if now.distance_to(last) > largest:
			largest = now.distance_to(last)
			worst = "tick %d stage %d step %.3f" % [_world.clock.tick, p.stage, largest]
		last = now
	assert_bool(done.call()).is_true()
	assert_float(largest).override_failure_message(worst).is_less(MAX_STEP_M)
	return largest


func test_a_seated_guest_gets_up_at_the_old_seat_then_sits_at_the_moved_table() -> void:
	_make()
	var p := _guest_to(Passenger.Stage.CAFE_SEATED)
	var visit := _cafes().visit_of(p.id)
	var sat_at := _cafes().seat_position(p)
	var owed := visit.dwell_end - _world.clock.tick
	var cash := _world.sim.wallet.balance
	_move_table(Vector2i(24, 5))
	# Before any tick: still drawn on the old seat, which a ghost table holds.
	assert_vector(_cafes().seat_position(p)).is_equal(sat_at)
	assert_int(Relocation.ghosts(_world.sim).size()).is_equal(1)
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_STANDING_UP)
	assert_object(visit.relocation).is_not_null()
	assert_bool(visit.relocation.exiting).is_true()
	assert_bool(visit.settled).is_false()
	assert_int(_world.sim.wallet.balance).is_equal(cash)
	_walk_until(p, func() -> bool: return p.stage == Passenger.Stage.CAFE_TO_SEAT)
	assert_int(Relocation.ghosts(_world.sim).size()).is_equal(0)
	_walk_until(p, func() -> bool: return p.stage == Passenger.Stage.CAFE_SEATED)
	var seat := _cafes().layout.seat(visit.room, visit.seat_key)
	assert_vector(_cafes().seat_position(p)).is_equal(
		BuildObjectDef.seat_root_world(_world.grid, seat)
	)
	assert_vector(_cafes().seat_position(p)).is_not_equal(sat_at)
	assert_object(visit.relocation).is_null()
	# Only the dwell it still owed when it got up.
	assert_int(visit.dwell_end - _world.clock.tick).is_equal(owed - 1)
	_walk_until(p, func() -> bool: return _cafes().visit_of(p.id) == null, 1500, true)
	assert_int(visit.outcome).is_equal(CafeVisit.Outcome.COMPLETE)
	assert_bool(visit.settled).is_true()
	assert_int(_world.sim.wallet.balance).is_equal(cash + visit.amount)
	assert_int(visit.amount).is_greater(0)


func test_a_guest_walking_off_sideways_from_its_old_seat_takes_one_step_a_tick() -> void:
	_make()
	var p := _guest_to(Passenger.Stage.CAFE_SEATED)
	# One cell east: the walk to the seat's new approach (25,7) sets off east,
	# across the last step of getting up (south-west), so a tick taking both
	# would move about 0.103 m.
	_move_table(Vector2i(25, 6))
	_walk_until(p, func() -> bool: return p.stage == Passenger.Stage.CAFE_TO_SEAT)
	_walk_until(p, func() -> bool: return p.stage == Passenger.Stage.CAFE_SEATED)
	assert_vector(p.at).is_equal(Vector2i(25, 7) + _at())


func test_a_second_move_mid_exit_changes_the_walk_not_the_exit() -> void:
	_make()
	var p := _guest_to(Passenger.Stage.CAFE_SEATED)
	var visit := _cafes().visit_of(p.id)
	var source := Relocation.placement(_world.grid, _ids["air_table"])
	_move_table(Vector2i(24, 5))
	for i in 6:
		_world.step()
	var stood_from := p.stage_tick
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_STANDING_UP)
	_move_table(Vector2i(24, 4))
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_STANDING_UP)
	assert_int(p.stage_tick).is_equal(stood_from)
	assert_dict(visit.relocation.source).is_equal(source)
	_walk_until(p, func() -> bool: return p.stage == Passenger.Stage.CAFE_SEATED)
	var seat := _cafes().layout.seat(visit.room, visit.seat_key)
	assert_int(seat["approach"].y).is_equal(5 + _at().y)
	assert_vector(p.at).is_equal(seat["approach"])


func test_a_guest_already_getting_up_finishes_at_the_old_seat_and_pays_once() -> void:
	_make()
	var p := _guest_to(Passenger.Stage.CAFE_STANDING_UP)
	var visit := _cafes().visit_of(p.id)
	var stood_at := _cafes().seat_position(p)
	var paid := _world.sim.wallet.balance
	_move_table(Vector2i(24, 5))
	_world.step()
	assert_int(visit.relocation.left).is_equal(-1)
	assert_float(_cafes().seat_position(p).distance_to(stood_at)).is_less(MAX_STEP_M)
	_walk_until(p, func() -> bool: return _cafes().visit_of(p.id) == null, 40, true)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
	assert_int(_world.sim.wallet.balance).is_equal(paid)
	assert_int(Relocation.ghosts(_world.sim).size()).is_equal(0)


func test_a_move_undone_before_any_tick_does_not_interrupt_the_guest() -> void:
	_make()
	var p := _guest_to(Passenger.Stage.CAFE_SEATED)
	var visit := _cafes().visit_of(p.id)
	var dwell_end := visit.dwell_end
	_move_table(Vector2i(24, 5))
	assert_int(Relocation.ghosts(_world.sim).size()).is_equal(1)
	_move_table(CafeTestLayout.AIR_TABLE)
	assert_int(Relocation.ghosts(_world.sim).size()).is_equal(0)
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_SEATED)
	assert_object(visit.relocation).is_null()
	assert_int(visit.dwell_end).is_equal(dwell_end)


func test_a_guest_whose_rest_of_visit_misses_the_flight_gives_up_unpaid() -> void:
	_make()
	var p := _guest_to(Passenger.Stage.CAFE_SEATED)
	var visit := _cafes().visit_of(p.id)
	# A dwell that would run to the doors: after the move it cannot fit again.
	visit.dwell_end = _world.flights.doors_close_tick(p.flight_id)
	var cash := _world.sim.wallet.balance
	_stages.erase(p.id)
	_move_table(Vector2i(24, 5))
	_walk_until(p, func() -> bool: return _cafes().visit_of(p.id) == null, 60, true)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
	assert_bool(visit.settled).is_false()
	assert_int(_world.sim.wallet.balance).is_equal(cash)
	assert_array(_stages[p.id]).not_contains([Passenger.Stage.CAFE_TO_SEAT])


func test_a_served_guest_walking_to_its_seat_goes_to_the_moved_seat() -> void:
	_make()
	var p := _guest_to(Passenger.Stage.CAFE_TO_SEAT)
	var visit := _cafes().visit_of(p.id)
	_stages.erase(p.id)
	_move_table(Vector2i(24, 5))
	_walk_until(p, func() -> bool: return p.stage == Passenger.Stage.CAFE_SEATED)
	assert_vector(p.at).is_equal(visit.seat["approach"])
	assert_int(visit.seat["approach"].y).is_equal(6 + _at().y)
	assert_array(_stages[p.id]).not_contains(
		[Passenger.Stage.CAFE_WALK, Passenger.Stage.CAFE_QUEUE, Passenger.Stage.CAFE_ORDER]
	)


func test_a_room_move_turned_in_place_relocates_the_guest_onto_the_new_seat() -> void:
	_make()
	var p := _guest_to(Passenger.Stage.CAFE_SEATED)
	var visit := _cafes().visit_of(p.id)
	var cash := _world.sim.wallet.balance
	# The same rectangle, turned half round: the table lands on row 5.
	var centre := Vector2i(24, 5) + _at()
	var result := RoomMove.commit(_world.grid, _ids["air_room"], centre, 2, _world.sim.wallet)
	assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	assert_int(Relocation.ghosts(_world.sim).size()).is_equal(1)
	_walk_until(p, func() -> bool: return p.stage == Passenger.Stage.CAFE_TO_SEAT)
	_walk_until(p, func() -> bool: return p.stage == Passenger.Stage.CAFE_SEATED)
	var record := _world.grid.get_object(_ids["air_table"])
	assert_int(record["facing"]).is_equal(2)
	var cells := [Vector2i(23, 5) + _at(), Vector2i(25, 5) + _at()]
	(
		assert_bool(visit.seat["cell"] in cells)
		. override_failure_message("%s, table %s" % [visit.seat, record])
		. is_true()
	)
	_walk_until(p, func() -> bool: return _cafes().visit_of(p.id) == null, 1500, true)
	assert_bool(visit.settled).is_true()
	assert_int(_world.sim.wallet.balance).is_equal(cash + visit.amount)


func test_a_room_move_onto_a_seated_guests_way_out_is_refused() -> void:
	_make()
	var centre := Vector2i(24, 5) + _at()
	# Control: with nobody seated the quarter turn is accepted.
	var control := RoomMove.plan(_world.grid, _ids["air_room"], centre, 1, _world.sim.wallet)
	assert_bool(control.result.ok).override_failure_message(control.result.reason_text()).is_true()
	var p := _guest_to(Passenger.Stage.CAFE_SEATED)
	var exits := _world.sim.move_exit_cells()
	assert_array(exits).contains([_cafes().visit_of(p.id).seat["approach"]])
	var result := RoomMove.commit(_world.grid, _ids["air_room"], centre, 1, _world.sim.wallet)
	assert_int(result.reason).is_equal(BuildResult.Reason.MOVE_EXIT_BLOCKED)
	assert_int(result.blocking_object_id).is_equal(_ids["air_table"])
	assert_vector(_world.grid.get_object(_ids["air_table"])["anchor"]).is_equal(
		CafeTestLayout.AIR_TABLE + _at()
	)


func test_save_and_load_while_getting_up_at_the_old_seat_plays_on() -> void:
	_make()
	var p := _guest_to(Passenger.Stage.CAFE_SEATED)
	_move_table(Vector2i(24, 5))
	for i in 5:
		_world.step()
	var text := (
		JSON
		. stringify(
			{
				"clock": _world.clock.to_snapshot(),
				"flights": _world.flights.to_snapshot(),
				"grid": _world.grid.to_snapshot(),
				"passengers": _world.sim.to_snapshot(),
				"wallet": _world.sim.wallet.to_snapshot(),
			}
		)
	)
	assert_str(text).contains("relocation")
	var data: Dictionary = JSON.parse_string(text)
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	var twin := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(1500, 4000), 99)
	assert_bool(twin.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(twin.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(twin.sim.from_snapshot(data["passengers"])).is_true()
	assert_bool(twin.sim.wallet.from_snapshot(data["wallet"])).is_true()
	var q := twin.passenger(p.id)
	assert_vector(twin.sim.cafes.seat_position(q)).is_equal(_cafes().seat_position(p))
	assert_int(Relocation.ghosts(twin.sim).size()).is_equal(1)
	for i in 200:
		_world.step()
		twin.step()
	assert_int(q.stage).is_equal(p.stage)
	assert_vector(twin.sim.world_position(q)).is_equal(_world.sim.world_position(p))
	twin.free_all()
