class_name WallRowDrag
extends RefCounted
## The straight row the Wall and Glass tools drag. A press starts it on a cell
## with the edge side the press was nearest to; the far end follows the
## pointer's cell and the row runs along whichever axis the drag has moved
## further (a tie goes along x), from the press cell, one edge in each cell. A
## row along x is a horizontal wall (NORTH or SOUTH edges), a row along z a
## vertical one (WEST or EAST edges); a press nearest the other kind of edge
## is turned toward the same corner (NORTH and WEST are the near edges, SOUTH
## and EAST the far ones). A row that never left its cell keeps the pressed
## side, so a click lays the edge it was nearest to. Release applies it once,
## in one undo step, with apply(): every edge the rules accept is placed and
## the rest are skipped, and a row that runs out of money stops at that edge.
## BuildMode owns the input and the ghost; this class owns the cells and what
## applying or previewing them does.


## What previewing a row says: per edge whether it would be placed, what the
## placed ones cost and why the first skipped one is skipped.
class Preview:
	extends RefCounted
	var edits: Array[BuildEdit] = []
	var valid: Array[bool] = []
	var cost := 0
	var blocked := 0
	var first_reason := ""


var active := false
## The BuildGrid.Side every edge of the row is on: the pressed side, turned to
## the drag axis once the row has left its cell.
var side: int:
	get:
		return _row_side()

var _press_side := 0
var _start := Vector2i.ZERO
var _end := Vector2i.ZERO
var _limit := Vector2i.ZERO


## Applies `edits` in order, each through `check` (a Callable taking a
## BuildEdit and returning a BuildResult: BuildMode.check) and then
## BuildTransaction.commit_plan(), so each keeps the door and money rules. An
## edge `check` refuses is skipped; one refused for money ends the row, and it
## and every edge after it count as skipped. The grid's signals go out once at
## the end. `dirty` receives the cells the placed edges changed. The caller
## opens the undo action around the call.
static func apply(
	grid: BuildGrid,
	edits: Array[BuildEdit],
	check: Callable,
	wallet: Wallet,
	dirty: Array[Vector2i]
) -> AreaDrag.Outcome:
	var outcome := AreaDrag.Outcome.new()
	var before := wallet.balance if wallet != null else 0
	grid.hold_signals()
	grid.begin_batch()
	var was_cleared := grid._reach_cleared
	if not was_cleared and grid.check_staff_reach:
		grid._reach_cleared = GridReach.batch_keeps_reach(grid, edits)
	for i in edits.size():
		var edit := edits[i]
		var result: BuildResult = check.call(edit)
		if result.ok:
			result = BuildTransaction.commit_plan(grid, DoorPlacement.edits_for(grid, edit), wallet)
		else:
			# Through the grid's hold queue, behind the edits already applied.
			var refusal := result
			grid._emit_or_hold(func() -> void: grid.edit_refused.emit(edit, refusal))
		if result.ok:
			outcome.placed += 1
			dirty.append_array(result.dirty_cells)
			continue
		if outcome.first_reason == "":
			outcome.first_reason = result.reason_text()
		if result.reason == BuildResult.Reason.CANT_AFFORD:
			outcome.skipped += edits.size() - i
			break
		outcome.skipped += 1
	grid._reach_cleared = was_cleared
	grid.end_batch()
	grid.release_signals()
	if wallet != null:
		outcome.money = absi(wallet.balance - before)
	return outcome


## What apply() would do with `edits` against the grid and wallet as they
## stand now: each edge `check` accepts is valid while the running cost still
## fits the wallet (a null wallet builds free), and the row stops being valid
## from the first one that does not.
static func preview(
	grid: BuildGrid, edits: Array[BuildEdit], check: Callable, wallet: Wallet
) -> Preview:
	var report := Preview.new()
	report.edits = edits
	var stopped := false
	var was_cleared := grid._reach_cleared
	if not was_cleared and grid.check_staff_reach:
		grid._reach_cleared = GridReach.batch_keeps_reach(grid, edits)
	for edit in edits:
		var result: BuildResult = check.call(edit)
		var edge_cost := 0
		if result.ok and wallet != null:
			edge_cost = BuildTransaction.needed(grid, DoorPlacement.edits_for(grid, edit))
			if report.cost + edge_cost > wallet.balance:
				result = BuildResult.refused(BuildResult.Reason.CANT_AFFORD)
		if result.reason == BuildResult.Reason.CANT_AFFORD:
			stopped = true
		var valid := result.ok and not stopped
		report.valid.append(valid)
		if valid:
			report.cost += edge_cost
			continue
		report.blocked += 1
		if report.first_reason == "":
			report.first_reason = result.reason_text()
	grid._reach_cleared = was_cleared
	return report


## Starts a row on `cell`, on the `edge_side` the press was nearest to.
## `grid_size` bounds the row.
func begin(cell: Vector2i, edge_side: int, grid_size: Vector2i) -> void:
	active = true
	_press_side = edge_side
	_limit = grid_size
	_start = cell
	_end = cell


