class_name TestVisitZeroSlack
extends GdUnitTestSuite
## An ordinary toilet or cafe visit the forecast admits is never cut short on
## its deadline tick (board a791eb90; the relocation returns had the same
## off-by-one, commit 857ebdd). step() sends a visitor off early on any tick at
## or past the deadline, so a visit whose stand-up falls exactly on the
## deadline (zero slack) must be refused at admission, not admitted and then cut
## (cafe: SHORT pay).
##
## A first run with the doors closing at BASE_DOORS finds the tick the visit
## stands up (E) and the deadline it was admitted with (D0). Runs with the
## doors moved by E - D0 + k then admit the same visit with k ticks of slack
## (the deadline moves with the doors one for one), and every one of them that
## is admitted must stand up when it is due, with the full outcome.

const BASE_DOORS := 4000
const BOARDING := 300
## Slack offsets swept around zero.
const OFFSETS: Array[int] = [-3, -2, -1, 0, 1, 2, 3]

var _world: PassengerTestWorld
## [stage, tick] entered by the passenger under test, in order.
var _stages: Array = []
var _outcome := CafeVisit.Outcome.NONE


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null
	_stages.clear()


func _track(p: Passenger) -> void:
	_stages.clear()
	_outcome = CafeVisit.Outcome.NONE
	var sim := _world.sim
	sim.stage_changed.connect(
		func(id: int, stage: Passenger.Stage) -> void:
			if id != p.id:
				return
			_stages.append([stage, sim.tick])
			if stage == Passenger.Stage.CAFE_STANDING_UP:
				_outcome = sim.cafes.visit_of(id).outcome
	)


## The tick `p` last entered `stage`, or -1.
func _entered(stage: Passenger.Stage) -> int:
	var found := -1
	for entry: Array in _stages:
		if entry[0] == stage:
			found = entry[1]
	return found


## An airside guest at the point it can start a visit to a `venue` (a stall is a
## walk-on counter: a grab and go order, no seat), with the doors closing at
## `doors`. Returns {"admitted", "deadline"}; the guest has started when admitted.
func _cafe_start(doors: int, venue: StringName = &"cafe", tables := true) -> Dictionary:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid, false, venue, tables)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(BOARDING, doors))
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	_track(p)
	p.hunger = 0
	p.cafe_cooldown = 1000000
	var cafes := _world.sim.cafes
	var plan := {}
	while plan.is_empty() and _world.clock.tick < BOARDING - 20:
		_world.step()
		if p.stage == Passenger.Stage.TO_GATE:
			plan = cafes.plan_visit(p)
	if plan.is_empty():
		return {"admitted": false, "p": p}
	cafes.commit_visit(p, plan)
	return {"admitted": true, "p": p, "deadline": cafes.visit_of(p.id).deadline}


## Steps until `p` is standing up from the cafe seat.
func _cafe_run(p: Passenger) -> void:
	var until := _world.clock.tick + 1500
	while p.stage != Passenger.Stage.CAFE_STANDING_UP and _world.clock.tick < until:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_STANDING_UP)


## Steps until the stall visit is over, and returns the tick it ended.
func _stall_run(p: Passenger) -> int:
	var until := _world.clock.tick + 1500
	while _world.sim.cafes.visit_of(p.id) != null and _world.clock.tick < until:
		_world.step()
	assert_object(_world.sim.cafes.visit_of(p.id)).is_null()
	return _world.clock.tick


## A landside toilet user at the point it can start its visit, with the doors
## closing at `doors`. Returns {"admitted", "deadline"}.
func _toilet_start(doors: int) -> Dictionary:
	var grid := BuildGrid.new()
	ToiletTestLayout.build(grid, 1)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(BOARDING, doors))
	_world.run_to(10)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	_track(p)
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.stage = Passenger.Stage.TO_SECURITY
	p.stage_tick = _world.clock.tick
	p.at = Vector2i(20, 14) + ReferenceTerminal.offset_on(_world.grid)
	p.clear_path()
	p.toilet_need = 90
	var toilets := _world.sim.toilets
	var plan := toilets.plan_visit(p)
	if plan.is_empty():
		return {"admitted": false, "p": p}
	toilets.commit_visit(p, plan)
	return {"admitted": true, "p": p, "deadline": toilets.visit_of(p.id).deadline}


