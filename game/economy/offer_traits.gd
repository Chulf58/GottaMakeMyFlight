class_name OfferTraits
extends RefCounted
## The trade-off traits an airline offer can carry (decision airline-offer-
## traits-each-offer-pairs-an-upside-with-a-downs; technical design offer-
## traits-technical-design-offertraits-table-frozen-trait). A paired offer has
## one upside and one downside at the same level (1 small, 2 big); a plain offer
## has none and pays PLAIN_FEE_PERCENT of its drawn fee. An offer's and a
## contract's `traits` term is {} for plain or {"up", "down", "level"}.
##
## Each day's traits are drawn from their own stream (draw_day), seeded from the
## run seed and the day, never from SimClock.rng, so the base offer draw is the
## same with or without traits. The generator is IncidentRoll's pinned xorshift32
## on a seed from this class's own text:
##   "gmmf-offer-traits|<SEED_VERSION>|<world seed>|<day>", 32-bit FNV-1a.
## One day draws, in this order: the plain offer's index, then for each paired
## offer in draw order its level roll (below(100)) and its pair index. A change
## to this order, the text, the table or the pair rules bumps SEED_VERSION.
##
## Every number is a whole percent and a tuning value.

const TOP_FARE := "top_fare"
const SHOPPERS := "shoppers"
const BAG_COVER := "bag_cover"
const FULL_FLIGHT := "full_flight"
const RUSH_CROWD := "rush_crowd"
const HEAVY_BAGS := "heavy_bags"
const SIGNING_BONUS := "signing_bonus"
const LOYAL_AIRLINE := "loyal_airline"
const MISS_FINE := "miss_fine"
const ODD_HOURS := "odd_hours"
const EXIT_FEE := "exit_fee"
## Upsides and downsides in table order (the order pairs are listed in).
const UPS: Array[String] = [
	TOP_FARE, SHOPPERS, BAG_COVER, FULL_FLIGHT, SIGNING_BONUS, LOYAL_AIRLINE
]
const DOWNS: Array[String] = [RUSH_CROWD, HEAVY_BAGS, MISS_FINE, ODD_HOURS, EXIT_FEE]
const LEVELS: Array[int] = [1, 2]
const KEYS := ["down", "level", "up"]

## What a trait needs before it is drawn: bags count only once a ready bag room
## exists (decision bags-count-only-once-a-ready-bag-room-exists-missed-bag-fee-
## and-rating), and shoppers need a shop or food room to spend in.
const NEEDS_BAGS := "bags"
const NEEDS_SHOPS := "shops"

## Per trait: the level values and what it needs ("" for nothing). The card
## label and tooltip per level are in label_of() and tip_of(). The values mean:
## TOP_FARE: percent more fee. SHOPPERS: the relaxed arrival share. BAG_COVER and
## HEAVY_BAGS: the percent of the fee a missed bag costs (PriceTable's default
## is 100 - MISSED_BAG_FEE_PERCENT). FULL_FLIGHT: bookings come from the top
## this percent of the plane size's range. RUSH_CROWD: the rushed arrival share.
## SIGNING_BONUS: dollars paid once, when the contract's first flight departs
## (Settlement). LOYAL_AIRLINE: counts double (+2 days/day) toward the
## airline's loyalty tiers (OfferBoard counts the days). MISS_FINE: dollars per
## passenger who misses the flight.
## ODD_HOURS: the minutes the departure window widens at each end, the same at
## both levels (FlightContract.window: 06:00 to 22:00 instead of 07:00 to 21:00;
## decision odd-hours-and-exit-fee-offer-traits-odd-hours-widens-the-dep). An
## Odd hours offer is drawn at one of the two ends, 06:00 or 22:00 (OfferBoard).
## EXIT_FEE: dollars the player pays to end the contract with the End button
## within its first EXIT_FEE_DAYS days (FlightSim.end_fee).
const TABLE := {
	TOP_FARE:
	{
		"values": [15, 30],
		"needs": "",
	},
	SHOPPERS:
	{
		"values": [45, 55],
		"needs": NEEDS_SHOPS,
	},
	BAG_COVER:
	{
		"values": [25, 0],
		"needs": NEEDS_BAGS,
	},
	FULL_FLIGHT:
	{
		"values": [50, 25],
		"needs": "",
	},
	RUSH_CROWD:
	{
		"values": [30, 45],
		"needs": "",
	},
	HEAVY_BAGS:
	{
		"values": [75, 100],
		"needs": NEEDS_BAGS,
	},
	SIGNING_BONUS:
	{
		"values": [150, 300],
		"needs": "",
	},
	LOYAL_AIRLINE:
	{
		"values": [2, 2],
		"needs": "",
	},
	MISS_FINE:
	{
		"values": [10, 20],
		"needs": "",
	},
	ODD_HOURS:
	{
		"values": [60, 60],
		"needs": "",
	},
	EXIT_FEE:
	{
		"values": [60, 120],
		"needs": "",
	},
}
## Pairs that cancel out, never drawn and refused on load. Odd hours and Exit
## fee cancel no upside. Signing bonus with Exit fee stays: the fee makes taking
## the bonus and then ending the contract cost more, it does not undo the bonus.
const FORBIDDEN: Array = [[SHOPPERS, RUSH_CROWD], [BAG_COVER, HEAVY_BAGS]]
## A plain offer pays this percent of its drawn fee, rounded.
const PLAIN_FEE_PERCENT := 90
## The English msgids of the plain and loyal card lines. Tests compare with
## them; card_labels(), card_tips(), loyal_label() and loyal_tip() return
## TranslationServer.translate() of the same literals, because the POT
## extractor reads only literals.
const PLAIN_LABEL := "Plain terms"
const PLAIN_TIP := "No catch, and 10% less pay."
## Percent chance a paired offer is level 2, by airline tier (RatingFormula.tier):
## tier 0 draws level 1 only, tier 1 mixes, tier 2 favours level 2.
const LEVEL_2_CHANCE: Array[int] = [0, 50, 75]
## 2: Signing bonus, Loyal airline and Miss fine joined the table.
## 3: Odd hours and Exit fee joined the table (28 pairs).
const SEED_VERSION := 3
## An Exit fee contract's term: ending it with the End button costs its fee on
## its first day and the EXIT_FEE_DAYS - 1 days after it; then it is free.
const EXIT_FEE_DAYS := 7
## Legacy 5-day / +10% binary loyalty constants kept for compatibility; active
## multi-tier loyalty thresholds and bonuses live on OfferBoard.
const LOYAL_DAYS := 5
const LOYAL_FEE_PERCENT := 10
const LOYAL_LABEL := "Loyal: +10%"
const LOYAL_TIP := "This airline is loyal to you: its offers pay 10% more."


