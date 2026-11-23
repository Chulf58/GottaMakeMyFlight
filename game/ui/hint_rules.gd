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
const PLACE_GATE_DESK := &"place_gate_desk"
const PLACE_SEATS := &"place_seats"
const SECOND_HIRE := &"second_hire"
const TOILET := &"toilet"
const FOOD := &"food"
const BAGGAGE_CONNECT := &"baggage_connect"
## The invitation to click a passenger (FollowInvite). It is remembered in the
## file once the player has selected a passenger, not once it has shown.
const FOLLOW_PASSENGER := &"follow_passenger"
## Onboarding hints that may already be true on frame 0 and should not be
## swallowed by the initial baseline read.
const STARTUP_IDS: Array[StringName] = [
	PLACE_CHECKIN,
	PLACE_SECURITY,
	PLACE_GATE_DESK,
	PLACE_SEATS,
]
## In priority order: the first one that is ready is shown.
const IDS: Array[StringName] = [
	PLACE_CHECKIN,
	PLACE_SECURITY,
	PLACE_GATE_DESK,
	PLACE_SEATS,
	SECOND_HIRE,
	TOILET,
	FOOD,
	BAGGAGE_CONNECT,
	FOLLOW_PASSENGER,
]

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
	PLACE_GATE_DESK:
	"Passengers board at a gate. Place a gate desk by an exit that faces the planes.",
	PLACE_SEATS:
	"Passengers wait at the gate. Place seats near it; the airport opens without them.",
	SECOND_HIRE: "One agent works one desk or scanner. Hire another on the Staff card.",
	TOILET: "Passengers need a toilet. Build a toilet room and put a stall in it.",
	FOOD: "Hungry passengers need food. Build a cafe with a counter and a table.",
	BAGGAGE_CONNECT: "Drag a belt from the back of a check-in desk into your Bag Room.",
	FOLLOW_PASSENGER: "Click a passenger to follow them to their flight",
}

## The build tools (BuildMode.Tool) or STAFF_CARD whose open category is each
## hint's opportunity: the player opening that tab while the cause is true.
const CATEGORIES := {
	PLACE_CHECKIN: [BuildMode.Tool.DESK],
	PLACE_SECURITY: [BuildMode.Tool.SCANNER, BuildMode.Tool.ARCH],
	PLACE_GATE_DESK: [BuildMode.Tool.GATE_DESK],
	PLACE_SEATS: [BuildMode.Tool.SEATS],
	SECOND_HIRE: [STAFF_CARD],
	TOILET: [BuildMode.Tool.TOILET_ROOM],
	FOOD:
	[
		BuildMode.Tool.CAFE_ROOM,
		BuildMode.Tool.BAR_ROOM,
		BuildMode.Tool.RESTAURANT_ROOM,
		BuildMode.Tool.STALL_ROOM,
	],
	BAGGAGE_CONNECT: [BuildMode.Tool.BAG_ROOM, BuildMode.Tool.BELT],
	FOLLOW_PASSENGER: [],
}


## The hint's sentence in the player's words. TEXT holds the English msgids
## (Words.msgids() has the same ones inside tr() for POT generation).
static func text(id: StringName) -> String:
	return TranslationServer.translate(TEXT[id])


static func categories_for(id: StringName) -> Array:
	return CATEGORIES[id]


static func is_startup(id: StringName) -> bool:
	return STARTUP_IDS.has(id)


