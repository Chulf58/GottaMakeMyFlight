class_name TestLandsideViewsLoad
extends GdUnitTestSuite
## A whole-world load into a paused main scene redraws the landside at once
## through SaveGame.loaded (no tick runs while paused): LandsideViews draws
## exactly the loaded vehicles on the map, each where the sim has it with
## nothing between two ticks, and a vehicle selection made before the load is
## cleared. Built once for the file: a starter game played until cars drive
## on the road, saved, and loaded into a second scene that had its own car
## selected.

const SEED := 4_400_101
const OTHER_SEED := 9
const LIMIT := 12000
const ON_MAP := 2

var _path := SaveTestKit.run_path("test_landside_views_load")
var _saved: Node
var _loaded: Node
var _run := {}


func before() -> void:
	_saved = SaveTestKit.boot(self, SEED)
	SaveTestKit.start_airport(_saved)
	var landside: LandsideSim = _saved.get_node("LandsideSim")
	var limit := landside.tick + LIMIT
	while landside.tick < limit and _on_map(landside).size() < ON_MAP:
		SaveTestKit.step(_saved)
	_run["saved_on_map"] = _on_map(landside)
	_run["saved"] = SaveTestKit.save_game(_saved).save_to_file(_path)
	_loaded = SaveTestKit.boot(self, OTHER_SEED)
	SaveTestKit.start_airport(_loaded)
	var other: LandsideSim = _loaded.get_node("LandsideSim")
	while other.tick < LIMIT and _on_map(other).is_empty():
		SaveTestKit.step(_loaded)
	var views: LandsideViews = _loaded.get_node("LandsideViews")
	_run["selected_before"] = _on_map(other)[0] if not _on_map(other).is_empty() else 0
	views.select(_run["selected_before"])
	_run["selected_after_select"] = views.selected_id
	_run["loaded"] = SaveTestKit.save_game(_loaded).load_from_file(_path)


func after() -> void:
	for main in [_saved, _loaded]:
		if main != null:
			main.free()
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + ".tmp")


## The ids of the vehicles on the map (not waiting below 0 on road_in).
static func _on_map(landside: LandsideSim) -> Array[int]:
	var out: Array[int] = []
	for id in landside.vehicle_ids():
		var v := landside.get_vehicle(id)
		if not (v.lane == LandsideVehicle.Lane.ROAD_IN and v.pos_mm < 0):
			out.append(id)
	return out


func test_a_paused_load_draws_the_loaded_vehicles_where_they_stand() -> void:
	var landside: LandsideSim = _loaded.get_node("LandsideSim")
	var views: LandsideViews = _loaded.get_node("LandsideViews")
	var clock: SimClock = _loaded.get_node("SimClock")
	var on_map := _on_map(landside)
	print(
		(
			"run %s; loaded on map %s, drawn %d, paused %s"
			% [_run, on_map, views.vehicle_count(), clock.paused]
		)
	)
	assert_bool(_run["saved"]).is_true()
	assert_bool(_run["loaded"]).is_true()
	assert_bool(clock.paused).is_true()
	assert_int(on_map.size()).is_greater_equal(ON_MAP)
	assert_array(on_map).is_equal(_run["saved_on_map"])
	assert_int(views.vehicle_count()).is_equal(on_map.size())
	for id in on_map:
		var v := landside.get_vehicle(id)
		var want := landside.world_position(v)
		assert_vector(views.pose_at(id, 0.0).origin).is_equal_approx(want, Vector3.ONE * 0.001)
		assert_vector(views.pose_at(id, 1.0).origin).is_equal_approx(want, Vector3.ONE * 0.001)
		assert_vector(views.node_for(id).position).is_equal_approx(want, Vector3.ONE * 0.001)


func test_a_selection_made_before_the_load_is_cleared() -> void:
	assert_int(_run["selected_before"]).is_greater(0)
	assert_int(_run["selected_after_select"]).is_equal(_run["selected_before"])
	var views: LandsideViews = _loaded.get_node("LandsideViews")
	assert_int(views.selected_id).is_equal(0)
