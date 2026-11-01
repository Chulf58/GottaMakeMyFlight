extends GdUnitTestSuite
## BirdPerches: every patch measured against the outdoor surfaces (site,
## curb bays, both car parks built), no patch on the terminal plot, the
## scatter decision, perch choice within a zone, the perches there with and
## without car parks, and patch offsets.

const WORLD := preload("res://tests/ambient/bird_world.gd")
const SITE := preload("res://build/terminal_site.tres")
const SURFACE_TOLERANCE := 0.01

var _world: Array[Dictionary] = []


func before() -> void:
	_world = WORLD.build(self)


func test_tables_line_up() -> void:
	var n := BirdPerches.SPOTS.size()
	assert_int(BirdPerches.HALVES.size()).is_equal(n)
	assert_int(BirdPerches.ZONES.size()).is_equal(n)
	assert_int(BirdPerches.LOTS.size()).is_equal(n)


## Every patch point stands on one flat surface at the perch height, with
## open sky over it: no perch is under a deck slab or a curb bay.
func test_every_patch_is_flat_under_open_sky() -> void:
	assert_int(_world.size()).is_greater(0)
	var checked := 0
	var problems: Array[String] = []
	for i in BirdPerches.SPOTS.size():
		var spot := BirdPerches.SPOTS[i]
		var half := BirdPerches.HALVES[i]
		for fx in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			for fz in [-1.0, 0.0, 1.0]:
				var p := spot + Vector3(fx * half.x, 0.0, fz * half.y)
				var down := WORLD.first_hit(_world, p + Vector3.UP * 30.0, p + Vector3.DOWN * 1.0)
				checked += 1
				if down.is_empty() or absf(float(down["y"]) - spot.y) > SURFACE_TOLERANCE:
					problems.append("perch %d at %s: surface %s" % [i, p, down])
					continue
				var up := WORLD.first_hit(
					_world, Vector3(p.x, down["y"] + 0.05, p.z), p + Vector3.UP * 40.0
				)
				if not up.is_empty():
					problems.append("perch %d at %s: covered by %s" % [i, p, up])
	print("perch points=", checked, " problems=", problems.size())
	for line in problems:
		print("PERCH ", line)
	assert_int(checked).is_equal(BirdPerches.SPOTS.size() * 15)
	assert_array(problems).is_empty()


func test_control_a_lower_deck_reads_as_covered() -> void:
	# Control for the check above: the multi-storey's middle deck (5.3 m) has
	# the top deck over it, so a perch there would be refused.
	var p := Vector3(-2.0, 5.3, -20.0)
	var up := WORLD.first_hit(_world, p + Vector3.UP * 0.05, p + Vector3.UP * 40.0)
	print("lower deck cover=", up)
	assert_dict(up).is_not_empty()


## No patch reaches onto the terminal plot, where the player builds (user
## ruling terminal-cutover-bird-perches-move-off-the-buildable-plot-re).
func test_no_patch_is_on_the_terminal_plot() -> void:
	var plot := Rect2(Vector2(SITE.grid_origin.x, SITE.grid_origin.z), Vector2(SITE.grid_size))
	var on_plot: Array[int] = []
	for i in BirdPerches.SPOTS.size():
		var centre := Vector2(BirdPerches.SPOTS[i].x, BirdPerches.SPOTS[i].z)
		var half := BirdPerches.HALVES[i]
		if plot.intersects(Rect2(centre - half, half * 2.0)):
			on_plot.append(i)
	print("plot ", plot, " perches ", BirdPerches.SPOTS.size(), " on it ", on_plot)
	assert_int(BirdPerches.SPOTS.size()).is_greater(0)
	assert_array(on_plot).is_empty()
	# Control: a patch on the plot's south edge would be caught.
	var edge := Rect2(Vector2(0.0, -60.4), Vector2(1.0, 0.8))
	assert_bool(plot.intersects(edge)).is_true()


func test_perches_there_follow_the_car_parks() -> void:
	var none: Array[bool] = [false, false]
	var surface: Array[bool] = [true, false]
	var both: Array[bool] = [true, true]
	var always := BirdPerches.LOTS.count(-1)
	assert_int(BirdPerches.available(none).size()).is_equal(always)
	assert_int(BirdPerches.available(surface).size()).is_equal(always + BirdPerches.LOTS.count(0))
	assert_int(BirdPerches.available(both).size()).is_equal(BirdPerches.SPOTS.size())
	for i in BirdPerches.SPOTS.size():
		if BirdPerches.LOTS[i] >= 0:
			assert_int(BirdPerches.ZONES[i]).is_equal(BirdPerches.Zone.EAST)


