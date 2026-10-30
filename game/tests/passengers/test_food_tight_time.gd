class_name TestFoodTightTime
extends GdUnitTestSuite
## A seated guest in a bar or a restaurant who runs short of time leaves early,
## pays the short share and still makes the flight (decision food-and-drink-
## cafe-bar-sit-down-restaurant-and-grab-and-go-st, point 2). The time runs
## short for real: the guest is admitted while security is empty, then a burst
## of passengers fills the scanner queues behind it, so the leave deadline
## passes while it is seated. Nothing sets a deadline by hand.

## Just checked in, between the desks and the scanner lanes.
const CROWD_CELL := Vector2i(16, 12)
## Passengers who check in at once, enough to make a seated guest's deadline pass.
const BURST := 30

var _worlds: Array[PassengerTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in _worlds:
		world.free_all()
	_worlds.clear()


func _checked_in(world: PassengerTestWorld) -> void:
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 0
	p.cafe_cooldown = 1000000
	p.stage = Passenger.Stage.TO_SECURITY
	p.at = CROWD_CELL
	p.clear_path()


## A landside guest admitted to a `venue` visit and seated, then the burst.
## Returns {"guest", "visit", "world", "mood" (when it got up), "seated_at",
## "left_at", "full" (what a full visit would have paid at that mood)}.
func _run(venue: StringName) -> Dictionary:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid, false, null, venue)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_worlds.append(world)
	var guest := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	guest.hunger = 0
	guest.cafe_cooldown = 1000000
	while guest.stage != Passenger.Stage.TO_SECURITY and world.clock.tick < 600:
		world.step()
	(
		assert_bool(world.sim.cafes.try_visit(guest))
		. override_failure_message("%s refused a guest at the start of its journey" % venue)
		. is_true()
	)
	var visit := world.sim.cafes.visit_of(guest.id)
	while guest.stage != Passenger.Stage.CAFE_SEATED and world.clock.tick < 1500:
		world.step()
	assert_int(guest.stage).is_equal(Passenger.Stage.CAFE_SEATED)
	var seated_at := world.clock.tick
	var dwell_end := visit.dwell_end
	for i in BURST:
		_checked_in(world)
	var mood := guest.mood
	while guest.stage == Passenger.Stage.CAFE_SEATED:
		mood = guest.mood
		world.step()
	return {
		"world": world,
		"guest": guest,
		"visit": visit,
		"mood": mood,
		"seated_at": seated_at,
		"dwell_end": dwell_end,
		"left_at": world.clock.tick,
		"full":
		CafeSim.spend(
			RoomTypes.get_type(venue).base_spend, mood, false, CafeVisit.Outcome.COMPLETE
		),
	}


func _check_leaves_early(venue: StringName) -> void:
	var seen := _run(venue)
	var world: PassengerTestWorld = seen["world"]
	var guest: Passenger = seen["guest"]
	var visit: CafeVisit = seen["visit"]
	print(
		(
			"%s: seated at %d, dwell would end %d, left at %d, paid %d of %d"
			% [
				venue,
				seen["seated_at"],
				seen["dwell_end"],
				seen["left_at"],
				visit.amount,
				seen["full"]
			]
		)
	)
	# It got up before its dwell was over, by the deadline and nothing else.
	assert_int(seen["left_at"]).is_less(seen["dwell_end"])
	assert_int(visit.outcome).is_equal(CafeVisit.Outcome.SHORT)
	# It paid, but less than the full visit.
	assert_int(visit.amount).is_greater(0)
	assert_int(visit.amount).is_less(seen["full"])
	assert_int(visit.amount).is_equal(
		CafeSim.spend(
			RoomTypes.get_type(venue).base_spend, seen["mood"], false, CafeVisit.Outcome.SHORT
		)
	)
	assert_int(world.sim.wallet.balance).is_equal(visit.amount)
	# An early leaver does not collect the mood lift of a full visit.
	assert_int(guest.mood).is_equal(seen["mood"])
	# And it still makes the flight.
	world.run_to(world.flights.doors_close_tick(guest.flight_id) + 1)
	assert_int(guest.stage).is_equal(Passenger.Stage.MADE)


func test_a_restaurant_guest_short_of_time_leaves_early_pays_less_and_makes_the_flight() -> void:
	_check_leaves_early(&"restaurant")


func test_a_bar_guest_short_of_time_leaves_early_pays_less_and_makes_the_flight() -> void:
	_check_leaves_early(&"bar")
