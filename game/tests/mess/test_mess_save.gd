class_name TestMessSave
extends GdUnitTestSuite
## The messes are saved whole (decision mess-sim-technical-design-messsim-
## under-passengersim-counters-refuse-at-cap, point 8): a save that went
## through JSON loads back the messes, the bin fill, the next id, every use
## counter and the diagnostics; a world loaded mid-run plays on exactly like
## the one that never stopped; and a save that does not fit the grid is refused
## and changes nothing.

const SPOT := Vector2i(15, 10)
const SAVE_AT := 1500
const RUN_ON := 1500

var _a: PassengerTestWorld
var _b: PassengerTestWorld
var _ids: Dictionary


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


## An open world with a bin and a table whose seat keys name a real object,
## so the save's counters and bin fill check against the grid.
func _world() -> PassengerTestWorld:
	var world := MessTestKit.open_world(7)
	_ids = {
		"bin": PassengerTestWorld.place(world.grid, MessSim.BIN_ID, Vector2i(5, 5), 0),
		"table": PassengerTestWorld.place(world.grid, &"cafe_table", Vector2i(24, 4), 0),
	}
	return world


## Litter caught by the bin, litter on the floor, a spill and a toilet mess,
## and one use short of the next mess at a second seat.
func _make_messes(world: PassengerTestWorld) -> void:
	var table: int = _ids["table"]
	MessTestKit.litter(world, Vector2i(5, 6), "%d:0" % table)
	MessTestKit.litter(world, SPOT, "%d:0" % table)
	world.sim.messes.cafe_used(MessTestKit.cafe_visit(SPOT, "%d:1" % table))
	world.sim.messes.add(MessSim.Kind.SPILL, Vector2i(20, 15))
	world.sim.messes.add(MessSim.Kind.TOILET, Vector2i(8, 12))


func test_a_save_through_json_loads_back_every_mess_bin_and_counter() -> void:
	_a = _world()
	_make_messes(_a)
	_a.run_to(_a.clock.tick + MessSim.GROW_TICKS)
	var saved := MessTestKit.through_json(_a.sim.messes.to_snapshot())
	_b = _world()
	_b.run_to(_a.clock.tick)
	assert_bool(_b.sim.messes.from_snapshot(saved)).is_true()
	var a := _a.sim.messes
	var b := _b.sim.messes
	var grown := 0
	for id in b.mess_ids():
		if b.get_mess(id)["grown"]:
			grown += 1
	print(
		(
			"messes %d, grown %d, next id %d, bin fill %d, sources %s, caught %d"
			% [b.mess_count(), grown, b.next_id(), b.fill_of(_ids["bin"]), b.sources(), b.caught]
		)
	)
	assert_int(b.mess_count()).is_equal(3)
	assert_int(grown).is_equal(1)
	assert_int(b.next_id()).is_equal(a.next_id())
	assert_int(b.next_id()).is_greater(1)
	assert_int(b.fill_of(_ids["bin"])).is_equal(1)
	assert_int(b.caught).is_equal(1)
	assert_array(b.sources()).is_equal(a.sources())
	for source in a.sources():
		assert_int(b.uses_of(source)).is_equal(a.uses_of(source))
	assert_int(b.uses_of(MessSim.seat_source("%d:1" % _ids["table"]))).is_equal(1)
	for id in a.mess_ids():
		assert_dict(b.get_mess(id)).is_equal(a.get_mess(id))
	assert_str(MessTestKit.text_of(b.to_snapshot())).is_equal(MessTestKit.text_of(a.to_snapshot()))


