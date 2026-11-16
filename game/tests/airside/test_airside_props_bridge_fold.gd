class_name TestAirsidePropsBridgeFold
extends GdUnitTestSuite
## The folded jet bridge (board b564cda3; ruling small-planes-the-jet-bridge-
## folds-back-against-the-terminal): with a plane that does not dock (03) at
## the gate, or none, the walkway, stair, landing, cab and pedestal are drawn
## retracted (hidden) and a glazed end wall (Fold_Cap) closes the vestibule's
## far end, so only the vestibule with its exit and apron doors stands on the
## wall. A docking model (04 to 07) unfolds it and docks as before. The joint
## pose stays parked() while folded, so everything that reads the pose reads
## what it read before. Each check has a positive control on the same meshes.

const Kit := preload("res://tests/airside/airside_props_kit.gd")
const BRIDGE_SCENE := preload("res://assets/airside/props/jet_bridge.glb")
const ON_FOOT := "tp_plane_03a"
const DOCKING: Array[String] = ["tp_plane_04a", "tp_plane_05a", "tp_plane_06a", "tp_plane_07a"]
## Heights over the walk line a passenger fills: feet, body and head.
const BODY_LIFTS: Array[float] = [0.3, 1.0, 2.0]
## The grid step of the vertical rays over the bridge's footprint.
const GRID_M := 0.25
## How far past the vestibule's far end the folded bridge may reach (the roof
## overhang is 0.04 m).
const REACH_SLACK_M := 0.05
## Kit.world_tris() grows each triangle's box by 0.001 m.
const BOX_SLACK_M := 0.002

var _airside: Airside
var _stand := StandPlacement.make(1, 20.0, -230.0)


func before() -> void:
	_airside = Kit.airside_from_main()
	add_child(_airside)
	assert_bool(_airside.set_gate_stands({"A": _stand})).is_true()


func after() -> void:
	_airside.free()


## The written glb carries Fold_Cap, a joint like the others; apply() shows it
## only folded, and hides the walkway (Walk_Slide and all under it) then. The
## cap fills the vestibule's far-end opening the walkway leaves.
func test_the_glb_carries_a_fold_cap_shown_only_when_folded() -> void:
	var holder: Node3D = auto_free(Node3D.new())
	add_child(holder)
	var bridge: Node3D = BRIDGE_SCENE.instantiate()
	holder.add_child(bridge)
	var joints := JetBridgePose.joints_of(bridge)
	assert_bool(joints.has(&"Fold_Cap")).is_true()
	var slide := joints[&"Walk_Slide"] as Node3D
	var cap := joints[&"Fold_Cap"] as Node3D
	JetBridgePose.apply(joints, JetBridgePose.parked())
	var open_reach := _reach(bridge)
	assert_bool(slide.is_visible_in_tree()).is_true()
	assert_bool(cap.is_visible_in_tree()).is_false()
	JetBridgePose.apply(joints, JetBridgePose.parked(), true)
	var box := _box_of(cap)
	var folded_reach := _reach(bridge)
	print(
		(
			"cap box %s; reach out from the wall: open %.3f m, folded %.3f m (vestibule end %.2f)"
			% [box, open_reach, folded_reach, JetBridgePose.VEST_END]
		)
	)
	assert_bool(slide.is_visible_in_tree()).is_false()
	assert_bool(cap.is_visible_in_tree()).is_true()
	# The cap spans the walkway's opening in the vestibule's far wall.
	assert_float(box.position.x).is_less_equal(-JetBridgePose.BOX_HALF)
	assert_float(box.end.x).is_greater_equal(JetBridgePose.BOX_HALF)
	assert_float(box.position.y).is_less_equal(BOX_SLACK_M)
	assert_float(box.end.y).is_greater_equal(JetBridgePose.BOX_TOP)
	assert_float(box.position.z).is_greater_equal(
		JetBridgePose.VEST_END - JetBridgePose.SKIN_T - BOX_SLACK_M
	)
	assert_float(box.end.z).is_less_equal(JetBridgePose.VEST_END + BOX_SLACK_M)
	# Folded, nothing reaches past the vestibule; open, the cab and bellows do.
	assert_float(folded_reach).is_less_equal(JetBridgePose.VEST_END + REACH_SLACK_M)
	assert_float(open_reach).is_greater(JetBridgePose.CAB_Z)


