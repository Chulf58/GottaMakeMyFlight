class_name WallRowDrag
extends RefCounted
## The straight row the Wall and Glass tools drag. A press starts it on a cell
## with the edge side the press was nearest to; the far end follows the
## pointer's cell and the row runs along whichever axis the drag has moved
## further (a tie goes along x), from the press cell, one edge of that side in
## each cell. Release applies it once, in one undo step, with apply(): every
## edge the rules accept is placed and the rest are skipped, and a row that
## runs out of money stops at that edge. BuildMode owns the input and the
## ghost; this class owns the cells and what applying or previewing them does.


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
## The BuildGrid.Side every edge of the row is on.
var side := 0

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
	for i in edits.size():
		var edit := edits[i]
		var result: BuildResult = check.call(edit)
		if result.ok:
			result = BuildTransaction.commit_plan(grid, DoorPlacement.edits_for(grid, edit), wallet)
		else:
			grid.edit_refused.emit(edit, result)
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
	return report


## Starts a row on `cell`, on the `edge_side` the press was nearest to.
## `grid_size` bounds the row.
func begin(cell: Vector2i, edge_side: int, grid_size: Vector2i) -> void:
	active = true
	side = edge_side
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


## The cells of the row from the press cell to the far end along the longer
## axis of the drag, both included.
func cells() -> Array[Vector2i]:
	var span := _end - _start
	var step := Vector2i(signi(span.x), 0)
	var count := absi(span.x)
	if absi(span.y) > absi(span.x):
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
