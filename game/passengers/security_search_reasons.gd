class_name SecuritySearchReasons
extends RefCounted
## Deterministic comic speech bubbles and matching inspect-card thoughts for
## security alarm and liquids repacks (decision
## frequent-security-searches-live-in-world-comic-belt-keys-liq). Derived from
## the passenger id and existing alarm/liquids flags so saves stay unchanged.

const SALT := 0x517CC1B7
const CONTRABAND_SALT := 0x2C9A4E73
const CONTRABAND_COUNT := 24

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

## 24 absurd cozy gag items, 3 per Blender gag prop GLB.
const CONTRABAND_ITEMS := [
	{
		"prop": "gag_snow_globe",
		"name": "Giant alpine snow globe",
		"quip": "Contains 400 ml of festive winter magic.",
	},
	{
		"prop": "gag_snow_globe",
		"name": "Souvenir city snow globe",
		"quip": "Too much decorative blizzard for cabin altitude.",
	},
	{
		"prop": "gag_snow_globe",
		"name": "Musical penguin snow globe",
		"quip": "Shakes nicely, still over the 100 ml limit.",
	},
	{
		"prop": "gag_syrup_jug",
		"name": "Family-size maple syrup jug",
		"quip": "Emergency pancake rations are still a liquid.",
	},
	{
		"prop": "gag_syrup_jug",
		"name": "Artisanal pancake syrup",
		"quip": "Declared as breakfast insurance.",
	},
	{
		"prop": "gag_syrup_jug",
		"name": "Emergency waffle syrup",
		"quip": "Sticky situation in tray three.",
	},
	{
		"prop": "gag_garden_gnome",
		"name": "Ceramic garden gnome",
		"quip": "Claimed to be a tiny travel companion.",
	},
	{
		"prop": "gag_garden_gnome",
		"name": "Uncle Barnaby's lucky gnome",
		"quip": "Too heavy for the overhead bin.",
	},
	{
		"prop": "gag_garden_gnome",
		"name": "Pointy-hat lawn gnome",
		"quip": "Refused to fit in a quart-size zip bag.",
	},
	{
		"prop": "gag_bowling_ball",
		"name": "Twelve-pound bowling ball",
		"quip": "Definitely not a compact neck pillow.",
	},
	{
		"prop": "gag_bowling_ball",
		"name": "Lucky league bowling ball",
		"quip": "Spare shoes were fine; the ball had to stay.",
	},
	{
		"prop": "gag_bowling_ball",
		"name": "Polished tournament ball",
		"quip": "Would roll straight out of the overhead locker.",
	},
	{
		"prop": "gag_flamingo",
		"name": "Plastic lawn flamingo",
		"quip": "Needs its own boarding pass at this height.",
	},
	{
		"prop": "gag_flamingo",
		"name": "Tropical souvenir flamingo",
		"quip": "Tried to pass as a walking stick.",
	},
	{
		"prop": "gag_flamingo",
		"name": "Neon pink yard flamingo",
		"quip": "Too fabulous for under-seat stowage.",
	},
	{
		"prop": "gag_rubber_duck",
		"name": "Giant bath-time rubber duck",
		"quip": "Squeaked during the X-ray scan.",
	},
	{
		"prop": "gag_rubber_duck",
		"name": "Captain Squeaks the duck",
		"quip": "Suspiciously buoyant carry-on cargo.",
	},
	{
		"prop": "gag_rubber_duck",
		"name": "Oversized squeaky duck",
		"quip": "Filled with bathwater from hotel checkout.",
	},
	{
		"prop": "gag_giant_wrench",
		"name": "Comically giant wrench",
		"quip": "Just in case the seat reclines slowly.",
	},
	{
		"prop": "gag_giant_wrench",
		"name": "Pocket-sized mega wrench",
		"quip": "Definitely not an approved nail file.",
	},
	{
		"prop": "gag_giant_wrench",
		"name": "Half-metre pipe wrench",
		"quip": "Way past the tool-length limit.",
	},
	{
		"prop": "gag_mystery_thermos",
		"name": "Unlabelled mystery thermos",
		"quip": "Smells faintly of soup, tea, or jet fuel.",
	},
	{
		"prop": "gag_mystery_thermos",
		"name": "Grandma's mystery thermos",
		"quip": "Could be cocoa; still 600 ml too large.",
	},
	{
		"prop": "gag_mystery_thermos",
		"name": "Rattling stainless thermos",
		"quip": "No one wants to open it at the checkpoint.",
	},
]


## True while `p` is actively in a body alarm check or carry-on bag search.
static func is_active(p: Passenger) -> bool:
	if p.stage != Passenger.Stage.SECURITY:
		return false
	if p.security_phase == SecurityRuntime.Phase.BODY_CHECK:
		return SecurityRuntime.body_pending(p)
	if p.security_phase == SecurityRuntime.Phase.REPACK:
		return SecurityRuntime.incident_open(p)
	return false