## "" when `traits` is {} or a valid pair from the table; otherwise what is
## wrong. JSON whole floats count as whole numbers.
static func problem(traits: Variant) -> String:
	if typeof(traits) != TYPE_DICTIONARY:
		return "traits must be a dictionary"
	var data: Dictionary = traits
	if data.is_empty():
		return ""
	var found := _shape_problem(data)
	if found == "" and is_forbidden(data["up"], data["down"]):
		found = "traits %s and %s cancel out and are never paired" % [data["up"], data["down"]]
	return found


## A read-only copy of checked `traits`, the level as an int.
static func frozen(traits: Dictionary) -> Dictionary:
	var out := {}
	if not traits.is_empty():
		out = {"up": str(traits["up"]), "down": str(traits["down"]), "level": int(traits["level"])}
	out.make_read_only()
	return out


static func is_plain(traits: Dictionary) -> bool:
	return traits.is_empty()


static func is_forbidden(up: String, down: String) -> bool:
	return FORBIDDEN.has([up, down])


## The level value of trait `id` in `traits`, or -1 when it does not carry it.
static func value(traits: Dictionary, id: String) -> int:
	if traits.is_empty() or (traits["up"] != id and traits["down"] != id):
		return -1
	return TABLE[id]["values"][int(traits["level"]) - 1]


## The fee per passenger an offer of drawn fee `fee` pays with `traits`.
static func fee_of(fee: int, traits: Dictionary) -> int:
	if is_plain(traits):
		return _percent_of(fee, PLAIN_FEE_PERCENT)
	var more := value(traits, TOP_FARE)
	return _percent_of(fee, 100 + more) if more >= 0 else fee


## An offer fee `fee` (already fee_of) with `bonus_percent` added, rounded half
## up; unchanged when `bonus_percent` <= 0.
static func fee_with_bonus(fee: int, bonus_percent: int) -> int:
	return _percent_of(fee, 100 + bonus_percent) if bonus_percent > 0 else fee


## Legacy binary loyal fee helper kept for compatibility; see fee_with_bonus.
static func loyal_fee_of(fee: int, loyal: bool) -> int:
	return fee_with_bonus(fee, LOYAL_FEE_PERCENT if loyal else 0)


## The dollars each missed passenger costs under `traits`, 0 without Miss fine.
static func miss_fine(traits: Dictionary) -> int:
	return maxi(value(traits, MISS_FINE), 0)


## The dollars the first departure pays under `traits`, 0 without Signing bonus.
static func signing_bonus(traits: Dictionary) -> int:
	return maxi(value(traits, SIGNING_BONUS), 0)


## The dollars ending a contract of `traits` early costs, 0 without Exit fee.
static func exit_fee(traits: Dictionary) -> int:
	return maxi(value(traits, EXIT_FEE), 0)


