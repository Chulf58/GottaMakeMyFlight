class_name HintRules
extends RefCounted
## What the first-time hints teach and when each one is due (HUD 7/7, decision
## first-time-hints-above-the-build-bar-moment-of-need-per-profile-memory).
## Pure rules over a "world" dictionary that read_world() takes from the sim, so
## the queue (Hints) and the tests share one definition of a cause.
##
## The ids are stable forever: the seen memory is keyed by them.

const PLACE_CHECKIN := &"place_checkin"
const PLACE_SECURITY := &"place_security"
const SECOND_HIRE := &"second_hire"
const TOILET := &"toilet"
const FOOD := &"food"
## In priority order: the first one that is ready is shown.
const IDS: Array[StringName] = [PLACE_CHECKIN, PLACE_SECURITY, SECOND_HIRE, TOILET, FOOD]

## A pseudo category: the Staff card being open is the second hire's opportunity.
const STAFF_CARD := "@staff"
## Seconds a cause must stay true before its hint may show, so a flicker (an
## agent between two ticks, a passenger walking past) never shows one.
const HOLD_S := 1.5

const TEXT := {
	PLACE_CHECKIN:
	(
		"Passengers need a check-in desk. Each desk also needs a hired agent:"
		+ " open Staff on the bar."
	),
	PLACE_SECURITY:
	"Passengers need security after check-in. Place a scanner or build a lane, and hire an officer.",
	SECOND_HIRE: "One agent works one desk or scanner. Hire another on the Staff card.",
	TOILET: "Passengers need a toilet. Build a toilet room and put a stall in it.",
	FOOD: "Hungry passengers need food. Build a cafe with a counter and a table.",
}

## The build categories (BuildMenu.CATEGORIES names) that are each hint's
## opportunity: the player opening one while the cause is true.
const CATEGORIES := {
	PLACE_CHECKIN: ["Check-in"],
	PLACE_SECURITY: ["Security", "Lane"],
	SECOND_HIRE: [STAFF_CARD],
	TOILET: ["Toilets"],
	FOOD: ["Cafe", "Food", "Dining"],
}


static func text(id: StringName) -> String:
	return TEXT[id]


static func categories_for(id: StringName) -> Array:
	return CATEGORIES[id]


## The hints whose cause is true in `world`, in IDS order. A cause is a state of
## the world that is true now, never a past event:
## - place_checkin: no desk stands.
## - place_security: a desk stands and there is no scanner and no lane part.
## - second_hire: a role has a verified shortage (read_world()) that the banner
##   does not already name. The banner's hire line for the same role means the
##   same thing, so its role is left out (meaning, not text).
## - toilet / food: a passenger needs one and no usable stall / cafe exists.
static func causes(world: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	if int(world["desks"]) == 0:
		out.append(PLACE_CHECKIN)
	elif int(world["scanners"]) == 0 and int(world["arches"]) == 0:
		out.append(PLACE_SECURITY)
	for role in world["shortage_roles"]:
		if not (world["hiring_roles"] as Array).has(role):
			out.append(SECOND_HIRE)
			break
	if int(world["stalls"]) == 0 and int(world["max_toilet_need"]) >= ToiletSim.NEED_AT:
		out.append(TOILET)
	if int(world["cafes"]) == 0 and int(world["max_hunger"]) >= CafeSim.HUNGRY_AT:
		out.append(FOOD)
	var ordered: Array[StringName] = []
	for id in IDS:
		if out.has(id):
			ordered.append(id)
	return ordered


## The hint to show now, or "". It is the first in IDS order that has its cause
## true, has not been seen, whose cause has held for HOLD_S (`held`: id ->
## seconds) and that has a trigger (`triggers`: id -> bool, an opportunity or
## inactivity).
static func pick(
	causes_now: Array[StringName], seen: Dictionary, held: Dictionary, triggers: Dictionary
) -> StringName:
	for id in IDS:
		if not causes_now.has(id) or seen.get(id, false):
			continue
		if float(held.get(id, 0.0)) >= HOLD_S and bool(triggers.get(id, false)):
			return id
	return &""


## The world as the hints read it from `sim`. `hiring_roles` are the roles the
## status banner currently asks to hire (StaffPanel.hiring_hint_roles()).
## Reading refreshes the toilet and cafe layouts if an edit left them stale.
static func read_world(sim: PassengerSim, hiring_roles: Array) -> Dictionary:
	sim.toilets.refresh()
	sim.cafes.refresh()
	var toilet := 0
	var hunger := 0
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		if p != null:
			toilet = maxi(toilet, p.toilet_need)
			hunger = maxi(hunger, p.hunger)
	return {
		"desks": sim.layout.desks.size(),
		"scanners": sim.layout.scanners.size(),
		"arches": sim.layout.security_lanes.arches.size(),
		"shortage_roles": _shortage_roles(sim),
		"hiring_roles": hiring_roles,
		"max_toilet_need": toilet,
		"max_hunger": hunger,
		"stalls": sim.toilets.layout.stalls.size(),
		"cafes": sim.cafes.layout.cafes.size(),
	}


## The roles (check-in, security) with a verified shortage: a usable station
## staff can reach has nobody claimed to it (an agent walking there has claimed
## it) and no hired agent of the role is spare (idle in the pool). Unusable and
## unreachable stations, and those the player closed (StationClosures), are not
## a shortage.
static func _shortage_roles(sim: PassengerSim) -> Array:
	var roles := []
	var staff := sim.staff
	if staff == null:
		return roles
	for role: StaffMember.Role in [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]:
		var open := 0
		for station in staff.stations_of(role):
			if (
				sim.layout.is_usable(station)
				and not staff.closures.is_closed(station)
				and not staff.spot_blocked(station)
				and not staff.spot_unreachable(station)
				and staff.staff_at(station) == 0
			):
				open += 1
		if open > 0 and _spare(staff, role) == 0:
			roles.append(role)
	return roles


## Hired members of `role` not leaving and not yet sent anywhere.
static func _spare(staff: StaffSim, role: StaffMember.Role) -> int:
	var spare := 0
	for id in staff.member_ids():
		var m := staff.get_member(id)
		if m.role == role and not m.leaving and m.state == StaffMember.State.IDLE:
			spare += 1
	return spare
