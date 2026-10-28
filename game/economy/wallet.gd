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
## credit, `claimed` is what credit_claim took to pay debts, as Category ->
## amount with only the shares above 0 (the balance moved by amount less their
## sum; empty for a spend or a credit no debt took from). `tick` is the clock's
## tick, or NO_TICK when the wallet has no clock.
signal transaction(amount: int, category: int, claimed: Dictionary, tick: int)

## What a movement is for. There is deliberately no catch-all: every caller
## says which one. UPKEEP is the daily running cost of rooms (toilet stalls).
enum Category { FEES, SHOP, GRANT, OPENING, BUILD, WAGES, UPKEEP }

## Upper bound on the balance, far below 2^53, so a JSON round trip and any
## sum of in-range amounts stay exact.
const MAX_BALANCE := 999_999_999_999
const SNAPSHOT_KEYS := ["balance"]
## The tick of a transaction from a wallet with no clock.
const NO_TICK := -1

var balance: int = 0
## Optional: debts that take a share of each credit before the balance sees
## it (Settlement's owed wages and owed upkeep). Called as claim(amount, commit)
## and returns a Dictionary of Category -> share, the debt each share pays:
## with commit false it says what it would take and changes nothing; with true
## it takes that and pays the debts. Every share is a whole number from 0 and
## together they are at most `amount`; a claim that breaks that pushes an error
## and the credit is refused. The balance gets the rest, and room is checked on
## that rest. Unset or freed, the whole credit lands. A load restores the
## balance as it was saved and claims nothing.
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


## Adds `amount`, less what credit_claim takes for debts. Returns false and
## leaves the balance and the debts unchanged when the amount is negative, the
## category unknown, the claim invalid, or what is left after the debts would
## pass MAX_BALANCE. Zero succeeds silently.
func credit(amount: int, category: Category) -> bool:
	if not _known(category):
		return false
	var claimed: Variant = _claims(amount, false)
	var taken := -1 if claimed == null else _claimed_total(claimed, amount)
	if taken < 0:
		return false
	if amount < 0 or amount - taken > MAX_BALANCE - balance:
		push_error("Wallet.credit: %d is not creditable at balance %d" % [amount, balance])
		return false
	_claims(amount, true)
	_set_balance(balance + amount - taken)
	_emit(amount, category, claimed)
	return true


## Takes `amount`. Returns false and leaves the balance unchanged when the
## amount is negative or more than the balance, or the category unknown. Zero
## succeeds silently.
func spend(amount: int, category: Category) -> bool:
	if not _known(category) or not can_afford(amount):
		return false
	_set_balance(balance - amount)
	_emit(-amount, category, {})
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


func _emit(amount: int, category: Category, claimed: Dictionary) -> void:
	if amount == 0:
		return
	transaction.emit(amount, category, claimed, clock.tick if is_instance_valid(clock) else NO_TICK)


## credit_claim's shares of `amount`, with the shares of 0 left out; empty when
## there is no claim or nothing to claim from, null (with an error pushed) when
## the claim does not return a Dictionary.
func _claims(amount: int, commit: bool) -> Variant:
	if amount <= 0 or not credit_claim.is_valid():
		return {}
	var shares: Variant = credit_claim.call(amount, commit)
	if typeof(shares) != TYPE_DICTIONARY:
		push_error("Wallet: credit_claim returned %s, not a Dictionary" % [shares])
		return null
	var result := {}
	for key in shares:
		if typeof(shares[key]) != TYPE_INT or shares[key] != 0:
			result[key] = shares[key]
	return result


## The sum of `claimed`, or -1 (with an error pushed) when a share is not a
## whole number from 0 under a known Category or the sum passes `amount`.
func _claimed_total(claimed: Dictionary, amount: int) -> int:
	var total := 0
	for key in claimed:
		var share: Variant = claimed[key]
		if typeof(key) != TYPE_INT or not Category.values().has(key):
			push_error("Wallet: credit_claim named %s, not a Wallet.Category" % [key])
			return -1
		if typeof(share) != TYPE_INT or share < 0:
			push_error("Wallet: credit_claim share %s is not a whole number from 0" % [share])
			return -1
		total += share
	if total > maxi(amount, 0):
		push_error("Wallet: credit_claim took %d of a credit of %d" % [total, amount])
		return -1
	return total


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
