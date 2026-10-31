extends GdUnitTestSuite
## BirdFlock without the game (no car parks, so the perches always there):
## groups perched with their feet on the patch, a car inside the scatter
## radius sends a group to another perch of its zone where it lands again,
## one outside does not, a pause holds a flight, and a load throws the flock
## away and perches a new one.

const STEP := 0.05
const STARTER := preload("res://landside/starter_landside.tres")

var _flock: BirdFlock
var _save: SaveGame


func before_test() -> void:
	_save = auto_free(SaveGame.new())
	_flock = BirdFlock.new()
	_flock.save_game = _save
	add_child(_flock)
	_flock.rng.seed = 1234
	_flock.rebuild()


func after_test() -> void:
	_flock.free()


func _run(seconds: float, threats: PackedVector3Array) -> void:
	for i in roundi(seconds / STEP):
		_flock.step(STEP, threats)


func _bird_count() -> int:
	var n := 0
	for g in _flock.groups:
		n += (g["birds"] as Array).size()
	return n


## Groups expected with no car park: per zone, ZONE_GROUPS or one fewer than
## the zone's perches.
func _expected_groups() -> int:
	var none: Array[bool] = []
	var there := BirdPerches.available(none)
	var total := 0
	for zone in BirdFlock.ZONE_GROUPS.size():
		var n := 0
		for i in there:
			if BirdPerches.ZONES[i] == zone:
				n += 1
		total += mini(BirdFlock.ZONE_GROUPS[zone], n - 1)
	return total


## The first group on a forecourt patch (perches 0 to 3).
func _forecourt_group() -> Dictionary:
	for g in _flock.groups:
		if g["spot"] < 4:
			return g
	return {}


func _assert_perched(g: Dictionary) -> void:
	var centre: Vector3 = BirdPerches.SPOTS[g["spot"]]
	var half: Vector2 = BirdPerches.HALVES[g["spot"]]
	for b in g["birds"]:
		var at: Vector3 = (b["node"] as Node3D).position
		var lift := BirdFlock.FOOT_LIFT * _flock.bird_scale
		assert_float(at.y).is_equal_approx(centre.y + lift, 1e-4)
		assert_float(absf(at.x - centre.x)).is_less_equal(half.x + 1e-4)
		assert_float(absf(at.z - centre.z)).is_less_equal(half.y + 1e-4)


func test_groups_perch_on_distinct_spots() -> void:
	assert_int(_flock.groups.size()).is_equal(_expected_groups())
	var spots := {}
	for g in _flock.groups:
		spots[g["spot"]] = true
		assert_int(BirdPerches.LOTS[g["spot"]]).is_equal(-1)
		assert_int(g["target"]).is_equal(-1)
		var most: int = BirdFlock.ZONE_GROUP_MAX[BirdPerches.ZONES[g["spot"]]]
		assert_int((g["birds"] as Array).size()).is_between(BirdFlock.GROUP_MIN, most)
		_assert_perched(g)
	assert_int(spots.size()).is_equal(_flock.groups.size())
	print("groups=", _flock.groups.size(), " birds=", _bird_count(), " spots=", spots.keys())
	assert_float(_flock.bird_scale).is_equal(1.5)


func test_car_inside_radius_scatters_and_group_lands_elsewhere() -> void:
	var g: Dictionary = _flock.groups[0]
	var from: int = g["spot"]
	var spot: Vector3 = BirdPerches.SPOTS[from]
	var car := PackedVector3Array([Vector3(spot.x, 0.1, spot.z + 4.0)])
	_flock.step(STEP, car)
	var target: int = g["target"]
	print("scatter from=", from, " target=", target)
	assert_int(target).is_not_equal(-1)
	assert_int(target).is_not_equal(from)
	assert_int(BirdPerches.ZONES[target]).is_equal(BirdPerches.ZONES[from])
	assert_bool(_flock.busy_spots(g).has(target)).is_false()
	var top := 0.0
	var clips := {}
	for i in roundi(14.0 / STEP):
		_flock.step(STEP, PackedVector3Array())
		for b in g["birds"]:
			top = maxf(top, (b["node"] as Node3D).position.y)
			clips[b["clip"]] = true
	print("flight top_y=", top, " clips=", clips.keys())
	assert_float(top).is_greater(spot.y + 3.0)
	assert_array(clips.keys()).contains(["takeoff", "fly", "land"])
	assert_int(g["target"]).is_equal(-1)
	assert_int(g["spot"]).is_equal(target)
	_assert_perched(g)


