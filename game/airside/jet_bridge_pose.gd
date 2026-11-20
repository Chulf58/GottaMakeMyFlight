class_name JetBridgePose
extends RefCounted
## The nose-loader jet bridge at a gate (board 0adca5c6; article airside-
## props; rulings jet-bridges-are-nose-loader-pedestal-bridges-an-enclosed-wal,
## nose-loader-bridge-design-stair-landing-and-cab-share-one-fl and plane-03-
## boards-on-foot-from-the-apron-plane-04-docks-the-no). Pure: from a stand,
## a plane model and whether it is docked it returns the rig's pose and every
## walk mount in world space; AirsideProps applies the pose to jet_bridge.glb,
## and the passenger sim walks the same walk (OutsideWalks.departure(), board
## 927ed9e0). Both decide docking from the flight's model (reaches()).
##
## The bridge's root is the gate's exit door sill on the stand's wall line,
## (stand x, wall_z), turned 180 degrees so its +z points out from the wall
## (north) and its +x west, toward the parked plane's port door. At a west or
## east stand the root, the plane's door and its normal turn a further quarter
## turn with the stand (StandPlacement.SIDE_YAW), so the bridge stands to its
## plane as it does at a north stand. A glazed
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
## its passengers leave the vestibule through the apron door
## (Mount_ApronDoor) and walk to the plane door. Parked, the cab stands at
## PARK_HEIGHT, over plane 03's wing and under plane 04's rotor.
##
## Folded (folds(), board b564cda3, ruling small-planes-the-jet-bridge-folds-
## back-against-the-terminal): with plane 03 or no plane at the gate the
## walkway is drawn retracted. apply() then hides Walk_Slide and everything on
## it (the stair enclosure, stair, landing, cab, bellows and pedestal) and
## Vest_Full (the full-height vestibule), and shows Fold_Cap, the vestibule's
## ground floor alone (ruling v2, "Lower the folded box"): FOLD_TOP high,
## reaching VEST_END out, with the same exit and apron doors. The joints stay
## parked, so the walk and every mount are what they were.
##
## The rig constants are the ones tools/blender/airside/build_airside_props.py
## builds the bridge with; test_airside_props_bridges.gd checks them against
## the written jet_bridge.glb.
##
## Not guaranteed: a door whose fuselage normal is not along the wall line
## (every stand's plane parks square to its wall) may solve to a cab the
## enclosure does not line up with; solve() refuses a front more than 25
## degrees off.

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
## The vestibule's far end out from the wall, where Fold_Cap stands, and the
## stair enclosure's outer half width (the opening the cap closes).
const VEST_END := 2.30
const BOX_HALF := 1.00
## The folded box's roof top.
const FOLD_TOP := 2.50
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
## How far out from plane 03's door, along its fuselage normal, its apron walk
## ends: right outboard of the main wheel pant (x <= 1.75 m in plane-local,
## leaving > 0.06 m body margin beyond BODY_M = 0.25 m) under the high wing.
const APRON_END_OUT_M := 1.30
## How far aft of plane 03's door (opposite the nose) the approach and end sit
## so the passenger clears the diagonal wing strut (z >= 1.26 m in plane-local,
## leaving > 0.09 m body margin beyond BODY_M = 0.25 m).
const APRON_END_AFT_M := 0.20
## Step straight out from Mount_ApronDoor so walkers clear the vestibule wall
## before angling past plane 03's propeller disc and wing strut.
const APRON_DOOR_OUT_M := 0.60
## Intermediate apron-walk waypoint for plane 03: out along the door normal so
## walkers pass clear of the spinning propeller disc and outboard of the low
## wing strut before stepping in beside the main wheel.
const APRON_CLEAR_OUT_M := 2.00
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
## The rig's joint nodes, by the name each has in jet_bridge.glb; Fold_Cap
## and Vest_Full are shown or hidden, never moved.
const JOINTS: Array[StringName] = [
	&"Walk_Slide",
	&"Stair_Rise",
	&"Curtain_Low",
	&"Floor_Lift",
	&"Curtain_High",
	&"Cab_Yaw",
	&"Bellows_Extend",
	&"Fold_Cap",
	&"Vest_Full",
]


## The ground the bridge at `stand` stands on: the surface under the parked
## plane (PlaneView.ground_height_at() of its stand point), so the docked
## floor meets the drawn door. The sim's walk (OutsideWalks) and the drawn
## bridge (AirsideProps) both use it. Off the paved site, at a north-row gate,
## it is below the site's ground height.
static func ground_y(stand: Dictionary) -> float:
	return PlaneView.ground_height_at(StandPlacement.stand_point(stand))


