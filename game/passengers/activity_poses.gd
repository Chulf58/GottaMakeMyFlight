class_name ActivityPoses
extends RefCounted
## How a passenger visiting an activity or rest room is drawn (decision
## activity-poses-sit-on-the-lounge-sofa-recline-in-the-nap-pod): on the lounge
## sofa it sits on the piece's seat mount with the sit clips, in the nap pod it
## sits the same way and then leans back against the cushion with the head
## tilted (PodRecline), and in the shower it steps into the cubicle and stands
## there under foam and steam (ShowerFoam), its icons still showing. The play
## area keeps the browse pose: standing in front of the piece, facing it.
##
## The sim runs every activity visit as one SHOP_BROWSE stage at the piece's
## slot cell (ShopLayout), so this view-only helper reads the pose from the
## stage's own clock: it sits down over the first SIT_DOWN_TICKS of the stage
## and stands up over the last STAND_UP_TICKS before the stay ends (the type's
## dwell, or the visit's deadline when that comes first). Everything is worked
## out from the sim each tick, so a load or a clock that went back draws the
## pose for the loaded tick with nothing to reset (anti-pattern
## a-per-id-view-record-holding-a-sim-tick-must-start-over-on-l).

enum Kind { NONE, SEAT, RECLINE, SHOWER }

## Piece -> how its visitor is drawn.
const KINDS := {
	&"lounge_sofa": Kind.SEAT,
	&"lounge_armchair": Kind.SEAT,
	&"nap_pod": Kind.RECLINE,
	&"shower_cubicle": Kind.SHOWER,
}
## Piece -> where its visitor's feet go, by slot index, in the piece's own
## frame (metres; x across, y along its front, +y out of the front). The seat
## roots are the .glb's Mount_SitRoot nodes (build_activities_kit.py and
## build_services_kit.py, pinned by test_activity_poses against the imported
## files); the shower spot is the middle of the cubicle's tray.
const ROOTS := {
	&"lounge_sofa": [Vector2(-0.5, 0.45), Vector2(0.5, 0.45)],
	&"lounge_armchair": [Vector2(0.0, 0.45)],
	&"nap_pod": [Vector2(0.0, 0.45)],
	&"shower_cubicle": [Vector2(0.0, 0.0)],
}
## The shower tray's top: a showering passenger stands on it.
const SHOWER_TRAY_M := 0.10
## Ticks of the step from the slot cell onto the seat or into the shower, at
## the start of the stay, and back out at its end (as CafeSim.SHUFFLE_TICKS).
const SHUFFLE_TICKS := 12
## Ticks the nap pod's lean back takes once seated, and the foam's build-up
## once in the shower (and the same again at the end).
const EASE_TICKS := 20


## How `p` is drawn now: NONE unless it is staying at a sofa, armchair, nap
## pod or shower on an activity visit.
static func kind(sim: PassengerSim, p: Passenger) -> Kind:
	var piece := _piece(sim, p)
	if piece.is_empty():
		return Kind.NONE
	return KINDS.get(piece["def"], Kind.NONE)


## The seat pose of a sofa or nap pod visitor now: sitting down over the first
## SIT_DOWN_TICKS of the stay, standing up over its last STAND_UP_TICKS, and
## seated between. UPRIGHT for every other passenger, a showering one included.
static func pose(sim: PassengerSim, p: Passenger) -> StageKinds.Pose:
	var k := kind(sim, p)
	if k != Kind.SEAT and k != Kind.RECLINE:
		return StageKinds.Pose.UPRIGHT
	if _left(sim, p) < PassengerSim.STAND_UP_TICKS:
		return StageKinds.Pose.STANDING_UP
	if sim.tick - p.stage_tick < PassengerSim.SIT_DOWN_TICKS:
		return StageKinds.Pose.SITTING_DOWN
	return StageKinds.Pose.SEATED


## How far (0 to 1) `p` has stepped from its slot cell onto its seat or into
## the shower: up over the first SHUFFLE_TICKS of the stay, down over the last.
static func share(sim: PassengerSim, p: Passenger) -> float:
	if kind(sim, p) == Kind.NONE:
		return 0.0
	var step_in := (sim.tick - p.stage_tick) / float(SHUFFLE_TICKS)
	var step_out := _left(sim, p) / float(SHUFFLE_TICKS)
	return clampf(minf(step_in, step_out), 0.0, 1.0)


