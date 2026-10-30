class_name TestStallWalkOnTime
extends GdUnitTestSuite
## A walk-on stall guest who runs short of time gives up (decision cafe-visit-
## design-forecast-the-whole-itinerary-abandon-by-a): the deadline is checked
## in every phase before the order is made, and a guest not yet served pays
## nothing. The deadline leaves from the counter's order spot with no standing
## up. The time runs short for real: the guest is admitted while security is
## empty, then a burst of passengers fills the scanner queues behind it.

## Just checked in, between the desks and the scanner lanes.
const CROWD_CELL := Vector2i(16, 12)
## Passengers who check in at once, enough to pass a landside guest's deadline.
const BURST := 40

var _worlds: Array[PassengerTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in _worlds:
		world.free_all()
	_worlds.clear()


func _new_passenger(world: PassengerTestWorld) -> Passenger:
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 0
	p.cafe_cooldown = 1000000
	return p


func _burst(world: PassengerTestWorld) -> void:
	for i in BURST:
		var p := _new_passenger(world)
		p.stage = Passenger.Stage.TO_SECURITY
		p.at = CROWD_CELL
		p.clear_path()


## A landside guest admitted to a stall visit while security is empty.
func _admitted() -> Array:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid, false, null, &"stall", false)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_worlds.append(world)
	var guest := _new_passenger(world)
	while guest.stage != Passenger.Stage.TO_SECURITY and world.clock.tick < 600:
		world.step()
	(
		assert_bool(world.sim.cafes.try_visit(guest))
		. override_failure_message("the stall refused a guest at the start of its journey")
		. is_true()
	)
	var visit := world.sim.cafes.visit_of(guest.id)
	assert_bool(visit.walk_on()).is_true()
	assert_int(visit.resume_stage).is_equal(Passenger.Stage.TO_SECURITY)
	# Admitted with time to spare: the deadline is not yet in sight.
	assert_int(visit.deadline).is_greater(world.clock.tick + 200)
	return [world, guest, visit]


func _assert_gave_up(world: PassengerTestWorld, guest: Passenger, visit: CafeVisit) -> void:
	assert_object(world.sim.cafes.visit_of(guest.id)).is_null()
	assert_bool(visit.served).is_false()
	assert_int(visit.outcome).is_equal(CafeVisit.Outcome.NONE)
	assert_int(visit.amount).is_equal(0)
	assert_int(world.sim.wallet.balance).is_equal(0)
	assert_int(guest.stage).is_equal(Passenger.Stage.TO_SECURITY)


func test_a_guest_on_its_way_to_the_stall_gives_up_when_security_fills() -> void:
	var made := _admitted()
	var world: PassengerTestWorld = made[0]
	var guest: Passenger = made[1]
	var visit: CafeVisit = made[2]
	_burst(world)
	var phases := {}
	while world.sim.cafes.visit_of(guest.id) != null and world.clock.tick < 1500:
		phases[guest.stage] = true
		world.step()
	print("gave up at %d, deadline %d, from %s" % [world.clock.tick, visit.deadline, phases.keys()])
	# It was still in the walk or queue, not at the counter being served.
	assert_bool(phases.has(Passenger.Stage.CAFE_ORDER)).is_false()
	assert_int(world.clock.tick).is_greater_equal(visit.deadline)
	_assert_gave_up(world, guest, visit)


func test_a_guest_giving_its_order_gives_up_unpaid_when_security_fills() -> void:
	var made := _admitted()
	var world: PassengerTestWorld = made[0]
	var guest: Passenger = made[1]
	var visit: CafeVisit = made[2]
	while guest.stage != Passenger.Stage.CAFE_ORDER and world.clock.tick < 1500:
		world.step()
	assert_int(guest.stage).is_equal(Passenger.Stage.CAFE_ORDER)
	var service_end := visit.service_end
	_burst(world)
	while world.sim.cafes.visit_of(guest.id) != null and world.clock.tick < 1500:
		world.step()
	print(
		"order due %d, gave up at %d, deadline %d" % [service_end, world.clock.tick, visit.deadline]
	)
	# It left in the middle of the order, before it was made.
	assert_int(world.clock.tick).is_less(service_end)
	assert_int(world.clock.tick).is_greater_equal(visit.deadline)
	_assert_gave_up(world, guest, visit)


## The counters step before the guest's own deadline check, and a walk-on
## order ends the visit the moment it is made. A deadline that passes on the
## very tick the order completes is therefore enforced by the order itself: the
## guest gives up unpaid instead of paying in full and setting off too late.
func test_a_deadline_passing_on_the_tick_the_order_completes_gives_up_unpaid() -> void:
	var made := _admitted()
	var world: PassengerTestWorld = made[0]
	var guest: Passenger = made[1]
	var visit: CafeVisit = made[2]
	while guest.stage != Passenger.Stage.CAFE_ORDER and world.clock.tick < 1500:
		world.step()
	assert_int(guest.stage).is_equal(Passenger.Stage.CAFE_ORDER)
	var service_end := visit.service_end
	# Two ticks before the order completes, with the deadline still ahead.
	while world.clock.tick < service_end - 2:
		world.step()
	assert_int(visit.deadline).is_greater(service_end)
	_burst(world)
	world.step()
	# One tick before: the burst has reached the queues, the guest's own check
	# has not fired yet, and the deadline now falls at or before the tick the
	# order ends.
	var spot: Vector2i = world.sim.cafes.layout.counter(visit.room, visit.counter)["lane"][0]
	var fresh := VisitForecast.live_deadline(world.sim, guest, spot, 0, visit.resume_stage)
	print("service_end %d, deadline after the burst %d" % [service_end, fresh])
	assert_int(world.clock.tick).is_equal(service_end - 1)
	assert_int(guest.stage).is_equal(Passenger.Stage.CAFE_ORDER)
	assert_int(fresh).is_less_equal(service_end)
	world.step()
	assert_int(world.clock.tick).is_equal(service_end)
	_assert_gave_up(world, guest, visit)
