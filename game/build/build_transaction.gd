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


## Accepted when `wallet` can pay for `edits`, else refused with CANT_AFFORD,
## or UNPRICED when a piece has no price. A null wallet always pays.
static func check(grid: BuildGrid, edits: Array[BuildEdit], wallet: Wallet) -> BuildResult:
	if wallet == null:
		return BuildResult.accepted()
	return _refusal(_quotes(grid, edits, false), wallet)


## Commits one player action: `plan` is applied edit by edit with
## BuildGrid.apply(), in order, stopping at the first refusal (the plan
## DoorPlacement.edits_for() makes). It commits only if the wallet can pay for
## the whole plan; a refusal for money changes nothing and is emitted as
## edit_refused for the plan's last edit. Money moves for the edits the grid
## accepted. Returns the last edit's result with every applied edit's dirty
## cells, or the first refusal.
static func commit_plan(grid: BuildGrid, plan: Array[BuildEdit], wallet: Wallet) -> BuildResult:
	var quotes := _quotes(grid, plan, wallet == null)
	var refusal := _refusal(quotes, wallet)
	if not refusal.ok:
		grid.edit_refused.emit(plan.back(), refusal)
		return refusal
	var net := 0
	var cleared: Array[Vector2i] = []
	var result: BuildResult = null
	for i in plan.size():
		plan[i].paid = quotes[i].paid
		result = grid.apply(plan[i])
		if not result.ok:
			break
		net += quotes[i].net()
		if i < plan.size() - 1:
			cleared.append_array(result.dirty_cells)
		else:
			result.dirty_cells.append_array(cleared)
	_settle(wallet, net)
	return result


## Commits a rectangle: `edits` go through one BuildGrid.apply_batch(), which
## validates each in order and skips the ones it refuses. All or nothing on
## money: when the wallet cannot pay for every edit, none is applied, each is
## refused with CANT_AFFORD (and emitted as edit_refused) and nothing is
## spent. Otherwise money moves for the edits the grid accepted. Returns one
## result per edit, in order.
static func commit_batch(
	grid: BuildGrid, edits: Array[BuildEdit], wallet: Wallet
) -> Array[BuildResult]:
	var quotes := _quotes(grid, edits, wallet == null)
	var refusal := _refusal(quotes, wallet)
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
	var net := 0
	for i in results.size():
		if results[i].ok:
			net += quotes[i].net()
	_settle(wallet, net)
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


## Accepted, or the reason `wallet` cannot take `quotes`. A null wallet
## (free edits) always takes them.
static func _refusal(quotes: Array[Quote], wallet: Wallet) -> BuildResult:
	if wallet == null:
		return BuildResult.accepted()
	var total := _needed(quotes)
	if total == PriceTable.NO_PRICE:
		return BuildResult.refused(BuildResult.Reason.UNPRICED)
	if not wallet.can_afford(total):
		return BuildResult.refused(BuildResult.Reason.CANT_AFFORD)
	return BuildResult.accepted()


## Takes or pays back `net`. The affordability check covers every subset of
## the checked edits, so a failed spend means that invariant broke.
static func _settle(wallet: Wallet, net: int) -> void:
	if wallet == null or net == 0:
		return
	if net > 0:
		if not wallet.spend(net):
			push_error("BuildTransaction: could not take %d from %d" % [net, wallet.balance])
	else:
		wallet.credit(-net)


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
