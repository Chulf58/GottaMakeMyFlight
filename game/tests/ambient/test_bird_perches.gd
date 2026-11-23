extends GdUnitTestSuite
## BirdPerches: every ground patch and elevated prop perch measured against
## real outdoor surfaces (ground, site, road extensions, curb bays, car parks,
## streetlights, benches, trees), no perch on the terminal plot, scatter and
## cross-zone flight rules, lot availability, and spacing offsets.

const WORLD := preload("res://tests/ambient/bird_world.gd")
const SITE := preload("res://build/terminal_site.tres")
const SURFACE_TOLERANCE := 0.015

var _world: Array[Dictionary] = []


func before() -> void:
	_world = WORLD.build(self)


func test_tables_line_up() -> void:
	var n := BirdPerches.SPOTS.size()
	assert_int(BirdPerches.HALVES.size()).is_equal(n)
	assert_int(BirdPerches.ZONES.size()).is_equal(n)
	assert_int(BirdPerches.LOTS.size()).is_equal(n)
	assert_int(BirdPerches.perch_count()).is_greater(n)


## Every ground patch point stands flat at perch height under open sky, and
## every elevated perch point/slot sits cleanly on its prop top under open sky.
func test_every_perch_sits_on_real_surface_under_open_sky() -> void:
	assert_int(_world.size()).is_greater(0)
	var checked := 0
	var problems: Array[String] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in BirdPerches.perch_count():
		var spot := BirdPerches.spot_pos(i)
		if not BirdPerches.is_elevated(i):
			var half := BirdPerches.spot_half(i)
			for fx in [-1.0, -0.5, 0.0, 0.5, 1.0]:
				for fz in [-1.0, 0.0, 1.0]:
					var p := spot + Vector3(fx * half.x, 0.0, fz * half.y)
					checked += 1
					_check_point(i, p, problems)
		else:
			assert_bool(BirdPerches.can_stroll(i)).is_false()
			checked += 1
			_check_point(i, spot, problems)
			for off in BirdPerches.offsets(rng, BirdPerches.spot_capacity(i), i, 1.2):
				checked += 1
				_check_point(i, spot + off, problems)
	print("perch points=", checked, " problems=", problems.size())
	for line in problems:
		print("PERCH ", line)
	assert_int(checked).is_greater(BirdPerches.SPOTS.size() * 15)
	assert_array(problems).is_empty()


func _check_point(idx: int, p: Vector3, problems: Array[String]) -> void:
	var down := WORLD.first_hit(_world, p + Vector3.UP * 30.0, p + Vector3.DOWN * 1.0)
	if down.is_empty() or absf(float(down["y"]) - p.y) > SURFACE_TOLERANCE:
		problems.append(
			"perch %d (%s) at %s: surface %s" % [idx, BirdPerches.spot_kind(idx), p, down]
		)
		return
	var up := WORLD.first_hit(_world, Vector3(p.x, down["y"] + 0.05, p.z), p + Vector3.UP * 40.0)
	if not up.is_empty():
		problems.append(
			"perch %d (%s) at %s: covered by %s" % [idx, BirdPerches.spot_kind(idx), p, up]
		)


func test_control_a_lower_deck_reads_as_covered() -> void:
	var p := Vector3(-2.0, 5.3, -20.0)
	var up := WORLD.first_hit(_world, p + Vector3.UP * 0.05, p + Vector3.UP * 40.0)
	print("lower deck cover=", up)
	assert_dict(up).is_not_empty()