## The minutes the departure window of `traits` widens at each end, 0 without
## Odd hours.
static func window_widening(traits: Dictionary) -> int:
	return maxi(value(traits, ODD_HOURS), 0)


## Whether a contract of `traits` counts double toward its airline's loyalty.
static func builds_loyalty(traits: Dictionary) -> bool:
	return value(traits, LOYAL_AIRLINE) >= 0


## Loyalty days earned per flown departure day: 2 with LOYAL_AIRLINE, else 1.
static func loyalty_day_gain(traits: Dictionary) -> int:
	return maxi(value(traits, LOYAL_AIRLINE), 1)


## The bookings of an offer whose drawn count `booked` is in [low, high]: with
## Full flight the count is moved into the top share of the range up to `high`,
## keeping its place in it, so no draw is added.
static func booked_of(booked: int, high: int, traits: Dictionary) -> int:
	var top := value(traits, FULL_FLIGHT)
	if top < 0:
		return booked
	@warning_ignore("integer_division")
	return high - (high - booked) * top / 100


## The fewest bookings booked_of gives for a range [low, high].
static func fewest_booked(low: int, high: int, traits: Dictionary) -> int:
	return booked_of(low, high, traits)


## The percent of its fee a passenger whose bag missed still pays.
static func missed_bag_paid_percent(traits: Dictionary) -> int:
	for id in [BAG_COVER, HEAVY_BAGS]:
		var cost := value(traits, id)
		if cost >= 0:
			return 100 - cost
	return PriceTable.MISSED_BAG_FEE_PERCENT


## The card's trait line as [upside, downside] labels, or [PLAIN_LABEL, ""].
static func card_labels(traits: Dictionary) -> PackedStringArray:
	if is_plain(traits):
		return PackedStringArray([TranslationServer.translate("Plain terms"), ""])
	var index := int(traits["level"]) - 1
	return PackedStringArray([label_of(traits["up"], index), label_of(traits["down"], index)])


## The tooltips for card_labels' two labels.
static func card_tips(traits: Dictionary) -> PackedStringArray:
	if is_plain(traits):
		return PackedStringArray([TranslationServer.translate("No catch, and 10% less pay."), ""])
	var index := int(traits["level"]) - 1
	return PackedStringArray([tip_of(traits["up"], index), tip_of(traits["down"], index)])


## Legacy binary loyal mark label kept for compatibility; OfferPanel renders tier badges.
static func loyal_label() -> String:
	return TranslationServer.translate("Loyal: +10%")


## Legacy binary loyal mark tooltip kept for compatibility; OfferPanel renders tier tips.
static func loyal_tip() -> String:
	return TranslationServer.translate("This airline is loyal to you: its offers pay 10% more.")


## The card label of trait `id` at level `index` + 1.
static func label_of(id: String, index: int) -> String:
	var amount: int = TABLE[id]["values"][index]
	match id:
		TOP_FARE:
			return TranslationServer.translate("Top fare +{percent}%").format({"percent": amount})
		SHOPPERS:
			if index == 0:
				return TranslationServer.translate("Shoppers")
			return TranslationServer.translate("Many shoppers")
		BAG_COVER:
			if index == 0:
				return TranslationServer.translate("Bag cover")
			return TranslationServer.translate("Full bag cover")
		FULL_FLIGHT:
			if index == 0:
				return TranslationServer.translate("Full flight")
			return TranslationServer.translate("Packed flight")
		RUSH_CROWD:
			if index == 0:
				return TranslationServer.translate("Rush crowd")
			return TranslationServer.translate("Big rush crowd")
		HEAVY_BAGS:
			if index == 0:
				return TranslationServer.translate("Heavy bags")
			return TranslationServer.translate("Very heavy bags")
		SIGNING_BONUS:
			return TranslationServer.translate("Signing bonus ${amount}").format({"amount": amount})
		LOYAL_AIRLINE:
			return TranslationServer.translate("Loyal airline")
		MISS_FINE:
			return TranslationServer.translate("Miss fine ${amount}").format({"amount": amount})
		ODD_HOURS:
			return TranslationServer.translate("Odd hours")
		EXIT_FEE:
			return TranslationServer.translate("Exit fee ${amount}").format({"amount": amount})
	push_error("OfferTraits.label_of: unknown trait '%s'" % id)
	return ""


