class_name ItemRowDrag
extends RefCounted
## Straight horizontal or vertical drag-paint row for repeatable corridor and
## room furniture tools (B3, decisions 45a81488 and 593876df). Step spacing
## respects the item's rotated footprint and interaction/approach cells so
## adjacent copies never collide or block each other's interaction spot.
## Preview and commit are partial-ok: blocked cells are skipped cleanly, and
## affordable valid copies commit in ONE UndoStack action.


class Preview:
	extends RefCounted
	var edits: Array[BuildEdit] = []
	var valid: Array[bool] = []
	var cost := 0
	var blocked := 0
	var first_reason := ""


const REPEATABLE_TOOLS := {
	BuildMode.Tool.SEATS: true,
	BuildMode.Tool.BENCH: true,
	BuildMode.Tool.TREE_BENCH: true,
	BuildMode.Tool.BUSH: true,
	BuildMode.Tool.PLANTER: true,
	BuildMode.Tool.PLANT_POT: true,
	BuildMode.Tool.TREE: true,
	BuildMode.Tool.BIN: true,
	BuildMode.Tool.POST: true,
	BuildMode.Tool.CHAIN: true,
	BuildMode.Tool.TOILET_STALL: true,
	BuildMode.Tool.TOILET_SINK: true,
	BuildMode.Tool.SHOWER: true,
	BuildMode.Tool.TABLE: true,
	BuildMode.Tool.DINING_TABLE: true,
	BuildMode.Tool.BOOTH: true,
	BuildMode.Tool.KIOSK_DISPLAY: true,
	BuildMode.Tool.PHARMACY_SHELF: true,
	BuildMode.Tool.DUTY_FREE_SHELF: true,
	BuildMode.Tool.FASHION_RAIL: true,
	BuildMode.Tool.CART: true,
	BuildMode.Tool.SOFA: true,
	BuildMode.Tool.ARMCHAIR: true,
	BuildMode.Tool.WORK_DESK: true,
	BuildMode.Tool.NAP_POD: true,
	BuildMode.Tool.ATM: true,
}

var active := false
var press_point := Vector3.ZERO

var _start := Vector2i.ZERO
var _end := Vector2i.ZERO
var _limit := Vector2i.ZERO
var _def_id: StringName = &""
var _facing := 0


static func is_repeatable(tool: BuildMode.Tool) -> bool:
	return REPEATABLE_TOOLS.has(tool)


## Smallest positive cell step along `axis_dir` (cardinal unit vector) so
## adjacent copies of `def_id` at `facing` never overlap footprints, reserve
## the same interaction cell, or cover each other's interaction/seat approach.
static func step_spacing(def_id: StringName, facing: int, axis_dir: Vector2i) -> int:
	var def := BuildCatalog.get_def(def_id)
	if def == null or axis_dir == Vector2i.ZERO:
		return 1
	var base_foot := def.footprint(Vector2i.ZERO, facing)
	var base_spot := def.interaction_cell(Vector2i.ZERO, facing)
	var base_approaches := _seat_approaches(def, Vector2i.ZERO, facing)
	for step in range(1, 32):
		var offset := axis_dir * step
		if _copies_clear(base_foot, base_spot, base_approaches, def, facing, offset):
			return step
	return 1


