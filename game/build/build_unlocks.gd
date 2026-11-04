class_name BuildUnlocks
extends Node
## Which build tools a game has opened (decisions build-unlocks-need-stars-and-
## passengers-served-hunger-cafe-a and build-items-unlock-with-airport-rating-
## stars-and-stay-unlocked). A new game offers the start set; tiers 2 to 4 open
## when the airport rating reaches the tier's stars AND the lifetime count of
## passengers who made their flight reaches its threshold (placeholders,
## tuned by playtest). A tier, once reached, is never lost, and what the player
## built above the tier before a load stays usable (only picking the tool is
## gated). The check runs on the first tick of each new game day, after the
## AirportRating has recorded the finished flights' no-shows (the scene lists
## this node after the rating, so its tick handler runs second).
##
## The cafe tier also starts passenger hunger: CafeSim.hunger_enabled follows
## cafe_open(), so before it no passenger grows hungry, loses mood to food or
## gets the cafe hint. Bins unlock with the cafe.
##
## BuildMode.set_tool() asks lock_text(); BuildMenu greys the locked cards with
## the same text. The save keeps the tier and the made-flight count (part
## "unlocks", SaveGame).

## The tier changed (a new game, an unlock or a load).
signal tier_changed(tier: int)
## A tier opened by play: the facilities it brings, ready to show.
signal unlocked(tier: int, text: String)

## The tier a new game starts at, and the one that opens the cafe.
const START_TIER := 1
const CAFE_TIER := 2
## Needed by a tool no tier lists: never met, so the tool is refused.
const UNLISTED_TIER := 99
## Most made-flight passengers counted (a save above it is refused).
const MAX_MADE := 1000000000
const NO_DAY := -1
const NOT_WIRED_TEXT := "Build unlocks are not wired"
## Each tier in order: the stars and made-flight passengers that open it, what
## to call its facilities in the unlock message, and its tools. Tier 1 is the
## start set. NONE and REMOVE belong to no tier and are always open.
const TIERS := [
	{
		"stars": 0.0,
		"passengers": 0,
		"facilities": "",
		"tools":
		[
			BuildMode.Tool.FLOOR,
			BuildMode.Tool.WALL,
			BuildMode.Tool.GLASS,
			BuildMode.Tool.DOOR,
			BuildMode.Tool.ENTRANCE,
			BuildMode.Tool.EXIT,
			BuildMode.Tool.DESK,
			BuildMode.Tool.SCANNER,
			BuildMode.Tool.GATE_DESK,
			BuildMode.Tool.SEATS,
			BuildMode.Tool.TOILET_ROOM,
			BuildMode.Tool.TOILET_STALL,
			BuildMode.Tool.TOILET_SINK,
			BuildMode.Tool.BUY_LAND,
		],
	},
	{
		"stars": 2.0,
		"passengers": 50,
		"facilities":
		"cafe and bins, security lane, baggage, kiosk, screen, plants, benches, curb bay",
		"tools":
		[
			BuildMode.Tool.CAFE_ROOM,
			BuildMode.Tool.COUNTER,
			BuildMode.Tool.TABLE,
			BuildMode.Tool.BIN,
			BuildMode.Tool.TRAY_TABLE,
			BuildMode.Tool.XRAY_BELT,
			BuildMode.Tool.ARCH,
			BuildMode.Tool.PICKUP_TABLE,
			BuildMode.Tool.BELT,
			BuildMode.Tool.BAG_ROOM,
			BuildMode.Tool.CART,
			BuildMode.Tool.KIOSK_ROOM,
			BuildMode.Tool.KIOSK_COUNTER,
			BuildMode.Tool.KIOSK_DISPLAY,
			BuildMode.Tool.SCREEN,
			BuildMode.Tool.BUSH,
			BuildMode.Tool.PLANTER,
			BuildMode.Tool.PLANT_POT,
			BuildMode.Tool.BENCH,
			BuildMode.Tool.POST,
			BuildMode.Tool.CHAIN,
			BuildMode.Tool.CURB,
		],
	},
	{
		"stars": 3.0,
		"passengers": 200,
		"facilities":
		(
			"food and services: bar, restaurant, grab-and-go, info desk, pharmacy,"
			+ " exchange, ATM, lounge, car park"
		),
		"tools":
		[
			BuildMode.Tool.TREE,
			BuildMode.Tool.TREE_BENCH,
			BuildMode.Tool.SURFACE_LOT,
			BuildMode.Tool.LOT_GATE,
			BuildMode.Tool.BAR_ROOM,
			BuildMode.Tool.RESTAURANT_ROOM,
			BuildMode.Tool.STALL_ROOM,
			BuildMode.Tool.BAR_COUNTER,
			BuildMode.Tool.GRAB_STALL,
			BuildMode.Tool.DINING_TABLE,
			BuildMode.Tool.BOOTH,
			BuildMode.Tool.INFO_DESK,
			BuildMode.Tool.INFO_SCREEN,
			BuildMode.Tool.PHARMACY_ROOM,
			BuildMode.Tool.PHARMACY_COUNTER,
			BuildMode.Tool.PHARMACY_SHELF,
			BuildMode.Tool.EXCHANGE_ROOM,
			BuildMode.Tool.EXCHANGE,
			BuildMode.Tool.ATM_ROOM,
			BuildMode.Tool.ATM,
			BuildMode.Tool.LOUNGE_ROOM,
			BuildMode.Tool.SOFA,
			BuildMode.Tool.ARMCHAIR,
			BuildMode.Tool.WORK_DESK,
		],
	},
	{
		"stars": 4.0,
		"passengers": 600,
		"facilities":
		(
			"premium shops and amenities: duty free, fashion, shower, nap pod, play area,"
			+ " fountain, statue, multi-storey"
		),
		"tools":
		[
			BuildMode.Tool.FOUNTAIN,
			BuildMode.Tool.STATUE,
			BuildMode.Tool.MULTI_STOREY,
			BuildMode.Tool.DUTY_FREE_ROOM,
			BuildMode.Tool.DUTY_FREE_TILL,
			BuildMode.Tool.DUTY_FREE_SHELF,
			BuildMode.Tool.FASHION_ROOM,
			BuildMode.Tool.FASHION_TILL,
			BuildMode.Tool.FASHION_RAIL,
			BuildMode.Tool.SHOWER,
			BuildMode.Tool.SHOWER_ROOM,
			BuildMode.Tool.NAP_POD,
			BuildMode.Tool.NAP_POD_ROOM,
			BuildMode.Tool.PLAY_AREA_ROOM,
			BuildMode.Tool.PLAY_BLOCKS,
			BuildMode.Tool.PLAY_SLIDE,
			BuildMode.Tool.PRIZE_PODIUM,
		],
	},
]

