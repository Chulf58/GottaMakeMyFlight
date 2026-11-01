class_name TestSaveGameStagingDesksBoarding
extends GdUnitTestSuite
## SaveGame staging runs the same info desk and boarding file checks as
## PassengerSim.from_snapshot: a save that breaks either is refused while
## staging, before any part installs, rather than passing staging and failing
## at install with the world half loaded.

var _world: PassengerTestWorld
var _text := ""


func before() -> void:
	PassengerTestWorld.tracker = self
	_world = PassengerTestWorld.reference_world(4242)
	_world.sim.schedule_flight(PassengerTestWorld.FLIGHT, 6)
	_world.run_to(120)
	_text = JSON.stringify(_world.sim.to_snapshot(), "", true, true)


func after() -> void:
	PassengerTestWorld.tracker = null


## The passengers part of the save taken in before(), as a file holds it.
func _taken() -> Dictionary:
	return JSON.parse_string(_text)


## What SaveGame stages for the passengers part, and the staged dictionary.
func _stage(data: Dictionary) -> Array:
	var save: SaveGame = auto_free(SaveGame.new())
	var staged := {"grid": _world.grid}
	return [save._stage_passengers(data, staged), staged]


## Staging refuses `bad` with `why` and keeps nothing for install; the sim
## refuses the same data and stays as it was.
func _assert_refused_both_ways(bad: Dictionary, why: String) -> void:
	var staging := _stage(bad)
	assert_str(staging[0]).contains(why)
	assert_bool((staging[1] as Dictionary).has("passengers")).is_false()
	assert_bool((staging[1] as Dictionary).has("sim")).is_false()
	var fresh := PassengerTestWorld.reference_world()
	var before := fresh.signature()
	assert_bool(fresh.sim.from_snapshot(bad)).is_false()
	assert_str(fresh.signature()).is_equal(before)
	fresh.free_all()


func test_the_saved_part_stages_as_it_is() -> void:
	var ok := _stage(_taken())
	assert_str(ok[0]).is_equal("")
	assert_bool((ok[1] as Dictionary).has("sim")).is_true()
	(ok[1]["sim"] as Node).free()


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
