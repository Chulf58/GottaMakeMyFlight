class_name TestRescueGrantPassengers
extends GdUnitTestSuite
## "No passenger can make a flight" (ruling going-broke-a-one-off-rescue-grant-
## when-the-airport-is-stuck), judged from where real passengers are: one who
## still has a route through the pieces left to use holds the grant back, and
## a cafe guest is judged by the stage its journey resumes at (decision
## cafe-visit-design-forecast-the-whole-itinerary-abandon-by-a). Every
## passenger here walked to its stage; none has its stage set by hand.

var _world: PassengerTestWorld
var _grant: RescueGrant


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


## The reference terminal, with both cafes when `cafes`.
func _make(cafes := false) -> void:
	var grid := BuildGrid.new()
	if cafes:
		CafeTestLayout.build(grid)
	else:
		ReferenceTerminal.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_grant = auto_free(RescueGrant.new())
	_grant.bind(_world.clock, _world.sim, _world.sim.wallet)


## Removes every object of the given kinds (BuildCatalog ids).
func _remove_all(defs: Array[StringName]) -> void:
	for id in _world.grid.object_ids():
		if defs.has(StringName(_world.grid.get_object(id)["def"])):
			assert_bool(_world.grid.apply(BuildEdit.remove_object(id)).ok).is_true()


## A passenger who never starts a cafe visit by itself, run until `stage`.
func _walk_to(stage: Passenger.Stage) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 0
	p.cafe_cooldown = 1000000
	while p.stage != stage and _world.clock.tick < 1500:
		_world.step()
	assert_int(p.stage).is_equal(stage)
	print("passenger %d at stage %d cell %s tick %d" % [p.id, p.stage, p.at, _world.clock.tick])
	return p


func test_a_checked_in_passenger_needs_only_a_scanner_and_an_exit() -> void:
	_make()
	_walk_to(Passenger.Stage.TO_SECURITY)
	_remove_all([&"checkin_desk"])
	assert_bool(_grant.evaluate()).is_false()
	_remove_all([&"security_scanner"])
	assert_bool(_grant.evaluate()).is_true()


func test_a_cleared_passenger_needs_only_an_exit() -> void:
	_make()
	_walk_to(Passenger.Stage.TO_GATE)
	_remove_all([&"checkin_desk", &"security_scanner"])
	assert_bool(_grant.evaluate()).is_false()
	_remove_all([&"exit_door"])
	assert_bool(_grant.evaluate()).is_true()


func test_a_passenger_on_the_road_in_needs_the_whole_journey() -> void:
	_make()
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	assert_int(p.stage).is_equal(Passenger.Stage.SPAWNED)
	_remove_all([&"exit_door"])
	assert_bool(_grant.evaluate()).is_true()


## An airside cafe guest goes back to the gate after the visit, so it can make
## the flight while the exit stands, and not once the exit is gone.
func test_an_airside_cafe_guest_waits_on_the_exit() -> void:
	_make(true)
	var p := _walk_to(Passenger.Stage.TO_GATE)
	assert_bool(_world.sim.cafes.try_visit(p)).is_true()
	assert_bool(Passenger.in_cafe(p.stage)).is_true()
	assert_int(_world.sim.cafes.visit_of(p.id).resume_stage).is_equal(Passenger.Stage.TO_GATE)
	_remove_all([&"checkin_desk", &"security_scanner"])
	assert_bool(_grant.evaluate()).is_false()
	_remove_all([&"exit_door"])
	assert_bool(_grant.evaluate()).is_true()


## A landside cafe guest has security still ahead.
func test_a_landside_cafe_guest_waits_on_the_scanners() -> void:
	_make(true)
	var p := _walk_to(Passenger.Stage.TO_SECURITY)
	assert_bool(_world.sim.cafes.try_visit(p)).is_true()
	assert_bool(Passenger.in_cafe(p.stage)).is_true()
	assert_int(_world.sim.cafes.visit_of(p.id).resume_stage).is_equal(Passenger.Stage.TO_SECURITY)
	_remove_all([&"checkin_desk"])
	assert_bool(_grant.evaluate()).is_false()
	_remove_all([&"security_scanner"])
	assert_bool(_grant.evaluate()).is_true()
