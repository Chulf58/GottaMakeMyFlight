class_name RoomMove
extends RefCounted
## Moving a built room with its furniture (decision
## move-rooms-technical-design-roommove-plan-of-existing-edits, parts 1 to 3,
## building the user ruling moving-a-room-with-its-furniture-is-free-and-keeps-paid-pric).
## A move is made of existing edits, in this order: REMOVE_OBJECT for each
## piece, PAINT_FLOOR on each new cell with no floor (the floor of the room
## cell it comes from), RESIZE_ROOM to the new rectangle, PLACE_OBJECT for
## each piece under its old id with its old def and paid, turned with the
## room, and last RESHAPE_BELT for the belts on and next to both rectangles.
## A quarter turn maps the room's cells and pieces as RoomTemplate.plan() does.
##
## A piece belongs to the room when its whole footprint lies inside the room.
## Doors, walls and the old floor stay behind. The move is refused, with a
## BuildResult reason, when a piece straddles the room's edge
## (MOVE_STRADDLES), a check-in desk, scanner or lane part stands in the room
## (MOVE_UNMOVABLE), a wall lies on a grid line inside the new rectangle
## (ROOM_WALL), the new rectangle overlaps another room (ROOM_OVERLAP), a
## piece does not fit at its new spot (MOVE_NO_FIT, with the grid's own reason
## as detail), a piece would stand on a cell that must stay clear
## (MOVE_EXIT_BLOCKED) or the wallet cannot pay for the new floor.
##
## The cells that must stay clear (`keep_clear`) are the way out of the
## passengers leaving the room. The caller may pass some in, and plan() and
## commit_move() add the passenger side's own: the cells the Callable in the
## grid's EXIT_CELLS_META meta returns (PassengerSim.move_exit_cells(), decision
## part 3). With neither, nothing is kept clear.
##
## commit_move() is the move's own atomic commit (decision part 2). It plans
## the move again from the grid as it stands, reading each piece's def, paid,
## anchor and facing and each floor cell itself, and refuses with MOVE_CHANGED
## a plan that differs from that in any edit (a stale room, a moved, added or
## repeated piece, a changed def, paid, anchor or facing, other floor). It
## applies only its own fresh edits. It runs the whole move on a
## copy of the grid first, then checks the wallet: pieces move for free and
## keep their paid, so a later removal refunds what they were bought for, and
## only new floor is charged, at the normal price. A refusal changes neither
## the grid, the wallet nor the undo history. An accepted move is one undo
## step: its undo puts the room and the pieces back under their ids and gives
## the floor money back. That undo lasts as long as any other build action's,
## until build mode ends (ruling
## build-mode-pauses-the-game-while-a-build-tray-is-open-closin); the move
## starts no refund of its own.
##
## Not done here: the tool, ghost and status line (slice 2) and the passengers
## using the room (decision parts 4 to 6).

## The grid meta holding the passenger side's keep-clear cells: a Callable
## with no arguments returning Array[Vector2i].
const EXIT_CELLS_META := &"room_move_exit_cells"

## The room being moved.
var room_id := 0
## Quarter turns clockwise, 0 to 3.
var turns := 0
## The room's rectangle before the move.
var from_rect := Rect2i()
## The room's rectangle after the move.
var to_rect := Rect2i()
## The ids of the pieces that move with the room, in id order.
var pieces: Array[int] = []
## The move's edits, belt reshapes last. Empty when the room cannot move at all.
var edits: Array[BuildEdit] = []
## What the new floor costs at normal prices: what the wallet must hold.
var cost := 0
## Accepted, or why the move is refused.
var result := BuildResult.accepted()


## The room's rectangle of `room_size` with its centre cell on `centre` after
## `quarter_turns` (RoomTemplate.rect_at()).
static func rect_at(room_size: Vector2i, centre: Vector2i, quarter_turns: int) -> Rect2i:
	var turned := room_size
	if posmod(quarter_turns, 2) == 1:
		turned = Vector2i(room_size.y, room_size.x)
	return Rect2i(centre - (turned - Vector2i.ONE) / 2, turned)


