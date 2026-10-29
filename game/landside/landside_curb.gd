class_name LandsideCurb
extends Resource
## A drop-off curb beside the road in (LandsideDefinition.road_in): a bay of
## berths cars pull into to let their passengers out. Cars queue on the road
## behind `stop_mm`, the head of the queue; the front car takes the lowest
## free berth. World points only; the sim keeps positions in whole mm.

## Where the queue head waits, in mm along road_in.
@export var stop_mm := 0
## Each berth's car position (the middle of the car).
@export var berths := PackedVector3Array()
## Where the passengers of the car in each berth step out, on the curb side.
@export var get_out := PackedVector3Array()
