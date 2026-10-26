class_name Wallet
extends RefCounted
## The player's money: a whole-number balance that never goes negative (no
## loans). Plain data; the price list lives in PriceTable.

signal changed(balance: int)

## Upper bound on the balance, far below 2^53, so a JSON round trip and any
## sum of in-range amounts stay exact.
const MAX_BALANCE := 999_999_999_999
const SNAPSHOT_KEYS := ["balance"]

var balance: int = 0


## A starting balance outside [0, MAX_BALANCE] pushes an error and leaves the
## wallet at 0 rather than holding an invalid balance.
func _init(starting_balance: int = 0) -> void:
	if starting_balance < 0 or starting_balance > MAX_BALANCE:
		push_error("Wallet: starting balance %d is outside 0..%d" % [starting_balance, MAX_BALANCE])
		return
	balance = starting_balance


func can_afford(amount: int) -> bool:
	return amount >= 0 and amount <= balance


## Adds `amount`. Returns false and leaves the balance unchanged when the
## amount is negative or would pass MAX_BALANCE. Zero succeeds silently.
func credit(amount: int) -> bool:
	if amount < 0 or amount > MAX_BALANCE - balance:
		push_error("Wallet.credit: %d is not creditable at balance %d" % [amount, balance])
		return false
	_set_balance(balance + amount)
	return true


## Takes `amount`. Returns false and leaves the balance unchanged when the
## amount is negative or more than the balance. Zero succeeds silently.
func spend(amount: int) -> bool:
	if not can_afford(amount):
		return false
	_set_balance(balance - amount)
	return true


## JSON-safe state for a save. The balance is a decimal string, like the
## SimClock tick, so it survives a JSON round trip exactly.
func to_snapshot() -> Dictionary:
	return {"balance": str(balance)}


## Restores a to_snapshot() dictionary. Pushes an error and returns false,
## leaving the wallet unchanged, when a key is missing or unknown or the
## balance is not a canonical decimal string in [0, MAX_BALANCE].
func from_snapshot(data: Dictionary) -> bool:
	var problem := _snapshot_problem(data)
	if problem != "":
		push_error("Wallet.from_snapshot: %s" % problem)
		return false
	_set_balance(str(data["balance"]).to_int())
	return true


func _snapshot_problem(data: Dictionary) -> String:
	for key in data.keys():
		if not SNAPSHOT_KEYS.has(key):
			return "unknown key '%s'" % key
	if not data.has("balance"):
		return "missing key 'balance'"
	var text: Variant = data["balance"]
	if not SimClock.is_int64_string(text) or str(text).begins_with("-"):
		return "balance must be a decimal string, 0 or more"
	if str(text).to_int() > MAX_BALANCE:
		return "balance must be at most %d" % MAX_BALANCE
	return ""


func _set_balance(value: int) -> void:
	if value == balance:
		return
	balance = value
	changed.emit(balance)