## The step from the sim's position (the slot cell) to where `p` is drawn: its
## seat root or the shower tray, times share(). Zero for everyone else, and
## for a visitor whose piece an edit removed.
static func offset(sim: PassengerSim, p: Passenger) -> Vector3:
	var piece := _piece(sim, p)
	if piece.is_empty() or not KINDS.has(piece["def"]):
		return Vector3.ZERO
	var spot := spot_of(sim.grid, piece, piece["index"])
	if KINDS[piece["def"]] == Kind.SHOWER:
		spot.y += SHOWER_TRAY_M
	return (spot - sim.world_position(p)) * share(sim, p)


## Where slot `index` of a piece record has its visitor's feet, in world space
## (the piece drawn as BuildView draws it, ROOTS in its frame); the piece's
## centre for a piece with no such slot.
static func spot_of(grid: BuildGrid, record: Dictionary, index: int) -> Vector3:
	var def := BuildCatalog.get_def(record["def"])
	var cells := def.footprint(record["anchor"], record["facing"])
	var frame := BuildView.object_transform(grid, cells, record["facing"])
	var roots: Array = ROOTS.get(record["def"], [])
	var root: Vector2 = roots[index] if index >= 0 and index < roots.size() else Vector2.ZERO
	return frame * Vector3(root.x, 0.0, root.y)


## The grid direction a staying visitor faces: out of the front of its piece
## (sat on the sofa or in the pod, or looking out of the shower door), except
## that a showering one faces into the cubicle while it steps in. Zero for
## everyone else.
static func facing(sim: PassengerSim, p: Passenger) -> Vector2i:
	var piece := _piece(sim, p)
	if piece.is_empty() or not KINDS.has(piece["def"]):
		return Vector2i.ZERO
	var out := TerminalLayout.front_of(piece["facing"])
	var stepping_in := sim.tick - p.stage_tick < SHUFFLE_TICKS
	if KINDS[piece["def"]] == Kind.SHOWER and stepping_in:
		return -out
	return out


## How far (0 to 1) a nap pod visitor leans back now: in over EASE_TICKS once
## it has sat down, out over EASE_TICKS before it stands up.
static func recline(sim: PassengerSim, p: Passenger) -> float:
	if kind(sim, p) != Kind.RECLINE:
		return 0.0
	var seated := sim.tick - p.stage_tick - PassengerSim.SIT_DOWN_TICKS
	var before_up := _left(sim, p) - PassengerSim.STAND_UP_TICKS
	return smoothstep(0.0, 1.0, minf(seated, before_up) / float(EASE_TICKS))


## How much foam (0 to 1) covers a showering visitor now: building up over
## EASE_TICKS as it steps in, rinsed off over EASE_TICKS before it steps out.
static func foam(sim: PassengerSim, p: Passenger) -> float:
	if kind(sim, p) != Kind.SHOWER:
		return 0.0
	var spent := sim.tick - p.stage_tick
	return smoothstep(0.0, 1.0, minf(spent, _left(sim, p)) / float(EASE_TICKS))


## The visited piece's grid record with "index" (the slot index) added, for a
## passenger staying on an activity visit; empty otherwise or once an edit
## removed the piece.
static func _piece(sim: PassengerSim, p: Passenger) -> Dictionary:
	if p.stage != Passenger.Stage.SHOP_BROWSE:
		return {}
	var visit := sim.shops.visit_of(p.id)
	if visit == null:
		return {}
	var type := RoomTypes.get_type(_room_type_id(sim, visit))
	var record := sim.grid.get_object(visit.display)
	if type == null or not type.activity or record.is_empty():
		return {}
	record["index"] = visit.index
	return record


static func _room_type_id(sim: PassengerSim, visit: ShopVisit) -> StringName:
	var room := sim.grid.get_room(visit.room)
	return room.get("type", &"") if not room.is_empty() else &""


## Ticks the stay has left after this one: the stage ends on the tick the
## dwell is reached (ShopSim.step settles it) or on the visit's deadline,
## whichever comes first, so the last tick drawn staying has 0 left.
static func _left(sim: PassengerSim, p: Passenger) -> int:
	var visit := sim.shops.visit_of(p.id)
	var type := RoomTypes.get_type(_room_type_id(sim, visit))
	var end := mini(p.stage_tick + ShopSim.browse_ticks(type), visit.deadline)
	return end - 1 - sim.tick
