class_name TestBoardingFilesSave
extends GdUnitTestSuite
## The boarding files in a save (PassengerSim version 15): a save taken while
## a walker waits to join a file, or mid-file with walkers indoors and on the
## apron, loads into a world that plays out exactly like the one that never
## stopped, and bad files are refused whole.

var _a: PassengerTestWorld
var _b: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in [_a, _b]:
		if world != null:
			world.free_all()
	_a = null
	_b = null


func _save(world: PassengerTestWorld) -> Dictionary:
	return {
		"clock": world.clock.to_snapshot(),
		"flights": world.flights.to_snapshot(),
		"grid": world.grid.to_snapshot(),
		"passengers": world.sim.to_snapshot(),
	}


func _load(data: Dictionary) -> PassengerTestWorld:
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	assert_bool(world.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(world.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(world.sim.from_snapshot(data["passengers"])).is_true()
	return world


## The world's signature plus the files and standing claims.
func _signature(world: PassengerTestWorld) -> String:
	return (
		"%s#%s#%s"
		% [
			world.signature(),
			JSON.stringify(world.sim.files.to_dict()),
			JSON.stringify(world.sim.standing.to_list())
		]
	)


## The reference world boarding 24 passengers, run until `ready` holds.
func _boarding_until(ready: Callable) -> PassengerTestWorld:
	var world := PassengerTestWorld.reference_world(4242)
	world.sim.schedule_flight(PassengerTestWorld.FLIGHT, 24)
	var doors := world.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	while world.clock.tick < doors and not ready.call(world):
		world.step()
	return world


static func _has_pending(world: PassengerTestWorld) -> bool:
	return not (world.sim.files.to_dict()["pending"] as Array).is_empty()


## Walkers indoors in a door file, one of them just out on the apron and still
## last in it, and an apron file.
static func _mid_file(world: PassengerTestWorld) -> bool:
	var files := world.sim.files.to_dict()
	if (files["planes"] as Array).is_empty():
		return false
	for entry: Dictionary in files["doors"]:
		var ids: Array = entry["passengers"]
		var out := world.passenger(ids[0]).stage == Passenger.Stage.APRON
		if out and ids.size() >= 3:
			return true
	return false


## Plays both worlds on to doors close and returns the first tick they differ,
## or -1.
func _first_difference() -> int:
	assert_str(_signature(_b)).is_equal(_signature(_a))
	var doors := _a.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	while _a.clock.tick <= doors:
		_a.step()
		_b.step()
		if _signature(_a) != _signature(_b):
			return _a.clock.tick
	return -1


func test_a_save_while_a_walker_waits_to_join_plays_out_identically() -> void:
	_a = _boarding_until(_has_pending)
	assert_bool(_has_pending(_a)).is_true()
	print("save at tick %d: files %s" % [_a.clock.tick, _a.sim.files.to_dict()])
	_b = _load(JSON.parse_string(JSON.stringify(_save(_a))))
	var bad := _first_difference()
	print("first differing tick %d, made %d" % [bad, _a.sim.made_count()])
	assert_int(bad).is_equal(-1)
	assert_int(_a.sim.made_count()).is_equal(24)


func test_a_save_mid_file_indoors_and_on_the_apron_plays_out_identically() -> void:
	_a = _boarding_until(_mid_file)
	assert_bool(_mid_file(_a)).is_true()
	print("save at tick %d: files %s" % [_a.clock.tick, _a.sim.files.to_dict()])
	_b = _load(JSON.parse_string(JSON.stringify(_save(_a))))
	var bad := _first_difference()
	print("first differing tick %d, made %d" % [bad, _a.sim.made_count()])
	assert_int(bad).is_equal(-1)
	assert_int(_a.sim.made_count()).is_equal(24)


func test_bad_boarding_files_are_refused_whole() -> void:
	_a = _boarding_until(_mid_file)
	var good: Dictionary = JSON.parse_string(JSON.stringify(_a.sim.to_snapshot()))
	var files: Dictionary = good["boarding"]
	var door_entry: Dictionary = files["doors"][0]
	var ids: Array = door_entry["passengers"]
	var indoor: int = ids[ids.size() - 1]
	var cases := {}
	var missing := good.duplicate(true)
	missing.erase("boarding")
	cases["missing key"] = missing
	var dropped := good.duplicate(true)
	# A JSON save holds its ids as floats: remove by place, not by value.
	(dropped["boarding"]["doors"][0]["passengers"] as Array).remove_at(ids.size() - 1)
	cases["walker in no file"] = dropped
	var swapped := good.duplicate(true)
	(swapped["boarding"]["doors"][0]["passengers"] as Array).reverse()
	cases["file out of order"] = swapped
	var wrong_door := good.duplicate(true)
	wrong_door["boarding"]["doors"][0]["door"] = int(door_entry["door"]) + 1000
	cases["wrong door"] = wrong_door
	var repeated := good.duplicate(true)
	(repeated["boarding"]["doors"][0]["passengers"] as Array).append(ids[0])
	cases["repeated walker"] = repeated
	var off_apron := good.duplicate(true)
	off_apron["boarding"]["planes"] = []
	cases["apron walker in no apron file"] = off_apron
	var walking := good.duplicate(true)
	(walking["boarding"]["pending"] as Array).append(indoor)
	cases["pending walker still walking"] = walking
	var settled := good.duplicate(true)
	(settled["boarding"]["delayed"] as Array).append(99999)
	cases["delayed walker unknown"] = settled
	var extra := good.duplicate(true)
	extra["boarding"]["queue"] = []
	cases["unknown key"] = extra
	assert_bool(_a.passenger(indoor).is_moving()).is_true()
	_b = PassengerTestWorld.reference_world()
	var before := _b.signature()
	for name: String in cases:
		var refused := not _b.sim.from_snapshot(cases[name])
		print("%s: refused %s" % [name, refused])
		assert_bool(refused).override_failure_message("%s loaded" % name).is_true()
		assert_str(_b.signature()).is_equal(before)
	# The unchanged save loads.
	assert_bool(_b.sim.from_snapshot(good)).is_true()
