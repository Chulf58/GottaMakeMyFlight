class_name TestAirsidePropsBridgeStairs
extends GdUnitTestSuite
## The jet bridge's stair box at the gate's exit door (board 0adca5c6; rulings
## jet-bridge-starts-at-the-gate-s-exit-door-passengers-step-fr and jet-bridge-
## boarding-design-stair-box-at-the-exit-door-real-w): the stair box and its
## link corridor (StairBox_Mesh) miss every plane model parked at the stand,
## the moving rig (tunnels, drive, cab) never cuts them in any pose the game
## uses, the drive leg stays under the hollow tunnel B's floor, and every walk
## mount stands on a bridge floor with a passenger's
## headroom over it. The plane is drawn as PlaneView draws it at the stand and
## reports through PlaneProps.follow(), as in test_airside_props_bridges.gd.
##
## Controls, each a positive count on the same meshes: a plane moved so its
## door sits on the stair head cuts the stair box; the tunnel yawed toward the
## terminal cuts it; a mount lifted 1 m finds no floor under it.

const Kit := preload("res://tests/airside/airside_props_kit.gd")
const MODELS: Array[String] = [
	"tp_plane_05a", "tp_plane_06a", "tp_plane_07a", "tp_plane_03a", "tp_plane_04a"
]
## The walk mounts in walk order (build_airside_props.py WALK_MOUNTS) that
## stand on a bridge floor; Mount_StairBottom is the exit door's sill, on the
## terminal's floor.
const FLOOR_MOUNTS: Array[String] = [
	"Mount_Vestibule",
	"Mount_StairFoot",
	"Mount_StairTop",
	"Mount_Link",
	"Mount_Rotunda",
	"Mount_TunnelA",
	"Mount_TunnelB",
	"Mount_CabFloor",
]
## How far under a mount the floor may lie, and the headroom a passenger
## (2.01 m tall, ruling airside-props-r11-rulings-board-through-a-docked-jet-
## bridge) needs over it.
## The walk from the exit sill to the plane door, mount by mount.
const WALK: Array[String] = [
	"Mount_StairBottom",
	"Mount_Vestibule",
	"Mount_StairFoot",
	"Mount_StairTop",
	"Mount_Link",
	"Mount_Rotunda",
	"Mount_TunnelA",
	"Mount_TunnelB",
	"Mount_CabFloor",
	"Mount_Door",
]
## Heights over the walk line that a passenger fills: feet, body and head.
const BODY_LIFTS: Array[float] = [0.3, 1.0, 2.0]
const FLOOR_SLACK_M := 0.05
const HEADROOM_M := 2.05

var _airside: Airside
var _stand := StandPlacement.make(1, 20.0, -230.0)


func before() -> void:
	_airside = Kit.airside_from_main()
	add_child(_airside)
	assert_bool(_airside.set_gate_stands({"A": _stand})).is_true()


func after() -> void:
	_airside.free()


func test_the_stair_box_misses_every_plane_at_the_stand() -> void:
	var entry: Dictionary = _airside.props.bridges["A"]
	var box := _stair_box(entry["node"])
	var top := (entry["node"].find_child("Mount_StairTop", true, false) as Node3D).global_position
	for model: String in MODELS:
		var plane := _park(model)
		var holder := plane.get_parent() as Node3D
		var found := Kit.crossings(plane, box)
		var inside := Kit.nested(plane, box)
		var gap := Kit.clearance(plane, box)
		# Control: the same plane with its door on the stair head.
		var door: Vector3 = plane.global_transform * PlaneModels.PLANES[model]["doors"][0]
		holder.position += top - door
		var moved := Kit.crossings(plane, box)
		holder.position -= top - door
		print(
			(
				"%s: stair box %d crossings (%s), %d nested, box gap %.2f m; door on the stair head %d"
				% [
					model,
					found["count"],
					found["meshes"],
					inside["count"],
					gap["gap"],
					moved["count"]
				]
			)
		)
		assert_int(found["count"]).is_equal(0)
		assert_int(inside["count"]).is_equal(0)
		assert_int(moved["count"]).is_greater(0)
		holder.free()