## The move of room `id` to `centre` after `quarter_turns`, checked on a copy
## of the grid and against `wallet` (null: free building, no money check).
## Read the plan's `result`; a refused plan keeps whatever edits it got to.
static func plan(
	grid: BuildGrid,
	id: int,
	centre: Vector2i,
	quarter_turns: int,
	wallet: Wallet = null,
	keep_clear: Array[Vector2i] = []
) -> RoomMove:
	var move := RoomMove.new()
	move.room_id = id
	move.turns = posmod(quarter_turns, 4)
	move.result = _shape(grid, move, centre)
	if not move.result.ok:
		return move
	move.edits = _edits(grid, move)
	var floors := _floor_edits(move.edits)
	move.cost = BuildTransaction.needed(grid, floors)
	var trial := _trial(grid, move, move.edits, _kept_clear(grid, keep_clear))
	move.result = trial["result"]
	move.edits.append_array(trial["reshapes"])
	if move.result.ok:
		move.result = BuildTransaction.check(grid, floors, wallet)
	return move


## Whether room `id` may move to `centre` after `quarter_turns` (plan()).
static func check(
	grid: BuildGrid,
	id: int,
	centre: Vector2i,
	quarter_turns: int,
	wallet: Wallet = null,
	keep_clear: Array[Vector2i] = []
) -> BuildResult:
	return plan(grid, id, centre, quarter_turns, wallet, keep_clear).result


## Plans the move (plan()) and commits it (commit_move()). A refused plan
## changes nothing, and the grid emits edit_refused for it (behind any signals
## an outer BuildGrid.hold_signals() holds).
static func commit(
	grid: BuildGrid,
	id: int,
	centre: Vector2i,
	quarter_turns: int,
	wallet: Wallet,
	history: UndoStack = null,
	keep_clear: Array[Vector2i] = []
) -> BuildResult:
	var move := plan(grid, id, centre, quarter_turns, wallet, keep_clear)
	if not move.result.ok:
		_emit_refused(grid, BuildEdit.resize_room(id, move.to_rect), move.result)
		return move.result
	return commit_move(grid, move, wallet, history, keep_clear)


## Commits `move` as one player action of `history` (null: no undo step).
## The move is planned again from the grid as it stands (_canonical()), and
## `move`'s edits other than belt reshapes must equal that plan field by field,
## in order; then the fresh edits are tried with fresh belt reshapes on a copy
## of the grid, `wallet` (null: free) must pay for the new floor, and they are
## applied to the live grid with its signals held until the floor is paid.
## Returns accepted with the room's id and the changed cells, or the refusal,
## with nothing changed and the grid emitting edit_refused for it (behind any
## signals an outer hold already queued). `move`'s own edits are never applied.
static func commit_move(
	grid: BuildGrid,
	move: RoomMove,
	wallet: Wallet,
	history: UndoStack = null,
	keep_clear: Array[Vector2i] = []
) -> BuildResult:
	keep_clear = _kept_clear(grid, keep_clear)
	var canon := _canonical(grid, move)
	var result := canon.result
	var edits := canon.edits
	var floors := _floor_edits(edits)
	for edit in floors:
		edit.paid = BuildTransaction.quote(grid, edit, wallet == null).paid
	if result.ok:
		var trial := _trial(grid, canon, edits, keep_clear)
		result = trial["result"]
		edits.append_array(trial["reshapes"])
	if result.ok:
		result = BuildTransaction.check(grid, floors, wallet)
	var refused_edit := BuildEdit.resize_room(move.room_id, move.to_rect)
	if not result.ok:
		_emit_refused(grid, refused_edit, result)
		return result
	var cost := BuildTransaction.needed(grid, floors) if wallet != null else 0
	if history != null:
		history.begin_action()
	result = _apply(grid, edits, cost, wallet, keep_clear, refused_edit)
	if history != null:
		history.end_action()
	result.room_id = move.room_id
	return result


## Fills `move`'s rectangles and pieces for a move to `centre`. Accepted, or
## NO_ROOM, OUT_OF_BOUNDS, MOVE_UNMOVABLE, MOVE_STRADDLES or ROOM_WALL.
static func _shape(grid: BuildGrid, move: RoomMove, centre: Vector2i) -> BuildResult:
	var room := grid.get_room(move.room_id)
	if room.is_empty():
		return BuildResult.refused(BuildResult.Reason.NO_ROOM)
	move.from_rect = room["rect"]
	move.to_rect = rect_at(move.from_rect.size, centre, move.turns)
	return _shape_rest(grid, move)


## The checks of _shape() once `move`'s rectangles are set: the new rectangle
## on the grid, the room's pieces (filling `move.pieces`) and no inner wall.
static func _shape_rest(grid: BuildGrid, move: RoomMove) -> BuildResult:
	var to := move.to_rect
	if not grid.in_bounds(to.position) or not grid.in_bounds(to.end - Vector2i.ONE):
		return BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
	var result := _members(grid, move.from_rect, move.pieces)
	if result.ok:
		result = _wall_problem(grid, to)
	return result


