class_name TestScreenRelief
extends GdUnitTestSuite
## Screens slow boredom (Boredom 4/5; decision boredom-screens-halve-how-fast-
## boredom-rises-for-covered-wai): a waiting passenger a screen stand covers
## gets bored at half the rate, RISE once every BoredomSim.SCREEN_RISE_BEATS
## beats, and a screen never lowers boredom. Nobody else is slowed, two
## screens slow it no more than one, and removing the screen restores the full
## rate. A seated passenger watches from its chair.

const SIZE := Vector2i(30, 20)
const SEAT_ROW_CELL := Vector2i(3, 14)
const GUEST_CELL := Vector2i(12, 8)
## Two rows north of GUEST_CELL, facing south, so it covers GUEST_CELL.
const SCREEN_CELL := Vector2i(12, 6)
const BOARDING := 5000
const DOORS := 6000

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(SIZE)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(2, 0), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(2, 19), 2)
	PassengerTestWorld.place(grid, &"seat_row", SEAT_ROW_CELL, 0)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(BOARDING, DOORS))
	_world.sim.apron_waypoints = PackedVector3Array()
	_world.run_to(10)


func after_test() -> void:
	_world.free_all()
	_world = null


func _screen(cell := SCREEN_CELL, facing := 0) -> int:
	return PassengerTestWorld.place(_world.grid, ScreenCoverage.SCREEN_ID, cell, facing)


## A calm cleared passenger at `cell` in `stage`, `boredom` bored.
func _guest(stage: Passenger.Stage, boredom: int, cell := GUEST_CELL) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = stage
	p.stage_tick = _world.clock.tick
	p.at = cell
	p.clear_path()
	p.boredom = boredom
	p.shop_cooldown = 0
	return p


## Steps the world over `p`'s next `beats` beats.
func _run_beats(p: Passenger, beats: int) -> void:
	for i in beats:
		var t := _world.clock.tick + 1
		while posmod(t, PassengerSim.BEAT_TICKS) != posmod(p.id, PassengerSim.BEAT_TICKS):
			t += 1
		_world.run_to(t)


func test_a_screen_halves_the_rise() -> void:
	assert_int(BoredomSim.SCREEN_RISE_BEATS).is_equal(2)


func test_a_standing_passenger_in_coverage_gets_bored_at_half_the_rate() -> void:
	_screen()
	var p := _guest(Passenger.Stage.STANDING, 20)
	var beats := 6 * BoredomSim.SCREEN_RISE_BEATS
	_run_beats(p, beats)
	print("%d beats under a screen: 20 -> %d" % [beats, p.boredom])
	assert_int(p.stage).is_equal(Passenger.Stage.STANDING)
	assert_int(p.boredom).is_equal(20 + 6 * BoredomSim.RISE)


func test_a_screen_never_lowers_boredom() -> void:
	_screen()
	var p := _guest(Passenger.Stage.STANDING, 30)
	var seen: Array[int] = [p.boredom]
	for i in 4 * BoredomSim.SCREEN_RISE_BEATS:
		_run_beats(p, 1)
		assert_int(p.boredom).is_greater_equal(seen.back())
		seen.append(p.boredom)
	print("boredom beat by beat under a screen: %s" % [seen])
	assert_int(p.boredom).is_equal(30 + 4 * BoredomSim.RISE)
	# It still stops at the cap.
	p.boredom = BoredomSim.MAX
	_run_beats(p, BoredomSim.SCREEN_RISE_BEATS)
	assert_int(p.boredom).is_equal(BoredomSim.MAX)


func test_a_passenger_behind_the_screen_rises_at_the_full_rate() -> void:
	_screen(SCREEN_CELL, 2)
	var p := _guest(Passenger.Stage.STANDING, 20)
	assert_bool(_world.sim.boredom.watching(p)).is_false()
	_run_beats(p, 6)
	assert_int(p.boredom).is_equal(20 + 6 * BoredomSim.RISE)


func test_only_waiting_stages_watch() -> void:
	_screen()
	var boredom := _world.sim.boredom
	var p := Passenger.new()
	p.at = GUEST_CELL
	var watched: Array[Passenger.Stage] = []
	for stage: Passenger.Stage in Passenger.Stage.values():
		p.stage = stage
		if boredom.watching(p):
			watched.append(stage)
			# Watching slows the rise; it does not stop it.
			assert_bool(boredom.rises(p)).is_true()
		else:
			p.boredom = 10
			boredom.beat(p)
			assert_int(p.boredom).is_equal(10)
	print("watched in %s" % [watched.map(func(s: int) -> String: return Passenger.Stage.keys()[s])])
	assert_array(watched).contains_exactly_in_any_order(BoredomSim.WAITING_STAGES)


func test_the_entertainment_freeze_still_holds_under_a_screen() -> void:
	_screen()
	var p := _guest(Passenger.Stage.STANDING, 30)
	var boredom := _world.sim.boredom
	boredom.entertainment = func(q: Passenger) -> bool: return q.id == p.id
	_run_beats(p, 2 * BoredomSim.SCREEN_RISE_BEATS)
	boredom.entertainment = Callable()
	assert_int(p.boredom).is_equal(30)


func test_a_seated_passenger_watches_from_its_chair() -> void:
	var p := Passenger.new()
	p.stage = Passenger.Stage.SEATED
	p.at = Vector2i(1, 1)
	p.seat_cell = GUEST_CELL
	assert_bool(_world.sim.boredom.watching(p)).is_false()
	_screen()
	assert_vector(Vector2(BoredomSim.watch_cell(p))).is_equal(Vector2(GUEST_CELL))
	assert_bool(_world.sim.boredom.watching(p)).is_true()
	p.stage = Passenger.Stage.STANDING
	assert_bool(_world.sim.boredom.watching(p)).is_false()


func test_two_screens_slow_it_no_more_than_one() -> void:
	_screen()
	var p := _guest(Passenger.Stage.STANDING, 20)
	var beats := 4 * BoredomSim.SCREEN_RISE_BEATS
	_run_beats(p, beats)
	var with_one := p.boredom - 20
	_screen(GUEST_CELL + Vector2i(0, 2), 2)
	_screen(GUEST_CELL + Vector2i(-2, 0), 3)
	var before := p.boredom
	_run_beats(p, beats)
	var with_three := p.boredom - before
	print("over %d beats: one screen +%d, three screens +%d" % [beats, with_one, with_three])
	assert_int(with_one).is_equal(4 * BoredomSim.RISE)
	assert_int(with_three).is_equal(with_one)


func test_removing_the_screen_restores_the_full_rate() -> void:
	var screen := _screen()
	var p := _guest(Passenger.Stage.STANDING, 40)
	_run_beats(p, 2 * BoredomSim.SCREEN_RISE_BEATS)
	assert_int(p.boredom).is_equal(40 + 2 * BoredomSim.RISE)
	assert_bool(_world.grid.apply(BuildEdit.remove_object(screen)).ok).is_true()
	var before := p.boredom
	_run_beats(p, 3)
	assert_int(p.boredom).is_equal(before + 3 * BoredomSim.RISE)
