class_name FoundationDrag
extends RefCounted
## Expand Terminal / Foundation Drag (`BuildMode.Tool.FOUNDATION`):
## lays missing terminal floor tiles, removes shared exterior seam walls
## (preserving rooms, glass walls, and standing doors), and adds new outer
## plain perimeter walls atomically in one composite commit and one undo step.

const DOOR_SEAL_REFUSAL := "Move the entrance, exit, or bay door before expanding through it"

static var _cache_key := ""
static var _cache_base: Plan = null


## What a Foundation drag over `rect` would do, staged on a trial grid.
class Plan:
	extends RefCounted
	var rect := Rect2i()
	var ok := true
	var nothing_to_place := false
	var refusal: BuildResult = null
	var refusal_text := ""
	var edits: Array[BuildEdit] = []
	var new_cells: Array[Vector2i] = []
	var outer_wall_edits: Array[BuildEdit] = []
	var seam_wall_edits: Array[BuildEdit] = []
	var refused_cells: Array[Vector2i] = []
	var refused_edges: Array[Vector3i] = []
	var touched_cells: Array[Vector2i] = []
	var placed_floors := 0
	var skipped := 0
	var unchanged := 0
	var first_reason := ""
	var net_cost := 0
	var has_price := false

	func status_label(has_wallet: bool) -> String:
		return BuildWords.foundation_drag_label(
			rect.size.x,
			rect.size.y,
			net_cost,
			has_wallet,
			nothing_to_place,
			"" if ok else refusal_text,
			skipped,
			first_reason
		)


## What applying a Foundation drag did, extending AreaDrag.Outcome for BuildDrags.
class Outcome:
	extends AreaDrag.Outcome
	var ok := true
	var refusal_text := ""
	var net_cost := 0
	var placed_floors := 0
	var placed_walls := 0
	var removed_seams := 0
	var touched_cells: Array[Vector2i] = []
	var result: BuildResult = null

	func message() -> String:
		if not ok:
			return refusal_text
		if placed == 0 and skipped == 0:
			return BuildWords.foundation_nothing()
		var text := "Placed %d" % placed
		if net_cost > 0:
			text += " for %d" % net_cost
		elif net_cost < 0:
			text += ", refund %d" % (-net_cost)
		if skipped > 0:
			text += ", skipped %d: %s" % [skipped, first_reason]
		return text


## Cached plan for hover ghosts and BuildMenu cost preview; keyed by grid state + rect.
static func plan_cached(grid: BuildGrid, rect: Rect2i, wallet: Wallet = null) -> Plan:
	if grid == null:
		return _build_base_plan(grid, rect)
	var key := _make_cache_key(grid, rect)
	if key != _cache_key or _cache_base == null:
		_cache_key = key
		_cache_base = _build_base_plan(grid, rect)
	return _with_wallet(_cache_base, wallet)


## Plans a Foundation drag over `rect` against `grid` and `wallet` without mutating either.
static func plan(grid: BuildGrid, rect: Rect2i, wallet: Wallet = null) -> Plan:
	return _with_wallet(_build_base_plan(grid, rect), wallet)


## Returns `Vector2i(net_cost, needed_cost)` for BuildMenuPrices while dragging `FOUNDATION`.
static func preview_price(mode: BuildMode) -> Vector2i:
	if mode == null or mode.grid == null or not mode._area.active:
		return Vector2i.ZERO
	var p := plan_cached(mode.grid, mode._area.rect(), mode.wallet())
	if not p.has_price or p.net_cost <= 0:
		return Vector2i.ZERO
	return Vector2i(p.net_cost, p.net_cost)


## Applies Foundation drag over `rect` atomically via BuildTransaction.commit_composite().
static func apply(grid: BuildGrid, rect: Rect2i, wallet: Wallet = null) -> Outcome:
	var p := _build_base_plan(grid, rect)
	p = _with_wallet(p, wallet)
	var outcome := Outcome.new()
	outcome.unchanged = p.unchanged
	outcome.skipped = p.skipped
	outcome.first_reason = p.first_reason
	outcome.touched_cells = p.touched_cells.duplicate()
	if p.nothing_to_place:
		return outcome
	if not p.ok:
		outcome.ok = false
		outcome.result = p.refusal
		outcome.refusal_text = p.refusal_text
		if p.refusal != null and not p.edits.is_empty():
			var edit := p.edits[0]
			var refusal := p.refusal
			grid._emit_or_hold(func() -> void: grid.edit_refused.emit(edit, refusal))
		return outcome
	var before_bal := wallet.balance if wallet != null else 0
	var res := BuildTransaction.commit_composite(grid, p.edits, wallet)
	outcome.result = res
	if not res.ok:
		outcome.ok = false
		outcome.refusal_text = res.reason_text()
		return outcome
	outcome.placed = p.placed_floors
	outcome.placed_floors = p.placed_floors
	outcome.placed_walls = p.outer_wall_edits.size()
	outcome.removed_seams = p.seam_wall_edits.size()
	if wallet != null:
		outcome.net_cost = before_bal - wallet.balance
		outcome.money = absi(outcome.net_cost)
		outcome.charged = outcome.net_cost >= 0
	return outcome


