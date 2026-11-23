extends GdUnitTestSuite
## Polish suite for Ambient Birds (decision 2be8c419): 1.2x scale, curb
## ping-pong fix, elevated perches (streetlights, benches, trees) & grass
## verges with bounded stroll, ground strolling via walk + turns, flight
## banking roll + pause freeze, cross-zone flights, takeoff puff pool/cleanup,
## and cooldown-gated Ambience-bus bird_scatter audio.

const STEP := 0.05
const STARTER := preload("res://landside/starter_landside.tres")
const GAME_AUDIO := preload("res://audio/game_audio.gd")


class NoPassengerViews:
	extends PassengerViews

	func _ready() -> void:
		pass

	func _notification(what: int) -> void:
		if what != NOTIFICATION_PREDELETE:
			return
		for n in [follow_anchor, _ring, _markers, _pops, _props, ghosts]:
			if n is Node and is_instance_valid(n) and (n as Node).get_parent() == null:
				(n as Node).free()


var _flock: BirdFlock
var _save: SaveGame
var _clock: SimClock
var _landside: LandsideSim
var _views: LandsideViews
var _pax: NoPassengerViews
var _audio: GAME_AUDIO
var _cfg_path := ""


func before_test() -> void:
	_audio = get_node("/root/GameAudio") as GAME_AUDIO
	_cfg_path = SaveTestKit.run_path("birds_polish_audio").replace(".json", ".cfg")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_cfg_path))
	_audio.reset_for_test()
	_audio.set_settings_path(_cfg_path)
	_save = auto_free(SaveGame.new())
	_clock = auto_free(SimClock.new())
	_clock.set_process(false)
	_clock.set_paused(false)
	add_child(_clock)
	_landside = auto_free(LandsideSim.new())
	_landside.use_definition(STARTER)
	_views = auto_free(LandsideViews.new())
	_views.landside = _landside
	add_child(_views)
	_pax = auto_free(NoPassengerViews.new())
	add_child(_pax)
	_flock = BirdFlock.new()
	_flock.clock = _clock
	_flock.save_game = _save
	_flock.landside_views = _views
	_flock.passenger_views = _pax
	add_child(_flock)
	_flock.rng.seed = 20261123
	_flock.rebuild()


func after_test() -> void:
	if is_instance_valid(_flock):
		_flock.free()
	if _audio != null:
		_audio.reset_for_test()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_cfg_path))


func test_scale_expanded_curb_grass_and_elevated_perch_categories() -> void:
	assert_float(_flock.bird_scale).is_equal_approx(1.2, 1e-4)
	var curb_count := 0
	var kinds := {}
	for i in BirdPerches.perch_count():
		var k := BirdPerches.spot_kind(i)
		kinds[k] = int(kinds.get(k, 0)) + 1
		if (
			not BirdPerches.is_elevated(i)
			and BirdPerches.spot_zone(i) == BirdPerches.Zone.UNDER_CANOPY
		):
			curb_count += 1
		if BirdPerches.is_elevated(i):
			assert_bool(BirdPerches.can_stroll(i)).is_false()
			assert_vector(BirdPerches.spot_half(i)).is_equal(Vector2.ZERO)
			assert_int(BirdPerches.spot_capacity(i)).is_between(1, 2)
			if k == "lamp_ped" or k == "lamp_hwy" or k == "pine" or k == "tree_planter":
				assert_int(BirdPerches.spot_capacity(i)).is_equal(1)
	assert_int(curb_count).is_greater(2)
	for req_kind in ["grass", "lamp_ped", "lamp_hwy", "bench", "tree_planter", "pine", "tree_leaf"]:
		(
			assert_int(int(kinds.get(req_kind, 0)))
			. override_failure_message("Missing perch kind %s" % req_kind)
			. is_greater(0)
		)


func test_ground_birds_stroll_with_walk_clip_and_elevated_birds_stay_put() -> void:
	var ground_group := {}
	var elevated_group := {}
	for g in _flock.groups:
		if not BirdPerches.is_elevated(g["spot"]) and ground_group.is_empty():
			ground_group = g
		elif BirdPerches.is_elevated(g["spot"]) and elevated_group.is_empty():
			elevated_group = g
	assert_dict(ground_group).is_not_empty()
	assert_dict(elevated_group).is_not_empty()

	var initial_pos := {}
	var initial_fwd := {}
	for g in [ground_group, elevated_group]:
		for b in g["birds"]:
			var n: Node3D = b["node"]
			initial_pos[n.get_instance_id()] = n.position
			initial_fwd[n.get_instance_id()] = Vector3(b["forward"])

	var saw_walk_clip := false
	var moved_ground := 0
	var turned_ground := 0
	var max_elevated_drift := 0.0
	var min_apart := BirdPerches.MIN_SPACING * _flock.bird_scale
	for _step in 240:
		_flock.step(STEP, PackedVector3Array())
		for b in ground_group["birds"]:
			if b["clip"] == "walk":
				saw_walk_clip = true
		# Ground birds preserve patch bounds and spacing throughout strolling.
		var gspot: int = ground_group["spot"]
		var gc := BirdPerches.spot_pos(gspot)
		var gh := BirdPerches.spot_half(gspot)
		var b_arr: Array = ground_group["birds"]
		for i in b_arr.size():
			var p := (b_arr[i]["node"] as Node3D).position
			assert_float(absf(p.x - gc.x)).is_less_equal(gh.x + 1e-4)
			assert_float(absf(p.z - gc.z)).is_less_equal(gh.y + 1e-4)
			for j in range(i + 1, b_arr.size()):
				var q := (b_arr[j]["node"] as Node3D).position
				assert_float(Vector2(p.x - q.x, p.z - q.z).length()).is_greater_equal(
					min_apart - 0.05
				)
		for b in elevated_group["birds"]:
			if elevated_group["target"] < 0:
				var n: Node3D = b["node"]
				var d: float = n.position.distance_to(initial_pos[n.get_instance_id()])
				max_elevated_drift = maxf(max_elevated_drift, d)
	for b in ground_group["birds"]:
		var n: Node3D = b["node"]
		if n.position.distance_to(initial_pos[n.get_instance_id()]) > 0.08:
			moved_ground += 1
		if (b["forward"] as Vector3).distance_to(initial_fwd[n.get_instance_id()]) > 0.05:
			turned_ground += 1
	assert_bool(saw_walk_clip).is_true()
	assert_int(moved_ground).is_greater(0)
	assert_int(turned_ground).is_greater(0)
	assert_float(max_elevated_drift).is_less_equal(0.001)