func test_a_world_loaded_mid_run_plays_on_like_the_one_that_never_stopped() -> void:
	_a = _world()
	_b = _world()
	for world in [_a, _b]:
		world.run_to(20)
	_make_messes(_a)
	_a.run_to(SAVE_AT)
	_b.run_to(SAVE_AT)
	var saved := MessTestKit.through_json(_a.sim.messes.to_snapshot())
	assert_bool(_b.sim.messes.from_snapshot(saved)).is_true()
	var guests: Array[Passenger] = []
	for world in [_a, _b]:
		guests.append(MessTestKit.guest(world, SPOT + Vector2i(0, 2)))
	for i in RUN_ON:
		for world in [_a, _b]:
			for p: Passenger in guests:
				if world.sim.get_passenger(p.id) == p:
					ToiletTestLayout.calm(p)
			world.step()
		# The next use of the second seat lands mid-run in both.
		if i == 100:
			for world in [_a, _b]:
				world.sim.messes.cafe_used(MessTestKit.cafe_visit(SPOT, "%d:1" % _ids["table"]))
				world.sim.messes.cafe_used(MessTestKit.cafe_visit(SPOT, "%d:1" % _ids["table"]))
	var grown := 0
	for id in _b.sim.messes.mess_ids():
		if _b.sim.messes.get_mess(id)["grown"]:
			grown += 1
	print(
		(
			"tick %d: unbroken mood %d, loaded mood %d, messes %d and %d, grown %d"
			% [
				_a.clock.tick,
				guests[0].mood,
				guests[1].mood,
				_a.sim.messes.mess_count(),
				_b.sim.messes.mess_count(),
				grown
			]
		)
	)
	assert_int(_a.clock.tick).is_equal(SAVE_AT + RUN_ON)
	assert_int(grown).is_greater(0)
	assert_int(guests[0].mood).is_less(MessTestKit.START_MOOD)
	assert_int(guests[1].mood).is_equal(guests[0].mood)
	assert_str(MessTestKit.text_of(_b.sim.messes.to_snapshot())).is_equal(
		MessTestKit.text_of(_a.sim.messes.to_snapshot())
	)


func test_a_save_that_does_not_fit_the_grid_is_refused_and_changes_nothing() -> void:
	_a = _world()
	_make_messes(_a)
	var good := MessTestKit.through_json(_a.sim.messes.to_snapshot())
	var cases := {
		"missing counters": func(d: Dictionary) -> void: d.erase("counters"),
		"old version": func(d: Dictionary) -> void: d["save_version"] = 0,
		"mess off the floor": func(d: Dictionary) -> void: d["messes"][0]["cell"] = [-3, 4],
		"approach not walkable": func(d: Dictionary) -> void: d["messes"][0]["approach"] = [24, 4],
		"unknown kind": func(d: Dictionary) -> void: d["messes"][0]["kind"] = 9,
		"grown spill": _grow_spill,
		"born after the tick":
		func(d: Dictionary) -> void: d["messes"][0]["born_tick"] = int(d["tick"]) + 1,
		"id at next id": func(d: Dictionary) -> void: d["messes"][0]["id"] = d["next_id"],
		"same id twice": func(d: Dictionary) -> void: d["messes"][1]["id"] = d["messes"][0]["id"],
		"bin that is no bin": func(d: Dictionary) -> void: d["bins"] = {str(_ids["table"]): 1},
		"bin over capacity":
		func(d: Dictionary) -> void: d["bins"] = {str(_ids["bin"]): MessSim.BIN_CAPACITY + 1},
		"counter of nothing": func(d: Dictionary) -> void: d["counters"]["seat:999:0"] = 1,
		"counter of a bad shape": func(d: Dictionary) -> void: d["counters"]["seat"] = 1,
		"negative overflow": func(d: Dictionary) -> void: d["overflow"] = -1,
	}
	var before := MessTestKit.text_of(_a.sim.messes.to_snapshot())
	var refused := 0
	for name: String in cases:
		var bad: Dictionary = good.duplicate(true)
		(cases[name] as Callable).call(bad)
		var problem := str(MessSim.checked(bad, _a.grid).get("error", ""))
		var loaded := _a.sim.messes.from_snapshot(bad)
		print("%s: refused '%s'" % [name, problem])
		assert_str(problem).override_failure_message(name).is_not_empty()
		assert_bool(loaded).override_failure_message(name).is_false()
		if problem != "" and not loaded:
			refused += 1
	assert_int(refused).is_equal(cases.size())
	assert_str(MessTestKit.text_of(_a.sim.messes.to_snapshot())).is_equal(before)
	assert_str(str(MessSim.checked(good, _a.grid).get("error", ""))).is_empty()


## Marks the saved spill grown: only litter grows.
func _grow_spill(data: Dictionary) -> void:
	for mess: Dictionary in data["messes"]:
		if int(mess["kind"]) == MessSim.Kind.SPILL:
			mess["grown"] = true
