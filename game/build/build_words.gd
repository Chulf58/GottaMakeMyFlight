class_name BuildWords
extends RefCounted
## The player's words for what the build tools refuse and say (decision
## translation-format-po-gettext-files-with-tr-and-tr-n-for-all). The English
## stays as data (BuildResult.REASON_TEXT, GhostReason.SHORT_TEXT,
## SecurityLanes.STATUS_TEXT, the BuildMode status constants) because tests and
## the card logic key on it; the screens call these helpers at the moment they
## set text, never the data direct.
##
## Static code cannot call tr() (an Object method), so each helper translates
## through TranslationServer with a context and Words.msgids() lists every
## English msgid inside tr(), which POT generation reads. test_build_words.gd
## checks the list holds every string the data can produce. A translated string
## is never case-transformed: a word inside a sentence is its own msgid.

const REFUSAL_CONTEXT := "build refusal"
const SHORT_CONTEXT := "ghost reason"
const LANE_CONTEXT := "lane status"
const STATUS_CONTEXT := "build status"
const DOOR_CONTEXT := "door tool, mid-sentence"

static var _words := Words.new()


## A BuildResult.REASON_TEXT line in the player's words.
static func refusal(english: String) -> String:
	return TranslationServer.translate(english, REFUSAL_CONTEXT)


## A GhostReason.SHORT_TEXT line in the player's words.
static func short_refusal(english: String) -> String:
	return TranslationServer.translate(english, SHORT_CONTEXT)


## A SecurityLanes.STATUS_TEXT line in the player's words.
static func lane_status(english: String) -> String:
	return TranslationServer.translate(english, LANE_CONTEXT)


## A BuildMode status constant (BELT_HINT, NOT_IN_LANE, FRONT_OUTSIDE_ROOM,
## DRAG_OVER_UI) in the player's words.
static func status(english: String) -> String:
	return TranslationServer.translate(english, STATUS_CONTEXT)


## What the status line tells the player to do when the door tool `door`
## ("entrance" or "exit", BuildMode.DOOR_NAMES) is refused for `reason`, or ""
## for a reason with no hint (BuildMode.DOOR_HINTS).
static func door_hint(reason: BuildResult.Reason, door: String) -> String:
	return _words.door_hint(reason, TranslationServer.translate(door, DOOR_CONTEXT))


## The ghost card's line for a door blocked by `blocker`, one whole sentence.
static func in_front(blocker: String) -> String:
	return _words.in_front(blocker)


## Every English msgid, for the test that checks the list against the data.
static func msgids() -> Array[String]:
	return _words.msgids()


