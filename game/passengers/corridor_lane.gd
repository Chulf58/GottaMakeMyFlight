class_name CorridorLane
extends RefCounted
## Purely visual wall-clamped right-hand corridor lane offset for walking
## passengers (decision passenger-walking-separation-wall-clamped-right-hand-
## corrido). Walkers moving along indoor corridor paths shift slightly to
## their right so opposite-direction walkers pass shoulder-to-shoulder instead
## of phasing through each other, strictly clamped against walls and obstacles
## and faded cleanly to zero at endpoints, turns, doorways, queues, stations,
## seats, scanners, and stalls. Never mutates sim state.

const LANE_OFFSET_M := 0.24
const CLEARANCE_M := 0.50
const TURN_BLEND_M := 0.45
const ENDPOINT_FADE_M := 2.4
const LOOKAHEAD_M := 1.2
const MIN_PATH_MM := 2000
const CHASE_STEP_M := 0.015

const WALK_STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.TO_CHECKIN,
	Passenger.Stage.TO_SECURITY,
	Passenger.Stage.TO_GATE,
	Passenger.Stage.TO_EXIT,
	Passenger.Stage.CAFE_WALK,
	Passenger.Stage.CAFE_TO_SEAT,
	Passenger.Stage.TOILET_WALK,
	Passenger.Stage.SHOP_WALK,
]


## Desired right-hand corridor lateral offset in world space (x, 0, z) for
## `p` in `sim`, or Vector3.ZERO when standing, stationary, near a door/endpoint,
## or boxed in on the right.
static func target_offset(sim: PassengerSim, p: Passenger) -> Vector3:
	if _excluded(sim, p):
		return Vector3.ZERO
	var end_weight := _endpoint_weight(p)
	if end_weight <= 0.001:
		return Vector3.ZERO
	return _lateral_offset(sim.grid, p, end_weight)


## Rendered lane offset for the next tick from previous `prev`: returns
## Vector3.ZERO immediately in any excluded state (stationary, non-corridor,
## FileWaiters, on an object cell, or within DoorSteer.FULL_M of a door), and
## strictly clamps the stepped candidate against the current position's fade
## envelope and 3x3 wall/obstacle clearance so the drawn body never lags into
## walls or zero-offset zones.
static func step_offset(sim: PassengerSim, p: Passenger, prev: Vector3) -> Vector3:
	if _excluded(sim, p):
		return Vector3.ZERO
	var pos_local := p.grid_position()
	var end_weight := _endpoint_weight(p)
	var door_weight := _door_weight(sim.grid, pos_local)
	if end_weight <= 0.001 or door_weight <= 0.001:
		return Vector3.ZERO
	var target := _lateral_offset(sim.grid, p, end_weight, door_weight)
	var cand := prev.move_toward(target, CHASE_STEP_M)
	var cap := LANE_OFFSET_M * end_weight * door_weight
	var cand_2d := Vector2(cand.x, cand.z)
	var cand_len := minf(cand_2d.length(), cap)
	if cand_len <= 0.001:
		return Vector3.ZERO
	var cand_dir := cand_2d.normalized()
	var walk_dir := _blended_direction(p).normalized()
	var dist := _tapered_clamp(sim.grid, pos_local, walk_dir, cand_dir, cand_len)
	if dist <= 0.001:
		return Vector3.ZERO
	return Vector3(cand_dir.x * dist, 0.0, cand_dir.y * dist)


static func _excluded(sim: PassengerSim, p: Passenger) -> bool:
	if sim == null or sim.grid == null or p == null:
		return true
	if not WALK_STAGES.has(p.stage) or not p.is_moving() or p.path.size() < 2:
		return true
	if sim.files.waiters.ids().has(p.id):
		return true
	return sim.grid.object_at(p.at) != 0


