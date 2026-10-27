class_name Finances
extends Node
## The scene's one Wallet, so every system that earns or spends shares a
## balance: cafe visits pay into it (Cafe 2/2), BuildMode pays for building
## from it (Economy 4/8, BuildTransaction), and airline fees and the money slot
## (Economy 5/8 and 7/8) are to use the same node.
##
## The wallet is set up once, in one of two ways: start_new_game() credits
## PriceTable.STARTING_BUDGET, and restore() loads a saved balance, replacing
## whatever was there. After either, start_new_game() is refused, so a
## restored game is never credited the budget. When neither has run by the time the node enters the
## tree, it is a new game: main.tscn takes that path. Economy 7/8's new-game
## setup is to call start_new_game() itself, and Economy 8/8's load restore().
## Restore through restore(), never through wallet.from_snapshot() directly,
## or entering the tree credits the budget on top.

var wallet := Wallet.new()

var _set_up := false


func _ready() -> void:
	if not _set_up:
		start_new_game()


## Credits the starting budget. Returns false and changes nothing when the
## wallet was already set up, by an earlier call or by restore().
func start_new_game() -> bool:
	if _set_up:
		return false
	_set_up = true
	return wallet.credit(PriceTable.STARTING_BUDGET)


## Restores a Wallet.to_snapshot() dictionary and marks the wallet set up, so
## the starting budget is never credited on top. Returns false and changes
## nothing when the wallet refuses the data (Wallet.from_snapshot()).
func restore(data: Dictionary) -> bool:
	if not wallet.from_snapshot(data):
		return false
	_set_up = true
	return true