## The bridge root's transform at `stand` (a StandPlacement stand, whose x and
## wall_z are its exit door's sill on the wall line), on the ground at
## `ground_y`.
static func root_for(stand: Dictionary, ground_y := 0.0) -> Transform3D:
	var at := Vector3(float(stand["x"]), ground_y, float(stand["wall_z"]))
	var side := StandPlacement.side_of(stand)
	if side != StandPlacement.NORTH:
		return Transform3D(Basis(Vector3.UP, PI + float(StandPlacement.SIDE_YAW[side])), at)
	return Transform3D(Basis(Vector3.UP, PI), at)


## Whether `model` docks the bridge.
static func docks(model: String) -> bool:
	return PlaneModels.PLANES.has(model) and not PlaneClasses.self_taxis(model)


## Whether the bridge is drawn folded with plane `model` ("" for none) at the
## gate: when no plane or one that does not dock stands there. A docking
## model out of reach leaves it parked, unfolded.
static func folds(model: String) -> bool:
	return not docks(model)


## Where plane `model` parked at `stand` has its front port door (world, the
## sill at `ground_y` + its sill height) and the unit normal out of its
## fuselage there: {"door", "normal"}. The plane stands as PlaneView draws it:
## nose to +z, moved by PlaneClasses.stand_offset(). At a side stand both are
## its north twin's turned onto it.
static func plane_door(stand: Dictionary, model: String, ground_y := 0.0) -> Dictionary:
	if StandPlacement.side_of(stand) != StandPlacement.NORTH:
		var twin := plane_door(StandPlacement.north_twin(stand), model, ground_y)
		return {
			"door": StandPlacement.to_world(stand, twin["door"]),
			"normal": StandPlacement.turn(stand, twin["normal"]),
		}
	var door: Vector3 = PlaneModels.PLANES[model]["doors"][0]
	var at := StandPlacement.stand_point(stand) + PlaneClasses.stand_offset(model) + door
	var side := signf(door.x) if door.x != 0.0 else 1.0
	return {"door": Vector3(at.x, ground_y + door.y, at.z), "normal": Vector3(side, 0.0, 0.0)}


## Whether plane `model` parked at `stand` docks the bridge: the model docks
## and the bridge reaches its door. It never pushes an error (pose_for() does
## for a docking model out of reach), so the passenger sim and AirsideProps ask
## it routinely, and pose_for(stand, model, reaches(...)) then never errs.
static func reaches(stand: Dictionary, model: String, ground_y := 0.0) -> bool:
	if not docks(model):
		return false
	var at := plane_door(stand, model, ground_y)
	return solve(root_for(stand, ground_y), at["door"], at["normal"])["ok"]


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
## pose reaches its door), "folded" (folds()), "door" and "normal" (the
## plane's door, model only),
## "mounts" (every mount name -> world point), "walk" (the docked walk from
## the exit sill to the plane door, else empty), "apron_walk" (exit sill,
## apron door, vestibule exit, outer approach, then on the ground beside the
## main wheel APRON_END_OUT_M out and APRON_END_AFT_M aft of the plane door,
## for a model that does not dock, else empty)}. A docking model whose door is
## out of reach is parked.
static func pose_for(stand: Dictionary, model: String, docked: bool, ground_y := 0.0) -> Dictionary:
	var root := root_for(stand, ground_y)
	var out := {"root": root, "docks": docks(model), "docked": false, "folded": folds(model)}
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
		# Step clear of the folded vestibule wall, pass clear of the propeller
		# disc and wing strut, then step in aft of the strut beside the main
		# wheel under the high wing.
		var normal: Vector3 = out["normal"]
		var forward := StandPlacement.turn(stand, Vector3(0.0, 0.0, 1.0))
		var door_exit: Vector3 = mounts[&"Mount_ApronDoor"] - normal * APRON_DOOR_OUT_M
		apron.append(Vector3(door_exit.x, ground_y, door_exit.z))
		var approach: Vector3 = out["door"] + normal * APRON_CLEAR_OUT_M - forward * APRON_END_AFT_M
		apron.append(Vector3(approach.x, ground_y, approach.z))
		var end: Vector3 = out["door"] + normal * APRON_END_OUT_M - forward * APRON_END_AFT_M
		apron.append(Vector3(end.x, ground_y, end.z))
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
## `pose` (solve() or parked()), drawn folded when `folded` (folds()): the
## walkway and the full vestibule hidden and Fold_Cap shown; otherwise the
## reverse.
static func apply(joints: Dictionary, pose: Dictionary, folded := false) -> void:
	(joints[&"Walk_Slide"] as Node3D).visible = not folded
	(joints[&"Vest_Full"] as Node3D).visible = not folded
	(joints[&"Fold_Cap"] as Node3D).visible = folded
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
