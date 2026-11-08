class_name PlaneModels
extends RefCounted
## Measured shapes of the plane, runway and jet bridge models (decision
## runway-and-taxi-technical-design-movement-plan-analytic-bookings-planned-
## pauses, points 1 and 2). Every number comes from
## tools/blender/census/plane_offsets.py, which reads the written .glb files;
## re-run it and copy its GDSCRIPT lines after a re-export. Metres, Godot axes,
## about each file's origin unless a field says otherwise.
##
## Every plane faces +z with its port side on +x. Per plane:
## - "aabb": the true vertex bounds.
## - "length", "half_span": nose to tail, and centreline to wingtip.
## - "nose", "tail": how far the nose is ahead of the origin and the tail
##   behind it.
## - "model_offset": the position that puts the middle of the box on the pose
##   point, as PlaneView draws every model off the stand (FlightPose.
##   model_position). About the pose point the nose and the tail are then each
##   length / 2 away.
## - "doors": one point per passenger door: the door's middle along the plane,
##   its outer face across, its sill height. Grouped by station (doors whose
##   middles are within 0.1 m along the plane), stations front to back, port
##   before starboard in each.
## - "own_swing_radius": this model's own half box diagonal about the pose
##   point, rounded up to 0.1 m (the rule StandPlacement.SWING_RADIUS_M uses).
##   It is not a stand clearance: a stand reserves its class radius, the
##   largest own_swing_radius among the class's members, which PlaneClasses
##   computes (board item R2). This table carries no classes.
##
## tp_plane_05a is the model the stand was built around, parked with offset
## (0, 0, 1.7) (PlaneClasses.REFERENCE_OFFSET); the measured middle is 1.63.

const PLANES := {
	"tp_plane_03a":
	{
		"path": "res://assets/planes/tp_plane_03a.glb",
		"aabb": AABB(Vector3(-7.06, -0.02, -6.46), Vector3(14.12, 3.23, 10.69)),
		"length": 10.69,
		"half_span": 7.06,
		"nose": 4.22,
		"tail": 6.46,
		"model_offset": Vector3(0.00, 0.00, 1.12),
		"doors": [Vector3(0.76, 0.79, 1.12), Vector3(-0.76, 0.79, 1.12)],
		"own_swing_radius": 8.9,
	},
	"tp_plane_04a":
	{
		"path": "res://assets/planes/tp_plane_04a.glb",
		"aabb": AABB(Vector3(-12.26, -0.01, -12.25), Vector3(24.53, 6.74, 19.27)),
		"length": 19.27,
		"half_span": 12.26,
		"nose": 7.02,
		"tail": 12.25,
		"model_offset": Vector3(0.00, 0.00, 2.62),
		"doors": [Vector3(1.30, 0.63, 0.64)],
		"own_swing_radius": 15.6,
	},
	"tp_plane_05a":
	{
		"path": "res://assets/planes/tp_plane_05a.glb",
		"aabb": AABB(Vector3(-14.17, -0.01, -16.25), Vector3(28.34, 7.17, 29.24)),
		"length": 29.24,
		"half_span": 14.17,
		"nose": 12.99,
		"tail": 16.25,
		"model_offset": Vector3(0.00, 0.00, 1.63),
		"doors": [Vector3(1.37, 1.58, 8.62)],
		"own_swing_radius": 20.4,
	},
	"tp_plane_06a":
	{
		"path": "res://assets/planes/tp_plane_06a.glb",
		"aabb": AABB(Vector3(-15.45, -0.01, -21.40), Vector3(30.90, 10.21, 41.98)),
		"length": 41.98,
		"half_span": 15.45,
		"nose": 20.58,
		"tail": 21.40,
		"model_offset": Vector3(0.00, 0.00, 0.41),
		"doors":
		[
			Vector3(1.69, 2.39, 15.09),
			Vector3(-1.69, 2.39, 15.09),
			Vector3(1.70, 2.39, 8.99),
			Vector3(-1.70, 2.39, 8.99),
			Vector3(1.70, 2.39, -3.95),
			Vector3(-1.70, 2.39, -3.95),
		],
		"own_swing_radius": 26.1,
	},
	"tp_plane_07a":
	{
		"path": "res://assets/planes/tp_plane_07a.glb",
		"aabb": AABB(Vector3(-21.78, -0.01, -24.38), Vector3(43.56, 12.11, 48.70)),
		"length": 48.70,
		"half_span": 21.78,
		"nose": 24.32,
		"tail": 24.38,
		"model_offset": Vector3(0.00, 0.00, 0.03),
		"doors":
		[
			Vector3(1.90, 2.91, 18.09),
			Vector3(-1.90, 2.91, 18.09),
			Vector3(1.91, 2.91, 10.09),
			Vector3(-1.91, 2.91, 10.09),
			Vector3(1.91, 2.91, -4.91),
			Vector3(-1.91, 2.91, -4.91),
			Vector3(1.84, 2.91, -14.61),
			Vector3(-1.84, 2.91, -14.61),
		],
		"own_swing_radius": 32.7,
	},
}

## The runway strips (64 m wide across z, 0.2 m thick) and the mobile jet
## bridge (TP_Loading_Truck_01A), by true vertex bounds.
const PIECES := {
	"tp_runway_01a":
	{
		"path": "res://assets/airside/tp_runway_01a.glb",
		"aabb": AABB(Vector3(0.00, 0.00, -32.00), Vector3(48.00, 0.20, 64.00)),
	},
	"tp_runway_02a":
	{
		"path": "res://assets/airside/tp_runway_02a.glb",
		"aabb": AABB(Vector3(-48.00, 0.00, -32.00), Vector3(96.00, 0.20, 64.00)),
	},
	"tp_runway_03a":
	{
		"path": "res://assets/airside/tp_runway_03a.glb",
		"aabb": AABB(Vector3(-48.00, 0.00, -32.00), Vector3(96.00, 0.20, 64.00)),
	},
	"tp_runway_04a":
	{
		"path": "res://assets/airside/tp_runway_04a.glb",
		"aabb": AABB(Vector3(-48.00, 0.00, -32.00), Vector3(96.00, 0.20, 64.00)),
	},
	"tp_runway_05a":
	{
		"path": "res://assets/airside/tp_runway_05a.glb",
		"aabb": AABB(Vector3(-48.00, 0.00, -32.00), Vector3(96.00, 0.20, 64.00)),
	},
	"tp_loading_truck_01a":
	{
		"path": "res://assets/vehicles/tp_loading_truck_01a.glb",
		"aabb": AABB(Vector3(-1.47, 0.00, -6.48), Vector3(3.06, 4.98, 14.04)),
	},
}
