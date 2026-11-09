class_name TestAirsidePropsBridgeStairs
extends GdUnitTestSuite
## The nose-loader bridge's walk and its clearances (board 0adca5c6; rulings
## nose-loader-bridge-design-stair-landing-and-cab-share-one-fl and plane-03-
## boards-on-foot-from-the-apron-plane-04-docks-the-no), for every docking
## model (04 to 07) and for plane 03, which boards on foot:
## - the docked plane cuts no bridge mesh but the bellows, which meet its skin;
## - every walk mount stands on a bridge floor with a passenger's headroom;
## - the straight walk between consecutive mounts, into and out of the cab,
##   meets no bridge mesh at feet, body and head height;
## - the walk turns once, 90 degrees, in the cab;
## - plane 03: the bridge stays parked, clear of its wing and gear, and the
##   apron walk from the apron door to its door passes under nothing of the
##   bridge lower than APRON_HEADROOM_M;
## - plane 04: its wing stands at least WING_CLEAR_M over the docked cab;
## - the pushback tug and the plane, from pushback start through the turn,
##   meet nothing of the parked bridge.
## Each check has a positive control on the same meshes.

const Kit := preload("res://tests/airside/airside_props_kit.gd")
const DOCKING: Array[String] = ["tp_plane_04a", "tp_plane_05a", "tp_plane_06a", "tp_plane_07a"]
const ON_FOOT := "tp_plane_03a"
const FLOOR_MOUNTS: Array[StringName] = [&"Mount_StairFoot", &"Mount_StairTop", &"Mount_CabFloor"]
## Heights over the walk line a passenger fills: feet, body and head.
const BODY_LIFTS: Array[float] = [0.3, 1.0, 2.0]
## How far under a mount its floor may lie, and the headroom over it.
const FLOOR_SLACK_M := 0.05
const HEADROOM_M := 2.05
const APRON_HEADROOM_M := 2.1
const WING_CLEAR_M := 0.15
## How far the parked cab must stand over plane 03's wing.
const PARK_CLEAR_M := 0.15
const PUSHBACK: Array[float] = [0.0, 0.1, 0.2, 0.35, 0.5, 0.65, 0.8, 1.0]

var _airside: Airside
var _stand := StandPlacement.make(1, 20.0, -230.0)


func before() -> void:
	_airside = Kit.airside_from_main()
	add_child(_airside)
	assert_bool(_airside.set_gate_stands({"A": _stand})).is_true()


func after() -> void:
	_airside.free()


func test_a_docked_plane_cuts_nothing_of_the_bridge_but_the_bellows() -> void:
	var bridge := _bridge()
	var body := _without_bellows(bridge)
	for model: String in DOCKING:
		var plane := _park(model)
		var found := Kit.crossings(plane, body)
		var inside := Kit.nested(plane, body)
		print(
			(
				"%s: %d crossings (%s), %d nested (%s)"
				% [model, found["count"], found["meshes"], inside["count"], inside["parts"]]
			)
		)
		assert_int(found["count"]).is_equal(0)
		assert_int(inside["count"]).is_equal(0)
		# Control: the plane moved 1 m toward the bridge cuts the cab.
		var holder := plane.get_parent() as Node3D
		holder.position.x += 1.0
		var moved := Kit.crossings(plane, body)
		holder.position.x -= 1.0
		print("control: %s 1 m nearer the bridge, %d crossings" % [model, moved["count"]])
		assert_int(moved["count"]).is_greater(0)
		holder.free()
	_restore(body)


