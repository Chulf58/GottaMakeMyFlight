class_name TestHandOffSpacing
extends GdUnitTestSuite
## A passenger stepping onto the boarding route from the security exit cell or
## from a gate seat's front cell waits for a clear slot: on its first TO_EXIT
## tick it is not within a body's width of a walker in a boarding file or
## waiting for one (board c1800254, decision passenger-spacing-fixed-per-cause-
## standing-spots-staggered-unloading-ordered-files). Each case puts a filed
## walker on the hand-off cell, so the passenger meets it as it sets off.

const SECURITY_EXIT := Vector2i(17, 7)
## The first tick a hand-off may take place on in these worlds.
const BOARDING := 20

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
	_world = null


## The ground distance from `p` to the nearest other walker heading out that is
## in a boarding file or waiting for one, and its id: [metres, id], with a
## large distance and id 0 when there is none.
static func nearest_filed(world: PassengerTestWorld, p: Passenger) -> Array:
	var best := 99.0
	var who := 0
	for id in world.sim.passenger_ids():
		var q := world.passenger(id)
		if id == p.id or not TestBoardingFiles.heading_out(q) or not world.sim.files.holds(id):
			continue
		var d := TestBoardingFiles.apart(world, p, q)
		if d < best:
			best = d
			who = id
	return [best, who]


## Steps until `p` turns to the exit; returns [ticks it waited after the filed
## walker was filed, the distance to the nearest filed walker on that tick].
func _until_it_sets_off(p: Passenger, limit := 200) -> Array:
	var waited := 0
	for i in limit:
		_world.step()
		if p.stage == Passenger.Stage.TO_EXIT:
			return [waited, nearest_filed(_world, p)[0]]
		waited += 1
	assert_bool(false).override_failure_message("passenger never set off").is_true()
	return [waited, 0.0]


func test_a_cleared_passenger_waits_at_the_security_exit_for_a_walker_leaving_it() -> void:
	_world = TestBoardingFiles.boarding_world()
	_world.run_to(BOARDING + 5)
	var ahead := TestBoardingFiles.walker(_world, SECURITY_EXIT)
	var cleared := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	TestBoardingFiles.turn_out(_world, cleared, SECURITY_EXIT)
	cleared.stage = Passenger.Stage.TO_GATE
	# The walker is filed and on the cell this tick: the control that the
	# hand-off meets one.
	_world.step()
	assert_bool(_world.sim.files.holds(ahead.id)).is_true()
	assert_float(nearest_filed(_world, cleared)[0]).is_less(TestBoardingFiles.BODY_M)
	var result := _until_it_sets_off(cleared)
	print("cleared waited %d ticks, then %.3f m from the nearest filed walker" % result)
	assert_int(result[0]).is_greater(0)
	assert_float(result[1]).is_greater_equal(TestBoardingFiles.BODY_M)


## A passenger up from a gate seat with a filed walker on its seat-front cell.
func test_a_passenger_up_from_a_gate_seat_waits_for_a_walker_on_its_front_cell() -> void:
	_world = PassengerTestWorld.reference_world(3)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	TestBoardingFiles.turn_out(_world, p, SECURITY_EXIT)
	p.stage = Passenger.Stage.TO_GATE
	while p.stage != Passenger.Stage.SEATED and _world.clock.tick < 1400:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SEATED)
	# Boarding opens now; the seat is given up after the stand-up.
	p.boarding_tick = _world.clock.tick + 1
	while p.stage != Passenger.Stage.STANDING_UP and _world.clock.tick < 1400:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.STANDING_UP)
	# The walker is filed one tick before the passenger's stand-up ends.
	while _world.clock.tick - p.stage_tick < ParkRecovery.stand_up_ticks(p) - 2:
		_world.step()
	var ahead := TestBoardingFiles.walker(_world, p.seat_front)
	_world.step()
	assert_bool(_world.sim.files.holds(ahead.id)).is_true()
	var result := _until_it_sets_off(p)
	print("seated passenger waited %d ticks, then %.3f m from the nearest filed walker" % result)
	assert_int(result[0]).is_greater(0)
	assert_float(result[1]).is_greater_equal(TestBoardingFiles.BODY_M)
