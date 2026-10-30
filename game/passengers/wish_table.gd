class_name WishTable
extends RefCounted
## Shopping wishes (ruling store-variety-passengers-have-a-shopping-wish-
## weighted-by-arrival-type-unmet-settles-for-less; decision shopping-wish-
## technical-design-id-hash-wish-admissible-wished-slot-then-fallback, point
## 1). A passenger may wish for one kind of shop, or for none. The wish is not
## drawn from the sim RNG and not saved: pick() derives it from the
## passenger's arrival type and a salted hash of its id, so a save, a load and
## a replay give every passenger the same wish. The salt keeps the wish apart
## from the other things derived from the id (BoredomSim.start_of(), the bag
## kinds).

## How a passenger's wish shows over it while it is bored (ShopSim's
## visit_wish_state()): no wish showing, a wish not yet planned, a relief
## visit of the wished kind, or a relief visit that settles for another shop.
enum State { NONE, WANTED, FULFILLED, SUBSTITUTED }

## No wish.
const NONE := &""
## The shop room types a passenger can wish for, in the order the weights
## give them. Every one relieves boredom (RoomType.relieves_boredom).
const CANDIDATES: Array[StringName] = [&"kiosk", &"pharmacy", &"duty_free", &"fashion"]
## Weights out of WEIGHT_TOTAL per arrival type (ArrivalTypes.Type order):
## no wish first, then CANDIDATES in order. Tuning values: rushed passengers
## lean to the kiosk and the pharmacy, relaxed ones to duty free and fashion,
## typical ones spread across all four.
const WEIGHTS: Array = [
	[100, 60, 30, 6, 4],
	[60, 35, 35, 35, 35],
	[40, 20, 20, 60, 60],
]
const WEIGHT_TOTAL := 200
## Mixed into the id before hashing, so the wish is its own draw.
const SALT := 0x5A0C3E11


## The wish of a passenger of arrival type `type` with id `passenger_id`: one
## of CANDIDATES, or NONE.
static func pick(type: ArrivalTypes.Type, passenger_id: int) -> StringName:
	var roll := roll_of(passenger_id)
	var weights: Array = WEIGHTS[type]
	roll -= int(weights[0])
	if roll < 0:
		return NONE
	for i in CANDIDATES.size():
		roll -= int(weights[i + 1])
		if roll < 0:
			return CANDIDATES[i]
	return NONE


## The wish of `p` (pick() of its arrival type and id).
static func of(p: Passenger) -> StringName:
	return pick(p.arrival_type, p.id)


## The roll pick() reads for `passenger_id`: 0 to WEIGHT_TOTAL - 1.
static func roll_of(passenger_id: int) -> int:
	return _mix(_mix(passenger_id) ^ SALT) % WEIGHT_TOTAL


## A 32-bit integer mixer (a non-negative result).
static func _mix(value: int) -> int:
	var x := value & 0xFFFFFFFF
	x = ((x >> 16) ^ x) * 0x45D9F3B & 0xFFFFFFFF
	x = ((x >> 16) ^ x) * 0x45D9F3B & 0xFFFFFFFF
	return (x >> 16) ^ x
