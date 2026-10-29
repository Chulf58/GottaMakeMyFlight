class_name LandsideLotSpot
extends Resource
## A place by the road where a car park can stand (LandsideDefinition.lots).
## A car that means to park turns off road_in at `branch_mm` onto `access`,
## drives to its end (the lot gate), then along the aisle (and up the ramps of
## a multi-storey) into a reserved slot; its passengers walk back to the gate
## (down the ramps from an upper deck) and over both carriageways along
## `crossing` to the porch. A leaving car drives back to `exit` and along it
## onto the road (LandsidePaths builds these routes). When the lot is full
## (every slot parked or reserved) a car does not turn and drops off at the
## curb instead.

## What the player can build here (decision landside-parking-kinds-a-cheap-
## surface-lot-and-an-expensive): a surface lot or a multi-storey car park.
## The kind fixes the spot's footprint and so its capacity (slots.size()).
enum Kind { SURFACE, MULTI_STOREY }

@export var kind := Kind.SURFACE
## The footprint's middle on the ground plane and its size in metres, x by z:
## where the build tools snap and what they draw.
@export var centre := Vector3.ZERO
@export var footprint := Vector2.ZERO
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
## A multi-storey only: the way from the gate through the building's entrance
## in its ground-floor wall, from in front of it to just inside.
@export var entrance := PackedVector3Array()
## Where the aisle between the stalls meets the gate side, on the ground. Cars
## and walkers turn between the aisle and a stall at the stall's z, at this x,
## on every deck.
@export var aisle_front := Vector3.ZERO
## A multi-storey only: per deck above the ground, the lowest first, the way
## down that deck's ramp, from the deck's aisle to the aisle of the deck below
## (the first ends where `entrance` ends). The points are on the walkable
## surface and include every slope break of the ramp (test_landside_geometry.gd
## checks them against the asset). Reversed, a deck's way down is a car's way
## up.
@export var ramps: Array[PackedVector3Array] = []