func test_flight_applies_banking_roll_levels_on_landing_and_freezes_when_paused() -> void:
	# Pick a group and scatter to a spot with differing X so the curve banks.
	var g := {}
	for cand in _flock.groups:
		if not BirdPerches.is_elevated(cand["spot"]):
			g = cand
			break
	assert_dict(g).is_not_empty()
	var from_spot: int = g["spot"]
	_flock.step(STEP, PackedVector3Array([BirdPerches.spot_pos(from_spot)]))
	assert_int(g["target"]).is_not_equal(-1)

	var max_abs_roll := 0.0
	var checked_pause := false
	for _i in roundi(14.0 / STEP):
		_flock.step(STEP, PackedVector3Array())
		for b in g["birds"]:
			if not b["landed"]:
				max_abs_roll = maxf(max_abs_roll, absf(float(b["roll"])))
		if not checked_pause and float(g["birds"][0]["t"]) > BirdFlock.TAKEOFF_S + 0.4:
			checked_pause = true
			var b0: Dictionary = g["birds"][0]
			var held_pos := (b0["node"] as Node3D).position
			var held_rot := (b0["node"] as Node3D).rotation
			_clock.set_paused(true)
			_flock._process(0.5)
			assert_vector((b0["node"] as Node3D).position).is_equal(held_pos)
			assert_vector((b0["node"] as Node3D).rotation).is_equal(held_rot)
			_clock.set_paused(false)
	assert_int(g["target"]).is_equal(-1)
	assert_float(max_abs_roll).is_greater(0.015)
	for b in g["birds"]:
		assert_float(absf(float(b["roll"]))).is_less_equal(1e-4)
		var local_up := (b["node"] as Node3D).basis.y.normalized()
		assert_float(local_up.dot(Vector3.UP)).is_greater(0.99)


func test_cross_zone_flight_reachability() -> void:
	var cross_edges := 0
	for i in BirdPerches.perch_count():
		for j in BirdPerches.perch_count():
			if BirdPerches.can_fly(i, j) and BirdPerches.spot_zone(i) != BirdPerches.spot_zone(j):
				cross_edges += 1
	assert_int(cross_edges).is_greater(50)


func test_takeoff_puff_pool_cap_cleanup_and_audio_cooldown() -> void:
	var fake_now := [10000]
	_audio._clock_ms = func() -> int: return fake_now[0]
	assert_int(_flock.active_puff_count()).is_equal(0)

	# First startled scatter spawns a puff and plays bird_scatter once.
	var g0: Dictionary = _flock.groups[0]
	_flock.step(STEP, PackedVector3Array([BirdPerches.spot_pos(g0["spot"])]))
	assert_int(_flock.active_puff_count()).is_equal(1)
	assert_int(_audio.sfx_count(&"bird_scatter")).is_equal(1)
	assert_str(String(_audio.last_sfx())).is_equal("bird_scatter")

	# Rapid scatters across other groups within 5000 ms cap puffs and stay silent.
	fake_now[0] = 11500
	for idx in range(1, _flock.groups.size()):
		var gi: Dictionary = _flock.groups[idx]
		_flock.step(STEP, PackedVector3Array([BirdPerches.spot_pos(gi["spot"])]))
	assert_int(_flock.active_puff_count()).is_less_equal(BirdFlock.MAX_PUFFS)
	assert_int(_audio.sfx_count(&"bird_scatter")).is_equal(1)

	# Advancing past PUFF_LIFE_S frees active puffs cleanly with 0 orphans.
	for _i in roundi((BirdFlock.PUFF_LIFE_S + 0.2) / STEP):
		_flock.step(STEP, PackedVector3Array())
	await await_idle_frame()
	assert_int(_flock.active_puff_count()).is_equal(0)

	# After cooldown elapses (5000 ms), a new scatter triggers bird_scatter again.
	for _i in roundi(14.0 / STEP):
		_flock.step(STEP, PackedVector3Array())
	fake_now[0] = 16000
	var g_after: Dictionary = _flock.groups[0]
	_flock.step(STEP, PackedVector3Array([BirdPerches.spot_pos(g_after["spot"])]))
	assert_int(_audio.sfx_count(&"bird_scatter")).is_equal(2)
