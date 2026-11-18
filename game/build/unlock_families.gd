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
## How many pieces the "other" line names.
const OTHER_NAMES := 5
## The context of the list separator, shared with every other list of names.
const LIST_SEPARATOR := "list separator"
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


## The tools of the listed `tiers` grouped by family; only families with a tool
## (or, for the runway, a size that opens) appear, in ORDER. The start tier and
## a tier no TIERS entry lists bring nothing: nothing opens for them.
static func grouped(tiers: Array) -> Dictionary:
	var groups := {}
	for tier: int in tiers:
		if tier <= BuildUnlocks.START_TIER or tier > BuildUnlocks.TIERS.size():
			continue
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


## One line per family the listed `tiers` bring, in the player's language.
static func lines(tiers: Array) -> Array[String]:
	var out: Array[String] = []
	var words := Words.new()
	var groups := grouped(tiers)
	for family: StringName in groups:
		var pieces := ""
		if family == OTHER:
			pieces = TranslationServer.translate(", ", LIST_SEPARATOR).join(_names(groups[family]))
		out.append(words.line(family, pieces))
	return out


## The first OTHER_NAMES card names of `tools`, as the build menu shows them
## (translated, and never case-changed, so a language keeps its own casing).
static func _names(tools: Array) -> Array[String]:
	var names: Array[String] = []
	for tool: BuildMode.Tool in tools:
		var card := BuildMenuCatalog.item(tool)
		if card.is_empty():
			continue
		var shown := BuildMenuCatalog.shown(String(card[0]))
		if not names.has(shown):
			names.append(shown)
		if names.size() >= OTHER_NAMES:
			break
	return names


## tr() is an instance method, so the static functions of this file ask a Words.
class Words:
	extends RefCounted

	## What each family is for and why to build it now; "other" names its
	## `pieces`, a list of card names.
	func line(family: StringName, pieces: String) -> String:
		var texts := {
			FOOD: tr("Food: hungry passengers lose mood. A cafe feeds them."),
			SECURITY: tr("Security: more lanes mean shorter queues at the checkpoint."),
			BAGGAGE: tr("Baggage: belts carry checked bags. A late bag misses its flight."),
			COMFORT: tr("Comfort: seats and lounges calm passengers who wait."),
			RUNWAY: tr("Runway: a longer runway takes bigger planes."),
		}
		if family == OTHER:
			return tr("Also new: {pieces}.").format({"pieces": pieces})
		return texts[family]
