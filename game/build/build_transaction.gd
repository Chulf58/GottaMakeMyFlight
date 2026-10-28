class_name BuildTransaction
extends RefCounted
## Where build edits meet money (decision
## flights-and-economy-design-tick-derived-calendar-timetable-o, point 6;
## ruling building-costs-money-from-a-starting-budget-you-can-t-build). Every
## player build plans its edits, quotes them here, checks the wallet can pay
## and commits grid and wallet together: a click or a door conversion through
## commit_plan(), a Floor or Remove rectangle through commit_batch(). A wall
## stroke is a run of clicks, one per segment, so it stops paying when the
## money runs out (BuildMode ends the stroke there).
##
## Prices come from PriceTable. A placed piece's price is saved on it in the
## grid (BuildEdit.paid), and a removal refunds PriceTable.refund_of() that
## saved price, so a piece placed for free refunds nothing. Repainting floor
## that is already the same is free. Rooms cost nothing.
##
## With no wallet (null) the edits are free and save no price: the
## non-spending path for tests and probes that build through BuildMode
## without a Finances node. Debug layouts (ReferenceTerminal) and snapshot
## loads write the grid directly and never come here.


## What one edit costs against the grid as it stands.
class Quote:
	extends RefCounted
	## Money the edit takes.
	var charge := 0
	## Money the edit pays back: the refund share of the saved price of the
	## piece it removes or replaces.
	var refund := 0
	## The purchase price saved on the piece after the edit.
	var paid := 0
	## False when PriceTable has no price for the piece.
	var priced := true

	## Money the edit takes after its refund; negative when it pays back.
	func net() -> int:
		return charge - refund


## Prices `edit` against the grid as it stands. With `free`, nothing is
## charged or refunded and a new piece saves no price. An edit the grid will
## refuse for an unknown object or wall kind is quoted at nothing.
static func quote(grid: BuildGrid, edit: BuildEdit, free := false) -> Quote:
	var q := Quote.new()
	var unchanged_floor := (
		edit.kind == BuildEdit.Kind.PAINT_FLOOR
		and grid.floor_at(edit.cell) == edit.floor_type
		and grid.zone_at(edit.cell) == edit.zone_id
	)
	if unchanged_floor:
		q.paid = grid.floor_paid(edit.cell)
		return q
	if free:
		return q
	match edit.kind:
		BuildEdit.Kind.PAINT_FLOOR:
			_buy(q, PriceTable.price_of_floor(), grid.floor_paid(edit.cell))
		BuildEdit.Kind.REMOVE_FLOOR:
			_sell(q, grid.floor_paid(edit.cell))
		BuildEdit.Kind.PLACE_WALL:
			var known := edit.wall_kind >= BuildGrid.WallKind.PLAIN
			if known and edit.wall_kind <= BuildGrid.MAX_WALL_KIND:
				var price := PriceTable.price_of_wall(edit.wall_kind)
				_buy(q, price, grid.wall_paid(edit.cell, edit.side))
		BuildEdit.Kind.REMOVE_WALL:
			_sell(q, grid.wall_paid(edit.cell, edit.side))
		BuildEdit.Kind.PLACE_OBJECT:
			if BuildCatalog.get_def(edit.def_id) != null:
				_buy(q, PriceTable.price_of_object(edit.def_id), 0)
		BuildEdit.Kind.REMOVE_OBJECT:
			_sell(q, int(grid.get_object(edit.object_id).get("paid", 0)))
	return q


## What the wallet must hold for `edits`: the sum of each edit's own net cost,
## each against the grid as it stands, with refunds counted only inside the
## edit that earns them (a replaced wall), never toward another edit. So any
## part of the edits that ends up applied costs no more than this.
## PriceTable.NO_PRICE when a piece has no price.
static func needed(grid: BuildGrid, edits: Array[BuildEdit]) -> int:
	return _needed(_quotes(grid, edits, false))


## Accepted when `wallet` can pay for `edits` and hold their settlement, else
## refused with CANT_AFFORD, WALLET_FULL (the settlement would pass
## Wallet.MAX_BALANCE) or UNPRICED (a piece has no price). A null wallet
## always takes them.
static func check(grid: BuildGrid, edits: Array[BuildEdit], wallet: Wallet) -> BuildResult:
	if wallet == null:
		return BuildResult.accepted()
	return _refusal(_quotes(grid, edits, false), wallet)