static func _endpoint_weight(p: Passenger) -> float:
	var walked_mm := p.seg_mm
	for i in p.path_index:
		walked_mm += Passenger.segment_mm(p.path[i], p.path[i + 1])
	var left_mm := p.remaining_mm()
	if walked_mm + left_mm < MIN_PATH_MM:
		return 0.0
	return (
		smoothstep(0.0, ENDPOINT_FADE_M, walked_mm / 1000.0)
		* smoothstep(0.0, ENDPOINT_FADE_M, left_mm / 1000.0)
	)


static func _lateral_offset(
	grid: BuildGrid, p: Passenger, end_weight: float, door_weight := -1.0
) -> Vector3:
	var blended := _blended_direction(p)
	var turn_scale := clampf(blended.length(), 0.0, 1.0)
	if turn_scale <= 0.001:
		return Vector3.ZERO
	var dir := blended.normalized()
	var right := Vector2(-dir.y, dir.x)
	var pos_local := p.grid_position()
	var d_weight := _door_weight(grid, pos_local) if door_weight < 0.0 else door_weight
	var desired := LANE_OFFSET_M * end_weight * d_weight * turn_scale
	if desired <= 0.001:
		return Vector3.ZERO
	var dist := _tapered_clamp(grid, pos_local, dir, right, desired)
	if dist <= 0.001:
		return Vector3.ZERO
	return Vector3(right.x * dist, 0.0, right.y * dist)


## Clamps `desired` strictly at `pos_local` and tapers down smoothly over
## LOOKAHEAD_M ahead along `walk_dir` so approaching a wall or obstacle eases
## smoothly rather than dropping sharply on a corner.
static func _tapered_clamp(
	grid: BuildGrid, pos_local: Vector2, walk_dir: Vector2, offset_dir: Vector2, desired: float
) -> float:
	var under := Vector2i(floori(pos_local.x), floori(pos_local.y))
	var limit := _clamp_distance(pos_local, offset_dir, desired, _obstacles_near(grid, under))
	if limit <= 0.001 or walk_dir.length_squared() < 1e-6:
		return limit
	for s: float in [0.4, 0.8, LOOKAHEAD_M]:
		var ahead := pos_local + walk_dir * s
		var a_cell := Vector2i(floori(ahead.x), floori(ahead.y))
		var d_ahead := _clamp_distance(ahead, offset_dir, desired, _obstacles_near(grid, a_cell))
		limit = minf(limit, d_ahead + (s / LOOKAHEAD_M) * LANE_OFFSET_M)
	return limit


## Smooth walking direction along `p.path` around corners so turns ease rather
## than snap. Length shrinks toward zero on sharp hairpin reversals.
static func _blended_direction(p: Passenger) -> Vector2:
	var a := p.path[p.path_index]
	var b := p.path[p.path_index + 1]
	var cur := _seg_dir(a, b)
	var seg_len := Passenger.segment_mm(a, b) / 1000.0
	var s := p.seg_mm / 1000.0
	var rem := seg_len - s
	if p.path_index > 0 and s < TURN_BLEND_M:
		var prev := _seg_dir(p.path[p.path_index - 1], a)
		var w := 0.5 + 0.5 * smoothstep(0.0, TURN_BLEND_M, s)
		return prev.lerp(cur, w)
	if p.path_index + 2 < p.path.size() and rem < TURN_BLEND_M:
		var nxt := _seg_dir(b, p.path[p.path_index + 2])
		var w := 0.5 + 0.5 * smoothstep(0.0, TURN_BLEND_M, rem)
		return nxt.lerp(cur, w)
	return cur


static func _seg_dir(a: Vector2i, b: Vector2i) -> Vector2:
	return Vector2(b - a).normalized()


