class_name SecuritySearchReasons
extends RefCounted
## Deterministic comic speech bubbles and matching inspect-card thoughts for
## security alarm and liquids repacks (decision
## frequent-security-searches-live-in-world-comic-belt-keys-liq). Derived from
## the passenger id and existing alarm/liquids flags so saves stay unchanged.

const SALT := 0x517CC1B7

const ALARM_BUBBLES: Array[String] = [
	"Forgot my belt!",
	"Keys in pocket!",
	"Coins in pocket!",
]
const LIQUIDS_BUBBLES: Array[String] = [
	"Oversized shampoo!",
	"Too much liquid!",
	"Forgot my water bottle!",
]
const ALARM_THOUGHTS: Array[String] = [
	"Set off the scanner: forgot my belt!",
	"Set off the scanner: keys in pocket!",
	"Set off the scanner: coins in pocket!",
]
const LIQUIDS_THOUGHTS: Array[String] = [
	"Stopped for liquids: oversized shampoo!",
	"Stopped for liquids: too much liquid!",
	"Stopped for liquids: forgot my water bottle!",
]


## True while `p` is actively in a security alarm or liquids repack.
static func is_active(p: Passenger) -> bool:
	return (
		p.stage == Passenger.Stage.SECURITY
		and p.security_phase == SecurityRuntime.Phase.REPACK
		and SecurityRuntime.incident_open(p)
	)


## Deterministic index in the alarm or liquids pool for `passenger_id`.
static func reason_index(passenger_id: int, is_alarm: bool) -> int:
	var pool_size := ALARM_BUBBLES.size() if is_alarm else LIQUIDS_BUBBLES.size()
	var mixed := _mix(passenger_id ^ SALT ^ (1 if is_alarm else 0))
	return mixed % pool_size


## Active comic speech bubble text (English msgid) for `p`, or "" when inactive.
## When both alarm and liquids are flagged, alarm takes precedence.
static func bubble_of(p: Passenger) -> String:
	if not is_active(p):
		return ""
	var idx := reason_index(p.id, p.alarm)
	return ALARM_BUBBLES[idx] if p.alarm else LIQUIDS_BUBBLES[idx]


## Whether `text` is one of the live security search bubble strings.
static func is_bubble_text(text: String) -> bool:
	return text in ALARM_BUBBLES or text in LIQUIDS_BUBBLES


## Unlocalized thought msgid matching `is_alarm` and `index`.
static func thought_msgid(is_alarm: bool, index: int) -> String:
	var pool := ALARM_THOUGHTS if is_alarm else LIQUIDS_THOUGHTS
	if index < 0 or index >= pool.size():
		return ""
	return pool[index]


static func _mix(value: int) -> int:
	var x := value & 0xFFFFFFFF
	x = ((x >> 16) ^ x) * 0x45D9F3B & 0xFFFFFFFF
	x = ((x >> 16) ^ x) * 0x45D9F3B & 0xFFFFFFFF
	return (x >> 16) ^ x