func test_every_walk_mount_stands_on_a_floor_with_headroom() -> void:
	var bridge := _bridge()
	for model: String in DOCKING:
		var plane := _park(model)
		var tris := Kit.world_tris(bridge)
		for mount in FLOOR_MOUNTS:
			var at := _at(bridge, mount)
			var below: Variant = _first_hit(tris, at + Vector3.UP * 0.5, at + Vector3.DOWN * 0.5)
			var above: Variant = _first_hit(
				tris, at + Vector3.UP * 0.05, at + Vector3.UP * HEADROOM_M
			)
			var gap := INF if below == null else absf((below as Vector3).y - at.y)
			print(
				(
					"%s %s at %s: floor %.3f m off, roof within %.2f m: %s"
					% [model, mount, at, gap, HEADROOM_M, above]
				)
			)
			assert_float(gap).is_less(FLOOR_SLACK_M)
			assert_bool(above == null).is_true()
		plane.get_parent().free()
	# Control: 1 m over the stair top there is no floor within 0.5 m.
	var tris := Kit.world_tris(bridge)
	var lifted := _at(bridge, &"Mount_StairTop") + Vector3.UP
	var none: Variant = _first_hit(tris, lifted + Vector3.UP * 0.5, lifted + Vector3.DOWN * 0.5)
	print("control: 1 m over Mount_StairTop the floor ray meets %s" % [none])
	assert_bool(none == null).is_true()


func test_the_walk_runs_clear_and_turns_once_in_the_cab() -> void:
	var bridge := _bridge()
	for model: String in DOCKING:
		var plane := _park(model)
		var tris := Kit.world_tris(bridge)
		var want := JetBridgePose.pose_for(_stand, model, true, _ground())
		var walk: PackedVector3Array = want["walk"]
		var blocked := 0
		var length := 0.0
		for i in range(1, walk.size()):
			length += walk[i - 1].distance_to(walk[i])
			for lift in BODY_LIFTS:
				var up := Vector3.UP * lift
				var hit: Variant = _first_hit(tris, walk[i - 1] + up, walk[i] + up)
				if hit != null:
					blocked += 1
					print("%s segment %d at %.1f m meets the bridge at %s" % [model, i, lift, hit])
		var turns := _turns(walk)
		print(
			(
				"%s: %d segments, %d blocked; walk %.2f m; turns %s deg"
				% [model, (walk.size() - 1) * BODY_LIFTS.size(), blocked, length, turns]
			)
		)
		assert_int(blocked).is_equal(0)
		# One turn, 90 degrees, at the cab floor; the walk runs straight before it.
		assert_float(turns[0]).is_less(0.5)
		assert_float(turns[1]).is_less(0.5)
		assert_float(turns[2]).is_equal_approx(90.0, 0.5)
		plane.get_parent().free()
	# Controls: the exit sill straight to the cab floor, skipping the stair,
	# meets the stair; the cab floor straight through the cab's far side meets
	# its wall.
	var tris := Kit.world_tris(bridge)
	var lift := Vector3.UP * BODY_LIFTS[0]
	var skip: Variant = _first_hit(
		tris, _at(bridge, &"Mount_ExitSill") + lift, _at(bridge, &"Mount_CabFloor") + lift
	)
	var cab := _at(bridge, &"Mount_CabFloor") + Vector3.UP * BODY_LIFTS[1]
	var through: Variant = _first_hit(tris, cab, cab + Vector3.RIGHT * 3.0)
	print("controls: sill to cab floor meets %s; cab floor 3 m east meets %s" % [skip, through])
	assert_bool(skip != null).is_true()
	assert_bool(through != null).is_true()


## Plane 03 reports undocked, the bridge parked over its wing and gear.
func test_plane_03_leaves_the_bridge_parked_clear_of_it() -> void:
	var entry: Dictionary = _airside.props.bridges["A"]
	var bridge: Node3D = entry["node"]
	var plane := _park(ON_FOOT)
	var found := Kit.crossings(plane, bridge)
	var inside := Kit.nested(plane, bridge)
	var gap := _gap_over(bridge.find_child("Cab_Yaw_Mesh", true, false) as Node3D, plane)
	print(
		(
			"03: docked %s model %s, %d crossings, %d nested, cab underside %.3f m over the plane"
			% [entry["docked"], entry["model"], found["count"], inside["count"], gap]
		)
	)
	assert_bool(entry["docked"]).is_false()
	assert_str(entry["model"]).is_equal(ON_FOOT)
	assert_int(found["count"]).is_equal(0)
	assert_int(inside["count"]).is_equal(0)
	assert_float(gap).is_greater_equal(PARK_CLEAR_M)
	# Control: the parked bridge with its cab at 05's sill cuts the 03's wing.
	var low := JetBridgePose.parked()
	low["height"] = 1.58
	JetBridgePose.apply(entry["joints"], low)
	var cut := Kit.crossings(plane, bridge)
	JetBridgePose.apply(entry["joints"], entry["pose"])
	print("control: cab at 1.58 m over the 03, %d crossings (%s)" % [cut["count"], cut["meshes"]])
	assert_int(cut["count"]).is_greater(0)
	plane.get_parent().free()