## A report of plane 03 folds the bridge with its joints parked; a docking
## model unfolds and docks it; with no report the gate folds. pose_for()
## names the same fold.
func test_a_plane_that_does_not_dock_folds_the_bridge() -> void:
	var props := _airside.props
	var entry: Dictionary = props.bridges["A"]
	var joints: Dictionary = entry["joints"]
	var ground := float(entry["root"].origin.y)
	var steps: Array = [[ON_FOOT, true, false]]
	for model: String in DOCKING:
		steps.append([model, false, true])
	steps.append(["", true, false])
	for step: Array in steps:
		var model: String = step[0]
		if model == "":
			props.release_plane(11)
		else:
			props.dock_plane(11, "A", model)
		var want := JetBridgePose.pose_for(_stand, model, model != "", ground)
		var walkway := (joints[&"Walk_Slide"] as Node3D).is_visible_in_tree()
		var cap := (joints[&"Fold_Cap"] as Node3D).is_visible_in_tree()
		print(
			(
				"%s: folded %s docked %s; walkway shown %s, cap shown %s; pose_for folded %s"
				% [
					model if model != "" else "none",
					entry["folded"],
					entry["docked"],
					walkway,
					cap,
					want["folded"]
				]
			)
		)
		assert_bool(entry["folded"]).is_equal(step[1])
		assert_bool(entry["docked"]).is_equal(step[2])
		assert_bool(want["folded"]).is_equal(step[1])
		assert_bool(walkway).is_equal(not step[1])
		assert_bool(cap).is_equal(step[1])
		if step[1]:
			assert_dict(entry["pose"]).is_equal(JetBridgePose.parked())


## With plane 03 at the gate the folded bridge stands over nothing of it and
## meets nothing of it, and the walk out of the apron door meets nothing of
## the bridge at feet, body or head height. Control: the bridge drawn parked
## and open, as before the fold, stands over the 03's wing.
func test_the_folded_bridge_stands_clear_of_plane_03_and_its_walk() -> void:
	var entry: Dictionary = _airside.props.bridges["A"]
	var bridge: Node3D = entry["node"]
	var plane := _park(ON_FOOT)
	var under := _plane_hits_under(bridge, plane)
	var found := Kit.crossings(plane, bridge)
	var inside := Kit.nested(plane, bridge)
	var walk: PackedVector3Array = (
		JetBridgePose.pose_for(_stand, ON_FOOT, false, _ground())["apron_walk"]
	)
	var blocked := _blocked(Kit.world_tris(bridge), walk)
	print(
		(
			(
				"03 folded %s: %d of %d rays over the bridge meet the 03; %d crossings, %d nested;"
				+ " apron walk %s, %d blocked segments"
			)
			% [entry["folded"], under.x, under.y, found["count"], inside["count"], walk, blocked]
		)
	)
	assert_bool(entry["folded"]).is_true()
	assert_int(under.y).is_greater(50)
	assert_int(under.x).is_equal(0)
	assert_int(found["count"]).is_equal(0)
	assert_int(inside["count"]).is_equal(0)
	assert_int(walk.size()).is_equal(3)
	assert_int(blocked).is_equal(0)
	# Control: open and parked, as drawn before the fold.
	JetBridgePose.apply(entry["joints"], JetBridgePose.parked())
	var open := _plane_hits_under(bridge, plane)
	# Control: the walk turned 1 m further out along the vestibule's west
	# wall, past the apron door, meets the wall.
	var shut := PackedVector3Array(walk)
	shut[1] += (entry["root"] as Transform3D).basis.z * 1.0
	JetBridgePose.apply(entry["joints"], entry["pose"], entry["folded"])
	var walled := _blocked(Kit.world_tris(bridge), shut)
	print(
		(
			"controls: open bridge, %d of %d rays meet the 03; walk past the apron door, %d blocked"
			% [open.x, open.y, walled]
		)
	)
	assert_int(open.x).is_greater(0)
	assert_int(walled).is_greater(0)
	plane.get_parent().free()


