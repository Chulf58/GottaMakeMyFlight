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

## The English msgids of the card's lines. Tests compare against them; the
## lines themselves go through TranslationServer.translate() with the same
## literal, because this class is static and has no tr(), and the POT extractor
## reads only literals. Change a text here and in its translate() call together.
const BLOCKER := AirportGate.Blocker
const TITLE_CLOSED := "To open the airport"
const TITLE_OPEN := "Your airport needs"
## The title while every opening line is done but the airport has not opened yet: it
## opens on the next tick, so a paused clock holds this state.
const TITLE_READY := "Ready: the airport opens on the next tick"

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
	out.append(
		line(
			TranslationServer.translate(
				"Entrance with a way through check-in and security to an exit"
			),
			not unmet.has(BLOCKER.NO_PATH)
		)
	)
	if unmet.has(BLOCKER.STAFF_SPOT):
		out.append(
			line(
				TranslationServer.translate(
					"Staff can't reach a desk or scanner passengers need: clear its staff spot"
				),
				false
			)
		)
	out.append(
		_station_line(
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
	out.append(
		line(
			TranslationServer.translate("Gate desk by an exit that faces the planes"),
			not unmet.has(BLOCKER.NO_GATE)
		)
	)
	out.append(line(TranslationServer.translate("Seats near the gate"), int(counts["seats"]) > 0))
	return out


## The gap lines once the airport is open, from HintRules.causes(`world`)
## (HintRules.read_world()). `lock_texts` maps a build tool to why it cannot be
## picked yet ("" or absent when it can), so a gap whose tool is locked names
## the unlock instead of asking for something the player cannot build.
static func gap_lines(world: Dictionary, seats: int, lock_texts: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cause in HintRules.causes(world):
		# The gate desk and seats hints have no gap line: the opening lines and
		# the seats gap below cover them.
		if not GAPS.has(cause):
			continue
		var locked: String = lock_texts.get(GAP_TOOLS.get(cause, BuildMode.Tool.NONE), "")
		if locked != "":
			var need := TranslationServer.translate("{need} ({unlock})")
			out.append(line(need.format({"need": _gap_need(cause), "unlock": locked}), false))
		else:
			out.append(line(_gap_text(cause), false))
	if seats == 0:
		out.append(
			line(
				TranslationServer.translate(
					"Passengers have nowhere to sit: place seats near the gate"
				),
				false
			)
		)
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


static func _station_line(key: String, state: String) -> Dictionary:
	return line(_station_text(key, state), state == "")


## The full line of a station: "" is its done form, else a NEXT key. One msgid
## per line, so a translation can order the words as its language needs.
static func _station_text(key: String, state: String) -> String:
	if key == "checkin":
		match state:
			"place":
				return TranslationServer.translate("Check-in desk and an agent: place a desk")
			"closed":
				return TranslationServer.translate(
					"Check-in desk and an agent: you closed every desk, open one again"
				)
			"hire":
				return TranslationServer.translate(
					"Check-in desk and an agent: hire an agent on Staff"
				)
			"walking":
				return TranslationServer.translate(
					"Check-in desk and an agent: the agent is on the way"
				)
		return TranslationServer.translate("Check-in desk and an agent")
	match state:
		"place":
			return TranslationServer.translate("Security scanner and an officer: place a scanner")
		"closed":
			return TranslationServer.translate(
				"Security scanner and an officer: you closed every scanner and lane, open one again"
			)
		"hire":
			return TranslationServer.translate(
				"Security scanner and an officer: hire an officer on Staff"
			)
		"walking":
			return TranslationServer.translate(
				"Security scanner and an officer: the officer is on the way"
			)
	return TranslationServer.translate("Security scanner and an officer")


## The gap line for a HintRules cause (see GAPS).
static func _gap_text(cause: StringName) -> String:
	match cause:
		HintRules.PLACE_CHECKIN:
			return TranslationServer.translate("Passengers need a check-in desk: place one")
		HintRules.PLACE_SECURITY:
			return TranslationServer.translate("Passengers need security: place a scanner")
		HintRules.SECOND_HIRE:
			return TranslationServer.translate(
				"A desk or scanner has nobody at it: hire another on Staff"
			)
		HintRules.TOILET:
			return TranslationServer.translate(
				"Passengers need a toilet: build a toilet room with a stall"
			)
	return TranslationServer.translate("Passengers are hungry: build a cafe")


## What a gap line says before its ask, for the causes whose build tool can be
## locked (GAP_TOOLS).
static func _gap_need(cause: StringName) -> String:
	match cause:
		HintRules.PLACE_CHECKIN:
			return TranslationServer.translate("Passengers need a check-in desk")
		HintRules.PLACE_SECURITY:
			return TranslationServer.translate("Passengers need security")
		HintRules.TOILET:
			return TranslationServer.translate("Passengers need a toilet")
	return TranslationServer.translate("Passengers are hungry")