## Adds to `ids` the pieces whose whole footprint lies in `rect`, doors left
## out (they stay behind). Refused with MOVE_UNMOVABLE for a check-in desk,
## scanner or lane part on any cell of `rect`, or MOVE_STRADDLES for a piece
## partly outside it, naming the piece as the blocker.
static func _members(grid: BuildGrid, rect: Rect2i, ids: Array[int]) -> BuildResult:
	var seen := {}
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var object_id := grid.object_at(Vector2i(x, y))
			if object_id == 0 or seen.has(object_id):
				continue
			seen[object_id] = true
			var record := grid.get_object(object_id)
			var def_id: StringName = record["def"]
			if BuildCatalog.is_door(def_id):
				continue
			if not RoomTemplate.keeps_piece(def_id):
				return BuildResult.refused(BuildResult.Reason.MOVE_UNMOVABLE, object_id)
			if not _inside(
				BuildCatalog.get_def(def_id).footprint(record["anchor"], record["facing"]), rect
			):
				return BuildResult.refused(BuildResult.Reason.MOVE_STRADDLES, object_id)
			ids.append(object_id)
	ids.sort()
	return BuildResult.accepted()


## ROOM_WALL when a wall of any kind lies on a grid line inside `area`, where
## the moved room would be split. A wall on its outer edge only bounds it.
static func _wall_problem(grid: BuildGrid, area: Rect2i) -> BuildResult:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x + 1, area.end.x):
			if grid.has_wall(Vector2i(x - 1, y), BuildGrid.Side.EAST):
				return BuildResult.refused(BuildResult.Reason.ROOM_WALL)
	for y in range(area.position.y + 1, area.end.y):
		for x in range(area.position.x, area.end.x):
			if grid.has_wall(Vector2i(x, y - 1), BuildGrid.Side.SOUTH):
				return BuildResult.refused(BuildResult.Reason.ROOM_WALL)
	return BuildResult.accepted()


## The move's edits without belt reshapes (see the class comment).
static func _edits(grid: BuildGrid, move: RoomMove) -> Array[BuildEdit]:
	var from := move.from_rect
	var shift := move.to_rect.position + _turn_offset(from.size, move.turns)
	var out: Array[BuildEdit] = []
	for object_id in move.pieces:
		out.append(BuildEdit.remove_object(object_id))
	for y in from.size.y:
		for x in from.size.x:
			var at := shift + BuildObjectDef.rotate_offset(Vector2i(x, y), move.turns)
			if grid.floor_at(at) == BuildGrid.FLOOR_NONE:
				var old := from.position + Vector2i(x, y)
				out.append(BuildEdit.paint_floor(at, grid.floor_at(old), grid.zone_at(old)))
	out.append(BuildEdit.resize_room(move.room_id, move.to_rect))
	for object_id in move.pieces:
		var record := grid.get_object(object_id)
		var anchor: Vector2i = record["anchor"]
		var edit := BuildEdit.place_object(
			record["def"],
			shift + BuildObjectDef.rotate_offset(anchor - from.position, move.turns),
			posmod(int(record["facing"]) + move.turns, 4)
		)
		edit.object_id = object_id
		edit.paid = int(record.get("paid", 0))
		out.append(edit)
	return out


## Where the room's north-west cell lands, from the new rectangle's corner,
## after `quarter_turns` (RoomTemplate's own offset).
static func _turn_offset(room_size: Vector2i, quarter_turns: int) -> Vector2i:
	var far := room_size - Vector2i.ONE
	var low := Vector2i.ZERO
	for corner in [Vector2i(far.x, 0), Vector2i(0, far.y), far]:
		var turned := BuildObjectDef.rotate_offset(corner, quarter_turns)
		low = Vector2i(mini(low.x, turned.x), mini(low.y, turned.y))
	return -low


