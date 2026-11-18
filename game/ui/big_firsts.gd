class_name BigFirsts
extends RefCounted
## The big moments that get the phone ring and the short dialog the first time
## they happen in a game, besides a new unlock tier (decisions phone-ring-and-
## help-dialog-also-on-big-firsts-first-runway-u and opening-phone-call-right-
## after-the-airport-opens-the-airline): the airline's opening call when the
## airport first opens, the first runway upgrade, and the first major incident.
## UnlockGuide shows them and BuildUnlocks keeps which have shown, in the save.

const OPENING := "opening"
const RUNWAY := "runway"
const INCIDENT := "incident"
## Every kind, in the order a dialog lists them.
const KINDS: Array[String] = [OPENING, RUNWAY, INCIDENT]

## The words are built in static functions, which cannot call tr() (an Object
## method), so they go through this instance's tr().
static var _translator := RefCounted.new()


static func is_kind(kind: String) -> bool:
	return KINDS.has(kind)


## The Terminal Manager's dialog title for airport-side firsts.
static func title_text() -> String:
	return _translator.tr("Big news at the airport")


## Gotta Air's nameplate subtitle for the opening call.
static func opening_title_text() -> String:
	return _translator.tr("Station manager")


## The words for the big first `kind`; `departure_time` fills OPENING's flight
## time (for example "08:13").
static func line_for(kind: String, departure_time := "") -> String:
	match kind:
		OPENING:
			return (
				"\n"
				. join(
					PackedStringArray(
						[
							(
								_translator
								. tr(
									# gdlint:ignore = max-line-length
									"Gotta Air here. Welcome, your airport is open, and I hear it is the only one with a dent in the carpet."
								)
							),
							(
								_translator
								. tr(
									# gdlint:ignore = max-line-length
									"Our first flight to Oslo leaves at {departure_time}. It is a small plane, so please keep the luggage small too."
								)
								. format({"departure_time": departure_time})
							),
							_translator.tr("Your first passengers are on their way in now."),
							_translator.tr("Good luck. Gotta make that flight!"),
						]
					)
				)
			)
		RUNWAY:
			return (
				_translator
				. tr(
					# gdlint:ignore = max-line-length
					"The runway works are done. Bigger planes can land now, so Offers can bring them flights."
				)
			)
		INCIDENT:
			return (
				_translator
				. tr(
					# gdlint:ignore = max-line-length
					"A big event has come up. Its notice says what it is and what you can do about it."
				)
			)
	return ""


## The dialog's text for the listed kinds: each kind's lines, then the note
## about the clock.
static func body_for(kinds: Array, departure_time := "") -> String:
	var lines: Array[String] = []
	for kind: String in KINDS:
		if kinds.has(kind):
			lines.append(line_for(kind, departure_time))
	return "\n".join(lines) + "\n" + _translator.tr("The clock goes on when you close this.")
