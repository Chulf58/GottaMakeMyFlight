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

## The words are built in static functions, which cannot call tr() (an Object
## method), so they go through this instance's tr() and tr_n().
static var _translator := RefCounted.new()
static var _long := LongWords.new()


## The unfilled words of a major's panel: {"title", "body"} and, for an offer,
## {"reward", "failure"}. {} for any other kind.
static func template(kind: String) -> Dictionary:
	match kind:
		IncidentCatalogue.INSPECTOR:
			return {
				"title": _translator.tr("Inspector visit tomorrow"),
				"body": _long.inspector_body(),
			}
		IncidentCatalogue.RUSH:
			return {"title": _translator.tr("Holiday rush tomorrow"), "body": _long.rush_body()}
		IncidentCatalogue.VIP:
			return {
				"title": _translator.tr("A VIP wants to fly"),
				"body":
				(
					_translator
					. tr(
						"A VIP wants to fly on {flight}. The first passenger to arrive for it is the VIP."
					)
				),
				"reward": _long.vip_reward(),
				"failure":
				_translator.tr("your rating drops by {penalty} if the VIP misses the flight."),
			}
		IncidentCatalogue.FAVOUR:
			return {
				"title": _translator.tr("An airline asks a favour"),
				"body":
				_translator.tr("An airline asks you to fit {extra} more passengers onto {flight}."),
				"reward":
				_translator.tr("{bonus} money now, and {extra} more passengers paying their fees."),
				"failure": _long.favour_failure(),
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
			words = {
				"title": _translator.tr("The VIP made the flight"),
				"detail": _translator.tr("The VIP boarded in a good mood. You earn {bonus} money."),
			}
		IncidentMajors.NEUTRAL:
			words = {
				"title": _translator.tr("The VIP made the flight"),
				"detail": _long.vip_neutral_result(),
			}
		IncidentMajors.PENALTY:
			words = {
				"title": _translator.tr("The VIP missed the flight"),
				"detail": _translator.tr("Your rating drops by {penalty}."),
			}
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
			words = {
				"title": _translator.tr("The inspector was happy"),
				"detail": _translator.tr("You earn {bonus} money."),
			}
		IncidentMajors.FAILED:
			words = {
				"title": _translator.tr("The inspector was not happy"),
				"detail":
				_translator.tr("The inspector found {found}. Your rating drops by {penalty}."),
			}
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
		var seen := _translator.tr_n(
			"{count} mess on the floor ({allowed} allowed)",
			"{count} messes on the floor ({allowed} allowed)",
			plan["seen_messes"]
		)
		parts.append(
			seen.format({"count": plan["seen_messes"], "allowed": _limit(plan, "max_messes")})
		)
	if plan["seen_full_queue"] > plan["max_full_queue"]:
		var seen := _translator.tr_n(
			"{count} passenger stuck in a full queue ({allowed} allowed)",
			"{count} passengers stuck in a full queue ({allowed} allowed)",
			plan["seen_full_queue"]
		)
		parts.append(
			seen.format(
				{"count": plan["seen_full_queue"], "allowed": _limit(plan, "max_full_queue")}
			)
		)
	if parts.size() == 2:
		return _translator.tr("{first} and {second}").format(
			{"first": parts[0], "second": parts[1]}
		)
	return "".join(parts)


## A plan limit in words: "none" for 0.
static func _limit(plan: Dictionary, key: String) -> String:
	return _translator.tr("none") if plan[key] == 0 else str(plan[key])


## "today's", "tomorrow's" or "day N's" for a flight leaving at `departs`, seen
## from `now`: the days the departures board heads its list with.
static func day_word(departs: int, now: int) -> String:
	var ahead := GameCalendar.day_of(departs) - GameCalendar.day_of(now)
	if ahead == 0:
		return _translator.tr("today's")
	if ahead == 1:
		return _translator.tr("tomorrow's")
	return _translator.tr("day {day}'s").format({"day": GameCalendar.day_of(departs) + 1})


## Half stars as words: "1 star", "half a star", "1.5 stars".
static func stars_text(half_stars: int) -> String:
	if half_stars == 1:
		return _translator.tr("half a star")
	if half_stars % 2 == 0:
		@warning_ignore("integer_division")
		var whole := half_stars / 2
		return _translator.tr_n("{count} star", "{count} stars", whole).format({"count": whole})
	return _translator.tr("{count} stars").format({"count": "%.1f" % (half_stars * 0.5)})


## The passenger inspect card's line for the VIP, "VIP for today's 15:15
## flight", from the VIP plan.
static func vip_line(plan: Dictionary, now_tick: int) -> String:
	return _translator.tr("VIP for {flight}").format({"flight": _flight_text(plan, now_tick)})


## "today's 10:29 flight": the plan's flight, seen from the day of `now_tick`.
static func _flight_text(plan: Dictionary, now_tick: int) -> String:
	var when := GameCalendar.clock_text(plan["departs"])
	return _translator.tr("{day} {time} flight").format(
		{"day": day_word(plan["departs"], now_tick), "time": when}
	)


static func _rush_vars(plan: Dictionary) -> Dictionary:
	var parts := PackedStringArray()
	for flight: Dictionary in plan["flights"]:
		parts.append("%s +%d" % [GameCalendar.clock_text(flight["departs"]), flight["extra"]])
	return {
		"total": plan["total"],
		"count": (plan["flights"] as Array).size(),
		"list": ", ".join(parts),
	}


## The sentences too long for a line, as instance methods: gdformat breaks a long
## literal in `_translator.tr(` into an unreadable chain, and a bare tr() is the form
## the POT extractor reads.
class LongWords:
	extends RefCounted

	## The inspector's announcement, a line per paragraph: the visit, the reward, the failure.
	func inspector_body() -> String:
		var visit := tr("The airport inspector visits tomorrow, some time between {from} and {to}.")
		var looks := tr("The inspector looks at messes on the floor and at queues that are full.")
		var reward := tr(
			# gdlint:ignore = max-line-length
			"Reward: {bonus} money if there are at most {max_messes} messes and at most {max_full_queue} passengers stuck in a full queue at the visit."
		)
		var failure := tr("If it fails: your rating drops by {penalty}.")
		return "\n".join([" ".join([visit, looks]), reward, failure])

	func rush_body() -> String:
		var booked := tr(
			# gdlint:ignore = max-line-length
			"Tomorrow is a holiday. {total} extra passengers are booked, spread over {count} of tomorrow's flights: {list}."
		)
		var reward := tr("Reward: every extra passenger pays the usual fee.")
		var failure := tr(
			# gdlint:ignore = max-line-length
			"If it fails: queues grow, and passengers who miss their flight lower your rating as usual."
		)
		return "\n".join([booked, reward, failure])

	func vip_reward() -> String:
		return tr(
			# gdlint:ignore = max-line-length
			"{bonus} money if the VIP makes the flight in a good mood (a mood of {good_mood} or higher when boarding)."
		)

	func favour_failure() -> String:
		return tr(
			# gdlint:ignore = max-line-length
			"the extra passengers need check-in and security too, and any who miss the flight lower your rating as usual."
		)

	func vip_neutral_result() -> String:
		return tr(
			# gdlint:ignore = max-line-length
			"The VIP made the flight, but their mood was below {good_mood} when boarding, so there is no bonus."
		)
