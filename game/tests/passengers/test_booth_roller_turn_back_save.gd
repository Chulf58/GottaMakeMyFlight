class_name TestBoothRollerTurnBackSave
extends GdUnitTestSuite
## A booth guest with a roller whose booth moves early in its step-in hold
## turns back at once (CafeSim._relocates()), with its relocation recorded and
## its deadline forecast again, and stands at the approach cell
## CafeSim.TURN_BACK_HOLD_TICKS longer (CafeSim.turn_back_hold()) so its roller
## is down and lifted before it sets off. Held in its sit-down instead
## (205d447), a save before tick 12 had no relocation, and the load put the
## guest at the booth's new approach cell; its deadline went stale (Sol
## re-check of 205d447, board 2eaa9bc4). Sim only, a restaurant booth.

## Ticks into the sit-down the booth is moved.
const MOVED_AT := 6
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


## A guest pulling a roller to the restaurant's booth, MOVED_AT ticks into its
## sit-down.
func _sitting() -> Passenger:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid, false, &"restaurant", true, &"cafe_counter", &"restaurant_booth")
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
	p.liquids = false
	p.alarm = false
	while p.stage != Passenger.Stage.TO_GATE and _world.clock.tick < 1500:
		_world.step()
	assert_bool(_world.sim.cafes.try_visit(p)).override_failure_message("visit refused").is_true()
	while p.stage != Passenger.Stage.CAFE_SITTING_DOWN and _world.clock.tick < 3000:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_SITTING_DOWN)
	for i in MOVED_AT:
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


## A save two ticks after the move (inside the 12 ticks 205d447 held the guest
## in its sit-down) plays on tick for tick like continuous play: the same
## stage, stage tick and spot every tick, both setting off on the same tick,
## no sooner than the turn-back's stand-up with TURN_BACK_HOLD_TICKS. Control:
## the guest turned back on the move and stood at the old approach cell.
func test_a_save_in_the_turn_back_hold_plays_on_like_continuous_play() -> void:
	var p := _sitting()
	var approach := _world.grid.cell_to_world(_world.sim.cafes.visit_of(p.id).seat["approach"])
	_move_booth(p)
	_world.step()
	var turned_at := _world.clock.tick
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_STANDING_UP)
	assert_object(_world.sim.cafes.visit_of(p.id).relocation).is_not_null()
	_world.step()
	_world.step()
	_twin = ShopMoveKit.load_twin(JSON.parse_string(ShopMoveKit.save_text(_world)))
	assert_object(_twin).override_failure_message("the save was refused").is_not_null()
	var q := _twin.passenger(p.id)
	var largest := 0.0
	var off_approach := 0.0
	var differs := 0
	var steps := 0
	while p.stage == Passenger.Stage.CAFE_STANDING_UP and steps < 80:
		var at := _world.sim.cafes.seat_position(p)
		largest = maxf(largest, at.distance_to(_twin.sim.cafes.seat_position(q)))
		off_approach = maxf(off_approach, Vector2(at.x - approach.x, at.z - approach.z).length())
		if q.stage != p.stage or q.stage_tick != p.stage_tick:
			differs += 1
		_world.step()
		_twin.step()
		steps += 1
	var set_off := _world.clock.tick - turned_at
	print(
		(
			(
				"booth roller turn-back save: set off %d ticks after the turn-back, %d ticks"
				+ " compared, largest spot difference %.5f m, stage differs %d, off approach %.3f m"
			)
			% [set_off, steps, largest, differs, off_approach]
		)
	)
	assert_int(steps).is_greater(10)
	assert_float(largest).is_less(SAME_M)
	assert_int(differs).is_equal(0)
	assert_int(q.stage).is_equal(p.stage)
	assert_float(off_approach).is_less(0.01)
	assert_int(set_off).is_greater_equal(
		ParkRecovery.UP_HOLD_TICKS + CafeSim.TURN_BACK_HOLD_TICKS - 1
	)


## The booth move forecasts the turned-back visit's deadline again on the
## tick it turns back: it equals the live forecast from its new state (the
## longer stand-up included). Control: the turn-back happened.
func test_a_booth_move_in_the_hold_refreshes_the_visit_deadline() -> void:
	var p := _sitting()
	var visit := _world.sim.cafes.visit_of(p.id)
	var before_move := visit.deadline
	_move_booth(p)
	_world.step()
	var live := _world.sim.cafes._live_deadline(p, visit)
	print(
		(
			"booth roller turn-back deadline: before %d, after %d, live %d, stage %d"
			% [before_move, visit.deadline, live, p.stage]
		)
	)
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_STANDING_UP)
	assert_int(visit.deadline).is_equal(live)
