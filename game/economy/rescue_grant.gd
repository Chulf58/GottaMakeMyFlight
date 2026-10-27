class_name RescueGrant
extends Node
## The one-off rescue grant (ruling going-broke-a-one-off-rescue-grant-when-the-
## airport-is-stuck): no loans and no game over, so an airport that cannot earn
## again is helped once. The airport is stuck when an essential (entrance,
## check-in desk, security scanner, exit door) is missing, the wallet cannot
## pay for the missing ones and no passenger inside can still make a flight.
## The grant is the shortfall: it brings the balance up to the price of the
## missing pieces, no more, and `granted` carries the message to show.
##
## One grant per stuck event. The event lasts until every essential stands
## again; only then can a later loss start a new one. The latch is saved
## (to_snapshot) so a load in the middle of an event cannot pay twice.
##
## The check runs on each SimClock tick and never from a BuildGrid signal: the
## wallet is not touched from inside a grid handler (build transaction staging
## is still open work), and PassengerSim has rebuilt its layout from the grid
## by the next tick. A grid edit therefore pays out at the next tick.

## Paid, with the player-facing message.
signal granted(amount: int, message: String)

const SNAPSHOT_KEYS := ["granted"]
## The essentials in message order: {object id, name shown to the player}.
const ESSENTIALS := [
	[&"entrance_door", "entrance"],
	[&"checkin_desk", "check-in desk"],
	[&"security_scanner", "security scanner"],
	[&"exit_door", "exit"],
]

## The journey stages that still need the check-in desk, the scanner (before
## the gate) and only the exit. Cafe stages need none: the visit ends and the
## journey resumes.
const DESK_STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.SPAWNED,
	Passenger.Stage.TO_CHECKIN,
	Passenger.Stage.CHECKIN_QUEUE,
	Passenger.Stage.CHECKIN,
]
const SCANNER_STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.TO_SECURITY,
	Passenger.Stage.SECURITY_QUEUE,
	Passenger.Stage.SECURITY,
]
const EXIT_STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.TO_GATE,
	Passenger.Stage.SITTING_DOWN,
	Passenger.Stage.SEATED,
	Passenger.Stage.STANDING,
	Passenger.Stage.STANDING_UP,
	Passenger.Stage.TO_EXIT,
	Passenger.Stage.APRON,
]

## In a scene these come from the wired nodes; tests call bind().
@export var clock: SimClock
@export var passengers: PassengerSim
@export var finances: Finances

var _clock: SimClock
var _sim: PassengerSim
var _wallet: Wallet
## True from the grant until every essential stands again.
var _granted := false


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


## The essentials the terminal has none of, as object ids in ESSENTIALS order.
func missing_essentials() -> Array[StringName]:
	var layout := _sim.layout
	var present := [
		not layout.entrances.is_empty(),
		not layout.desks.is_empty(),
		not layout.scanners.is_empty(),
		not layout.exits.is_empty(),
	]
	var missing: Array[StringName] = []
	for i in ESSENTIALS.size():
		if not present[i]:
			missing.append(ESSENTIALS[i][0])
	return missing


## Pays the grant if the airport is stuck and has not been helped in this
## event. True when a grant was paid. Called on every tick.
func evaluate() -> bool:
	var missing := missing_essentials()
	if missing.is_empty():
		_granted = false
		return false
	if _granted:
		return false
	var cost := 0
	for def in missing:
		cost += PriceTable.price_of_object(def)
	if _wallet.balance >= cost or _someone_can_make_a_flight(missing):
		return false
	var amount := cost - _wallet.balance
	if not _wallet.credit(amount):
		return false
	_granted = true
	granted.emit(amount, _message(amount, missing))
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


## True when a passenger who has not finished has only pieces left to use that
## still stand. A passenger on a cafe visit counts: the visit ends and the
## journey is judged again on a later tick.
func _someone_can_make_a_flight(missing: Array[StringName]) -> bool:
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		if p.is_done():
			continue
		var needs := _needs_of(p.stage)
		var blocked := false
		for def in needs:
			if missing.has(def):
				blocked = true
				break
		if not blocked:
			return true
	return false


## The pieces a passenger at `stage` still has to use, in journey order.
static func _needs_of(stage: Passenger.Stage) -> Array[StringName]:
	if DESK_STAGES.has(stage):
		return [&"checkin_desk", &"security_scanner", &"exit_door"]
	if SCANNER_STAGES.has(stage):
		return [&"security_scanner", &"exit_door"]
	if EXIT_STAGES.has(stage):
		return [&"exit_door"]
	return []


static func _message(amount: int, missing: Array[StringName]) -> String:
	var names := PackedStringArray()
	for def in missing:
		for essential in ESSENTIALS:
			if essential[0] == def:
				names.append(essential[1])
	return (
		"The airport authority has sent a rescue grant of %d to rebuild: %s. It is a one-off."
		% [amount, ", ".join(names)]
	)
