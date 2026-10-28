class_name RescueGrant
extends Node
## The one-off rescue grant (ruling going-broke-a-one-off-rescue-grant-when-the-
## airport-is-stuck): no loans and no game over, so an airport that cannot earn
## again is helped once. The airport is stuck when a new passenger has no
## working path (RepairPlan.has_working_path(): entrance, check-in desk,
## scanner, exit, each reachable on foot), the wallet cannot pay for the
## repair and no passenger in the terminal can still make a flight. The grant
## is the shortfall: it brings the balance up to the repair's price
## (RepairPlan.least_balance() of RepairPlan.make()'s edits: the missing
## pieces, the floor they stand on and the floor that joins them up, bought in
## order with each refund paying toward the rest), no more, and `granted`
## carries the message to show. Owed wages and owed upkeep (together
## Settlement.claimed_debt()) are paid out of any credit the moment it lands,
## so the grant adds them on top: it clears both debts and still leaves the
## repair's funding in the wallet.
##
## One grant per stuck event. The event lasts until a working path exists
## again; only then can a later loss start a new one. The latch is saved
## (to_snapshot) so a load in the middle of an event cannot pay twice.
##
## The check runs on each SimClock tick and never from a BuildGrid signal: the
## wallet is not touched from inside a grid handler (build transaction staging
## is still open work), and PassengerSim has rebuilt its layout from the grid
## by the next tick. A grid edit therefore pays out at the next tick. The grid's
## signals only mark the cached working-path answer and repair plan stale and
## keep the plan's price bound; the route search runs again on the next tick.
##
## Planning copies the grid and searches it, which is too slow to redo on
## every tick after every build click. So the price of the last plan made is
## kept as an upper bound on what a repair costs, raised by each edit since by
## the most that edit can add to a repair: the floor's price for floor taken
## up, the dearest essential's price for an object taken away, nothing for
## anything placed or painted (taking it away again costs nothing). While the
## wallet holds at least the bound, a repair it can pay for exists and no new
## plan is made. A grid change that is not an edit (a load) forgets the bound.

## Paid, with the player-facing message.
signal granted(amount: int, message: String)

const SNAPSHOT_KEYS := ["granted"]
## The name shown to the player for each piece a repair can place.
const PIECE_NAMES := {
	&"entrance_door": "entrance",
	&"checkin_desk": "check-in desk",
	&"security_scanner": "security scanner",
	&"exit_door": "exit",
}

## In a scene these come from the wired nodes; tests call bind().
@export var clock: SimClock
@export var passengers: PassengerSim
@export var finances: Finances
## Optional: its owed wages and upkeep are added to the grant (see the class notes). Tests
## set it after bind(); without it a grant is the repair's shortfall alone.
@export var settlement: Settlement

var _clock: SimClock
var _sim: PassengerSim
var _wallet: Wallet
## True from the grant until a working path exists again.
var _granted := false
## The repair for the grid as it stands; null once the grid changes.
var _plan: RepairPlan
var _watched: BuildGrid
## At least what a repair costs now, or -1 when unknown (see the class notes).
var _bound := -1
## Set by an edit that changed cells, so graph_changed can tell edits from loads.
var _edit_seen := false
## The working-path answer for the grid as it stands, redone once it is stale.
var _path_ok := false
var _path_dirty := true


func _ready() -> void:
	if clock == null or passengers == null or finances == null:
		push_error("RescueGrant: clock, passengers and finances must all be set")
		return
	bind(clock, passengers, finances.wallet)


## Checks on `with_clock`'s ticks and pays into `with_wallet`. Binding the
## clock already followed does nothing new; binding another lets go of the first.
func bind(with_clock: SimClock, sim: PassengerSim, with_wallet: Wallet) -> void:
	_sim = sim
	_wallet = with_wallet
	if with_clock == _clock:
		return
	if _clock != null:
		_clock.ticked.disconnect(_on_tick)
	_clock = with_clock
	_clock.ticked.connect(_on_tick)


## Whether a new passenger can walk the whole journey on the grid as it stands.
## The answer is kept until the grid changes.
func has_working_path() -> bool:
	_watch_grid()
	if _path_dirty:
		_path_ok = RepairPlan.has_working_path(_sim.grid, _sim.layout)
		_path_dirty = false
	return _path_ok


## The repair for the grid as it stands, made once per grid change.
func repair_plan() -> RepairPlan:
	_watch_grid()
	if _plan == null:
		_plan = RepairPlan.make(_sim.grid, _sim.shell)
		_bound = _price_of(_plan)
	return _plan


## Pays the grant if the airport is stuck and has not been helped in this
## event. True when a grant was paid. Called on every tick.
func evaluate() -> bool:
	if has_working_path():
		_granted = false
		return false
	if _granted or _someone_can_make_a_flight():
		return false
	var amount := _shortfall()
	if amount <= 0:
		return false
	var wages := settlement.wages_owed() if settlement != null else 0
	var upkeep := settlement.upkeep_owed() if settlement != null else 0
	var debt := settlement.claimed_debt() if settlement != null else 0
	if not _wallet.credit(amount + debt, Wallet.Category.GRANT):
		return false
	_granted = true
	granted.emit(amount + debt, _message(amount, repair_plan().edits, wages, upkeep))
	return true


## JSON-safe state for a save: whether the current stuck event was paid.
func to_snapshot() -> Dictionary:
	return {"granted": _granted}


