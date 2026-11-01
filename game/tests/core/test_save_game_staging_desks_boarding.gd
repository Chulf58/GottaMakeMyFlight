class_name TestSaveGameStagingDesksBoarding
extends GdUnitTestSuite
## SaveGame staging runs the same info desk and boarding file checks as
## PassengerSim.from_snapshot: a save that breaks either is refused while
## staging, before any part installs, rather than passing staging and failing
## at install with the world half loaded. A live help visit and non-empty
## boarding files stage and install alike.

var _world: PassengerTestWorld
var _text := ""
var _desk_world: PassengerTestWorld
var _desk_text := ""
var _boarding_world: PassengerTestWorld
var _boarding_text := ""


func before() -> void:
	PassengerTestWorld.tracker = self
	_world = PassengerTestWorld.reference_world(4242)
	_world.sim.schedule_flight(PassengerTestWorld.FLIGHT, 6)
	_world.run_to(120)
	_text = _taken_from(_world)
	_desk_world = _mid_help_world()
	_desk_text = _taken_from(_desk_world)
	_boarding_world = _mid_file_world()
	_boarding_text = _taken_from(_boarding_world)


func after() -> void:
	PassengerTestWorld.tracker = null


static func _taken_from(world: PassengerTestWorld) -> String:
	return JSON.stringify(world.sim.to_snapshot(), "", true, true)


## One stuck guest run until a desk is helping it, standing at the desk.
func _mid_help_world() -> PassengerTestWorld:
	var world := InfoDeskTestLayout.world()
	var p := InfoDeskTestLayout.guest(world, Vector2i(9, 10), 50)
	var limit := world.clock.tick + 600
	while world.clock.tick < limit and not _helping(world, p):
		world.step()
	assert_bool(_helping(world, p)).is_true()
	return world


static func _helping(world: PassengerTestWorld, p: Passenger) -> bool:
	return (
		world.sim.info_desks.holds(p)
		and p.at == InfoDeskTestLayout.DESK_FRONT
		and world.sim.info_desks.to_list()["visits"][0][2] != InfoDesk.WALKING
	)


## The reference world boarding 24 passengers, run until walkers are in a door
## file and an apron file.
func _mid_file_world() -> PassengerTestWorld:
	var world := PassengerTestWorld.reference_world(4242)
	world.sim.schedule_flight(PassengerTestWorld.FLIGHT, 24)
	var doors := world.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	while world.clock.tick < doors and not _filed(world):
		world.step()
	assert_bool(_filed(world)).is_true()
	return world


static func _filed(world: PassengerTestWorld) -> bool:
	var files := world.sim.files.to_dict()
	return not (files["doors"] as Array).is_empty() and not (files["planes"] as Array).is_empty()


## The passengers part of the save taken in before(), as a file holds it.
func _taken() -> Dictionary:
	return JSON.parse_string(_text)


## What SaveGame stages for the passengers part of `data` on `world`'s grid,
## and the staged dictionary.
func _stage(data: Dictionary, world := _world) -> Array:
	var save: SaveGame = auto_free(SaveGame.new())
	var staged := {"grid": world.grid}
	return [save._stage_passengers(data, staged), staged]


## Staging refuses `bad` with `why` and keeps nothing for install; the sim
## refuses the same data and stays as it was.
func _assert_refused_both_ways(bad: Dictionary, why: String, fresh := _fresh()) -> void:
	var staging := _stage(bad, fresh)
	assert_str(staging[0]).contains(why)
	assert_bool((staging[1] as Dictionary).has("passengers")).is_false()
	assert_bool((staging[1] as Dictionary).has("sim")).is_false()
	var before := fresh.signature()
	assert_bool(fresh.sim.from_snapshot(bad)).is_false()
	assert_str(fresh.signature()).is_equal(before)
	fresh.free_all()


## A new world on the same grid as the one saved in before().
func _fresh() -> PassengerTestWorld:
	return PassengerTestWorld.reference_world()


func test_the_saved_part_stages_as_it_is() -> void:
	var ok := _stage(_taken())
	assert_str(ok[0]).is_equal("")
	assert_bool((ok[1] as Dictionary).has("sim")).is_true()
	(ok[1]["sim"] as Node).free()


func test_a_live_help_visit_stages_and_installs() -> void:
	var data: Dictionary = JSON.parse_string(_desk_text)
	var visits: Array = data["info_desk"]["visits"]
	assert_int(visits.size()).is_equal(1)
	assert_int(int(visits[0][2])).is_not_equal(InfoDesk.WALKING)
	var fresh := InfoDeskTestLayout.world()
	var ok := _stage(data, fresh)
	assert_str(ok[0]).is_equal("")
	assert_bool((ok[1] as Dictionary).has("sim")).is_true()
	(ok[1]["sim"] as Node).free()
	assert_bool(fresh.sim.from_snapshot(data)).is_true()
	assert_dict(fresh.sim.info_desks.to_list()).is_equal(_desk_world.sim.info_desks.to_list())
	fresh.free_all()


## The help end is checked against the saved tick: an end at or before it
## cannot be live, whatever the visit looked like when saved.
func test_a_help_end_the_saved_tick_has_passed_is_refused_while_staging() -> void:
	var bad: Dictionary = JSON.parse_string(_desk_text)
	bad["info_desk"]["visits"][0][2] = str(bad["tick"]).to_int()
	_assert_refused_both_ways(bad, "help end outside", InfoDeskTestLayout.world())


func test_non_empty_boarding_files_stage_and_install() -> void:
	var data: Dictionary = JSON.parse_string(_boarding_text)
	assert_int((data["boarding"]["doors"] as Array).size()).is_greater(0)
	assert_int((data["boarding"]["planes"] as Array).size()).is_greater(0)
	var fresh := PassengerTestWorld.reference_world()
	var ok := _stage(data, fresh)
	assert_str(ok[0]).is_equal("")
	assert_bool((ok[1] as Dictionary).has("sim")).is_true()
	(ok[1]["sim"] as Node).free()
	assert_bool(fresh.sim.from_snapshot(data)).is_true()
	assert_dict(fresh.sim.files.to_dict()).is_equal(_boarding_world.sim.files.to_dict())
	fresh.free_all()


## The files are checked against the layout: a walker moved to the wrong door
## file is refused.
func test_boarding_files_out_of_order_are_refused_while_staging() -> void:
	var bad: Dictionary = JSON.parse_string(_boarding_text)
	bad["boarding"]["doors"][0]["door"] = 999999
	_assert_refused_both_ways(bad, "door file", PassengerTestWorld.reference_world())


func test_an_info_desk_visit_of_an_unknown_passenger_is_refused_while_staging() -> void:
	var bad := _taken()
	bad["info_desk"]["visits"].append([999999, 1, InfoDesk.WALKING])
	_assert_refused_both_ways(bad, "info_desk visit")


func test_a_current_save_with_no_info_desk_key_is_refused_while_staging() -> void:
	var bad := _taken()
	assert_bool(bad.erase("info_desk")).is_true()
	_assert_refused_both_ways(bad, "missing key 'info_desk'")


func test_a_pending_boarding_walker_of_an_unknown_passenger_is_refused_while_staging() -> void:
	var bad := _taken()
	bad["boarding"]["pending"].append(999999)
	_assert_refused_both_ways(bad, "pending passenger")


func test_a_current_save_with_no_boarding_key_is_refused_while_staging() -> void:
	var bad := _taken()
	assert_bool(bad.erase("boarding")).is_true()
	_assert_refused_both_ways(bad, "missing key 'boarding'")
