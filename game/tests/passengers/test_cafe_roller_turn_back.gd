class_name TestCafeRollerTurnBack
extends GdUnitTestSuite
## A cafe guest with a roller whose table is moved during the first 12 ticks of
## its sit-down turns back (CafeSim._relocates()). Its roller stand-up is the
## stand-up, the roller's pick-up and the step out (CafeSim.up_ticks()), so it
## steps back from the share of the step onto the seat it had made, not from
## the whole step (board c0707a22, as the shop's Relocation.reached, decision
## move-rooms-turn-back-as-built-a-roller-visitor-moved-mid-sit). Cases use
## CafeTestLayout's airside cafe table, moved one cell north as a room move does.

## The longest step a tick may take: a walking step (PassengerSim.WALK_MM).
const MAX_STEP_M := PassengerSim.WALK_MM / 1000.0 + 0.002
## Float tolerance for "the same spot" between the played and the loaded sim.
const SAME_M := 0.0005

var _world: PassengerTestWorld
var _twin: PassengerTestWorld
var _ids: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in [_world, _twin]:
		if world != null:
			world.free_all()
	_world = null
	_twin = null


## A guest pulling a roller, `spent` ticks into its sit-down at the airside cafe.
func _sitting(spent: int) -> Passenger:
	var grid := BuildGrid.new()
	_ids = CafeTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var p: Passenger = null
	for attempt in 200:
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		p.cafe_cooldown = 1000000
		p.hunger = 30
		p.carry_on = 1
		if SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER:
			break
		p.carry_on = 0
		ToiletTestLayout.calm(p)
	assert_bool(ParkRecovery.has_roller(p)).is_true()
	p.liquids = false
	p.alarm = false
	while p.stage != Passenger.Stage.TO_GATE and _world.clock.tick < 1500:
		_world.step()
	assert_bool(_world.sim.cafes.try_visit(p)).override_failure_message("visit refused").is_true()
	while p.stage != Passenger.Stage.CAFE_SITTING_DOWN and _world.clock.tick < 3000:
		_world.step()
	for i in spent:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_SITTING_DOWN)
	return p


## Moves the airside table one cell north, as a room move does.
func _move_table() -> void:
	var id: int = _ids["air_table"]
	var record := _world.grid.get_object(id)
	var place := BuildEdit.place_object(
		record["def"], record["anchor"] + Vector2i(0, -1), record["facing"]
	)
	place.object_id = id
	place.paid = int(record.get("paid", 0))
	for result in _world.grid.apply_batch([BuildEdit.remove_object(id), place]):
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()


## The guest `spent` ticks into its sit-down when the table moves, played to the
## end of its stand-up: the largest step in any tick, from the tick of the move on.
func _largest_step_turning_back(spent: int) -> float:
	var p := _sitting(spent)
	var cafes := _world.sim.cafes
	var last := cafes.seat_position(p)
	_move_table()
	var largest := 0.0
	var worst := ""
	var steps := 0
	while steps < 80:
		_world.step()
		if p.stage != Passenger.Stage.CAFE_STANDING_UP:
			break
		var now := cafes.seat_position(p)
		if now.distance_to(last) > largest:
			largest = now.distance_to(last)
			worst = "tick %d step %.3f m (limit %.3f)" % [_world.clock.tick, largest, MAX_STEP_M]
		last = now
		steps += 1
	print("roller turn-back at %d, %d ticks standing up, largest step %s" % [spent, steps, worst])
	assert_int(steps).is_greater(PassengerSim.STAND_UP_TICKS)
	assert_float(largest).override_failure_message(worst).is_less(MAX_STEP_M)
	return largest


func test_a_roller_guest_moved_at_the_start_of_its_sit_down_steps_back_at_walking_pace() -> void:
	assert_float(_largest_step_turning_back(0)).is_greater(0.0)


func test_a_roller_guest_moved_5_ticks_into_its_sit_down_steps_back_at_walking_pace() -> void:
	assert_float(_largest_step_turning_back(5)).is_greater(0.0)


func test_a_roller_guest_moved_11_ticks_into_its_sit_down_steps_back_at_walking_pace() -> void:
	assert_float(_largest_step_turning_back(11)).is_greater(0.0)


func test_a_save_in_a_turned_back_roller_guests_stand_up_keeps_its_step() -> void:
	var p := _sitting(5)
	_move_table()
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_STANDING_UP)
	var data: Dictionary = JSON.parse_string(ShopMoveKit.save_text(_world))
	var moving: Dictionary = data["passengers"]["cafe"]["visits"][0]["relocation"]
	# The sim sees the move one tick on: 5 ticks sat, 6 at the turn-back.
	assert_int(int(moving["reached"])).is_equal(6)
	_twin = ShopMoveKit.load_twin(data)
	assert_object(_twin).is_not_null()
	var q := _twin.passenger(p.id)
	var largest := 0.0
	var steps := 0
	while p.stage == Passenger.Stage.CAFE_STANDING_UP and steps < 80:
		var played := _world.sim.cafes.seat_position(p)
		largest = maxf(largest, played.distance_to(_twin.sim.cafes.seat_position(q)))
		_world.step()
		_twin.step()
		steps += 1
	print("roller turn-back save, largest spot difference %.5f m over %d ticks" % [largest, steps])
	assert_int(steps).is_greater(PassengerSim.STAND_UP_TICKS)
	assert_float(largest).is_less(SAME_M)
	assert_int(q.stage).is_equal(p.stage)
