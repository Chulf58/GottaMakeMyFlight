extends GdUnitTestSuite
## Every flight a group can make (each pair of perches in one zone, the
## zone's lowest and highest lift, three pairs of patch places) stays clear of
## the shell (porches, facade, canopy and its poles, all shown from far out),
## the curb bays and both car parks. A flying crow at bird scale 1.5 is taken
## as a body BODY_UP above its origin with lines BODY_RADIUS to each side (its
## wings span 1.65 m).

const WORLD := preload("res://tests/ambient/bird_world.gd")
## The paving the birds stand on and the road they fly over.
const GROUND: Array[String] = ["Lot", "Road"]
const BODY_RADIUS := 0.85
const BODY_UP := 0.375
const SAMPLES := 64
## Random flights per perch pair on top of the nine fixed ones (seed 2026).
const SWEEP := 12

var _world: Array[Dictionary] = []


func before() -> void:
	for e in WORLD.build(self):
		if not GROUND.has(e["name"]):
			e["box"] = (e["box"] as AABB).grow(BODY_RADIUS)
			_world.append(e)


## The first mesh a flight's body runs into, as text, or "". Each piece of
## the flight is cast along the body's centre line and four lines beside it,
## against the mesh's triangles (its box is only the broad phase).
func _first_clash(from: Vector3, to: Vector3, lift: float) -> String:
	var sides: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(BODY_RADIUS, 0, 0),
		Vector3(-BODY_RADIUS, 0, 0),
		Vector3(0, 0, BODY_RADIUS),
		Vector3(0, 0, -BODY_RADIUS)
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
	assert_bool(names.has("Porch_7") and names.has("Porch_8") and names.has("Canopy")).is_true()
	var flights := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var clashes: Array[String] = []
	var spots := BirdPerches.SPOTS
	for i in spots.size():
		for j in spots.size():
			if i == j or BirdPerches.ZONES[i] != BirdPerches.ZONES[j]:
				continue
			var lifts: Vector2 = BirdFlock.ZONE_LIFTS[BirdPerches.ZONES[i]]
			var hi := BirdPerches.HALVES[i]
			var hj := BirdPerches.HALVES[j]
			var pairs := [
				[Vector3.ZERO, Vector3.ZERO],
				[Vector3(-hi.x, 0, -hi.y), Vector3(hj.x, 0, hj.y)],
				[Vector3(hi.x, 0, hi.y), Vector3(-hj.x, 0, -hj.y)],
			]
			# The extremes, the middle lift, and a seeded random sweep of places
			# anywhere in both patches at any lift in the zone's range.
			var cases: Array = []
			for lift in [lifts.x, (lifts.x + lifts.y) * 0.5, lifts.y]:
				for pair in pairs:
					cases.append([pair[0], pair[1], lift])
			for k in SWEEP:
				var a := Vector3(rng.randf_range(-hi.x, hi.x), 0, rng.randf_range(-hi.y, hi.y))
				var b := Vector3(rng.randf_range(-hj.x, hj.x), 0, rng.randf_range(-hj.y, hj.y))
				cases.append([a, b, rng.randf_range(lifts.x, lifts.y)])
			for c in cases:
				var clash := _first_clash(spots[i] + c[0], spots[j] + c[1], c[2])
				if clash != "":
					clashes.append("%d->%d lift %.2f: %s" % [i, j, c[2], clash])
				flights += 1
	print("flights checked=", flights, " meshes=", _world.size(), " clashes=", clashes.size())
	for c in clashes:
		print("CLASH ", c)
	assert_int(flights).is_greater(100)
	assert_array(clashes).is_empty()


func test_control_a_drop_through_a_porch_clashes() -> void:
	# A body dropping straight down onto the forecourt under Porch_8 must
	# clash, so the check above can see a porch at all.
	var from := Vector3(-26.0, 6.0, -62.5)
	var to := Vector3(-26.0, 0.5, -62.5)
	var hit := ""
	for e in _world:
		var inv: Transform3D = e["inv"]
		if not (e["mesh"] as TriangleMesh).intersect_segment(inv * from, inv * to).is_empty():
			hit = e["name"]
	print("control clash=", hit)
	assert_str(hit).is_equal("Porch_8")
