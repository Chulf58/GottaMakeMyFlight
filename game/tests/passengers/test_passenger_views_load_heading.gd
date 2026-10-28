class_name TestPassengerViewsLoadHeading
extends GdUnitTestSuite
## A load while paused turns a walking passenger to face along its path, even
## when the view had since turned to something else (a seat, the next leg):
## a snap has no interval to take a heading from.

const SEED := 6_102_026
const SEARCH_LIMIT := 12000
const TURN_LIMIT := 4000
const TURNED_RAD := 0.3

var _path := SaveTestKit.run_path("test_passenger_views_load_heading")
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
	_run["saved"] = SaveTestKit.save_game(_main).save_to_file(_path)
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
	_run["loaded"] = SaveTestKit.save_game(_main).load_from_file(_path)
	_run["rotations_after_load"] = _rotations(_run["saved_headings"].keys())


func after() -> void:
	if _main != null:
		_main.free()
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + ".tmp")


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


## A passenger on the cell grid: path cells from `cells`, `stage` as given,
## `index` cells already walked.
static func _on_grid(stage: Passenger.Stage, cells: Array[Vector2i], index := 0) -> Passenger:
	var p := Passenger.new()
	p.stage = stage
	p.at = cells[index]
	p.set_path(cells)
	p.path_index = index
	return p


## A passenger on the walk outside: `points` as the apron, `mm` walked.
static func _on_apron(stage: Passenger.Stage, points: Array[Vector3], mm: int) -> Passenger:
	var p := Passenger.new()
	p.stage = stage
	p.apron = points
	p.apron_mm = mm
	return p


func test_walk_heading_on_the_grid_follows_the_current_path_step() -> void:
	var cells: Array[Vector2i] = [Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 3)]
	assert_vector(_views.walk_heading(_on_grid(Passenger.Stage.TO_SECURITY, cells, 0))).is_equal(
		Vector2(1, 0)
	)
	assert_vector(_views.walk_heading(_on_grid(Passenger.Stage.TO_SECURITY, cells, 1))).is_equal(
		Vector2(0, 1)
	)
	# On the last cell nothing is left to walk.
	assert_vector(_views.walk_heading(_on_grid(Passenger.Stage.TO_SECURITY, cells, 2))).is_equal(
		Vector2.ZERO
	)


func test_walk_heading_on_the_apron_follows_the_leg_under_the_progress() -> void:
	var points: Array[Vector3] = [Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 1, 3)]
	for stage in [Passenger.Stage.APRON, Passenger.Stage.SPAWNED]:
		# The first leg is 4000 mm long, the second 3000 mm (height costs nothing).
		assert_vector(_views.walk_heading(_on_apron(stage, points, 1000))).is_equal(Vector2(4, 0))
		assert_vector(_views.walk_heading(_on_apron(stage, points, 5000))).is_equal(Vector2(0, 3))


func test_walk_heading_outside_reads_the_apron_not_a_leftover_grid_path() -> void:
	# Control: the same path heads along (0, 1) once the passenger is not outside.
	var points: Array[Vector3] = [Vector3(0, 0, 0), Vector3(4, 0, 0)]
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1)]
	var outside := _on_apron(Passenger.Stage.APRON, points, 1000)
	outside.set_path(cells)
	assert_vector(_views.walk_heading(outside)).is_equal(Vector2(4, 0))
	var inside := _on_apron(Passenger.Stage.TO_GATE, points, 1000)
	inside.set_path(cells)
	assert_vector(_views.walk_heading(inside)).is_equal(Vector2(0, 1))


func test_walk_heading_is_zero_once_the_apron_walk_has_ended() -> void:
	var points: Array[Vector3] = [Vector3(0, 0, 0), Vector3(4, 0, 0)]
	var done := _on_apron(Passenger.Stage.APRON, points, 4000)
	done.clear_path()
	assert_vector(_views.walk_heading(done)).is_equal(Vector2.ZERO)