class Words:
	extends RefCounted

	func door_hint(reason: BuildResult.Reason, door: String) -> String:
		var text := ""
		match reason:
			BuildResult.Reason.NO_FLOOR:
				text = tr("Put the {door} on a floor tile at the outside edge", "door hint")
			BuildResult.Reason.DOOR_NOT_ON_EDGE:
				text = tr("Put the {door} on the outside edge of the floor", "door hint")
			BuildResult.Reason.INTERACTION_BLOCKED:
				text = tr("Clear the floor in front of the {door}", "door hint")
			BuildResult.Reason.DOOR_WALLED:
				text = tr("Take down the glass or door wall behind the {door}", "door hint")
			BuildResult.Reason.WALL_HOLDS_DOOR:
				text = tr("The wall behind the {door} holds a door; pick another spot", "door hint")
		return text.format({"door": door})

	func in_front(blocker: String) -> String:
		return tr("{blocker} in front", "ghost reason").format({"blocker": blocker})

	## Never called: every English line the data can produce inside tr(), so POT
	## generation finds it. test_build_words.gd checks the list against the data.
	func msgids() -> Array[String]:
		return [
			# BuildResult.REASON_TEXT
			tr("Outside the building area", "build refusal"),
			tr("Needs floor", "build refusal"),
			tr("Unknown floor type", "build refusal"),
			tr("Zone id must be 0 or more", "build refusal"),
			tr("Facing must be 0 to 3", "build refusal"),
			tr("Unknown object", "build refusal"),
			tr("Overlaps another object", "build refusal"),
			tr("A wall runs through it", "build refusal"),
			tr("The spot in front is blocked", "build refusal"),
			tr("Blocks the spot in front of another object", "build refusal"),
			tr("An object stands here", "build refusal"),
			tr("There is already a wall here", "build refusal"),
			tr("No wall here", "build refusal"),
			tr("No such object", "build refusal"),
			tr("Unknown wall kind", "build refusal"),
			tr("A door needs a plain wall on each side", "build refusal"),
			tr("A door stands beside this wall", "build refusal"),
			tr(
				"Entrances and exits need the outside edge, with no floor behind them",
				"build refusal"
			),
			tr("Keep the edge behind an entrance or exit open", "build refusal"),
			tr("Unknown room type", "build refusal"),
			tr("Overlaps another room", "build refusal"),
			tr("A room covers this floor; remove the room first", "build refusal"),
			tr("No such room", "build refusal"),
			tr("Not enough money", "build refusal"),
			tr("This piece has no price", "build refusal"),
			tr("The money is at its limit; the refund would not fit", "build refusal"),
			tr("Belts cannot cross; a belt joins at most three others", "build refusal"),
			tr("A wall is in the way of the belt", "build refusal"),
			tr("Only a belt piece changes shape", "build refusal"),
			tr(
				# gdlint:ignore = max-line-length
				"Keep the staff spot behind a desk, beside a scanner or at a lane officer's post free, with a way in",
				"build refusal"
			),
			tr("A wall is in the way of the lane. Remove the wall first", "build refusal"),
			tr("Put it on one of the marked landside spots", "build refusal"),
			tr("Every spot of this kind nearby is already built", "build refusal"),
			tr("Cars are still in it. Close it and wait until it is empty", "build refusal"),
			tr("A wall is in the way of the room", "build refusal"),
			tr("A plane uses this apron. Build here after it takes off", "build refusal"),
			tr("You do not own this land. Buy the plot with Buy land first", "build refusal"),
			tr("You already own this plot", "build refusal"),
			tr("Buy a plot next to land you own", "build refusal"),
			tr("Put a gate desk within 4 cells of a free exit facing the planes", "build refusal"),
			tr(
				"A flight is still due at this gate. Remove it after the flight leaves",
				"build refusal"
			),
			tr(
				"No other gate is free for these flights. Move them in Departures first",
				"build refusal"
			),
			tr("Something is in front of the door", "build refusal"),
			tr("A piece sits across the room's edge", "build refusal"),
			tr("Desks, scanners and lane parts cannot move with a room", "build refusal"),
			tr("A piece does not fit at the new spot", "build refusal"),
			tr("Keep the way out clear for the passengers leaving the room", "build refusal"),
			tr("The room changed since it was picked up. Pick it up again", "build refusal"),
			tr("Not unlocked yet", "build refusal"),
			tr(
				"No room for a plane outside this exit. Keep the ground out from it clear",
				"build refusal"
			),
			tr(
				"Something blocks the way from this exit to the taxi lane. Clear a path out from it",
				"build refusal"
			),
			tr(
				"A booked flight's plane needs this ground. Move its flights in Departures first",
				"build refusal"
			),
			tr(
				"The side taxiway would have to move and leave a booked flight with no way to its gate",
				"build refusal"
			),
			# GhostReason.SHORT_TEXT
			tr("Outside the building", "ghost reason"),
			tr("Overlaps an object", "ghost reason"),
			tr("A wall is in the way", "ghost reason"),
			tr("Front spot blocked", "ghost reason"),
			tr("Blocks a front spot", "ghost reason"),
			tr("Wall already here", "ghost reason"),
			tr("Needs wall on both sides", "ghost reason"),
			tr("A door is beside it", "ghost reason"),
			tr("Needs the outside edge", "ghost reason"),
			tr("Keep the edge open", "ghost reason"),
			tr("Overlaps a room", "ghost reason"),
			tr("Remove the room first", "ghost reason"),
			tr("Money at its limit", "ghost reason"),
			tr("Belts cannot cross", "ghost reason"),
			tr("Keep the staff spot free", "ghost reason"),
			tr("A wall is in the lane", "ghost reason"),
			tr("Bad zone id", "ghost reason"),
			tr("Only belts change shape", "ghost reason"),
			tr("Needs a marked spot", "ghost reason"),
			tr("Spot already built", "ghost reason"),
			tr("Cars are still in it", "ghost reason"),
			tr("A plane is on the apron", "ghost reason"),
			tr("Buy this land first", "ghost reason"),
			tr("Plot already owned", "ghost reason"),
			tr("Not next to your land", "ghost reason"),
			tr("No free exit nearby", "ghost reason"),
			tr("Gates are too close", "ghost reason"),
			tr("A flight is due here", "ghost reason"),
			tr("Flights have no gate", "ghost reason"),
			tr("A piece is on the edge", "ghost reason"),
			tr("A piece cannot move", "ghost reason"),
			tr("A piece does not fit", "ghost reason"),
			tr("Blocks a way out", "ghost reason"),
			tr("The room changed", "ghost reason"),
			tr("No room for the plane", "ghost reason"),
			tr("Way to the lane blocked", "ghost reason"),
			tr("A booked plane needs it", "ghost reason"),
			tr("Strands a booked flight", "ghost reason"),
			# SecurityLanes.STATUS_TEXT
			tr("Lane ready", "lane status"),
			tr("Needs a tray table", "lane status"),
			tr("Needs an X-ray belt", "lane status"),
			tr("Needs a pickup table", "lane status"),
			tr("Parts face different ways", "lane status"),
			tr("A wall cuts through the lane", "lane status"),
			tr("Clear the way through the arch", "lane status"),
			tr("Clear the floor for the queue", "lane status"),
			tr("Clear the floor for the repack spot", "lane status"),
			tr("Clear the way back from the repack spot", "lane status"),
			tr("Clear the way out past the pickup table", "lane status"),
			tr("Clear the officer's spot by the X-ray belt", "lane status"),
			tr("Clear the helper's spot by the repack spot", "lane status"),
			tr("No arch", "lane status"),
			# BuildMode status constants
			tr("Drag to lay a belt", "build status"),
			tr("Not part of a lane", "build status"),
			tr("Its front is outside the room, so it will not count", "build status"),
			tr("Drag stops over the menu. Move back onto the floor to keep sizing", "build status"),
			# Door tool names, inside a sentence
			tr("entrance", "door tool, mid-sentence"),
			tr("exit", "door tool, mid-sentence"),
		]
