class_name StallDoors
extends RefCounted
## Stateless outward bi-fold door animation for toilet_stall pieces
## (Door_Leaf_Stall_L/R + child Door_Fold_Stall_L/R; board ac734ad8). Reads only
## PassengerSim / ToiletSim state and the clock's alpha, so frame rate, late
## first draws and save loads produce identical leaf and fold angles.

const LEAF_LEFT := "Door_Leaf_Stall_L"
const LEAF_RIGHT := "Door_Leaf_Stall_R"
const FOLD_LEFT := "Door_Fold_Stall_L"
const FOLD_RIGHT := "Door_Fold_Stall_R"
const ROOT_PREFIX := "ToiletStall_ROOT/"
## Walk distance (mm) before the stall's approach cell over which the bi-fold
## leaves open (0.55 m), finishing before a front-carried bag reaches z = 1.12 m.
const WALK_OPEN_MM := 550.0
## Tick within TOILET_ENTER (12 ticks) when the leaves begin closing behind the
## visitor stepping in to Mount_Turn.
const ENTER_CLOSE_START := 9.0
## Tick within TOILET_STANDING_UP (24 ticks) when the leaves begin opening so
## they reach 1.0 before TOILET_EXIT tick 0's bag pick-up (k = 0..1) starts.
const STAND_OPEN_START := 20.0
## Tick within TOILET_EXIT (12 ticks) when the leaves begin closing (10..12,
## z_root = 1.31..1.50 m, well past the z <= 1.11 m outward bi-fold stack).
const EXIT_CLOSE_START := 10.0
## Outer half-leaf turns 90 deg outward (-PI/2 on L, +PI/2 on R) while child
## inner panel folds 180 deg back (+PI on L, -PI on R) so z stays >= 0.878 m.
const OPEN_RAD := PI * 0.5
const FOLD_RAD := PI


## Door open weight in [0, 1] for placed `toilet_stall` object `stall_id`.
static func open_weight(sim: PassengerSim, stall_id: int, alpha: float) -> float:
	if sim == null or sim.grid == null or sim.toilets == null or stall_id <= 0:
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
	if sim == null or sim.toilets == null or ghost.get("def") != &"toilet_stall":
		return 0.0
	var stall_id := int(ghost.get("id", 0))
	var holder_id := sim.toilets.stall_holder(stall_id)
	var visit := sim.toilets.visit_of(holder_id) if holder_id != 0 else null
	var p := sim.get_passenger(holder_id) if holder_id != 0 else null
	if visit == null or p == null or not _same_placement(visit.piece, ghost):
		return 0.0
	return _stage_weight(sim, p, visit, clampf(alpha, 0.0, 1.0))


## Poses any relocated toilet_stall stand-ins in `ghosts` without redundant
## per-frame Relocation.ghosts() scans when no toilet visit is relocated.
static func sync_ghosts(
	sim: PassengerSim, ghosts: RelocationGhosts, alpha: float, from_process: bool
) -> void:
	if sim == null or sim.grid == null or sim.toilets == null or ghosts == null:
		return
	var relocated: Array[ToiletVisit] = []
	for id in sim.toilets.visit_ids():
		var p := sim.get_passenger(id)
		var visit := sim.toilets.visit_of(id)
		if p == null or visit == null or not ToiletSim.STALL_STAGES.has(p.stage):
			continue
		var live := Relocation.placement(sim.grid, visit.stall_id)
		var leaving := (
			visit.relocation != null
			and visit.relocation.exiting
			and not visit.piece.is_empty()
			and live != visit.piece
		)
		if leaving or Relocation.moved(visit.piece, live):
			relocated.append(visit)
	if relocated.is_empty():
		if not from_process and ghosts.count() > 0:
			ghosts.sync()
		return
	if not from_process:
		ghosts.sync()
	var clamped := clampf(alpha, 0.0, 1.0)
	for visit in relocated:
		var entry := visit.piece.duplicate()
		entry["id"] = visit.stall_id
		var node := ghosts.node_of(entry)
		var p := sim.get_passenger(visit.passenger)
		if node != null and p != null:
			apply(node, _stage_weight(sim, p, visit, clamped))


## Rotates Door_Leaf_Stall_L/R outward (-/+90 deg * weight) and child
## Door_Fold_Stall_L/R back (+/-180 deg * weight) on `node`.
static func apply(node: Node3D, weight: float) -> void:
	if node == null:
		return
	var clamped := clampf(weight, 0.0, 1.0)
	var left := _find_part(node, LEAF_LEFT)
	var right := _find_part(node, LEAF_RIGHT)
	if left != null:
		left.rotation = Vector3(0.0, -OPEN_RAD * clamped, 0.0)
		var fold_l := _find_fold(left, FOLD_LEFT)
		if fold_l != null:
			fold_l.rotation = Vector3(0.0, FOLD_RAD * clamped, 0.0)
	if right != null:
		right.rotation = Vector3(0.0, OPEN_RAD * clamped, 0.0)
		var fold_r := _find_fold(right, FOLD_RIGHT)
		if fold_r != null:
			fold_r.rotation = Vector3(0.0, -FOLD_RAD * clamped, 0.0)


static func _find_part(node: Node3D, part_name: String) -> Node3D:
	var direct := node.get_node_or_null(ROOT_PREFIX + part_name) as Node3D
	if direct != null:
		return direct
	return node.find_child(part_name, true, false) as Node3D


static func _find_fold(leaf: Node3D, fold_name: String) -> Node3D:
	var direct := leaf.get_node_or_null(fold_name) as Node3D
	if direct != null:
		return direct
	return leaf.find_child(fold_name, true, false) as Node3D


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
