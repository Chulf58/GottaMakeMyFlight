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

const SURFACE_FOOTPRINT := Vector2(24.0, 32.3)
const SURFACE_CENTRE_Z := -21.65
const SURFACE_AISLE_Z := -35.0
const SURFACE_GATE_DX := -3.7
const SURFACE_EXIT_DX := 3.7
const SURFACE_CROSS_DX := -6.7
const SURFACE_SLOT_DX := 6.85
const SURFACE_SLOT_ZS := [-30.5, -26.5, -22.5, -18.5, -14.5, -10.5]

const MULTI_FOOTPRINT := Vector2(24.0, 52.0)
const MULTI_CENTRE_Z := -8.0
const MULTI_AISLE_DX := -2.5
const MULTI_AISLE_Z := -28.0
const MULTI_GATE_DX := 3.5
const MULTI_EXIT_DX := 6.5
const MULTI_CROSS_DX := -2.0
const MULTI_CROSS_START_DX := 2.35
const MULTI_SLOT_DX := -6.6
const MULTI_GROUND_ZS := [-20.0, -16.0, -12.0, -8.0, -4.0, 0.0, 4.0, 8.0, 12.0]
const MULTI_UPPER_ZS := [-28.0, -24.0, -20.0, -16.0, -12.0, -8.0, -4.0, 0.0, 4.0, 8.0, 12.0]
const FORECOURT_HALF_X := 35.0
const ROAD_END_EAST_X := 140.4
const ROAD_THROUGH_WEST_Z := -48.25
const ROAD_THROUGH_EAST_Z := -43.6
const ROAD_FORECOURT_Z := -55.0
const ROAD_FORECOURT_EAST_X := 34.0
const ROAD_FORECOURT_TURN_X := 40.0

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
## A multi-storey only: the way out through the entrance in its own lane, from
## just inside to in front of it, where `exit` starts. A leaving car drives
## from the aisle front or the foot of the lowest ramp to its first point.
## Empty: the car leaves the way it came in, `entrance` reversed.
@export var way_out := PackedVector3Array()
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


## Returns `pad` when its default kind already matches `target_kind`, or a
## deterministic kind-shifted copy centred at `pad.centre.x` joined to `road_in`.
static func for_kind(
	pad: LandsideLotSpot, target_kind: Kind, road_in: PackedVector3Array
) -> LandsideLotSpot:
	if pad.kind == target_kind:
		return pad
	return build_pad(pad.centre.x, target_kind, road_in)


## Builds a complete surface or multi-storey lot spot centred at `cx` with
## `branch_mm` computed deterministically along `road_in`.
static func build_pad(cx: float, target_kind: Kind, road_in: PackedVector3Array) -> LandsideLotSpot:
	var spot := LandsideLotSpot.new()
	spot.kind = target_kind
	if target_kind == Kind.MULTI_STOREY:
		_fill_multi(spot, cx, road_in)
	else:
		_fill_surface(spot, cx, road_in)
	return spot


static func _fill_surface(spot: LandsideLotSpot, cx: float, road_in: PackedVector3Array) -> void:
	spot.centre = Vector3(cx, 0.0, SURFACE_CENTRE_Z)
	spot.footprint = SURFACE_FOOTPRINT
	spot.aisle_front = Vector3(cx, 0.1, SURFACE_AISLE_Z)
	var gate_x := cx + SURFACE_GATE_DX
	var exit_x := cx + SURFACE_EXIT_DX
	spot.access = _access_lane(cx, gate_x, false, road_in)
	spot.branch_mm = LandsideDefinition.mm_along(road_in, spot.access[0])
	spot.exit = PackedVector3Array(
		[
			Vector3(exit_x, 0.1, -37.5),
			Vector3(exit_x, 0.1, -39.7),
			Vector3(exit_x, 0.2, -39.95),
			Vector3(exit_x, 0.2, -41.26),
			Vector3(exit_x, 0.1, -41.5),
			Vector3(exit_x, 0.1, ROAD_THROUGH_EAST_Z),
			Vector3(ROAD_END_EAST_X, 0.1, ROAD_THROUGH_EAST_Z),
		]
	)
	var slots := PackedVector3Array()
	for side in [-SURFACE_SLOT_DX, SURFACE_SLOT_DX]:
		for z in SURFACE_SLOT_ZS:
			slots.append(Vector3(cx + side, 0.1, z))
	spot.slots = slots
	spot.crossing = _crossing_lane(cx, cx + SURFACE_CROSS_DX, cx + SURFACE_CROSS_DX, -38.2)


