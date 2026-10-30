class_name TestInfoDeskSave
extends GdUnitTestSuite
## A help visit survives save and load (decision info-desk-helps-stuck-
## passengers-a-short-help-visit-with-a-m): mid-walk, mid-help and in its
## cooldown, a loaded world plays on exactly like the one that never stopped.
## Passenger save version 12 carries the state under "info_desk".

const BEAT := PassengerSim.BEAT_TICKS

var _a: PassengerTestWorld
var _b: PassengerTestWorld
## Help ticks seen by each world, keyed by "a" and "b".
var _helped := {"a": [], "b": []}


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
	_helped = {"a": [], "b": []}


func _watch(world: PassengerTestWorld, key: String) -> void:
	world.sim.info_desks.helped.connect(
		func(_id: int, _desk: int) -> void: _helped[key].append(world.clock.tick)
	)


func _save(world: PassengerTestWorld) -> String:
	return (
		JSON
		. stringify(
			{
				"clock": world.clock.to_snapshot(),
				"flights": world.flights.to_snapshot(),
				"grid": world.grid.to_snapshot(),
				"passengers": world.sim.to_snapshot(),
			}
		)
	)


func _load(text: String) -> PassengerTestWorld:
	var data: Dictionary = JSON.parse_string(text)
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	var world := PassengerTestWorld.make(
		grid, PassengerTestWorld.starts_with(InfoDeskTestLayout.BOARDING, InfoDeskTestLayout.DOORS)
	)
	world.sim.apron_waypoints = PackedVector3Array()
	assert_bool(world.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(world.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(world.sim.from_snapshot(data["passengers"])).is_true()
	return world


## A world with one stuck guest, run until `stop` says to save; returns the guest.
func _stuck_guest(stop: Callable) -> Passenger:
	_a = InfoDeskTestLayout.world()
	_watch(_a, "a")
	var p := InfoDeskTestLayout.guest(_a, Vector2i(9, 10), 50)
	var limit := _a.clock.tick + 600
	while _a.clock.tick < limit and not stop.call(p):
		_a.step()
	assert_bool(stop.call(p)).is_true()
	return p


func _carry_on_to_the_end(p: Passenger, twin: Passenger) -> void:
	InfoDeskTestLayout.open_wall(_a.grid)
	InfoDeskTestLayout.open_wall(_b.grid)
	var end := _a.clock.tick + 1800
	_a.run_to(end)
	_b.run_to(end)
	print(
		(
			"never stopped: help at %s, made %d, mood %d; loaded: help at %s, made %d, mood %d"
			% [
				_helped["a"],
				_a.sim.made_count(),
				p.mood,
				_helped["b"],
				_b.sim.made_count(),
				twin.mood
			]
		)
	)
	assert_str(_b.signature()).is_equal(_a.signature())
	assert_int(twin.mood).is_equal(p.mood)
	assert_int(_b.sim.made_count()).is_equal(1)
	assert_int(_a.sim.made_count()).is_equal(1)


func test_a_save_mid_walk_plays_on_like_the_world_that_never_stopped() -> void:
	var p := _stuck_guest(
		func(g: Passenger) -> bool:
			return _a.sim.info_desks.holds(g) and g.is_moving() and g.at.x < 9
	)
	var saved := _save(_a)
	_b = _load(saved)
	_watch(_b, "b")
	var twin := _b.passenger(p.id)
	assert_bool(_b.sim.info_desks.holds(twin)).is_true()
	assert_int(_b.sim.info_desks.desk_of(twin)).is_equal(_a.sim.info_desks.desk_of(p))
	assert_bool(twin.is_moving()).is_true()
	_carry_on_to_the_end(p, twin)
	assert_int(_helped["a"].size()).is_equal(1)
	assert_array(_helped["b"]).is_equal(_helped["a"])


func test_a_save_mid_help_plays_on_like_the_world_that_never_stopped() -> void:
	var p := _stuck_guest(
		func(g: Passenger) -> bool:
			return (
				_a.sim.info_desks.holds(g)
				and g.at == InfoDeskTestLayout.DESK_FRONT
				and _a.sim.info_desks.to_list()["visits"][0][2] != InfoDesk.WALKING
			)
	)
	_a.run_to(_a.clock.tick + 10)
	var saved := _save(_a)
	_b = _load(saved)
	_watch(_b, "b")
	var twin := _b.passenger(p.id)
	assert_bool(_b.sim.info_desks.holds(twin)).is_true()
	assert_array(_b.sim.info_desks.to_list()["visits"]).is_equal(
		_a.sim.info_desks.to_list()["visits"]
	)
	_carry_on_to_the_end(p, twin)
	assert_int(_helped["a"].size()).is_equal(1)
	assert_array(_helped["b"]).is_equal(_helped["a"])


func test_the_cooldown_survives_a_save() -> void:
	var p := _stuck_guest(func(_g: Passenger) -> bool: return not _helped["a"].is_empty())
	_a.run_to(_a.clock.tick + 100)
	_b = _load(_save(_a))
	_watch(_b, "b")
	var twin := _b.passenger(p.id)
	assert_array(_b.sim.info_desks.to_list()["cooldowns"]).is_equal(
		_a.sim.info_desks.to_list()["cooldowns"]
	)
	var end := _a.clock.tick + InfoDesk.COOLDOWN_TICKS - 200
	_a.run_to(end)
	_b.run_to(end)
	assert_int(_helped["a"].size()).is_equal(1)
	assert_array(_helped["b"]).is_empty()
	assert_bool(_b.sim.info_desks.holds(twin)).is_false()
	assert_str(_b.signature()).is_equal(_a.signature())


func test_the_passenger_save_carries_the_visit_under_info_desk() -> void:
	var p := _stuck_guest(func(g: Passenger) -> bool: return _a.sim.info_desks.holds(g))
	var data: Dictionary = JSON.parse_string(JSON.stringify(_a.sim.to_snapshot()))
	assert_int(int(data["save_version"])).is_equal(15)
	assert_int(int(data["info_desk"]["visits"][0][0])).is_equal(p.id)
	assert_int(int(data["info_desk"]["visits"][0][1])).is_equal(_a.sim.info_desks.desk_of(p))


func test_a_bad_info_desk_state_is_refused_whole() -> void:
	var p := _stuck_guest(func(g: Passenger) -> bool: return _a.sim.info_desks.holds(g))
	var good: Dictionary = JSON.parse_string(JSON.stringify(_a.sim.to_snapshot()))
	var desk := int(good["info_desk"]["visits"][0][1])
	var bad_cases: Array[Dictionary] = []
	var missing := good.duplicate(true)
	missing.erase("info_desk")
	bad_cases.append(missing)
	for state: Variant in [
		{"visits": [[p.id + 50, desk, -1]], "cooldowns": []},
		{"visits": [[p.id, desk, -1], [p.id, desk, 5]], "cooldowns": []},
		{"visits": [[p.id, 0, -1]], "cooldowns": []},
		{"visits": [[p.id, desk, -2]], "cooldowns": []},
		{"visits": [[p.id, desk, 1.5]], "cooldowns": []},
		{"visits": [[p.id, desk]], "cooldowns": []},
		{"visits": [], "cooldowns": [[p.id + 50, 10]]},
		{"visits": [], "cooldowns": [[p.id, -1]]},
		{"visits": []},
		[],
	]:
		var bad := good.duplicate(true)
		bad["info_desk"] = state
		bad_cases.append(bad)
	_b = InfoDeskTestLayout.world()
	var before := _b.signature()
	for bad in bad_cases:
		assert_bool(_b.sim.from_snapshot(bad)).is_false()
		assert_str(_b.signature()).is_equal(before)
		assert_array(_b.sim.info_desks.to_list()["visits"]).is_empty()


func test_a_save_from_before_version_12_loads_with_no_help_state() -> void:
	var p := _stuck_guest(func(g: Passenger) -> bool: return _a.sim.info_desks.holds(g))
	var old: Dictionary = JSON.parse_string(JSON.stringify(_a.sim.to_snapshot()))
	old.erase("info_desk")
	old["save_version"] = PassengerSnapshot.V10
	_b = InfoDeskTestLayout.world()
	assert_bool(_b.sim.from_snapshot(old)).is_true()
	assert_bool(_b.sim.info_desks.to_list()["visits"].is_empty()).is_true()
	assert_bool(_b.sim.info_desks.holds(_b.passenger(p.id))).is_false()


func test_a_snapshot_that_cannot_be_live_is_refused_whole_and_for_its_own_reason() -> void:
	# A help in progress: the passenger stands at the desk and the help ends
	# within HELP_TICKS of the saved tick.
	var p := _stuck_guest(_helping)
	var tick := _a.clock.tick
	var good: Dictionary = JSON.parse_string(JSON.stringify(_a.sim.to_snapshot()))
	var desk := _a.sim.info_desks.desk_of(p)
	var end := int(good["info_desk"]["visits"][0][2])
	var exit_door := 0
	for id in _a.grid.object_ids():
		if str(_a.grid.get_object(id)["def"]) == "exit_door":
			exit_door = id
	assert_int(exit_door).is_not_equal(0)
	assert_bool(end > tick and end <= tick + InfoDesk.HELP_TICKS).is_true()
	var live := {"visits": [[p.id, desk, end]], "cooldowns": [[p.id, 0]]}
	# The control: the live state passes the same check the refusals fail.
	var verdict := InfoDesk.checked(live, {p.id: _stub(p, -1, null)}, tick, _a.grid)
	assert_bool(verdict.has("error")).is_false()
	var far := tick + InfoDesk.HELP_TICKS + 1
	var fresh := tick + InfoDesk.COOLDOWN_TICKS + 1
	# [name, state, passenger stage or -1, passenger cell or null, error words]
	var cases: Array = [
		["expired help", _visit(p, desk, tick), -1, null, "help end"],
		["long past", _visit(p, desk, tick - 40), -1, null, "help end"],
		["too far ahead", _visit(p, desk, far), -1, null, "help end"],
		["an exit door, not a desk", _visit(p, exit_door, end), -1, null, "not an info desk"],
		["no such object", _visit(p, 9999, end), -1, null, "not an info desk"],
		["a stage no desk helps", live, Passenger.Stage.TO_GATE, null, "no desk helps"],
		["helped away from the desk", live, -1, [3, 3], "away from the desk"],
		["a cooldown past a fresh one", _cooldown(p, fresh), -1, null, "fresh cooldown"],
		["a settled passenger", _cooldown(p, 0), Passenger.Stage.MADE, null, "settled"],
	]
	_b = InfoDeskTestLayout.world()
	var before := _b.signature()
	for entry: Array in cases:
		var label: String = entry[0]
		var direct := InfoDesk.checked(
			entry[1], {p.id: _stub(p, entry[2], entry[3])}, tick, _a.grid
		)
		assert_bool(direct.has("error")).override_failure_message(label).is_true()
		assert_str(str(direct.get("error", ""))).override_failure_message(label).contains(entry[4])
		var bad := good.duplicate(true)
		bad["info_desk"] = entry[1]
		for record: Dictionary in bad["passengers"]:
			if int(record["id"]) != p.id:
				continue
			if int(entry[2]) >= 0:
				record["stage"] = int(entry[2])
			if entry[3] != null:
				record["at"] = entry[3]
		assert_bool(_b.sim.from_snapshot(bad)).override_failure_message(label).is_false()
		assert_str(_b.signature()).override_failure_message(label).is_equal(before)
		assert_array(_b.sim.info_desks.to_list()["visits"]).is_empty()
		assert_array(_b.sim.info_desks.to_list()["cooldowns"]).is_empty()


func test_a_visit_for_a_passenger_not_stuck_in_a_helpable_way_is_refused() -> void:
	# A visit only starts for a stuck status a desk helps (InfoDesk.HELPABLE), so
	# a save carrying one for a calm or merely queued passenger cannot be live.
	var p := _stuck_guest(_helping)
	var tick := _a.clock.tick
	var good: Dictionary = JSON.parse_string(JSON.stringify(_a.sim.to_snapshot()))
	assert_bool(InfoDesk.HELPABLE.has(p.stuck)).is_true()
	var live: Dictionary = good["info_desk"]
	var control := InfoDesk.checked(live, {p.id: _stub(p, -1, null)}, tick, _a.grid)
	assert_bool(control.has("error")).is_false()
	_b = InfoDeskTestLayout.world()
	# The control: the unaltered snapshot loads, so the refusals below are the stuck status.
	assert_bool(_b.sim.from_snapshot(good)).is_true()
	var before := _b.signature()
	var kept: Array = _b.sim.info_desks.to_list()["visits"]
	for stuck: Passenger.Stuck in [Passenger.Stuck.NONE, Passenger.Stuck.QUEUE_FULL]:
		var label := "stuck %d" % stuck
		var direct := InfoDesk.checked(live, {p.id: _stub(p, -1, null, stuck)}, tick, _a.grid)
		assert_bool(direct.has("error")).override_failure_message(label).is_true()
		assert_str(str(direct.get("error", ""))).override_failure_message(label).contains(
			"not stuck in a way a desk helps"
		)
		var bad := good.duplicate(true)
		for record: Dictionary in bad["passengers"]:
			if int(record["id"]) == p.id:
				record["stuck"] = int(stuck)
		assert_bool(_b.sim.from_snapshot(bad)).override_failure_message(label).is_false()
		assert_str(_b.signature()).override_failure_message(label).is_equal(before)
		assert_array(_b.sim.info_desks.to_list()["visits"]).is_equal(kept)


func test_a_version_11_snapshot_without_info_desk_is_refused_and_changes_nothing() -> void:
	_stuck_guest(func(g: Passenger) -> bool: return _a.sim.info_desks.holds(g))
	var old: Dictionary = JSON.parse_string(JSON.stringify(_a.sim.to_snapshot()))
	old.erase("info_desk")
	old["save_version"] = 11
	_b = InfoDeskTestLayout.world()
	var spare := InfoDeskTestLayout.guest(_b, Vector2i(9, 10), 50)
	_b.run_to(30)
	var before := _b.signature()
	var tick := _b.clock.tick
	var visits: Array = _b.sim.info_desks.to_list()["visits"]
	assert_bool(_b.sim.from_snapshot(old)).is_false()
	assert_str(_b.signature()).is_equal(before)
	assert_int(_b.sim.tick).is_equal(tick)
	assert_bool(_b.sim.get_passenger(spare.id) == spare).is_true()
	assert_array(_b.sim.info_desks.to_list()["visits"]).is_equal(visits)


func test_removing_the_desk_mid_help_ends_the_visit_so_a_save_stays_loadable() -> void:
	var p := _stuck_guest(_helping)
	var desk := _a.sim.info_desks.desk_of(p)
	assert_bool(_a.grid.apply(BuildEdit.remove_object(desk)).ok).is_true()
	# A save waits for the tick that settles an edit; that tick ends the visit.
	_a.step()
	assert_bool(_a.sim.info_desks.holds(p)).is_false()
	assert_array(_a.sim.info_desks.to_list()["visits"]).is_empty()
	_b = _load(_save(_a))
	assert_bool(_b.sim.info_desks.holds(_b.passenger(p.id))).is_false()


## A stop for _stuck_guest(): the passenger is being helped, at the desk.
func _helping(g: Passenger) -> bool:
	return (
		_a.sim.info_desks.holds(g)
		and g.at == InfoDeskTestLayout.DESK_FRONT
		and _a.sim.info_desks.to_list()["visits"][0][2] != InfoDesk.WALKING
	)


## A copy of `p` for InfoDesk.checked(), with a stage, cell or stuck status
## overridden (stuck -1 keeps `p`'s own).
func _stub(p: Passenger, stage: int, cell: Variant, stuck: int = -1) -> Passenger:
	var stub := Passenger.new()
	stub.id = p.id
	stub.stuck = p.stuck if stuck < 0 else stuck as Passenger.Stuck
	stub.stage = p.stage if stage < 0 else stage
	stub.at = p.at if cell == null else Vector2i(cell[0], cell[1])
	return stub


func _visit(p: Passenger, desk: int, end: int) -> Dictionary:
	return {"visits": [[p.id, desk, end]], "cooldowns": []}


func _cooldown(p: Passenger, tick: int) -> Dictionary:
	return {"visits": [], "cooldowns": [[p.id, tick]]}