static func _seat_approaches(def: BuildObjectDef, anchor: Vector2i, facing: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for seat: Dictionary in def.seat_descriptors(anchor, facing):
		out.append(seat["approach"])
	return out


static func _copies_clear(
	base_foot: Array[Vector2i],
	base_spot: Vector2i,
	base_approaches: Array[Vector2i],
	def: BuildObjectDef,
	facing: int,
	offset: Vector2i
) -> bool:
	var next_foot := def.footprint(offset, facing)
	var next_spot := def.interaction_cell(offset, facing)
	for cell in next_foot:
		if base_foot.has(cell) or cell == base_spot or base_approaches.has(cell):
			return false
	if next_spot != BuildObjectDef.NO_CELL:
		if base_foot.has(next_spot) or next_spot == base_spot:
			return false
	for approach in _seat_approaches(def, offset, facing):
		if base_foot.has(approach):
			return false
	return true


## Evaluates each candidate edit in order against `grid`, `check`, `unlocks`
## and `wallet`, skipping blocked cells and stopping affordable additions once
## the wallet cannot pay for the next valid copy.
static func preview(
	grid: BuildGrid,
	edits: Array[BuildEdit],
	check: Callable,
	wallet: Wallet,
	unlocks: BuildUnlocks = null,
	require_unlocks := false
) -> Preview:
	var report := Preview.new()
	report.edits = edits
	var stopped := false
	var was_cleared := grid._reach_cleared
	if not was_cleared and grid.check_staff_reach:
		grid._reach_cleared = GridReach.batch_keeps_reach(grid, edits)
	for edit in edits:
		var result: BuildResult = _check_candidate(edit, check, unlocks, require_unlocks)
		var item_cost := 0
		if result.ok and wallet != null:
			item_cost = BuildTransaction.needed(grid, [edit] as Array[BuildEdit])
			if report.cost + item_cost > wallet.balance:
				result = BuildResult.refused(BuildResult.Reason.CANT_AFFORD)
		if result.reason == BuildResult.Reason.CANT_AFFORD:
			stopped = true
		var ok := result.ok and not stopped
		report.valid.append(ok)
		if ok:
			report.cost += item_cost
			continue
		report.blocked += 1
		if report.first_reason == "":
			report.first_reason = result.reason_text()
	grid._reach_cleared = was_cleared
	return report


static func _check_candidate(
	edit: BuildEdit, check: Callable, unlocks: BuildUnlocks, require_unlocks: bool
) -> BuildResult:
	if unlocks != null or require_unlocks:
		var lock := BuildUnlocks.edits_lock_text(
			unlocks, require_unlocks, [edit] as Array[BuildEdit]
		)
		if lock != "":
			var locked := BuildResult.refused(BuildResult.Reason.LOCKED)
			locked.detail = lock
			return locked
	return check.call(edit)


## Commits every valid affordable candidate in `edits` inside the caller's open
## UndoStack action, skipping blocked cells and stopping once money runs out.
static func apply(
	grid: BuildGrid,
	edits: Array[BuildEdit],
	check: Callable,
	wallet: Wallet,
	dirty: Array[Vector2i],
	placed_ids: Array[int] = [],
	placed_cells: Array[Vector2i] = [],
	unlocks: BuildUnlocks = null,
	require_unlocks := false
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
		var result := _check_candidate(edit, check, unlocks, require_unlocks)
		if result.ok:
			result = BuildTransaction.commit_plan(grid, [edit] as Array[BuildEdit], wallet)
		else:
			var refusal := result
			grid._emit_or_hold(func() -> void: grid.edit_refused.emit(edit, refusal))
		if result.ok:
			outcome.placed += 1
			dirty.append_array(result.dirty_cells)
			if result.object_id != 0:
				placed_ids.append(result.object_id)
			var def := BuildCatalog.get_def(edit.def_id)
			if def != null:
				placed_cells.append_array(def.footprint(edit.cell, edit.facing))
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


## Live preview cost Vector2i(cost, needed) for BuildMenuPrices while dragging.
static func preview_price(mode: BuildMode) -> Vector2i:
	if mode == null or not mode._item_row.active:
		return Vector2i.ZERO
	var plan := preview(
		mode.grid,
		mode._item_row.edits(),
		mode.check,
		mode.wallet(),
		mode.unlocks,
		mode.require_unlocks
	)
	return Vector2i(plan.cost, plan.cost)


func begin(
	cell: Vector2i, point: Vector3, grid_size: Vector2i, def_id: StringName, facing: int
) -> void:
	active = true
	press_point = point
	_limit = grid_size
	_start = cell
	_end = cell
	_def_id = def_id
	_facing = facing


func move(cell: Vector2i) -> void:
	_end = cell.clamp(Vector2i.ZERO, _limit - Vector2i.ONE)


func cancel() -> void:
	active = false


func is_single_cell() -> bool:
	return _start == _end


func _along_x() -> bool:
	var span := _end - _start
	return absi(span.y) <= absi(span.x)


func axis_dir() -> Vector2i:
	var span := _end - _start
	if _along_x():
		return Vector2i(signi(span.x) if span.x != 0 else 1, 0)
	return Vector2i(0, signi(span.y))


func cells() -> Array[Vector2i]:
	var dir := axis_dir()
	var span := _end - _start
	var dist := absi(span.x) if _along_x() else absi(span.y)
	var stride := maxi(1, step_spacing(_def_id, _facing, dir))
	var count := dist / stride + 1
	var row: Array[Vector2i] = []
	for i in count:
		row.append(_start + dir * (i * stride))
	return row


func edits() -> Array[BuildEdit]:
	var out: Array[BuildEdit] = []
	for cell in cells():
		out.append(BuildEdit.place_object(_def_id, cell, _facing))
	return out


func start_cell() -> Vector2i:
	return _start


func end_cell() -> Vector2i:
	return cells().back()
