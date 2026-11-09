class_name RunwayWorks
extends RefCounted
## The works that grow the runway one size (decision runway-upgrade-works-wait-
## for-a-timetable-gap-passengers-per-plane-class and runway-and-taxi-technical-
## design-movement-plan-analytic-bookings-planned-pauses, section 7). A bought
## upgrade books the runway into the first stretch of the timetable that is
## clear of every booking for the whole works (FlightPlans.works_start), about
## 1 game hour for a medium runway and 2 for a large one, so no flight is lost.
## The stretch is then a fixed booking for every plan (fixed_bookings()): an
## offer that would use the runway during it is refused, and no plane already
## planned changes. When the works end the runway takes the new size (Runway.
## settle()). While the airport is closed nothing flies, so FlightSim applies
## the size at once and books nothing.
##
## One instance per Runway holds the state, which is saved with it: the size the
## works build ("" for none), and the tick they start and end. After the size
## switches, the booking is held HOLD_TICKS longer: a plane that met the works
## and was planned around them is still flying, and dropping the booking would
## re-plan it.
##
## The static functions are the player's side: problem() says why the upgrade
## cannot be bought, buy() takes the money and books the works.

const LARGEST_TEXT := "The runway is already the largest size"
const BOOKED_TEXT := "Runway works are already booked"
const NO_GAP_TEXT := "The timetable leaves no quiet stretch for the works"

## Ticks the works take, by the size they build: 1 and 2 game hours.
const TICKS := {PlaneClasses.MEDIUM: 1200, PlaneClasses.LARGE: 2400}
## The ticks a flight takes from its first state to DEPARTED
## (FlightSim.PHASE_TICKS added up), a test pins it.
const HOLD_TICKS := 3900
const SAVE_KEYS := ["target", "start", "finish"]
const NO_TICK := -1

## The size the works build, "" when none are booked or under way.
var target := ""
## The first and last tick of the works, NO_TICK for none. They stay after the
## works end, until the booking is dropped.
var start := NO_TICK
var finish := NO_TICK


## How many ticks the works that build a `size` runway take, 0 for a size
## nothing builds.
static func ticks(size: String) -> int:
	return TICKS.get(size, 0)


## The size one upgrade builds from a runway of `size`, "" for the largest and
## for an unknown size.
static func next_size(size: String) -> String:
	var at := PlaneClasses.ORDER.find(size)
	if at < 0 or at + 1 >= PlaneClasses.ORDER.size():
		return ""
	return PlaneClasses.ORDER[at + 1]


## What the card says when the wallet is short of the works.
static func short_text(size: String) -> String:
	return "Not enough money: the %s runway works cost $%d" % [size, PriceTable.runway_price(size)]


## Why the runway of `flights` cannot be upgraded now, or "": the largest runway
## has none, works already booked, the build tier not reached (the unlock text,
## with the stars and passengers the game has), a short wallet, or a timetable
## with no stretch for the works.
static func problem(flights: FlightSim, unlocks: BuildUnlocks, wallet: Wallet) -> String:
	var next := next_size(flights.runway.size)
	var text := BOOKED_TEXT if flights.runway.works.scheduled() else ""
	if text == "" and next == "":
		text = LARGEST_TEXT
	if text == "":
		text = _means_problem(next, unlocks, wallet)
	if text == "" and flights.works_start(next) < 0:
		text = NO_GAP_TEXT
	return text


## The tier and wallet part of problem() for the upgrade to `next`.
static func _means_problem(next: String, unlocks: BuildUnlocks, wallet: Wallet) -> String:
	if unlocks == null:
		return BuildUnlocks.NOT_WIRED_TEXT
	var tier := BuildUnlocks.runway_tier(next)
	if unlocks.tier() < tier:
		return unlocks.tier_text(tier)
	if wallet == null or not wallet.can_afford(PriceTable.runway_price(next)):
		return short_text(next)
	return ""


