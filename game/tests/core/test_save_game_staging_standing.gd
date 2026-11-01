class_name TestSaveGameStagingStanding
extends GdUnitTestSuite
## SaveGame staging runs the same standing-spot check as
## PassengerSim.from_snapshot: a save holding a STANDING passenger with no
## standing spot is refused while staging, before any part installs, rather
## than passing staging and failing at install with the world half loaded.

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
	_world = null


## The reference world with more cleared passengers at the gate than it has
## seats, run until three stand on spots.
func _crowded_world() -> PassengerTestWorld:
	var world := PassengerTestWorld.reference_world(4242)
	world.sim.schedule_flight(PassengerTestWorld.FLIGHT, 24)
	world.run_to(200)
	for i in world.sim.layout.seats.size() + 3:
		TestStandingSpotClaims.cleared(world)
	for i in 400:
		world.step()
		if _standing_ids(world).size() >= 3:
			break
	return world


func _standing_ids(world: PassengerTestWorld) -> Array:
	var ids := []
	for id in world.sim.passenger_ids():
		if world.passenger(id).stage == Passenger.Stage.STANDING:
			ids.append(id)
	return ids


## The passengers part of a save taken now, through JSON as a file holds it.
func _taken() -> Dictionary:
	var text := JSON.stringify(_world.sim.to_snapshot(), "", true, true)
	return JSON.parse_string(text)


## What SaveGame stages for the passengers part, and the staged dictionary.
func _stage(data: Dictionary) -> Array:
	var save: SaveGame = auto_free(SaveGame.new())
	var staged := {"grid": _world.grid}
	return [save._stage_passengers(data, staged), staged]


func test_a_standing_passenger_with_no_spot_is_refused_while_staging() -> void:
	_world = _crowded_world()
	var standing := _standing_ids(_world)
	assert_int(standing.size()).is_greater_equal(3)
	var good := _taken()
	# Positive control: the saved part stages as it is.
	var ok := _stage(good)
	assert_str(ok[0]).is_equal("")
	assert_bool((ok[1] as Dictionary).has("passengers")).is_true()
	(ok[1]["sim"] as Node).free()
	var bad := good.duplicate(true)
	var claims: Array = bad["standing"]
	var dropped := -1
	for i in claims.size():
		if int(claims[i]["passenger"]) == standing[0]:
			dropped = i
	assert_int(dropped).is_greater_equal(0)
	claims.remove_at(dropped)
	var staging := _stage(bad)
	assert_str(staging[0]).contains("holds no standing spot")
	# Refused before anything is kept for install.
	assert_bool((staging[1] as Dictionary).has("passengers")).is_false()
	assert_bool((staging[1] as Dictionary).has("sim")).is_false()
	# Staging and install agree: the sim itself refuses the same data.
	var fresh := PassengerTestWorld.reference_world()
	var before := fresh.signature()
	assert_bool(fresh.sim.from_snapshot(bad)).is_false()
	assert_str(fresh.signature()).is_equal(before)
	fresh.free_all()
