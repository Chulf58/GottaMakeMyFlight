class_name TestPassengerViewsLoadHeading
extends GdUnitTestSuite
## A load while paused turns a walking passenger to face along its path, even
## when the view had since turned to something else (a seat, the next leg):
## a snap has no interval to take a heading from.

const SEED := 6_102_026
const PATH := "user://saves/test_passenger_views_load_heading.json"
const SEARCH_LIMIT := 12000
const TURN_LIMIT := 4000
const TURNED_RAD := 0.3

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
	while _walkers().is_empty() and ticks < SEARCH_LIMIT:
		SaveTestKit.step(_main)
		ticks += 1
	_views.draw()
	_run["saved_headings"] = _headings(_walkers())
	_run["saved"] = SaveTestKit.save_game(_main).save_to_file(PATH)
	# Play on until a saved walker's view faces away from its saved heading.
	var turned := false
	ticks = 0
	while not turned and ticks < TURN_LIMIT:
		SaveTestKit.step(_main)
		_views.draw()
		ticks += 1
		for id in _run["saved_headings"]:
			var node := _views.node_for(id)
			if node != null and _gap(node.rotation.y, _run["saved_headings"][id]) > TURNED_RAD:
				turned = true
	_run["turned_before_load"] = turned
	_run["rotations_before_load"] = _rotations(_run["saved_headings"].keys())
	_run["loaded"] = SaveTestKit.save_game(_main).load_from_file(PATH)
	DirAccess.remove_absolute(PATH)
	_run["rotations_after_load"] = _rotations(_run["saved_headings"].keys())


func after() -> void:
	_main.free()


## Ids of passengers walking now that have a view, in the sim's own terms.
func _walkers() -> Array:
	var ids: Array = []
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		if _views.node_for(id) != null and _views.walk_heading(p) != Vector2.ZERO:
			ids.append(id)
	return ids


func _headings(ids: Array) -> Dictionary:
	var at := {}
	for id in ids:
		var h := _views.walk_heading(_sim.get_passenger(id))
		at[id] = atan2(h.x, h.y)
	return at


func _rotations(ids: Array) -> Dictionary:
	var at := {}
	for id in ids:
		var node := _views.node_for(id)
		if node != null:
			at[id] = node.rotation.y
	return at


static func _gap(a: float, b: float) -> float:
	return absf(angle_difference(a, b))


func test_a_walker_was_found_and_the_view_turned_away_before_the_load() -> void:
	# Control: without a turn the load could pass by leaving the view alone.
	assert_bool(_run["saved"]).is_true()
	assert_bool(_run["loaded"]).is_true()
	assert_bool(_run["saved_headings"].is_empty()).is_false()
	assert_bool(_run["turned_before_load"]).is_true()


func test_a_loaded_walker_faces_along_its_path_with_no_tick_run() -> void:
	var headings: Dictionary = _run["saved_headings"]
	var after_load: Dictionary = _run["rotations_after_load"]
	var checked := 0
	for id in after_load:
		var p := _sim.get_passenger(id)
		if p == null or _views.walk_heading(p) == Vector2.ZERO:
			continue
		var h := _views.walk_heading(p)
		assert_float(_gap(after_load[id], atan2(h.x, h.y))).is_less(0.01)
		checked += 1
	assert_int(checked).is_greater(0)
	var turned := 0
	for id in headings:
		var before: Dictionary = _run["rotations_before_load"]
		if before.has(id) and _gap(before[id], headings[id]) > TURNED_RAD:
			assert_float(_gap(after_load[id], headings[id])).is_less(0.01)
			turned += 1
	assert_int(turned).is_greater(0)
