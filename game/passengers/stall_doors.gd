class_name StallDoors
extends RefCounted
## Stateless inward door swing for toilet_stall pieces (Door_Leaf_Stall_L and
## Door_Leaf_Stall_R; decision toilet-stall-kit-piece-1x2-footprint-side-
## partitions-out-to, board ac734ad8). Reads only PassengerSim / ToiletSim
## state and the clock's alpha, so frame rate, late first draws and save loads
## produce identical leaf angles.

const LEAF_LEFT := "Door_Leaf_Stall_L"
const LEAF_RIGHT := "Door_Leaf_Stall_R"
const ROOT_PREFIX := "ToiletStall_ROOT/"
## Walk distance (mm) before the stall's approach cell over which the doors
## open ahead of an arriving visitor (0.40 m).
const WALK_OPEN_MM := 400.0
## Tick within TOILET_ENTER (12 ticks) when the doors begin closing behind the
## visitor stepping in to Mount_Turn.
const ENTER_CLOSE_START := 9.0
## Tick within TOILET_STANDING_UP (24 ticks) when the doors begin opening so
## they reach 1.0 before TOILET_EXIT tick 0's bag pick-up (k = 0..1) starts.
const STAND_OPEN_START := 20.0
## Tick within TOILET_EXIT (12 ticks) when the doors begin closing after the
## 6-tick bag pick-up and step-out clear the doorway.
const EXIT_CLOSE_START := 9.0
## Each half-leaf swings 90 degrees inward toward Mount_Use (-Z): +90 deg on L
## and -90 deg on R about Godot +Y.
const OPEN_RAD := PI * 0.5


## Door open weight in [0, 1] for placed `toilet_stall` object `stall_id`.
static func open_weight(sim: PassengerSim, stall_id: int, alpha: float) -> float:
	if sim == null or sim.grid == null or stall_id <= 0:
		return 0.0
	var live := Relocation.placement(sim.grid, stall_id)
	var holder_id := sim.toilets.stall_holder(stall_id)
	if live.is_empty() or live["def"] != &"toilet_stall" or holder_id == 0:
		return 0.0
	var visit := sim.toilets.visit_of(holder_id)
	var p := sim.get_passenger(holder_id)
	if visit == null or p == null or visit.stall_id != stall_id:
		return 0.0
	var leaving_old := visit.relocation != null and visit.relocation.exiting
	if leaving_old or Relocation.moved(visit.piece, live):
		return 0.0
	return _stage_weight(sim, p, visit, clampf(alpha, 0.0, 1.0))


## Door open weight in [0, 1] for a Relocation.ghosts() toilet_stall stand-in
## while its occupant finishes leaving the old spot.
static func ghost_open_weight(sim: PassengerSim, ghost: Dictionary, alpha: float) -> float:
	if sim == null or ghost.get("def") != &"toilet_stall":
		return 0.0
	var stall_id := int(ghost.get("id", 0))
	var holder_id := sim.toilets.stall_holder(stall_id)
	var visit := sim.toilets.visit_of(holder_id) if holder_id != 0 else null
	var p := sim.get_passenger(holder_id) if holder_id != 0 else null
	if visit == null or p == null or not _same_placement(visit.piece, ghost):
		return 0.0
	return _stage_weight(sim, p, visit, clampf(alpha, 0.0, 1.0))


## Rotates Door_Leaf_Stall_L (+90 deg * weight) and Door_Leaf_Stall_R
## (-90 deg * weight) inward on `node`.
static func apply(node: Node3D, weight: float) -> void:
	if node == null:
		return
	var clamped := clampf(weight, 0.0, 1.0)
	var left := _find_leaf(node, LEAF_LEFT)
	var right := _find_leaf(node, LEAF_RIGHT)
	if left != null:
		left.rotation = Vector3(0.0, OPEN_RAD * clamped, 0.0)
	if right != null:
		right.rotation = Vector3(0.0, -OPEN_RAD * clamped, 0.0)


static func _find_leaf(node: Node3D, leaf_name: String) -> Node3D:
	var direct := node.get_node_or_null(ROOT_PREFIX + leaf_name) as Node3D
	if direct != null:
		return direct
	return node.find_child(leaf_name, true, false) as Node3D


static func _same_placement(a: Dictionary, b: Dictionary) -> bool:
	return (
		not a.is_empty()
		and a.get("def") == b.get("def")
		and a.get("anchor") == b.get("anchor")
		and a.get("facing") == b.get("facing")
	)


static func _stage_weight(
	sim: PassengerSim, p: Passenger, visit: ToiletVisit, alpha: float
) -> float:
	var elapsed := float(sim.tick - p.stage_tick) + alpha
	match p.stage:
		Passenger.Stage.TOILET_WALK:
			return _walk_weight(p, visit, alpha)
		Passenger.Stage.TOILET_ENTER:
			return _close_ramp(elapsed, ENTER_CLOSE_START, float(ToiletSim.ENTER_TICKS))
		Passenger.Stage.TOILET_STANDING_UP:
			return _open_ramp(elapsed, STAND_OPEN_START, float(PassengerSim.STAND_UP_TICKS))
		Passenger.Stage.TOILET_EXIT:
			return _close_ramp(elapsed, EXIT_CLOSE_START, float(ToiletSim.EXIT_TICKS))
	return 0.0


static func _walk_weight(p: Passenger, visit: ToiletVisit, alpha: float) -> float:
	var approach: Vector2i = visit.stall.get("approach", Passenger.NO_CELL)
	if approach == Passenger.NO_CELL:
		return 0.0
	if p.at == approach and not p.is_moving():
		return 1.0
	if not p.is_moving() or p.path_end() != approach:
		return 0.0
	var left_mm := maxf(float(p.remaining_mm()) - alpha * float(p.pace_mm()), 0.0)
	return _ease(1.0 - left_mm / WALK_OPEN_MM)


static func _open_ramp(elapsed: float, from_tick: float, to_tick: float) -> float:
	return _ease((elapsed - from_tick) / (to_tick - from_tick))


static func _close_ramp(elapsed: float, from_tick: float, to_tick: float) -> float:
	return 1.0 - _ease((elapsed - from_tick) / (to_tick - from_tick))


static func _ease(ratio: float) -> float:
	return smoothstep(0.0, 1.0, clampf(ratio, 0.0, 1.0))