func test_the_moving_rig_never_cuts_the_stair_box() -> void:
	var entry: Dictionary = _airside.props.bridges["A"]
	var bridge: Node3D = entry["node"]
	var box := _stair_box(bridge)
	var rig := bridge.find_child("Tunnel_Yaw", true, false) as Node3D
	for model: String in MODELS:
		var plane := _park(model)
		var found := Kit.crossings(rig, box)
		print(
			(
				"%s: docked %s clear %s yaw %.1f deg slide %.2f: rig into stair box %d crossings (%s)"
				% [
					model,
					entry["docked"],
					entry["clear"],
					rad_to_deg(entry["pose"]["yaw"]),
					entry["pose"]["slide"],
					found["count"],
					found["meshes"],
				]
			)
		)
		assert_bool(entry["docked"] or entry["clear"]).is_true()
		assert_int(found["count"]).is_equal(0)
		_assert_leg_under_floor(model, bridge)
		plane.get_parent().free()
	# Parked with no plane.
	_airside.props.release_plane(1)
	assert_bool(entry["docked"] or entry["clear"]).is_false()
	var parked := Kit.crossings(rig, box)
	# Control: the parked pose yawed toward the terminal.
	var toward: Dictionary = entry["pose"].duplicate()
	toward["yaw"] = PI
	JetBridgePose.apply(entry["joints"], toward)
	var cut := Kit.crossings(rig, box)
	JetBridgePose.apply(entry["joints"], entry["pose"])
	print("parked: %d crossings; yawed toward the terminal: %d" % [parked["count"], cut["count"]])
	assert_int(parked["count"]).is_equal(0)
	assert_int(cut["count"]).is_greater(0)
	_assert_leg_under_floor("parked", bridge)
	# Control: the drive leg at a 0.5 m drive height rises through the floor.
	var low: Dictionary = entry["pose"].duplicate()
	low["drive_h"] = 0.5
	JetBridgePose.apply(entry["joints"], low)
	var through := _leg_over_floor(bridge)
	JetBridgePose.apply(entry["joints"], entry["pose"])
	print("control: at drive height 0.5 m the leg top is %.3f m over tunnel B's floor" % through)
	assert_float(through).is_greater(0.0)


## Tunnel B is hollow, so the drive leg's top must stay under its floor.
func _assert_leg_under_floor(label: String, bridge: Node3D) -> void:
	var over := _leg_over_floor(bridge)
	print("%s: drive leg top %.3f m over tunnel B's floor" % [label, over])
	assert_float(over).is_less(0.0)


## How far the highest point of the drive leg and bogie stands over tunnel B's
## floor top (0.02 m under the floor line, in Tunnel_Slide's frame).
func _leg_over_floor(bridge: Node3D) -> float:
	var slide := bridge.find_child("Tunnel_Slide", true, false) as Node3D
	var foot := bridge.find_child("Drive_Foot_Mesh", true, false) as MeshInstance3D
	var inv := slide.global_transform.affine_inverse()
	var top := -INF
	for v in foot.mesh.get_faces():
		top = maxf(top, (inv * (foot.global_transform * v)).y)
	return top + 0.02


func test_every_walk_mount_stands_on_a_floor_with_headroom() -> void:
	var entry: Dictionary = _airside.props.bridges["A"]
	var bridge: Node3D = entry["node"]
	var tris := Kit.world_tris(bridge)
	for model: String in ["tp_plane_05a", "tp_plane_06a", "tp_plane_07a", ""]:
		var plane: Node3D = null if model == "" else _park(model)
		if plane == null:
			_airside.props.release_plane(1)
		tris = Kit.world_tris(bridge)
		for mount: String in FLOOR_MOUNTS:
			var at := (bridge.find_child(mount, true, false) as Node3D).global_position
			var below: Variant = _first_hit(tris, at + Vector3.UP * 0.5, at + Vector3.DOWN * 0.5)
			var above: Variant = _first_hit(
				tris, at + Vector3.UP * 0.05, at + Vector3.UP * HEADROOM_M
			)
			var floor_gap := INF if below == null else absf((below as Vector3).y - at.y)
			print(
				(
					"%s %s at %s: floor %s (%.3f m off), roof within %.2f m: %s"
					% [
						model if model != "" else "parked",
						mount,
						at,
						below,
						floor_gap,
						HEADROOM_M,
						above
					]
				)
			)
			assert_float(floor_gap).is_less(FLOOR_SLACK_M)
			assert_bool(above == null).is_true()
		if plane != null:
			plane.get_parent().free()
	# Control: a point 1 m over the corridor floor finds no floor within 0.5 m.
	var link := (bridge.find_child("Mount_Link", true, false) as Node3D).global_position
	var lifted := link + Vector3.UP
	var none: Variant = _first_hit(tris, lifted + Vector3.UP * 0.5, lifted + Vector3.DOWN * 0.5)
	print("control: 1 m over Mount_Link the floor ray meets %s" % [none])
	assert_bool(none == null).is_true()


