class_name UnlockFamilies
extends RefCounted
## The families a newly opened tier brings, and the one line each gets in the
## unlock dialog (decision new-unlock-tier-phone-ring-and-a-short-per-family-
## dialog-onc). The families come from BuildUnlocks.TIERS: each tool of an
## opened tier belongs to the family FAMILY_OF names (any other tool is
## "other"), and a runway size that opens with the tier (RUNWAY_TIERS) adds
## "runway". A family is a line only when the tiers bring something in it.

const FOOD := &"food"
const SECURITY := &"security"
const BAGGAGE := &"baggage"
const COMFORT := &"comfort"
const RUNWAY := &"runway"
const OTHER := &"other"
## The order the lines are shown in.
const ORDER := [FOOD, SECURITY, BAGGAGE, COMFORT, RUNWAY, OTHER]
## What each family is for and why to build it now; "other" lists its pieces.
const LINES := {
	FOOD: "Food: hungry passengers lose mood. A cafe feeds them.",
	SECURITY: "Security: more lanes mean shorter queues at the checkpoint.",
	BAGGAGE: "Baggage: belts carry checked bags. A late bag misses its flight.",
	COMFORT: "Comfort: seats and lounges calm passengers who wait.",
	RUNWAY: "Runway: a longer runway takes bigger planes.",
	OTHER: "Also new: %s.",
}
## How many pieces the "other" line names.
const OTHER_NAMES := 5
const FAMILY_OF := {
	BuildMode.Tool.CAFE_ROOM: FOOD,
	BuildMode.Tool.COUNTER: FOOD,
	BuildMode.Tool.TABLE: FOOD,
	BuildMode.Tool.BIN: FOOD,
	BuildMode.Tool.TRAY_TABLE: FOOD,
	BuildMode.Tool.BAR_ROOM: FOOD,
	BuildMode.Tool.RESTAURANT_ROOM: FOOD,
	BuildMode.Tool.STALL_ROOM: FOOD,
	BuildMode.Tool.BAR_COUNTER: FOOD,
	BuildMode.Tool.GRAB_STALL: FOOD,
	BuildMode.Tool.DINING_TABLE: FOOD,
	BuildMode.Tool.BOOTH: FOOD,
	BuildMode.Tool.XRAY_BELT: SECURITY,
	BuildMode.Tool.ARCH: SECURITY,
	BuildMode.Tool.PICKUP_TABLE: SECURITY,
	BuildMode.Tool.BELT: BAGGAGE,
	BuildMode.Tool.BAG_ROOM: BAGGAGE,
	BuildMode.Tool.CART: BAGGAGE,
	BuildMode.Tool.BENCH: COMFORT,
	BuildMode.Tool.BUSH: COMFORT,
	BuildMode.Tool.PLANTER: COMFORT,
	BuildMode.Tool.PLANT_POT: COMFORT,
	BuildMode.Tool.TREE: COMFORT,
	BuildMode.Tool.TREE_BENCH: COMFORT,
	BuildMode.Tool.LOUNGE_ROOM: COMFORT,
	BuildMode.Tool.SOFA: COMFORT,
	BuildMode.Tool.ARMCHAIR: COMFORT,
	BuildMode.Tool.WORK_DESK: COMFORT,
	BuildMode.Tool.SHOWER: COMFORT,
	BuildMode.Tool.SHOWER_ROOM: COMFORT,
	BuildMode.Tool.NAP_POD: COMFORT,
	BuildMode.Tool.NAP_POD_ROOM: COMFORT,
	BuildMode.Tool.PLAY_AREA_ROOM: COMFORT,
	BuildMode.Tool.PLAY_BLOCKS: COMFORT,
	BuildMode.Tool.PLAY_SLIDE: COMFORT,
	BuildMode.Tool.FOUNTAIN: COMFORT,
	BuildMode.Tool.STATUE: COMFORT,
}


## The family of a tool: its FAMILY_OF entry, else "other".
static func family_of(tool: BuildMode.Tool) -> StringName:
	return FAMILY_OF.get(tool, OTHER)


## The tools tiers `first` to `last` bring, grouped by family; only families
## with a tool (or, for the runway, a size that opens) appear, in ORDER.
static func grouped(first: int, last: int) -> Dictionary:
	var groups := {}
	for tier in range(maxi(first, 1), mini(last, BuildUnlocks.TIERS.size()) + 1):
		for tool: BuildMode.Tool in BuildUnlocks.TIERS[tier - 1]["tools"]:
			var family := family_of(tool)
			if not groups.has(family):
				groups[family] = []
			groups[family].append(tool)
		for size: String in BuildUnlocks.RUNWAY_TIERS:
			if BuildUnlocks.RUNWAY_TIERS[size] == tier and not groups.has(RUNWAY):
				groups[RUNWAY] = []
	var ordered := {}
	for family in ORDER:
		if groups.has(family):
			ordered[family] = groups[family]
	return ordered


## One line per family the tiers `first` to `last` bring.
static func lines(first: int, last: int) -> Array[String]:
	var out: Array[String] = []
	var groups := grouped(first, last)
	for family: StringName in groups:
		if family == OTHER:
			out.append(LINES[OTHER] % ", ".join(_names(groups[family])))
		else:
			out.append(LINES[family])
	return out


static func _names(tools: Array) -> Array[String]:
	var names: Array[String] = []
	for tool: BuildMode.Tool in tools:
		var card := BuildMenuCatalog.item(tool)
		if not card.is_empty() and not names.has(String(card[0]).to_lower()):
			names.append(String(card[0]).to_lower())
		if names.size() >= OTHER_NAMES:
			break
	return names
