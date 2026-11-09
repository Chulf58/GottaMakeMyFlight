class_name JetBridgePose
extends RefCounted
## The nose-loader jet bridge at a gate (board 0adca5c6; article airside-
## props; rulings jet-bridges-are-nose-loader-pedestal-bridges-an-enclosed-wal,
## nose-loader-bridge-design-stair-landing-and-cab-share-one-fl and plane-03-
## boards-on-foot-from-the-apron-plane-04-docks-the-no). Pure: from a stand,
## a plane model and whether it is docked it returns the rig's pose and every
## walk mount in world space; AirsideProps applies the pose to jet_bridge.glb,
## and the passenger sim can read the same walk later.
##
## The bridge's root is the gate's exit door sill on the stand's wall line,
## (stand x, wall_z), turned 180 degrees so its +z points out from the wall
## (north) and its +x west, toward the parked plane's port door. A glazed
## vestibule stands on the exit door; a glazed stair enclosure runs straight
## out from it to a short landing on a pedestal, and the cab stands at the
## landing's end. Docked, the stair, landing and cab share one floor height,
## the plane's door sill: the stair keeps its RISERS and each rise is height /
## RISERS. The cab pivot is placed from the door itself: the enclosure slides
## out by `slide` so the cab sits abeam the door, the cab turns to face the
## fuselage and its bellows extend by `extend` to the skin. The walk from the
## exit door turns once, 90 degrees, in the cab.
##
## Models 04 to 07 dock. Model 03 does not (its door is under its high wing):
## the bridge stays parked and its passengers leave the vestibule through the
## apron door (Mount_ApronDoor) and walk to the plane door. Parked, the cab
## stands at PARK_HEIGHT, over plane 03's wing and under plane 04's rotor.
##
## The rig constants are the ones tools/blender/airside/build_airside_props.py
## builds the bridge with; test_airside_props_bridges.gd checks them against
## the written jet_bridge.glb.
##
## Not guaranteed: a door whose fuselage normal is not along the wall line
## (every stand in the game faces north) may solve to a cab the enclosure does
## not line up with; solve() refuses a front more than 25 degrees off.

## The rig, in metres, in the root's frame (+z out from the wall).
const STAIR_Z0 := 0.80
const STAIR_Z1 := 4.55
const STEP_OFF := 0.10
const RISERS := 16
const CAB_Z := 6.30
const CAB_HALF := 1.50
const CAB_IN := 2.10
const CAB_TOP := 2.25
const MOUNT_DOOR_Z := 2.10
const LANDING_END := CAB_Z - CAB_HALF
const CURTAIN_T := 0.04
const CURTAIN_GAP := 0.10
const CURTAIN_MIN := 0.01
const BOX_TOP := 5.20
const SKIN_T := 0.08
const VEST_HALF := 1.10
const APRON_Z := 0.80
## The vestibule's terminal face and the exit door collar off the wall line:
## both clear the terminal wall and stay under the roof fascia 0.25 m out.
const BOX_GAP_M := 0.30
const COLLAR_GAP_M := 0.16
## The joint ranges: the floor height (the docked models' sills), the slide
## out, the bellows' extension.
const HEIGHT_MIN := 0.63
const HEIGHT_MAX := 2.91
const SLIDE_MAX := 1.90
const EXTEND_MIN := -0.15
const EXTEND_MAX := 0.30
## Parked: the cab over plane 03's wing (2.57 m) and under plane 04's rotor
## disc (5.46 m) wherever either stands at the gate, facing west, the bellows
## drawn in.
const PARK_HEIGHT := 3.05
const PARK_EXTEND := -0.15
## How far the cab's front may turn off the walkway's square, in degrees.
const FRONT_MAX_DEG := 25.0
## How near a reported door must lie to a model's parked door to name it.
const SAME_DOOR_M := 0.05
## Slack on the joint ranges, so a pose exactly on a limit counts.
const LIMIT_SLACK := 1e-4
## The models that dock (ruling plane-03-boards-on-foot-from-the-apron-plane-
## 04-docks-the-no); every other model boards on foot from the apron door.
const DOCKING: Array[String] = ["tp_plane_04a", "tp_plane_05a", "tp_plane_06a", "tp_plane_07a"]
## The walk from the exit door to the plane door, mount by mount, and the
## way out to the apron for a model that does not dock.
const WALK: Array[StringName] = [
	&"Mount_ExitSill", &"Mount_StairFoot", &"Mount_StairTop", &"Mount_CabFloor", &"Mount_Door"
]
const APRON: Array[StringName] = [&"Mount_ExitSill", &"Mount_ApronDoor"]
## The rig's joint nodes, by the name each has in jet_bridge.glb.
const JOINTS: Array[StringName] = [
	&"Walk_Slide",
	&"Stair_Rise",
	&"Curtain_Low",
	&"Floor_Lift",
	&"Curtain_High",
	&"Cab_Yaw",
	&"Bellows_Extend",
]