## Restores a to_snapshot() dictionary. Pushes an error and returns false,
## changing nothing, for a missing or unknown key or a non-boolean value.
func from_snapshot(data: Dictionary) -> bool:
	for key in data.keys():
		if not SNAPSHOT_KEYS.has(key):
			push_error("RescueGrant.from_snapshot: unknown key '%s'" % key)
			return false
	if not data.has("granted") or typeof(data["granted"]) != TYPE_BOOL:
		push_error("RescueGrant.from_snapshot: 'granted' must be true or false")
		return false
	_granted = data["granted"]
	return true


func _on_tick(_tick: int) -> void:
	evaluate()


## What the repair costs beyond the balance, or 0 when the wallet can pay for
## one (by the kept bound or the plan's own price) or no repair was found.
func _shortfall() -> int:
	_watch_grid()
	if _bound >= 0 and _wallet.balance >= _bound:
		return 0
	var cost := _price_of(repair_plan())
	return maxi(cost - _wallet.balance, 0) if cost >= 0 else 0


## What `plan` costs: its edits bought in order, or its fallback price when the
## caps ran out; -1 when there is no repair to price.
func _price_of(plan: RepairPlan) -> int:
	if not plan.ok:
		return plan.fallback_price
	var cost := RepairPlan.least_balance(_sim.grid, plan.edits)
	if cost == PriceTable.NO_PRICE:
		push_error("RescueGrant: the repair has a piece with no price")
		return -1
	return cost


func _watch_grid() -> void:
	if _watched == _sim.grid:
		return
	if _watched != null:
		_watched.graph_changed.disconnect(_on_graph_changed)
		_watched.edit_applied.disconnect(_on_edit_applied)
	_watched = _sim.grid
	_watched.graph_changed.connect(_on_graph_changed)
	_watched.edit_applied.connect(_on_edit_applied)
	_plan = null
	_bound = -1
	_path_dirty = true


func _on_edit_applied(edit: BuildEdit, result: BuildResult) -> void:
	if result.dirty_cells.is_empty():
		return
	_edit_seen = true
	if _bound < 0:
		return
	match edit.kind:
		BuildEdit.Kind.REMOVE_FLOOR:
			var floor_edit := BuildEdit.paint_floor(edit.cell, BuildGrid.FLOOR_TILE, 1)
			_bound += maxi(BuildTransaction.quote(_watched, floor_edit).net(), 0)
		BuildEdit.Kind.REMOVE_OBJECT:
			_bound += _dearest_essential()


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	_plan = null
	_path_dirty = true
	if not _edit_seen:
		_bound = -1
	_edit_seen = false


func _dearest_essential() -> int:
	var most := 0
	for def_id in PIECE_NAMES:
		var edit := BuildEdit.place_object(def_id, Vector2i.ZERO, 0)
		most = maxi(most, BuildTransaction.quote(_watched, edit).net())
	return most


## True when a passenger who has not finished still has a route from where it
## stands through the pieces it has left to use. A guest on a facility visit
## is judged by the stage its journey resumes at (StageKinds.resume_of()),
## from the cell it sets off from (a cafe seat's approach) when it is at the
## seat. A gate sitter is judged from the cell in front of its seat.
func _someone_can_make_a_flight() -> bool:
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		if p.is_done():
			continue
		if p.stage == Passenger.Stage.APRON:
			return true
		var stage := p.stage
		var start := p.at
		var where := StageKinds.location(stage)
		if StageKinds.in_visit(stage):
			var resume := StageKinds.resume_of(_sim, p)
			if resume.is_empty():
				continue
			stage = resume["stage"]
			if not _sim.grid.is_walkable(start) and resume["cell"] != Passenger.NO_CELL:
				start = resume["cell"]
		elif where == StageKinds.Location.GATE_SEAT and p.seat_front != Passenger.NO_CELL:
			start = p.seat_front
		elif stage == Passenger.Stage.SECURITY:
			start = p.path_end()
		var starts: Array[Vector2i] = [start]
		if RepairPlan.can_finish(_sim.grid, _sim.layout, starts, _first_leg(stage)):
			return true
	return false


## The first leg a passenger at `stage` still has to walk. One inside a
## scanner's passage is judged from beyond it, so only its exit is left.
static func _first_leg(stage: Passenger.Stage) -> int:
	match StageKinds.leg(stage):
		StageKinds.Leg.CHECKIN:
			return RepairPlan.Leg.DESK
		StageKinds.Leg.SECURITY:
			if stage != Passenger.Stage.SECURITY:
				return RepairPlan.Leg.SCANNER
	return RepairPlan.Leg.EXIT


static func _message(amount: int, edits: Array[BuildEdit], wages := 0, upkeep := 0) -> String:
	var names := PackedStringArray()
	for edit in edits:
		if edit.kind == BuildEdit.Kind.PLACE_OBJECT and PIECE_NAMES.has(edit.def_id):
			names.append(PIECE_NAMES[edit.def_id])
	for edit in edits:
		if edit.kind == BuildEdit.Kind.PAINT_FLOOR:
			names.append("floor")
			break
	var what := ", ".join(names) if not names.is_empty() else "a way through the terminal"
	var text := (
		"The airport authority has sent a rescue grant of %d to rebuild: %s. It is a one-off."
		% [amount, what]
	)
	if wages > 0 and upkeep > 0:
		text += (
			" A further %d clears the owed wages (%d) and upkeep (%d)."
			% [wages + upkeep, wages, upkeep]
		)
	elif wages > 0:
		text += " A further %d clears the owed wages." % wages
	elif upkeep > 0:
		text += " A further %d clears the owed upkeep." % upkeep
	return text
