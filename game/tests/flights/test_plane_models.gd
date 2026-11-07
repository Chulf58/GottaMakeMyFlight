class_name TestPlaneModels
extends GdUnitTestSuite
## The imported plane, runway and jet bridge models match PlaneModels: every
## mesh surface carries a toon material, the true vertex bounds are within
## 0.1 m of the table, and the plane sizes are within 0.1 m of the pack census
## (finding toon-planes-pack-census-runway-pieces-plane-sizes-and-missing-
## airside-props).

const TOLERANCE_M := 0.1
const TOON_MATERIALS := [
	"res://assets/materials/tp_atlas_toon.tres",
	"res://assets/materials/tp_atlas_simple_toon.tres",
	"res://assets/materials/tp_glass.tres",
	"res://assets/materials/tp_lights.tres",
]
## Census length and span per plane, as the finding states them (one decimal).
const CENSUS := {
	"tp_plane_03a": Vector2(10.7, 14.1),
	"tp_plane_04a": Vector2(19.3, 24.5),
	"tp_plane_05a": Vector2(29.2, 28.3),
	"tp_plane_06a": Vector2(42.0, 30.9),
	"tp_plane_07a": Vector2(48.7, 43.6),
}

## Model name -> {"surfaces", "bound", "unbound": [names], "aabb"}.
var _measured := {}


func before() -> void:
	var rows := PlaneModels.PLANES.duplicate()
	rows.merge(PlaneModels.PIECES)
	for model: String in rows:
		var packed := load(rows[model]["path"]) as PackedScene
		if packed == null:
			_measured[model] = null
			continue
		var scene := packed.instantiate() as Node3D
		_measured[model] = _measure(scene)
		scene.free()


## Counts the surfaces and their materials, and takes the vertex bounds about
## the scene root.
func _measure(scene: Node3D) -> Dictionary:
	var out := {"surfaces": 0, "bound": 0, "unbound": [], "aabb": AABB()}
	var first := true
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var xf := mi.transform
		var up := mi.get_parent() as Node3D
		while up != null and up != scene:
			xf = up.transform * xf
			up = up.get_parent() as Node3D
		xf = scene.transform * xf
		for i in mi.mesh.get_surface_count():
			out["surfaces"] += 1
			var mat := mi.get_active_material(i)
			if mat != null and mat.resource_path in TOON_MATERIALS:
				out["bound"] += 1
			else:
				out["unbound"].append("%s/%d" % [mi.name, i])
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p := xf * v
				if first:
					out["aabb"] = AABB(p, Vector3.ZERO)
					first = false
				else:
					out["aabb"] = (out["aabb"] as AABB).expand(p)
	return out


func _all_models() -> Array:
	return PlaneModels.PLANES.keys() + PlaneModels.PIECES.keys()


func _row(model: String) -> Dictionary:
	return PlaneModels.PLANES.get(model, PlaneModels.PIECES.get(model, {}))


func test_every_model_loads_and_every_surface_has_a_toon_material() -> void:
	for model: String in _all_models():
		var m = _measured[model]
		assert_that(m).override_failure_message("%s did not load" % model).is_not_null()
		if m == null:
			continue
		print("MATERIALS %s surfaces=%d bound=%d" % [model, m["surfaces"], m["bound"]])
		var none := "%s has no surface" % model
		assert_int(m["surfaces"]).override_failure_message(none).is_greater(0)
		(
			assert_array(m["unbound"])
			. override_failure_message(
				"%s surfaces without a toon material: %s" % [model, m["unbound"]]
			)
			. is_empty()
		)


func test_vertex_bounds_match_the_table() -> void:
	for model: String in _all_models():
		var m = _measured[model]
		if m == null:
			fail("%s did not load" % model)
			continue
		var got: AABB = m["aabb"]
		var want: AABB = _row(model)["aabb"]
		print("BOUNDS %s measured %s table %s" % [model, got, want])
		(
			assert_vector(got.position)
			. override_failure_message(
				"%s bounds start %s, table %s" % [model, got.position, want.position]
			)
			. is_equal_approx(want.position, Vector3.ONE * TOLERANCE_M)
		)
		(
			assert_vector(got.end)
			. override_failure_message("%s bounds end %s, table %s" % [model, got.end, want.end])
			. is_equal_approx(want.end, Vector3.ONE * TOLERANCE_M)
		)


func test_plane_sizes_match_the_census() -> void:
	for model: String in CENSUS:
		var row: Dictionary = PlaneModels.PLANES[model]
		var census: Vector2 = CENSUS[model]
		var span := 2.0 * float(row["half_span"])
		print("CENSUS %s length %.2f span %.2f, census %s" % [model, row["length"], span, census])
		assert_float(row["length"]).is_equal_approx(census.x, TOLERANCE_M)
		assert_float(2.0 * float(row["half_span"])).is_equal_approx(census.y, TOLERANCE_M)
	assert_int(CENSUS.size()).is_equal(PlaneModels.PLANES.size())