## The move commit_move() may apply for `move`: planned again from the grid
## as it stands, for the same room, turns and new rectangle, with fresh edits
## (belt reshapes left out). Its `result` is MOVE_CHANGED, naming the piece
## where one is at fault, when `move` no longer describes that plan: the room's
## rectangle is no longer `move.from_rect`, `move.to_rect` is not the room's
## size turned by `move.turns`, or `move`'s edits other than belt reshapes
## differ from the fresh ones in order, kind or any field the grid reads (an
## anchor, a facing, a def, a paid, an id, a floor cell, type or zone, the
## room's rectangle). Otherwise NO_ROOM, the refusals of _shape_rest(), or
## accepted.
static func _canonical(grid: BuildGrid, move: RoomMove) -> RoomMove:
	var canon := RoomMove.new()
	canon.room_id = move.room_id
	canon.turns = posmod(move.turns, 4)
	canon.to_rect = move.to_rect
	var room := grid.get_room(move.room_id)
	if room.is_empty():
		canon.result = BuildResult.refused(BuildResult.Reason.NO_ROOM)
		return canon
	canon.from_rect = room["rect"]
	var turned := rect_at(canon.from_rect.size, Vector2i.ZERO, canon.turns).size
	if canon.from_rect != move.from_rect or move.to_rect.size != turned:
		canon.result = BuildResult.refused(BuildResult.Reason.MOVE_CHANGED)
		return canon
	canon.result = _shape_rest(grid, canon)
	if not canon.result.ok:
		return canon
	canon.edits = _edits(grid, canon)
	var given: Array[BuildEdit] = []
	for edit in move.edits:
		if edit.kind != BuildEdit.Kind.RESHAPE_BELT:
			given.append(edit)
	for i in maxi(given.size(), canon.edits.size()):
		var mine: BuildEdit = given[i] if i < given.size() else null
		var fresh: BuildEdit = canon.edits[i] if i < canon.edits.size() else null
		if mine == null or fresh == null or _edit_key(mine) != _edit_key(fresh):
			var blocker := mine.object_id if mine != null else fresh.object_id
			canon.result = BuildResult.refused(BuildResult.Reason.MOVE_CHANGED, blocker)
			break
	return canon


## Every field of `edit` the grid reads for the kinds a move uses. A floor's
## paid is left out: commit_move() prices the floor itself.
static func _edit_key(edit: BuildEdit) -> Array:
	var paid := edit.paid if edit.kind == BuildEdit.Kind.PLACE_OBJECT else 0
	return [
		edit.kind,
		edit.cell,
		edit.side,
		edit.wall_kind,
		edit.floor_type,
		edit.zone_id,
		edit.def_id,
		edit.facing,
		edit.object_id,
		edit.room_size,
		edit.room_type,
		edit.room_id,
		paid,
	]


## Runs `edits` on a copy of the grid with the keep-clear and belt crossing
## rules, then the belt checks and reshapes on and next to both rectangles:
## {"result": accepted or the first refusal, "reshapes": the RESHAPE_BELT
## edits}. A piece that does not fit is refused with MOVE_NO_FIT, the grid's
## own reason as its detail and the piece as its blocker.
static func _trial(
	grid: BuildGrid, move: RoomMove, edits: Array[BuildEdit], keep_clear: Array[Vector2i]
) -> Dictionary:
	var scratch := BuildUndo.trial_copy_of(grid)
	var reshapes: Array[BuildEdit] = []
	var last: Array[BuildEdit] = [null]
	var rule := func(on: BuildGrid, edit: BuildEdit) -> BuildResult:
		last[0] = edit
		return _place_problem(on, edit, keep_clear)
	var result := scratch.apply_sequence(edits, rule)
	if not result.ok:
		return {"result": _named(result, last[0]), "reshapes": reshapes}
	var near := _near(scratch, [move.from_rect, move.to_rect])
	var scene := BeltShaper.Scene.new(scratch)
	for cell in near:
		if scene.is_belt(cell) and scene.links(cell).size() > 3:
			result = BuildResult.refused(BuildResult.Reason.BELT_CROSSING)
	if result.ok:
		reshapes = BeltShaper.reshape_edits(scratch, near)
		result = scratch.apply_sequence(reshapes, Callable())
	return {"result": result, "reshapes": reshapes}


## The rules a move edit meets beyond BuildGrid.validate(): a piece set down
## on a keep-clear cell is refused with MOVE_EXIT_BLOCKED, then the belt
## crossing rule (BeltShaper.crossing_problem()). Null when it passes.
static func _place_problem(
	grid: BuildGrid, edit: BuildEdit, keep_clear: Array[Vector2i]
) -> BuildResult:
	if edit.kind == BuildEdit.Kind.PLACE_OBJECT and not keep_clear.is_empty():
		var def := BuildCatalog.get_def(edit.def_id)
		if def != null:
			for cell in def.footprint(edit.cell, edit.facing):
				if keep_clear.has(cell):
					return BuildResult.refused(BuildResult.Reason.MOVE_EXIT_BLOCKED, edit.object_id)
	return BeltShaper.crossing_problem(grid, edit)


