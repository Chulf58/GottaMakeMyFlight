class_name JetBridgePose
extends RefCounted
## Where the jet bridge stands at a gate and how its rig poses to dock at a
## plane door (board 4c08b8e5, Runway R11; article airside-props). Pure: it
## reads a stand and a door point and returns transforms and joint values;
## AirsideProps applies them to the jet_bridge.glb nodes. Visual only: the sim
## never reads it, and passengers keep the apron walk.
##
## The rig constants are the ones tools/blender/airside/build_airside_props.py
## builds the bridge with; test_jet_bridge_pose.gd checks them against the rest
## translations in the written jet_bridge.glb, so a re-export that moves a pivot
## fails there. The pose math is the build script's docstring, in the bridge
## root's frame: given the door sill point P and the unit normal n out of the
## fuselage, the cab pivot C = P + n * MOUNT_DOOR_Z, the tunnel yaws to C,
## pitches by th = atan2(C.y - ROT_FLOOR, d) and slides s = hypot(d, dh) -
## CAB_Z, the cab and the drive leg level out, and the drive foot drops to the
## ground. A pose with s outside 0..SLIDE_MAX, |th| over PITCH_MAX_DEG or a
## drive height over DRIVE_H_MAX is out of reach.
##
## Placement (the as-built default from render_airside_plates.py's stand plate):
## the root stands LINK_Z + LINK_WALL_GAP_M north of the stand's wall line,
## turned 180 degrees so its fixed link stub backs onto the terminal, east of
## the port door (the plane's port side is +x at the stand) where its cab pivot
## is DOCK_REACH_M from the column. Every plane parks with its front port door
## on the stand's door (PlaneClasses.stand_offset), so one root serves every
## model; only the sill height differs.
##
## Not guaranteed: the bridge is not checked against a neighbouring gate's
## plane. Models 03 and 04 have sills (0.79 m, 0.63 m) below the rig's reach,
## so while one stands at the gate the bridge takes parked_clear(): fully
## retracted with its tunnel swung along the wall line, clear of the plane
## (ruling plane-04-stops-further-out-with-the-passenger-walk-ending-at, part
## 2, "Swing it clear").

## The rig, in metres, from build_airside_props.py.
const ROT_FLOOR := 2.75
const HINGE_Z := 1.70
const CAB_Z := 6.80
const SLIDE_MAX := 5.0
const DRIVE_H_MAX := 2.90
const DRIVE_Z := 5.20
const TUN_B_SINK := 0.30
const MOUNT_DOOR_Z := 2.10
const PITCH_MAX_DEG := 9.0
const LINK_Z := 2.60
## The gap the link stub's back keeps to the wall line.
const LINK_WALL_GAP_M := 0.3
## Column axis to cab pivot when docked at the stand door: the middle of the
## rig's reach (HINGE_Z + CAB_Z + 1.5), as the stand plate placed it.
const DOCK_REACH_M := 10.0
## Slack on the reach limits, so a pose exactly on a limit counts as in reach.
const LIMIT_SLACK := 1e-4
## The rig's joint nodes, by the name each has in jet_bridge.glb.
const JOINTS: Array[StringName] = [
	&"Tunnel_Yaw",
	&"Tunnel_Pitch",
	&"Tunnel_Slide",
	&"Cab_Level",
	&"Cab_Yaw",
	&"Drive_Level",
	&"Drive_Foot",
	&"Mount_Door",
]


## The bridge root's transform for `stand` (a StandPlacement stand), on the
## ground at `ground_y`.
static func root_for(stand: Dictionary, ground_y := 0.0) -> Transform3D:
	var cab := stand_door(stand) + Vector3(MOUNT_DOOR_Z, 0.0, 0.0)
	var z := float(stand["wall_z"]) - (LINK_Z + LINK_WALL_GAP_M)
	var across := z - cab.z
	var x := cab.x + sqrt(maxf(DOCK_REACH_M * DOCK_REACH_M - across * across, 0.0))
	return Transform3D(Basis(Vector3.UP, PI), Vector3(x, ground_y, z))


## Where every parked plane's front port door skin stands at `stand`, on the
## ground (y 0): the reference model's door under its stand offset, which
## PlaneClasses.stand_offset() lines every model up with. It lies 2.13 m west
## of StandPlacement.door_point(), the passengers' walk end, which stands on
## the apron beside the fuselage.
static func stand_door(stand: Dictionary) -> Vector3:
	var model := PlaneClasses.REFERENCE_MODEL
	var door: Vector3 = PlaneModels.PLANES[model]["doors"][0]
	var at := StandPlacement.stand_point(stand) + PlaneClasses.stand_offset(model) + door
	return Vector3(at.x, 0.0, at.z)