## Books the upgrade and takes its price, or returns what problem() says and
## changes nothing.
static func buy(flights: FlightSim, unlocks: BuildUnlocks, wallet: Wallet) -> String:
	var refusal := problem(flights, unlocks, wallet)
	if refusal != "":
		return refusal
	var next := next_size(flights.runway.size)
	if not flights.start_works(next):
		return NO_GAP_TEXT
	if not wallet.spend(PriceTable.runway_price(next), Wallet.Category.BUILD):
		push_error("RunwayWorks.buy: the wallet refused the price it had just afforded")
	return ""


## What the card says about the works: "" when none are booked, else when they
## start and end, as a clock time (with the day when it is not today).
static func schedule_text(works: RunwayWorks, now: int) -> String:
	if not works.scheduled():
		return ""
	var begins := "start" if works.start >= now else "started"
	return (
		"Works on the %s runway %s %s and end %s"
		% [
			works.target,
			begins,
			_when(works.start, now),
			_when(works.finish, now),
		]
	)


## "at 22:05", "tomorrow at 00:05" or "on Day 4 at 00:05" (the HUD's day number).
static func _when(tick: int, now: int) -> String:
	var ahead := GameCalendar.day_of(tick) - GameCalendar.day_of(now)
	var time := GameCalendar.clock_text(tick)
	if ahead <= 0:
		return "at %s" % time
	if ahead == 1:
		return "tomorrow at %s" % time
	return "on Day %d at %s" % [GameCalendar.day_of(tick) + 1, time]


## Books works that build `size` from tick `from`.
func begin(size: String, from: int) -> void:
	target = size
	start = from
	finish = from + ticks(size)


## Forgets the works and their booking.
func clear() -> void:
	target = ""
	start = NO_TICK
	finish = NO_TICK


## Whether works are booked or under way (their size not yet built).
func scheduled() -> bool:
	return target != ""


## The works as a fixed booking for GroundPlanner.plan_all(): one while the
## works are booked, under way or held, none otherwise.
func fixed_bookings() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if start != NO_TICK:
		out.append(GroundPlanner.works_booking(float(start), float(finish - start)))
	return out


func to_snapshot() -> Dictionary:
	return {"target": target, "start": start, "finish": finish}


## Restores a to_snapshot() dictionary, including one that went through JSON.
## Pushes an error and returns false, leaving the works unchanged, when
## anything is missing, mistyped or inconsistent.
func from_snapshot(data: Dictionary) -> bool:
	var refusal := snapshot_problem(data)
	if refusal != "":
		push_error("RunwayWorks.from_snapshot: %s" % refusal)
		return false
	target = data["target"]
	start = int(data["start"])
	finish = int(data["finish"])
	return true


## "" when `data` is exactly SAVE_KEYS and either holds no works, or the ticks
## of held works, or booked works of a size that takes ticks(target) from start.
func snapshot_problem(data: Dictionary) -> String:
	var shape := _shape_problem(data)
	if shape != "":
		return shape
	var from := int(data["start"])
	var to := int(data["finish"])
	var size: String = data["target"]
	var none := from == NO_TICK and to == NO_TICK
	var held := from >= 0 and to > from
	if size == "":
		return "" if none or held else "held works need a start and a later finish, or neither"
	if not TICKS.has(size):
		return "target must be one of %s or empty" % [TICKS.keys()]
	if from < 0 or to != from + ticks(size):
		return "works of a %s runway run %d ticks from a start of 0 or more" % [size, ticks(size)]
	return ""


## What is wrong with the keys and types of `data`, or "".
func _shape_problem(data: Dictionary) -> String:
	for key in data.keys():
		if not SAVE_KEYS.has(key):
			return "unknown key '%s'" % key
	for key in SAVE_KEYS:
		if not data.has(key):
			return "missing key '%s'" % key
	if typeof(data["target"]) != TYPE_STRING:
		return "target must be a string"
	for key in ["start", "finish"]:
		if not WholeNumber.is_whole(data[key]):
			return "%s must be a whole number" % key
	return ""
