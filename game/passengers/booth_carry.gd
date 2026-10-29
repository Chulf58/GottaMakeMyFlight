class_name BoothCarry
extends RefCounted
## How a passenger carries through a basic scanner booth (decision basic-
## scanner-booth-passengers-carry-their-bags-in-front-and): CarryOnProps asks
## these while SecurityLooks.in_booth_passage() holds. The free arms tuck in
## (a turn of its own, eased over CarryOnProps.TRANSFER_TICKS like the front
## carry), a passenger without bags included; a roller is lifted into the hand
## at the booth's entry and that move ends at the side before the turn to the
## front, and past the booth it stays in hand until the turn back has ended,
## so it never passes through the body. Pure: it reads and writes only the
## held record it is given.

## A free hand tucked in: aimed this far out, about over the elbow, so the
## forearm points ahead and the fingers stay inside the booth's 0.41 m
## half-opening (at CarryOnProps.FRONT_FREE_HAND_M they reach about 0.43 m).
const TUCK_HAND_M := 0.22
## The same for a free hand beside a front-carried case: further out, so its
## fingertips stay clear of the case.
const TUCK_BESIDE_M := 0.28


## How far `held` has tucked its free arms in at sim time `now`, 0 (swinging)
## to 1 (tucked). Its own turn, so a front carry that goes on past the booth
## (a closed cell beyond it) does not keep the arms tucked.
static func tuck_weight(held: Dictionary, now: float) -> float:
	var target := 1.0 if held.get("tuck", false) else 0.0
	if not held.has("tuck_since"):
		return target
	var k := clampf((now - held["tuck_since"]) / CarryOnProps.TRANSFER_TICKS, 0.0, 1.0)
	return lerpf(held["tuck_from"], target, 1.0 - (1.0 - k) * (1.0 - k))


## Starts the turn in or out when `booth` changes, at `tick`. A new record
## starts tucked only when `restored` (made again after a load); a new one,
## walking in, turns in from the swing.
static func update_tuck(held: Dictionary, booth: bool, restored: bool, tick: float) -> void:
	if not held.has("tuck"):
		held["tuck"] = booth and restored
	if booth != held["tuck"]:
		held["tuck_from"] = tuck_weight(held, tick)
		held["tuck_since"] = tick
		held["tuck"] = booth


## Where a free hand aims while `tuck` of the way in: beside a front-carried
## case (`beside`) or not.
static func free_hand_width(beside: bool, tuck: float) -> float:
	var tucked_at := TUCK_BESIDE_M if beside else TUCK_HAND_M
	return lerpf(CarryOnProps.FRONT_FREE_HAND_M, tucked_at, tuck)


## Whether a roller of `held` is going into the hand at `tick`: lifted now
## (`lifts`) from the pull, or lifted less than TRANSFER_TICKS ago.
static func roller_rising(
	held: Dictionary, kinds: Array[SecurityLooks.Kind], lifts: Array[bool], tick: float
) -> bool:
	var was: Array = held["bags"]
	for i in mini(was.size(), kinds.size()):
		if kinds[i] != SecurityLooks.Kind.ROLLER or not lifts[i] or was[i]["kind"] != kinds[i]:
			continue
		if int(was[i].get("place", 0)) % 2 == 0:
			return true
		var from_pull: bool = was[i].get("carry_was", -1) == SecurityLooks.Carry.PULL
		var since := tick - float(was[i].get("changed", -INF))
		if from_pull and since < CarryOnProps.TRANSFER_TICKS:
			return true
	return false


## For each bag: whether a roller lifted by its handle that would go back to
## the pull now stays in hand, because it was in hand while the arms were
## tucked for a booth (`tuck` above 0; marked "booth_kept") and the front
## weight (`front`) has not turned back to the side yet. The mark lasts until
## the front carry has ended, so a way past the booth closed on both sides,
## where the front carry goes on after the tuck, keeps it in hand too.
static func kept_lifted(
	held: Dictionary,
	kinds: Array[SecurityLooks.Kind],
	lifts: Array[bool],
	front: float,
	tuck: float
) -> Array[bool]:
	var was: Array = held["bags"]
	var out: Array[bool] = []
	for i in kinds.size():
		if i >= was.size() or kinds[i] != SecurityLooks.Kind.ROLLER or was[i]["kind"] != kinds[i]:
			out.append(false)
			continue
		var in_hand: bool = int(was[i].get("place", 0)) % 2 == 1 and not was[i].get("by_bar", false)
		if tuck > 0.0 and in_hand:
			was[i]["booth_kept"] = true
		if front <= 0.0:
			was[i]["booth_kept"] = false
		out.append(not lifts[i] and in_hand and was[i].get("booth_kept", false))
	return out
