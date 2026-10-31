class_name TestLandsideMultiStoreyClearance
extends GdUnitTestSuite
## The multi-storey's slots, gate and ground-floor routes against the converted
## asset (board e3aa4367; decision multi-storey-car-park-ground-floor-cut-a-
## level-entrance-thro). Every slot holds the largest car on its deck top clear
## of every wall and of the floor paint (decision multi-storey-car-park-slots-
## fit-the-painted-stalls: one car inside each painted stall of the upper
## decks, none on the ground floor's hatched zone); the gate and the way out
## stand in line with the entrance opening, so no car crosses the apron at a
## slant; a ground-floor car's way in
## and out never climbs or drops more than a few cm, through the gap cut in the
## ramp kerb, and its sides clear every wall on the way. Past the slab's front
## edge the route is the apron ramp: it stays between road and slab, in the same
## steps.

const STARTER := preload("res://landside/starter_landside.tres")
const MULTI_SCENE := preload("res://assets/landside/tc_parking_2a.glb")
## Half the largest car plus 5 cm: tp_suv_01b is 5.20 m long with its nose
## 2.69 m ahead of its origin, tp_van_01a is 2.47 m wide.
const HALF_LENGTH := 2.75
const HALF_WIDTH := 1.3
## Heights over the floor of the lines along a car's sides: low enough to meet
## a kerb (0.2 m and more), high enough to meet a wall.
const SIDE_HEIGHTS: Array[float] = [0.15, 1.0]
const STEP := 0.25
## A ground-floor route climbs or drops at most MAX_STEP between two samples
## STEP apart, and its floor stays within RISE of its lowest point. What it
## may meet: the ramp foot, 6 cm over the floor by the gap, and floor paint up
## to 3 cm thick. The kerb it used to cross stands 0.2 m over the ramp.
const MAX_STEP := 0.04
const RISE := 0.1
## The road top the lanes are authored on; the apron ramp runs from it up to the
## slab.
const ROAD_Y := 0.1
## The ground-floor front wall's middle line, in the asset's own frame (the
## wall runs z -23.2 to -21.9, 1.2 m over the floor at y 0.3).
const FRONT_WALL_Z := -22.55
## Slots by deck (decision multi-storey-car-park-slots-fit-the-painted-stalls):
## 9 on the ground floor between the hatched zone and the back wall, 11 on
## each upper deck, one in each painted stall.
const SLOTS := 31
const GROUND_SLOTS := 9
## Floor paint is a level face this far over its deck top (measured: 0.7 to
## 3.3 cm).
const PAINT_MIN := 0.004
const PAINT_MAX := 0.045

var _spot: LandsideLotSpot
var _paths: LandsidePaths
## World-space triangles [a, b, c]: within 25 degrees of level, and the rest
## (walls, kerb sides), the latter with their bounds for a quick reject.
var _level := []
var _upright := []
var _upright_box: Array[AABB] = []
## Deck top height -> the paint triangles on it, each a PackedVector2Array in
## (x, z).
var _paint := {}


func before() -> void:
	_spot = STARTER.lots[1]
	_paths = LandsidePaths.new(STARTER)
	var asset: Node3D = MULTI_SCENE.instantiate()
	add_child(asset)
	var at := Transform3D(Basis(), _spot.centre)
	for mi: MeshInstance3D in asset.find_children("*", "MeshInstance3D", true, false):
		var to_world := at * mi.global_transform
		var f := mi.mesh.get_faces()
		for i in range(0, f.size(), 3):
			var a: Vector3 = to_world * f[i]
			var b: Vector3 = to_world * f[i + 1]
			var c: Vector3 = to_world * f[i + 2]
			var n := (b - a).cross(c - a)
			if n.length() < 1e-6:
				continue
			if absf(n.normalized().y) > 0.9:
				_level.append([a, b, c])
			else:
				_upright.append([a, b, c])
				_upright_box.append(AABB(a, Vector3.ZERO).expand(b).expand(c))
	for slot in _spot.slots:
		_paint[slot.y] = []
	for tri: Array in _level:
		for deck: float in _paint:
			var low := minf(minf(tri[0].y, tri[1].y), tri[2].y) - deck
			var high := maxf(maxf(tri[0].y, tri[1].y), tri[2].y) - deck
			if low > PAINT_MIN and high < PAINT_MAX:
				var flat := PackedVector2Array()
				for corner: Vector3 in tri:
					flat.append(Vector2(corner.x, corner.z))
				_paint[deck].append(flat)
	asset.free()


