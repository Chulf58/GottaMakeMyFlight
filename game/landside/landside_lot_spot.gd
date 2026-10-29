class_name LandsideLotSpot
extends Resource
## A place by the road where a car park can stand (LandsideDefinition.lots).
## A car that means to park turns off road_in at `branch_mm` onto `access`,
## drives to its end (the lot gate) and parks in a reserved slot; its
## passengers walk `crossing` from the gate over both carriageways to the
## porch. A leaving car drives `exit` back onto the road. When the lot is full
## (every slot parked or reserved) a car does not turn and drops off at the
## curb instead.

## Where the turn is, in mm along road_in.
@export var branch_mm := 0
## The lane from the turn to the lot gate.
@export var access := PackedVector3Array()
## The lane from the lot gate back onto the road and off the map.
@export var exit := PackedVector3Array()
## Each parking space's car position.
@export var slots := PackedVector3Array()
## The walk from the lot gate over the road to the porch.
@export var crossing := PackedVector3Array()