static func _fill_multi(spot: LandsideLotSpot, cx: float, road_in: PackedVector3Array) -> void:
	spot.centre = Vector3(cx, 0.0, MULTI_CENTRE_Z)
	spot.footprint = MULTI_FOOTPRINT
	spot.aisle_front = Vector3(cx + MULTI_AISLE_DX, 0.3, MULTI_AISLE_Z)
	var gate_x := cx + MULTI_GATE_DX
	var exit_x := cx + MULTI_EXIT_DX
	spot.access = _access_lane(cx, gate_x, true, road_in)
	spot.branch_mm = LandsideDefinition.mm_along(road_in, spot.access[0])
	spot.exit = PackedVector3Array(
		[
			Vector3(exit_x, 0.1, -38.0),
			Vector3(exit_x, 0.1, -39.7),
			Vector3(exit_x, 0.2, -39.95),
			Vector3(exit_x, 0.2, -41.26),
			Vector3(exit_x, 0.1, -41.5),
			Vector3(exit_x, 0.1, ROAD_THROUGH_EAST_Z),
			Vector3(ROAD_END_EAST_X, 0.1, ROAD_THROUGH_EAST_Z),
		]
	)
	var slots := PackedVector3Array()
	for z in MULTI_GROUND_ZS:
		slots.append(Vector3(cx + MULTI_SLOT_DX, 0.3, z))
	for deck_y in [5.3, 10.3]:
		for z in MULTI_UPPER_ZS:
			slots.append(Vector3(cx + MULTI_SLOT_DX, deck_y, z))
	spot.slots = slots
	spot.crossing = _crossing_lane(cx, cx + MULTI_CROSS_START_DX, cx + MULTI_CROSS_DX, -38.0)
	spot.entrance = PackedVector3Array([Vector3(gate_x, 0.3, -33.0), Vector3(gate_x, 0.36, -28.0)])
	spot.way_out = PackedVector3Array(
		[
			Vector3(exit_x, 0.36, -28.0),
			Vector3(exit_x, 0.3, -33.0),
			Vector3(exit_x, 0.3, -34.0),
			Vector3(exit_x, 0.26, -34.8),
			Vector3(exit_x, 0.22, -35.6),
			Vector3(exit_x, 0.18, -36.4),
			Vector3(exit_x, 0.14, -37.2),
		]
	)
	var r0 := PackedVector3Array(
		[
			Vector3(cx - 2.5, 5.3, 5.5),
			Vector3(cx + 5.0, 5.3, 5.5),
			Vector3(cx + 5.0, 5.3, 0.5),
			Vector3(cx + 5.0, 4.3, -5.5),
			Vector3(cx + 5.0, 2.7, -11.5),
			Vector3(cx + 5.0, 1.3, -17.5),
			Vector3(cx + 5.0, 0.5, -23.5),
			Vector3(gate_x, 0.36, -28.0),
		]
	)
	var r1 := PackedVector3Array(
		[
			Vector3(cx - 2.5, 10.3, 5.5),
			Vector3(cx + 5.0, 10.3, 5.5),
			Vector3(cx + 5.0, 10.3, 0.5),
			Vector3(cx + 5.0, 9.25, -5.5),
			Vector3(cx + 5.0, 7.6, -11.5),
			Vector3(cx + 5.0, 6.15, -17.5),
			Vector3(cx + 5.0, 5.3, -23.5),
			Vector3(cx + 5.0, 5.3, -25.5),
			Vector3(cx - 2.5, 5.3, -25.5),
		]
	)
	spot.ramps = [r0, r1]


