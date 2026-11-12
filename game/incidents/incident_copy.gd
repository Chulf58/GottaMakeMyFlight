class_name IncidentCopy
extends RefCounted
## The words of the four major incidents' panel: the cause, the reward and the
## failure, in plain sentences with {name} slots (template()). fill() puts in
## the numbers of the incident's saved plan alone (never IncidentTuning, which
## only fills a plan when it is made), so the panel says exactly what will happen:
## the counts of a holiday rush are the ones
## already booked. An announcement (inspector, rush) carries all three in its
## body, since its panel has no reward and failure lines; an offer (VIP,
## favour) keeps them in "reward" and "failure".

const INSPECTOR_BODY := (
	"The airport inspector visits tomorrow, some time between {from} and {to}. "
	+ "The inspector looks at messes on the floor and at queues that are full.\n"
	+ "Reward: {bonus} money if there are at most {max_messes} messes and at most "
	+ "{max_full_queue} passengers stuck in a full queue at the visit.\n"
	+ "If it fails: your rating drops by {penalty}."
)
const RUSH_BODY := (
	"Tomorrow is a holiday. {total} extra passengers are booked, spread over {count} of "
	+ "tomorrow's flights: {list}.\n"
	+ "Reward: every extra passenger pays the usual fee.\n"
	+ "If it fails: queues grow, and passengers who miss their flight lower your "
	+ "rating as usual."
)
const VIP_BODY := "A VIP wants to fly on {flight}. The first passenger to arrive for it is the VIP."
const VIP_REWARD := (
	"{bonus} money if the VIP makes the flight in a good mood (a mood of {good_mood} or "
	+ "higher when boarding)."
)
const VIP_FAILURE := "your rating drops by {penalty} if the VIP misses the flight."
const FAVOUR_BODY := "An airline asks you to fit {extra} more passengers onto {flight}."
const FAVOUR_REWARD := "{bonus} money now, and {extra} more passengers paying their fees."
const FAVOUR_FAILURE := (
	"the extra passengers need check-in and security too, and any who miss the flight "
	+ "lower your rating as usual."
)

## The result cards of a VIP, posted by IncidentCards when it ends: the title
## and the words for each outcome (IncidentMajors.BONUS, NEUTRAL, PENALTY).
const VIP_MADE_TITLE := "The VIP made the flight"
const VIP_MISSED_TITLE := "The VIP missed the flight"
const VIP_BONUS_RESULT := "The VIP boarded in a good mood. You earn {bonus} money."
const VIP_NEUTRAL_RESULT := (
	"The VIP made the flight, but their mood was below {good_mood} when boarding, "
	+ "so there is no bonus."
)
const VIP_MISSED_RESULT := "Your rating drops by {penalty}."

## The result cards of the inspector's visit: the title and the words for each
## outcome (IncidentMajors.PASSED, FAILED).
const INSPECTOR_PASSED_TITLE := "The inspector was happy"
const INSPECTOR_FAILED_TITLE := "The inspector was not happy"
const INSPECTOR_PASSED_RESULT := "You earn {bonus} money."
const INSPECTOR_FAILED_RESULT := "The inspector found {found}. Your rating drops by {penalty}."
## The breaches a failed visit names, each with the count seen and the limit.
const INSPECTOR_MESSES_FOUND := "{seen} on the floor ({allowed} allowed)"
const INSPECTOR_QUEUE_FOUND := "{seen} stuck in a full queue ({allowed} allowed)"


## The unfilled words of a major's panel: {"title", "body"} and, for an offer,
## {"reward", "failure"}. {} for any other kind.
static func template(kind: String) -> Dictionary:
	match kind:
		IncidentCatalogue.INSPECTOR:
			return {"title": "Inspector visit tomorrow", "body": INSPECTOR_BODY}
		IncidentCatalogue.RUSH:
			return {"title": "Holiday rush tomorrow", "body": RUSH_BODY}
		IncidentCatalogue.VIP:
			return {
				"title": "A VIP wants to fly",
				"body": VIP_BODY,
				"reward": VIP_REWARD,
				"failure": VIP_FAILURE,
			}
		IncidentCatalogue.FAVOUR:
			return {
				"title": "An airline asks a favour",
				"body": FAVOUR_BODY,
				"reward": FAVOUR_REWARD,
				"failure": FAVOUR_FAILURE,
			}
	return {}


## `copy` with its {name} slots filled from `incident`'s plan. A copy without
## slots, or an incident without a plan, comes back as it was. `now_tick` is the
## clock when the words are shown: a flight is "today's" or "tomorrow's" by it.
static func fill(copy: Dictionary, incident: Dictionary, now_tick: int) -> Dictionary:
	var vars := vars_of(incident, now_tick)
	var out := {}
	for key: String in copy:
		out[key] = str(copy[key]).format(vars)
	return out


## The slot values of an incident's plan.
static func vars_of(incident: Dictionary, now_tick: int) -> Dictionary:
	var plan: Dictionary = incident.get("plan", {})
	if plan.is_empty():
		return {}
	match incident["kind"]:
		IncidentCatalogue.INSPECTOR:
			return {
				"from": GameCalendar.clock_text(plan["window_from"]),
				"to": GameCalendar.clock_text(plan["window_to"]),
				"bonus": plan["pass_money"],
				"max_messes": plan["max_messes"],
				"max_full_queue": plan["max_full_queue"],
				"penalty": stars_text(plan["fail_half_stars"]),
			}
		IncidentCatalogue.RUSH:
			return _rush_vars(plan)
		IncidentCatalogue.VIP:
			return {
				"flight": _flight_text(plan, now_tick),
				"bonus": plan["bonus"],
				"good_mood": plan["good_mood"],
				"penalty": stars_text(plan["miss_half_stars"]),
			}
		IncidentCatalogue.FAVOUR:
			return {
				"flight": _flight_text(plan, now_tick),
				"extra": plan["extra"],
				"bonus": plan["bonus"],
			}
	return {}