## Steps until `p` is using the stall, then until it stands up.
func _toilet_run(p: Passenger) -> void:
	var until := _world.clock.tick + 1500
	while p.stage != Passenger.Stage.TOILET_STANDING_UP and _world.clock.tick < until:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.TOILET_STANDING_UP)


func _free_world() -> void:
	_world.free_all()
	_world = null


func test_a_cafe_visit_admitted_at_any_slack_is_not_cut_short() -> void:
	var base := _cafe_start(BASE_DOORS)
	assert_bool(base["admitted"]).is_true()
	_cafe_run(base["p"])
	var due := _entered(Passenger.Stage.CAFE_STANDING_UP)
	var shift: int = due - base["deadline"]
	_free_world()
	var admitted := 0
	var refused := 0
	var tightest := 1000
	var report := ""
	for k in OFFSETS:
		var start := _cafe_start(BASE_DOORS + shift + k)
		if not start["admitted"]:
			refused += 1
		else:
			admitted += 1
			tightest = mini(tightest, start["deadline"] - due)
			_cafe_run(start["p"])
			if (
				_entered(Passenger.Stage.CAFE_STANDING_UP) != due
				or _outcome != CafeVisit.Outcome.COMPLETE
			):
				report += (
					" slack %d: stood up at %d (due %d), outcome %d;"
					% [
						start["deadline"] - due,
						_entered(Passenger.Stage.CAFE_STANDING_UP),
						due,
						_outcome
					]
				)
		_free_world()
	# The sweep crosses the admission line: some offsets in, some out, and the
	# tightest one admitted stands up a tick before its deadline.
	assert_int(admitted).is_greater(0)
	assert_int(refused).is_greater(0)
	assert_int(tightest).is_equal(1)
	assert_str(report).is_empty()


func test_a_toilet_visit_admitted_at_any_slack_is_not_cut_short() -> void:
	var base := _toilet_start(BASE_DOORS)
	assert_bool(base["admitted"]).is_true()
	_toilet_run(base["p"])
	var due := _entered(Passenger.Stage.TOILET_STANDING_UP)
	var shift: int = due - base["deadline"]
	_free_world()
	var admitted := 0
	var refused := 0
	var tightest := 1000
	var report := ""
	for k in OFFSETS:
		var start := _toilet_start(BASE_DOORS + shift + k)
		if not start["admitted"]:
			refused += 1
		else:
			admitted += 1
			tightest = mini(tightest, start["deadline"] - due)
			_toilet_run(start["p"])
			var stood := _entered(Passenger.Stage.TOILET_STANDING_UP)
			if stood != due:
				report += (
					" slack %d: stood up at %d (due %d);" % [start["deadline"] - due, stood, due]
				)
		_free_world()
	assert_int(admitted).is_greater(0)
	assert_int(refused).is_greater(0)
	# Standing up on the deadline tick is the same as finishing the use there.
	assert_int(tightest).is_equal(0)
	assert_str(report).is_empty()


func test_a_stall_visit_admitted_at_any_slack_is_served_and_paid() -> void:
	var base := _cafe_start(BASE_DOORS, &"stall", false)
	assert_bool(base["admitted"]).is_true()
	assert_bool(_world.sim.cafes.visit_of(base["p"].id).walk_on()).is_true()
	var due := _stall_run(base["p"])
	assert_int(_world.sim.wallet.balance).is_greater(0)
	var shift: int = due - base["deadline"]
	_free_world()
	var admitted := 0
	var refused := 0
	var tightest := 1000
	var report := ""
	for k in OFFSETS:
		var start := _cafe_start(BASE_DOORS + shift + k, &"stall", false)
		if not start["admitted"]:
			refused += 1
		else:
			admitted += 1
			tightest = mini(tightest, start["deadline"] - due)
			var ended := _stall_run(start["p"])
			if ended != due or _world.sim.wallet.balance <= 0:
				report += (
					" slack %d: ended at %d (due %d), paid %d;"
					% [start["deadline"] - due, ended, due, _world.sim.wallet.balance]
				)
		_free_world()
	assert_int(admitted).is_greater(0)
	assert_int(refused).is_greater(0)
	# Served on the deadline tick is given up unpaid, so the tightest admitted
	# is served a tick before it.
	assert_int(tightest).is_equal(1)
	assert_str(report).is_empty()
