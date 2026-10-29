class_name LandsideCurbSpot
extends Resource
## A place by the road where a drop-off curb bay can be built
## (LandsideDefinition.curb_spots), 16 x 3 m with two berths (decision
## landside-assets-the-curb-is-an-authored-paint-only-drop-off). Once built,
## its berths join the starter curb's: the front car at the curb's stop takes
## the lowest free berth of all. World points only.

## The bay's middle on the ground plane, where the build tools snap.
@export var centre := Vector3.ZERO
## The bay's size in metres, x by z.
@export var footprint := Vector2(16.0, 3.0)
## Each berth's car position, the first to fill first.
@export var berths := PackedVector3Array()
## Where the passengers of the car in each berth step out, on the curb side.
@export var get_out := PackedVector3Array()
