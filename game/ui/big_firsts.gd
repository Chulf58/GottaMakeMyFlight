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

## The words are built in static functions, which cannot call tr() (an Object
## method), so they go through this instance's tr().
static var _translator := RefCounted.new()


static func is_kind(kind: String) -> bool:
	return KINDS.has(kind)


## The dialog's title.
static func title_text() -> String:
	return _translator.tr("Big news at the airport")


## The line of words for the big first `kind`.
static func line_for(kind: String) -> String:
	match kind:
		RUNWAY:
			return (
				_translator
				. tr(
					"The runway works are done. Bigger planes can land now, so Offers can bring them flights."
				)
			)
		INCIDENT:
			return _translator.tr(
				"A big event has come up. Its notice says what it is and what you can do about it."
			)
	return ""


## The dialog's text for the listed kinds: one line each, then the note about
## the clock.
static func body_for(kinds: Array) -> String:
	var lines: Array[String] = []
	for kind: String in KINDS:
		if kinds.has(kind):
			lines.append(line_for(kind))
	return "\n".join(lines) + "\n" + _translator.tr("The clock goes on when you close this.")
