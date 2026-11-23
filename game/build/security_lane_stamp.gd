class_name SecurityLaneStamp
extends RefCounted
## 1-click Complete Security Lane stamp: computes, validates, ghosts and places
## the four core lane parts directly from SecurityLanes.geometry() as one atomic
## transaction and one Undo step.

const PART_KEYS := {
	SecurityLanes.TRAY_TABLE: "tray_table",
	SecurityLanes.XRAY_BELT: "xray_belt",
	SecurityLanes.ARCH: "arch",
	SecurityLanes.PICKUP_TABLE: "pickup_table",
}


## The four placement edits for a complete lane rooted at `anchor` and `facing`,
## derived directly from SecurityLanes.geometry().
static func edits_for(
	anchor: Vector2i, facing: int, mirror := SecurityLanes.RIGHT
) -> Array[BuildEdit]:
	var geom := SecurityLanes.geometry(anchor, facing, mirror)
	var out: Array[BuildEdit] = []
	for def_id: StringName in SecurityLanes.PART_IDS:
		var cell: Vector2i = geom[PART_KEYS[def_id]]
		out.append(BuildEdit.place_object(def_id, cell, facing))
	return out


## The four part footprint cells of the stamp at `anchor` and `facing`.
static func footprint_cells(
	anchor: Vector2i, facing: int, mirror := SecurityLanes.RIGHT
) -> Array[Vector2i]:
	var geom := SecurityLanes.geometry(anchor, facing, mirror)
	var out: Array[Vector2i] = []
	for def_id: StringName in SecurityLanes.PART_IDS:
		out.append(geom[PART_KEYS[def_id]])
	return out


## Combined price of the four core parts in PriceTable, or PriceTable.NO_PRICE.
static func price() -> int:
	var total := 0
	for def_id: StringName in SecurityLanes.PART_IDS:
		var part_price := PriceTable.price_of_object(def_id)
		if part_price == PriceTable.NO_PRICE:
			return PriceTable.NO_PRICE
		total += part_price
	return total


## All-or-nothing check: verifies wallet affordability, wall clearance,
## placement rules, officer spots, staff reach, and full SecurityLanes.COMPLETE
## status on a trial copy before any piece is applied.
static func check(
	grid: BuildGrid, anchor: Vector2i, facing: int, wallet: Wallet, mirror := SecurityLanes.RIGHT
) -> BuildResult:
	var edits := edits_for(anchor, facing, mirror)
	var money := BuildTransaction.check(grid, edits, wallet)
	if not money.ok:
		return money
	var geom := SecurityLanes.geometry(anchor, facing, mirror)
	if LaneWall.walled_edge(grid, geom):
		return BuildResult.refused(BuildResult.Reason.LANE_WALL)
	var standing := grid.recognised_lanes()
	for edit in edits:
		var rule := GridRules.check(grid, edit)
		if not rule.ok:
			return rule
		var officer := standing.officer_spot_problem(grid, edit)
		if officer != null:
			return officer
	var trial := BuildUndo.trial_copy_of(grid)
	var seq := trial.apply_sequence(edits, Callable())
	if not seq.ok:
		return seq
	var lanes := SecurityLanes.new()
	lanes.rebuild(trial)
	var arch_id := trial.object_at(anchor)
	var status := lanes.status(arch_id)
	if status != SecurityLanes.Status.COMPLETE:
		return _status_refusal(status, arch_id)
	return BuildResult.accepted()


static func hover(mode: BuildMode, point: Variant) -> void:
	mode._hover_edit = null
	if (
		mode._status_note != ""
		and (point == null or mode.grid.world_to_cell(point) != mode._note_cell)
	):
		mode._status_note = ""
		mode._hover_key = ""
		mode._show_status(null)
	if point == null or not mode._pointer_on_grid:
		mode._ghost.visible = false
		mode._front_warning = ""
		if mode._hover_key != "":
			mode._hover_key = ""
			mode._lane_hint = ""
			mode._show_status(null)
		return
	var anchor := mode.grid.world_to_cell(point)
	var purse := mode.wallet()
	var bal := purse.balance if purse != null else -1
	var key := "lane_stamp:%s:%d:%d" % [anchor, mode.facing, bal]
	if key == mode._hover_key:
		return
	mode._hover_key = key
	mode._lane_hint = ""
	mode._front_warning = ""
	var result := check(mode.grid, anchor, mode.facing, purse)
	var tint := mode._valid_material if result.ok else mode._invalid_material
	BuildGhost.clear(mode)
	for edit in edits_for(anchor, mode.facing):
		BuildGhost.object(mode, edit.def_id, edit.cell, edit.facing, tint)
	mode._show_status(result)


static func apply(mode: BuildMode, point: Vector3) -> BuildResult:
	mode._status_note = ""
	var anchor := mode.grid.world_to_cell(point)
	var edits := edits_for(anchor, mode.facing)
	var before_bal := mode.wallet().balance if mode.wallet() != null else 0
	var result := check(mode.grid, anchor, mode.facing, mode.wallet())
	if not result.ok:
		mode._show_status(result)
		mode.notify_refusal(mode._status if mode._status != "" else result.reason_text())
		mode.grid.edit_refused.emit(edits[2], result)
		return result
	mode.grid.hold_signals()
	result = BuildTransaction.commit_plan(mode.grid, edits, mode.wallet())
	if result.ok:
		BuildDrags.reshape_belts(mode, result.dirty_cells)
	mode.grid.release_signals()
	if result.ok:
		mode._redraw()
		mode._hover_key = ""
		mode.grid_changed.emit()
		var after_bal := mode.wallet().balance if mode.wallet() != null else 0
		var cells := footprint_cells(anchor, mode.facing)
		var placed_ids: Array[int] = []
		for c in cells:
			var oid := mode.grid.object_at(c)
			if oid != 0 and not placed_ids.has(oid):
				placed_ids.append(oid)
		mode.emit_player_commit(
			&"security_lane",
			cells,
			placed_ids,
			before_bal - after_bal if mode.wallet() != null else 0
		)
		mode._status_note = Words.new().placed_note(BuildMenuCatalog.shown("Security lane"))
		mode._note_cell = anchor
	mode._show_status(result)
	if not result.ok:
		mode.notify_refusal(mode._status if mode._status != "" else result.reason_text())
	return result


static func _status_refusal(status: int, arch_id: int) -> BuildResult:
	match status:
		SecurityLanes.Status.WALL_IN_LANE:
			return BuildResult.refused(BuildResult.Reason.LANE_WALL, arch_id)
		SecurityLanes.Status.NO_PRIMARY_SPOT, SecurityLanes.Status.NO_HELPER_SPOT:
			return BuildResult.refused(BuildResult.Reason.STAFF_SPOT, arch_id)
	return BuildResult.refused(BuildResult.Reason.INTERACTION_BLOCKED, arch_id)


class Words:
	extends RefCounted

	func placed_note(item_name: String) -> String:
		return tr("{item} placed", "build status").format({"item": item_name})
