class_name BigFirsts
extends RefCounted
## The big moments that get the phone ring and the short dialog the first time
## they happen in a game, besides a new unlock tier (decision phone-ring-and-
## help-dialog-also-on-big-firsts-first-runway-u): the first runway upgrade and
## the first major incident. Each has one line of words; UnlockGuide shows them
## and BuildUnlocks keeps which have shown, in the save.

const RUNWAY := "runway"
const INCIDENT := "incident"
## Every kind, in the order a dialog lists them.
const KINDS: Array[String] = [RUNWAY, INCIDENT]

const TITLE_TEXT := "Big news at the airport"
const FOOTER_TEXT := "The clock goes on when you close this."
const LINES := {
	RUNWAY:
	"The runway works are done. Bigger planes can land now, so Offers can bring them flights.",
	INCIDENT: "A big event has come up. Its notice says what it is and what you can do about it.",
}


static func is_kind(kind: String) -> bool:
	return KINDS.has(kind)


## The dialog's text for the listed kinds: one line each, then the note about
## the clock.
static func body_for(kinds: Array) -> String:
	var lines: Array[String] = []
	for kind: String in KINDS:
		if kinds.has(kind):
			lines.append(LINES[kind])
	return "\n".join(lines) + "\n" + FOOTER_TEXT