## The bridge root's transform at `stand` (a StandPlacement stand, whose x and
## wall_z are its exit door's sill on the wall line), on the ground at
## `ground_y`.
static func root_for(stand: Dictionary, ground_y := 0.0) -> Transform3D:
	var at := Vector3(float(stand["x"]), ground_y, float(stand["wall_z"]))
	return Transform3D(Basis(Vector3.UP, PI), at)


## Whether `model` docks the bridge.
static func docks(model: String) -> bool:
	return DOCKING.has(model)


## Where plane `model` parked at `stand` has its front port door (world, the
## sill at `ground_y` + its sill height) and the unit normal out of its
## fuselage there: {"door", "normal"}. The plane stands as PlaneView draws it:
## nose to +z, moved by PlaneClasses.stand_offset().
static func plane_door(stand: Dictionary, model: String, ground_y := 0.0) -> Dictionary:
	var door: Vector3 = PlaneModels.PLANES[model]["doors"][0]
	var at := StandPlacement.stand_point(stand) + PlaneClasses.stand_offset(model) + door
	var side := signf(door.x) if door.x != 0.0 else 1.0
	return {"door": Vector3(at.x, ground_y + door.y, at.z), "normal": Vector3(side, 0.0, 0.0)}


## The model whose front port door, parked at `stand`, lies within SAME_DOOR_M
## of `door` (world), or "" for none. Every model's door sits at its own sill
## height (0.63 to 2.91 m, 0.16 m apart at the closest), so a reported door
## names its model.
static func model_at(stand: Dictionary, door: Vector3, ground_y := 0.0) -> String:
	for model: String in PlaneModels.PLANES:
		if (plane_door(stand, model, ground_y)["door"] as Vector3).distance_to(door) < SAME_DOOR_M:
			return model
	return ""


## The pose that puts Mount_Door on `door` (world) with the cab facing back
## along `normal` (world, out of the fuselage), for a bridge at `root`:
## {"ok", "slide", "height", "cab_yaw", "extend"}. "ok" is false when the door
## is out of the rig's reach.
static func solve(root: Transform3D, door: Vector3, normal: Vector3) -> Dictionary:
	var inv := root.affine_inverse()
	var p := inv * door
	var front := -(inv.basis * normal).slide(Vector3.UP).normalized()
	var yaw := atan2(front.x, front.z)
	var square := absf(front.x) >= cos(deg_to_rad(FRONT_MAX_DEG))
	var extend := (p.x / front.x - MOUNT_DOOR_Z) if square else 0.0
	var slide := p.z - front.z * (MOUNT_DOOR_Z + extend) - CAB_Z
	var ok := (
		square
		and _within(slide, 0.0, SLIDE_MAX)
		and _within(p.y, HEIGHT_MIN, HEIGHT_MAX)
		and _within(extend, EXTEND_MIN, EXTEND_MAX)
	)
	return {"ok": ok, "slide": slide, "height": p.y, "cab_yaw": yaw, "extend": extend}


## The parked pose: drawn in, the cab at PARK_HEIGHT facing west.
static func parked() -> Dictionary:
	return {
		"ok": true, "slide": 0.0, "height": PARK_HEIGHT, "cab_yaw": PI / 2.0, "extend": PARK_EXTEND
	}


