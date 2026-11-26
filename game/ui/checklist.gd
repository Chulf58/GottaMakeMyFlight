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
const GATE := "Place Gate Desk (Operations)"
const GATE_AGENT := "Gate desk and an agent"
const SEATS := "Place Seats near the gate (Operations)"
## What a not-done check-in line (key "checkin") or security line ("security")
## says, by what is missing.
const NEXT := {
	"checkin":
	{
		"place": "Place Check-in (Operations)",
		"closed": "Open a closed Check-in desk",
		"hire": "Hire Check-in agent (Staff)",
		"walking": "Check-in agent on the way",
	},
	"security":
	{
		"place": "Place Security (Operations)",
		"closed": "Open a closed Security scanner or lane",
		"hire": "Hire Security officer (Staff)",
		"walking": "Security officer on the way",
	},
	"gate":
	{
		"hire": "Hire Gate agent (Staff)",
		"walking": "Gate agent on the way",
	},
}

## The gap lines after opening, by HintRules cause, and the seats gap.
const GAPS := {
	HintRules.PLACE_CHECKIN: "Place Check-in (Operations)",
	HintRules.PLACE_SECURITY: "Place Security (Operations)",
	HintRules.SECOND_HIRE: "Station unstaffed: hire staff (Staff)",
	HintRules.TOILET: "Passengers need a toilet: build Toilet room (Facilities)",
	HintRules.FOOD: "Passengers are hungry: build Cafe (Food & Drink)",
	HintRules.CLEANERS: "Messes need cleaning: hire a cleaner (Staff)",
}
const NO_SEATS := "Place Seats near the gate (Operations)"
## The build tool each gap line asks for, so a locked one says so.
const GAP_TOOLS := {
	HintRules.PLACE_CHECKIN: BuildMode.Tool.DESK,
	HintRules.PLACE_SECURITY: BuildMode.Tool.SCANNER,
	HintRules.TOILET: BuildMode.Tool.TOILET_ROOM,
	HintRules.FOOD: BuildMode.Tool.CAFE_ROOM,
}


static func line(text: String, done: bool, why := "", action := {}) -> Dictionary:
	return {
		"text": text,
		"done": done,
		"why": "" if done else why,
		"action": {} if done else action,
	}


