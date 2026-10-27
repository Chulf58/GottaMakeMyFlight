class_name TestBaggageSnapshot
extends GdUnitTestSuite
## The bags' save part (BaggageSnapshot, BaggageSim.to_snapshot and
## from_snapshot): a JSON round trip gives the same state, a save waits for
## the tick after an edit, and a part that does not fit itself or the grid is
## refused without changing the sim.

var _world: BagTestWorld
var _desk := 0


func before_test() -> void:
	_world = BagTestWorld.make(self)
	_desk = _world.line()


## The live part after a trip through JSON text.
func _saved() -> Dictionary:
	return JSON.parse_string(JSON.stringify(_world.sim.to_snapshot()))


## Two riding bags, one at the desk, one loaded and one missed.
func _busy() -> void:
	var lone := _world.desk(Vector2i(2, 2))
	_world.sim.check_in(1, BagTestWorld.FLIGHT, lone)
	for i in 3:
		_world.sim.check_in(i + 2, BagTestWorld.FLIGHT, _desk)
	_world.run_to(45)


func _assert_refused(data: Dictionary, reason: String) -> void:
	var before := _world.signature()
	assert_bool(_world.sim.from_snapshot(data)).override_failure_message(reason).is_false()
	assert_str(_world.signature()).is_equal(before)


func test_a_json_round_trip_loads_the_same_bags() -> void:
	_busy()
	var data := _saved()
	var before := _world.signature()
	assert_bool(_world.sim.from_snapshot(data)).is_true()
	assert_str(_world.signature()).is_equal(before)
	assert_that(JSON.parse_string(JSON.stringify(_world.sim.to_snapshot()))).is_equal(data)
	assert_int(int(data["save_version"])).is_equal(BaggageSnapshot.SAVE_VERSION)


func test_results_and_totals_round_trip() -> void:
	var world := BagTestWorld.make(self, 400)
	world.sim.check_in(1, BagTestWorld.FLIGHT, world.line())
	world.sim.check_in(2, BagTestWorld.FLIGHT, world.desk(Vector2i(2, 2)))
	world.run_to(201)
	var data: Dictionary = JSON.parse_string(JSON.stringify(world.sim.to_snapshot()))
	var twin := BagTestWorld.make(self, 400)
	twin.line()
	twin.desk(Vector2i(2, 2))
	twin.run_to(201)
	assert_bool(twin.sim.from_snapshot(data)).is_true()
	assert_str(twin.signature()).is_equal(world.signature())
	assert_that(twin.sim.results).is_equal(world.sim.results)
	assert_that(twin.sim.results[BagTestWorld.FLIGHT]).is_equal(
		{"loaded": 1, "missed": 1, "causes": {"no_belt": 1}}
	)


func test_no_save_is_taken_between_an_edit_and_the_next_tick() -> void:
	_busy()
	_world.lay(Vector2i(3, 6), Vector2i(3, 4))
	assert_bool(_world.sim.routes_stale).is_true()
	assert_that(_world.sim.to_snapshot()).is_equal({})
	(
		assert_error(func() -> void: _world.sim.to_snapshot())
		. is_push_error(
			"BaggageSim.to_snapshot: a build edit settles on the next tick; save after it"
		)
	)
	_world.step()
	assert_bool(_world.sim.routes_stale).is_false()
	assert_that(_world.sim.to_snapshot()).is_not_equal({})


func test_a_part_broken_alone_is_refused() -> void:
	_busy()
	var cases := [
		["unknown key", func(d: Dictionary) -> void: d["extra"] = 1],
		["old version", func(d: Dictionary) -> void: d["save_version"] = 0],
		["ids not rising", func(d: Dictionary) -> void: d["bags"][1]["id"] = 1],
		["id at next_id", func(d: Dictionary) -> void: d["next_id"] = 4],
		["missed with no cause", func(d: Dictionary) -> void: _missed(d, Bag.Cause.NONE)],
		["loaded with a cause", func(d: Dictionary) -> void: _loaded(d, Bag.Cause.LATE)],
		["unsettled after cutoff", func(d: Dictionary) -> void: d["bags"][1]["cutoff_tick"] = 45],
		["bad state", func(d: Dictionary) -> void: d["bags"][1]["state"] = 9],
		["half a cell", func(d: Dictionary) -> void: d["bags"][1]["cell"] = [3.5, 7]],
		["two-cell step", func(d: Dictionary) -> void: d["bags"][1]["from"] = [2, 0]],
		["remain past an edge", func(d: Dictionary) -> void: d["bags"][1]["remain_mm"] = 1001],
		["made after the tick", func(d: Dictionary) -> void: d["bags"][1]["created_tick"] = 46],
		["causes not adding up", func(d: Dictionary) -> void: _result(d, 1, {"late": 2})],
		["unknown cause", func(d: Dictionary) -> void: _result(d, 1, {"stolen": 1})],
		["totals below results", func(d: Dictionary) -> void: _result(d, 0, {}, 3)],
	]
	for entry in cases:
		var data := _saved()
		(entry[1] as Callable).call(data)
		_assert_refused(data, entry[0])


func test_a_part_that_does_not_fit_the_grid_is_refused() -> void:
	_busy()
	var off_belt := _saved()
	off_belt["bags"][1]["cell"] = [0, 0]
	_assert_refused(off_belt, "a riding bag off the belts")
	var stacked := _saved()
	stacked["bags"][2]["cell"] = stacked["bags"][1]["cell"]
	stacked["bags"][2]["from"] = stacked["bags"][1]["from"]
	stacked["bags"][2]["remain_mm"] = stacked["bags"][1]["remain_mm"]
	_assert_refused(stacked, "two bags on one cell")
	var blocked := _saved()
	blocked["bags"][1]["state"] = Bag.State.BLOCKED
	_assert_refused(blocked, "a bag with a route saved as blocked")
	var roomless := _saved()
	roomless["bags"][1]["state"] = Bag.State.IN_ROOM
	roomless["bags"][1]["remain_mm"] = 0
	roomless["bags"][1]["rest_tick"] = 40
	_assert_refused(roomless, "a bag in the room away from any end")


func test_a_bag_whose_desk_is_gone_still_loads() -> void:
	_busy()
	var data := _saved()
	data["bags"][0]["desk"] = 4242
	data["bags"][0]["passenger"] = 999999
	assert_bool(_world.sim.from_snapshot(data)).is_true()
	assert_int(_world.bag(1).desk).is_equal(4242)


func _missed(data: Dictionary, cause: int) -> void:
	data["bags"][1]["state"] = Bag.State.MISSED
	data["bags"][1]["cause"] = cause
	data["bags"][1]["outcome_tick"] = 44


func _loaded(data: Dictionary, cause: int) -> void:
	data["bags"][1]["state"] = Bag.State.LOADED
	data["bags"][1]["cause"] = cause
	data["bags"][1]["outcome_tick"] = 44


func _result(data: Dictionary, missed: int, causes: Dictionary, loaded_total := -1) -> void:
	data["results"][BagTestWorld.FLIGHT] = {"loaded": 0, "missed": missed, "causes": causes}
	if loaded_total >= 0:
		data["results"][BagTestWorld.FLIGHT]["loaded"] = loaded_total