## Commits one player action: `plan` is applied edit by edit with
## BuildGrid.apply(), in order, stopping at the first refusal (the plan
## DoorPlacement.edits_for() makes). The grid's signals are held while the
## plan applies, the wallet is settled exactly for the edits that were applied
## (_settle()), and only then are the signals published, in the order they
## happened, so a listener already sees the money settled. Listeners get each
## edit's own result. A plan the wallet cannot pay for or hold the settlement
## of changes nothing and is emitted as edit_refused for its last edit. When
## the exact settlement of a partly applied plan does not fit, the grid is put
## back, the held signals are dropped and that refusal is returned and emitted
## the same way. Otherwise returns the last edit's result, or a copy of it with
## every applied edit's dirty cells when all went through, or the first
## refusal.
static func commit_plan(grid: BuildGrid, plan: Array[BuildEdit], wallet: Wallet) -> BuildResult:
	var quotes := _quotes(grid, plan, wallet == null)
	var refusal := _refusal(quotes, wallet)
	if not refusal.ok:
		_emit_refused(grid, plan.back(), refusal)
		return refusal
	var snapshot := _snapshot_if_settlement_can_fail(grid, quotes, wallet)
	var applied: Array[bool] = []
	var cleared: Array[Vector2i] = []
	var result: BuildResult = null
	var mark := grid.hold_signals()
	for i in plan.size():
		plan[i].paid = quotes[i].paid
		result = grid.apply(plan[i])
		if not result.ok:
			break
		applied.append(true)
		if i < plan.size() - 1:
			cleared.append_array(result.dirty_cells)
	var settlement := _settle(wallet, quotes, applied)
	if not settlement.ok:
		_roll_back(grid, snapshot, mark, "commit_plan", settlement)
		_emit_refused(grid, plan.back(), settlement)
		return settlement
	grid.release_signals()
	if not result.ok:
		return result
	var whole := BuildResult.accepted()
	whole.object_id = result.object_id
	whole.room_id = result.room_id
	whole.dirty_cells = result.dirty_cells.duplicate()
	whole.dirty_cells.append_array(cleared)
	return whole


## Commits a rectangle: `edits` go through one BuildGrid.apply_batch(), which
## validates each in order and skips the ones it refuses. All or nothing on
## money: when the wallet cannot pay for every edit (or hold the settlement),
## none is applied, each is refused (and emitted as edit_refused) and no money
## moves. Otherwise the grid's signals are held while the edits apply, the
## wallet is settled exactly for the edits that were applied (_settle()), and
## only then are the signals published. When that exact settlement does not
## fit, the grid is put back, the held signals are dropped and every edit is
## refused and emitted as above. Returns one result per edit, in order.
static func commit_batch(
	grid: BuildGrid, edits: Array[BuildEdit], wallet: Wallet
) -> Array[BuildResult]:
	var quotes := _quotes(grid, edits, wallet == null)
	var refusal := _refusal(quotes, wallet)
	if not refusal.ok:
		return _refuse_all(grid, edits, refusal)
	var snapshot := _snapshot_if_settlement_can_fail(grid, quotes, wallet)
	for i in edits.size():
		edits[i].paid = quotes[i].paid
	var mark := grid.hold_signals()
	var results := grid.apply_batch(edits)
	var applied: Array[bool] = []
	for result in results:
		applied.append(result.ok)
	var settlement := _settle(wallet, quotes, applied)
	if not settlement.ok:
		_roll_back(grid, snapshot, mark, "commit_batch", settlement)
		return _refuse_all(grid, edits, settlement)
	grid.release_signals()
	return results


## Puts the grid back to `snapshot` after a settlement that did not fit and
## drops the signals held since `mark`. When the restore itself is refused
## (BuildGrid.from_snapshot() false), the grid still holds the applied edits:
## that is pushed as an error naming the failed restore, and the held signals
## are published instead of dropped, so listeners stay in step with the grid
## as it really is. The caller still refuses the build: nothing was paid.
static func _roll_back(
	grid: BuildGrid, snapshot: Dictionary, mark: int, caller: String, settlement: BuildResult
) -> void:
	if grid.from_snapshot(snapshot):
		grid.release_signals(mark)
		return
	push_error(
		(
			(
				"BuildTransaction.%s: the settlement was refused (%s) and restoring the grid failed;"
				+ " the applied edits stay on the grid, unpaid"
			)
			% [caller, settlement.reason_text()]
		)
	)
	grid.release_signals()


## One refusal per edit, each emitted as edit_refused.
static func _refuse_all(
	grid: BuildGrid, edits: Array[BuildEdit], refusal: BuildResult
) -> Array[BuildResult]:
	var results: Array[BuildResult] = []
	for edit in edits:
		var refused := BuildResult.refused(refusal.reason)
		results.append(refused)
		_emit_refused(grid, edit, refused)
	return results


