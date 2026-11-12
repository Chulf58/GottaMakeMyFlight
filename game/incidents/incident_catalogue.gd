class_name IncidentCatalogue
extends RefCounted
## The incident kinds (decision daily-incidents-small-ones-just-happen-with-
## a-card-and-a-cau): each kind's category (minor or major), the airline tier
## it needs, its weight from what the player has built, the states it moves
## through and its card words. For now one minor kind, the spill, and "none",
## whose weight keeps some days quiet, and the four majors: the inspector's
## visit and the holiday rush (announced), the VIP and the airline favour
## (offers). Their numbers are IncidentTuning's, their words IncidentCopy's,
## their effects IncidentMajors'.

## Bumped whenever a kind or a weight changes: it is part of every roll's seed
## (IncidentRoll), so an old seed never replays against a new catalogue.
const VERSION := 2
const NONE := "none"
const SPILL := "spill"
const INSPECTOR := "inspector"
const RUSH := "rush"
const VIP := "vip"
const FAVOUR := "favour"
const MINOR := "minor"
const MAJOR := "major"
## Every state an incident can be in. A minor is scheduled when rolled, active
## once it happened and done when it is over.
const SCHEDULED := "scheduled"
const ANNOUNCED := "announced"
const OFFERED := "offered"
const ACCEPTED := "accepted"
const DECLINED := "declined"
const ACTIVE := "active"
const DONE := "done"
const STATES: Array[String] = [SCHEDULED, ANNOUNCED, OFFERED, ACCEPTED, DECLINED, ACTIVE, DONE]
## Where a spill can happen: a check-in desk's or a scanner's passenger spot.
const CHECKIN_PLACE := "Check-in"
const SECURITY_PLACE := "Security"
const SPILL_PLACES: Array[String] = [CHECKIN_PLACE, SECURITY_PLACE]
## Catalogue order, which is the weighted draw's order.
const ORDER: Array[String] = [NONE, SPILL, INSPECTOR, RUSH, VIP, FAVOUR]
## "offer" is true for an opt-in major the player accepts or declines; the
## others are announced.
const KINDS := {
	NONE: {"category": MINOR, "tier": 0},
	SPILL: {"category": MINOR, "tier": 0},
	INSPECTOR: {"category": MAJOR, "tier": IncidentTuning.INSPECTOR_TIER, "offer": false},
	RUSH: {"category": MAJOR, "tier": IncidentTuning.RUSH_TIER, "offer": false},
	VIP: {"category": MAJOR, "tier": IncidentTuning.VIP_TIER, "offer": true},
	FAVOUR: {"category": MAJOR, "tier": IncidentTuning.FAVOUR_TIER, "offer": true},
}
## The weight of a quiet day. Tuning value.
const NONE_WEIGHT := 4
## A spill's weight is one per place it can happen (check-in desks and
## scanners), up to this. Tuning value: with the starter terminal's one desk
## and one scanner a spill comes about one day in three.
const SPILL_MOST := 4


## The kinds an incident can be, "none" left out.
static func kinds() -> Array[String]:
	var out: Array[String] = []
	for kind in ORDER:
		if kind != NONE:
			out.append(kind)
	return out


static func is_major(kind: String) -> bool:
	return KINDS.get(kind, {}).get("category", MINOR) == MAJOR


static func tier(kind: String) -> int:
	return int(KINDS.get(kind, {}).get("tier", 0))


## Whether a major is an opt-in offer (VIP, favour) rather than an announcement.
static func is_offer(kind: String) -> bool:
	return KINDS.get(kind, {}).get("offer", false)


## The weight of `kind` in `world`: {"tier": the airline tier, "places": the
## places a spill can happen, "contracts": the running contracts}. The rush,
## the VIP and the favour need a running contract to land on.
static func weight(kind: String, world: Dictionary) -> int:
	var contracts := int(world.get("contracts", 0)) > 0
	match kind:
		NONE:
			return NONE_WEIGHT
		SPILL:
			return mini(int(world.get("places", 0)), SPILL_MOST)
		INSPECTOR:
			return IncidentTuning.INSPECTOR_WEIGHT
		RUSH:
			return IncidentTuning.RUSH_WEIGHT if contracts else 0
		VIP:
			return IncidentTuning.VIP_WEIGHT if contracts else 0
		FAVOUR:
			return IncidentTuning.FAVOUR_WEIGHT if contracts else 0
	return 0


## The roll's candidates for `world`, in catalogue order: each kind the tier
## allows, with its weight (IncidentRoll.roll).
static func candidates(world: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for kind in ORDER:
		if tier(kind) <= int(world.get("tier", 0)):
			out.append({"kind": kind, "weight": weight(kind, world), "major": is_major(kind)})
	return out


## The states `kind` moves through.
static func states_for(kind: String) -> Array[String]:
	var out: Array[String] = []
	match kind:
		SPILL:
			out.assign([SCHEDULED, ACTIVE, DONE])
		INSPECTOR, RUSH:
			out.assign([SCHEDULED, ANNOUNCED, DONE])
		VIP:
			out.assign([SCHEDULED, OFFERED, ACCEPTED, DECLINED, DONE])
		FAVOUR:
			out.assign([SCHEDULED, OFFERED, DECLINED, DONE])
	return out


## The words of a major's panel (IncidentPanel): {"title", "body"}, and for an
## offer also {"reward", "failure"}, each a short plain sentence naming what the
## player gets and what it costs. They hold {name} slots that
## IncidentCopy.fill() fills from the incident's plan, so the numbers shown are
## the ones in force. {} for a kind with none (every minor).
static func panel_copy(kind: String) -> Dictionary:
	return IncidentCopy.template(kind)


## The card's title for an active incident.
static func card_title(incident: Dictionary) -> String:
	if incident.get("kind", "") == SPILL:
		return "Spill near %s" % incident["place"]
	return ""


## The card's words for an active incident: the cause, then what happens next.
static func card_detail(incident: Dictionary, cleaner_hired: bool) -> String:
	if incident.get("kind", "") != SPILL:
		return ""
	var cause := "A passenger dropped a coffee."
	if cleaner_hired:
		return "%s A cleaner will mop it up." % cause
	return "%s Hire a cleaner to clean it." % cause