## The derived fields agree with the bounds they come from.
func test_plane_fields_follow_from_the_bounds() -> void:
	for model: String in PlaneModels.PLANES:
		var row: Dictionary = PlaneModels.PLANES[model]
		var box: AABB = row["aabb"]
		var off: Vector3 = row["model_offset"]
		assert_float(row["length"]).is_equal_approx(box.size.z, 0.01)
		assert_float(row["half_span"]).is_equal_approx(box.size.x / 2.0, 0.01)
		assert_float(row["nose"]).is_equal_approx(box.end.z, 0.01)
		assert_float(row["tail"]).is_equal_approx(-box.position.z, 0.01)
		# The offset puts the box middle on the pose point.
		var middle := box.get_center() + off
		assert_float(middle.x).is_equal_approx(0.0, 0.01)
		assert_float(middle.z).is_equal_approx(0.0, 0.01)
		# Each model's own swing radius: its half box diagonal, rounded up to 0.1 m.
		var reach := Vector2(box.size.z / 2.0, box.size.x / 2.0).length()
		var swing := float(row["own_swing_radius"])
		(
			assert_bool(swing >= reach and swing < reach + 0.1)
			. override_failure_message("%s swing %.1f, half diagonal %.3f" % [model, swing, reach])
			. is_true()
		)


## The ruled class radii (decision runway-and-taxi-technical-design-movement-
## plan-analytic-bookings-planned-pauses; finding toon-planes-pack-census-
## runway-pieces-plane-sizes-and-missing-airside-props) are the largest own
## swing radius among each class's members.
func test_class_radius_is_the_largest_member_radius() -> void:
	var classes := [
		[["tp_plane_03a"], 8.9],
		[["tp_plane_04a", "tp_plane_05a"], 20.4],
		[["tp_plane_06a", "tp_plane_07a"], 32.7],
	]
	for entry: Array in classes:
		var largest := 0.0
		for model: String in entry[0]:
			largest = maxf(largest, float(PlaneModels.PLANES[model]["own_swing_radius"]))
		print("CLASS %s radius %.1f, ruled %.1f" % [entry[0], largest, entry[1]])
		assert_float(largest).is_equal_approx(entry[1], 0.001)


## Each plane has a door, and every door point is inside the box, near the
## centreline and above the ground.
func test_door_points_sit_inside_the_plane() -> void:
	for model: String in PlaneModels.PLANES:
		var row: Dictionary = PlaneModels.PLANES[model]
		var box: AABB = row["aabb"]
		var doors: Array = row["doors"]
		assert_int(doors.size()).override_failure_message("%s has no door" % model).is_greater(0)
		for door: Vector3 in doors:
			(
				assert_bool(box.grow(0.01).has_point(door))
				. override_failure_message("%s door %s outside %s" % [model, door, box])
				. is_true()
			)
			assert_float(absf(door.x)).is_less(2.5)
			assert_float(door.y).is_greater(0.5)


## Doors come grouped by station (within 0.1 m along the plane), stations front
## to back. Every station starts with a port door (+x); a paired station has
## one starboard door after it, mirrored across the centreline at the same sill.
func test_doors_run_by_station_port_first() -> void:
	var paired := 0
	for model: String in PlaneModels.PLANES:
		var stations: Array[Array] = []
		for door: Vector3 in PlaneModels.PLANES[model]["doors"]:
			if not stations.is_empty() and absf((stations[-1][0] as Vector3).z - door.z) < 0.1:
				stations[-1].append(door)
			else:
				stations.append([door])
		var last_z := INF
		for station in stations:
			var port: Vector3 = station[0]
			var msg := "%s station %s" % [model, station]
			assert_float(port.z).override_failure_message(msg).is_less(last_z - 0.1)
			last_z = port.z
			assert_float(port.x).override_failure_message(msg).is_greater(0.0)
			assert_int(station.size()).override_failure_message(msg).is_less_equal(2)
			if station.size() == 2:
				paired += 1
				var star: Vector3 = station[1]
				assert_float(star.x).override_failure_message(msg).is_less(0.0)
				assert_float(port.x + star.x).override_failure_message(msg).is_equal_approx(
					0.0, 0.05
				)
				assert_float(star.y).override_failure_message(msg).is_equal_approx(port.y, 0.05)
	# 03A one, 06A three, 07A four paired stations.
	assert_int(paired).is_equal(8)