func test_every_slot_holds_a_car_on_its_deck_top_clear_of_every_wall() -> void:
	var samples := 0
	var lines := 0
	for slot in _spot.slots:
		var nose := LandsidePlaces.parked_heading(_spot, slot)
		var side := Vector3(-nose.z, 0.0, nose.x)
		# The car's footprint stands on the deck top with headroom everywhere.
		for u in range(-roundi(HALF_LENGTH / STEP), roundi(HALF_LENGTH / STEP) + 1):
			for v in range(-roundi(HALF_WIDTH / STEP), roundi(HALF_WIDTH / STEP) + 1):
				var at: Vector3 = slot + nose * (u * STEP) + side * (v * STEP)
				var problem := TestLandsideGeometry._footing(_level, at)
				(
					assert_str(problem)
					. override_failure_message("slot %s, car at %s: %s" % [slot, at, problem])
					. is_empty()
				)
				samples += 1
		# No wall or kerb side crosses the car's outline or its diagonals.
		var corners: Array[Vector3] = []
		for c in [[1, 1], [1, -1], [-1, -1], [-1, 1]]:
			corners.append(slot + nose * (HALF_LENGTH * c[0]) + side * (HALF_WIDTH * c[1]))
		for h in SIDE_HEIGHTS:
			var up := Vector3(0.0, h, 0.0)
			for k in 4:
				lines += _assert_clear(corners[k] + up, corners[(k + 1) % 4] + up, "slot %s" % slot)
			lines += _assert_clear(corners[0] + up, corners[2] + up, "slot %s" % slot)
			lines += _assert_clear(corners[1] + up, corners[3] + up, "slot %s" % slot)
	print(
		(
			"multi-storey slots %d, footprint samples %d, outline lines %d"
			% [_spot.slots.size(), samples, lines]
		)
	)
	assert_int(_spot.slots.size()).is_equal(SLOTS)
	assert_int(samples).is_equal(SLOTS * 23 * 11)
	assert_int(lines).is_equal(SLOTS * 2 * 6)


func test_no_parked_car_stands_on_a_painted_stall_line_or_the_hatched_zone() -> void:
	var per_deck := {}
	for slot in _spot.slots:
		per_deck[slot.y] = int(per_deck.get(slot.y, 0)) + 1
		var on := _paint_under(slot, Vector3.ZERO)
		(
			assert_int(on)
			. override_failure_message("slot %s stands on %d paint faces" % [slot, on])
			. is_equal(0)
		)
		# A control: the same car 2 m along the row stands on a painted line
		# (upper decks), so the check meets the paint it is looking for.
		if slot.y > 1.0:
			assert_int(_paint_under(slot, Vector3(0.0, 0.0, 2.0))).is_greater(0)
	# A control on the ground floor: a car in the middle of the hatched zone.
	var hatch := Vector3(_spot.slots[0].x, _spot.slots[0].y, -26.5)
	assert_int(_paint_under(hatch, Vector3.ZERO)).is_greater(0)
	var counts := []
	for deck: float in _paint:
		counts.append("%.2f: %d paint faces" % [deck, _paint[deck].size()])
	print("multi-storey slots by deck %s; %s" % [per_deck, counts])
	assert_int(per_deck.get(_spot.aisle_front.y, 0)).is_equal(GROUND_SLOTS)
	assert_int(per_deck.size()).is_equal(3)
	for deck: float in per_deck:
		if deck > 1.0:
			assert_int(per_deck[deck]).is_equal((SLOTS - GROUND_SLOTS) / 2)


