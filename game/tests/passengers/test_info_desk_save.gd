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
	assert_int(int(data["save_version"])).is_equal(12)
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