## Tool -> the tier that opens it, built on first use.
static var _by_tool: Dictionary = {}

## The airport rating the stars are read from and the passenger sim whose
## outcomes are counted and whose cafe hunger follows the cafe tier. The scene
## wires both; a node without them never unlocks.
@export var rating: AirportRating
@export var passengers: PassengerSim
## Ticks the day check; without it only check() unlocks.
@export var clock: SimClock

var _tier := START_TIER
var _made := 0
var _checked_day := NO_DAY


func _ready() -> void:
	if rating == null or passengers == null:
		push_error("BuildUnlocks: rating and passengers must be set; nothing will unlock")
	if passengers != null:
		passengers.outcome.connect(_on_outcome)
	if clock != null:
		clock.ticked.connect(on_tick)
	tier_changed.connect(_apply_hunger)
	_apply_hunger(_tier)


## The tier a tool needs: 0 for NONE and REMOVE (always open), UNLISTED_TIER for
## a tool no tier lists.
static func tier_of(tool: BuildMode.Tool) -> int:
	if tool == BuildMode.Tool.NONE or tool == BuildMode.Tool.REMOVE:
		return 0
	if _by_tool.is_empty():
		for i in TIERS.size():
			for listed: BuildMode.Tool in TIERS[i]["tools"]:
				_by_tool[listed] = i + 1
	return _by_tool.get(tool, UNLISTED_TIER)