func test_car_in_near_lane_leaves_a_forecourt_group_perched() -> void:
	var g := _forecourt_group()
	assert_dict(g).is_not_empty()
	var spot: Vector3 = BirdPerches.SPOTS[g["spot"]]
	var before: Array[Vector3] = []
	for b in g["birds"]:
		before.append((b["node"] as Node3D).position)
	_run(5.0, PackedVector3Array([Vector3(spot.x, 0.1, -55.0)]))
	assert_int(g["target"]).is_equal(-1)
	for i in before.size():
		assert_vector((g["birds"][i]["node"] as Node3D).position).is_equal(before[i])
	# Control: the same group does scatter once the car is at the berth.
	_flock.step(STEP, PackedVector3Array([Vector3(spot.x, 0.1, -57.2)]))
	assert_int(g["target"]).is_not_equal(-1)


func test_pause_holds_a_flight() -> void:
	var g: Dictionary = _flock.groups[0]
	_flock.step(STEP, PackedVector3Array([BirdPerches.SPOTS[g["spot"]]]))
	_run(1.2, PackedVector3Array())
	var b: Dictionary = g["birds"][0]
	var held: Vector3 = (b["node"] as Node3D).position
	var t: float = b["t"]
	_flock.step(0.0, PackedVector3Array())
	assert_vector((b["node"] as Node3D).position).is_equal(held)
	assert_float(b["t"]).is_equal(t)
	assert_float(held.y).is_greater(BirdPerches.SPOTS[g["spot"]].y + 0.5)


func test_load_throws_the_flock_away_and_perches_a_new_one() -> void:
	var g: Dictionary = _flock.groups[0]
	_flock.step(STEP, PackedVector3Array([BirdPerches.SPOTS[g["spot"]]]))
	_run(0.5, PackedVector3Array())
	var old := {}
	for og in _flock.groups:
		for b in og["birds"]:
			old[(b["node"] as Node3D).get_instance_id()] = b["node"]
	assert_int(old.size()).is_greater(0)
	_save.loaded.emit(true)
	for node in old.values():
		assert_bool((node as Node).is_queued_for_deletion()).is_true()
	assert_int(_flock.groups.size()).is_equal(_expected_groups())
	assert_int(_bird_count()).is_greater_equal(_expected_groups() * BirdFlock.GROUP_MIN)
	for ng in _flock.groups:
		assert_int(ng["target"]).is_equal(-1)
		_assert_perched(ng)
		for b in ng["birds"]:
			assert_bool(old.has((b["node"] as Node3D).get_instance_id())).is_false()


func test_failed_load_keeps_the_flock() -> void:
	var first: Node3D = _flock.groups[0]["birds"][0]["node"]
	_save.loaded.emit(false)
	assert_bool(first.is_queued_for_deletion()).is_false()


func test_birds_never_leave_the_patches() -> void:
	# A minute of a car driving up and down the curb: every perched group
	# stands on its patch top, never anywhere else.
	var landed := 0
	var flights := 0
	for i in roundi(60.0 / STEP):
		var x := -32.0 + fmod(i * STEP * 3.0, 24.0)
		_flock.step(STEP, PackedVector3Array([Vector3(x, 0.1, -57.2)]))
		for g in _flock.groups:
			if g["target"] < 0:
				_assert_perched(g)
				landed += 1
			else:
				flights += 1
	print("perched group checks=", landed, " flying group steps=", flights)
	assert_int(landed).is_greater(0)
	assert_int(flights).is_greater(0)


