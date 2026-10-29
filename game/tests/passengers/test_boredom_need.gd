class_name TestBoredomNeed
extends GdUnitTestSuite
## The boredom need (Boredom 1/5; decision boredom-and-shops-design-boredom-
## need-while-waiting-kiosk-sh, point 1): an integer need each passenger starts
## with from its id (no sim RNG drawn), rising once a second only while it
## waits (gate seated and standing, and every queue stage, cafe queues
## included), up to BoredomSim.MAX, and not while it is entertained. A bored
## passenger gets no mood from its gate seat and loses a point every
## BoredomSim.MOOD_BEATS seconds. With no kiosk built, NeedsPolicy starts no
## visit for it.

## A floored world with the exit on the north edge and one gate seat row in
## the south-west, away from GUEST_CELL, so a cleared passenger walks to it.
const SIZE := Vector2i(30, 20)
const SEAT_ROW_CELL := Vector2i(3, 14)
const GUEST_CELL := Vector2i(12, 8)
const BOARDING := 5000
const DOORS := 6000
## The stages boredom rises in.
const WAITING: Array[Passenger.Stage] = [
	Passenger.Stage.CHECKIN_QUEUE,
	Passenger.Stage.SECURITY_QUEUE,
	Passenger.Stage.CAFE_QUEUE,
	Passenger.Stage.SEATED,
	Passenger.Stage.STANDING,
]

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


## A calm cleared passenger at GUEST_CELL in `stage`, `boredom` bored.
func _guest(stage: Passenger.Stage, boredom: int) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = stage
	p.stage_tick = _world.clock.tick
	p.at = GUEST_CELL
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


func test_a_passenger_starts_with_the_boredom_its_id_gives() -> void:
	var seen := {}
	for i in 12:
		var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
		var boredom := _world.passenger(id).boredom
		assert_int(boredom).is_equal(BoredomSim.start_of(id))
		assert_int(boredom).is_between(BoredomSim.START_MIN, BoredomSim.START_MAX)
		seen[boredom] = true
	print("12 spawns, %d distinct starts" % seen.size())
	assert_int(seen.size()).is_greater(5)
	assert_int(BoredomSim.START_MAX).is_less(BoredomSim.BORED_AT)


func test_it_rises_in_every_waiting_stage_and_in_no_other() -> void:
	var p := Passenger.new()
	var rising: Array[Passenger.Stage] = []
	for stage: Passenger.Stage in Passenger.Stage.values():
		p.stage = stage
		p.boredom = 10
		_world.sim.boredom.beat(p)
		assert_int(p.boredom).is_equal(10 + BoredomSim.RISE if stage in WAITING else 10)
		if p.boredom > 10:
			rising.append(stage)
	print("rises in %s" % [rising.map(func(s: int) -> String: return Passenger.Stage.keys()[s])])
	assert_array(rising).contains_exactly_in_any_order(WAITING)
	assert_array(BoredomSim.WAITING_STAGES).contains_exactly_in_any_order(WAITING)


func test_it_does_not_rise_on_the_walk_to_a_gate_seat_and_rises_once_seated() -> void:
	var p := _guest(Passenger.Stage.TO_GATE, 20)
	var walked := 0
	while p.stage != Passenger.Stage.SEATED and walked < 60:
		var before := p.boredom
		var stage := p.stage
		_run_beats(p, 1)
		if p.stage == stage:
			assert_int(p.boredom).is_equal(before)
			walked += 1
	print("walked and sat down over %d beats at boredom %d, now %s" % [walked, p.boredom, p.stage])
	assert_int(walked).is_greater(2)
	assert_int(p.stage).is_equal(Passenger.Stage.SEATED)
	var seated := p.boredom
	_run_beats(p, 10)
	assert_int(p.stage).is_equal(Passenger.Stage.SEATED)
	print("10 beats seated: %d -> %d" % [seated, p.boredom])
	assert_int(p.boredom).is_equal(seated + 10 * BoredomSim.RISE)


func test_it_rises_once_a_second_standing_at_the_gate() -> void:
	var p := _guest(Passenger.Stage.STANDING, 20)
	_run_beats(p, 10)
	assert_int(p.stage).is_equal(Passenger.Stage.STANDING)
	assert_int(p.boredom).is_equal(20 + 10 * BoredomSim.RISE)


func test_it_stops_at_the_cap() -> void:
	var p := Passenger.new()
	p.stage = Passenger.Stage.STANDING
	p.boredom = BoredomSim.MAX - 1
	_world.sim.boredom.beat(p)
	assert_int(p.boredom).is_equal(BoredomSim.MAX)
	_world.sim.boredom.beat(p)
	assert_int(p.boredom).is_equal(BoredomSim.MAX)


func test_it_freezes_while_the_passenger_is_entertained() -> void:
	var p := _guest(Passenger.Stage.STANDING, 30)
	var other := _guest(Passenger.Stage.STANDING, 30)
	var boredom := _world.sim.boredom
	boredom.entertainment = func(q: Passenger) -> bool: return q.id == p.id
	assert_bool(boredom.entertained(p)).is_true()
	assert_bool(boredom.entertained(other)).is_false()
	boredom.beat(p)
	boredom.beat(other)
	assert_int(p.boredom).is_equal(30)
	assert_int(other.boredom).is_equal(30 + BoredomSim.RISE)
	# With nothing entertaining, it rises again.
	boredom.entertainment = Callable()
	assert_bool(boredom.entertained(p)).is_false()
	boredom.beat(p)
	assert_int(p.boredom).is_equal(30 + BoredomSim.RISE)


func test_a_bored_seated_passenger_gains_no_mood_and_loses_some() -> void:
	var bored := _guest(Passenger.Stage.SEATED, BoredomSim.BORED_AT)
	var calm := _guest(Passenger.Stage.SEATED, 0)
	bored.mood = 50
	calm.mood = 50
	var beats := 4 * BoredomSim.MOOD_BEATS
	_run_beats(bored, beats)
	_run_beats(calm, 1)
	assert_int(bored.stage).is_equal(Passenger.Stage.SEATED)
	print("after %d beats: bored mood %d, calm mood %d" % [beats, bored.mood, calm.mood])
	# Exactly one point every MOOD_BEATS beats, and no seat bonus.
	assert_int(bored.mood).is_equal(50 - beats / BoredomSim.MOOD_BEATS)
	# The calm one still gets its seat's point a beat.
	assert_int(calm.mood).is_greater(50 + beats - 2)


func test_a_bored_passenger_starts_no_visit_with_no_kiosk_built() -> void:
	var p := _guest(Passenger.Stage.STANDING, BoredomSim.MAX)
	assert_bool(_world.sim.shops.wants_relief(p)).is_true()
	var choice := NeedsPolicy.choose(_world.sim, p)
	assert_int(choice["need"]).is_equal(NeedsPolicy.Need.NONE)
	assert_array(choice["refused"]).is_equal([NeedsPolicy.Need.BOREDOM])
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.NONE)
	assert_int(StageKinds.visit_facility(_world.sim, p)).is_equal(StageKinds.Facility.NONE)
	p.boredom = BoredomSim.BORED_AT - 1
	assert_bool(_world.sim.shops.wants_relief(p)).is_false()