## No perch reaches onto the terminal plot (user ruling terminal-cutover).
func test_no_patch_is_on_the_terminal_plot() -> void:
	var plot := Rect2(Vector2(SITE.grid_origin.x, SITE.grid_origin.z), Vector2(SITE.grid_size))
	var on_plot: Array[int] = []
	for i in BirdPerches.perch_count():
		var pos := BirdPerches.spot_pos(i)
		var half := BirdPerches.spot_half(i)
		if plot.intersects(Rect2(Vector2(pos.x, pos.z) - half, half * 2.0 + Vector2(0.01, 0.01))):
			on_plot.append(i)
	print("plot ", plot, " perches ", BirdPerches.perch_count(), " on it ", on_plot)
	assert_int(BirdPerches.perch_count()).is_greater(0)
	assert_array(on_plot).is_empty()
	var edge := Rect2(Vector2(0.0, -60.4), Vector2(1.0, 0.8))
	assert_bool(plot.intersects(edge)).is_true()


func test_perches_there_follow_the_car_parks() -> void:
	var none: Array[bool] = [false, false]
	var surface: Array[bool] = [true, false]
	var both: Array[bool] = [true, true]
	var lot_spots := BirdPerches.LOTS.count(0)
	var total := BirdPerches.perch_count()
	assert_int(BirdPerches.available(none).size()).is_equal(total - lot_spots)
	assert_int(BirdPerches.available(surface).size()).is_equal(total)
	assert_int(BirdPerches.available(both).size()).is_equal(total)
	for i in total:
		if BirdPerches.spot_lot(i) >= 0:
			assert_int(BirdPerches.spot_zone(i)).is_equal(BirdPerches.Zone.EAST)


func test_car_in_near_lane_scatters_the_road_edge() -> void:
	var spot := BirdPerches.spot_pos(1)
	var car := Vector3(spot.x, 0.1, -55.0)
	print("lane distance=", BirdPerches.nearest(spot, PackedVector3Array([car])))
	assert_bool(BirdPerches.scatter_due(spot, PackedVector3Array([car]))).is_true()


func test_car_past_the_centre_line_does_not_scatter_the_road_edge() -> void:
	var spot := BirdPerches.spot_pos(1)
	var car := Vector3(spot.x, 0.1, -50.0)
	print("far lane distance=", BirdPerches.nearest(spot, PackedVector3Array([car])))
	assert_bool(BirdPerches.scatter_due(spot, PackedVector3Array([car]))).is_false()
	assert_bool(BirdPerches.scatter_due(spot, PackedVector3Array())).is_false()


func test_scatter_distance_is_flat() -> void:
	var spot := BirdPerches.spot_pos(0)
	var above := spot + Vector3(6.0, 5.0, 0.0)
	assert_bool(BirdPerches.scatter_due(spot, PackedVector3Array([above]))).is_true()


func test_pick_respects_can_fly_capacity_and_skips_busy() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var busy: Array[int] = [1, 12]
	var seen := {}
	for i in 40:
		var got := BirdPerches.pick(rng, 0, busy, PackedVector3Array(), 3)
		assert_int(got).is_not_equal(0)
		assert_bool(busy.has(got)).is_false()
		assert_bool(BirdPerches.can_fly(0, got)).is_true()
		assert_int(BirdPerches.spot_capacity(got)).is_greater_equal(3)
		seen[got] = true
	assert_int(seen.size()).is_greater(1)


func test_pick_prefers_a_clear_perch_and_crosses_zones() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var near_spot3 := PackedVector3Array([BirdPerches.spot_pos(3) + Vector3(-3, 0, 0)])
	var busy: Array[int] = []
	var saw_cross_zone := false
	for i in 40:
		var got := BirdPerches.pick(rng, 2, busy, near_spot3, 2)
		var gap := BirdPerches.nearest(BirdPerches.spot_pos(got), near_spot3)
		assert_float(gap).is_greater_equal(BirdPerches.LAND_CLEAR)
		if BirdPerches.spot_zone(got) != BirdPerches.spot_zone(2):
			saw_cross_zone = true
	assert_bool(saw_cross_zone).is_true()


func test_pick_returns_none_when_all_reachable_are_busy() -> void:
	var rng := RandomNumberGenerator.new()
	var all_reachable: Array[int] = []
	for i in BirdPerches.perch_count():
		if BirdPerches.can_fly(0, i):
			all_reachable.append(i)
	assert_int(BirdPerches.pick(rng, 0, all_reachable, PackedVector3Array())).is_equal(-1)


