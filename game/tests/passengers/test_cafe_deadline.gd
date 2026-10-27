class_name TestCafeDeadline
extends GdUnitTestSuite
## A cafe visit never makes a passenger miss a flight it would have made
## without it (decision cafe-visit-design-forecast-the-whole-itinerary-abandon-
## by-a, point 1): the deadline follows the "abandon now" forecast with the
## queues as they are, so a landside guest whose security queue fills during
## its visit leaves in time. The same stream of passengers is run twice: with
## no visit the guest passes security first and makes the flight; with the
## live deadline it leaves before the end of its visit and makes it. A landside
## deadline is forecast again every tick, so a burst at security right after
## the guest's beat sends it on at once.

## Just checked in, between the desks and the scanner lanes.
const CROWD_CELL := Vector2i(16, 12)
## One more passenger reaches security this often, faster than the two
## scanners serve them (one per 20 ticks), so the queue keeps growing.
const CROWD_EVERY := 7
const CROWD_UNTIL := 700
## Passengers who check in at once, enough to make a seated guest's deadline
## pass (two scanners, SECURITY_TICKS each).
const BURST := 16

var _worlds: Array[PassengerTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in _worlds:
		world.free_all()
	_worlds.clear()


## Runs the scenario: a guest admitted to a landside visit (unless `visit` is
## false) while security is empty, then a stream of passengers who have just
## checked in. Returns [the guest, the admission deadline, the earliest
## deadline, the visit or null].
func _scenario(visit_cafe: bool) -> Array:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_worlds.append(world)
	var guest := _new_passenger(world)
	while guest.stage != Passenger.Stage.TO_SECURITY and world.clock.tick < 600:
		world.step()
	var admitted := 0
	var visit: CafeVisit = null
	if visit_cafe:
		assert_bool(world.sim.cafes.try_visit(guest)).is_true()
		visit = world.sim.cafes.visit_of(guest.id)
		admitted = visit.deadline
		print("admitted at %d, deadline %d" % [world.clock.tick, admitted])
	var earliest := admitted
	while world.clock.tick < world.flights.doors_close_tick(guest.flight_id) + 1:
		if world.clock.tick < CROWD_UNTIL and posmod(world.clock.tick, CROWD_EVERY) == 0:
			_checked_in(world)
		var current := world.sim.cafes.visit_of(guest.id)
		if current != null:
			earliest = mini(earliest, current.deadline)
		world.step()
	return [guest, admitted, earliest, visit]


## A passenger who has just checked in and heads for security.
func _checked_in(world: PassengerTestWorld) -> void:
	var p := _new_passenger(world)
	p.stage = Passenger.Stage.TO_SECURITY
	p.at = CROWD_CELL
	p.clear_path()


func _new_passenger(world: PassengerTestWorld) -> Passenger:
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 0
	p.cafe_cooldown = 1000000
	return p


## A seated landside guest, just after its beat, and a burst of passengers
## who have just checked in: the burst choosing the scanners makes the guest's
## live deadline pass, and the guest leaves on the next tick rather than on
## its next beat, then still makes the flight.
func test_a_burst_at_security_right_after_the_guests_beat_sends_it_on_at_once() -> void:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_worlds.append(world)
	var guest := _new_passenger(world)
	while guest.stage != Passenger.Stage.TO_SECURITY and world.clock.tick < 600:
		world.step()
	assert_bool(world.sim.cafes.try_visit(guest)).is_true()
	var visit := world.sim.cafes.visit_of(guest.id)
	assert_int(visit.resume_stage).is_equal(Passenger.Stage.TO_SECURITY)
	while guest.stage != Passenger.Stage.CAFE_SEATED and world.clock.tick < 900:
		world.step()
	assert_int(guest.stage).is_equal(Passenger.Stage.CAFE_SEATED)
	# The tick of the guest's beat has just been stepped.
	while (
		posmod(world.clock.tick, PassengerSim.BEAT_TICKS)
		!= posmod(guest.id, PassengerSim.BEAT_TICKS)
	):
		world.step()
	var beat_tick := world.clock.tick
	var before_burst := visit.deadline
	for i in BURST:
		_checked_in(world)
	var approach: Vector2i = visit.seat["approach"]
	var due := -1
	while guest.stage == Passenger.Stage.CAFE_SEATED and world.clock.tick < beat_tick + 40:
		world.step()
		var fresh := CafeForecast.live_deadline(
			world.sim, guest, approach, Passenger.Stage.TO_SECURITY
		)
		if due < 0 and fresh <= world.clock.tick:
			due = world.clock.tick
	var left := world.clock.tick
	print(
		(
			"beat %d, deadline %d before the burst; due at %d, left at %d (%s)"
			% [beat_tick, before_burst, due, left, Passenger.Stage.keys()[guest.stage]]
		)
	)
	# The burst made the guest's deadline pass well before its next beat.
	assert_int(before_burst).is_greater(beat_tick + PassengerSim.BEAT_TICKS)
	assert_int(due).is_between(beat_tick + 1, beat_tick + 2)
	# It got up within a tick of that, not on its next beat.
	assert_int(guest.stage).is_equal(Passenger.Stage.CAFE_STANDING_UP)
	assert_int(left - due).is_less_equal(1)
	world.run_to(world.flights.doors_close_tick(guest.flight_id) + 1)
	assert_int(guest.stage).is_equal(Passenger.Stage.MADE)


func test_a_guest_leaves_in_time_when_security_fills_during_its_visit() -> void:
	var alone: Passenger = _scenario(false)[0]
	var live := _scenario(true)
	var guest: Passenger = live[0]
	var visit: CafeVisit = live[3]
	print(
		(
			"no visit: %s; live: %s at %d, deadline %d -> %d, outcome %s served %s"
			% [
				Passenger.Stage.keys()[alone.stage],
				Passenger.Stage.keys()[guest.stage],
				guest.outcome_tick,
				live[1],
				live[2],
				CafeVisit.Outcome.keys()[visit.outcome],
				visit.served,
			]
		)
	)
	# Without the detour the guest makes it.
	assert_int(alone.stage).is_equal(Passenger.Stage.MADE)
	# The growing queue brought the deadline forward and cut the visit short,
	# and following it the guest made the flight.
	assert_int(live[2]).is_less(live[1])
	assert_int(visit.outcome).is_not_equal(CafeVisit.Outcome.COMPLETE)
	assert_int(guest.stage).is_equal(Passenger.Stage.MADE)
