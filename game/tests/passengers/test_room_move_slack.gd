class_name TestRoomMoveSlack
extends GdUnitTestSuite
## The return forecast of a relocated visitor at its tightest (decision
## move-rooms-technical-design-roommove-plan-of-existing-edits, part 4; ruling
## moving-a-room-with-its-furniture-is-free-and-keeps-paid-pric, point 4). On
## the tick before the visitor leaves its old spot, the test sets the service
## it still owes so that it would start to get up (cafe) or stand up from the
## stall (toilet) `slack` ticks before its deadline, counting the walk that
## starts the tick after it leaves. With one tick of slack it is admitted and
## finishes the whole visit; with none it gives up at once: unpaid at the
## cafe, its need as it was at the toilet. Never admitted and then cut short.
## Layouts as in test_room_move_cafe.gd and test_room_move_toilet.gd.

var _world: PassengerTestWorld
var _ids: Dictionary
## Passenger id -> [stage, tick] entered, in order.
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


func _at() -> Vector2i:
	return ReferenceTerminal.offset_on(_world.grid)


func _track() -> void:
	var sim := _world.sim
	sim.stage_changed.connect(
		func(id: int, stage: Passenger.Stage) -> void:
			if not _stages.has(id):
				_stages[id] = []
			_stages[id].append([stage, sim.tick])
	)


## The tick `p` last entered `stage`, or -1.
func _entered(p: Passenger, stage: Passenger.Stage) -> int:
	var found := -1
	for entry: Array in _stages.get(p.id, []):
		if entry[0] == stage:
			found = entry[1]
	return found


func _move(id: int, anchor: Vector2i) -> void:
	var record := _world.grid.get_object(id)
	var place := BuildEdit.place_object(record["def"], anchor + _at(), record["facing"])
	place.object_id = id
	place.paid = int(record.get("paid", 0))
	for result in _world.grid.apply_batch([BuildEdit.remove_object(id), place]):
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()


## Steps until `p` is in `stage` with `spent` ticks of it gone.
func _run_to(p: Passenger, stage: Passenger.Stage, spent: int) -> void:
	var until := _world.clock.tick + 1500
	while (
		not (p.stage == stage and _world.clock.tick - p.stage_tick == spent)
		and _world.clock.tick < until
	):
		_world.step()
	assert_int(p.stage).is_equal(stage)


## A cafe guest one tick before it leaves its old seat, owing the dwell that
## leaves it `slack` ticks before its deadline. Returns the tick it would start
## to get up at the new seat.
func _cafe_return(slack: int) -> Passenger:
	var grid := BuildGrid.new()
	_ids = CafeTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(1500, 4000))
	_track()
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 0
	p.cafe_cooldown = 1000000
	var started := false
	while p.stage != Passenger.Stage.CAFE_SEATED and _world.clock.tick < 1400:
		_world.step()
		if not started and p.stage == Passenger.Stage.TO_GATE:
			started = _world.sim.cafes.try_visit(p)
	_move(_ids["air_table"], Vector2i(24, 5))
	_run_to(p, Passenger.Stage.CAFE_STANDING_UP, PassengerSim.STAND_UP_TICKS - 1)
	var visit := _world.sim.cafes.visit_of(p.id)
	_world.sim.cafes.refresh()
	var approach: Vector2i = _world.sim.cafes.layout.seat(visit.room, visit.seat_key)["approach"]
	var walk := JourneyForecast.walk_ticks(VisitRoute.plan(_world.grid, p, approach)["mm"])
	var deadline := VisitForecast.deadline(
		_world.sim, p, approach, PassengerSim.STAND_UP_TICKS, visit.resume_stage
	)
	# Left the old seat on the next tick, walking from the one after.
	var seated := _world.clock.tick + 1 + 1 + walk + PassengerSim.SIT_DOWN_TICKS
	visit.relocation.left = deadline - slack - seated
	assert_int(visit.relocation.left).is_greater(0)
	return p