## `result` as the move reports it: a refused piece placement becomes
## MOVE_NO_FIT with the grid's reason as detail, unless it was kept clear.
static func _named(result: BuildResult, edit: BuildEdit) -> BuildResult:
	var placing := edit != null and edit.kind == BuildEdit.Kind.PLACE_OBJECT
	if not placing or result.reason == BuildResult.Reason.MOVE_EXIT_BLOCKED:
		return result
	var named := BuildResult.refused(BuildResult.Reason.MOVE_NO_FIT, edit.object_id)
	named.detail = result.reason_text()
	return named


## Every cell of `rects` and of the ring around each, on the grid, each once.
static func _near(grid: BuildGrid, rects: Array[Rect2i]) -> Array[Vector2i]:
	var seen := {}
	var out: Array[Vector2i] = []
	for rect in rects:
		var ring := rect.grow(1)
		for y in range(ring.position.y, ring.end.y):
			for x in range(ring.position.x, ring.end.x):
				var cell := Vector2i(x, y)
				if grid.in_bounds(cell) and not seen.has(cell):
					seen[cell] = true
					out.append(cell)
	return out


## Applies `edits` to the live grid with its signals held, then takes `cost`
## from `wallet` for the new floor, and only then publishes the signals. When
## either step fails (the copy accepted the same edits, so only a defect gets
## here) the grid is put back from a snapshot, the held signals are dropped
## and the refusal is emitted for `refused_edit` (behind any signals an outer
## hold queued earlier). The snapshot load is kept out of the open undo
## receipt and what the move recorded in it is dropped, so the earlier undo
## history stays usable.
static func _apply(
	grid: BuildGrid,
	edits: Array[BuildEdit],
	cost: int,
	wallet: Wallet,
	keep_clear: Array[Vector2i],
	refused_edit: BuildEdit
) -> BuildResult:
	var snapshot := grid.to_snapshot()
	var receipt := grid.recorder
	var recorded := receipt.inverses.size() if receipt != null else 0
	var mark := grid.hold_signals()
	var rule := func(on: BuildGrid, edit: BuildEdit) -> BuildResult:
		return _place_problem(on, edit, keep_clear)
	var result := grid.apply_sequence(edits, rule)
	if not result.ok:
		push_error("RoomMove.commit_move: the grid refused a move its copy accepted")
	elif wallet != null and cost > 0 and not wallet.spend(cost, Wallet.Category.BUILD):
		result = BuildResult.refused(BuildResult.Reason.CANT_AFFORD)
	if result.ok:
		grid.release_signals()
		return result
	grid.recorder = null
	var restored := grid.from_snapshot(snapshot)
	grid.recorder = receipt
	if restored:
		if receipt != null:
			receipt.inverses.resize(recorded)
		grid.release_signals(mark)
	else:
		push_error(
			"RoomMove.commit_move: restoring the grid failed; the move stays applied, unpaid"
		)
		grid.release_signals()
	_emit_refused(grid, refused_edit, result)
	return result


## Emits edit_refused through the grid's own hold queue (as
## BuildTransaction does), so a refusal made while a caller holds the grid's
## signals waits behind the signals already queued there.
static func _emit_refused(grid: BuildGrid, edit: BuildEdit, refusal: BuildResult) -> void:
	grid._emit_or_hold(func() -> void: grid.edit_refused.emit(edit, refusal))


## `keep_clear` plus the cells the grid's EXIT_CELLS_META Callable returns,
## each once.
static func _kept_clear(grid: BuildGrid, keep_clear: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = keep_clear.duplicate()
	var exits: Callable = grid.get_meta(EXIT_CELLS_META, Callable())
	if exits.is_valid():
		for cell: Vector2i in exits.call():
			if not out.has(cell):
				out.append(cell)
	return out


static func _floor_edits(edits: Array[BuildEdit]) -> Array[BuildEdit]:
	var out: Array[BuildEdit] = []
	for edit in edits:
		if edit.kind == BuildEdit.Kind.PAINT_FLOOR:
			out.append(edit)
	return out


static func _inside(cells: Array[Vector2i], rect: Rect2i) -> bool:
	for cell in cells:
		if not rect.has_point(cell):
			return false
	return true
