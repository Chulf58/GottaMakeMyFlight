extends GdUnitTestSuite
## BirdFlock without the game (no car parks, so the perches always there):
## groups perched with their feet on the patch, a car inside the scatter
## radius sends a group to another perch of its zone where it lands again,
## one outside does not, a pause holds a flight, and a load throws the flock
## away and perches a new one.

const STEP := 0.05
const STARTER := preload("res://landside/starter_landside.tres")


## An intentional PassengerViews fake: no sim, so it draws no passengers and
## the flock reads none; its own _ready (pools, rings) is skipped.
class NoPassengerViews:
	extends PassengerViews

	func _ready() -> void:
		pass

	# The nodes PassengerViews builds as members, which its skipped _ready
	# would have parented, are freed with the fake so none is left orphaned.
	func _notification(what: int) -> void:
		if what != NOTIFICATION_PREDELETE:
			return
		for n in [follow_anchor, _ring, _markers, _pops, _props, ghosts]:
			if n is Node and is_instance_valid(n) and (n as Node).get_parent() == null:
				(n as Node).free()


## A flock whose cars and passengers are one point the test moves, read on
## the flock's own scan schedule (its _process is the real one).
class OneCarFlock:
	extends BirdFlock
	var car := Vector3(1000, 0, 1000)

	func threats_now() -> PackedVector3Array:
		_threats.resize(0)
		_threats.append(car)
		return _threats


var _flock: BirdFlock
var _save: SaveGame
var _clock: SimClock
var _landside: LandsideSim
var _views: LandsideViews
var _pax: NoPassengerViews


## Every dependency real (SimClock not processing; the tests advance it),
## except the passenger views, an intentional fake.
func before_test() -> void:
	_save = auto_free(SaveGame.new())
	_clock = auto_free(SimClock.new())
	_clock.set_process(false)
	add_child(_clock)
	_landside = auto_free(LandsideSim.new())
	_landside.use_definition(STARTER)
	_views = auto_free(LandsideViews.new())
	_views.landside = _landside
	add_child(_views)
	_pax = auto_free(NoPassengerViews.new())
	add_child(_pax)
	_flock = _wired(BirdFlock.new(), 1234)


func after_test() -> void:
	_flock.free()


func _wired(f: BirdFlock, seed_value: int) -> BirdFlock:
	f.clock = _clock
	f.save_game = _save
	f.landside_views = _views
	f.passenger_views = _pax
	add_child(f)
	f.rng.seed = seed_value
	f.rebuild()
	return f


func _run(seconds: float, threats: PackedVector3Array) -> void:
	for i in roundi(seconds / STEP):
		_flock.step(STEP, threats)


func _bird_count() -> int:
	var n := 0
	for g in _flock.groups:
		n += (g["birds"] as Array).size()
	return n


## Groups expected with no car park: per zone ground groups + ELEVATED_GROUPS.
func _expected_groups() -> int:
	var none: Array[bool] = []
	var there := BirdPerches.available(none)
	var total := 0
	for zone in BirdFlock.ZONE_GROUPS.size():
		var n := 0
		for i in there:
			if not BirdPerches.is_elevated(i) and BirdPerches.spot_zone(i) == zone:
				n += 1
		total += mini(BirdFlock.ZONE_GROUPS[zone], maxi(n - 1, 0))
	var elevated := 0
	for i in there:
		if BirdPerches.is_elevated(i):
			elevated += 1
	return total + mini(BirdFlock.ELEVATED_GROUPS, elevated)


## The first ground group on a road-edge patch (perches 0, 1, or 12).
func _road_edge_group() -> Dictionary:
	for g in _flock.groups:
		var s: int = g["spot"]
		if s == 0 or s == 1 or s == 12:
			return g
	return {}


func _assert_perched(g: Dictionary) -> void:
	var spot: int = g["spot"]
	var centre := BirdPerches.spot_pos(spot)
	var half := BirdPerches.spot_half(spot)
	var span_x := half.x if half.x > 0.0 else 0.7
	var span_z := half.y if half.y > 0.0 else 0.7
	for b in g["birds"]:
		var at: Vector3 = (b["node"] as Node3D).position
		var lift := BirdFlock.FOOT_LIFT * _flock.bird_scale
		assert_float(at.y).is_equal_approx(centre.y + lift, 1e-4)
		assert_float(absf(at.x - centre.x)).is_less_equal(span_x + 1e-4)
		assert_float(absf(at.z - centre.z)).is_less_equal(span_z + 1e-4)


