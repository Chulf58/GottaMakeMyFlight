class_name TestToiletNeed
extends GdUnitTestSuite
## The toilet need (decision toilet-design-queue-free-reservable-stalls-per-
## stall-daily-u, point 5; decision a-passenger-with-a-high-need-detours-to-
## the-nearest-facility): drawn from the sim RNG at spawn, rising once a
## second; from ToiletSim.NEED_AT the passenger detours to a toilet only when
## the forecast allows, and otherwise carries on and loses mood. With hunger
## high as well, the toilet comes first.

## A floored world with the exit on the north edge, a cafe in the north-east
## and a toilet room south of it, everyone airside. With no gate seats a
## passenger waits standing at the gate until boarding and has its beats there.
const SIZE := Vector2i(30, 20)
const EXIT_CELL := Vector2i(2, 0)
const ENTRANCE_CELL := Vector2i(2, 19)
const CAFE_ROOM := Rect2i(16, 2, 6, 6)
const TOILET_ROOM := Rect2i(16, 10, 4, 4)
const GUEST_CELL := Vector2i(12, 8)
const BOARDING := 5000
const DOORS := 6000

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


func _floor_world(toilet := true) -> PassengerTestWorld:
	var grid := PassengerTestWorld.floored(SIZE)
	PassengerTestWorld.place(grid, &"exit_door", EXIT_CELL, 0)
	PassengerTestWorld.place(grid, &"entrance_door", ENTRANCE_CELL, 2)
	assert_bool(grid.apply(BuildEdit.place_room(CAFE_ROOM, &"cafe")).ok).is_true()
	PassengerTestWorld.place(grid, &"cafe_counter", Vector2i(17, 2), 0)
	PassengerTestWorld.place(grid, &"cafe_table", Vector2i(18, 5), 0)
	if toilet:
		assert_bool(grid.apply(BuildEdit.place_room(TOILET_ROOM, &"toilet")).ok).is_true()
		PassengerTestWorld.place(grid, &"toilet_stall", Vector2i(17, 10), 0)
		PassengerTestWorld.place(grid, &"toilet_sink", Vector2i(19, 10), 0)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(BOARDING, DOORS))
	_world.sim.apron_waypoints = PackedVector3Array()
	_world.run_to(10)
	return _world


## A calm cleared passenger standing at GUEST_CELL, heading for the gate.
func _airside() -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _world.clock.tick
	p.at = GUEST_CELL
	p.clear_path()
	return p


## The next tick on which `p` has its beat.
func _next_beat(p: Passenger) -> int:
	var t := _world.clock.tick + 1
	while posmod(t, PassengerSim.BEAT_TICKS) != posmod(p.id, PassengerSim.BEAT_TICKS):
		t += 1
	return t


func test_the_need_is_drawn_at_spawn_and_rises_once_a_second() -> void:
	_world = PassengerTestWorld.reference_world(7)
	var seen := {}
	for i in 40:
		var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		assert_int(p.toilet_need).is_between(ToiletSim.NEED_START_MIN, ToiletSim.NEED_START_MAX)
		seen[p.toilet_need] = true
	print("40 spawns drew %d distinct needs" % seen.size())
	assert_int(seen.size()).is_greater(10)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.toilet_need = 10
	_world.run_to(_world.clock.tick + 5 * PassengerSim.BEAT_TICKS)
	print("need after 5 beats %d" % p.toilet_need)
	assert_int(p.toilet_need).is_equal(10 + 5 * ToiletSim.NEED_RISE)


func test_a_high_need_with_no_toilet_costs_mood_and_a_low_one_does_not() -> void:
	_floor_world(false)
	var needy := _airside()
	var easy := _airside()
	needy.toilet_need = ToiletSim.NEED_AT + 10
	needy.toilet_cooldown = 0
	var start := _world.clock.tick
	var end := start + 40 * PassengerSim.BEAT_TICKS
	_world.run_to(end)
	# Mood point beats: the passenger's own beats on every MOOD_BEATS-th second.
	var expected := 0
	for t in range(start + 1, end + 1):
		@warning_ignore("integer_division")
		var second := t / PassengerSim.BEAT_TICKS
		var own := posmod(t, PassengerSim.BEAT_TICKS) == posmod(needy.id, PassengerSim.BEAT_TICKS)
		if own and posmod(second, ToiletSim.MOOD_BEATS) == 0:
			expected += 1
	print("mood needy %d easy %d, expected gap %d" % [needy.mood, easy.mood, expected])
	assert_int(expected).is_greater(5)
	assert_int(easy.mood - needy.mood).is_equal(expected)
	# It never had a visit, and kept trying every RETRY_TICKS.
	assert_object(_world.sim.toilets.visit_of(needy.id)).is_null()
	assert_int(needy.toilet_cooldown).is_greater(end - PassengerSim.BEAT_TICKS)


func test_with_no_time_left_the_passenger_carries_on_and_still_makes_the_flight() -> void:
	_floor_world()
	# Control: with time to spare the same passenger is admitted.
	var early := _airside()
	early.toilet_need = 95
	assert_bool(_world.sim.toilets.try_visit(early)).is_true()
	# Near the doors closing a visit no longer fits: it walks on to the plane.
	_world.run_to(DOORS - 250)
	var late := _airside()
	late.toilet_need = 95
	assert_bool(_world.sim.toilets.try_visit(late)).is_false()
	assert_object(_world.sim.toilets.visit_of(late.id)).is_null()
	assert_int(late.stage).is_equal(Passenger.Stage.TO_GATE)
	_world.run_to(DOORS + 1)
	print(
		(
			"early %s, late %s"
			% [Passenger.Stage.keys()[early.stage], Passenger.Stage.keys()[late.stage]]
		)
	)
	assert_int(early.stage).is_equal(Passenger.Stage.MADE)
	assert_int(late.stage).is_equal(Passenger.Stage.MADE)


func test_with_hunger_and_toilet_need_both_high_the_toilet_comes_first() -> void:
	_floor_world()
	var both := _airside()
	var hungry := _airside()
	for p in [both, hungry]:
		p.hunger = 90
		p.cafe_cooldown = 0
	both.toilet_need = 90
	both.toilet_cooldown = 0
	_world.run_to(maxi(_next_beat(both), _next_beat(hungry)))
	var toilets := _world.sim.toilets
	var cafes := _world.sim.cafes
	print(
		(
			"both: toilet %s cafe %s; hungry only: toilet %s cafe %s"
			% [
				toilets.visit_of(both.id) != null,
				cafes.visit_of(both.id) != null,
				toilets.visit_of(hungry.id) != null,
				cafes.visit_of(hungry.id) != null,
			]
		)
	)
	assert_object(toilets.visit_of(both.id)).is_not_null()
	assert_object(cafes.visit_of(both.id)).is_null()
	assert_int(StageKinds.visit_facility(_world.sim, both)).is_equal(StageKinds.Facility.TOILET)
	# Control: hunger alone takes the same kind of passenger to the cafe.
	assert_object(cafes.visit_of(hungry.id)).is_not_null()
	assert_object(toilets.visit_of(hungry.id)).is_null()
	# A cafe visit is never started on top of a toilet visit.
	assert_bool(cafes.try_visit(both)).is_false()