func test_car_in_near_lane_scatters_the_road_edge() -> void:
	var spot: Vector3 = BirdPerches.SPOTS[1]
	var car := Vector3(spot.x, 0.1, -55.0)
	print("lane distance=", BirdPerches.nearest(spot, PackedVector3Array([car])))
	assert_bool(BirdPerches.scatter_due(spot, PackedVector3Array([car]))).is_true()


func test_car_past_the_centre_line_does_not_scatter_the_road_edge() -> void:
	var spot: Vector3 = BirdPerches.SPOTS[1]
	var car := Vector3(spot.x, 0.1, -50.0)
	print("far lane distance=", BirdPerches.nearest(spot, PackedVector3Array([car])))
	assert_bool(BirdPerches.scatter_due(spot, PackedVector3Array([car]))).is_false()
	assert_bool(BirdPerches.scatter_due(spot, PackedVector3Array())).is_false()


func test_scatter_distance_is_flat() -> void:
	var spot: Vector3 = BirdPerches.SPOTS[0]
	var above := spot + Vector3(6.0, 5.0, 0.0)
	assert_bool(BirdPerches.scatter_due(spot, PackedVector3Array([above]))).is_true()


func test_pick_stays_in_zone_and_skips_busy() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var busy: Array[int] = []
	var seen := {}
	for i in 40:
		seen[BirdPerches.pick(rng, 1, busy, PackedVector3Array())] = true
	assert_array(seen.keys()).contains_exactly([0])
	var open_seen := {}
	var none: Array[int] = []
	for i in 40:
		open_seen[BirdPerches.pick(rng, 2, none, PackedVector3Array())] = true
	for k in open_seen.keys():
		assert_int(BirdPerches.ZONES[k]).is_equal(BirdPerches.Zone.WEST)


func test_pick_prefers_a_clear_perch() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	# A threat 3 m west of sidewalk perch 3: from perch 2 only perch 4 of the
	# west zone is LAND_CLEAR from it.
	var near_west := PackedVector3Array([BirdPerches.SPOTS[3] + Vector3(-3, 0, 0)])
	var busy: Array[int] = []
	for i in 20:
		var got := BirdPerches.pick(rng, 2, busy, near_west)
		var gap := BirdPerches.nearest(BirdPerches.SPOTS[got], near_west)
		assert_float(gap).is_greater_equal(BirdPerches.LAND_CLEAR)


func test_pick_takes_farthest_when_none_is_clear() -> void:
	var rng := RandomNumberGenerator.new()
	# From west perch 2 the candidates are 3, 4, 9 (a threat on each) and 10
	# (5 m from the threat on 4, inside LAND_CLEAR): none is clear, so the
	# farthest from a threat, 10, is taken.
	var threats := PackedVector3Array(
		[BirdPerches.SPOTS[3], BirdPerches.SPOTS[4], BirdPerches.SPOTS[9]]
	)
	var busy: Array[int] = []
	assert_int(BirdPerches.pick(rng, 2, busy, threats)).is_equal(10)


func test_pick_returns_none_when_the_zone_is_full() -> void:
	var rng := RandomNumberGenerator.new()
	var busy: Array[int] = [1]
	assert_int(BirdPerches.pick(rng, 0, busy, PackedVector3Array())).is_equal(-1)


func test_offsets_fit_the_patch_and_keep_apart() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for case in [[0, 3], [1, 3], [3, 4], [7, 6]]:
		var spot: int = case[0]
		var offs := BirdPerches.offsets(rng, case[1], spot, 1.5)
		var half := BirdPerches.HALVES[spot]
		assert_int(offs.size()).is_equal(case[1])
		for i in offs.size():
			assert_float(absf(offs[i].x)).is_less_equal(half.x)
			assert_float(absf(offs[i].z)).is_less_equal(half.y)
			for j in range(i + 1, offs.size()):
				var apart := offs[i].distance_to(offs[j])
				assert_float(apart).is_greater_equal(BirdPerches.MIN_SPACING * 1.5)