## Weight in [0, 1] fading smoothly to 0 near any entrance/exit door or
## interior door wall so DoorSteer and doorway frames are never fought.
static func _door_weight(grid: BuildGrid, pos_local: Vector2) -> float:
	var weight := 1.0
	var here := grid.origin + Vector3(pos_local.x, 0.0, pos_local.y)
	for door: Array in DoorSteer.doors_near(grid, here):
		if float(door[3]) < DoorSteer.LATERAL_M and float(door[2]) < DoorSteer.EASE_M:
			weight = minf(weight, smoothstep(DoorSteer.FULL_M, DoorSteer.EASE_M, float(door[2])))
	var under := Vector2i(floori(pos_local.x), floori(pos_local.y))
	for dy in range(-DoorSteer.REACH_CELLS, DoorSteer.REACH_CELLS + 1):
		for dx in range(-DoorSteer.REACH_CELLS, DoorSteer.REACH_CELLS + 1):
			var cell := under + Vector2i(dx, dy)
			if not grid.in_bounds(cell):
				continue
			if grid.wall_kind(cell, BuildGrid.Side.NORTH) == BuildGrid.WallKind.DOOR:
				var n_w := _edge_door_weight(pos_local.y - cell.y, pos_local.x - (cell.x + 0.5))
				weight = minf(weight, n_w)
			if grid.wall_kind(cell, BuildGrid.Side.WEST) == BuildGrid.WallKind.DOOR:
				var w_w := _edge_door_weight(pos_local.x - cell.x, pos_local.y - (cell.y + 0.5))
				weight = minf(weight, w_w)
	return weight


static func _edge_door_weight(d_plane: float, d_axis: float) -> float:
	if absf(d_axis) >= DoorSteer.LATERAL_M or absf(d_plane) >= DoorSteer.EASE_M:
		return 1.0
	return smoothstep(DoorSteer.FULL_M, DoorSteer.EASE_M, absf(d_plane))


## Grid-local obstacle boxes (solid/non-passenger cells, object footprints, and
## wall edges) within the 3x3 neighbourhood around `under`.
static func _obstacles_near(grid: BuildGrid, under: Vector2i) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cell := under + Vector2i(dx, dy)
			if not grid.is_passenger_cell(cell) or grid.object_at(cell) != 0:
				out.append(Rect2(Vector2(cell), Vector2.ONE))
			if grid.wall_kind(cell, BuildGrid.Side.NORTH) != BuildGrid.WallKind.NONE:
				out.append(Rect2(Vector2(cell), Vector2(1.0, 0.0)))
			if grid.wall_kind(cell, BuildGrid.Side.WEST) != BuildGrid.WallKind.NONE:
				out.append(Rect2(Vector2(cell), Vector2(0.0, 1.0)))
			if dy == 1 and grid.wall_kind(cell, BuildGrid.Side.SOUTH) != BuildGrid.WallKind.NONE:
				out.append(Rect2(Vector2(cell.x, cell.y + 1), Vector2(1.0, 0.0)))
			if dx == 1 and grid.wall_kind(cell, BuildGrid.Side.EAST) != BuildGrid.WallKind.NONE:
				out.append(Rect2(Vector2(cell.x + 1, cell.y), Vector2(0.0, 1.0)))
	return out


static func _clamp_distance(
	pos: Vector2, right: Vector2, desired: float, obstacles: Array[Rect2]
) -> float:
	if _is_clear(pos, pos + right * desired, obstacles):
		return desired
	var lo := 0.0
	var hi := desired
	for i in 10:
		var mid := (lo + hi) * 0.5
		if _is_clear(pos, pos + right * mid, obstacles):
			lo = mid
		else:
			hi = mid
	return lo


static func _is_clear(origin: Vector2, candidate: Vector2, obstacles: Array[Rect2]) -> bool:
	for rect in obstacles:
		var limit := minf(CLEARANCE_M, _dist_to_rect(origin, rect))
		if _dist_to_rect(candidate, rect) < limit - 1e-4:
			return false
	return true


static func _dist_to_rect(pt: Vector2, rect: Rect2) -> float:
	var cx := clampf(pt.x, rect.position.x, rect.end.x)
	var cy := clampf(pt.y, rect.position.y, rect.end.y)
	return pt.distance_to(Vector2(cx, cy))