## The opening lines while the airport is closed. `unmet` is AirportGate.unmet().
## `counts` has "entrances", "desks", "scanners", "exits", "seats" and
## "checkin_staying", "security_staying", "gate_staying".
static func opening_lines(unmet: Array, counts: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append(_path_line(unmet, counts))
	if unmet.has(BLOCKER.STAFF_SPOT):
		out.append(
			line(
				TranslationServer.translate(
					"Staff can't reach a desk or scanner passengers need: clear its staff spot"
				),
				false,
				TranslationServer.translate(
					"Staff need a clear tile behind each station to work it."
				)
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
	if unmet.has(BLOCKER.NO_GATE_AGENT) and not unmet.has(BLOCKER.NO_GATE):
		var walking := int(counts.get("gate_staying", 0)) > 0
		var msg := (
			TranslationServer.translate("Gate agent on the way")
			if walking
			else TranslationServer.translate("Hire Gate agent (Staff)")
		)
		var gate_why := (
			TranslationServer.translate("The airport opens once staff reach their stations.")
			if walking
			else TranslationServer.translate("Gate desks stay closed until an agent is hired.")
		)
		var action := {} if walking else {"kind": "staff", "role": StaffMember.Role.GATE}
		out.append(line(msg, false, gate_why, action))
	else:
		out.append(
			line(
				TranslationServer.translate("Place Gate Desk (Operations)"),
				not unmet.has(BLOCKER.NO_GATE),
				TranslationServer.translate("Opens boarding for your first flight."),
				{"kind": "tool", "tool": BuildMode.Tool.GATE_DESK}
			)
		)
	out.append(
		line(
			TranslationServer.translate("Place Seats near the gate (Operations)"),
			int(counts["seats"]) > 0,
			TranslationServer.translate("Keeps waiting passengers comfortable."),
			{"kind": "tool", "tool": BuildMode.Tool.SEATS}
		)
	)
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
		var tool: BuildMode.Tool = GAP_TOOLS.get(cause, BuildMode.Tool.NONE)
		var locked: String = lock_texts.get(tool, "")
		var why := _gap_why(cause)
		var action := _gap_action(cause, locked != "")
		if locked != "":
			var need := TranslationServer.translate("{need} ({unlock})")
			out.append(
				line(need.format({"need": _gap_need(cause), "unlock": locked}), false, why, action)
			)
		else:
			out.append(line(_gap_text(cause), false, why, action))
	if seats == 0:
		out.append(
			line(
				TranslationServer.translate("Place Seats near the gate (Operations)"),
				false,
				TranslationServer.translate("Keeps waiting passengers comfortable."),
				{"kind": "tool", "tool": BuildMode.Tool.SEATS}
			)
		)
	return out


## Diagnoses which leg is missing when NO_PATH blocks opening so the checklist
## names and highlights the missing piece (or FLOOR when all 4 exist but are disconnected).
static func _path_line(unmet: Array, counts: Dictionary) -> Dictionary:
	if not unmet.has(BLOCKER.NO_PATH):
		return line(
			TranslationServer.translate(
				"Entrance with a way through check-in and security to an exit"
			),
			true
		)
	if int(counts.get("entrances", 0)) == 0:
		return line(
			TranslationServer.translate("Place an entrance door"),
			false,
			TranslationServer.translate(
				"Passengers walk from the entrance through security to the exit."
			),
			{"kind": "tool", "tool": BuildMode.Tool.ENTRANCE}
		)
	if int(counts.get("desks", 0)) == 0:
		return line(
			TranslationServer.translate("Place a check-in desk"),
			false,
			TranslationServer.translate("Passengers check in here before security."),
			{"kind": "tool", "tool": BuildMode.Tool.DESK}
		)
	if int(counts.get("scanners", 0)) == 0:
		return line(
			TranslationServer.translate("Place a security scanner"),
			false,
			TranslationServer.translate("Clears passengers and bags for the gate."),
			{"kind": "tool", "tool": BuildMode.Tool.SCANNER}
		)
	if int(counts.get("exits", 0)) == 0:
		return line(
			TranslationServer.translate("Place an airside exit door"),
			false,
			TranslationServer.translate("Passengers board planes through an airside exit."),
			{"kind": "tool", "tool": BuildMode.Tool.EXIT}
		)
	return line(
		TranslationServer.translate(
			"Connect entrance, check-in, security and exit with open floor"
		),
		false,
		TranslationServer.translate(
			"Passengers walk from the entrance through security to the exit."
		),
		{"kind": "tool", "tool": BuildMode.Tool.FLOOR}
	)


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
	return line(
		_station_text(key, state),
		state == "",
		_station_why(key, state),
		_station_action(key, state)
	)


static func _station_why(key: String, state: String) -> String:
	if state == "":
		return ""
	if key == "checkin":
		match state:
			"place":
				return TranslationServer.translate("Passengers check in here before security.")
			"closed":
				return TranslationServer.translate("Closed desks cannot serve waiting passengers.")
			"hire":
				return TranslationServer.translate("Stations stay closed until an agent is hired.")
			"walking":
				return TranslationServer.translate(
					"The airport opens once staff reach their stations."
				)
	match state:
		"place":
			return TranslationServer.translate("Clears passengers and bags for the gate.")
		"closed":
			return TranslationServer.translate("Closed security lanes cannot clear passengers.")
		"hire":
			return TranslationServer.translate("Stations stay closed until an officer is hired.")
		"walking":
			return TranslationServer.translate("The airport opens once staff reach their stations.")
	return ""


static func _station_action(key: String, state: String) -> Dictionary:
	if state == "place":
		return {
			"kind": "tool",
			"tool": BuildMode.Tool.DESK if key == "checkin" else BuildMode.Tool.SCANNER,
		}
	if state == "hire":
		return {
			"kind": "staff",
			"role": StaffMember.Role.CHECKIN if key == "checkin" else StaffMember.Role.SECURITY,
		}
	return {}


## The full line of a station: "" is its done form, else a NEXT key. One msgid
## per line, so a translation can order the words as its language needs.
static func _station_text(key: String, state: String) -> String:
	if key == "checkin":
		match state:
			"place":
				return TranslationServer.translate("Place Check-in (Operations)")
			"closed":
				return TranslationServer.translate("Open a closed Check-in desk")
			"hire":
				return TranslationServer.translate("Hire Check-in agent (Staff)")
			"walking":
				return TranslationServer.translate("Check-in agent on the way")
		return TranslationServer.translate("Check-in desk and an agent")
	match state:
		"place":
			return TranslationServer.translate("Place Security (Operations)")
		"closed":
			return TranslationServer.translate("Open a closed Security scanner or lane")
		"hire":
			return TranslationServer.translate("Hire Security officer (Staff)")
		"walking":
			return TranslationServer.translate("Security officer on the way")
	return TranslationServer.translate("Security scanner and an officer")


## The gap line for a HintRules cause (see GAPS).
static func _gap_text(cause: StringName) -> String:
	match cause:
		HintRules.PLACE_CHECKIN:
			return TranslationServer.translate("Place Check-in (Operations)")
		HintRules.PLACE_SECURITY:
			return TranslationServer.translate("Place Security (Operations)")
		HintRules.SECOND_HIRE:
			return TranslationServer.translate("Station unstaffed: hire staff (Staff)")
		HintRules.TOILET:
			return TranslationServer.translate(
				"Passengers need a toilet: build Toilet room (Facilities)"
			)
		HintRules.CLEANERS:
			return TranslationServer.translate("Messes need cleaning: hire a cleaner (Staff)")
	return TranslationServer.translate("Passengers are hungry: build Cafe (Food & Drink)")


static func _gap_why(cause: StringName) -> String:
	match cause:
		HintRules.PLACE_CHECKIN:
			return TranslationServer.translate("Passengers check in here before security.")
		HintRules.PLACE_SECURITY:
			return TranslationServer.translate("Clears passengers and bags for the gate.")
		HintRules.SECOND_HIRE:
			return TranslationServer.translate("Each extra station needs its own staff member.")
		HintRules.TOILET:
			return TranslationServer.translate("Prevents comfort drops while passengers wait.")
		HintRules.CLEANERS:
			return TranslationServer.translate(
				"Cleaners mop messes and empty bins so passenger mood stays up."
			)
	return TranslationServer.translate("Hungry passengers lose mood before boarding.")


static func _gap_action(cause: StringName, is_locked: bool) -> Dictionary:
	if cause == HintRules.SECOND_HIRE:
		return {"kind": "staff"}
	if cause == HintRules.CLEANERS:
		return {"kind": "staff", "role": StaffMember.Role.CLEANER}
	if is_locked:
		return {}
	var tool: BuildMode.Tool = GAP_TOOLS.get(cause, BuildMode.Tool.NONE)
	return {"kind": "tool", "tool": tool} if tool != BuildMode.Tool.NONE else {}


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
