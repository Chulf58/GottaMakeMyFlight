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
const VIP_BODY := (
	"A VIP wants to fly on the {time} flight. The first passenger to arrive for that "
	+ "flight is the VIP."
)
const VIP_REWARD := "{bonus} money if the VIP makes the flight in a good mood."
const VIP_FAILURE := "your rating drops by {penalty} if the VIP misses the flight."
const FAVOUR_BODY := "An airline asks you to fit {extra} more passengers onto its {time} flight."
const FAVOUR_REWARD := "{bonus} money now, and {extra} more passengers paying their fees."
const FAVOUR_FAILURE := (
	"the extra passengers need check-in and security too, and any who miss the flight "
	+ "lower your rating as usual."
)


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
## slots, or an incident without a plan, comes back as it was.
static func fill(copy: Dictionary, incident: Dictionary) -> Dictionary:
	var vars := vars_of(incident)
	var out := {}
	for key: String in copy:
		out[key] = str(copy[key]).format(vars)
	return out


## The slot values of an incident's plan.
static func vars_of(incident: Dictionary) -> Dictionary:
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
				"time": GameCalendar.clock_text(plan["departs"]),
				"bonus": plan["bonus"],
				"penalty": stars_text(plan["miss_half_stars"]),
			}
		IncidentCatalogue.FAVOUR:
			return {
				"time": GameCalendar.clock_text(plan["departs"]),
				"extra": plan["extra"],
				"bonus": plan["bonus"],
			}
	return {}


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


static func _rush_vars(plan: Dictionary) -> Dictionary:
	var parts := PackedStringArray()
	for flight: Dictionary in plan["flights"]:
		parts.append("%s +%d" % [GameCalendar.clock_text(flight["departs"]), flight["extra"]])
	return {
		"total": plan["total"],
		"count": (plan["flights"] as Array).size(),
		"list": ", ".join(parts),
	}