static func _build_base_plan(grid: BuildGrid, rect: Rect2i) -> Plan:
	var p := Plan.new()
	p.rect = rect
	if (
		grid == null
		or not rect.has_area()
		or not grid.in_bounds(rect.position)
		or not grid.in_bounds(rect.end - Vector2i.ONE)
	):
		p.ok = false
		p.refusal = BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
		p.refusal_text = p.refusal.reason_text()
		return p
	var raw_new_cells: Array[Vector2i] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			if grid.floor_at(cell) == BuildGrid.FLOOR_NONE:
				raw_new_cells.append(cell)
			else:
				p.unchanged += 1
	if raw_new_cells.is_empty():
		p.ok = true
		p.nothing_to_place = true
		return p
	var sealed := _sealed_door_cells(grid, raw_new_cells)
	if not sealed.is_empty():
		p.ok = false
		p.refusal = BuildResult.refused(BuildResult.Reason.DOOR_NOT_ON_EDGE)
		p.refusal_text = BuildWords.foundation_door_seal()
		p.refused_cells = sealed
		return p
	var trial := BuildUndo.trial_copy_of(grid)
	var accepted_set := {}
	var floor_edits: Array[BuildEdit] = []
	var first_floor_refusal: BuildResult = null
	for cell in raw_new_cells:
		var edit := BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, BuildMode.TERMINAL_ZONE)
		var res := _try_stage_edit(trial, edit)
		if res.ok:
			accepted_set[cell] = true
			p.new_cells.append(cell)
			floor_edits.append(edit)
		else:
			p.skipped += 1
			if p.first_reason == "":
				p.first_reason = res.reason_text()
			if first_floor_refusal == null:
				first_floor_refusal = res
			p.refused_cells.append(cell)
	if p.new_cells.is_empty():
		p.ok = false
		p.refusal = first_floor_refusal
		p.refusal_text = p.first_reason
		p.skipped = 0
		p.first_reason = ""
		return p
	var seam_door_candidates: Array[BuildEdit] = []
	var seam_plain_candidates: Array[BuildEdit] = []
	var outer_candidates: Array[BuildEdit] = []
	_collect_edge_candidates(
		grid,
		p.new_cells,
		accepted_set,
		seam_door_candidates,
		seam_plain_candidates,
		outer_candidates
	)
	p.edits.append_array(floor_edits)
	_stage_edge_list(trial, seam_door_candidates, p.edits, p.seam_wall_edits, p)
	_stage_edge_list(trial, seam_plain_candidates, p.edits, p.seam_wall_edits, p)
	_stage_edge_list(trial, outer_candidates, p.edits, p.outer_wall_edits, p)
	var preview := BuildTransaction.preview_composite(grid, p.edits)
	var preview_res: BuildResult = preview["result"]
	if not preview_res.ok:
		p.ok = false
		p.refusal = preview_res
		p.refusal_text = preview_res.reason_text()
	else:
		p.net_cost = int(preview["net"])
		p.has_price = true
	p.placed_floors = p.new_cells.size()
	p.touched_cells = _collect_touched_cells(grid, rect, p.edits)
	return p


static func _sealed_door_cells(grid: BuildGrid, cells: Array[Vector2i]) -> Array[Vector2i]:
	var sealed: Array[Vector2i] = []
	for cell in cells:
		if DoorPlacement.beyond_a_door(grid, cell) or DoorPlacement.beyond_a_bay_door(grid, cell):
			sealed.append(cell)
	return sealed


static func _collect_edge_candidates(
	grid: BuildGrid,
	new_cells: Array[Vector2i],
	accepted_set: Dictionary,
	seam_doors: Array[BuildEdit],
	seam_plains: Array[BuildEdit],
	outer_walls: Array[BuildEdit]
) -> void:
	var seen_edges := {}
	for cell in new_cells:
		for side in 4:
			var other: Vector2i = cell + BuildGrid.SIDE_STEP[side]
			if not grid.in_bounds(other) or not _will_be_floored(grid, other, accepted_set):
				_maybe_add_outer_wall(grid, cell, side, outer_walls)
				continue
			var key := _edge_key(cell, side)
			if seen_edges.has(key):
				continue
			seen_edges[key] = true
			if (
				_will_be_terminal(grid, cell, accepted_set)
				and _will_be_terminal(grid, other, accepted_set)
				and grid.room_at(cell) == 0
				and grid.room_at(other) == 0
				and not DoorPlacement.on_a_way_out(grid, cell, side)
			):
				var kind := grid.wall_kind(cell, side)
				if kind == BuildGrid.WallKind.DOOR:
					seam_doors.append(BuildEdit.remove_wall(cell, side))
				elif kind == BuildGrid.WallKind.PLAIN:
					seam_plains.append(BuildEdit.remove_wall(cell, side))