## A toilet user one tick before it is out of its old stall, owing the use
## that leaves it `slack` ticks before its deadline.
func _toilet_return(slack: int) -> Passenger:
	var grid := BuildGrid.new()
	_ids = ToiletTestLayout.build(grid, 1)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_track()
	_world.run_to(10)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.stage = Passenger.Stage.TO_SECURITY
	p.stage_tick = _world.clock.tick
	p.at = Vector2i(20, 14) + _at()
	p.clear_path()
	p.toilet_need = 90
	assert_bool(_world.sim.toilets.try_visit(p)).is_true()
	_run_to(p, Passenger.Stage.TOILET_USE, 5)
	_move(_ids["land_stalls"][0], Vector2i(25, 10))
	_run_to(p, Passenger.Stage.TOILET_EXIT, ToiletSim.EXIT_TICKS - 1)
	var visit := _world.sim.toilets.visit_of(p.id)
	_world.sim.toilets.refresh()
	var approach: Vector2i = _world.sim.toilets.layout.stall(visit.stall_id)["approach"]
	var walk := JourneyForecast.walk_ticks(VisitRoute.plan(_world.grid, p, approach)["mm"])
	var deadline := VisitForecast.deadline(
		_world.sim, p, approach, ToiletSim.LEAVE_TICKS, visit.resume_stage
	)
	var sat := (
		_world.clock.tick + 1 + 1 + walk + ToiletSim.ENTER_TICKS + PassengerSim.SIT_DOWN_TICKS
	)
	visit.relocation.left = deadline - slack - sat
	assert_int(visit.relocation.left).is_greater(0)
	return p


func test_a_cafe_return_with_one_tick_of_slack_finishes_the_whole_dwell() -> void:
	var p := _cafe_return(1)
	var visit := _world.sim.cafes.visit_of(p.id)
	var cash := _world.sim.wallet.balance
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_TO_SEAT)
	var dwell_end := -1
	while _world.sim.cafes.visit_of(p.id) != null and _world.clock.tick < 6000:
		_world.step()
		if p.stage == Passenger.Stage.CAFE_SEATED:
			dwell_end = visit.dwell_end
	assert_int(_entered(p, Passenger.Stage.CAFE_STANDING_UP)).is_equal(dwell_end)
	assert_int(visit.outcome).is_equal(CafeVisit.Outcome.COMPLETE)
	assert_int(_world.sim.wallet.balance).is_equal(cash + visit.amount)


func test_a_cafe_return_with_no_slack_gives_up_unpaid_at_once() -> void:
	var p := _cafe_return(0)
	var visit := _world.sim.cafes.visit_of(p.id)
	var cash := _world.sim.wallet.balance
	_world.step()
	assert_object(_world.sim.cafes.visit_of(p.id)).is_null()
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
	assert_bool(visit.settled).is_false()
	assert_int(_world.sim.wallet.balance).is_equal(cash)


func test_a_toilet_return_with_one_tick_of_slack_uses_all_it_owes() -> void:
	var p := _toilet_return(1)
	var owed := _world.sim.toilets.visit_of(p.id).relocation.left
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.TOILET_WALK)
	while _world.sim.toilets.visit_of(p.id) != null and _world.clock.tick < 6000:
		_world.step()
	var used := _entered(p, Passenger.Stage.TOILET_STANDING_UP)
	assert_int(used - _entered(p, Passenger.Stage.TOILET_USE)).is_equal(owed)
	assert_int(p.toilet_need).is_less(20)


func test_a_toilet_return_with_no_slack_goes_on_with_its_need() -> void:
	var p := _toilet_return(0)
	var need := p.toilet_need
	_world.step()
	assert_object(_world.sim.toilets.visit_of(p.id)).is_null()
	assert_int(p.stage).is_equal(Passenger.Stage.TO_SECURITY)
	assert_int(p.toilet_need).is_greater_equal(need)
