class_name TestScreenRelief
extends GdUnitTestSuite
## Screen relief (Boredom 4/5; decision boredom-and-shops-design-boredom-need-
## while-waiting-kiosk-sh, point 3): a waiting passenger a screen stand covers
## has its boredom fall BoredomSim.RELIEF every RELIEF_BEATS beats instead of
## rising, down to 0; nobody else is relieved, and two screens relieve no
## faster than one. A seated passenger watches from its chair.

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


func test_relief_is_slower_than_the_rise() -> void:
	assert_int(BoredomSim.RELIEF).is_greater(0)
	assert_int(BoredomSim.RELIEF_BEATS).is_greater(1)
	assert_int(BoredomSim.RELIEF).is_less_equal(BoredomSim.RISE)


func test_a_standing_passenger_in_coverage_gets_less_bored() -> void:
	_screen()
	var p := _guest(Passenger.Stage.STANDING, 60)
	var beats := 6 * BoredomSim.RELIEF_BEATS
	_run_beats(p, beats)
	print("%d beats under a screen: 60 -> %d" % [beats, p.boredom])
	assert_int(p.stage).is_equal(Passenger.Stage.STANDING)
	assert_int(p.boredom).is_equal(60 - 6 * BoredomSim.RELIEF)


func test_it_stops_at_zero() -> void:
	_screen()
	var p := _guest(Passenger.Stage.STANDING, 1)
	_run_beats(p, 4 * BoredomSim.RELIEF_BEATS)
	assert_int(p.boredom).is_equal(0)


func test_a_passenger_behind_the_screen_still_gets_bored() -> void:
	_screen(SCREEN_CELL, 2)
	var p := _guest(Passenger.Stage.STANDING, 20)
	assert_bool(_world.sim.boredom.relieves(p)).is_false()
	_run_beats(p, 6)
	assert_int(p.boredom).is_equal(20 + 6 * BoredomSim.RISE)


func test_only_waiting_stages_are_relieved() -> void:
	_screen()
	var boredom := _world.sim.boredom
	var p := Passenger.new()
	p.at = GUEST_CELL
	var relieved: Array[Passenger.Stage] = []
	for stage: Passenger.Stage in Passenger.Stage.values():
		p.stage = stage
		if boredom.relieves(p):
			relieved.append(stage)
			assert_bool(boredom.rises(p)).is_false()
		else:
			# Nothing else falls under a screen.
			p.boredom = 10
			boredom.beat(p)
			assert_int(p.boredom).is_greater_equal(10)
	print(
		"relieved in %s" % [relieved.map(func(s: int) -> String: return Passenger.Stage.keys()[s])]
	)
	assert_array(relieved).contains_exactly_in_any_order(BoredomSim.WAITING_STAGES)
	# Walking through the coverage leaves boredom as it is.
	p.stage = Passenger.Stage.TO_GATE
	p.boredom = 30
	boredom.beat(p)
	assert_int(p.boredom).is_equal(30)


func test_a_seated_passenger_watches_from_its_chair() -> void:
	var p := Passenger.new()
	p.stage = Passenger.Stage.SEATED
	p.at = Vector2i(1, 1)
	p.seat_cell = GUEST_CELL
	assert_bool(_world.sim.boredom.relieves(p)).is_false()
	_screen()
	assert_vector(Vector2(BoredomSim.watch_cell(p))).is_equal(Vector2(GUEST_CELL))
	assert_bool(_world.sim.boredom.relieves(p)).is_true()
	p.stage = Passenger.Stage.STANDING
	assert_bool(_world.sim.boredom.relieves(p)).is_false()


func test_two_screens_relieve_no_faster_than_one() -> void:
	_screen()
	var p := _guest(Passenger.Stage.STANDING, 80)
	var beats := 4 * BoredomSim.RELIEF_BEATS
	_run_beats(p, beats)
	var with_one := 80 - p.boredom
	_screen(GUEST_CELL + Vector2i(0, 2), 2)
	_screen(GUEST_CELL + Vector2i(-2, 0), 3)
	var before := p.boredom
	_run_beats(p, beats)
	var with_three := before - p.boredom
	print("over %d beats: one screen -%d, three screens -%d" % [beats, with_one, with_three])
	assert_int(with_one).is_equal(4 * BoredomSim.RELIEF)
	assert_int(with_three).is_equal(with_one)


func test_removing_the_screen_lets_boredom_rise_again() -> void:
	var screen := _screen()
	var p := _guest(Passenger.Stage.STANDING, 40)
	_run_beats(p, 2 * BoredomSim.RELIEF_BEATS)
	assert_int(p.boredom).is_less(40)
	assert_bool(_world.grid.apply(BuildEdit.remove_object(screen)).ok).is_true()
	var before := p.boredom
	_run_beats(p, 3)
	assert_int(p.boredom).is_equal(before + 3 * BoredomSim.RISE)
