class_name LandsidePlaces
extends Node3D
## The curb bays and car parks of the landside, drawn where the sim's
## LandsideDefinition puts their berths and slots (Landside 4/4): the curb's
## paint bays (tp_curb_bay_01a) always, and a surface lot (tp_parking_01a) on
## each lot spot LandsideSim has built. Read-only; LandsideViews refreshes it
## each tick and it rebuilds only when the built lots change.
##
## Provisional layout, pending a ruling on the authored geometry: a bay holds
## two berths 6.5 m apart, so berths are paired along the kerb from the end
## nearest the curb's stop and a berth left without a partner gets no paint;
## a bay's origin stands on the kerb line (kerb_z), as the bay asset expects
## (decision landside-assets-the-curb-is-an-authored-paint-only-drop-off).
## A lot faces the road, its entrance edge on the gate (the end of its access
## lane) and its middle across the road on the middle of its slots. The road
## runs along x, as LandsideDefinition says.

const BAY := preload("res://assets/landside/tp_curb_bay_01a.glb")
const LOT := preload("res://assets/landside/tp_parking_01a.glb")
## The bay's two berths, centre to centre (tools/blender/landside/curb_bay.py).
const BAY_PITCH := 6.5
const PITCH_TOLERANCE := 0.05
## The lot's entrance edge in its own frame: its barriers stand at local x -7
## and the slab starts at -7.3 (landside_plates_probe.gd MEASURE line).
const LOT_ENTRANCE_X := -7.3
## Turned so the lot's entrance side (local -x) faces the road (-z).
const LOT_YAW := -PI / 2.0
## The lot's ground height, as the landside plates placed it.
const LOT_Y := -0.1

@export var landside: LandsideSim
## The kerb line's z: measured on tp_airport_shell.glb in main.tscn (shell at
## z -80), where the road and sidewalk tops are one plane at y 0.107.
@export var kerb_z := -58.7
@export var road_top := 0.107

var _bays: Array[Node3D] = []
## Lot spot -> its drawn lot.
var _lots := {}


## Adds the curb bays once and a lot for each lot spot built, and removes the
## lot of a spot no longer built.
func refresh() -> void:
	if landside == null or landside.definition == null:
		return
	if _bays.is_empty():
		for origin in bay_origins(landside.definition, kerb_z, road_top):
			var bay: Node3D = BAY.instantiate()
			bay.name = "CurbBay%d" % _bays.size()
			bay.position = origin
			add_child(bay)
			_bays.append(bay)
	for spot in landside.lots_built.size():
		var built: bool = landside.lots_built[spot]
		if built and not _lots.has(spot):
			var lot: Node3D = LOT.instantiate()
			lot.name = "Lot%d" % spot
			lot.transform = lot_transform(landside.definition.lots[spot])
			add_child(lot)
			_lots[spot] = lot
		elif not built and _lots.has(spot):
			(_lots[spot] as Node).queue_free()
			_lots.erase(spot)


func bay_count() -> int:
	return _bays.size()


func bay(i: int) -> Node3D:
	return _bays[i]


## The drawn lot of a spot, or null.
func lot_node(spot: int) -> Node3D:
	return _lots.get(spot)


## Where each curb bay stands: one per pair of berths 6.5 m apart along the
## kerb, paired from the berth nearest the curb's stop on; a berth with no
## partner is left out.
static func bay_origins(
	definition: LandsideDefinition, at_kerb_z: float, at_height: float
) -> Array[Vector3]:
	var stop := LandsideDefinition.point_at(definition.road_in, definition.curb.stop_mm)
	var berths: Array = Array(definition.curb.berths)
	berths.sort_custom(
		func(a: Vector3, b: Vector3) -> bool: return absf(a.x - stop.x) < absf(b.x - stop.x)
	)
	var out: Array[Vector3] = []
	var i := 0
	while i + 1 < berths.size():
		var a: Vector3 = berths[i]
		var b: Vector3 = berths[i + 1]
		if absf(absf(a.x - b.x) - BAY_PITCH) <= PITCH_TOLERANCE and is_equal_approx(a.z, b.z):
			out.append(Vector3((a.x + b.x) * 0.5, at_height, at_kerb_z))
			i += 2
		else:
			i += 1
	return out


## Where a lot spot's surface lot stands: facing the road, its entrance edge
## on the gate and centred across on its slots.
static func lot_transform(spot: LandsideLotSpot) -> Transform3D:
	var gate := spot.access[spot.access.size() - 1]
	var lo := INF
	var hi := -INF
	for slot in spot.slots:
		lo = minf(lo, slot.x)
		hi = maxf(hi, slot.x)
	var basis := Basis(Vector3.UP, LOT_YAW)
	# Local +x points along world +z once turned, so the entrance edge sits
	# LOT_ENTRANCE_X behind the origin along z.
	return Transform3D(basis, Vector3((lo + hi) * 0.5, LOT_Y, gate.z - LOT_ENTRANCE_X))