## Publishes edit_refused through the grid's own hold queue, so a refusal
## arriving while a caller holds the grid's signals waits behind the edits
## already queued there instead of overtaking them.
static func _emit_refused(grid: BuildGrid, edit: BuildEdit, refusal: BuildResult) -> void:
	grid._emit_or_hold(func() -> void: grid.edit_refused.emit(edit, refusal))


## The grid as it stands, when _settle() could fail for `quotes`: only when the
## refunds of the edits that end up applied can pass Wallet.MAX_BALANCE, which
## _refusal() ruled out for all of them applied but not for a part. Empty
## otherwise, so a build that cannot fail to settle pays for no snapshot.
static func _snapshot_if_settlement_can_fail(
	grid: BuildGrid, quotes: Array[Quote], wallet: Wallet
) -> Dictionary:
	if wallet == null or _refunds(quotes) <= Wallet.MAX_BALANCE - wallet.balance:
		return {}
	return grid.to_snapshot()


static func _quotes(grid: BuildGrid, edits: Array[BuildEdit], free: bool) -> Array[Quote]:
	var out: Array[Quote] = []
	for edit in edits:
		out.append(quote(grid, edit, free))
	return out


static func _needed(quotes: Array[Quote]) -> int:
	var total := 0
	for q in quotes:
		if not q.priced:
			return PriceTable.NO_PRICE
		total += maxi(q.net(), 0)
	return total


## The refunds `quotes` pay at most: each edit that pays back more than it
## costs.
static func _refunds(quotes: Array[Quote]) -> int:
	var total := 0
	for q in quotes:
		total += maxi(-q.net(), 0)
	return total


## The net money the edits in `quotes` take when every one is applied.
static func _net(quotes: Array[Quote]) -> int:
	var total := 0
	for q in quotes:
		total += q.net()
	return total


## Accepted, or the reason `wallet` cannot take `quotes`. The wallet must hold
## needed() (the most any subset of the edits can take) and, once every edit is
## applied, the exact final balance must stay within Wallet.MAX_BALANCE: a
## charge in the same plan makes room for a refund (a paid wall made an
## entrance). If the grid then refuses some edit and the settlement of the
## rest does not fit, the commit puts the grid back (see commit_plan()). A null
## wallet (free edits) always takes them.
static func _refusal(quotes: Array[Quote], wallet: Wallet) -> BuildResult:
	if wallet == null:
		return BuildResult.accepted()
	var total := _needed(quotes)
	if total == PriceTable.NO_PRICE:
		return BuildResult.refused(BuildResult.Reason.UNPRICED)
	if not wallet.can_afford(total):
		return BuildResult.refused(BuildResult.Reason.CANT_AFFORD)
	if -_net(quotes) > Wallet.MAX_BALANCE - wallet.balance:
		return BuildResult.refused(BuildResult.Reason.WALLET_FULL)
	return BuildResult.accepted()


## After the grid changed, before its signals are published: moves the exact
## net money of the edits that were applied (`applied[i]` true), the price of
## the ones that were not never having left the wallet. Accepted, or refused
## with CANT_AFFORD or WALLET_FULL when the wallet cannot take it (only
## possible when the grid refused an edit that was not expected to fail and
## the rest does not fit); the wallet is then unchanged and the caller puts
## the grid back.
static func _settle(wallet: Wallet, quotes: Array[Quote], applied: Array[bool]) -> BuildResult:
	if wallet == null:
		return BuildResult.accepted()
	var net := 0
	for i in quotes.size():
		if i < applied.size() and applied[i]:
			net += quotes[i].net()
	if net > 0 and not wallet.spend(net, Wallet.Category.BUILD):
		return BuildResult.refused(BuildResult.Reason.CANT_AFFORD)
	if net < 0:
		if -net > Wallet.MAX_BALANCE - wallet.balance:
			return BuildResult.refused(BuildResult.Reason.WALLET_FULL)
		wallet.credit(-net, Wallet.Category.BUILD)
	return BuildResult.accepted()


## A new piece at `price` in place of one saved at `old_paid` (0 for none).
static func _buy(q: Quote, price: int, old_paid: int) -> void:
	if price == PriceTable.NO_PRICE:
		q.priced = false
		return
	q.charge = price
	q.paid = price
	_sell(q, old_paid)


## Takes off a piece saved at `old_paid`: refunds its share and saves nothing.
static func _sell(q: Quote, old_paid: int) -> void:
	if old_paid > 0:
		q.refund = PriceTable.refund_of(old_paid)
