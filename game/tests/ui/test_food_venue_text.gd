class_name TestFoodVenueText
extends GdUnitTestSuite
## The follow line names the food venue a guest is visiting: the stall, bar
## and restaurant each have their own walk, queue and order words, and the
## cafe keeps its own. The stall has no seat stages.

var _worlds: Array[PassengerTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in _worlds:
		world.free_all()
	_worlds.clear()


## The distinct follow-line texts a guest shows through a whole visit to `venue`.
func _texts(venue: StringName) -> Array:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid, false, null, venue, venue != &"stall")
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_worlds.append(world)
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.cafe_cooldown = 1000000
	p.hunger = 30
	while p.stage != Passenger.Stage.TO_GATE and world.clock.tick < 900:
		world.step()
	assert_bool(world.sim.cafes.try_visit(p)).is_true()
	var seen: Array = []
	while world.sim.cafes.visit_of(p.id) != null and world.clock.tick < 3000:
		var text := PassengerHud.stage_text(world.sim, p)
		if not seen.has(text):
			seen.append(text)
		world.step()
	return seen


func test_a_stall_guest_sees_stall_words_and_no_seat_stage() -> void:
	var seen := _texts(&"stall")
	print("stall texts %s" % [seen])
	assert_array(seen).is_equal(
		["Heading to the food stall", "Queuing at the food stall", "Grabbing a snack"]
	)


func test_a_bar_guest_sees_bar_words() -> void:
	var seen := _texts(&"bar")
	print("bar texts %s" % [seen])
	(
		assert_array(seen)
		. is_equal(
			[
				"Heading to the bar",
				"Queuing at the bar",
				"Ordering a drink",
				"Taking a drink to a seat",
				"Sitting down at the bar",
				"Having a drink",
				"Leaving the bar",
			]
		)
	)


func test_a_restaurant_guest_sees_restaurant_words() -> void:
	var seen := _texts(&"restaurant")
	print("restaurant texts %s" % [seen])
	assert_array(seen).contains(
		["Heading to the restaurant", "Queuing at the restaurant", "Ordering a meal"]
	)
	assert_array(seen).contains(["Having a meal", "Leaving the restaurant"])


func test_a_cafe_guest_keeps_the_cafe_words() -> void:
	var seen := _texts(&"cafe")
	assert_array(seen).contains(
		["Heading to the cafe", "Queuing at the cafe", "Ordering a coffee", "Having a coffee"]
	)
