class_name TestAirsidePropsBridgeClear
extends GdUnitTestSuite
## A jet bridge whose gate holds a plane it cannot dock (models 03 and 04)
## swings clear of it (board 82a139d0; ruling plane-04-stops-further-out-with-
## the-passenger-walk-ending-at, part 2): fully retracted, its tunnel along the
## wall line sloping down JetBridgePose.CLEAR_PITCH_DEG, no mesh edge of the
## plane or the bridge crossing the other (Kit.crossings()), no part of either
## lying wholly inside a mesh of the other
## (Kit.nested()), and no plane vertex inside a bridge mesh's box. The box gap
## the other way is printed only: a fuselage's box is loose, and tunnel A's
## vertices fall inside it.
## The plane is drawn as PlaneView draws it at the stand and reports through
## PlaneProps.follow(), as in test_airside_props_bridges.gd.
##
## Controls, each a positive count on the same plane and bridge meshes: the
## plain parked pose (which the R11 lane measured cutting plane 03), and the
## swung-clear bridge with the plane moved so its door sill sits on the cab.

const Kit := preload("res://tests/airside/airside_props_kit.gd")
const UNREACHED: Array[String] = ["tp_plane_03a", "tp_plane_04a"]

var _airside: Airside
var _stand := StandPlacement.make(1, 20.0, -230.0)


func before() -> void:
	_airside = Kit.airside_from_main()
	add_child(_airside)
	assert_bool(_airside.set_gate_stands({"A": _stand})).is_true()


func after() -> void:
	_airside.free()


func test_an_undockable_plane_gets_the_bridge_swung_clear_and_uncut() -> void:
	var at := StandPlacement.stand_point(_stand)
	var pose := Transform3D(Basis.IDENTITY, at + Vector3.UP * PlaneView.ground_height_at(at))
	var entry: Dictionary = _airside.props.bridges["A"]
	var bridge: Node3D = entry["node"]
	var cab := bridge.find_child("Cab_Yaw", true, false) as Node3D
	var foot := bridge.find_child("Drive_Foot", true, false) as Node3D
	var wall := float(_stand["wall_z"])
	for model: String in UNREACHED:
		var plane := Kit.posed_model(self, model, pose, at, Vector3.BACK)
		var holder := plane.get_parent() as Node3D
		var props := PlaneProps.new()
		holder.add_child(props)
		props.follow(true, plane, model, FlightSim.State.BOARDING, "A", _airside, 1)
		var clear: Dictionary = entry["pose"]
		var found := Kit.crossings(plane, bridge)
		var reach := _aabb_of(bridge)
		var door: Vector3 = plane.global_transform * PlaneModels.PLANES[model]["doors"][0]
		print(
			(
				(
					"%s: clear %s docked %s, yaw %.1f deg, slide %.2f, pitch %.2f deg: %d crossings"
					+ " (%s); bridge x %.2f..%.2f z %.2f..%.2f (wall %.2f), door %s, foot y %.3f"
				)
				% [
					model,
					entry["clear"],
					entry["docked"],
					rad_to_deg(clear["yaw"]),
					clear["slide"],
					rad_to_deg(clear["pitch"]),
					found["count"],
					found["meshes"],
					reach.position.x,
					reach.end.x,
					reach.position.z,
					reach.end.z,
					wall,
					door,
					foot.global_position.y,
				]
			)
		)
		assert_bool(entry["clear"]).is_true()
		assert_bool(entry["docked"]).is_false()
		assert_float(clear["slide"]).is_equal(0.0)
		# Board 0adca5c6 moved the column 1.1 m further out for the link corridor,
		# and a level swung cab then met plane 04's rotor disc (32 crossings), so
		# the swung tunnel slopes down CLEAR_PITCH_DEG instead of lying level.
		assert_float(clear["pitch"]).is_equal_approx(
			-deg_to_rad(JetBridgePose.CLEAR_PITCH_DEG), 1e-6
		)
		assert_float(absf(clear["yaw"])).is_equal_approx(PI / 2.0, 1e-6)
		assert_int(found["count"]).is_equal(0)
		var gap := Kit.clearance(plane, bridge)
		print(
			(
				(
					"%s: box gap %.2f m; plane into bridge %.2f m (%s to %s), bridge"
					+ " into plane %.2f m (%s to %s)"
				)
				% [
					model,
					gap["gap"],
					gap["a_to_b"]["gap"],
					gap["a_to_b"]["from"],
					gap["a_to_b"]["into"],
					gap["b_to_a"]["gap"],
					gap["b_to_a"]["from"],
					gap["b_to_a"]["into"],
				]
			)
		)
		var inside := Kit.nested(plane, bridge)
		print("%s: %d parts nested (%s)" % [model, inside["count"], inside["parts"]])
		assert_int(inside["count"]).is_equal(0)
		assert_float(gap["a_to_b"]["gap"]).is_greater(0.0)
		assert_float(absf(foot.global_position.y - entry["root"].origin.y)).is_less(0.01)
		# Control 1: the plain parked pose on the same meshes.
		JetBridgePose.apply(
			entry["joints"],
			JetBridgePose.parked(entry["root"], JetBridgePose.stand_door(_stand), Vector3.RIGHT)
		)
		var parked := Kit.crossings(plane, bridge)
		var parked_gap := Kit.clearance(plane, bridge)
		var parked_reach := _aabb_of(bridge)
		JetBridgePose.apply(entry["joints"], clear)
		# The swung tunnel comes no nearer the wall than the fixed link stub.
		print("%s: plain parked bridge z ends %.2f" % [model, parked_reach.end.z])
		assert_float(reach.end.z).is_less_equal(parked_reach.end.z + 0.001)
		assert_float(reach.end.z).is_less(wall)
		# Control 2: the swung-clear bridge with the plane's door sill on its cab.
		var shift := cab.global_position - door
		holder.position += shift
		var moved := Kit.crossings(plane, bridge)
		holder.position -= shift
		print(
			(
				(
					"%s controls: plain parked %d crossings (%s), box gap %.2f m; door on"
					+ " the swung cab %d crossings"
				)
				% [model, parked["count"], parked["meshes"], parked_gap["gap"], moved["count"]]
			)
		)
		assert_int(parked["count"]).is_greater(0)
		assert_float(parked_gap["gap"]).is_equal(0.0)
		assert_int(moved["count"]).is_greater(0)
		# Control 3: nested() on these real meshes finds a small box inside the
		# plane's fuselage and inside the bridge's cab.
		for host: Node3D in [plane, bridge]:
			var part_name := "Fuselage" if host == plane else "Cab_Yaw_Mesh"
			var part := host.find_child("*%s*" % part_name, true, false) as MeshInstance3D
			var probe := _box(Vector3.ONE * 0.02, _inner_point(part))
			var held := Kit.nested(host, probe)
			print("%s: a box inside the %s nests as %s" % [model, part_name, held["parts"]])
			assert_bool(held["parts"].has("%s in %s" % [probe.name, part.name])).is_true()
			probe.free()
		props.follow(true, plane, model, FlightSim.State.PUSHBACK, "A", _airside, 1)
		assert_bool(entry["clear"]).is_false()
		assert_float(absf(entry["pose"]["yaw"] - clear["yaw"])).is_greater(0.01)
		holder.free()