## The bridge at `stand` with plane `model` ("" for none) parked there,
## docked or not: {"root", "pose", "docks" (the model docks), "docked" (the
## pose reaches its door), "door" and "normal" (the plane's door, model only),
## "mounts" (every mount name -> world point), "walk" (the docked walk from
## the exit sill to the plane door, else empty), "apron_walk" (exit sill,
## apron door, then the plane door on the ground, for a model that does not
## dock, else empty)}. A docking model whose door is out of reach is parked.
static func pose_for(stand: Dictionary, model: String, docked: bool, ground_y := 0.0) -> Dictionary:
	var root := root_for(stand, ground_y)
	var out := {"root": root, "docks": docks(model), "docked": false}
	var pose := parked()
	if model != "":
		var at := plane_door(stand, model, ground_y)
		out["door"] = at["door"]
		out["normal"] = at["normal"]
		if docked and docks(model):
			var aim := solve(root, at["door"], at["normal"])
			if aim["ok"]:
				pose = aim
				out["docked"] = true
			else:
				push_error("JetBridgePose: %s's door is out of the bridge's reach" % model)
	out["pose"] = pose
	var mounts := mounts_for(root, pose)
	out["mounts"] = mounts
	var walk := PackedVector3Array()
	var apron := PackedVector3Array()
	if out["docked"]:
		for name in WALK:
			walk.append(mounts[name])
	elif model != "" and not docks(model):
		for name in APRON:
			apron.append(mounts[name])
		var door: Vector3 = out["door"]
		apron.append(Vector3(door.x, ground_y, door.z))
	out["walk"] = walk
	out["apron_walk"] = apron
	return out


## Every mount of the bridge at `root` in `pose`, in world space: mount name
## -> point. The same points the glb's Mount_* nodes take under apply().
static func mounts_for(root: Transform3D, pose: Dictionary) -> Dictionary:
	var slide := root * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, pose["slide"]))
	var h: float = pose["height"]
	var cab := slide * Vector3(0.0, h, CAB_Z)
	var front := (
		Basis(Vector3.UP, pose["cab_yaw"]) * Vector3(0.0, 0.0, MOUNT_DOOR_Z + pose["extend"])
	)
	return {
		&"Mount_ExitSill": root * Vector3.ZERO,
		&"Mount_ApronDoor": root * Vector3(VEST_HALF, 0.0, APRON_Z),
		&"Mount_StairFoot": slide * Vector3(0.0, 0.0, STAIR_Z0 - STEP_OFF),
		&"Mount_StairTop": slide * Vector3(0.0, h, STAIR_Z1 + STEP_OFF),
		&"Mount_CabFloor": cab,
		&"Mount_Door": cab + root.basis * front,
	}


## Sets the joints of `joints` (JOINTS name -> Node3D, from joints_of()) to
## `pose` (solve() or parked()).
static func apply(joints: Dictionary, pose: Dictionary) -> void:
	var h: float = pose["height"]
	(joints[&"Walk_Slide"] as Node3D).position.z = pose["slide"]
	(joints[&"Stair_Rise"] as Node3D).scale = Vector3(1.0, h, 1.0)
	(joints[&"Curtain_Low"] as Node3D).scale = Vector3(1.0, maxf(h - CURTAIN_GAP, CURTAIN_MIN), 1.0)
	(joints[&"Floor_Lift"] as Node3D).position.y = h
	var over := BOX_TOP - SKIN_T - h - (CAB_IN + CURTAIN_GAP)
	(joints[&"Curtain_High"] as Node3D).scale = Vector3(1.0, maxf(over, CURTAIN_MIN), 1.0)
	(joints[&"Cab_Yaw"] as Node3D).rotation = Vector3(0.0, pose["cab_yaw"], 0.0)
	(joints[&"Bellows_Extend"] as Node3D).position.z = pose["extend"]


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


static func _within(value: float, lo: float, hi: float) -> bool:
	return value >= lo - LIMIT_SLACK and value <= hi + LIMIT_SLACK