static func _access_lane(
	cx: float, gate_x: float, multi: bool, road_in: PackedVector3Array
) -> PackedVector3Array:
	var lane := PackedVector3Array()
	if road_in.size() >= 3 and cx >= -10.0 and cx <= FORECOURT_HALF_X:
		var join_x := minf(gate_x, ROAD_FORECOURT_EAST_X)
		lane.append(Vector3(join_x, 0.1, ROAD_FORECOURT_Z))
		lane.append(Vector3(gate_x, 0.1, -45.0))
	elif cx > FORECOURT_HALF_X:
		var join_x := gate_x + 6.0
		lane.append(Vector3(join_x, 0.1, ROAD_THROUGH_WEST_Z))
		lane.append(Vector3(join_x - 3.0, 0.1, -47.3))
		lane.append(Vector3(gate_x, 0.1, -45.0))
	else:
		var join_x := ROAD_FORECOURT_TURN_X + clampf(roundf(absf(cx) / 28.0) * 0.5, 0.5, 3.0)
		lane.append(Vector3(join_x, 0.1, ROAD_THROUGH_WEST_Z))
		lane.append(Vector3(gate_x + 6.0, 0.1, ROAD_THROUGH_WEST_Z))
		lane.append(Vector3(gate_x + 3.0, 0.1, -47.3))
		lane.append(Vector3(gate_x, 0.1, -45.0))
	lane.append(Vector3(gate_x, 0.1, -41.5))
	lane.append(Vector3(gate_x, 0.2, -41.26))
	lane.append(Vector3(gate_x, 0.2, -39.95))
	lane.append(Vector3(gate_x, 0.1, -39.7))
	if multi:
		lane.append(Vector3(gate_x, 0.1, -38.0))
		lane.append(Vector3(gate_x, 0.14, -37.2))
		lane.append(Vector3(gate_x, 0.18, -36.4))
		lane.append(Vector3(gate_x, 0.22, -35.6))
		lane.append(Vector3(gate_x, 0.26, -34.8))
		lane.append(Vector3(gate_x, 0.3, -34.0))
	else:
		lane.append(Vector3(gate_x, 0.1, -37.5))
	return lane


static func _crossing_lane(
	cx: float, start_x: float, cross_x: float, start_z: float
) -> PackedVector3Array:
	var pts := PackedVector3Array(
		[
			Vector3(start_x, 0.1, start_z),
			Vector3(start_x, 0.1, -39.75),
			Vector3(start_x, 0.2, -40.05),
		]
	)
	if not is_equal_approx(start_x, cross_x):
		pts.append(Vector3(cross_x, 0.2, -40.05))
	pts.append(Vector3(cross_x, 0.2, -41.1))
	pts.append(Vector3(cross_x, 0.1, -41.4))
	if absf(cx) <= FORECOURT_HALF_X:
		pts.append(Vector3(cross_x, 0.1, -58.52))
		pts.append(Vector3(cross_x, 0.2, -58.82))
		pts.append(Vector3(cross_x, 0.2, -60.5))
	else:
		var edge_x := FORECOURT_HALF_X if cx > 0.0 else -FORECOURT_HALF_X
		pts.append(Vector3(cross_x, 0.1, -50.5))
		pts.append(Vector3(cross_x, 0.2, -50.8))
		pts.append(Vector3(cross_x, 0.2, -51.6))
		pts.append(Vector3(edge_x, 0.2, -51.6))
		pts.append(Vector3(edge_x, 0.1, -52.5))
		pts.append(Vector3(edge_x, 0.1, -58.52))
		pts.append(Vector3(edge_x, 0.2, -58.82))
		pts.append(Vector3(edge_x, 0.2, -60.5))
	return pts
