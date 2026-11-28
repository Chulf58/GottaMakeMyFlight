class_name BaggageShuttle
extends RefCounted
## One baggage_cart shuttle trip between a bag room and a parked plane's stand
## (decisions baggage-loop-completion-connect-gated-penalties-visible-wait and
## bag-room-rethink-b1-bay-door-4x3-kit-and-b2-hand-carry-wave-routing).
## Routes exclusively through a valid Roll-Up Bay Door (baggage_bay_door) with
## orthogonal clearance anchors, and tracks brisk 2-bag hand-carry transfers.

enum Phase { TO_BAG_ROOM, TRANSFER_OUT, OUTBOUND, UNLOADING, RETURNING, TRANSFER_IN }

const ENTRY_TICKS := 10
const TRANSFER_LEG_TICKS := 4
const LOAD_STEP_TICKS := TRANSFER_LEG_TICKS
const CARRY_BATCH_SIZE := 2
const MIN_TRAVEL_TICKS := 40
const MAX_TRAVEL_TICKS := 140
const UNLOAD_TICKS := 20
const TRAVEL_TICKS_PER_M := 3.0
const APRON_CLEAR_HALF_WIDTH_M := 0.85
const AGENT_SIDE_CART_M := 0.75
const AGENT_END_OFFSET_M := 0.45
const RAMP_WALK_MPS := 3.2
const SMALL_CARGO_OFFSET := Vector3(-2.6, 0.0, 5.8)
const LARGE_CARGO_OFFSET := Vector3(-5.0, 0.0, 1.5)
const FALLBACK_CARGO_OFFSET := Vector3(-3.5, 0.0, 6.5)
const ROUTE_PAD_CELLS := 4
const SHUTTLE_OFFSET := Vector3(0.0, 0.0, -1.25)

var id := 0
var cart_id := 0
var bay_door_id := 0
var flight := ""
var phase := Phase.TRANSFER_OUT
var load_start_tick := 0
var transfer_start_tick := 0
var load_step_ticks := TRANSFER_LEG_TICKS
var next_load_tick := 0
var start_tick := 0
var arrive_tick := 0
var unload_tick := 0
var return_tick := 0
var origin_world := Vector3.ZERO
var origin_yaw := 0.0
var target_world := Vector3.ZERO
var target_yaw := 0.0
var pickup_world := Vector3.ZERO
var bay_inside_world := Vector3.ZERO
var bay_door_world := Vector3.ZERO
var bay_outside_world := Vector3.ZERO
## Ordered world path points [origin_world, ..., target_world].
var waypoints: Array[Vector3] = []
var bag_ids: Array[int] = []
var carried_bag_ids: Array[int] = []
var pending_bag_ids: Array[int] = []
## Staff member id assigned as driver/loader (0 = automated / unassigned).
var driver_staff_id := 0
var inbound := false


## True while the cart itself currently holds suitcases on its deck.
func carrying_bags() -> bool:
	return not bag_ids.is_empty()


## Where the cart parks beside the plane at `stand` (StandPlacement): starboard
## forward fuselage, away from the port passenger walk and jet bridge.
static func cargo_point(stand: Dictionary, model_name := "") -> Vector3:
	var twin := StandPlacement.north_twin(stand)
	var at: Vector3
	if model_name != "" and PlaneClasses.self_taxis(model_name):
		at = StandPlacement.stand_point(twin) + SMALL_CARGO_OFFSET
	elif model_name != "" and PlaneModels.PLANES.has(model_name):
		at = StandPlacement.door_point(twin, model_name) + LARGE_CARGO_OFFSET
	else:
		at = StandPlacement.stand_point(twin) + FALLBACK_CARGO_OFFSET
	return StandPlacement.to_world(stand, at)


## Surface height under `point`: site paving/ramp height on a SiteGrid, else
## the test grid's origin height.
static func ground_y(grid: BuildGrid, point: Vector3) -> float:
	if grid is SiteGrid:
		return PlaneView.ground_height_at(point)
	return grid.origin.y if grid != null else 0.0


