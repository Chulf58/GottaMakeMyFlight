class_name TestCafeDeadline
extends GdUnitTestSuite
## A cafe visit never makes a passenger miss a flight it would have made
## without it (decision cafe-visit-design-forecast-the-whole-itinerary-abandon-
## by-a, point 1): the deadline follows the "abandon now" forecast with the
## queues as they are, so a landside guest whose security queue fills during
## its visit leaves in time. The same stream of passengers is run three ways:
## with no visit the guest passes security first and makes the flight; with
## the deadline held at its admission value the guest stays to the end of its
## visit and misses; with the live deadline it leaves early and makes it.

## Just checked in, between the desks and the scanner lanes.
const CROWD_CELL := Vector2i(16, 12)
## One more passenger reaches security this often, faster than the two
## scanners serve them (one per 20 ticks), so the queue keeps growing.
const CROWD_EVERY := 7
const CROWD_UNTIL := 700

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
## checked in. With `frozen` the guest's deadline is held at its admission
## value. Returns [the guest, the admission deadline, the earliest deadline].
func _scenario(visit_cafe: bool, frozen: bool) -> Array:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_worlds.append(world)
	var guest := _new_passenger(world)
	while guest.stage != Passenger.Stage.TO_SECURITY and world.clock.tick < 600:
		world.step()
	var admitted := 0
	if visit_cafe:
		assert_bool(world.sim.cafes.try_visit(guest)).is_true()
		admitted = world.sim.cafes.visit_of(guest.id).deadline
		print("admitted at %d, deadline %d" % [world.clock.tick, admitted])
	var earliest := admitted
	while world.clock.tick < world.flights.doors_close_tick(guest.flight_id) + 1:
		if world.clock.tick < CROWD_UNTIL and posmod(world.clock.tick, CROWD_EVERY) == 0:
			_checked_in(world)
		var current := world.sim.cafes.visit_of(guest.id)
		if current != null:
			if frozen:
				current.deadline = admitted
			earliest = mini(earliest, current.deadline)
		world.step()
	return [guest, admitted, earliest]


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


func test_a_guest_leaves_in_time_when_security_fills_during_its_visit() -> void:
	var alone: Passenger = _scenario(false, false)[0]
	var frozen: Passenger = _scenario(true, true)[0]
	var live := _scenario(true, false)
	var guest: Passenger = live[0]
	print(
		(
			"no visit: %s; held deadline: %s; live: %s at %d, deadline %d -> %d"
			% [
				Passenger.Stage.keys()[alone.stage],
				Passenger.Stage.keys()[frozen.stage],
				Passenger.Stage.keys()[guest.stage],
				guest.outcome_tick,
				live[1],
				live[2],
			]
		)
	)
	# Without the detour the guest makes it; staying to the end of the visit
	# while the queue grows makes it miss.
	assert_int(alone.stage).is_equal(Passenger.Stage.MADE)
	assert_int(frozen.stage).is_equal(Passenger.Stage.MISSED)
	# Following the live forecast it left earlier and made the flight.
	assert_int(live[2]).is_less(live[1])
	assert_int(guest.stage).is_equal(Passenger.Stage.MADE)