func test_missing_dependencies_are_named() -> void:
	var bare := BirdFlock.new()
	(
		assert_error(func() -> void: add_child(bare))
		. is_push_error(
			"BirdFlock: missing clock, passenger_views, landside_views, save_game; birds run degraded"
		)
	)
	assert_int(bare.groups.size()).is_greater(0)
	bare.free()


## Through the real _process: a paused SimClock holds a flight and sets every
## player to 0; at 3x a flight runs three times as fast and players run at 3.
func test_real_clock_pause_and_three_times_speed() -> void:
	var clock: SimClock = auto_free(SimClock.new())
	clock.set_process(false)
	add_child(clock)
	var f := BirdFlock.new()
	f.clock = clock
	add_child(f)
	f.rng.seed = 99
	f.rebuild()
	var g: Dictionary = f.groups[0]
	f.step(STEP, PackedVector3Array([BirdPerches.SPOTS[g["spot"]]]))
	f._process(0.5)
	var b: Dictionary = g["birds"][0]
	var held: Vector3 = (b["node"] as Node3D).position
	var t: float = b["t"]
	clock.set_paused(true)
	f._process(1.0)
	assert_vector((b["node"] as Node3D).position).is_equal(held)
	assert_float(b["t"]).is_equal(t)
	for bird in g["birds"]:
		assert_float((bird["player"] as AnimationPlayer).speed_scale).is_equal(0.0)
	clock.set_paused(false)
	clock.set_speed(3)
	f._process(0.1)
	print("3x: t ", t, " -> ", b["t"])
	assert_float(float(b["t"]) - t).is_equal_approx(0.3, 1e-4)
	for og in f.groups:
		for bird in og["birds"]:
			assert_float((bird["player"] as AnimationPlayer).speed_scale).is_equal(3.0)
	f.free()


## Through the real _process and LandsideViews: building the surface lot
## rebuilds the flock with the lot's perches there, removing it again drops
## them.
func test_building_a_lot_rebuilds_through_the_views() -> void:
	var sim: LandsideSim = auto_free(LandsideSim.new())
	sim.use_definition(STARTER)
	var views: LandsideViews = auto_free(LandsideViews.new())
	views.landside = sim
	add_child(views)
	var f := BirdFlock.new()
	f.landside_views = views
	add_child(f)
	f._process(0.2)
	var first: Node3D = f.groups[0]["birds"][0]["node"]
	assert_bool(first.is_queued_for_deletion()).is_false()
	assert_bool(sim.build_lot(0)).is_true()
	f._process(BirdFlock.SCAN_S + 0.01)
	assert_bool(first.is_queued_for_deletion()).is_true()
	assert_array(f._lots_seen).is_equal([true, false])
	var lot_closed := 0
	var closed := f.closed_spots({})
	for i in BirdPerches.SPOTS.size():
		if BirdPerches.LOTS[i] == 0 and closed.has(i):
			lot_closed += 1
	var on_lot := 0
	for g in f.groups:
		on_lot += 1 if BirdPerches.LOTS[g["spot"]] == 0 else 0
	print("groups after build=", f.groups.size(), " on lot=", on_lot, " lot closed=", lot_closed)
	# A lot perch is closed now only because a group holds it.
	assert_int(lot_closed).is_equal(on_lot)
	assert_bool(sim.remove_lot(0)).is_true()
	var second: Node3D = f.groups[0]["birds"][0]["node"]
	f._process(BirdFlock.SCAN_S + 0.01)
	assert_bool(second.is_queued_for_deletion()).is_true()
	for g in f.groups:
		assert_int(BirdPerches.LOTS[g["spot"]]).is_equal(-1)
	f.free()