func test_the_gate_and_the_way_out_stand_in_line_with_the_entrance_opening() -> void:
	var gate := _spot.access[_spot.access.size() - 1]
	var out := _spot.exit[0]
	# Straight in and straight out, along z, with no slant across the apron.
	for point in [_spot.access[_spot.access.size() - 2], _spot.entrance[0], _spot.entrance[1]]:
		assert_float(point.x).is_equal(gate.x)
	for point in [_spot.way_out[0], _spot.way_out[1], _spot.exit[1]]:
		assert_float(point.x).is_equal(out.x)
	# Keep right: going in (+z) the in lane is on the -x side of the out lane.
	assert_float(gate.x).is_less(out.x)
	# The opening in the front wall, measured on the asset: the run of x with no
	# wall top (over 1 m above the floor, under the first deck) around the gate.
	var z := _spot.centre.z + FRONT_WALL_Z
	var lo := gate.x
	var hi := gate.x
	assert_bool(_wall_at(gate.x, z)).is_false()
	while lo > _spot.centre.x - 12.0 and not _wall_at(lo - 0.05, z):
		lo -= 0.05
	while hi < _spot.centre.x + 12.0 and not _wall_at(hi + 0.05, z):
		hi += 0.05
	print(
		(
			"multi-storey opening x %.2f..%.2f, in lane x %.2f, out lane x %.2f"
			% [lo, hi, gate.x, out.x]
		)
	)
	# The wall stands either side (a control: the scan met it).
	assert_bool(_wall_at(lo - 0.1, z)).is_true()
	assert_bool(_wall_at(hi + 0.1, z)).is_true()
	assert_float(gate.x - HALF_WIDTH).is_greater_equal(lo + 0.1)
	assert_float(out.x + HALF_WIDTH).is_less_equal(hi - 0.1)
	# Both lanes cross the wall line on the far side of the gate: the gate is in
	# front of the opening and the car meets the wall line straight on.
	assert_float(_spot.entrance[0].z).is_greater(gate.z)
	assert_float(_spot.entrance[1].z).is_greater(z)
	assert_float(_spot.way_out[1].z).is_less(z)


func test_a_ground_floor_car_drives_in_and_out_level_through_the_kerb_gap() -> void:
	var routes := 0
	var samples := 0
	var through_gap := 0
	var worst_step := 0.0
	var worst_at := Vector3.ZERO
	var worst_rise := 0.0
	var lines := 0
	var apron := 0
	var edge_z := _spot.centre.z - _spot.footprint.y / 2.0
	for slot in _spot.slots.size():
		if LandsidePaths.deck_of(_spot, _spot.slots[slot]) != 0:
			continue
		var path: PackedVector3Array = _paths.slot_path[1][slot]
		var route := path.slice(path.find(_spot.entrance[0]), path.size())
		assert_int(route.size()).is_greater(4)
		routes += 1
		var lowest := INF
		var highest := -INF
		var before_y := NAN
		for i in range(1, route.size()):
			var a: Vector3 = route[i - 1]
			var b: Vector3 = route[i]
			var parts := maxi(ceili(a.distance_to(b) / STEP), 1)
			for part in parts + 1:
				var at := a.lerp(b, float(part) / parts)
				# Past the slab's front edge the lane is the apron ramp itself (the
				# asset has no floor there): its height must stay between the road
				# and the slab, and its steps count like the floor's.
				var on_apron := at.z < edge_z
				var y := at.y if on_apron else _floor_near(at)
				(
					assert_bool(is_nan(y))
					. override_failure_message("slot %d: no floor under %s" % [slot, at])
					. is_false()
				)
				if on_apron:
					apron += 1
					assert_float(y).is_greater_equal(ROAD_Y - 0.0001)
					assert_float(y).is_less_equal(_spot.entrance[0].y + 0.0001)
				if not is_nan(before_y) and absf(y - before_y) > worst_step:
					worst_step = absf(y - before_y)
					worst_at = at
				before_y = y
				if not on_apron:
					lowest = minf(lowest, y)
					highest = maxf(highest, y)
				samples += 1
				# The ramp kerb runs x 1.0 to 1.7 beside the stalls.
				if at.x > 1.05 and at.x < 1.65 and at.z < -24.0:
					through_gap += 1
			# The car's sides clear every wall and kerb on the way.
			var flat := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
			var side := Vector3(-flat.z, 0.0, flat.x) * HALF_WIDTH
			for h in SIDE_HEIGHTS:
				var up := Vector3(0.0, h, 0.0)
				for s in [side, -side]:
					lines += _assert_clear(a + s + up, b + s + up, "slot %d route" % slot)
		worst_rise = maxf(worst_rise, highest - lowest)
	var report := (
		"ground-floor routes %d, samples %d (apron %d), in the kerb gap %d, "
		% [routes, samples, apron, through_gap]
	)
	report += (
		"worst step %.3f m at %s, rise %.3f m, side lines %d"
		% [worst_step, worst_at, worst_rise, lines]
	)
	print(report)
	assert_int(routes).is_equal(GROUND_SLOTS)
	# Every route passes the gap both ways (a control: the check met the kerb line).
	assert_int(through_gap).is_greater_equal(routes * 2)
	# And down the apron ramp (a control: the route does leave the asset's floor).
	assert_int(apron).is_greater_equal(routes * 8)
	assert_float(worst_step).is_less_equal(MAX_STEP)
	assert_float(worst_rise).is_less_equal(RISE)
	assert_int(lines).is_greater(routes * 4 * 4)