## Moves the far end to `cell`, kept inside the grid.
func move(cell: Vector2i) -> void:
	_end = cell.clamp(Vector2i.ZERO, _limit - Vector2i.ONE)


func cancel() -> void:
	active = false


func is_single_cell() -> bool:
	return _start == _end


func _row_side() -> int:
	if is_single_cell():
		return _press_side
	var near := _press_side == BuildGrid.Side.NORTH or _press_side == BuildGrid.Side.WEST
	if _along_x():
		return BuildGrid.Side.NORTH if near else BuildGrid.Side.SOUTH
	return BuildGrid.Side.WEST if near else BuildGrid.Side.EAST


## Whether the row runs along x: the drag moved at least as far in x as in z.
func _along_x() -> bool:
	var span := _end - _start
	return absi(span.y) <= absi(span.x)


## The cells of the row from the press cell to the far end along the longer
## axis of the drag, both included.
func cells() -> Array[Vector2i]:
	var span := _end - _start
	var step := Vector2i(signi(span.x), 0)
	var count := absi(span.x)
	if not _along_x():
		step = Vector2i(0, signi(span.y))
		count = absi(span.y)
	var row: Array[Vector2i] = []
	for i in count + 1:
		row.append(_start + step * i)
	return row


## One wall of `kind` (a BuildGrid.WallKind) on the row's side in each cell.
func edits(kind: int) -> Array[BuildEdit]:
	var result: Array[BuildEdit] = []
	for cell in cells():
		result.append(BuildEdit.place_wall(cell, side, kind))
	return result


## The cell the drag started on.
func start_cell() -> Vector2i:
	return _start


## The last cell of the row.
func end_cell() -> Vector2i:
	return cells().back()


