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
const DETAIL_CONTEXT := "refusal detail"
const ITEM_MID_CONTEXT := "item name, mid-sentence"
const LIST_CONTEXT := "list separator"

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


## What a refusal names beyond its reason (BuildResult.detail), in the player's words.
## The English detail stays the key; detail_args carry the values, so each sentence is
## one msgid. A detail with no arguments, or an unknown reason, is shown as it came.
static func detail(result: BuildResult) -> String:
	var args := result.detail_args
	# The flights of a gate in use, flights stuck or a spur that strands one.
	if args.has("flights"):
		return TranslationServer.translate(", ", LIST_CONTEXT).join(args["flights"])
	match result.reason:
		BuildResult.Reason.GATE_STAND_OVERLAP:
			if args.has("gate"):
				return _words.gate_close(args["gate"])
		BuildResult.Reason.GATE_ROUTE:
			if args.has("gate") and args.has("plane"):
				return _words.gate_plane(args["gate"], args["plane"], result.detail)
		BuildResult.Reason.DOOR_FRONT_BLOCKED:
			return TranslationServer.translate(result.detail, ITEM_MID_CONTEXT)
		BuildResult.Reason.LOCKED:
			if args.has("tier") or args.has("unwired"):
				return BuildUnlocks.lock_words(args)
		BuildResult.Reason.MOVE_NO_FIT:
			if args.has("inner"):
				return (args["inner"] as BuildResult).reason_text()
	return result.detail


## "Belt 7 cells" for the belt being dragged, one whole line with the plural rule.
static func belt_cells(count: int) -> String:
	return _words.belt_cells(count)


## "Facing auto", or "Facing 2", for the piece about to be placed.
static func facing_text(auto: bool, facing: int) -> String:
	return _words.facing(auto, facing)


## "12 x 8", the size of the rectangle being dragged.
static func size_text(width: int, height: int) -> String:
	return _words.area_size(width, height)


## "Cafe 4 x 3": the room tool's drag line, `room` in the player's words.
static func room_size(room: String, width: int, height: int) -> String:
	return _words.room_size(room, width, height)


## "Cafe marked: Needs a counter", `room` and `status` in the player's words.
static func room_marked(room: String, status: String) -> String:
	return _words.room_marked(room, status)


## "Drag to mark a cafe", for the room type whose English name is `room_name`.
static func room_hint(room_name: String) -> String:
	var room := TranslationServer.translate(room_name.to_lower(), DisplayWords.ROOM_MID_CONTEXT)
	return _words.room_hint(room)


## Every English msgid, for the test that checks the list against the data.
static func msgids() -> Array[String]:
	return _words.msgids()