func test_groups_perch_on_distinct_spots() -> void:
	assert_int(_flock.groups.size()).is_equal(_expected_groups())
	var spots := {}
	for g in _flock.groups:
		var s: int = g["spot"]
		spots[s] = true
		assert_int(BirdPerches.spot_lot(s)).is_equal(-1)
		assert_int(g["target"]).is_equal(-1)
		var most: int = BirdPerches.spot_capacity(s)
		var least := 1 if BirdPerches.is_elevated(s) else BirdFlock.GROUND_GROUP_MIN
		assert_int((g["birds"] as Array).size()).is_between(least, most)
		_assert_perched(g)
	assert_int(spots.size()).is_equal(_flock.groups.size())
	print("groups=", _flock.groups.size(), " birds=", _bird_count(), " spots=", spots.keys())
	assert_float(_flock.bird_scale).is_equal(1.2)


func test_car_inside_radius_scatters_and_group_lands_elsewhere() -> void:
	var g: Dictionary = _flock.groups[0]
	var from: int = g["spot"]
	var spot := BirdPerches.spot_pos(from)
	var car := PackedVector3Array([Vector3(spot.x, 0.1, spot.z + 4.0)])
	_flock.step(STEP, car)
	var target: int = g["target"]
	print("scatter from=", from, " target=", target)
	assert_int(target).is_not_equal(-1)
	assert_int(target).is_not_equal(from)
	assert_bool(BirdPerches.can_fly(from, target)).is_true()
	assert_bool(_flock.busy_spots(g).has(target)).is_false()
	var top := 0.0
	var clips := {}
	for i in roundi(14.0 / STEP):
		_flock.step(STEP, PackedVector3Array())
		for b in g["birds"]:
			top = maxf(top, (b["node"] as Node3D).position.y)
			clips[b["clip"]] = true
	print("flight top_y=", top, " clips=", clips.keys())
	assert_float(top).is_greater(spot.y + 2.0)
	assert_array(clips.keys()).contains(["takeoff", "fly", "land"])
	assert_int(g["target"]).is_equal(-1)
	assert_int(g["spot"]).is_equal(target)
	_assert_perched(g)


func test_car_past_the_centre_line_leaves_a_road_edge_group_perched() -> void:
	var g := _road_edge_group()
	assert_dict(g).is_not_empty()
	var spot := BirdPerches.spot_pos(g["spot"])
	_run(5.0, PackedVector3Array([Vector3(spot.x, 0.1, -50.0)]))
	assert_int(g["target"]).is_equal(-1)
	_assert_perched(g)
	# Control: the same group does scatter once the car is in the near lane.
	_flock.step(STEP, PackedVector3Array([Vector3(spot.x, 0.1, -55.0)]))
	assert_int(g["target"]).is_not_equal(-1)


func test_pause_holds_a_flight() -> void:
	var g: Dictionary = _flock.groups[0]
	_flock.step(STEP, PackedVector3Array([BirdPerches.spot_pos(g["spot"])]))
	_run(1.2, PackedVector3Array())
	var b: Dictionary = g["birds"][0]
	var held: Vector3 = (b["node"] as Node3D).position
	var t: float = b["t"]
	_flock.step(0.0, PackedVector3Array())
	assert_vector((b["node"] as Node3D).position).is_equal(held)
	assert_float(b["t"]).is_equal(t)
	assert_float(held.y).is_greater(BirdPerches.spot_pos(g["spot"]).y + 0.5)


func test_load_throws_the_flock_away_and_perches_a_new_one() -> void:
	var g: Dictionary = _flock.groups[0]
	_flock.step(STEP, PackedVector3Array([BirdPerches.spot_pos(g["spot"])]))
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
		var x := -40.0 + fmod(i * STEP * 3.0, 24.0)
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
	var clock := _clock
	var f := _flock
	var g: Dictionary = f.groups[0]
	_flock.step(STEP, PackedVector3Array([BirdPerches.spot_pos(g["spot"])]))
	_flock._process(0.5)
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


## Through the real _process, SimClock ticks and LandsideViews: building the
## surface lot rebuilds the flock with the lot's perches there, removing it
## again drops them.
func test_building_a_lot_rebuilds_through_the_views() -> void:
	var sim := _landside
	var f := _flock
	_tick_and_process(f)
	var first: Node3D = f.groups[0]["birds"][0]["node"]
	assert_bool(first.is_queued_for_deletion()).is_false()
	assert_bool(sim.build_lot(0)).is_true()
	_tick_and_process(f)
	assert_bool(first.is_queued_for_deletion()).is_true()
	assert_array(f._lots_seen).is_equal([true, false])
	var lot_closed := 0
	var closed := f.closed_spots({})
	for i in BirdPerches.SPOTS.size():
		if BirdPerches.LOTS[i] == 0 and closed.has(i):
			lot_closed += 1
	var on_lot := 0
	for g in f.groups:
		on_lot += 1 if BirdPerches.spot_lot(g["spot"]) == 0 else 0
	print("groups after build=", f.groups.size(), " on lot=", on_lot, " lot closed=", lot_closed)
	# A lot perch is closed now only because a group holds it.
	assert_int(lot_closed).is_equal(on_lot)
	assert_bool(sim.remove_lot(0)).is_true()
	var second: Node3D = f.groups[0]["birds"][0]["node"]
	_tick_and_process(f)
	assert_bool(second.is_queued_for_deletion()).is_true()
	for g in f.groups:
		assert_int(BirdPerches.spot_lot(g["spot"])).is_equal(-1)


