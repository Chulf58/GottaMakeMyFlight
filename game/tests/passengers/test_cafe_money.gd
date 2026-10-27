class_name TestCafeMoney
extends GdUnitTestSuite
## Settling a cafe visit (decision cafe-visit-design-forecast-the-whole-
## itinerary-abandon-by-a, points 6 and 7; rulings shops-and-food-stalls-earn-
## per-visit-toilets-and-screens-cos and store-mechanics-draw-a-room-then-
## furnish-it-required-pieces): base spend x mood% x airside%, rounded once,
## credited to the wallet once, the visit marked settled, then `paid`.

var _world: PassengerTestWorld
var _ids: Dictionary
## [passenger id, room id, amount, wallet balance when emitted] per `paid`.
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


func _make() -> void:
	var grid := BuildGrid.new()
	_ids = CafeTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.sim.cafes.paid.connect(_on_paid)


func _on_paid(id: int, room: int, amount: int) -> void:
	_paid.append([id, room, amount, _world.sim.wallet.balance])


## A passenger on a visit started the tick it reached `stage`.
func _guest(stage: Passenger.Stage) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.cafe_cooldown = 1000000
	p.hunger = 30
	while p.stage != stage and _world.clock.tick < 900:
		_world.step()
	assert_bool(_world.sim.cafes.try_visit(p)).is_true()
	return p


func _run_to_stage(p: Passenger, stage: Passenger.Stage) -> void:
	while p.stage != stage and _world.clock.tick < 1400:
		_world.step()
	assert_int(p.stage).is_equal(stage)


func test_spend_is_base_times_mood_times_side_rounded_once() -> void:
	var complete := CafeVisit.Outcome.COMPLETE
	var short := CafeVisit.Outcome.SHORT
	# 15 x 80% = 12; 15 x 120% x 125% = 22.5, rounded half up.
	assert_int(CafeSim.spend(15, 0, false, complete)).is_equal(12)
	assert_int(CafeSim.spend(15, 100, true, complete)).is_equal(23)
	# 15 x 108% x 125% = 20.25; 15 x 108% = 16.2; 15 x 108% x 50% = 8.1.
	assert_int(CafeSim.spend(15, 70, true, complete)).is_equal(20)
	assert_int(CafeSim.spend(15, 70, false, complete)).is_equal(16)
	assert_int(CafeSim.spend(15, 70, false, short)).is_equal(8)
	# Rounded once, not per factor: 15 x 101.2% x 125% x 50% = 9.4875.
	assert_int(CafeSim.spend(15, 53, true, short)).is_equal(9)
	assert_int(CafeSim.spend(15, 70, true, CafeVisit.Outcome.NONE)).is_equal(0)


func test_a_full_airside_visit_pays_once_into_the_wallet_then_signals() -> void:
	_make()
	var p := _guest(Passenger.Stage.TO_GATE)
	var visit := _world.sim.cafes.visit_of(p.id)
	_run_to_stage(p, Passenger.Stage.CAFE_SEATED)
	while p.stage == Passenger.Stage.CAFE_SEATED:
		var mood := p.mood
		_world.step()
		if p.stage == Passenger.Stage.CAFE_STANDING_UP:
			var expected := CafeSim.spend(15, mood, true, CafeVisit.Outcome.COMPLETE)
			print("mood %d paid %d balance %d" % [mood, visit.amount, _world.sim.wallet.balance])
			assert_int(visit.amount).is_equal(expected)
			assert_int(p.mood).is_equal(mini(mood + CafeSim.SERVED_MOOD_BONUS, 100))
	assert_bool(visit.settled).is_true()
	assert_int(p.hunger).is_less_equal(1)
	assert_int(_world.sim.wallet.balance).is_equal(visit.amount)
	assert_array(_paid).is_equal([[p.id, _ids["air_room"], visit.amount, visit.amount]])
	_world.run_to(1000)
	assert_int(_world.sim.wallet.balance).is_equal(visit.amount)
	assert_int(_paid.size()).is_equal(1)


func test_a_landside_visit_pays_without_the_airside_bonus() -> void:
	_make()
	var p := _guest(Passenger.Stage.TO_SECURITY)
	var visit := _world.sim.cafes.visit_of(p.id)
	_run_to_stage(p, Passenger.Stage.CAFE_SEATED)
	var mood := p.mood
	while p.stage == Passenger.Stage.CAFE_SEATED:
		mood = p.mood
		_world.step()
	assert_int(visit.amount).is_equal(CafeSim.spend(15, mood, false, CafeVisit.Outcome.COMPLETE))
	assert_int(_world.sim.wallet.balance).is_equal(visit.amount)


func test_leaving_early_pays_the_short_share_and_resets_hunger_only() -> void:
	_make()
	var p := _guest(Passenger.Stage.TO_GATE)
	var visit := _world.sim.cafes.visit_of(p.id)
	_run_to_stage(p, Passenger.Stage.CAFE_SEATED)
	visit.deadline = _world.clock.tick + 1
	var mood := p.mood
	while p.stage == Passenger.Stage.CAFE_SEATED:
		mood = p.mood
		_world.step()
	assert_int(visit.outcome).is_equal(CafeVisit.Outcome.SHORT)
	assert_int(visit.amount).is_equal(CafeSim.spend(15, mood, true, CafeVisit.Outcome.SHORT))
	assert_int(p.mood).is_equal(mood)
	assert_int(p.hunger).is_equal(0)
	assert_int(_world.sim.wallet.balance).is_equal(visit.amount)


func test_giving_up_before_service_pays_nothing_and_keeps_hunger() -> void:
	_make()
	var p := _guest(Passenger.Stage.TO_GATE)
	var visit := _world.sim.cafes.visit_of(p.id)
	visit.deadline = _world.clock.tick + 1
	_world.step()
	_world.step()
	assert_object(_world.sim.cafes.visit_of(p.id)).is_null()
	assert_bool(visit.settled).is_false()
	assert_int(p.hunger).is_greater_equal(30)
	assert_int(_world.sim.wallet.balance).is_equal(0)
	assert_array(_paid).is_empty()


func test_with_no_wallet_nothing_is_settled_or_signalled() -> void:
	_make()
	var p := _guest(Passenger.Stage.TO_GATE)
	var visit := _world.sim.cafes.visit_of(p.id)
	_run_to_stage(p, Passenger.Stage.CAFE_SEATED)
	_world.sim.wallet = null
	_run_to_stage(p, Passenger.Stage.CAFE_STANDING_UP)
	assert_bool(visit.settled).is_false()
	assert_array(_paid).is_empty()
	assert_int(p.hunger).is_greater(0)