## The tooltip of trait `id` at level `index` + 1.
static func tip_of(id: String, index: int) -> String:
	var amount: int = TABLE[id]["values"][index]
	match id:
		TOP_FARE:
			return TranslationServer.translate("Pays {percent}% more per passenger.").format(
				{"percent": amount}
			)
		SHOPPERS:
			return (
				TranslationServer
				. translate("{percent}% of passengers come early with time to shop (usually 30%).")
				. format({"percent": amount})
			)
		BAG_COVER:
			if index == 0:
				return (
					TranslationServer
					. translate("A missed bag costs {percent}% of the fee (usually 50%).")
					. format({"percent": amount})
				)
			return TranslationServer.translate(
				"A missed bag costs nothing (usually 50% of the fee)."
			)
		FULL_FLIGHT:
			if index == 0:
				return TranslationServer.translate("Booked from the top half of the plane's range.")
			return TranslationServer.translate("Booked from the top quarter of the plane's range.")
		RUSH_CROWD:
			return (
				TranslationServer
				. translate("{percent}% of passengers arrive late in a rush (usually 15%).")
				. format({"percent": amount})
			)
		HEAVY_BAGS:
			if index == 0:
				return (
					TranslationServer
					. translate("A missed bag costs {percent}% of the fee (usually 50%).")
					. format({"percent": amount})
				)
			return TranslationServer.translate("A missed bag costs the whole fee (usually 50%).")
		SIGNING_BONUS:
			return (
				TranslationServer
				. translate("Pays ${amount} once, when this contract's first flight leaves.")
				. format({"amount": amount})
			)
		LOYAL_AIRLINE:
			return (
				TranslationServer
				. translate(
					# gdlint:ignore = max-line-length
					"Counts double (+{days} days/day) toward airline loyalty tiers (Bronze +5%, Silver +10%, Gold +15%)."
				)
				. format({"days": amount})
			)
		MISS_FINE:
			return (
				TranslationServer
				. translate("Each passenger who misses this flight costs ${amount}.")
				. format({"amount": amount})
			)
		ODD_HOURS:
			return TranslationServer.translate(
				"Departs at 06:00 or 22:00, outside the usual 07:00 to 21:00."
			)
		EXIT_FEE:
			return (
				TranslationServer
				. translate("Ending this contract in its first {days} days costs ${amount}.")
				. format({"days": EXIT_FEE_DAYS, "amount": amount})
			)
	push_error("OfferTraits.tip_of: unknown trait '%s'" % id)
	return ""


## The [up, down] pairs that may be drawn when `live` ({NEEDS_BAGS: bool,
## NEEDS_SHOPS: bool}, a missing need is not live) holds: table order, forbidden
## pairs and traits whose need is not live left out.
static func pairs(live: Dictionary) -> Array:
	var out := []
	for up in UPS:
		for down in DOWNS:
			if _is_live(up, live) and _is_live(down, live) and not is_forbidden(up, down):
				out.append([up, down])
	return out


## The seed of `day`'s trait stream (see the class notes).
static func seed_for(world_seed: int, day: int) -> int:
	var text := "gmmf-offer-traits|%s|%s|%s" % [str(SEED_VERSION), str(world_seed), str(day)]
	var seed_value := IncidentRoll.fnv1a_32(text.to_utf8_buffer())
	return seed_value if seed_value != 0 else 1


## The traits of `day`'s `count` offers in draw order: one plain, the others
## paired, at levels by `tier` (0..LEVEL_2_CHANCE.size() - 1), from pairs(`live`).
static func draw_day(
	world_seed: int, day: int, count: int, tier: int, live: Dictionary
) -> Array[Dictionary]:
	var stream := IncidentRoll.new(seed_for(world_seed, day))
	var allowed := pairs(live)
	var plain := stream.below(count)
	var out: Array[Dictionary] = []
	for index in count:
		if index == plain:
			out.append(frozen({}))
			continue
		var level := 2 if stream.below(100) < LEVEL_2_CHANCE[tier] else 1
		var pair: Array = allowed[stream.below(allowed.size())]
		out.append(frozen({"up": pair[0], "down": pair[1], "level": level}))
	return out


## "" when a non-empty `data` has the keys, an upside, a downside and a level.
static func _shape_problem(data: Dictionary) -> String:
	var keys: Array = data.keys()
	keys.sort()
	if keys != KEYS:
		return "traits hold exactly %s, not %s" % [KEYS, keys]
	var texts := typeof(data["up"]) == TYPE_STRING and typeof(data["down"]) == TYPE_STRING
	if not texts or not UPS.has(data["up"]) or not DOWNS.has(data["down"]):
		return "traits '%s' and '%s' are not an upside and a downside" % [data["up"], data["down"]]
	if not WholeNumber.is_whole(data["level"]) or not LEVELS.has(int(data["level"])):
		return "traits level must be one of %s" % [LEVELS]
	return ""


static func _is_live(id: String, live: Dictionary) -> bool:
	var need: String = TABLE[id]["needs"]
	return need == "" or bool(live.get(need, false))


## `amount` * `percent` / 100, rounded half up.
static func _percent_of(amount: int, percent: int) -> int:
	@warning_ignore("integer_division")
	return (amount * percent + 50) / 100
