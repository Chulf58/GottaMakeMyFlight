class_name TestPassengerThoughtsSave
extends GdUnitTestSuite
## Thoughts are saved with the passenger (user ruling in decision passenger-
## inspect-thoughts-recorded-at-sim-outcomes-saved-pin-marks-where): the shown
## list and the repeat-suppression marks come back from JSON as they were, a
## version 19 save is refused with no migration, and a bad thought record
## refuses the whole load and leaves the sim as it was: a thought with no cell
## or off the grid, a facility its kind does not take, or repeat marks that
## are missing or disagree with the newest kept thought of a kind.

var _world: PassengerTestWorld
var _id := 0


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_world = PassengerTestWorld.reference_world()
	_id = _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(40)
	var p := _world.passenger(_id)
	PassengerThoughts.record(p, PassengerThoughts.Kind.MEAL, 12, Vector2i(3, 4), 77)
	PassengerThoughts.decor(p, 30, Vector2i(5, 6))
	PassengerThoughts.record(p, PassengerThoughts.Kind.TOILET_RELIEF, 35, Vector2i(6, 7), 78)


func after_test() -> void:
	_world.free_all()
	_world = null


func _saved() -> Dictionary:
	return JSON.parse_string(JSON.stringify(_world.sim.to_snapshot()))


func _record_of(data: Dictionary) -> Dictionary:
	for record: Dictionary in data["passengers"]:
		if int(record["id"]) == _id:
			return record
	return {}


func test_thoughts_and_their_marks_come_back_from_json() -> void:
	var p := _world.passenger(_id)
	var thoughts := p.thoughts.duplicate()
	var marks := p.thought_marks.duplicate()
	var data := _saved()
	assert_int(int(data["save_version"])).is_equal(32)
	assert_bool(_world.sim.from_snapshot(data)).is_true()
	var back := _world.passenger(_id)
	print("saved %s / %s, loaded %s / %s" % [thoughts, marks, back.thoughts, back.thought_marks])
	assert_int(back.thoughts.size()).is_equal(3 * PassengerThoughts.STRIDE)
	assert_array(Array(back.thoughts)).is_equal(Array(thoughts))
	assert_array(Array(back.thought_marks)).is_equal(Array(marks))
	assert_array(PassengerThoughts.entries(back)).is_equal(PassengerThoughts.entries(p))


func test_a_version_19_save_is_refused() -> void:
	var data := _saved()
	data["save_version"] = 19
	var before := _world.signature()
	assert_bool(_world.sim.from_snapshot(data)).is_false()
	assert_str(_world.signature()).is_equal(before)


func test_a_bad_thought_record_refuses_the_load() -> void:
	var good := _saved()
	var bad_cases := {}
	var cases := {
		"no thoughts": func(r: Dictionary) -> void: r.erase("thoughts"),
		"no marks": func(r: Dictionary) -> void: r.erase("thought_marks"),
		"cut entry": func(r: Dictionary) -> void: (r["thoughts"] as Array).pop_back(),
		"unknown kind": func(r: Dictionary) -> void: r["thoughts"][0] = 99,
		"future tick": func(r: Dictionary) -> void: r["thoughts"][1] = 999999,
		"off the grid": func(r: Dictionary) -> void: r["thoughts"][2] = -5,
		"text tick": func(r: Dictionary) -> void: r["thoughts"][1] = "12",
		"too many": func(r: Dictionary) -> void: _overfill(r),
		"short marks": func(r: Dictionary) -> void: (r["thought_marks"] as Array).pop_back(),
		"future mark": func(r: Dictionary) -> void: r["thought_marks"][0] = 999999,
		"marks cleared": func(r: Dictionary) -> void: r["thought_marks"] = [],
		"mark disagrees": func(r: Dictionary) -> void: r["thought_marks"][0] = 11,
		"kept kind unmarked": func(r: Dictionary) -> void: r["thought_marks"][2] = -1,
		"no cell": func(r: Dictionary) -> void: _set_cell(r, Passenger.NO_CELL),
		"meal without a room": func(r: Dictionary) -> void: r["thoughts"][4] = 0,
		"decor with a room": func(r: Dictionary) -> void: r["thoughts"][10] = 5,
		"meal with a value": func(r: Dictionary) -> void: r["thoughts"][5] = 3,
	}
	for label: String in cases:
		var data: Dictionary = good.duplicate(true)
		(cases[label] as Callable).call(_record_of(data))
		bad_cases[label] = data
	var before := _world.signature()
	var thoughts := Array(_world.passenger(_id).thoughts)
	for label: String in bad_cases:
		var accepted := _world.sim.from_snapshot(bad_cases[label])
		print("%s accepted %s" % [label, accepted])
		assert_bool(accepted).override_failure_message(label).is_false()
	assert_str(_world.signature()).is_equal(before)
	assert_array(Array(_world.passenger(_id).thoughts)).is_equal(thoughts)
	assert_bool(_world.sim.from_snapshot(good)).is_true()


static func _set_cell(record: Dictionary, cell: Vector2i) -> void:
	record["thoughts"][2] = cell.x
	record["thoughts"][3] = cell.y


static func _overfill(record: Dictionary) -> void:
	var list: Array = record["thoughts"]
	var first := list.slice(0, PassengerThoughts.STRIDE)
	while list.size() <= PassengerThoughts.CAP * PassengerThoughts.STRIDE:
		list.append_array(first)


func test_an_empty_list_may_have_no_marks() -> void:
	var data := _saved()
	var record := _record_of(data)
	record["thoughts"] = []
	record["thought_marks"] = []
	assert_bool(_world.sim.from_snapshot(data)).is_true()
	assert_int(PassengerThoughts.count(_world.passenger(_id))).is_equal(0)