## The 03's apron walk passes under nothing of the bridge lower than
## APRON_HEADROOM_M.
func test_plane_03s_apron_walk_has_headroom_under_the_bridge() -> void:
	var bridge := _bridge()
	var plane := _park(ON_FOOT)
	var want := JetBridgePose.pose_for(_stand, ON_FOOT, false, _ground())
	var walk: PackedVector3Array = want["apron_walk"]
	var tris := Kit.world_tris(bridge)
	var low := _lowest_over(tris, walk)
	print("03 apron walk %s: lowest bridge part over it %.3f m" % [walk, low])
	assert_int(walk.size()).is_equal(3)
	assert_float(low).is_greater_equal(APRON_HEADROOM_M)
	# Control: the walk moved 1.5 m east, under the cab at 1.58 m, meets it.
	var entry: Dictionary = _airside.props.bridges["A"]
	var lowered := JetBridgePose.parked()
	lowered["height"] = 1.58
	JetBridgePose.apply(entry["joints"], lowered)
	var shifted := PackedVector3Array()
	for p in walk:
		shifted.append(p + Vector3.RIGHT * 1.5)
	var under := _lowest_over(Kit.world_tris(bridge), shifted)
	JetBridgePose.apply(entry["joints"], entry["pose"])
	print("control: walk under the lowered cab, lowest bridge part %.3f m" % under)
	assert_float(under).is_less(APRON_HEADROOM_M)
	plane.get_parent().free()


## Plane 04's wing stands at least WING_CLEAR_M over the docked cab (the
## bellows, which meet the skin, are checked by the crossing test).
func test_plane_04s_wing_clears_the_docked_cab() -> void:
	var entry: Dictionary = _airside.props.bridges["A"]
	var plane := _park("tp_plane_04a")
	var cab: Array[Node3D] = [entry["node"].find_child("Cab_Yaw_Mesh", true, false) as Node3D]
	var gap := _gap_under(cab, plane)
	print("04: docked %s, wing %.3f m over the cab" % [entry["docked"], gap])
	assert_bool(entry["docked"]).is_true()
	assert_float(gap).is_greater_equal(WING_CLEAR_M)
	# Control: the cab 0.3 m higher leaves less than WING_CLEAR_M.
	var high: Dictionary = entry["pose"].duplicate()
	high["height"] = float(high["height"]) + 0.3
	JetBridgePose.apply(entry["joints"], high)
	var less := _gap_under(cab, plane)
	JetBridgePose.apply(entry["joints"], entry["pose"])
	print("control: cab 0.3 m higher, wing %.3f m over it" % less)
	assert_float(less).is_less(WING_CLEAR_M)
	plane.get_parent().free()