## The result card of a finished VIP, {"title", "detail"}, filled from its plan;
## {} for an incident that is not a VIP or ended without a result to tell
## (IncidentMajors.NOT_HELD).
static func vip_result(incident: Dictionary) -> Dictionary:
	if incident.get("kind", "") != IncidentCatalogue.VIP:
		return {}
	var words := {}
	match incident.get("outcome", ""):
		IncidentMajors.BONUS:
			words = {"title": VIP_MADE_TITLE, "detail": VIP_BONUS_RESULT}
		IncidentMajors.NEUTRAL:
			words = {"title": VIP_MADE_TITLE, "detail": VIP_NEUTRAL_RESULT}
		IncidentMajors.PENALTY:
			words = {"title": VIP_MISSED_TITLE, "detail": VIP_MISSED_RESULT}
		_:
			return {}
	return fill(words, incident, incident["fire_tick"])


## The result card of a finished inspector visit, {"title", "detail"}, filled
## from its plan; {} for an incident that is not an inspector or has no result.
static func inspector_result(incident: Dictionary) -> Dictionary:
	if incident.get("kind", "") != IncidentCatalogue.INSPECTOR:
		return {}
	var words := {}
	match incident.get("outcome", ""):
		IncidentMajors.PASSED:
			words = {"title": INSPECTOR_PASSED_TITLE, "detail": INSPECTOR_PASSED_RESULT}
		IncidentMajors.FAILED:
			words = {"title": INSPECTOR_FAILED_TITLE, "detail": INSPECTOR_FAILED_RESULT}
		_:
			return {}
	var out := fill(words, incident, incident["fire_tick"])
	if incident["outcome"] == IncidentMajors.FAILED:
		out["detail"] = out["detail"].format({"found": _inspector_found(incident["plan"])})
	return out


## The rules a failed visit broke, in words: "4 messes on the floor (2 allowed)",
## "3 passengers stuck in a full queue (none allowed)" or both joined by "and".
## A count within its limit is not named.
static func _inspector_found(plan: Dictionary) -> String:
	var parts := PackedStringArray()
	if plan["seen_messes"] > plan["max_messes"]:
		var seen := _counted(plan["seen_messes"], "mess", "messes")
		parts.append(
			INSPECTOR_MESSES_FOUND.format({"seen": seen, "allowed": _limit(plan, "max_messes")})
		)
	if plan["seen_full_queue"] > plan["max_full_queue"]:
		var seen := _counted(plan["seen_full_queue"], "passenger", "passengers")
		parts.append(
			INSPECTOR_QUEUE_FOUND.format({"seen": seen, "allowed": _limit(plan, "max_full_queue")})
		)
	return " and ".join(parts)


static func _counted(count: int, one: String, many: String) -> String:
	return "%d %s" % [count, one if count == 1 else many]


## A plan limit in words: "none" for 0.
static func _limit(plan: Dictionary, key: String) -> String:
	return "none" if plan[key] == 0 else str(plan[key])


## "today's", "tomorrow's" or "day N's" for a flight leaving at `departs`, seen
## from `now`: the days the departures board heads its list with.
static func day_word(departs: int, now: int) -> String:
	var ahead := GameCalendar.day_of(departs) - GameCalendar.day_of(now)
	if ahead == 0:
		return "%s's" % DeparturesBoard.TODAY_HEADING.to_lower()
	if ahead == 1:
		return "%s's" % DeparturesBoard.TOMORROW_HEADING.to_lower()
	return "day %d's" % (GameCalendar.day_of(departs) + 1)


## Half stars as words: "1 star", "half a star", "1.5 stars".
static func stars_text(half_stars: int) -> String:
	if half_stars == 1:
		return "half a star"
	if half_stars == 2:
		return "1 star"
	if half_stars % 2 == 0:
		@warning_ignore("integer_division")
		return "%d stars" % (half_stars / 2)
	return "%.1f stars" % (half_stars * 0.5)


## The passenger inspect card's line for the VIP, "VIP for today's 15:15
## flight", from the VIP plan.
static func vip_line(plan: Dictionary, now_tick: int) -> String:
	return "VIP for %s" % _flight_text(plan, now_tick)


## "today's 10:29 flight": the plan's flight, seen from the day of `now_tick`.
static func _flight_text(plan: Dictionary, now_tick: int) -> String:
	var when := GameCalendar.clock_text(plan["departs"])
	return "%s %s flight" % [day_word(plan["departs"], now_tick), when]


static func _rush_vars(plan: Dictionary) -> Dictionary:
	var parts := PackedStringArray()
	for flight: Dictionary in plan["flights"]:
		parts.append("%s +%d" % [GameCalendar.clock_text(flight["departs"]), flight["extra"]])
	return {
		"total": plan["total"],
		"count": (plan["flights"] as Array).size(),
		"list": ", ".join(parts),
	}
