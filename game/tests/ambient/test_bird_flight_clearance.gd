extends GdUnitTestSuite
## Every flight a group can make (each pair of reachable ground or elevated
## perches via BirdPerches.can_fly, including cross-zone flights, at low/mid/high
## lifts from BirdFlock.lift_bounds) stays clear of the airport site, curb bays,
## car parks, tunnel portals, lampposts, benches and trees.

const WORLD := preload("res://tests/ambient/bird_world.gd")
## Ground & road meshes the birds perch on and fly over.
const GROUND: Array[String] = ["Road", "Ground", "Road_Ext", "Road_Ext_Dashes", "Crosswalk_Stripes"]
const BODY_RADIUS := 0.85
const BODY_UP := 0.375
const SAMPLES := 64
const SWEEP := 6

var _world: Array[Dictionary] = []


func before() -> void:
	for e in WORLD.build(self):
		if not GROUND.has(e["name"]) and not String(e["name"]).begins_with(OwnedPaving.PREFIX):
			e["box"] = (e["box"] as AABB).grow(BODY_RADIUS)
			_world.append(e)


func _first_clash(from: Vector3, to: Vector3, lift: float) -> String:
	var sides: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(BODY_RADIUS, 0, 0),
		Vector3(-BODY_RADIUS, 0, 0),
		Vector3(0, 0, BODY_RADIUS),
		Vector3(0, 0, -BODY_RADIUS),
	]
	var prev := BirdFlock.flight_point(from, to, lift, 0.0) + Vector3.UP * BODY_UP
	for i in range(1, SAMPLES + 1):
		var u := float(i) / SAMPLES
		var body := BirdFlock.flight_point(from, to, lift, u) + Vector3.UP * BODY_UP
		for e in _world:
			var box: AABB = e["box"]
			if not box.has_point(body) and not box.has_point(prev):
				continue
			var inv: Transform3D = e["inv"]
			for s in sides:
				var hit := (e["mesh"] as TriangleMesh).intersect_segment(
					inv * (prev + s), inv * (body + s)
				)
				if not hit.is_empty():
					return "%s near %s (u %.2f)" % [e["name"], body, u]
		prev = body
	return ""


func test_flights_clear_the_world() -> void:
	var names := {}
	for e in _world:
		names[e["name"]] = true
	assert_bool(names.has("TP_Curb_Bay_01A") and names.has("Parking_2A")).is_true()
	var flights := 0
	var cross_zone_pairs := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var clashes: Array[String] = []
	var total := BirdPerches.perch_count()
	for i in total:
		for j in total:
			if not BirdPerches.can_fly(i, j):
				continue
			if BirdPerches.spot_zone(i) != BirdPerches.spot_zone(j):
				cross_zone_pairs += 1
			var pi := BirdPerches.spot_pos(i)
			var pj := BirdPerches.spot_pos(j)
			var lifts := BirdFlock.lift_bounds(pi, pj, BirdPerches.spot_zone(j))
			var hi := BirdPerches.spot_half(i)
			var hj := BirdPerches.spot_half(j)
			var pairs := [
				[Vector3.ZERO, Vector3.ZERO],
				[Vector3(-hi.x, 0, -hi.y), Vector3(hj.x, 0, hj.y)],
				[Vector3(hi.x, 0, hi.y), Vector3(-hj.x, 0, -hj.y)],
			]
			var cases: Array = []
			for lift in [lifts.x, (lifts.x + lifts.y) * 0.5, lifts.y]:
				for pair in pairs:
					cases.append([pair[0], pair[1], lift])
			for k in SWEEP:
				var a := Vector3(rng.randf_range(-hi.x, hi.x), 0, rng.randf_range(-hi.y, hi.y))
				var b := Vector3(rng.randf_range(-hj.x, hj.x), 0, rng.randf_range(-hj.y, hj.y))
				cases.append([a, b, rng.randf_range(lifts.x, lifts.y)])
			for c in cases:
				var clash := _first_clash(pi + c[0], pj + c[1], c[2])
				if clash != "":
					clashes.append(
						(
							"%d(%s)->%d(%s) lift %.2f: %s"
							% [
								i,
								BirdPerches.spot_kind(i),
								j,
								BirdPerches.spot_kind(j),
								c[2],
								clash
							]
						)
					)
				flights += 1
	print(
		"flights checked=",
		flights,
		" cross_zone_pairs=",
		cross_zone_pairs,
		" meshes=",
		_world.size(),
		" clashes=",
		clashes.size()
	)
	for idx in mini(clashes.size(), 30):
		print("CLASH ", clashes[idx])
	assert_int(cross_zone_pairs).is_greater(50)
	assert_int(flights).is_greater(3000)
	assert_array(clashes).is_empty()


func test_control_a_drop_onto_a_curb_bay_clashes() -> void:
	# Target the single starter curb bay's centre divider line (x = -12.0 after 54ae52b0).
	var from := Vector3(-12.0, 6.0, -57.6)
	var to := Vector3(-12.0, 0.05, -57.6)
	var hit := ""
	for e in _world:
		var inv: Transform3D = e["inv"]
		if not (e["mesh"] as TriangleMesh).intersect_segment(inv * from, inv * to).is_empty():
			hit = e["name"]
	print("control clash=", hit)
	assert_str(hit).is_equal("TP_Curb_Bay_01A")
