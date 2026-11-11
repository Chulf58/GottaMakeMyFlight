class_name IncidentRoll
extends RefCounted
## The incident draws, as pure functions of a seed (decision daily-incidents-
## technical-design-incidentdirector-shared-clo). The incidents never draw from
## SimClock.rng: turning them on or off must not change any offer or passenger
## draw. Godot does not promise that Array.hash() or RandomNumberGenerator stay
## the same across engine versions, so both the seed derivation and the
## generator are written out here and pinned by test vectors.
##
## Seed derivation, version SEED_VERSION:
##   text = "gmmf-incidents|<SEED_VERSION>|<catalogue version>|<world seed>|
##           <day>|<purpose>", every number in plain decimal (str(), a minus
##           sign for a negative world seed), purpose a short ASCII word;
##   seed = 32-bit FNV-1a of the text's UTF-8 bytes (offset basis 2166136261,
##          prime 16777619), and 1 when that is 0.
## Generator: xorshift32 (shifts 13, 17, 5) on that seed; each next_u32()
## steps the state once and returns it. below(n) is next_u32() % n.
##
## One day's roll draws, in this order: the kind (weighted, catalogue order),
## then the fire tick inside the window, then, for a major, the next day a
## major may come (2 or 3 days on). A change to this order, the text or the
## generator bumps SEED_VERSION; a change to the kinds or their weights bumps
## IncidentCatalogue.VERSION. Everything a roll decides is saved as ticks, so
## a load never draws again.

const SEED_VERSION := 1
const FNV_OFFSET := 2166136261
const FNV_PRIME := 16777619
const MASK_32 := 0xFFFFFFFF
## A major comes at most once in this many days, plus one more at random.
const MAJOR_GAP_DAYS := 2

## The generator's state, 1 to 2^32 - 1.
var state := 1


func _init(seed_value := 1) -> void:
	state = seed_value & MASK_32
	if state == 0:
		state = 1


## The seed for `purpose` on `day` (see the class notes).
static func seed_for(world_seed: int, day: int, catalogue_version: int, purpose: String) -> int:
	var text := (
		"gmmf-incidents|%s|%s|%s|%s|%s"
		% [str(SEED_VERSION), str(catalogue_version), str(world_seed), str(day), purpose]
	)
	var value := fnv1a_32(text.to_utf8_buffer())
	return value if value != 0 else 1


## 32-bit FNV-1a. Every product stays below 2^57, so nothing overflows.
static func fnv1a_32(bytes: PackedByteArray) -> int:
	var value := FNV_OFFSET
	for byte in bytes:
		value = ((value ^ byte) * FNV_PRIME) & MASK_32
	return value


## A generator for `purpose` on `day`.
static func stream(
	world_seed: int, day: int, catalogue_version: int, purpose: String
) -> IncidentRoll:
	return IncidentRoll.new(seed_for(world_seed, day, catalogue_version, purpose))


## Steps the xorshift32 state and returns it.
func next_u32() -> int:
	var x := state
	x ^= (x << 13) & MASK_32
	x ^= x >> 17
	x ^= (x << 5) & MASK_32
	state = x
	return x


## A draw in [0, n); n must be 1 or more.
func below(n: int) -> int:
	return next_u32() % n


## Whether a major may be rolled on `day`.
static func major_allowed(day: int, next_major_day: int) -> bool:
	return day >= next_major_day


## One day's roll. `candidates` are {"kind", "weight", "major"} in catalogue
## order, "none" among them; a weight of 0, or a major before next_major_day,
## takes no part. `window` is the inclusive tick range a fire may land in; an
## empty one (x > y) leaves only "none". Returns {"kind", "fire_tick",
## "next_major_day"}; fire_tick is -1 for "none".
static func roll(
	draws: IncidentRoll, candidates: Array, day: int, next_major_day: int, window: Vector2i
) -> Dictionary:
	var open: Array[Dictionary] = []
	var total := 0
	for entry: Dictionary in candidates:
		var allowed: bool = entry["kind"] == IncidentCatalogue.NONE or window.x <= window.y
		if entry["major"] and not major_allowed(day, next_major_day):
			allowed = false
		if allowed and int(entry["weight"]) > 0:
			open.append(entry)
			total += int(entry["weight"])
	var result := {
		"kind": IncidentCatalogue.NONE, "fire_tick": -1, "next_major_day": next_major_day
	}
	if total == 0:
		return result
	var pick := draws.below(total)
	var chosen: Dictionary = open[open.size() - 1]
	for entry in open:
		pick -= int(entry["weight"])
		if pick < 0:
			chosen = entry
			break
	if chosen["kind"] == IncidentCatalogue.NONE:
		return result
	result["kind"] = chosen["kind"]
	result["fire_tick"] = window.x + draws.below(window.y - window.x + 1)
	if chosen["major"]:
		result["next_major_day"] = day + MAJOR_GAP_DAYS + draws.below(2)
	return result
