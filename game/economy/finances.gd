class_name Finances
extends Node
## The scene's one Wallet, so every system that earns or spends shares a
## balance: cafe visits pay into it (Cafe 2/2), BuildMode pays for building
## from it (Economy 4/8, BuildTransaction), and airline fees and the money slot
## (Economy 5/8 and 7/8) are to use the same node.
##
## A new game starts with PriceTable.STARTING_BUDGET, credited once when the
## node enters the tree. This is the stand-in for Economy 7/8's new-game
## setup, which is to take it over. A save load (Economy 8/8) restores the
## wallet with Wallet.from_snapshot(), which replaces the balance and never
## credits the budget again.

var wallet := Wallet.new()

var _budget_given := false


func _ready() -> void:
	start_new_game()


## Credits the starting budget. Returns false and changes nothing when it was
## already credited.
func start_new_game() -> bool:
	if _budget_given:
		return false
	_budget_given = true
	return wallet.credit(PriceTable.STARTING_BUDGET)
