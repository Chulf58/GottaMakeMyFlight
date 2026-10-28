class_name Wallet
extends RefCounted
## The player's money: a whole-number balance that never goes negative (no
## loans). Plain data; the price list lives in PriceTable.
##
## Every credit and spend names what the money is for (Category), and every
## movement that happens emits one transaction (decision money-hover-design-
## categorised-wallet-transactions-feed-a-sa), which the DayLedger adds up per
## day. A refused movement and a snapshot restore emit none.

signal changed(balance: int)
## Money moved: `amount` is the gross amount, negative for a spend; for a
## credit, `wages_claimed` is the part credit_claim took for owed wages (the
## balance moved by amount - wages_claimed). `tick` is the clock's tick, or
## NO_TICK when the wallet has no clock.
signal transaction(amount: int, category: int, wages_claimed: int, tick: int)

## What a movement is for. There is deliberately no catch-all: every caller
## says which one.
enum Category { FEES, SHOP, GRANT, OPENING, BUILD, WAGES }

## Upper bound on the balance, far below 2^53, so a JSON round trip and any
## sum of in-range amounts stay exact.
const MAX_BALANCE := 999_999_999_999
const SNAPSHOT_KEYS := ["balance"]
## The tick of a transaction from a wallet with no clock.
const NO_TICK := -1

var balance: int = 0
## Optional: a debt that takes a share of each credit before the balance sees
## it (Settlement's owed wages). Called as claim(amount, commit): with commit
## false it returns how much it would take and changes nothing; with true it
## takes that, pays the debt and returns it. The balance gets the rest, and
## room is checked on that rest. Unset or freed, the whole credit lands. A load
## restores the balance as it was saved and claims nothing.
var credit_claim: Callable
## Stamps each transaction with its tick; Finances sets the scene's clock.
var clock: SimClock


## A starting balance outside [0, MAX_BALANCE] pushes an error and leaves the
## wallet at 0 rather than holding an invalid balance.
func _init(starting_balance: int = 0) -> void:
	if starting_balance < 0 or starting_balance > MAX_BALANCE:
		push_error("Wallet: starting balance %d is outside 0..%d" % [starting_balance, MAX_BALANCE])
		return
	balance = starting_balance


func can_afford(amount: int) -> bool:
	return amount >= 0 and amount <= balance


## Adds `amount`, less what credit_claim takes for a debt. Returns false and
## leaves the balance and the debt unchanged when the amount is negative, the
## category unknown, or what is left after the debt would pass MAX_BALANCE.
## Zero succeeds silently.
func credit(amount: int, category: Category) -> bool:
	if not _known(category):
		return false
	var taken := _claimed(amount, false)
	if amount < 0 or amount - taken > MAX_BALANCE - balance:
		push_error("Wallet.credit: %d is not creditable at balance %d" % [amount, balance])
		return false
	_claimed(amount, true)
	_set_balance(balance + amount - taken)
	_emit(amount, category, taken)
	return true


## Takes `amount`. Returns false and leaves the balance unchanged when the
## amount is negative or more than the balance, or the category unknown. Zero
## succeeds silently.
func spend(amount: int, category: Category) -> bool:
	if not _known(category) or not can_afford(amount):
		return false
	_set_balance(balance - amount)
	_emit(-amount, category, 0)
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


func _known(category: int) -> bool:
	if Category.values().has(category):
		return true
	push_error("Wallet: %d is not a Wallet.Category" % category)
	return false


func _emit(amount: int, category: Category, wages_claimed: int) -> void:
	if amount == 0:
		return
	transaction.emit(
		amount, category, wages_claimed, clock.tick if is_instance_valid(clock) else NO_TICK
	)


func _claimed(amount: int, commit: bool) -> int:
	if amount <= 0 or not credit_claim.is_valid():
		return 0
	var taken: int = credit_claim.call(amount, commit)
	return clampi(taken, 0, amount)


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