## How many paint triangles on `slot`'s deck the outline of a car parked
## there, moved by `offset`, overlaps.
func _paint_under(slot: Vector3, offset: Vector3) -> int:
	var nose := LandsidePlaces.parked_heading(_spot, slot)
	var side := Vector3(-nose.z, 0.0, nose.x)
	var at := slot + offset
	var outline := PackedVector2Array()
	for c in [[1, 1], [1, -1], [-1, -1], [-1, 1]]:
		var corner: Vector3 = at + nose * (HALF_LENGTH * c[0]) + side * (HALF_WIDTH * c[1])
		outline.append(Vector2(corner.x, corner.z))
	var hits := 0
	for tri: PackedVector2Array in _paint[slot.y]:
		hits += int(not Geometry2D.intersect_polygons(outline, tri).is_empty())
	return hits


## 1 after checking that no upright face crosses the line from `a` to `b`.
func _assert_clear(a: Vector3, b: Vector3, what: String) -> int:
	var box := AABB(a, Vector3.ZERO).expand(b).grow(0.01)
	for i in _upright.size():
		if not box.intersects(_upright_box[i]):
			continue
		var tri: Array = _upright[i]
		var hit: Variant = Geometry3D.segment_intersects_triangle(a, b, tri[0], tri[1], tri[2])
		(
			assert_bool(hit == null)
			. override_failure_message("%s: %s to %s meets a wall at %s" % [what, a, b, hit])
			. is_true()
		)
		if hit != null:
			return 1
	return 1


## The height of the top level face over `at`'s ground point within 0.45 m of
## its height (the surface a wheel stands on; the ground-floor quad runs on
## under the ramp), or NAN.
func _floor_near(at: Vector3) -> float:
	var best := NAN
	for face in _level:
		var y := TestLandsideGeometry._height_on(face, at)
		if is_nan(y) or absf(y - at.y) > 0.45:
			continue
		if is_nan(best) or y > best:
			best = y
	return best


## Whether a wall top stands at (x, z): a level face over 1 m above the ground
## floor and under the first deck.
func _wall_at(x: float, z: float) -> bool:
	var at := Vector3(x, 0.0, z)
	for face in _level:
		var y := TestLandsideGeometry._height_on(face, at)
		if not is_nan(y) and y > 1.3 and y < 4.0:
			return true
	return false