## Every SecurityLanes.STATUS_TEXT line, the one inventory of the lane texts.
static func lane_status_msgids() -> Array[String]:
	return _words.lane_status_msgids()


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

	func gate_close(gate: String) -> String:
		return tr("gate {gate} is too close", "refusal detail").format({"gate": gate})

	## "gate B, a large plane" for a booked class (PlaneClasses), one msgid per class;
	## `english` is the detail as it came, for a class this list does not know.
	func gate_plane(gate: String, plane: String, english: String) -> String:
		var text := ""
		match plane:
			PlaneClasses.SMALL:
				text = tr("gate {gate}, a small plane", "refusal detail")
			PlaneClasses.MEDIUM:
				text = tr("gate {gate}, a medium plane", "refusal detail")
			PlaneClasses.LARGE:
				text = tr("gate {gate}, a large plane", "refusal detail")
			_:
				return english
		return text.format({"gate": gate})

	func belt_cells(count: int) -> String:
		return tr_n("Belt {count} cell", "Belt {count} cells", count, "build status").format(
			{"count": count}
		)

	func facing(auto: bool, facing_value: int) -> String:
		if auto:
			return tr("Facing auto", "build status")
		return tr("Facing {facing}", "build status").format({"facing": facing_value})

	func area_size(width: int, height: int) -> String:
		return tr("{width} x {height}", "build status").format({"width": width, "height": height})

	func room_size(room: String, width: int, height: int) -> String:
		return tr("{room} {width} x {height}", "build status").format(
			{"room": room, "width": width, "height": height}
		)

	func room_marked(room: String, status: String) -> String:
		return tr("{room} marked: {status}", "build status").format(
			{"room": room, "status": status}
		)

	func room_hint(room: String) -> String:
		return tr("Drag to mark a {room}", "build status").format({"room": room})

	func in_front(blocker: String) -> String:
		return tr("{blocker} in front", "ghost reason").format({"blocker": blocker})

	## Never called: every English line the data can produce inside tr(), so POT
	## generation finds it. test_build_words.gd checks the list against the data.
	func msgids() -> Array[String]:
		var out: Array[String] = [
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
			# BuildMode status constants
			tr("Drag to lay a belt", "build status"),
			tr("Not part of a lane", "build status"),
			tr("Its front is outside the room, so it will not count", "build status"),
			tr("Drag stops over the menu. Move back onto the floor to keep sizing", "build status"),
			# Door tool names, inside a sentence
			tr("entrance", "door tool, mid-sentence"),
			tr("exit", "door tool, mid-sentence"),
			# BuildResult.detail_args sentences and lists
			tr("gate {gate} is too close", "refusal detail"),
			tr("gate {gate}, a small plane", "refusal detail"),
			tr("gate {gate}, a medium plane", "refusal detail"),
			tr("gate {gate}, a large plane", "refusal detail"),
			tr(", ", "list separator"),
			# Status lines of the belt, facing, area drag and room tools
			tr_n("Belt {count} cell", "Belt {count} cells", 1, "build status"),
			tr("Facing auto", "build status"),
			tr("Facing {facing}", "build status"),
			tr("{width} x {height}", "build status"),
			tr("{room} {width} x {height}", "build status"),
			tr("{room} marked: {status}", "build status"),
			tr("Drag to mark a {room}", "build status"),
			# A door's blocker inside the refusal (BuildCatalog display_name, lower case)
			tr("atm", "item name, mid-sentence"),
			tr("baggage belt", "item name, mid-sentence"),
			tr("baggage cart", "item name, mid-sentence"),
			tr("bar counter", "item name, mid-sentence"),
			tr("belt corner", "item name, mid-sentence"),
			tr("belt end", "item name, mid-sentence"),
			tr("belt merge", "item name, mid-sentence"),
			tr("bench", "item name, mid-sentence"),
			tr("bin", "item name, mid-sentence"),
			tr("bush", "item name, mid-sentence"),
			tr("cafe counter", "item name, mid-sentence"),
			tr("cafe table", "item name, mid-sentence"),
			tr("chain", "item name, mid-sentence"),
			tr("check-in desk", "item name, mid-sentence"),
			tr("clothes rail", "item name, mid-sentence"),
			tr("currency exchange", "item name, mid-sentence"),
			tr("display stand", "item name, mid-sentence"),
			tr("duty free shelf", "item name, mid-sentence"),
			tr("duty free till", "item name, mid-sentence"),
			tr("entrance", "item name, mid-sentence"),
			tr("exit to the plane", "item name, mid-sentence"),
			tr("fashion till", "item name, mid-sentence"),
			tr("fountain", "item name, mid-sentence"),
			tr("gate desk", "item name, mid-sentence"),
			tr("gate seats", "item name, mid-sentence"),
			tr("grab-and-go stall", "item name, mid-sentence"),
			tr("info desk", "item name, mid-sentence"),
			tr("info screen", "item name, mid-sentence"),
			tr("kiosk counter", "item name, mid-sentence"),
			tr("lounge armchair", "item name, mid-sentence"),
			tr("lounge sofa", "item name, mid-sentence"),
			tr("nap pod", "item name, mid-sentence"),
			tr("pharmacy counter", "item name, mid-sentence"),
			tr("pharmacy shelf", "item name, mid-sentence"),
			tr("pickup table", "item name, mid-sentence"),
			tr("plant pot", "item name, mid-sentence"),
			tr("planter", "item name, mid-sentence"),
			tr("play blocks", "item name, mid-sentence"),
			tr("play slide", "item name, mid-sentence"),
			tr("post", "item name, mid-sentence"),
			tr("prize podium", "item name, mid-sentence"),
			tr("restaurant booth", "item name, mid-sentence"),
			tr("restaurant table", "item name, mid-sentence"),
			tr("screen", "item name, mid-sentence"),
			tr("security arch", "item name, mid-sentence"),
			tr("security scanner", "item name, mid-sentence"),
			tr("shower", "item name, mid-sentence"),
			tr("sink", "item name, mid-sentence"),
			tr("statue", "item name, mid-sentence"),
			tr("toilet stall", "item name, mid-sentence"),
			tr("tray table", "item name, mid-sentence"),
			tr("tree", "item name, mid-sentence"),
			tr("tree bench", "item name, mid-sentence"),
			tr("work desk", "item name, mid-sentence"),
			tr("x-ray belt", "item name, mid-sentence"),
		]
		out.append_array(lane_status_msgids())
		return out

	## Never called: every SecurityLanes.STATUS_TEXT line inside tr(), so POT generation
	## finds it. The one inventory of the lane texts, shared with the lane-hint sign.
	func lane_status_msgids() -> Array[String]:
		return [
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
		]