static func _maybe_add_outer_wall(
	grid: BuildGrid, cell: Vector2i, side: int, out: Array[BuildEdit]
) -> void:
	if grid.wall_kind(cell, side) != BuildGrid.WallKind.NONE:
		return
	if DoorPlacement.on_a_way_out(grid, cell, side):
		return
	if DoorPlacement._on_bay_approach_wall(grid, cell, side):
		return
	out.append(BuildEdit.place_wall(cell, side, BuildGrid.WallKind.PLAIN))


static func _stage_edge_list(
	trial: BuildGrid,
	candidates: Array[BuildEdit],
	all_edits: Array[BuildEdit],
	bucket: Array[BuildEdit],
	p: Plan
) -> void:
	for edit in candidates:
		var res := _try_stage_edit(trial, edit)
		if res.ok:
			all_edits.append(edit)
			bucket.append(edit)
		else:
			p.skipped += 1
			if p.first_reason == "":
				p.first_reason = res.reason_text()
			p.refused_edges.append(Vector3i(edit.cell.x, edit.cell.y, edit.side))


static func _try_stage_edit(trial: BuildGrid, edit: BuildEdit) -> BuildResult:
	var problem := BuildTransaction.composite_rule(trial, edit)
	if problem != null:
		return problem
	return trial.apply(edit)


static func _will_be_floored(grid: BuildGrid, cell: Vector2i, accepted_set: Dictionary) -> bool:
	return (
		accepted_set.has(cell)
		or (grid.in_bounds(cell) and grid.floor_at(cell) != BuildGrid.FLOOR_NONE)
	)


static func _will_be_terminal(grid: BuildGrid, cell: Vector2i, accepted_set: Dictionary) -> bool:
	if accepted_set.has(cell):
		return true
	return (
		grid.in_bounds(cell)
		and grid.floor_at(cell) != BuildGrid.FLOOR_NONE
		and grid.zone_at(cell) == BuildMode.TERMINAL_ZONE
	)


static func _edge_key(cell: Vector2i, side: int) -> Vector3i:
	match side:
		BuildGrid.Side.SOUTH:
			return Vector3i(cell.x, cell.y + 1, BuildGrid.Side.NORTH)
		BuildGrid.Side.EAST:
			return Vector3i(cell.x + 1, cell.y, BuildGrid.Side.WEST)
	return Vector3i(cell.x, cell.y, side)


static func _collect_touched_cells(
	grid: BuildGrid, rect: Rect2i, edits: Array[BuildEdit]
) -> Array[Vector2i]:
	var seen := {}
	var out: Array[Vector2i] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c := Vector2i(x, y)
			if grid.in_bounds(c) and not seen.has(c):
				seen[c] = true
				out.append(c)
	for edit in edits:
		if grid.in_bounds(edit.cell) and not seen.has(edit.cell):
			seen[edit.cell] = true
			out.append(edit.cell)
		if edit.kind == BuildEdit.Kind.REMOVE_WALL or edit.kind == BuildEdit.Kind.PLACE_WALL:
			var other := edit.cell + BuildGrid.SIDE_STEP[edit.side]
			if grid.in_bounds(other) and not seen.has(other):
				seen[other] = true
				out.append(other)
	return out


static func _with_wallet(base: Plan, wallet: Wallet) -> Plan:
	if wallet == null or not base.ok or base.nothing_to_place:
		return base
	if base.net_cost > 0 and not wallet.can_afford(base.net_cost):
		return _refused_copy(base, BuildResult.refused(BuildResult.Reason.CANT_AFFORD))
	if base.net_cost < 0 and not wallet.can_credit(-base.net_cost, Wallet.Category.BUILD):
		return _refused_copy(base, BuildResult.refused(BuildResult.Reason.WALLET_FULL))
	return base


static func _refused_copy(base: Plan, refusal: BuildResult) -> Plan:
	var out := Plan.new()
	out.rect = base.rect
	out.ok = false
	out.nothing_to_place = base.nothing_to_place
	out.refusal = refusal
	out.refusal_text = refusal.reason_text()
	out.edits = base.edits
	out.new_cells = base.new_cells
	out.outer_wall_edits = base.outer_wall_edits
	out.seam_wall_edits = base.seam_wall_edits
	out.refused_cells = base.refused_cells
	out.refused_edges = base.refused_edges
	out.touched_cells = base.touched_cells
	out.placed_floors = base.placed_floors
	out.skipped = base.skipped
	out.unchanged = base.unchanged
	out.first_reason = base.first_reason
	out.net_cost = base.net_cost
	out.has_price = base.has_price
	return out


static func _make_cache_key(grid: BuildGrid, rect: Rect2i) -> String:
	return (
		"%d:%s:%d:%d:%d:%d"
		% [
			grid.get_instance_id(),
			rect,
			grid.floor_version(),
			grid.wall_version(),
			grid.route_version(),
			room_sig(grid),
		]
	)


static func room_sig(grid: BuildGrid) -> int:
	var h := 17
	for rid in grid.room_ids():
		var r: Rect2i = grid.get_room(rid).get("rect", Rect2i())
		h = h * 31 + rid + r.position.x * 7 + r.position.y * 13 + r.size.x * 19 + r.size.y * 23
	return h