func test_pick_takes_farthest_when_none_is_clear() -> void:
	var rng := RandomNumberGenerator.new()
	var busy: Array[int] = []
	for i in BirdPerches.perch_count():
		if BirdPerches.can_fly(2, i) and i != 3 and i != 10:
			busy.append(i)
	# Threat is 1.5 m from perch 3 and 7.0 m from perch 10; both are inside LAND_CLEAR (9.0 m).
	var threats := PackedVector3Array([BirdPerches.spot_pos(3) + Vector3(-1.5, 0, 0)])
	assert_float(BirdPerches.nearest(BirdPerches.spot_pos(3), threats)).is_less(
		BirdPerches.LAND_CLEAR
	)
	assert_float(BirdPerches.nearest(BirdPerches.spot_pos(10), threats)).is_less(
		BirdPerches.LAND_CLEAR
	)
	assert_int(BirdPerches.pick(rng, 2, busy, threats, 1)).is_equal(10)


func test_offsets_fit_the_patch_and_keep_apart() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for case in [[0, 3], [1, 3], [3, 4], [7, 6]]:
		var spot: int = case[0]
		var offs := BirdPerches.offsets(rng, case[1], spot, 1.2)
		var half := BirdPerches.HALVES[spot]
		assert_int(offs.size()).is_equal(case[1])
		for i in offs.size():
			assert_float(absf(offs[i].x)).is_less_equal(half.x)
			assert_float(absf(offs[i].z)).is_less_equal(half.y)
			for j in range(i + 1, offs.size()):
				var apart := offs[i].distance_to(offs[j])
				assert_float(apart).is_greater_equal(BirdPerches.MIN_SPACING * 1.2)


func test_patches_are_disjoint_and_clear_of_street_dressing() -> void:
	for i in BirdPerches.SPOTS.size():
		var si := BirdPerches.SPOTS[i]
		var hi := BirdPerches.HALVES[i]
		for j in range(i + 1, BirdPerches.SPOTS.size()):
			var sj := BirdPerches.SPOTS[j]
			var hj := BirdPerches.HALVES[j]
			var overlap_x := absf(si.x - sj.x) < hi.x + hj.x
			var overlap_z := absf(si.z - sj.z) < hi.y + hj.y
			(
				assert_bool(overlap_x and overlap_z)
				. override_failure_message("patches %d and %d overlap" % [i, j])
				. is_false()
			)
	for p in LandsideStreetDressing.prop_specs():
		var pos: Vector3 = p["pos"]
		var hp: Vector2 = p["half"]
		for j in BirdPerches.SPOTS.size():
			var spot := BirdPerches.SPOTS[j]
			var half := BirdPerches.HALVES[j]
			var too_close_x := absf(pos.x - spot.x) < half.x + hp.x + 0.5
			var too_close_z := absf(pos.z - spot.z) < half.y + hp.y + 0.5
			(
				assert_bool(too_close_x and too_close_z)
				. override_failure_message("%s too close to perch %d" % [p["name"], j])
				. is_false()
			)


func test_offsets_pack_reliably_across_many_seeds() -> void:
	assert_float(BirdPerches.MIN_SPACING).is_greater_equal(0.90)
	var rng := RandomNumberGenerator.new()
	for s in 50:
		rng.seed = s + 100
		for i in BirdPerches.SPOTS.size():
			var want := 6 if BirdPerches.LOTS[i] >= 0 else 3
			var offs := BirdPerches.offsets(rng, want, i, 1.2)
			assert_int(offs.size()).override_failure_message("seed %d spot %d" % [s, i]).is_equal(
				want
			)
			for a in offs.size():
				for b in range(a + 1, offs.size()):
					assert_float(offs[a].distance_to(offs[b])).is_greater_equal(
						BirdPerches.MIN_SPACING * 1.2
					)