## The hand-over at one gate: a 03 boards (folded), pushes back (still folded,
## so nothing appears over it), a 04 arrives and boards (docked, open), pushes
## back (folded again). At every step the bridge as drawn meets nothing of the
## plane then at the stand but the docked bellows, which meet the 04's skin.
func test_the_03_to_04_hand_over_never_draws_the_bridge_into_a_plane() -> void:
	var entry: Dictionary = _airside.props.bridges["A"]
	var bridge: Node3D = entry["node"]
	var bellows := bridge.find_child("Bellows_Extend_Mesh", true, false) as Node3D
	var steps := [
		[ON_FOOT, FlightSim.State.BOARDING, true, false],
		[ON_FOOT, FlightSim.State.PUSHBACK, true, false],
		["tp_plane_04a", FlightSim.State.BOARDING, false, true],
		["tp_plane_04a", FlightSim.State.PUSHBACK, true, false],
	]
	var plane: Node3D = null
	for step: Array in steps:
		if plane == null or plane.get_meta(&"model") != step[0]:
			if plane != null:
				plane.get_parent().free()
			plane = _park(step[0])
			plane.set_meta(&"model", step[0])
		var props := plane.get_parent().get_child(1) as PlaneProps
		props.follow(true, plane, step[0], step[1], "A", _airside, 1)
		bellows.visible = false
		var found := Kit.crossings(plane, bridge)
		var inside := Kit.nested(plane, bridge)
		var under := _plane_hits_under(bridge, plane) if step[2] else Vector2i.ZERO
		bellows.visible = true
		print(
			(
				"%s %s: folded %s docked %s; %d crossings, %d nested (bellows aside); %d rays over it"
				% [
					step[0],
					FlightSim.State.keys()[step[1]],
					entry["folded"],
					entry["docked"],
					found["count"],
					inside["count"],
					under.x
				]
			)
		)
		assert_bool(entry["folded"]).is_equal(step[2])
		assert_bool(entry["docked"]).is_equal(step[3])
		assert_int(found["count"]).is_equal(0)
		assert_int(inside["count"]).is_equal(0)
		assert_int(under.x).is_equal(0)
	plane.get_parent().free()
	assert_bool(entry["folded"]).is_true()


## Vertical rays on a GRID_M grid over the bridge's visible footprint, from its
## top down to the ground, against plane `plane`: (hits, rays).
func _plane_hits_under(bridge: Node3D, plane: Node3D) -> Vector2i:
	var tris := Kit.world_tris(plane)
	var box := _box_of(bridge)
	var count := Vector2i.ZERO
	var x := box.position.x
	while x <= box.end.x:
		var z := box.position.z
		while z <= box.end.z:
			var from := Vector3(x, box.end.y, z)
			count.y += 1
			if _first_hit(tris, from, Vector3(x, box.position.y - 1.0, z)) != null:
				count.x += 1
			z += GRID_M
		x += GRID_M
	return count


## Segments of `walk` (each at every BODY_LIFTS height) that meet a triangle of
## `tris`.
func _blocked(tris: Array[Dictionary], walk: PackedVector3Array) -> int:
	var blocked := 0
	for i in range(1, walk.size()):
		for lift in BODY_LIFTS:
			var up := Vector3.UP * lift
			if _first_hit(tris, walk[i - 1] + up, walk[i] + up) != null:
				blocked += 1
	return blocked


func _first_hit(tris: Array[Dictionary], from: Vector3, to: Vector3) -> Variant:
	var seg := AABB(from, Vector3.ZERO).expand(to).grow(0.01)
	var best: Variant = null
	for t: Dictionary in tris:
		if not (t["box"] as AABB).intersects(seg):
			continue
		var p: PackedVector3Array = t["p"]
		var hit: Variant = Geometry3D.segment_intersects_triangle(from, to, p[0], p[1], p[2])
		if hit != null and (best == null or from.distance_to(hit) < from.distance_to(best)):
			best = hit
	return best


## How far out from the wall (the root's +z) any visible part of `bridge`
## reaches.
func _reach(bridge: Node3D) -> float:
	var inv := bridge.global_transform.affine_inverse()
	var far := -INF
	for t: Dictionary in Kit.world_tris(bridge):
		for p: Vector3 in t["p"]:
			far = maxf(far, (inv * p).z)
	return far


## The world bounds of `node`'s visible meshes (the bridge's own frame when it
## stands at the identity).
func _box_of(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for t: Dictionary in Kit.world_tris(node):
		var b: AABB = t["box"]
		box = b if first else box.merge(b)
		first = false
	return box


func _ground() -> float:
	return float(_airside.props.bridges["A"]["root"].origin.y)


## Plane `model` parked at the stand, reporting to gate A as in BOARDING; its
## PlaneProps is the holder's second child.
func _park(model: String) -> Node3D:
	var at := StandPlacement.stand_point(_stand)
	var pose := Transform3D(Basis.IDENTITY, at + Vector3.UP * PlaneView.ground_height_at(at))
	var plane := Kit.posed_model(self, model, pose, at, Vector3.BACK)
	var props := PlaneProps.new()
	plane.get_parent().add_child(props)
	props.follow(true, plane, model, FlightSim.State.BOARDING, "A", _airside, 1)
	return plane
