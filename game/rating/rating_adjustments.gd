class_name RatingAdjustments
extends RefCounted
## The incident adjustments AirportRating holds (decision daily-incidents-
## technical-design-incidentdirector-shared-clo): each moves the stars by a
## whole number of half stars, after RatingFormula.stars(), from its outcome
## tick up to but not including its expiry tick. They are never passenger
## records, so they leave the made share and the mood alone.
##
## Expiry: an adjustment is active while outcome_tick <= tick < expiry_tick.
## expiry_for() gives the tick at which an incident's day leaves the rolling
## window (the first tick of the day WINDOW_DAYS after it), so an adjustment
## with that expiry counts at the end of its own day and the two after it,
## exactly as long as a passenger recorded that day. The IncidentDirector
## picks the expiry; a shorter one is allowed.
##
## The list is plain data with its JSON shape and its load checks; a load is
## strict and refuses a bad list whole.

## The keys of one adjustment, in a save as in active().
const KEYS := ["id", "outcome_tick", "expiry_tick", "half_star_delta"]
## Most adjustments held at once; incidents roll at most once a day.
const MAX_COUNT := 64
## Largest shift one adjustment may make either way, in half stars: the whole
## 1 to 5 scale.
const MAX_HALF_STAR_DELTA := 8

var _list: Array[Dictionary] = []


## The first tick of the day the rolling window drops `outcome_tick`'s day.
static func expiry_for(outcome_tick: int) -> int:
	return GameCalendar.day_start(GameCalendar.day_of(outcome_tick) + RatingFormula.WINDOW_DAYS)


## `stars` moved by `half_stars` half stars, clamped to MIN_STARS..MAX_STARS.
static func apply(stars: float, half_stars: int) -> float:
	return clampf(stars + half_stars * 0.5, RatingFormula.MIN_STARS, RatingFormula.MAX_STARS)


## "" if an adjustment with these values may be added at `now`, else why not.
func add_problem(
	id: String, outcome_tick: int, expiry_tick: int, half_star_delta: int, now: int
) -> String:
	var problem := _value_problem(id, outcome_tick, expiry_tick, half_star_delta)
	if problem == "" and expiry_tick <= now:
		problem = "expiry tick %d is not after the rating's tick %d" % [expiry_tick, now]
	if problem == "" and _has(id):
		problem = "adjustment '%s' is already held" % id
	if problem == "" and _list.size() >= MAX_COUNT:
		problem = "%d adjustments are already held" % MAX_COUNT
	return problem


## Adds one that add_problem() passed.
func add(id: String, outcome_tick: int, expiry_tick: int, half_star_delta: int) -> void:
	(
		_list
		. append(
			{
				"id": id,
				"outcome_tick": outcome_tick,
				"expiry_tick": expiry_tick,
				"half_star_delta": half_star_delta,
			}
		)
	)


## The sum of the half stars of those active at `tick`.
func half_stars_at(tick: int) -> int:
	var total := 0
	for entry in _list:
		if entry["outcome_tick"] <= tick and tick < entry["expiry_tick"]:
			total += entry["half_star_delta"]
	return total


## Drops those whose expiry is at or before `tick`; true if any went.
func drop_expired(tick: int) -> bool:
	var kept: Array[Dictionary] = []
	for entry in _list:
		if entry["expiry_tick"] > tick:
			kept.append(entry)
	var dropped := kept.size() != _list.size()
	_list = kept
	return dropped


## Copies of those held, in the order they were added. AirportRating drops
## expired ones as its tick passes, so these are the active ones.
func active() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _list:
		out.append(entry.duplicate())
	return out


## Installs a list from read().
func replace(list: Array[Dictionary]) -> void:
	_list = list


## Reads a saved list taken at `tick` into `out`: "" or why it is refused.
## Every adjustment saved was active at that tick, so its outcome is at or
## before it and its expiry after it.
static func read(entries: Variant, tick: int, out: Array[Dictionary]) -> String:
	if typeof(entries) != TYPE_ARRAY:
		return "adjustments must be an array"
	if (entries as Array).size() > MAX_COUNT:
		return "adjustments holds more than %d" % MAX_COUNT
	var seen := {}
	for entry: Variant in entries:
		var problem := _entry_problem(entry)
		if problem == "":
			problem = _saved_problem(entry, tick, seen)
		if problem != "":
			return problem
		seen[entry["id"]] = true
		(
			out
			. append(
				{
					"id": entry["id"],
					"outcome_tick": int(entry["outcome_tick"]),
					"expiry_tick": int(entry["expiry_tick"]),
					"half_star_delta": int(entry["half_star_delta"]),
				}
			)
		)
	return ""


func _has(id: String) -> bool:
	for entry in _list:
		if entry["id"] == id:
			return true
	return false


static func _value_problem(
	id: String, outcome_tick: int, expiry_tick: int, half_star_delta: int
) -> String:
	if id == "":
		return "an adjustment needs an id"
	if outcome_tick < 0:
		return "outcome tick %d is before the game began" % outcome_tick
	if expiry_tick <= outcome_tick or expiry_tick > RatingSnapshot.MAX_TICK:
		return "expiry tick %d must be after outcome tick %d" % [expiry_tick, outcome_tick]
	if half_star_delta == 0 or absi(half_star_delta) > MAX_HALF_STAR_DELTA:
		return (
			"half_star_delta %d must be from -%d to %d and not 0"
			% [half_star_delta, MAX_HALF_STAR_DELTA, MAX_HALF_STAR_DELTA]
		)
	return ""


static func _entry_problem(entry: Variant) -> String:
	if typeof(entry) != TYPE_DICTIONARY:
		return "adjustments must be dictionaries"
	for key in (entry as Dictionary).keys():
		if not KEYS.has(key):
			return "adjustment has unknown key '%s'" % key
	for key in KEYS:
		if not (entry as Dictionary).has(key):
			return "adjustment is missing key '%s'" % key
	if typeof(entry["id"]) != TYPE_STRING:
		return "adjustment id must be a string"
	# Range-checked before int(): a double past 2^63 does not convert.
	for key in ["outcome_tick", "expiry_tick", "half_star_delta"]:
		var value: Variant = entry[key]
		if not WholeNumber.is_whole(value) or absf(float(value)) > RatingSnapshot.MAX_TICK:
			return "adjustment %s must be a whole number up to 2^53" % key
	return ""


static func _saved_problem(entry: Dictionary, tick: int, seen: Dictionary) -> String:
	if seen.has(entry["id"]):
		return "adjustment '%s' is listed twice" % entry["id"]
	var problem := _value_problem(
		entry["id"],
		int(entry["outcome_tick"]),
		int(entry["expiry_tick"]),
		int(entry["half_star_delta"])
	)
	if problem == "" and int(entry["outcome_tick"]) > tick:
		problem = "adjustment outcome tick is after the saved tick %d" % tick
	if problem == "" and int(entry["expiry_tick"]) <= tick:
		problem = "adjustment expiry tick is not after the saved tick %d" % tick
	return problem
