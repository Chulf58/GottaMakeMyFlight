class_name TestFoodTightTime
extends GdUnitTestSuite
## A seated guest in a bar or a restaurant who runs short of time leaves early
## and pays the short share (decision food-and-drink-cafe-bar-sit-down-
## restaurant-and-grab-and-go-st, point 2). The restaurant guest still makes
## the flight. The bar guest, already late at a walk, catches the burst's
## boarding line and is held at its pace, so it misses behind the line, for
## the crowding reason, and not in the bar (decision a-late-passenger-held-up-
## by-people-traffic-at-boarding-misse). The time runs
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


## With `held_up`, the guest misses the flight in the boarding line instead of
## making it.
func _check_leaves_early(venue: StringName, held_up := false) -> void:
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
	world.run_to(world.flights.doors_close_tick(guest.flight_id) + 1)
	if not held_up:
		# And it still makes the flight.
		assert_int(guest.stage).is_equal(Passenger.Stage.MADE)
		return
	# Held up by people traffic: it missed out at the boarding line, not in
	# the bar, and the flight's result blames the crowds.
	var reasons: Array = FlightResult.summarize(world.sim, guest.flight_id)["reasons"]
	print(
		(
			"%s guest missed at %s, %s; reasons %s"
			% [
				venue,
				Passenger.Stage.keys()[guest.missed_stage],
				Passenger.Stuck.keys()[guest.missed_stuck],
				reasons
			]
		)
	)
	assert_int(guest.stage).is_equal(Passenger.Stage.MISSED)
	assert_bool(guest.missed_stage in [Passenger.Stage.TO_EXIT, Passenger.Stage.APRON]).is_true()
	assert_int(guest.missed_stuck).is_equal(Passenger.Stuck.CROWDED)
	(
		assert_bool(
			reasons.any(func(r: Dictionary) -> bool: return r["text"] == FlightResult.CROWDED_TEXT)
		)
		. is_true()
	)


func test_a_restaurant_guest_short_of_time_leaves_early_pays_less_and_makes_the_flight() -> void:
	_check_leaves_early(&"restaurant")


## Changed for decision a-late-passenger-held-up-by-people-traffic-at-boarding-
## misse: this guest made the flight only by running through the burst's
## walkers on the apron. Runners now keep a boarding line's pace, so it misses
## there, and the miss is the terminal's crowding, not the bar's.
func test_a_bar_guest_short_of_time_leaves_early_pays_less_and_misses_in_the_boarding_line(
) -> void:
	_check_leaves_early(&"bar", true)