## Deterministic cart transform at integer sim `at_tick`.
func pose_at(at_tick: int, grid: BuildGrid) -> Transform3D:
	var pts: Array[Vector3] = waypoints if waypoints.size() >= 2 else [origin_world, target_world]
	var pos := origin_world
	var yaw := origin_yaw
	if phase == Phase.OUTBOUND:
		var span := maxi(1, arrive_tick - start_tick)
		var t := clampf(float(at_tick - start_tick) / float(span), 0.0, 1.0)
		var sample := _sample_path(pts, t, origin_yaw)
		pos = sample["pos"]
		yaw = _blend_yaw(origin_yaw, sample["yaw"], target_yaw, t)
	elif phase == Phase.UNLOADING:
		pos = target_world
		yaw = target_yaw
	elif phase == Phase.RETURNING:
		var span := maxi(1, return_tick - unload_tick)
		var t := clampf(float(at_tick - unload_tick) / float(span), 0.0, 1.0)
		var rev := pts.duplicate()
		rev.reverse()
		var sample := _sample_path(rev, t, target_yaw)
		pos = sample["pos"]
		yaw = _blend_yaw(target_yaw, sample["yaw"], origin_yaw, t)
	pos.y = ground_y(grid, pos)
	return Transform3D(Basis(Vector3.UP, yaw), pos)


## Deterministic Ramp Agent pose at integer sim `at_tick` across all phases.
func agent_pose_at(at_tick: int, grid: BuildGrid, bag_sim: BaggageSim = null) -> Dictionary:
	if phase == Phase.TO_BAG_ROOM:
		return _entry_agent_pose(at_tick, grid)
	if phase == Phase.TRANSFER_OUT:
		return _transfer_out_agent_pose(at_tick, grid, bag_sim)
	if phase == Phase.TRANSFER_IN:
		return _transfer_in_agent_pose(at_tick, grid, bag_sim)
	var cart_xform := pose_at(at_tick, grid)
	var pos := cart_xform * SHUTTLE_OFFSET
	pos.y = ground_y(grid, pos)
	if phase == Phase.UNLOADING:
		var to_cart := cart_xform.origin - pos
		return {"pos": pos, "yaw": atan2(to_cart.x, to_cart.z), "clip": "idle", "speed": 1.0}
	var forward := cart_xform.basis.z.slide(Vector3.UP)
	var yaw := atan2(forward.x, forward.z) if forward.length() > 0.001 else 0.0
	var next_xform := pose_at(at_tick + 1, grid)
	var step_m := (next_xform * SHUTTLE_OFFSET - pos).slide(Vector3.UP).length()
	var walk_mps := StaffCharacters.CLIP_WALK_MPS[StaffMember.Role.RAMP]
	var speed := clampf((step_m * SimClock.TICK_RATE) / walk_mps, 0.5, 2.5)
	return {"pos": pos, "yaw": yaw, "clip": "walk", "speed": speed}


## Orthogonal inside/threshold/outside clearance anchors for a valid Roll-Up Bay Door,
## or {} when the door is gone or its apron approach is obstructed.
static func bay_door_anchors(grid: BuildGrid, door_id: int) -> Dictionary:
	if grid == null or door_id <= 0:
		return {}
	var record := grid.get_object(door_id)
	if record.is_empty() or not BuildCatalog.is_bay_door(record["def"]):
		return {}
	var anchor: Vector2i = record["anchor"]
	var facing: int = record["facing"]
	if not DoorPlacement.is_bay_door_apron_clear(grid, anchor, facing):
		return {}
	var out := DoorPlacement.back_step(facing)
	var cells := DoorPlacement.bay_door_cells(anchor, facing)
	var apron_cells: Array[Vector2i] = []
	for cell in cells:
		if _edge_walled(grid, cell, out, false):
			return {}
		apron_cells.append(cell + out)
	var w0 := grid.cell_to_world(cells[0])
	var w1 := grid.cell_to_world(cells[1])
	var mid_in := (w0 + w1) * 0.5
	var out_dir := Vector3(float(out.x), 0.0, float(out.y))
	var door_center := mid_in + out_dir * 0.5
	var outside_dist := 1.0
	var far_clear := true
	for ap in apron_cells:
		var far_cell: Vector2i = ap + out
		if (
			not DoorPlacement.is_apron_cell_open(grid, far_cell)
			or _edge_walled(grid, ap, out, false)
		):
			far_clear = false
			break
	if far_clear:
		outside_dist = 1.5
	var outside_clear := mid_in + out_dir * outside_dist
	mid_in.y = ground_y(grid, mid_in)
	door_center.y = ground_y(grid, door_center)
	outside_clear.y = ground_y(grid, outside_clear)
	return {
		"bay_door_id": door_id,
		"cells": cells,
		"apron_cells": apron_cells,
		"out_step": out,
		"inside_clear": mid_in,
		"door_center": door_center,
		"outside_clear": outside_clear,
	}