## One sim tick on the real clock, then one frame of the flock.
func _tick_and_process(f: BirdFlock) -> void:
	_clock.advance(SimClock.STEP)
	f._process(SimClock.STEP)


## Regression for the 0.15 s real-time scan: at 3x a car passing 6.2 m from a
## perch is inside the 6.3 m radius for 2.24 m of road, 0.075 real seconds,
## between two of the old scan frames (1/60 s and 0.167 s). Scanning on every
## sim tick (one per frame at 3x and 60 fps) catches it.
func test_a_car_crossing_the_radius_between_old_scans_scatters() -> void:
	var f: OneCarFlock = _wired(OneCarFlock.new(), 1234)
	var g: Dictionary = f.groups[0]
	var spot := BirdPerches.spot_pos(g["spot"])
	_clock.set_speed(3)
	var dt := 1.0 / 60.0
	var t := 0.0
	var inside := 0
	var caught_at := -1.0
	for i in 30:
		t += dt
		f.car = Vector3(spot.x - 1.118 + 30.0 * (t - 0.04), 0.1, spot.z + 6.2)
		if BirdPerches.scatter_due(spot, PackedVector3Array([f.car])):
			inside += 1
		_clock.advance(dt)
		f._process(dt)
		if g["target"] >= 0 and caught_at < 0.0:
			caught_at = t
	print("frames inside radius=", inside, " scattered at t=", caught_at)
	assert_int(inside).is_greater(0)
	assert_int(g["target"]).is_not_equal(-1)
	f.free()


## VF7 regression: evaluated skinned crow mesh never dips below -0.0070 m during eat
## (so BirdFlock.FOOT_LIFT keeps feet >= -0.0005 m at ground contact).
func test_crow_eat_animation_keeps_feet_on_perch() -> void:
	var crow: Node3D = auto_free(BirdFlock.CROW.instantiate() as Node3D)
	add_child(crow)
	var player := crow.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skel := crow.find_child("Skeleton3D", true, false) as Skeleton3D
	assert_object(player).is_not_null()
	assert_object(skel).is_not_null()
	player.callback_mode_process = AnimationPlayer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	player.speed_scale = 0.0
	var surfaces: Array = []
	for mi: MeshInstance3D in crow.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null or mi.mesh == null or not (mi.name in BirdFlock.VARIANTS):
			continue
		var bind_bones := PackedInt32Array()
		var bind_poses: Array[Transform3D] = []
		for bind in mi.skin.get_bind_count():
			var bname := mi.skin.get_bind_name(bind)
			bind_bones.append(skel.find_bone(bname) if bname != "" else mi.skin.get_bind_bone(bind))
			bind_poses.append(mi.skin.get_bind_pose(bind))
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / verts.size()
			surfaces.append([bind_bones, bind_poses, verts, bones, weights, per])
	assert_bool(surfaces.is_empty()).is_false()
	player.play("idle_01")
	player.seek(0.0, true)
	await skel.skeleton_updated
	var idle_min_y := _crow_skinned_min_y(crow, skel, surfaces)
	var eat_len := player.get_animation("eat").length
	var eat_min_y := INF
	var worst_step := -1
	player.play("eat")
	for step in 61:
		player.seek(eat_len * float(step) / 60.0, true)
		await skel.skeleton_updated
		var min_y := _crow_skinned_min_y(crow, skel, surfaces)
		if min_y < eat_min_y:
			eat_min_y = min_y
			worst_step = step
	var lifted_y := eat_min_y + BirdFlock.FOOT_LIFT
	print(
		(
			"crow eat evaluated mesh: min_y=%.5f lifted_y=%.5f idle_min_y=%.5f (worst_step=%d)"
			% [eat_min_y, lifted_y, idle_min_y, worst_step]
		)
	)
	assert_float(eat_min_y).is_greater_equal(-0.0070)
	assert_float(lifted_y).is_greater_equal(-0.0005)