## Through pushback, from the stand through its turn, neither the tug nor the
## plane meets the parked bridge.
func test_the_pushback_tug_and_plane_clear_the_parked_bridge() -> void:
	var bridge := _bridge()
	var path := _airside.phase_path(FlightSim.State.PUSHBACK, "A")
	var entry_dir := FlightPose.exit_dir(_airside.phase_path(FlightSim.State.TAXI_IN, "A"))
	for model: String in DOCKING + [ON_FOOT]:
		var worst := 0
		for t in PUSHBACK:
			var pose := FlightPose.pose(FlightSim.State.PUSHBACK, t, path, entry_dir)
			var plane := Kit.posed_model(self, model, pose, path[0], entry_dir)
			var props := PlaneProps.new()
			plane.get_parent().add_child(props)
			props.follow(true, plane, model, FlightSim.State.PUSHBACK, "A", _airside, 1)
			var tug := Kit.crossings(props.tug, bridge)
			var body := Kit.crossings(plane, bridge)
			worst = maxi(worst, tug["count"] + body["count"])
			if tug["count"] + body["count"] > 0:
				print(
					(
						"%s t %.2f: tug %d, plane %d crossings"
						% [model, t, tug["count"], body["count"]]
					)
				)
			if model == ON_FOOT and t == 0.0:
				# Control: the tug moved onto the vestibule meets it.
				var start := props.tug.global_position
				props.tug.global_position = _at(bridge, &"Mount_StairFoot")
				var met := Kit.crossings(props.tug, bridge)
				props.tug.global_position = start
				print("control: tug on the stair foot, %d crossings" % met["count"])
				assert_int(met["count"]).is_greater(0)
			plane.get_parent().free()
		print("%s pushback: worst %d crossings over %d samples" % [model, worst, PUSHBACK.size()])
		assert_int(worst).is_equal(0)


## Positive controls for Kit.nested(), which the crossing tests above assert
## to be 0: a small box placed inside a real fuselage and one inside the real
## cab are found nested; a closed box wholly inside another is found whichever
## is passed first and not once moved apart, with no edge crossings either way.
func test_nested_finds_a_part_wholly_inside_a_real_mesh() -> void:
	var plane := _park("tp_plane_05a")
	var bridge := _bridge()
	for host: Node3D in [plane, bridge]:
		var part_name := "Fuselage" if host == plane else "Cab_Yaw_Mesh"
		var part := host.find_child("*%s*" % part_name, true, false) as MeshInstance3D
		var probe := _test_box(Vector3.ONE * 0.02, _inner_point(part))
		var held := Kit.nested(host, probe)
		print("a box inside %s nests as %s" % [part.name, held["parts"]])
		assert_bool(held["parts"].has("%s in %s" % [probe.name, part.name])).is_true()
		probe.free()
	plane.get_parent().free()
	var outer := _test_box(Vector3(4.0, 4.0, 4.0), Vector3.ZERO)
	var inner := _test_box(Vector3(1.0, 1.0, 1.0), Vector3(0.5, 0.2, -0.3))
	var crossed := Kit.crossings(inner, outer)
	var inside := Kit.nested(outer, inner)
	var inside_back := Kit.nested(inner, outer)
	inner.position = Vector3(3.5, 0.0, 0.0)
	var apart := Kit.nested(outer, inner)
	print(
		(
			"boxes: %d crossings, nested %s and %s; apart %d"
			% [crossed["count"], inside["parts"], inside_back["parts"], apart["count"]]
		)
	)
	assert_int(crossed["count"]).is_equal(0)
	assert_int(inside["count"]).is_equal(1)
	assert_int(inside_back["count"]).is_equal(1)
	assert_int(apart["count"]).is_equal(0)
	outer.free()
	inner.free()


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