## The straight walk between each pair of consecutive walk mounts, ending at
## Mount_Door, meets none of the bridge's own meshes at a passenger's feet,
## body and head height (Sol review of 8c348ea: a closed rotunda put two walls
## across Mount_Link -> Mount_Rotunda -> Mount_TunnelA), docked at 05, 06 and
## 07 and parked. Controls: the exit sill straight to Mount_Link, skipping the
## stair, runs into the stair box; the rotunda's centre straight out east
## meets the rotunda's wall.
func test_the_walk_between_mounts_runs_clear_through_the_bridge() -> void:
	var entry: Dictionary = _airside.props.bridges["A"]
	var bridge: Node3D = entry["node"]
	for model: String in ["tp_plane_05a", "tp_plane_06a", "tp_plane_07a", ""]:
		var plane: Node3D = null if model == "" else _park(model)
		var tris := Kit.world_tris(bridge)
		var blocked := 0
		for i in range(1, WALK.size()):
			var a := _at(bridge, WALK[i - 1])
			var b := _at(bridge, WALK[i])
			for lift in BODY_LIFTS:
				var hit: Variant = _first_hit(tris, a + Vector3.UP * lift, b + Vector3.UP * lift)
				if hit != null:
					blocked += 1
					print(
						(
							"%s %s -> %s at %.1f m meets the bridge at %s"
							% [model, WALK[i - 1], WALK[i], lift, hit]
						)
					)
		print(
			(
				"%s: %d walk segments, %d blocked"
				% [
					model if model != "" else "parked",
					(WALK.size() - 1) * BODY_LIFTS.size(),
					blocked
				]
			)
		)
		assert_int(blocked).is_equal(0)
		if plane != null:
			plane.get_parent().free()
	var parked := Kit.world_tris(bridge)
	var sill := _at(bridge, "Mount_StairBottom") + Vector3.UP * BODY_LIFTS[0]
	var link := _at(bridge, "Mount_Link") + Vector3.UP * BODY_LIFTS[0]
	var skip: Variant = _first_hit(parked, sill, link)
	var centre := _at(bridge, "Mount_Rotunda") + Vector3.UP * BODY_LIFTS[1]
	var east := centre + Vector3.RIGHT * 3.0
	var wall: Variant = _first_hit(parked, centre, east)
	print("controls: sill to link meets %s; rotunda centre to 3 m east meets %s" % [skip, wall])
	assert_bool(skip != null).is_true()
	assert_bool(wall != null).is_true()


func _at(bridge: Node3D, mount: String) -> Vector3:
	return (bridge.find_child(mount, true, false) as Node3D).global_position


## A parked plane `model` at the stand, reporting to the bridge as in BOARDING.
func _park(model: String) -> Node3D:
	var at := StandPlacement.stand_point(_stand)
	var pose := Transform3D(Basis.IDENTITY, at + Vector3.UP * PlaneView.ground_height_at(at))
	var plane := Kit.posed_model(self, model, pose, at, Vector3.BACK)
	var props := PlaneProps.new()
	plane.get_parent().add_child(props)
	props.follow(true, plane, model, FlightSim.State.BOARDING, "A", _airside, 1)
	return plane


func _stair_box(bridge: Node3D) -> MeshInstance3D:
	var box := bridge.find_child("StairBox_Mesh", true, false) as MeshInstance3D
	assert_object(box).is_not_null()
	return box


## The hit of segment `from`-`to` with a triangle of `tris` (Kit.world_tris())
## nearest `from`, or null.
func _first_hit(tris: Array[Dictionary], from: Vector3, to: Vector3) -> Variant:
	var best: Variant = null
	for tri: Dictionary in tris:
		var p: PackedVector3Array = tri["p"]
		var hit: Variant = Geometry3D.segment_intersects_triangle(from, to, p[0], p[1], p[2])
		if hit != null and (best == null or from.distance_to(hit) < from.distance_to(best)):
			best = hit
	return best
