extends GdUnitTestSuite
## The check-in room the line outside the entrance admits against
## (EntranceLine._reach(), board 66be00a0 fix round 3): a seeker inside takes
## its place on a desk it can reach before any claim is placed, so a claim never
## holds the only place that seeker can get to; and the room is worked out once
## per tick, however many desks stand and however many passengers come in.

const Claims := preload("res://tests/passengers/test_entrance_line_claims.gd")

## Where a seeker behind the split hall's wall stands: it reaches the walled
## desk only, and the door the other desk only.
const BEHIND_WALL := Vector2i(12, 12)

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
	_world = null


## A passenger inside on `cell` looking for a desk, waiting for a place, there
## before anyone outside is admitted.
func _seeker(cell: Vector2i) -> Passenger:
	var p := HoldLineKit.passenger(_world, cell, Passenger.Stage.TO_CHECKIN)
	_world.sim.entrance.forget(p.id)
	p.stuck = Passenger.Stuck.QUEUE_FULL
	return p


## [door reaches, `p` reaches, free places] for `desk`'s next place.
func _reach_of(desk: int, p: Passenger) -> Array:
	var sim := _world.sim
	var line := sim.layout.line_of(desk)
	var at := PassengerStations.slot(sim, desk)
	var q := sim._queue(desk)
	var door := TestEntranceLine._door(_world)
	return [
		not StationQueue.set_off(sim.grid, q, line, sim._by_id, door, at).is_empty(),
		not StationQueue.set_off(sim.grid, q, line, sim._by_id, p.at, at).is_empty(),
		line.size() - at,
	]


## A seeker behind the wall reaches only the walled desk: it takes none of
## the one place the door reaches, so one arrival is admitted on it, and the
## seeker then goes to the walled desk.
func test_a_seeker_who_cannot_reach_the_door_side_desk_leaves_its_place_to_the_line() -> void:
	_world = Claims._split_hall(1)
	var sim := _world.sim
	var reach: int = sim.get_meta(&"reach")
	var walled: int = sim.get_meta(&"walled")
	var seeker := _seeker(BEHIND_WALL)
	var reach_state := _reach_of(reach, seeker)
	var walled_state := _reach_of(walled, seeker)
	prints("reach desk", reach_state, "walled desk", walled_state)
	# Control: the door reaches only the desk on its side, with one place; the
	# seeker only the walled one.
	assert_array(reach_state).is_equal([true, false, 1])
	assert_array(walled_state.slice(0, 2)).is_equal([false, true])
	assert_int(walled_state[2]).is_greater(0)
	var claimant := sim.spawn_now(PassengerTestWorld.FLIGHT)
	prints(
		"claims",
		sim.entrance.claims,
		"stations",
		sim.entrance.stations,
		"waiting",
		sim.entrance.order
	)
	assert_array(sim.entrance.claims).is_equal([claimant])
	assert_int(int(sim.entrance.stations[claimant])).is_equal(reach)
	PassengerStations.choose(sim, seeker)
	prints("seeker", seeker.station, Passenger.Stuck.keys()[seeker.stuck])
	assert_int(seeker.station).is_equal(walled)


## With a second seeker on the door's side, there before anyone is admitted,
## the one place the door reaches is that seeker's: the arrival waits outside,
## and the seeker takes the place.
func test_a_claim_never_takes_the_only_place_a_seeker_inside_can_reach() -> void:
	_world = Claims._split_hall(1)
	var sim := _world.sim
	var reach: int = sim.get_meta(&"reach")
	var walled: int = sim.get_meta(&"walled")
	var behind := _seeker(BEHIND_WALL)
	var near := _seeker(Vector2i(4, 12))
	assert_array(_reach_of(reach, near)).is_equal([true, true, 1])
	assert_bool(_reach_of(walled, near)[1]).is_false()
	var arrival := sim.spawn_now(PassengerTestWorld.FLIGHT)
	prints("claims", sim.entrance.claims, "waiting", sim.entrance.order)
	assert_array(sim.entrance.claims).is_empty()
	assert_array(sim.entrance.order).is_equal([arrival])
	PassengerStations.choose(sim, behind)
	PassengerStations.choose(sim, near)
	prints("seekers", behind.station, near.station)
	assert_int(behind.station).is_equal(walled)
	assert_int(near.station).is_equal(reach)


## Seven desks, each with two places free, and twenty arrivals: in a tick the
## line looks for the way to each desk's place once, plus once a desk per
## seeker inside, however many it admits or turns away that tick.
func test_the_room_is_worked_out_once_a_tick_with_many_desks() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(16, 22))
	var desks: Array[int] = []
	for x in [1, 3, 5, 7, 9, 11, 13]:
		desks.append(PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(x, 1), 0))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(8, 21), 2)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	var sim := _world.sim
	for desk in desks:
		for i in sim.layout.line_of(desk).size() - 2:
			HoldLineKit.member(_world, desk)
	var inside := 0
	for p in sim._passengers:
		inside += int(PassengerStations.is_seeking(sim, p, true))
	# One tick, and twenty arrivals at its end, before the next.
	var start := sim.entrance.reach_queries
	_world.step()
	TestEntranceLine._arrive(_world, 20)
	var on_arrival := sim.entrance.reach_queries - start
	var admitted := sim.entrance.claims.size()
	var most := 0
	var total := 0
	for t in 40:
		var seekers := 0
		for p in sim._passengers:
			seekers += int(not p.is_done() and PassengerStations.is_seeking(sim, p, true))
		var before := sim.entrance.reach_queries
		_world.step()
		var spent := sim.entrance.reach_queries - before
		total += spent
		most = maxi(most, spent)
		assert_int(spent).is_less_equal(desks.size() * (1 + seekers))
	prints(
		"admitted",
		admitted,
		"waiting",
		sim.entrance.order.size(),
		"queries for the tick and its 20 arrivals",
		on_arrival,
		"a tick at most",
		most,
		"in 40 ticks",
		total
	)
	# A tick and twenty arrivals, with nobody inside looking: one look a desk.
	assert_int(inside).is_equal(0)
	assert_int(on_arrival).is_less_equal(desks.size())
	# Control: the line admitted some and kept the rest waiting, and it looked.
	assert_int(admitted).is_equal(14)
	assert_int(sim.entrance.order.size()).is_greater(0)
	assert_int(on_arrival).is_greater(0)
	assert_int(total).is_greater(0)
