extends GdUnitTestSuite
## BirdPerches: every patch measured against the outdoor surfaces (shell,
## curb bays, both car parks built), the scatter decision, perch choice within
## a zone, the perches there with and without car parks, and patch offsets.

const WORLD := preload("res://tests/ambient/bird_world.gd")
const SURFACE_TOLERANCE := 0.01

var _world: Array[Dictionary] = []


func before() -> void:
	_world = WORLD.build(self)


func test_tables_line_up() -> void:
	var n := BirdPerches.SPOTS.size()
	assert_int(BirdPerches.HALVES.size()).is_equal(n)
	assert_int(BirdPerches.ZONES.size()).is_equal(n)
	assert_int(BirdPerches.LOTS.size()).is_equal(n)


## Every patch point stands on one flat surface at the perch height, and over
## it is open sky or, for the zone under the canopy, the roof group (the
## canopy) higher than an arch there reaches. No perch is under a porch, a
## deck slab or indoors.
func test_every_patch_is_flat_under_open_sky_or_the_canopy() -> void:
	assert_int(_world.size()).is_greater(0)
	var checked := 0
	var problems: Array[String] = []
	for i in BirdPerches.SPOTS.size():
		var spot := BirdPerches.SPOTS[i]
		var half := BirdPerches.HALVES[i]
		var arch_top := spot.y + 0.75 * BirdFlock.ZONE_LIFTS[BirdPerches.ZONES[i]].y + 0.75
		for fx in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			for fz in [-1.0, 0.0, 1.0]:
				var p := spot + Vector3(fx * half.x, 0.0, fz * half.y)
				var down := WORLD.first_hit(
					_world, p + Vector3.UP * 30.0, p + Vector3.DOWN * 1.0, ShellView.ROOF_NODES
				)
				checked += 1
				if down.is_empty() or absf(float(down["y"]) - spot.y) > SURFACE_TOLERANCE:
					problems.append("perch %d at %s: surface %s" % [i, p, down])
					continue
				var up := WORLD.first_hit(
					_world, Vector3(p.x, down["y"] + 0.05, p.z), p + Vector3.UP * 40.0
				)
				if up.is_empty():
					continue
				var canopy_ok: bool = (
					BirdPerches.ZONES[i] == BirdPerches.Zone.UNDER_CANOPY
					and ShellView.ROOF_NODES.has(up["name"])
					and float(up["y"]) > arch_top
				)
				if not canopy_ok:
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


func test_interior_control_reads_as_indoors() -> void:
	var p := Vector3(-20.0, 0.0, -80.0)
	var down := WORLD.first_hit(
		_world, p + Vector3.UP * 3.0, p + Vector3.DOWN, ShellView.ROOF_NODES
	)
	var up := WORLD.first_hit(_world, Vector3(p.x, down["y"] + 0.05, p.z), p + Vector3.UP * 40.0)
	print("interior control floor=", down, " cover=", up)
	assert_dict(up).is_not_empty()


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


func test_car_at_curb_berth_scatters() -> void:
	# The forecourt back row, the farther of the two rows from the berths.
	var spot: Vector3 = BirdPerches.SPOTS[0]
	var car := Vector3(spot.x, 0.1, -57.2)
	print("berth distance=", BirdPerches.nearest(spot, PackedVector3Array([car])))
	assert_bool(BirdPerches.scatter_due(spot, PackedVector3Array([car]))).is_true()


func test_car_in_near_lane_does_not_scatter_the_forecourt() -> void:
	var spot: Vector3 = BirdPerches.SPOTS[1]
	var car := Vector3(spot.x, 0.1, -55.0)
	print("lane distance=", BirdPerches.nearest(spot, PackedVector3Array([car])))
	assert_bool(BirdPerches.scatter_due(spot, PackedVector3Array([car]))).is_false()
	assert_bool(BirdPerches.scatter_due(spot, PackedVector3Array())).is_false()


func test_scatter_distance_is_flat() -> void:
	var spot: Vector3 = BirdPerches.SPOTS[0]
	var above := spot + Vector3(6.0, 5.0, 0.0)
	assert_bool(BirdPerches.scatter_due(spot, PackedVector3Array([above]))).is_true()


func test_pick_stays_in_zone_and_skips_busy() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var busy: Array[int] = [0, 2, 3]
	var seen := {}
	for i in 40:
		seen[BirdPerches.pick(rng, 1, busy, PackedVector3Array())] = true
	assert_array(seen.keys()).contains_exactly([4])
	var open_seen := {}
	var none: Array[int] = []
	for i in 40:
		open_seen[BirdPerches.pick(rng, 5, none, PackedVector3Array())] = true
	for k in open_seen.keys():
		assert_int(BirdPerches.ZONES[k]).is_equal(BirdPerches.Zone.WEST)


func test_pick_prefers_a_clear_perch() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var near_west := PackedVector3Array([BirdPerches.SPOTS[0] + Vector3(-3, 0, 0)])
	var busy: Array[int] = []
	for i in 20:
		var got := BirdPerches.pick(rng, 2, busy, near_west)
		var gap := BirdPerches.nearest(BirdPerches.SPOTS[got], near_west)
		assert_float(gap).is_greater_equal(BirdPerches.LAND_CLEAR)


func test_pick_takes_farthest_when_none_is_clear() -> void:
	var rng := RandomNumberGenerator.new()
	# Threats on spots 0 and 1, both 1.3 m apart; from 3 with 4 busy, spot 2
	# is the only candidate left in the zone.
	var threats := PackedVector3Array([BirdPerches.SPOTS[0], BirdPerches.SPOTS[1]])
	var busy: Array[int] = [4]
	assert_int(BirdPerches.pick(rng, 3, busy, threats)).is_equal(2)


func test_pick_returns_none_when_the_zone_is_full() -> void:
	var rng := RandomNumberGenerator.new()
	var busy: Array[int] = [1, 2, 3, 4]
	assert_int(BirdPerches.pick(rng, 0, busy, PackedVector3Array())).is_equal(-1)


func test_offsets_fit_the_patch_and_keep_apart() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for case in [[0, 3], [4, 3], [6, 4], [10, 6]]:
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