## The hints whose cause is true in `world`, in IDS order. A cause is a state of
## the world that is true now, never a past event:
## - place_checkin: no desk stands.
## - place_security: a desk stands and there is no scanner and no lane part.
## - place_gate_desk: a desk and a scanner or lane part stand and no gate has a desk.
## - place_seats: a gate has a desk and no seat stands (advice, like the checklist
##   seats line). "gate_desks" and "seats" default to met where a world lacks them.
## - second_hire: a role has a verified shortage (read_world()) that the banner
##   does not already name. The banner's hire line for the same role means the
##   same thing, so its role is left out (meaning, not text).
## - toilet / food: a passenger needs one and no usable stall / cafe exists.
## - follow_passenger: a passenger is in the terminal and none is selected
##   ("follow_ready" and "followed", FollowInvite.read(); both default to false
##   where a world does not carry them).
static func causes(world: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	if int(world["desks"]) == 0:
		out.append(PLACE_CHECKIN)
	elif int(world["scanners"]) == 0 and int(world["arches"]) == 0:
		out.append(PLACE_SECURITY)
	var gate_desks := int(world.get("gate_desks", 1))
	var checked_in := int(world["desks"]) > 0
	var secured := int(world["scanners"]) > 0 or int(world["arches"]) > 0
	if checked_in and secured and gate_desks == 0:
		out.append(PLACE_GATE_DESK)
	elif gate_desks > 0 and int(world.get("seats", 1)) == 0:
		out.append(PLACE_SEATS)
	for role in world["shortage_roles"]:
		if not (world["hiring_roles"] as Array).has(role):
			out.append(SECOND_HIRE)
			break
	if int(world["stalls"]) == 0 and int(world["max_toilet_need"]) >= ToiletSim.NEED_AT:
		out.append(TOILET)
	if int(world["cafes"]) == 0 and int(world["max_hunger"]) >= CafeSim.HUNGRY_AT:
		out.append(FOOD)
	if int(world.get("bag_rooms", 0)) > 0 and int(world.get("connected_desks", 0)) == 0:
		out.append(BAGGAGE_CONNECT)
	if bool(world.get("follow_ready", false)) and not bool(world.get("followed", false)):
		out.append(FOLLOW_PASSENGER)
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
		"gate_desks": sim.layout.gate_desks.size(),
		"seats": sim.layout.seats.size(),
		"shortage_roles": _shortage_roles(sim),
		"hiring_roles": hiring_roles,
		"max_toilet_need": toilet,
		"max_hunger": hunger if sim.cafes.hunger_enabled else 0,
		"stalls": sim.toilets.layout.stalls.size(),
		"cafes": sim.cafes.layout.cafes.size(),
		"bag_rooms": _bag_room_count(sim.grid),
		"connected_desks": BagRoutes.build(sim.grid).connected_desk_count(),
	}


static func _bag_room_count(grid: BuildGrid) -> int:
	if grid == null:
		return 0
	var count := 0
	for room_id in grid.room_ids():
		var room := grid.get_room(room_id)
		if not room.is_empty() and StringName(room["type"]) == BeltShaper.BAG_ROOM:
			count += 1
	return count


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
	for role: StaffMember.Role in [
		StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY, StaffMember.Role.GATE
	]:
		var open := 0
		for station in staff.stations_of(role):
			if (
				StaffPosts.usable(sim.grid, sim.layout, station)
				and not staff.closures.is_closed(station)
				and not staff.spot_blocked(station)
				and not staff.spot_unreachable(station)
				and staff.staff_at(station) == 0
			):
				open += 1
		if open > _spare(staff, role):
			roles.append(role)
	return roles


## Hired members of `role` not leaving and not yet claimed by a station
## (including overnight off-shift members who return before morning arrivals).
static func _spare(staff: StaffSim, role: StaffMember.Role) -> int:
	var spare := 0
	for id in staff.member_ids():
		var m := staff.get_member(id)
		if m.role != role or m.leaving:
			continue
		if (
			m.state == StaffMember.State.IDLE
			or m.state == StaffMember.State.OFF_SHIFT
			or m.state == StaffMember.State.LEAVING_SHIFT
		):
			spare += 1
	return spare


## The hint sentences inside tr(), for POT generation; a test checks they match TEXT.
class Words:
	extends RefCounted

	func msgids() -> PackedStringArray:
		return PackedStringArray(
			[
				tr(
					"Passengers need a check-in desk. Each desk also needs a hired agent: open Staff on the bar."
				),
				tr(
					# gdlint:ignore = max-line-length
					"Passengers need security after check-in. Place a scanner or build a lane, and hire an officer."
				),
				tr(
					"Passengers board at a gate. Place a gate desk by an exit that faces the planes."
				),
				tr(
					"Passengers wait at the gate. Place seats near it; the airport opens without them."
				),
				tr("One agent works one desk or scanner. Hire another on the Staff card."),
				tr("Passengers need a toilet. Build a toilet room and put a stall in it."),
				tr("Hungry passengers need food. Build a cafe with a counter and a table."),
				tr("Drag a belt from the back of a check-in desk into your Bag Room."),
				tr("Click a passenger to follow them to their flight"),
			]
		)
