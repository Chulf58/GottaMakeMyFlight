class_name BuildUndo
extends RefCounted
## Undoes one BuildReceipt as one atomic transaction (decision
## build-mode-undo-design-action-receipts-with-before-values-at, points 2 to
## 4). The money is checked first: undoing a build credits back what it spent,
## undoing a removal takes back its whole refund, owed wages' share included.
## Then the receipt's inverse edits, last applied first, are applied to a copy
## of the grid with every build rule that applies: BuildGrid.validate() (with
## staff reach and the lane officer spots), the entrance and exit rules
## (DoorPlacement) and the belt links (BeltShaper). Only when every edit passes
## there are they applied to the live grid, with its signals held until the
## money is settled. A refusal changes neither the grid nor the wallet.
##
## Not guaranteed: anything outside the grid and the build money. Passengers,
## bags and queues are never rewound.


## Applies `receipt`'s undo to `grid` and settles it with `wallet` (null for
## free building). Returns accepted, or the first refusal with nothing changed.
static func commit(grid: BuildGrid, receipt: BuildReceipt, wallet: Wallet) -> BuildResult:
	var money := _money_problem(receipt.money, wallet)
	if money != null:
		return money
	var edits := receipt.undo_edits()
	var rule := rule_problem
	var snapshot := grid.to_snapshot()
	var scratch := trial_copy_of(grid, snapshot)
	if scratch == null:
		push_error("BuildUndo.commit: the grid could not be copied to check the undo")
		return BuildResult.refused(BuildResult.Reason.NONE)
	var trial := scratch.apply_sequence(edits, rule)
	if not trial.ok:
		return trial
	var mark := grid.hold_signals()
	var result := grid.apply_sequence(edits, rule)
	if not result.ok:
		push_error("BuildUndo.commit: the live grid refused an undo its copy accepted")
	else:
		result = _settle(receipt.money, wallet)
	if not result.ok:
		_roll_back(grid, snapshot, mark)
		return result
	grid.release_signals()
	return result


## A copy of `grid` (from `snapshot`, its to_snapshot() when empty) to try
## edits on before the live grid takes them, or null when the snapshot does not
## load (from_snapshot() pushed why). It keeps the grid's class: a site grid's
## copy is a SiteGrid carrying the same site and guard, so the trial refuses
## what the live grid would (an edit inside the plane's area), instead of the
## live grid refusing it after the trial took it. Every trial copy of a grid
## edits may then reach (an undo, a template paste, the starter shell, the
## debug interior) is made here.
static func trial_copy_of(grid: BuildGrid, snapshot := {}) -> BuildGrid:
	var copy: BuildGrid
	var site_grid := grid as SiteGrid
	if site_grid == null:
		copy = BuildGrid.new(grid.size, grid.origin)
	else:
		copy = SiteGrid.new(site_grid.site)
		(copy as SiteGrid).guard = site_grid.guard
	if not copy.from_snapshot(grid.to_snapshot() if snapshot.is_empty() else snapshot):
		return null
	return copy


## The rules beyond BuildGrid.validate() for one undo edit on `grid` as the
## earlier edits left it, or null. An entrance or exit comes back only with no
## wall of any kind on its way out: the plain wall a placement takes down
## (DoorPlacement.edits_for()) is not taken down by an undo.
static func rule_problem(grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	if edit.kind == BuildEdit.Kind.PLACE_OBJECT and BuildCatalog.is_door(edit.def_id):
		var side := BuildGrid.SIDE_STEP.find(DoorPlacement.back_step(edit.facing))
		if grid.wall_kind(edit.cell, side) != BuildGrid.WallKind.NONE:
			return BuildResult.refused(BuildResult.Reason.DOOR_WALLED)
	var problem := DoorPlacement.edge_problem(grid, edit)
	if problem == null:
		problem = BeltShaper.crossing_problem(grid, edit)
	return problem


## CANT_AFFORD when the wallet cannot pay back a refund of `money` (above 0),
## WALLET_FULL when a credit of what was spent (below 0) cannot fit once owed
## wages and upkeep take their share (Wallet.can_credit()), else null.
static func _money_problem(money: int, wallet: Wallet) -> BuildResult:
	if wallet == null:
		return null
	if money > 0 and not wallet.can_afford(money):
		return BuildResult.refused(BuildResult.Reason.CANT_AFFORD)
	if money < 0 and not wallet.can_credit(-money, Wallet.Category.BUILD):
		return BuildResult.refused(BuildResult.Reason.WALLET_FULL)
	return null


static func _settle(money: int, wallet: Wallet) -> BuildResult:
	if wallet == null or money == 0:
		return BuildResult.accepted()
	if money > 0 and not wallet.spend(money, Wallet.Category.BUILD):
		return BuildResult.refused(BuildResult.Reason.CANT_AFFORD)
	if money < 0 and not wallet.credit(-money, Wallet.Category.BUILD):
		return BuildResult.refused(BuildResult.Reason.WALLET_FULL)
	return BuildResult.accepted()


## Puts the live grid back after a step that should not fail did, and drops
## the signals held since `mark`. A refused restore leaves the applied edits on
## the grid: that is pushed as an error and the held signals are published, so
## listeners stay in step with the grid as it is.
static func _roll_back(grid: BuildGrid, snapshot: Dictionary, mark: int) -> void:
	if grid.from_snapshot(snapshot):
		grid.release_signals(mark)
		return
	push_error("BuildUndo.commit: restoring the grid failed; the undo stays applied, unsettled")
	grid.release_signals()
