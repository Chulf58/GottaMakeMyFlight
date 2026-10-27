class_name Finances
extends Node
## The scene's one Wallet, so every system that earns or spends shares a
## balance: cafe visits pay into it now (Cafe 2/2), and build costs, airline
## fees and the money slot (Economy 4/8 to 7/8) are to use the same node. The
## balance starts at 0; the starting budget is Economy 7/8's new-game setup.

var wallet := Wallet.new()
