class_name JetBridgePose
extends RefCounted
## Where the jet bridge stands at a gate and how its rig poses to dock at a
## plane door (board 4c08b8e5, Runway R11; article airside-props). Pure: it
## reads a stand and a door point and returns transforms and joint values;
## AirsideProps applies them to the jet_bridge.glb nodes. Visual only: the sim
## never reads it, and passengers keep the apron walk.
##
## The rig constants are the ones tools/blender/airside/build_airside_props.py
## builds the bridge with; test_airside_props_bridges.gd checks them against
## the rest translations in the written jet_bridge.glb, so a re-export that
## moves a pivot fails there. The pose math is the build script's docstring,
## in the bridge root's frame: given the door sill point P and the unit normal
## n out of the fuselage, the cab pivot C = P + n * MOUNT_DOOR_Z, the tunnel
## yaws to C, pitches by th = atan2(C.y - ROT_FLOOR, d) and slides s =
## hypot(d, dh) - CAB_Z, the cab and the drive leg level out, and the drive
## foot drops to the ground. A pose with s outside 0..SLIDE_MAX, |th| over
## PITCH_MAX_DEG or a drive height over DRIVE_H_MAX is out of reach.
##
## Placement (board 0adca5c6; ruling jet-bridge-starts-at-the-gate-s-exit-
## door-passengers-step-fr): the bridge starts at the gate's own exit door.
## Its stair box stands outside the exit door, and its link corridor runs along
## the wall to the rotunda, so the root (the column) stands ROOT_OUT_M north of
## the stand's wall line and EXIT_X_M east of the exit door, turned 180 degrees
## so the stair box backs onto the terminal; Mount_StairBottom then lies on the
## exit door's sill on the wall line. The column cannot stand at the door
## itself: the plane door is 6.4 m out from the wall and the rig reaches 8.5 to
## 13.5 m (9.0 m at plane 05's sill, whose 1.16 m drop sets a 9 degree pitch),
## so the corridor carries the walk to where the reach starts. Every plane
## parks with its front port door on the stand's door (PlaneClasses.
## stand_offset), so one root serves every model; only the sill height differs.
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
## The root's frame from the stair box (build_airside_props.py ROOT_OUT,
## EXIT_X, LINK_Z): the wall line is z = -ROOT_OUT_M, the exit door's centre
## x = EXIT_X_M, and the link corridor's axis z = -LINK_Z.
const ROOT_OUT_M := 4.0
const EXIT_X_M := 9.7
const LINK_Z := 2.80
## How far the swung-clear tunnel (parked_clear()) slopes down. With the
## column ROOT_OUT_M out, a level cab's roof (5.73 m) reaches plane 04's port
## rotor disc (5.46 m up, from 4.37 m out from the wall at the stand); 6
## degrees lowers it to 5.02 m.
const CLEAR_PITCH_DEG := 6.0
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
## ground at `ground_y`: its stair box at the stand's exit door, whose centre
## is (stand x, wall_z) on the wall line.
static func root_for(stand: Dictionary, ground_y := 0.0) -> Transform3D:
	var at := Vector3(float(stand["x"]) + EXIT_X_M, ground_y, float(stand["wall_z"]) - ROOT_OUT_M)
	return Transform3D(Basis(Vector3.UP, PI), at)


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
## `door` (world), the fuselage facing out along `normal`: fully retracted like
## parked(), with the tunnel swung toward the terminal until it lies along the
## wall line, on the door's side of the column, sloping down CLEAR_PITCH_DEG,
## and the cab level, facing the fuselage. In the root's frame the wall line
## runs along x (root_for() turns the root about y only), so the tunnel yaws
## to +-90 degrees. The tunnel and cab then lie 2.4 to 5.6 m out from the wall
## line, north of the link corridor (which ends 2.1 m out), ahead of the door,
## and the bellows stop 1.2 m short of the door's x.
static func parked_clear(root: Transform3D, door: Vector3, normal: Vector3) -> Dictionary:
	var pose := parked(root, door, normal)
	var side := 1.0 if (root.affine_inverse() * door).x >= 0.0 else -1.0
	var yaw := side * PI / 2.0
	var th := -deg_to_rad(CLEAR_PITCH_DEG)
	pose["cab_yaw"] = float(pose["cab_yaw"]) + float(pose["yaw"]) - yaw
	pose["yaw"] = yaw
	pose["pitch"] = th
	pose["drive_h"] = ROT_FLOOR - TUN_B_SINK * cos(th) + DRIVE_Z * sin(th)
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
