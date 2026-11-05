class_name TestBoothTurnBackSave
extends GdUnitTestSuite
## A booth guest turned back mid sit-down by a table move (CafeSim._relocates())
## gets up with no stand-up lead, and a save taken at that tick plays on
## exactly: the load keeps the turn-back (CafeSnapshot "turned_back"), so
## seat_position() does not apply CafeSim.STAND_UP_LEAD_TICKS to the reversal
## and shift the guest by up to half a metre (board 8a466fef). Cases use a
## restaurant booth, a guest with no roller, and a shift a room move makes.

## Float tolerance for "the same spot" between the played and the loaded sim.
const SAME_M := 0.0005

var _world: PassengerTestWorld
var _twin: PassengerTestWorld


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


## A booth guest with no roller, `ticks` ticks into its sit-down.
func _sitting(ticks: int) -> Passenger:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid, false, &"restaurant", true, &"cafe_counter", &"restaurant_booth")
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.cafe_cooldown = 1000000
	p.hunger = 30
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	while p.stage != Passenger.Stage.TO_GATE and _world.clock.tick < 1500:
		_world.step()
	assert_bool(_world.sim.cafes.try_visit(p)).override_failure_message("visit refused").is_true()
	while p.stage != Passenger.Stage.CAFE_SITTING_DOWN and _world.clock.tick < 3000:
		_world.step()
	for i in ticks:
		_world.step()
	return p


## Moves the guest's booth to the first of three neighbouring cells the grid
## accepts, as a room move does (removed and placed again under its id).
func _move_booth(p: Passenger) -> void:
	var id := int(_world.sim.cafes.visit_of(p.id).seat["object_id"])
	var record := _world.grid.get_object(id)
	for shift: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0)]:
		var place := BuildEdit.place_object(
			record["def"], record["anchor"] + shift, record["facing"]
		)
		place.object_id = id
		place.paid = int(record.get("paid", 0))
		if _world.grid.apply_batch([BuildEdit.remove_object(id), place])[1].ok:
			return
		var back := BuildEdit.place_object(record["def"], record["anchor"], record["facing"])
		back.object_id = id
		back.paid = place.paid
		_world.grid.apply_batch([back])
	fail("the booth could not be moved")


## The save of the played world, as the parsed JSON a load reads.
func _save() -> Dictionary:
	return JSON.parse_string(ShopMoveKit.save_text(_world))


## A guest turned back 6 ticks into its sit-down by a booth move, one tick on.
func _turned_back() -> Passenger:
	var p := _sitting(6)
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_SITTING_DOWN)
	_move_booth(p)
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_STANDING_UP)
	return p


func test_a_save_at_the_turn_back_reverses_tick_for_tick_like_continuous_play() -> void:
	var p := _turned_back()
	_twin = ShopMoveKit.load_twin(_save())
	assert_object(_twin).is_not_null()
	var q := _twin.passenger(p.id)
	assert_int(q.stage).is_equal(Passenger.Stage.CAFE_STANDING_UP)
	var largest := 0.0
	var steps := 0
	while p.stage == Passenger.Stage.CAFE_STANDING_UP and steps < 40:
		var played := _world.sim.cafes.seat_position(p)
		largest = maxf(largest, played.distance_to(_twin.sim.cafes.seat_position(q)))
		_world.step()
		_twin.step()
		steps += 1
	print("booth turn-back save, largest spot difference %.5f m over %d ticks" % [largest, steps])
	assert_int(steps).is_greater(3)
	assert_float(largest).is_less(SAME_M)
	assert_int(q.stage).is_equal(p.stage)


func test_a_guest_seated_when_its_booth_moved_keeps_the_stand_up_lead_after_a_load() -> void:
	var p := _sitting(0)
	while p.stage != Passenger.Stage.CAFE_SEATED and _world.clock.tick < 3000:
		_world.step()
	_move_booth(p)
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_STANDING_UP)
	var data := _save()
	assert_bool(data["passengers"]["cafe"]["visits"][0].has("turned_back")).is_false()
	_twin = ShopMoveKit.load_twin(data)
	assert_object(_twin).is_not_null()
	var q := _twin.passenger(p.id)
	for i in 6:
		var played := _world.sim.cafes.seat_position(p)
		assert_float(played.distance_to(_twin.sim.cafes.seat_position(q))).is_less(SAME_M)
		_world.step()
		_twin.step()


func test_a_turned_back_flag_is_refused_unless_it_is_a_bool_on_a_guest_getting_up() -> void:
	_turned_back()
	var data := _save()
	assert_bool(data["passengers"]["cafe"]["visits"][0]["turned_back"]).is_true()
	_twin = ShopMoveKit.load_twin(data)
	assert_object(_twin).override_failure_message("the legal save").is_not_null()
	for bad: Variant in [1, "yes", null]:
		var mangled: Dictionary = data.duplicate(true)
		mangled["passengers"]["cafe"]["visits"][0]["turned_back"] = bad
		assert_object(ShopMoveKit.load_twin(mangled)).override_failure_message(str(bad)).is_null()
	# The flag on a guest who is not getting up at an old seat: it has no
	# relocation to reverse.
	_world.free_all()
	_world = null
	var seated := _sitting(0)
	while seated.stage != Passenger.Stage.CAFE_SEATED and _world.clock.tick < 3000:
		_world.step()
	var plain := _save()
	assert_object(ShopMoveKit.load_twin(plain)).override_failure_message("plain").is_not_null()
	plain["passengers"]["cafe"]["visits"][0]["turned_back"] = true
	assert_object(ShopMoveKit.load_twin(plain)).is_null()
