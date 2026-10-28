class_name TestPassengerViewsLoad
extends GdUnitTestSuite
## A quick load while paused draws every passenger where the loaded sim puts
## it at once, with no tick run (board item 4e443730: views kept their
## pre-load positions until the first tick after unpausing).

const SEED := 6_102_026
const PASSENGERS_WANTED := 4
## Ticks played after the save and before the load, so the world moves on.
const AFTER_SAVE := 60
const SEARCH_LIMIT := 12000

var _path := SaveTestKit.run_path("test_passenger_views_load")
var _main: Node
var _views: PassengerViews
var _sim: PassengerSim
var _run := {}


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_views = _main.get_node("PassengerViews")
	_sim = _main.get_node("PassengerSim")
	SaveTestKit.start_airport(_main)
	var ticks := 0
	while _views.active_count() < PASSENGERS_WANTED and ticks < SEARCH_LIMIT:
		SaveTestKit.step(_main)
		ticks += 1
	_run["ticks_to_passengers"] = ticks
	_run["saved"] = SaveTestKit.save_game(_main).save_to_file(_path)
	_run["ids_at_save"] = _views.active_count()
	_views.draw()
	_run["at_save"] = _positions()
	for i in AFTER_SAVE:
		SaveTestKit.step(_main)
	_views.draw()
	_run["before_load"] = _positions()
	_run["ids_before_load"] = _node_ids()
	_run["loaded"] = SaveTestKit.save_game(_main).load_from_file(_path)
	_run["after_load"] = _positions()
	_run["ids_after_load"] = _node_ids()


func after() -> void:
	if _main != null:
		_main.free()
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + ".tmp")


func _node_ids() -> Array:
	var ids: Array = []
	for id in _sim.passenger_ids():
		if _views.node_for(id) != null:
			ids.append(id)
	return ids


func _positions() -> Dictionary:
	var at := {}
	for id in _node_ids():
		at[id] = (_views.node_for(id) as Node3D).position
	return at


func test_the_world_was_set_up_with_passengers_and_a_save() -> void:
	assert_bool(_run["saved"]).is_true()
	assert_bool(_run["loaded"]).is_true()
	assert_int(_run["ids_at_save"]).is_greater_equal(PASSENGERS_WANTED)


func test_views_moved_between_the_save_and_the_load() -> void:
	# Control: without it a snap to unmoved positions would prove nothing.
	var saved_at: Dictionary = _run["at_save"]
	var before_load: Dictionary = _run["before_load"]
	var moved := 0
	for id in before_load:
		if saved_at.has(id) and (saved_at[id] as Vector3).distance_to(before_load[id]) > 0.5:
			moved += 1
	assert_int(moved).is_greater(0)


func test_every_view_is_at_the_loaded_sim_position_with_no_tick_run() -> void:
	assert_bool(_main.get_node("SimClock").paused).is_true()
	assert_int(_count_views_at_sim_position()).is_greater(0)
	# The next frame draws between the recorded positions: still the same spot.
	_views.draw()
	assert_int(_count_views_at_sim_position()).is_greater(0)


func _count_views_at_sim_position() -> int:
	var checked := 0
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		var node := _views.node_for(id)
		if node == null:
			continue
		var want := _views.draw_position(p)
		assert_float(node.position.distance_to(want)).is_less(0.01)
		assert_vector(_views.tick_position(id, false)).is_equal_approx(want, Vector3.ONE * 0.01)
		assert_vector(_views.tick_position(id, true)).is_equal_approx(want, Vector3.ONE * 0.01)
		checked += 1
	return checked


func test_views_match_the_loaded_passengers_exactly() -> void:
	# Expected from the sim alone: not made, and a missed passenger only while
	# it lingers.
	var expected: Array = []
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		if p.stage == Passenger.Stage.MADE:
			continue
		if (
			p.stage == Passenger.Stage.MISSED
			and _sim.tick - p.outcome_tick > PassengerViews.MISSED_LINGER_TICKS
		):
			continue
		expected.append(id)
	assert_int(expected.size()).is_greater(0)
	for id in expected:
		assert_object(_views.node_for(id)).is_not_null()
	assert_int(_views.active_count()).is_equal(expected.size())
	for id in _run["ids_before_load"]:
		if not expected.has(id):
			assert_object(_views.node_for(id)).is_null()
