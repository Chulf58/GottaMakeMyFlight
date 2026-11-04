class_name Checklist
extends RefCounted
## The lines of the checklist card (decision checklist-card-shows-what-the-
## airport-still-needs): what the airport still needs to open, each line ticking
## off when done, and once it is open the current gaps instead. Pure rules over
## AirportGate.unmet() and a few counts, so StaffPanel and the tests share one
## definition of each line. A line is {"text": String, "done": bool}.
##
## The opening lines follow the build order: the entrance (ticked by the path
## test, RepairPlan.has_working_path, the same check that opens the airport),
## check-in, security, the gate desk and seats. Seats are advice only (decision
## checklist-card-seats-line-is-advice-not-an-opening-blocker-s): the line ticks
## when a seat stands, but the airport opens without one. The staff spot line
## shows only while it keeps the airport closed. A check-in or security line
## that is not done says what to do next: place the station, open one the
## player closed, hire on Staff, or wait for the member on the way.

const BLOCKER := AirportGate.Blocker
const TITLE_CLOSED := "To open the airport"
const TITLE_OPEN := "Your airport needs"

const ENTRANCE := "Entrance with a way through check-in and security to an exit"
const STAFF_SPOT := "Staff can't reach a desk or scanner passengers need: clear its staff spot"
const CHECKIN := "Check-in desk and an agent"
const SECURITY := "Security scanner and an officer"
const GATE := "Gate desk by an exit that faces the planes"
const SEATS := "Seats near the gate"
## What a not-done check-in line (key "checkin") or security line ("security")
## adds after a colon, by what is missing.
const NEXT := {
	"checkin":
	{
		"place": "place a desk",
		"closed": "you closed every desk, open one again",
		"hire": "hire an agent on Staff",
		"walking": "the agent is on the way",
	},
	"security":
	{
		"place": "place a scanner",
		"closed": "you closed every scanner and lane, open one again",
		"hire": "hire an officer on Staff",
		"walking": "the officer is on the way",
	},
}

## The gap lines after opening, by HintRules cause, and the seats gap.
const GAPS := {
	HintRules.PLACE_CHECKIN: "Passengers need a check-in desk: place one",
	HintRules.PLACE_SECURITY: "Passengers need security: place a scanner",
	HintRules.SECOND_HIRE: "A desk or scanner has nobody at it: hire another on Staff",
	HintRules.TOILET: "Passengers need a toilet: build a toilet room with a stall",
	HintRules.FOOD: "Passengers are hungry: build a cafe",
}
const NO_SEATS := "Passengers have nowhere to sit: place seats near the gate"
## The build tool each gap line asks for, so a locked one says so.
const GAP_TOOLS := {
	HintRules.PLACE_CHECKIN: BuildMode.Tool.DESK,
	HintRules.PLACE_SECURITY: BuildMode.Tool.SCANNER,
	HintRules.TOILET: BuildMode.Tool.TOILET_ROOM,
	HintRules.FOOD: BuildMode.Tool.CAFE_ROOM,
}


static func line(text: String, done: bool) -> Dictionary:
	return {"text": text, "done": done}


## The opening lines while the airport is closed. `unmet` is AirportGate.unmet().
## `counts` has "desks", "scanners", "seats" (TerminalLayout sizes) and
## "checkin_staying", "security_staying" (hired members not leaving).
static func opening_lines(unmet: Array, counts: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append(line(ENTRANCE, not unmet.has(BLOCKER.NO_PATH)))
	if unmet.has(BLOCKER.STAFF_SPOT):
		out.append(line(STAFF_SPOT, false))
	out.append(
		_station_line(
			CHECKIN,
			"checkin",
			_station_state(
				unmet,
				BLOCKER.NO_CHECKIN,
				BLOCKER.CHECKIN_CLOSED,
				counts,
				"desks",
				"checkin_staying"
			)
		)
	)
	out.append(
		_station_line(
			SECURITY,
			"security",
			_station_state(
				unmet,
				BLOCKER.NO_SECURITY,
				BLOCKER.SECURITY_CLOSED,
				counts,
				"scanners",
				"security_staying"
			)
		)
	)
	out.append(line(GATE, not unmet.has(BLOCKER.NO_GATE)))
	out.append(line(SEATS, int(counts["seats"]) > 0))
	return out


## The gap lines once the airport is open, from HintRules.causes(`world`)
## (HintRules.read_world()). `lock_texts` maps a build tool to why it cannot be
## picked yet ("" or absent when it can), so a gap whose tool is locked names
## the unlock instead of asking for something the player cannot build.
static func gap_lines(world: Dictionary, seats: int, lock_texts: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cause in HintRules.causes(world):
		var text: String = GAPS[cause]
		var locked: String = lock_texts.get(GAP_TOOLS.get(cause, BuildMode.Tool.NONE), "")
		if locked != "":
			text = "%s (%s)" % [text.get_slice(":", 0), locked]
		out.append(line(text, false))
	if seats == 0:
		out.append(line(NO_SEATS, false))
	return out


## "" when the station line is done, else a NEXT key.
static func _station_state(
	unmet: Array, missing: int, closed: int, counts: Dictionary, stations: String, staying: String
) -> String:
	if unmet.has(closed):
		return "closed"
	if not unmet.has(missing):
		return ""
	if int(counts[stations]) == 0:
		return "place"
	return "hire" if int(counts[staying]) == 0 else "walking"


static func _station_line(text: String, key: String, state: String) -> Dictionary:
	if state == "":
		return line(text, true)
	return line("%s: %s" % [text, NEXT[key][state]], false)