## Why `tool` cannot be picked, or "" when it can. `gate` is the scene's
## BuildUnlocks; none builds with every tool only when `required` is false (a
## test world or probe that builds without a game), and otherwise refuses every
## gated tool, never unlocks them.
static func lock_text(gate: BuildUnlocks, required: bool, tool: BuildMode.Tool) -> String:
	if tier_of(tool) == 0:
		return ""
	if gate == null:
		return NOT_WIRED_TEXT if required else ""
	return "" if gate.allows(tool) else gate.unlock_text(tool)


## What tier `tier` asks for: "Unlocks at 3 stars and 200 passengers".
static func requirement_text(tier: int) -> String:
	if tier < 2 or tier > TIERS.size():
		return "Not available yet"
	var need: Dictionary = TIERS[tier - 1]
	var stars: float = need["stars"]
	return (
		"Unlocks at %s stars and %d passengers"
		% [
			str(int(stars)) if is_equal_approx(stars, floorf(stars)) else str(stars),
			need["passengers"]
		]
	)


func tier() -> int:
	return _tier


## Passengers counted as having made their flight, over the whole game.
func made_total() -> int:
	return _made


func allows(tool: BuildMode.Tool) -> bool:
	return tier_of(tool) <= _tier


## True from the cafe tier on: hunger, the food mood penalty and the cafe hint
## all start with it.
func cafe_open() -> bool:
	return _tier >= CAFE_TIER


## The requirement of the tier `tool` needs, and how far the game is from it.
func unlock_text(tool: BuildMode.Tool) -> String:
	var needed := tier_of(tool)
	var text := requirement_text(needed)
	if needed < 2 or needed > TIERS.size() or rating == null:
		return text
	return "%s (now %s stars, %d passengers)" % [text, str(rating.stars()), _made]


## The first tick of a new game day runs the check.
func on_tick(tick: int) -> void:
	var day := GameCalendar.day_of(tick)
	if day == _checked_day:
		return
	_checked_day = day
	check()


## Opens every tier whose stars and passengers are both met; one that is open
## stays open.
func check() -> void:
	if rating == null:
		return
	var stars := rating.stars()
	var reached := _tier
	for i in range(_tier, TIERS.size()):
		var need: Dictionary = TIERS[i]
		if stars < need["stars"] or _made < need["passengers"]:
			break
		reached = i + 1
	if reached > _tier:
		_open_to(reached)


## One more passenger made their flight.
func note_made() -> void:
	_made = mini(_made + 1, MAX_MADE)


## JSON-safe state for a save: the highest tier and the made-flight count.
func to_snapshot() -> Dictionary:
	return {"tier": _tier, "made": _made}


## Restores a to_snapshot() dictionary, including one that went through JSON.
## Pushes an error and returns false, leaving the state unchanged, when
## anything is missing, mistyped or out of range.
func from_snapshot(data: Dictionary) -> bool:
	var problem := _snapshot_problem(data)
	if problem != "":
		push_error("BuildUnlocks.from_snapshot: %s" % problem)
		return false
	_tier = int(data["tier"])
	_made = int(data["made"])
	_checked_day = NO_DAY
	tier_changed.emit(_tier)
	return true


static func _snapshot_problem(data: Dictionary) -> String:
	for key in data.keys():
		if key != "tier" and key != "made":
			return "unknown key '%s'" % key
	for key in ["tier", "made"]:
		if not data.has(key) or not WholeNumber.is_whole(data[key]):
			return "'%s' must be a whole number" % key
	if int(data["tier"]) < START_TIER or int(data["tier"]) > TIERS.size():
		return "tier %d is outside %d to %d" % [int(data["tier"]), START_TIER, TIERS.size()]
	if int(data["made"]) < 0 or int(data["made"]) > MAX_MADE:
		return "made %d is outside 0 to %d" % [int(data["made"]), MAX_MADE]
	return ""


func _open_to(reached: int) -> void:
	var opened := []
	for i in range(_tier, reached):
		opened.append(TIERS[i]["facilities"])
	_tier = reached
	tier_changed.emit(_tier)
	unlocked.emit(_tier, "Unlocked: %s" % "; ".join(opened))


func _on_outcome(_id: int, made: bool) -> void:
	if made:
		note_made()


func _apply_hunger(_new_tier: int) -> void:
	if passengers != null:
		passengers.cafes.hunger_enabled = cafe_open()