## A point inside `part`: halfway between where a ray down near the middle of
## its bounds first enters and leaves it. The ray is set off the middle and
## skewed a little, so it does not run along a face's diagonal.
func _inner_point(part: MeshInstance3D) -> Vector3:
	var box := part.global_transform * part.get_aabb()
	var top := Vector3(box.get_center().x + 0.137, box.end.y + 1.0, box.get_center().z + 0.083)
	var bottom := top + Vector3(0.011, -(box.size.y + 2.0), 0.007)
	var faces := part.mesh.get_faces()
	var hits: Array[Vector3] = []
	for i in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(
			top,
			bottom,
			part.global_transform * faces[i],
			part.global_transform * faces[i + 1],
			part.global_transform * faces[i + 2]
		)
		if hit != null:
			hits.append(hit)
	hits.sort_custom(func(p: Vector3, q: Vector3) -> bool: return p.y > q.y)
	assert_int(hits.size()).is_greater_equal(2)
	return hits[0].lerp(hits[1], 0.5) if hits.size() >= 2 else box.get_center()


## The world bounds of every visible mesh under `node`.
func _aabb_of(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for tri: Dictionary in Kit.world_tris(node):
		box = tri["box"] if first else box.merge(tri["box"])
		first = false
	return box


## Control for the counters themselves: a closed box wholly inside another has
## no edge crossings, nested() finds it whichever box is passed first, and the
## box gap reads 0 whichever of the two is checked into the other. Apart by
## 1 m along x, the inner box's face corners read the true 1 m and the outer
## box's corners read sqrt(5.5) m.
func test_a_part_wholly_inside_another_is_found_both_ways() -> void:
	var outer := _box(Vector3(4.0, 4.0, 4.0), Vector3.ZERO)
	var inner := _box(Vector3(1.0, 1.0, 1.0), Vector3(0.5, 0.2, -0.3))
	var crossed := Kit.crossings(inner, outer)
	var nested := Kit.clearance(outer, inner)
	var nested_back := Kit.clearance(inner, outer)
	var inside := Kit.nested(outer, inner)
	var inside_back := Kit.nested(inner, outer)
	inner.position = Vector3(3.5, 0.0, 0.0)
	var apart := Kit.clearance(outer, inner)
	var inside_apart := Kit.nested(outer, inner)
	print(
		(
			"nested parts: %s and %s; apart: %d"
			% [inside["parts"], inside_back["parts"], inside_apart["count"]]
		)
	)
	assert_int(inside["count"]).is_equal(1)
	assert_int(inside_back["count"]).is_equal(1)
	assert_int(inside_apart["count"]).is_equal(0)
	print(
		(
			(
				"nested: %d crossings; outer into inner %.2f m, inner into outer %.2f m;"
				+ " apart: %.2f m and %.2f m"
			)
			% [
				crossed["count"],
				nested["a_to_b"]["gap"],
				nested["b_to_a"]["gap"],
				apart["a_to_b"]["gap"],
				apart["b_to_a"]["gap"],
			]
		)
	)
	assert_int(crossed["count"]).is_equal(0)
	# The old one-way check: the outer box's vertices miss the inner's bounds.
	assert_float(nested["a_to_b"]["gap"]).is_greater(0.0)
	assert_float(nested["b_to_a"]["gap"]).is_equal(0.0)
	assert_float(nested["gap"]).is_equal(0.0)
	assert_float(nested_back["gap"]).is_equal(0.0)
	assert_float(apart["a_to_b"]["gap"]).is_equal_approx(sqrt(5.5), 1e-4)
	assert_float(apart["b_to_a"]["gap"]).is_equal_approx(1.0, 1e-4)
	assert_float(apart["gap"]).is_equal_approx(1.0, 1e-4)
	outer.free()
	inner.free()


## A closed box mesh of `size` centred at `at`, in the tree.
func _box(size: Vector3, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = at
	add_child(mi)
	return mi