## Wall-remove drag in Tool.REMOVE: started when a press hits a wall edge,
## follows a straight H/V wall line or L-path along wall edges, previews all
## matching walls for removal, and deletes them atomically in one undo step
## without touching floor tiles.
class RemoveDrag:
	extends RefCounted
	var active := false
	var press_point := Vector3.ZERO
	var end_point := Vector3.ZERO

	var _axis := 0
	var _start_line := 0
	var _start_pos := 0
	var _end_pos := 0
	var _perp_line := -1
	var _end_perp := 0
	var _limit := Vector2i.ZERO

	func begin(grid_size: Vector2i, cell: Vector2i, edge_side: int, point: Vector3) -> void:
		active = true
		press_point = point
		end_point = point
		_limit = grid_size
		_perp_line = -1
		if edge_side == BuildGrid.Side.NORTH or edge_side == BuildGrid.Side.SOUTH:
			_axis = 0
			_start_line = cell.y if edge_side == BuildGrid.Side.NORTH else cell.y + 1
			_start_pos = cell.x
			_end_pos = cell.x
		else:
			_axis = 1
			_start_line = cell.x if edge_side == BuildGrid.Side.WEST else cell.x + 1
			_start_pos = cell.y
			_end_pos = cell.y

	func cancel() -> void:
		active = false

	func move(grid: BuildGrid, point: Vector3, wall_edge: Vector3i) -> void:
		end_point = point
		var local := Vector2(point.x - grid.origin.x, point.z - grid.origin.z)
		if wall_edge.z >= 0:
			var w := _edge_coords(wall_edge)
			if w[0] == _axis and w[1] == _start_line:
				_end_pos = clampi(w[2], 0, _limit[_axis] - 1)
				_perp_line = -1
				return
			if w[0] != _axis:
				_perp_line = w[1]
				if _perp_line > _start_pos:
					_end_pos = clampi(_perp_line - 1, 0, _limit[_axis] - 1)
				else:
					_end_pos = clampi(_perp_line, 0, _limit[_axis] - 1)
				_end_perp = clampi(w[2], 0, _limit[1 - _axis] - 1)
				return
		var pos := clampi(floori(local[_axis]), 0, _limit[_axis] - 1)
		var perp := local[1 - _axis]
		_end_pos = pos
		if absf(perp - float(_start_line)) < 1.0:
			_perp_line = -1
			return
		if pos > _start_pos:
			_perp_line = pos + 1
		elif pos < _start_pos:
			_perp_line = pos
		else:
			_perp_line = (_start_pos + 1 if local[_axis] >= float(_start_pos) + 0.5 else _start_pos)
		_perp_line = clampi(_perp_line, 0, _limit[_axis])
		_end_perp = clampi(floori(perp), 0, _limit[1 - _axis] - 1)

	func edges(grid: BuildGrid) -> Array[Vector3i]:
		var out: Array[Vector3i] = []
		var seen := {}
		var step1 := 1 if _end_pos >= _start_pos else -1
		for p in range(_start_pos, _end_pos + step1, step1):
			_append_if_wall(grid, _axis, _start_line, p, seen, out)
		if _perp_line >= 0:
			var start2 := _start_line if _end_perp >= _start_line else _start_line - 1
			var step2 := 1 if _end_perp >= _start_line else -1
			for q in range(start2, _end_perp + step2, step2):
				_append_if_wall(grid, 1 - _axis, _perp_line, q, seen, out)
		return out

	func edits(grid: BuildGrid) -> Array[BuildEdit]:
		var doors: Array[BuildEdit] = []
		var walls: Array[BuildEdit] = []
		for edge in edges(grid):
			var cell := Vector2i(edge.x, edge.y)
			var edit := BuildEdit.remove_wall(cell, edge.z)
			if grid.wall_kind(cell, edge.z) == BuildGrid.WallKind.DOOR:
				doors.append(edit)
			else:
				walls.append(edit)
		var out: Array[BuildEdit] = []
		out.append_array(doors)
		out.append_array(walls)
		return out

	func end_cell(grid: BuildGrid) -> Vector2i:
		return grid.world_to_cell(end_point)

	static func preview(
		grid: BuildGrid, edge_list: Array[Vector3i], check: Callable, wallet: Wallet = null
	) -> Preview:
		var report := Preview.new()
		if edge_list.is_empty():
			return report
		var scratch := BuildUndo.trial_copy_of(grid)
		var results := {}
		var door_edges: Array[Vector3i] = []
		var other_edges: Array[Vector3i] = []
		for edge in edge_list:
			var c := Vector2i(edge.x, edge.y)
			if grid.wall_kind(c, edge.z) == BuildGrid.WallKind.DOOR:
				door_edges.append(edge)
			else:
				other_edges.append(edge)
		for edge in door_edges:
			results[edge] = _preview_edge(scratch, edge, check)
		for edge in other_edges:
			results[edge] = _preview_edge(scratch, edge, check)
		for edge in edge_list:
			var cell := Vector2i(edge.x, edge.y)
			var edit := BuildEdit.remove_wall(cell, edge.z)
			report.edits.append(edit)
			var res: BuildResult = results[edge]
			report.valid.append(res.ok)
			if res.ok:
				report.cost += PriceTable.refund_of(grid.wall_paid(cell, edge.z))
			else:
				report.blocked += 1
				if report.first_reason == "":
					report.first_reason = res.reason_text()
		if (
			wallet != null
			and report.cost > 0
			and not wallet.can_credit(report.cost, Wallet.Category.BUILD)
		):
			var full := BuildResult.refused(BuildResult.Reason.WALLET_FULL)
			report.first_reason = full.reason_text()
			report.blocked = report.edits.size()
			report.cost = 0
			for i in report.valid.size():
				report.valid[i] = false
		return report

	static func _preview_edge(scratch: BuildGrid, edge: Vector3i, check: Callable) -> BuildResult:
		var cell := Vector2i(edge.x, edge.y)
		var edit := BuildEdit.remove_wall(cell, edge.z)
		var res := scratch.apply(edit)
		if res.ok and check.is_valid():
			var extra: BuildResult = check.call(edit)
			if not extra.ok and extra.reason != BuildResult.Reason.WALL_HOLDS_DOOR:
				res = extra
		return res

	static func apply(
		grid: BuildGrid,
		ordered_edits: Array[BuildEdit],
		_check: Callable,
		wallet: Wallet,
		dirty: Array[Vector2i]
	) -> AreaDrag.Outcome:
		var outcome := AreaDrag.Outcome.new()
		outcome.removing = true
		if ordered_edits.is_empty():
			return outcome
		var before := wallet.balance if wallet != null else 0
		var result := BuildTransaction.commit_composite(grid, ordered_edits, wallet)
		if result.ok:
			outcome.placed = ordered_edits.size()
			dirty.append_array(result.dirty_cells)
			if wallet != null:
				outcome.money = absi(wallet.balance - before)
				outcome.charged = wallet.balance < before
		else:
			outcome.skipped = ordered_edits.size()
			outcome.first_reason = result.reason_text()
		return outcome

	static func _edge_coords(edge: Vector3i) -> Array[int]:
		match edge.z:
			BuildGrid.Side.NORTH:
				return [0, edge.y, edge.x]
			BuildGrid.Side.SOUTH:
				return [0, edge.y + 1, edge.x]
			BuildGrid.Side.WEST:
				return [1, edge.x, edge.y]
		return [1, edge.x + 1, edge.y]

	static func _append_if_wall(
		grid: BuildGrid, axis: int, line: int, pos: int, seen: Dictionary, out: Array[Vector3i]
	) -> void:
		if pos < 0 or line < 0:
			return
		var cell: Vector2i
		var edge_side: int
		if axis == 0:
			if pos >= grid.size.x or line > grid.size.y:
				return
			cell = Vector2i(pos, line) if line < grid.size.y else Vector2i(pos, line - 1)
			edge_side = BuildGrid.Side.NORTH if line < grid.size.y else BuildGrid.Side.SOUTH
		else:
			if pos >= grid.size.y or line > grid.size.x:
				return
			cell = Vector2i(line, pos) if line < grid.size.x else Vector2i(line - 1, pos)
			edge_side = BuildGrid.Side.WEST if line < grid.size.x else BuildGrid.Side.EAST
		var key := Vector3i(cell.x, cell.y, edge_side)
		if seen.has(key) or not grid.has_wall(cell, edge_side):
			return
		seen[key] = true
		out.append(key)
