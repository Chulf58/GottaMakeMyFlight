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


## Accepted when `wallet` can pay for `edits` and hold their refunds, else
## refused with CANT_AFFORD, WALLET_FULL (a refund would pass
## Wallet.MAX_BALANCE) or UNPRICED (a piece has no price). A null wallet
## always takes them.
static func check(grid: BuildGrid, edits: Array[BuildEdit], wallet: Wallet) -> BuildResult:
	if wallet == null:
		return BuildResult.accepted()
	return _refusal(_quotes(grid, edits, false), wallet)


## Commits one player action: `plan` is applied edit by edit with
## BuildGrid.apply(), in order, stopping at the first refusal (the plan
## DoorPlacement.edits_for() makes). The plan's whole price (needed()) is taken
## before the grid changes, so a listener on the grid's signals already sees
## it paid; afterwards the price of every edit that was not applied comes
## back, and the refunds of the applied ones are paid. A plan the wallet
## cannot pay for or hold the refunds of changes nothing and is emitted as
## edit_refused for its last edit. Returns the last edit's result with every
## applied edit's dirty cells, or the first refusal.
static func commit_plan(grid: BuildGrid, plan: Array[BuildEdit], wallet: Wallet) -> BuildResult:
	var quotes := _quotes(grid, plan, wallet == null)
	var refusal := _take_price(quotes, wallet)
	if not refusal.ok:
		grid.edit_refused.emit(plan.back(), refusal)
		return refusal
	var applied: Array[bool] = []
	var cleared: Array[Vector2i] = []
	var result: BuildResult = null
	for i in plan.size():
		plan[i].paid = quotes[i].paid
		result = grid.apply(plan[i])
		if not result.ok:
			break
		applied.append(true)
		if i < plan.size() - 1:
			cleared.append_array(result.dirty_cells)
		else:
			result.dirty_cells.append_array(cleared)
	_settle(wallet, quotes, applied)
	return result


## Commits a rectangle: `edits` go through one BuildGrid.apply_batch(), which
## validates each in order and skips the ones it refuses. All or nothing on
## money: when the wallet cannot pay for every edit (or hold the refunds),
## none is applied, each is refused (and emitted as edit_refused) and no money
## moves. Otherwise the whole price is taken before the grid changes, the
## price of every edit the grid refused comes back afterwards, and the
## refunds of the applied ones are paid. Returns one result per edit, in order.
static func commit_batch(
	grid: BuildGrid, edits: Array[BuildEdit], wallet: Wallet
) -> Array[BuildResult]:
	var quotes := _quotes(grid, edits, wallet == null)
	var refusal := _take_price(quotes, wallet)
	var results: Array[BuildResult] = []
	if not refusal.ok:
		for edit in edits:
			var refused := BuildResult.refused(refusal.reason)
			results.append(refused)
			grid.edit_refused.emit(edit, refused)
		return results
	for i in edits.size():
		edits[i].paid = quotes[i].paid
	results = grid.apply_batch(edits)
	var applied: Array[bool] = []
	for result in results:
		applied.append(result.ok)
	_settle(wallet, quotes, applied)
	return results


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


## Accepted, or the reason `wallet` cannot take `quotes`. The wallet must hold
## needed() now, and room for every refund on top of today's balance: after
## the price is taken, at most the price and the refunds come back, so the
## settlement after the grid changes can never pass Wallet.MAX_BALANCE. A null
## wallet (free edits) always takes them.
static func _refusal(quotes: Array[Quote], wallet: Wallet) -> BuildResult:
	if wallet == null:
		return BuildResult.accepted()
	var total := _needed(quotes)
	if total == PriceTable.NO_PRICE:
		return BuildResult.refused(BuildResult.Reason.UNPRICED)
	if not wallet.can_afford(total):
		return BuildResult.refused(BuildResult.Reason.CANT_AFFORD)
	if _refunds(quotes) > Wallet.MAX_BALANCE - wallet.balance:
		return BuildResult.refused(BuildResult.Reason.WALLET_FULL)
	return BuildResult.accepted()


## Checks `quotes` against `wallet` and takes their whole price (needed())
## before any edit is applied. Returns the refusal, with nothing taken, when
## the wallet cannot take them.
static func _take_price(quotes: Array[Quote], wallet: Wallet) -> BuildResult:
	var refusal := _refusal(quotes, wallet)
	if not refusal.ok or wallet == null:
		return refusal
	if not wallet.spend(_needed(quotes)):
		return BuildResult.refused(BuildResult.Reason.CANT_AFFORD)
	return refusal


## After the grid changed: gives back the price taken for every edit that was
## not applied (`applied[i]` false or missing) and pays the refund of every
## applied edit that pays back more than it costs. _refusal() left room for
## all of it, so a failed credit means something else filled the wallet while
## the grid changed; that is reported, not hidden.
static func _settle(wallet: Wallet, quotes: Array[Quote], applied: Array[bool]) -> void:
	if wallet == null:
		return
	var back := 0
	for i in quotes.size():
		var net := quotes[i].net()
		var done := i < applied.size() and applied[i]
		if done and net < 0:
			back -= net
		elif not done and net > 0:
			back += net
	if back > 0 and not wallet.credit(back):
		push_error("BuildTransaction: %d owed back did not fit the wallet" % back)


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