static func _crow_skinned_min_y(crow: Node3D, skel: Skeleton3D, surfaces: Array) -> float:
	var to_crow := crow.global_transform.affine_inverse() * skel.global_transform
	var min_y := INF
	for surf: Array in surfaces:
		var bind_bones: PackedInt32Array = surf[0]
		var bind_poses: Array[Transform3D] = surf[1]
		var verts: PackedVector3Array = surf[2]
		var bones: PackedInt32Array = surf[3]
		var weights: PackedFloat32Array = surf[4]
		var per: int = surf[5]
		var mats: Array[Transform3D] = []
		for b in bind_bones.size():
			mats.append(to_crow * skel.get_bone_global_pose(bind_bones[b]) * bind_poses[b])
		for k in verts.size():
			var v := Vector3.ZERO
			for j in per:
				var w := weights[k * per + j]
				if w > 0.0:
					v += (mats[bones[k * per + j]] * verts[k]) * w
			min_y = minf(min_y, v.y)
	return min_y


func test_perched_birds_keep_clear_spacing_and_avoid_adjacent_clumps() -> void:
	var crow: Node3D = auto_free(BirdFlock.CROW.instantiate() as Node3D)
	var crow_length := 0.0
	for v in BirdFlock.VARIANTS:
		var mi := crow.find_child(v, true, false) as MeshInstance3D
		assert_object(mi).is_not_null()
		crow_length = maxf(crow_length, mi.get_aabb().size.z)
	var min_apart := BirdPerches.MIN_SPACING * _flock.bird_scale
	print("crow_length_1.5=%.3f min_apart=%.3f" % [crow_length * _flock.bird_scale, min_apart])
	assert_float(min_apart).is_greater(crow_length * _flock.bird_scale)
	for s in 20:
		_flock.rng.seed = 2000 + s
		_flock.rebuild()
		var positions: Array[Vector3] = []
		var west_spots: Array[int] = []
		var east_spots: Array[int] = []
		for g in _flock.groups:
			var spot: int = g["spot"]
			var zone := BirdPerches.spot_zone(spot)
			assert_int((g["birds"] as Array).size()).is_less_equal(3)
			if not BirdPerches.is_elevated(spot):
				if zone == BirdPerches.Zone.WEST:
					west_spots.append(spot)
				elif zone == BirdPerches.Zone.EAST:
					east_spots.append(spot)
			for b in g["birds"]:
				positions.append((b["node"] as Node3D).position)
		for z_spots in [west_spots, east_spots]:
			for i in z_spots.size():
				for j in range(i + 1, z_spots.size()):
					var a := BirdPerches.spot_pos(z_spots[i])
					var b := BirdPerches.spot_pos(z_spots[j])
					var gap := Vector2(a.x - b.x, a.z - b.z).length()
					assert_float(gap).is_greater_equal(BirdFlock.MIN_GROUP_GAP)
		for i in positions.size():
			for j in range(i + 1, positions.size()):
				var d := (
					Vector2(positions[i].x - positions[j].x, positions[i].z - positions[j].z)
					. length()
				)
				assert_float(d).is_greater_equal(min_apart)
	# Verify a scattered group also lands >= MIN_GROUP_GAP from other active groups.
	_flock.rng.seed = 1234
	_flock.rebuild()
	var west_group := {}
	for g in _flock.groups:
		var s: int = g["spot"]
		if not BirdPerches.is_elevated(s) and BirdPerches.spot_zone(s) == BirdPerches.Zone.WEST:
			west_group = g
			break
	assert_dict(west_group).is_not_empty()
	var src := BirdPerches.spot_pos(west_group["spot"])
	_flock.step(STEP, PackedVector3Array([src]))
	var target: int = west_group["target"]
	assert_int(target).is_not_equal(-1)
	for g in _flock.groups:
		if g != west_group:
			var other := BirdPerches.spot_pos(g["spot"])
			var tgt := BirdPerches.spot_pos(target)
			assert_float(Vector2(tgt.x - other.x, tgt.z - other.z).length()).is_greater_equal(
				BirdFlock.MIN_GROUP_GAP
			)
	_run(14.0, PackedVector3Array())
	assert_int(west_group["target"]).is_equal(-1)
	for i in west_group["birds"].size():
		for j in range(i + 1, west_group["birds"].size()):
			var pa: Vector3 = (west_group["birds"][i]["node"] as Node3D).position
			var pb: Vector3 = (west_group["birds"][j]["node"] as Node3D).position
			assert_float(Vector2(pa.x - pb.x, pa.z - pb.z).length()).is_greater_equal(min_apart)