## A closed box mesh of `size` centred at `at`, in the tree.
func _test_box(size: Vector3, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = at
	add_child(mi)
	return mi


func _bridge() -> Node3D:
	return _airside.props.bridges["A"]["node"]


func _ground() -> float:
	return float(_airside.props.bridges["A"]["root"].origin.y)


func _at(bridge: Node3D, mount: StringName) -> Vector3:
	return (bridge.find_child(String(mount), true, false) as Node3D).global_position


## Plane `model` parked at the stand, reporting to gate A as in BOARDING.
func _park(model: String) -> Node3D:
	var at := StandPlacement.stand_point(_stand)
	var pose := Transform3D(Basis.IDENTITY, at + Vector3.UP * PlaneView.ground_height_at(at))
	var plane := Kit.posed_model(self, model, pose, at, Vector3.BACK)
	var props := PlaneProps.new()
	plane.get_parent().add_child(props)
	props.follow(true, plane, model, FlightSim.State.BOARDING, "A", _airside, 1)
	return plane


## Hides the bellows (which meet the plane's skin by design) and returns the
## bridge; _restore() shows them again.
func _without_bellows(bridge: Node3D) -> Node3D:
	(bridge.find_child("Bellows_Extend_Mesh", true, false) as Node3D).visible = false
	return bridge


func _restore(bridge: Node3D) -> void:
	(bridge.find_child("Bellows_Extend_Mesh", true, false) as Node3D).visible = true


## The least height from the top of `parts` up to `plane` over the parts'
## footprint (vertical rays on a 0.1 m grid), INF when nothing is over them.
func _gap_under(parts: Array[Node3D], plane: Node3D) -> float:
	var tris := Kit.world_tris(plane)
	var best := INF
	for part in parts:
		var box := _box(part)
		for x in _steps(box.position.x, box.end.x):
			for z in _steps(box.position.z, box.end.z):
				var from := Vector3(x, box.end.y, z)
				var hit: Variant = _first_hit(tris, from, from + Vector3.UP * 4.0)
				if hit != null:
					best = minf(best, (hit as Vector3).y - box.end.y)
	return best


## The least height from `plane`'s top up to the underside of `part` over
## the part's footprint, INF when the plane is not under it.
func _gap_over(part: Node3D, plane: Node3D) -> float:
	var tris := Kit.world_tris(plane)
	var box := _box(part)
	var best := INF
	for x in _steps(box.position.x, box.end.x):
		for z in _steps(box.position.z, box.end.z):
			var from := Vector3(x, box.position.y, z)
			var hit: Variant = _first_hit(tris, from, from + Vector3.DOWN * 4.0)
			if hit != null:
				best = minf(best, box.position.y - (hit as Vector3).y)
	return best


## The lowest bridge point over the polyline `walk` (vertical rays every
## 0.1 m, from FLOOR_SLACK_M over the walk, above the floors it walks on, up
## 6 m), measured from the walk; INF when nothing is over it.
func _lowest_over(tris: Array[Dictionary], walk: PackedVector3Array) -> float:
	var low := INF
	for i in range(1, walk.size()):
		var n := ceili(walk[i - 1].distance_to(walk[i]) / 0.1)
		for k in n + 1:
			var p := walk[i - 1].lerp(walk[i], float(k) / n)
			var from := p + Vector3.UP * FLOOR_SLACK_M
			var hit: Variant = _first_hit(tris, from, p + Vector3.UP * 6.0)
			if hit != null:
				low = minf(low, (hit as Vector3).y - p.y)
	return low


func _box(part: Node3D) -> AABB:
	var mi := part as MeshInstance3D
	return mi.global_transform * mi.get_aabb()


func _steps(lo: float, hi: float) -> Array[float]:
	var out: Array[float] = []
	var n := ceili((hi - lo) / 0.1)
	for k in n + 1:
		out.append(lo + (hi - lo) * k / n)
	return out


## The turn at each inner point of `walk`, in degrees, on the ground plane.
func _turns(walk: PackedVector3Array) -> Array[float]:
	var out: Array[float] = []
	for i in range(1, walk.size() - 1):
		var a := walk[i] - walk[i - 1]
		var b := walk[i + 1] - walk[i]
		out.append(absf(rad_to_deg(Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z)))))
	return out


## The hit of segment `from`-`to` with a triangle of `tris` (Kit.world_tris())
## nearest `from`, or null.
func _first_hit(tris: Array[Dictionary], from: Vector3, to: Vector3) -> Variant:
	var best: Variant = null
	var span := AABB(from, Vector3.ZERO).expand(to).grow(0.01)
	for tri: Dictionary in tris:
		if not (tri["box"] as AABB).intersects(span):
			continue
		var p: PackedVector3Array = tri["p"]
		var hit: Variant = Geometry3D.segment_intersects_triangle(from, to, p[0], p[1], p[2])
		if hit != null and (best == null or from.distance_to(hit) < from.distance_to(best)):
			best = hit
	return best