## Deterministic index in the alarm or liquids pool for `passenger_id`.
static func reason_index(passenger_id: int, is_alarm: bool) -> int:
	var pool_size := ALARM_BUBBLES.size() if is_alarm else LIQUIDS_BUBBLES.size()
	var mixed := _mix(passenger_id ^ SALT ^ (1 if is_alarm else 0))
	return mixed % pool_size


## Deterministic contraband gag item index (0..23) for `passenger_id`.
static func contraband_index(passenger_id: int) -> int:
	return _mix(passenger_id ^ CONTRABAND_SALT) % CONTRABAND_ITEMS.size()


static func contraband_item(index: int) -> Dictionary:
	if index < 0 or index >= CONTRABAND_ITEMS.size():
		return {}
	return CONTRABAND_ITEMS[index]


static func contraband_prop(index: int) -> String:
	return String(contraband_item(index).get("prop", ""))


static func contraband_piece(index: int) -> String:
	var prop := contraband_prop(index)
	return "interior/contraband/" + prop if prop != "" else ""


static func contraband_name(index: int) -> String:
	var raw := String(contraband_item(index).get("name", ""))
	return TranslationServer.translate(raw) if raw != "" else ""


static func contraband_quip(index: int) -> String:
	var raw := String(contraband_item(index).get("quip", ""))
	return TranslationServer.translate(raw) if raw != "" else ""


## Active comic speech bubble text (English msgid) for `p`, or "" when inactive.
## Body checks use ALARM_BUBBLES; bag searches use LIQUIDS_BUBBLES (with alarm
## precedence at a basic scanner if both are open).
static func bubble_of(p: Passenger) -> String:
	if not is_active(p):
		return ""
	var use_alarm := (
		p.security_phase == SecurityRuntime.Phase.BODY_CHECK or SecurityRuntime.body_pending(p)
	)
	var idx := reason_index(p.id, use_alarm)
	return ALARM_BUBBLES[idx] if use_alarm else LIQUIDS_BUBBLES[idx]


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


class Words:
	extends RefCounted

	## Never called: every contraband name and quip inside tr(), so POT
	## generation finds them all.
	func msgids() -> Array[String]:
		return [
			tr("Giant alpine snow globe"),
			tr("Contains 400 ml of festive winter magic."),
			tr("Souvenir city snow globe"),
			tr("Too much decorative blizzard for cabin altitude."),
			tr("Musical penguin snow globe"),
			tr("Shakes nicely, still over the 100 ml limit."),
			tr("Family-size maple syrup jug"),
			tr("Emergency pancake rations are still a liquid."),
			tr("Artisanal pancake syrup"),
			tr("Declared as breakfast insurance."),
			tr("Emergency waffle syrup"),
			tr("Sticky situation in tray three."),
			tr("Ceramic garden gnome"),
			tr("Claimed to be a tiny travel companion."),
			tr("Uncle Barnaby's lucky gnome"),
			tr("Too heavy for the overhead bin."),
			tr("Pointy-hat lawn gnome"),
			tr("Refused to fit in a quart-size zip bag."),
			tr("Twelve-pound bowling ball"),
			tr("Definitely not a compact neck pillow."),
			tr("Lucky league bowling ball"),
			tr("Spare shoes were fine; the ball had to stay."),
			tr("Polished tournament ball"),
			tr("Would roll straight out of the overhead locker."),
			tr("Plastic lawn flamingo"),
			tr("Needs its own boarding pass at this height."),
			tr("Tropical souvenir flamingo"),
			tr("Tried to pass as a walking stick."),
			tr("Neon pink yard flamingo"),
			tr("Too fabulous for under-seat stowage."),
			tr("Giant bath-time rubber duck"),
			tr("Squeaked during the X-ray scan."),
			tr("Captain Squeaks the duck"),
			tr("Suspiciously buoyant carry-on cargo."),
			tr("Oversized squeaky duck"),
			tr("Filled with bathwater from hotel checkout."),
			tr("Comically giant wrench"),
			tr("Just in case the seat reclines slowly."),
			tr("Pocket-sized mega wrench"),
			tr("Definitely not an approved nail file."),
			tr("Half-metre pipe wrench"),
			tr("Way past the tool-length limit."),
			tr("Unlabelled mystery thermos"),
			tr("Smells faintly of soup, tea, or jet fuel."),
			tr("Grandma's mystery thermos"),
			tr("Could be cocoa; still 600 ml too large."),
			tr("Rattling stainless thermos"),
			tr("No one wants to open it at the checkpoint."),
		]