## The pose that puts Mount_Door on `door` (world) with the cab facing back
## along `normal` (world, out of the fuselage), for a bridge whose root is at
## `root`: {"ok", "yaw", "pitch", "slide", "cab_yaw", "drive_h"}. "ok" is
## false when the door is out of the rig's reach.
static func solve(root: Transform3D, door: Vector3, normal: Vector3) -> Dictionary:
	var inv := root.affine_inverse()
	var p := inv * door
	var n := (inv.basis * normal).slide(Vector3.UP).normalized()
	var c := p + n * MOUNT_DOOR_Z
	var yaw := atan2(c.x, c.z)
	var d := Vector2(c.x, c.z).length() - HINGE_Z
	var dh := c.y - ROT_FLOOR
	var th := atan2(dh, d)
	var s := Vector2(d, dh).length() - CAB_Z
	var h := ROT_FLOOR - TUN_B_SINK * cos(th) + (DRIVE_Z + s) * sin(th)
	var ok := (
		s >= -LIMIT_SLACK
		and s <= SLIDE_MAX + LIMIT_SLACK
		and absf(th) <= deg_to_rad(PITCH_MAX_DEG) + LIMIT_SLACK
		and h <= DRIVE_H_MAX + LIMIT_SLACK
	)
	return {
		"ok": ok,
		"yaw": yaw,
		"pitch": th,
		"slide": s,
		"cab_yaw": atan2(-n.x, -n.z) - yaw,
		"drive_h": h,
	}


## The parked pose for a bridge at `root`: aimed at the stand door `door`
## (world), level and fully retracted, so its cab waits about 1.5 m back from
## where it docks.
static func parked(root: Transform3D, door: Vector3, normal: Vector3) -> Dictionary:
	var aim := solve(root, door, normal)
	return {
		"ok": true,
		"yaw": aim["yaw"],
		"pitch": 0.0,
		"slide": 0.0,
		"cab_yaw": aim["cab_yaw"],
		"drive_h": ROT_FLOOR - TUN_B_SINK,
	}


## The parked pose while a plane the rig cannot dock stands at the stand door
## `door` (world), the fuselage facing out along `normal`: level and fully
## retracted like parked(), with the tunnel swung toward the terminal until it
## lies along the wall line, on the door's side of the column, and the cab
## facing the fuselage. In the root's frame the wall line runs along x
## (root_for() turns the root about y only), so the tunnel yaws to +-90
## degrees. The tunnel and cab then lie within 4.4 m of the wall line, ahead
## of the door, and the bellows stop 0.8 m short of the door's x.
static func parked_clear(root: Transform3D, door: Vector3, normal: Vector3) -> Dictionary:
	var pose := parked(root, door, normal)
	var side := 1.0 if (root.affine_inverse() * door).x >= 0.0 else -1.0
	var yaw := side * PI / 2.0
	pose["cab_yaw"] = float(pose["cab_yaw"]) + float(pose["yaw"]) - yaw
	pose["yaw"] = yaw
	return pose


## Sets the joints of `joints` (JOINTS name -> Node3D, from joints_of()) to
## `pose` (solve(), parked() or parked_clear()).
static func apply(joints: Dictionary, pose: Dictionary) -> void:
	var th: float = pose["pitch"]
	(joints[&"Tunnel_Yaw"] as Node3D).rotation = Vector3(0.0, pose["yaw"], 0.0)
	(joints[&"Tunnel_Pitch"] as Node3D).rotation = Vector3(-th, 0.0, 0.0)
	(joints[&"Tunnel_Slide"] as Node3D).position.z = pose["slide"]
	(joints[&"Cab_Level"] as Node3D).rotation = Vector3(th, 0.0, 0.0)
	(joints[&"Drive_Level"] as Node3D).rotation = Vector3(th, 0.0, 0.0)
	(joints[&"Cab_Yaw"] as Node3D).rotation = Vector3(0.0, pose["cab_yaw"], 0.0)
	(joints[&"Drive_Foot"] as Node3D).position.y = -float(pose["drive_h"])


## JOINTS name -> node in an instanced jet_bridge.glb; {} (with an error) when
## one is missing.
static func joints_of(bridge: Node) -> Dictionary:
	var out := {}
	for joint in JOINTS:
		var node := bridge.find_child(String(joint), true, false) as Node3D
		if node == null:
			push_error("JetBridgePose: jet_bridge.glb has no node '%s'" % joint)
			return {}
		out[joint] = node
	return out