## All valid Roll-Up Bay Doors wholly inside `room_rect`, sorted by object id.
static func valid_bay_doors_in_room(grid: BuildGrid, room_rect: Rect2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if grid == null or room_rect.size == Vector2i.ZERO:
		return out
	var ids := grid.object_ids()
	ids.sort()
	for door_id in ids:
		var record := grid.get_object(door_id)
		if not BuildCatalog.is_bay_door(record["def"]):
			continue
		var cells := DoorPlacement.bay_door_cells(record["anchor"], record["facing"])
		var inside := true
		for c in cells:
			if not room_rect.has_point(c):
				inside = false
				break
		if not inside:
			continue
		var anchors := bay_door_anchors(grid, door_id)
		if not anchors.is_empty():
			out.append(anchors)
	return out


## Plans a bay-door-only orthogonal route from `origin` (inside a bag_room) to `target`.
## Returns {"ok": bool, "bay_door_id": int, "waypoints": Array[Vector3], ...}.
static func plan_room_route(grid: BuildGrid, origin: Vector3, target: Vector3) -> Dictionary:
	var fail := {"ok": false, "bay_door_id": 0, "waypoints": [] as Array[Vector3]}
	if grid == null:
		return fail
	var origin_cell := grid.world_to_cell(origin)
	var room_id := grid.room_at(origin_cell)
	if room_id == 0:
		return fail
	var room := grid.get_room(room_id)
	if StringName(room.get("type", &"")) != BeltShaper.BAG_ROOM:
		return fail
	var room_rect: Rect2i = room.get("rect", Rect2i())
	var doors := valid_bay_doors_in_room(grid, room_rect)
	if doors.is_empty():
		return fail
	var bounds := _search_bounds(grid, origin, target)
	var target_cell := _clamp_to_rect(grid.world_to_cell(target), bounds)
	var field := _apron_field(grid, bounds, target_cell)
	var dist_from_target: Dictionary = field["dist"]
	var apron_parent: Dictionary = field["parent"]
	var room_bfs := _room_bfs(grid, origin_cell, room_rect)
	var room_dist: Dictionary = room_bfs["dist"]
	var room_parent: Dictionary = room_bfs["parent"]
	var best := _pick_best_bay_door(doors, room_dist, dist_from_target)
	if best.is_empty():
		return fail
	var door_info: Dictionary = best["door"]
	var inside_cell: Vector2i = best["inside"]
	var ext_cell: Vector2i = best["ext"]
	var pts := _room_waypoints(grid, origin, origin_cell, inside_cell, room_parent)
	var bay_in: Vector3 = door_info["inside_clear"]
	var bay_door: Vector3 = door_info["door_center"]
	var bay_out: Vector3 = door_info["outside_clear"]
	_append_unique_pt(pts, bay_in)
	_append_unique_pt(pts, bay_door)
	_append_unique_pt(pts, bay_out)
	var apron_cells := _trace_to_target(ext_cell, target_cell, apron_parent)
	var apron_pts := _build_apron_points(grid, bay_out, target, apron_cells, true)
	for i in range(1, apron_pts.size()):
		_append_unique_pt(pts, apron_pts[i])
	return {
		"ok": pts.size() >= 2,
		"bay_door_id": int(door_info["bay_door_id"]),
		"waypoints": pts,
		"bay_inside": bay_in,
		"bay_door": bay_door,
		"bay_outside": bay_out,
	}


## Plans a wall-clear polyline [origin, ..., target]: indoor bag rooms route
## exclusively through a valid baggage_bay_door (returning [] if none); exterior
## origins route across the apron with >= APRON_CLEAR_HALF_WIDTH_M clearance.
static func plan_route(grid: BuildGrid, origin: Vector3, target: Vector3) -> Array[Vector3]:
	if grid == null:
		return [origin, target]
	var origin_cell := grid.world_to_cell(origin)
	var target_cell := grid.world_to_cell(target)
	if grid.room_at(origin_cell) != 0 or grid.is_indoor(origin_cell):
		var room_res := plan_room_route(grid, origin, target)
		if bool(room_res["ok"]):
			var wp: Array[Vector3] = room_res["waypoints"]
			return wp
		return [] as Array[Vector3]
	if not grid.is_indoor(target_cell) and _apron_segment_clear(grid, origin, target):
		return [origin, target]
	var bounds := _search_bounds(grid, origin, target)
	var clamped_origin := _clamp_to_rect(origin_cell, bounds)
	var clamped_target := _clamp_to_rect(target_cell, bounds)
	var field := _apron_field(grid, bounds, clamped_target)
	var dist_from_target: Dictionary = field["dist"]
	if not dist_from_target.has(clamped_origin):
		return [] as Array[Vector3]
	var ext_cells := _trace_to_target(clamped_origin, clamped_target, field["parent"])
	return _build_apron_points(grid, origin, target, ext_cells, false)


## Plans an orthogonal exit polyline from an indoor position out through a valid
## Roll-Up Bay Door onto the apron (`outside_clear`), or [] if none is reachable.
static func exit_path_to_apron(grid: BuildGrid, from_pos: Vector3) -> Array[Vector3]:
	if grid == null:
		return []
	var from_cell := grid.world_to_cell(from_pos)
	var room_id := grid.room_at(from_cell)
	if room_id == 0:
		return []
	var room_rect: Rect2i = grid.get_room(room_id).get("rect", Rect2i())
	var doors := valid_bay_doors_in_room(grid, room_rect)
	if doors.is_empty():
		return []
	var room_bfs := _room_bfs(grid, from_cell, room_rect)
	var room_dist: Dictionary = room_bfs["dist"]
	var best_door := {}
	var best_cell := Vector2i.ZERO
	var best_cost := 1 << 29
	for door: Dictionary in doors:
		for c: Vector2i in door["cells"]:
			if room_dist.has(c) and int(room_dist[c]) < best_cost:
				best_cost = int(room_dist[c])
				best_door = door
				best_cell = c
	if best_door.is_empty():
		return []
	var pts := _room_waypoints(grid, from_pos, from_cell, best_cell, room_bfs["parent"])
	_append_unique_pt(pts, best_door["inside_clear"])
	_append_unique_pt(pts, best_door["door_center"])
	_append_unique_pt(pts, best_door["outside_clear"])
	return pts


## Plans an orthogonal entry polyline from outside `bay_door_id` into `target_pos`.
static func entry_path_from_apron(
	grid: BuildGrid, door_id: int, target_pos: Vector3
) -> Array[Vector3]:
	var anchors := bay_door_anchors(grid, door_id)
	if anchors.is_empty():
		return []
	var pts: Array[Vector3] = [
		anchors["outside_clear"],
		anchors["door_center"],
		anchors["inside_clear"],
	]
	var target_cell := grid.world_to_cell(target_pos)
	var room_id := grid.room_at(target_cell)
	if room_id != 0:
		var room_rect: Rect2i = grid.get_room(room_id).get("rect", Rect2i())
		var cells: Array = anchors["cells"]
		var start_cell: Vector2i = cells[0]
		var room_bfs := _room_bfs(grid, start_cell, room_rect)
		var dist: Dictionary = room_bfs["dist"]
		if dist.has(target_cell):
			var inside_pts := _room_waypoints(
				grid, anchors["inside_clear"], start_cell, target_cell, room_bfs["parent"]
			)
			for i in range(1, inside_pts.size()):
				_append_unique_pt(pts, inside_pts[i])
	_append_unique_pt(pts, target_pos)
	return pts


static func route_length(pts: Array[Vector3]) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
	return total


## True when segment `a -> b` crosses any grid wall edge (or clips a wall corner).
static func segment_hits_wall(
	grid: BuildGrid, a: Vector3, b: Vector3, allow_doors := false
) -> bool:
	if grid == null:
		return false
	var dist := Vector2(b.x - a.x, b.z - a.z).length()
	var steps := maxi(2, int(ceilf(dist / 0.25)))
	var prev := grid.world_to_cell(a)
	for i in range(1, steps + 1):
		var p := a.lerp(b, float(i) / float(steps))
		var cell := grid.world_to_cell(p)
		if cell == prev:
			continue
		if _step_walled(grid, prev, cell, allow_doors):
			return true
		prev = cell
	return false


func _entry_agent_pose(at_tick: int, grid: BuildGrid) -> Dictionary:
	var dest := (
		_cart_stand_pos(origin_world, pickup_world)
		if inbound
		else _end_stand_pos(pickup_world, origin_world)
	)
	var pts: Array[Vector3] = []
	for pt in [bay_outside_world, bay_door_world, bay_inside_world, dest]:
		if pt != Vector3.ZERO or pts.is_empty():
			_append_unique_pt(pts, pt)
	if pts.size() < 2:
		pts = [dest, dest]
	var span := maxi(1, transfer_start_tick - load_start_tick)
	var t := clampf(float(at_tick - load_start_tick) / float(span), 0.0, 1.0)
	var sample := _sample_path(pts, t, origin_yaw)
	var pos: Vector3 = sample["pos"]
	pos.y = ground_y(grid, pos)
	var speed := clampf(
		(
			(route_length(pts) / float(span) * SimClock.TICK_RATE)
			/ StaffCharacters.CLIP_WALK_MPS[StaffMember.Role.RAMP]
		),
		0.8,
		2.2,
	)
	return {"pos": pos, "yaw": float(sample["yaw"]), "clip": "walk", "speed": speed}


func _transfer_out_agent_pose(at_tick: int, grid: BuildGrid, bag_sim: BaggageSim) -> Dictionary:
	var end_world := _active_outbound_end_world(grid, bag_sim)
	var end_pos := _end_stand_pos(end_world, origin_world)
	var cart_pos := _cart_stand_pos(origin_world, end_world)
	var span := maxi(1, load_step_ticks)
	var leg_start := next_load_tick - span
	var t := clampf(float(at_tick - leg_start) / float(span), 0.0, 1.0)
	var carrying := not carried_bag_ids.is_empty()
	var from_pt := end_pos if carrying else cart_pos
	var to_pt := cart_pos if carrying else end_pos
	var pos := from_pt.lerp(to_pt, t)
	pos.y = ground_y(grid, pos)
	var dir := Vector2(to_pt.x - from_pt.x, to_pt.z - from_pt.z)
	var yaw := atan2(dir.x, dir.y) if dir.length_squared() > 1e-5 else origin_yaw
	var speed := clampf(
		(
			(dir.length() / float(span) * SimClock.TICK_RATE)
			/ StaffCharacters.CLIP_WALK_MPS[StaffMember.Role.RAMP]
		),
		0.8,
		2.4,
	)
	return {"pos": pos, "yaw": yaw, "clip": "walk", "speed": speed}


func _transfer_in_agent_pose(at_tick: int, grid: BuildGrid, bag_sim: BaggageSim) -> Dictionary:
	var drop_world := _active_inbound_end_world(grid, bag_sim)
	var drop_pos := _end_stand_pos(drop_world, origin_world)
	var cart_pos := _cart_stand_pos(origin_world, drop_world)
	var span := maxi(1, load_step_ticks)
	var leg_start := next_load_tick - span
	var t := clampf(float(at_tick - leg_start) / float(span), 0.0, 1.0)
	var carrying := not carried_bag_ids.is_empty()
	var from_pt := cart_pos if carrying else drop_pos
	var to_pt := drop_pos if carrying else cart_pos
	var pos := from_pt.lerp(to_pt, t)
	pos.y = ground_y(grid, pos)
	var dir := Vector2(to_pt.x - from_pt.x, to_pt.z - from_pt.z)
	var yaw := atan2(dir.x, dir.y) if dir.length_squared() > 1e-5 else origin_yaw
	var speed := clampf(
		(
			(dir.length() / float(span) * SimClock.TICK_RATE)
			/ StaffCharacters.CLIP_WALK_MPS[StaffMember.Role.RAMP]
		),
		0.8,
		2.4,
	)
	return {"pos": pos, "yaw": yaw, "clip": "walk", "speed": speed}


func _active_outbound_end_world(grid: BuildGrid, bag_sim: BaggageSim) -> Vector3:
	if bag_sim != null and grid != null:
		var bid := (
			carried_bag_ids[0]
			if not carried_bag_ids.is_empty()
			else (pending_bag_ids[0] if not pending_bag_ids.is_empty() else 0)
		)
		if bid > 0:
			var bag := bag_sim.get_bag(bid)
			if bag != null:
				var w := grid.cell_to_world(bag.cell)
				w.y = ground_y(grid, w)
				return w
	return pickup_world


func _active_inbound_end_world(grid: BuildGrid, bag_sim: BaggageSim) -> Vector3:
	if bag_sim != null and grid != null:
		var drop := BaggageInbound.drop_cell_for_shuttle(bag_sim, self)
		if drop != Vector2i(-1, -1):
			var w := grid.cell_to_world(drop)
			w.y = ground_y(grid, w)
			return w
	return pickup_world


static func _end_stand_pos(end_world: Vector3, cart_world: Vector3) -> Vector3:
	var flat := Vector2(cart_world.x - end_world.x, cart_world.z - end_world.z)
	if flat.length() <= AGENT_END_OFFSET_M + 0.05:
		return end_world
	var dir := flat.normalized() * AGENT_END_OFFSET_M
	return end_world + Vector3(dir.x, 0.0, dir.y)


static func _cart_stand_pos(cart_world: Vector3, end_world: Vector3) -> Vector3:
	var flat := Vector2(end_world.x - cart_world.x, end_world.z - cart_world.z)
	if flat.length() <= AGENT_SIDE_CART_M + 0.05:
		return cart_world
	var dir := flat.normalized() * AGENT_SIDE_CART_M
	return cart_world + Vector3(dir.x, 0.0, dir.y)


static func _room_bfs(grid: BuildGrid, origin_cell: Vector2i, room_rect: Rect2i) -> Dictionary:
	var room_dist := {origin_cell: 0}
	var room_parent := {}
	var queue: Array[Vector2i] = [origin_cell]
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		var d: int = room_dist[cur]
		for step in BuildGrid.SIDE_STEP:
			var nxt: Vector2i = cur + step
			if not room_rect.has_point(nxt) or room_dist.has(nxt):
				continue
			if _edge_walled(grid, cur, step, false):
				continue
			room_dist[nxt] = d + 1
			room_parent[nxt] = cur
			queue.append(nxt)
	return {"dist": room_dist, "parent": room_parent}


static func _pick_best_bay_door(
	doors: Array[Dictionary], room_dist: Dictionary, dist_from_target: Dictionary
) -> Dictionary:
	var best := {}
	for door: Dictionary in doors:
		var out_step: Vector2i = door["out_step"]
		for cell: Vector2i in door["cells"]:
			var ext: Vector2i = cell + out_step
			if not room_dist.has(cell) or not dist_from_target.has(ext):
				continue
			var score: int = int(room_dist[cell]) + 1 + int(dist_from_target[ext])
			if best.is_empty() or score < int(best["score"]):
				best = {"door": door, "inside": cell, "ext": ext, "score": score}
	return best


static func _append_unique_pt(pts: Array[Vector3], pt: Vector3) -> void:
	if pts.is_empty():
		pts.append(pt)
		return
	var last := pts[pts.size() - 1]
	if Vector2(last.x - pt.x, last.z - pt.z).length_squared() > 1e-4:
		pts.append(pt)


static func _step_walled(
	grid: BuildGrid, from_cell: Vector2i, to_cell: Vector2i, allow_doors := false
) -> bool:
	var diff := to_cell - from_cell
	if diff == Vector2i.ZERO:
		return false
	if absi(diff.x) + absi(diff.y) == 1:
		return _edge_walled(grid, from_cell, diff, allow_doors)
	if absi(diff.x) == 1 and absi(diff.y) == 1:
		var sx := Vector2i(diff.x, 0)
		var sy := Vector2i(0, diff.y)
		var via_x := (
			_edge_walled(grid, from_cell, sx, allow_doors)
			or _edge_walled(grid, from_cell + sx, sy, allow_doors)
		)
		var via_y := (
			_edge_walled(grid, from_cell, sy, allow_doors)
			or _edge_walled(grid, from_cell + sy, sx, allow_doors)
		)
		return via_x or via_y
	var steps := maxi(absi(diff.x), absi(diff.y)) * 2
	var wa := grid.cell_to_world(from_cell)
	var wb := grid.cell_to_world(to_cell)
	var prev := from_cell
	for i in range(1, steps + 1):
		var c := grid.world_to_cell(wa.lerp(wb, float(i) / float(steps)))
		if c != prev:
			if _step_walled(grid, prev, c, allow_doors):
				return true
			prev = c
	return false


static func _edge_walled(
	grid: BuildGrid, cell: Vector2i, step: Vector2i, allow_doors := false
) -> bool:
	var side := BuildGrid.SIDE_STEP.find(step)
	if side < 0:
		return false
	if grid.in_bounds(cell):
		var kind := grid.wall_kind(cell, side)
		if kind != BuildGrid.WallKind.NONE and (not allow_doors or kind != BuildGrid.WallKind.DOOR):
			return true
	var other := cell + step
	var opp := (side + 2) % 4
	if grid.in_bounds(other):
		var kind2 := grid.wall_kind(other, opp)
		if (
			kind2 != BuildGrid.WallKind.NONE
			and (not allow_doors or kind2 != BuildGrid.WallKind.DOOR)
		):
			return true
	return false


static func _search_bounds(grid: BuildGrid, origin: Vector3, target: Vector3) -> Rect2i:
	var area := grid.flood_area()
	var co := grid.world_to_cell(origin)
	var ct := grid.world_to_cell(target)
	var merged := Rect2i(co, Vector2i.ONE).merge(Rect2i(ct, Vector2i.ONE))
	if area.size != Vector2i.ZERO:
		merged = merged.merge(area)
	return merged.grow(ROUTE_PAD_CELLS).intersection(Rect2i(Vector2i.ZERO, grid.size))


static func _clamp_to_rect(cell: Vector2i, rect: Rect2i) -> Vector2i:
	return Vector2i(
		clampi(cell.x, rect.position.x, rect.end.x - 1),
		clampi(cell.y, rect.position.y, rect.end.y - 1)
	)


static func _apron_field(grid: BuildGrid, bounds: Rect2i, target_cell: Vector2i) -> Dictionary:
	var filter_indoor := not grid.is_indoor(target_cell)
	var dist := {target_cell: 0}
	var parent := {}
	var frontier: Array[Vector2i] = [target_cell]
	while not frontier.is_empty():
		var best_idx := 0
		var best_cost: int = dist[frontier[0]]
		for i in range(1, frontier.size()):
			var c: int = dist[frontier[i]]
			if c < best_cost:
				best_cost = c
				best_idx = i
		var cur: Vector2i = frontier[best_idx]
		frontier.remove_at(best_idx)
		var d: int = dist[cur]
		for step in BuildGrid.SIDE_STEP:
			var nxt: Vector2i = cur + step
			if not bounds.has_point(nxt):
				continue
			if (filter_indoor and grid.is_indoor(nxt)) or _edge_walled(grid, cur, step, false):
				continue
			var step_cost := 4 if _touches_any_wall(grid, nxt) else 1
			var cand := d + step_cost
			if cand < int(dist.get(nxt, 1 << 29)):
				dist[nxt] = cand
				parent[nxt] = cur
				frontier.append(nxt)
	return {"dist": dist, "parent": parent}


static func _touches_any_wall(grid: BuildGrid, cell: Vector2i) -> bool:
	if not grid.in_bounds(cell):
		return false
	for side in 4:
		if grid.has_wall(cell, side):
			return true
	return false


static func _trace_to_target(
	start_cell: Vector2i, target_cell: Vector2i, parent: Dictionary
) -> Array[Vector2i]:
	var path: Array[Vector2i] = [start_cell]
	var cur := start_cell
	while cur != target_cell and parent.has(cur):
		cur = parent[cur]
		path.append(cur)
	return path


static func _room_waypoints(
	grid: BuildGrid,
	origin: Vector3,
	origin_cell: Vector2i,
	inside_cell: Vector2i,
	room_parent: Dictionary,
) -> Array[Vector3]:
	if inside_cell == origin_cell:
		return [origin]
	var rev: Array[Vector2i] = []
	var walk := inside_cell
	while walk != origin_cell:
		rev.append(walk)
		walk = room_parent[walk]
	rev.append(origin_cell)
	rev.reverse()
	var raw: Array[Vector3] = [origin]
	for i in range(1, rev.size()):
		var w := grid.cell_to_world(rev[i])
		w.y = origin.y
		raw.append(w)
	var smoothed: Array[Vector3] = [raw[0]]
	var idx := 0
	while idx < raw.size() - 1:
		var furthest := idx + 1
		for cand in range(raw.size() - 1, idx, -1):
			if not segment_hits_wall(grid, raw[idx], raw[cand], false):
				furthest = cand
				break
		smoothed.append(raw[furthest])
		idx = furthest
	return smoothed


static func _build_apron_points(
	grid: BuildGrid, start_world: Vector3, target: Vector3, cells: Array[Vector2i], keep_start: bool
) -> Array[Vector3]:
	var raw: Array[Vector3] = [start_world]
	for i in range(1, cells.size()):
		var w := grid.cell_to_world(cells[i])
		w.y = start_world.y
		raw.append(w)
	if Vector2(raw[raw.size() - 1].x - target.x, raw[raw.size() - 1].z - target.z).length() > 0.05:
		raw.append(target)
	var smoothed: Array[Vector3] = [raw[0]]
	var idx := 0
	while idx < raw.size() - 1:
		var furthest := idx + 1
		for cand in range(raw.size() - 1, idx, -1):
			if _apron_segment_clear(grid, raw[idx], raw[cand]):
				furthest = cand
				break
		smoothed.append(raw[furthest])
		idx = furthest
	if keep_start or smoothed.size() >= 2:
		return smoothed
	return [start_world, target]


static func _apron_segment_clear(grid: BuildGrid, a: Vector3, b: Vector3) -> bool:
	if segment_hits_wall(grid, a, b, false) or _segment_hits_indoor(grid, a, b):
		return false
	var flat := Vector2(b.x - a.x, b.z - a.z)
	if flat.length_squared() <= 0.01:
		return true
	var perp := Vector2(-flat.y, flat.x).normalized() * APRON_CLEAR_HALF_WIDTH_M
	var offset := Vector3(perp.x, 0.0, perp.y)
	return (
		not segment_hits_wall(grid, a + offset, b + offset, false)
		and not segment_hits_wall(grid, a - offset, b - offset, false)
		and not _segment_hits_indoor(grid, a + offset, b + offset)
		and not _segment_hits_indoor(grid, a - offset, b - offset)
	)


static func _segment_hits_indoor(grid: BuildGrid, a: Vector3, b: Vector3) -> bool:
	if grid == null:
		return false
	var dist := Vector2(b.x - a.x, b.z - a.z).length()
	var steps := maxi(2, int(ceilf(dist / 0.25)))
	for i in steps + 1:
		var p := a.lerp(b, float(i) / float(steps))
		if grid.is_indoor(grid.world_to_cell(p)):
			return true
	return false


static func _sample_path(pts: Array[Vector3], t: float, fallback_yaw: float) -> Dictionary:
	var total := route_length(pts)
	if total <= 0.001:
		return {"pos": pts[0], "yaw": fallback_yaw}
	var want := clampf(t, 0.0, 1.0) * total
	var covered := 0.0
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var flat := Vector2(b.x - a.x, b.z - a.z)
		var seg := flat.length()
		if seg <= 0.0001:
			continue
		if covered + seg >= want or i == pts.size() - 1:
			var local_t := clampf((want - covered) / seg, 0.0, 1.0)
			return {"pos": a.lerp(b, local_t), "yaw": atan2(flat.x, flat.y)}
		covered += seg
	return {"pos": pts[pts.size() - 1], "yaw": fallback_yaw}


static func _blend_yaw(from_yaw: float, travel_yaw: float, to_yaw: float, t: float) -> float:
	if t < 0.15:
		return lerp_angle(from_yaw, travel_yaw, t / 0.15)
	if t > 0.85:
		return lerp_angle(travel_yaw, to_yaw, (t - 0.85) / 0.15)
	return travel_yaw
