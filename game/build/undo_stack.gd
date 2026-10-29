class_name UndoStack
extends RefCounted
## BuildMode's undo history (decision
## build-mode-undo-design-action-receipts-with-before-values-at, point 5): the
## BuildReceipt of each of the last CAPACITY player build actions, newest on
## top. Not saved, and there is no redo.
##
## BuildMode brackets each action with begin_action() and end_action(): the
## grid records into a fresh receipt meanwhile and the wallet's build
## transactions add up its money. A receipt with nothing in it (a refused
## action) is dropped. undo() replays the newest through BuildUndo with
## recording off.
##
## The history is cleared when anything changes the grid or the build money's
## meaning from outside an action: a grid edit or snapshot load that arrives
## while no action or undo runs (a save load, the debug starter terminal), a
## rescue grant paying (Wallet.Category.GRANT; undoing the removals that made
## the airport stuck would keep the grant) and a new game's starting budget
## (Wallet.Category.OPENING). A grid replaced from a snapshot in the middle of
## an action (BuildTransaction rolling a commit back) clears it too.

const CAPACITY := 20
const NOTHING_TO_UNDO := "Nothing to undo"
const UNDONE := "Undone"
const CANT_UNDO := "Can't undo"

var _receipts: Array[BuildReceipt] = []
var _grid: BuildGrid
var _wallet: Wallet
## Open actions and undos: grid and wallet changes inside them are BuildMode's.
var _depth := 0
var _receipt: BuildReceipt = null


## Follows `grid` and `wallet` (null for free building). Call once.
func watch(grid: BuildGrid, wallet: Wallet) -> void:
	_grid = grid
	_wallet = wallet
	grid.edit_applied.connect(_on_edit_applied)
	grid.graph_changed.connect(_on_graph_changed)
	if wallet != null:
		wallet.transaction.connect(_on_transaction)


func size() -> int:
	return _receipts.size()


## The newest receipt, or null when the history is empty. Read it, never change it.
func peek() -> BuildReceipt:
	return null if _receipts.is_empty() else _receipts.back()


func clear() -> void:
	_receipts.clear()


## Opens a player action. Actions nest (a rectangle that is one click); only
## the outermost records.
func begin_action() -> void:
	_depth += 1
	if _depth == 1:
		_receipt = BuildReceipt.new()
		_grid.recorder = _receipt


## Closes the action begin_action() opened and keeps its receipt.
func end_action() -> void:
	_depth -= 1
	if _depth > 0:
		return
	_grid.recorder = null
	var receipt := _receipt
	_receipt = null
	if receipt.replaced:
		clear()
	elif not receipt.is_empty():
		_receipts.append(receipt)
		if _receipts.size() > CAPACITY:
			_receipts.pop_front()


## Undoes the newest action (BuildUndo.commit()) and drops it from the history.
## Null when the history is empty; a refusal keeps it.
func undo(shell: ShellDefinition = null) -> BuildResult:
	var receipt := peek()
	if receipt == null:
		return null
	_depth += 1
	var result := BuildUndo.commit(_grid, receipt, _wallet, shell)
	_depth -= 1
	if result.ok:
		_receipts.pop_back()
	return result


func _on_edit_applied(_edit: BuildEdit, _result: BuildResult) -> void:
	if _depth == 0:
		clear()


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	if _depth == 0:
		clear()


func _on_transaction(amount: int, category: int, _claimed: Dictionary, _tick: int) -> void:
	if category == Wallet.Category.GRANT or category == Wallet.Category.OPENING:
		clear()
	elif category == Wallet.Category.BUILD and _receipt != null:
		_receipt.money += amount
