class_name DisplayWords
extends RefCounted
## The player's words for names and reasons that live as English data: an
## object's name (BuildCatalog), a room type's name and its requirement notes
## (RoomTypes, RoomRules), a landside place's name, and why a station or lane is
## not working. The data stays English because it keys lookups, icons and tests;
## the screens call these helpers at the moment they set text, never the data
## direct (decision translation-format-po-gettext-files-with-tr-and-tr-n-for-all).
##
## Static code cannot call tr() (an Object method), so each helper translates
## through TranslationServer with a context and Words.msgids() lists every English
## msgid inside tr(), which POT generation reads. test_display_words.gd checks the
## list holds every name and note the data can produce. A reason that follows a
## comma ("Status: Not ready, needs a tray table") is its own lower-case msgid in
## the "status reason" context, and a room name inside a sentence is its own
## lower-case msgid in the "room name, mid-sentence" context, so no translated
## text is ever case-transformed.

const ITEM_CONTEXT := "item name"
const ROOM_TYPE_CONTEXT := "room type"
const PLACE_CONTEXT := "landside place"
const NEED_CONTEXT := "room need"
const REASON_CONTEXT := "status reason"
const ROOM_MID_CONTEXT := "room name, mid-sentence"

static var _words := Words.new()


## An object's name by its BuildObjectDef.display_name.
static func item(english: String) -> String:
	return TranslationServer.translate(english, ITEM_CONTEXT)


## A room type's name by its RoomTypes.RoomType.display_name.
static func room_type(english: String) -> String:
	return TranslationServer.translate(english, ROOM_TYPE_CONTEXT)


## A landside place's name by its LandsidePlacement.NAMES entry.
static func landside(english: String) -> String:
	return TranslationServer.translate(english, PLACE_CONTEXT)


## What a ready room says (RoomRules.READY).
static func ready() -> String:
	return _words.ready()


## `status`'s notes in the player's words, in the order RoomRules gave them.
static func notes(status: RoomRules.RoomStatus) -> PackedStringArray:
	var out := PackedStringArray()
	for i in status.notes.size():
		if i == 0 and status.too_small:
			out.append(_too_small(status, false))
		else:
			out.append(TranslationServer.translate(status.notes[i], NEED_CONTEXT))
	return out


## Why a room is not ready, lower case, for a sentence that follows a comma.
static func room_reason(status: RoomRules.RoomStatus) -> String:
	if status.too_small:
		return _too_small(status, true)
	return reason(status.notes[0])


## An English reason (a lane status, a station's closed reason, a room note) in
## the player's words, lower case, for a sentence that follows a comma. The
## English text is lower-cased before the lookup, so the msgid is the lower-case
## form and a translation is never lower-cased.
static func reason(english: String) -> String:
	return TranslationServer.translate(english.to_lower(), REASON_CONTEXT)


## The whole status line of a desk whose gate link failed, from a
## GateDesks.unlinked() entry.
static func gate_unlinked(why: Dictionary) -> String:
	return _words.gate_unlinked(why)


## The whole status line of a faulted scanner, repaired on tick `repair`.
static func fault_status(repair: int) -> String:
	return _words.fault_status(repair)


## "Biggest plane: Medium" for a plane class (PlaneClasses), one whole line each.
static func biggest_plane(plane_class: String) -> String:
	return _words.biggest_plane(plane_class)


static func _too_small(status: RoomRules.RoomStatus, lower: bool) -> String:
	var type := RoomTypes.get_type(status.type_id)
	var room := TranslationServer.translate(type.display_name.to_lower(), ROOM_MID_CONTEXT)
	return _words.too_small(room, type.min_size, lower)


class Words:
	extends RefCounted

	func ready() -> String:
		return tr("Ready", "room status")

	func too_small(room: String, min_size: Vector2i, lower: bool) -> String:
		var text := (
			tr("too small: a {room} needs at least {width}x{height}", "status reason")
			if lower
			else tr("Too small: a {room} needs at least {width}x{height}", "room need")
		)
		return text.format({"room": room, "width": min_size.x, "height": min_size.y})

	func gate_unlinked(why: Dictionary) -> String:
		match why["why"]:
			GateDesks.Unlinked.NO_EXIT:
				return (
					tr("Status: unlinked: no exit facing the planes in {cells} cells", "gate card")
					. format({"cells": GateDesks.LINK_CELLS})
				)
			GateDesks.Unlinked.EXIT_TAKEN:
				return tr("Status: unlinked: gate {gate} uses the exit", "gate card").format(
					{"gate": why["gate"]}
				)
			GateDesks.Unlinked.STAND_OVERLAP:
				return tr("Status: unlinked: stand would overlap gate {gate}", "gate card").format(
					{"gate": why["gate"]}
				)
			GateDesks.Unlinked.NO_ROOM:
				return tr("Status: unlinked: no room for a plane", "gate card")
			GateDesks.Unlinked.ROUTE_BLOCKED:
				return tr("Status: unlinked: way to the lane blocked", "gate card")
		return tr("Status: unlinked: every gate letter in use", "gate card")

	func fault_status(repair: int) -> String:
		return tr("Status: Scanner fault, fixed by {time}").format(
			{"time": GameCalendar.clock_text(repair)}
		)

	func biggest_plane(plane_class: String) -> String:
		match plane_class:
			PlaneClasses.SMALL:
				return tr("Biggest plane: Small", "gate card")
			PlaneClasses.MEDIUM:
				return tr("Biggest plane: Medium", "gate card")
			PlaneClasses.LARGE:
				return tr("Biggest plane: Large", "gate card")
		return tr("Biggest plane: {class}", "gate card").format({"class": plane_class.capitalize()})

	## Never called: every name, note and reason the data can produce inside tr(),
	## so POT generation finds it. test_display_words.gd checks the list against
	## the data.
	func msgids() -> Array[String]:
		return [
			# Object names (BuildObjectDef.display_name)
			tr("ATM", "item name"),
			tr("Baggage belt", "item name"),
			tr("Baggage cart", "item name"),
			tr("Bar counter", "item name"),
			tr("Belt corner", "item name"),
			tr("Belt end", "item name"),
			tr("Belt merge", "item name"),
			tr("Bench", "item name"),
			tr("Bin", "item name"),
			tr("Bush", "item name"),
			tr("Cafe counter", "item name"),
			tr("Cafe table", "item name"),
			tr("Chain", "item name"),
			tr("Check-in desk", "item name"),
			tr("Clothes rail", "item name"),
			tr("Currency exchange", "item name"),
			tr("Display stand", "item name"),
			tr("Duty free shelf", "item name"),
			tr("Duty free till", "item name"),
			tr("Entrance", "item name"),
			tr("Exit to the plane", "item name"),
			tr("Fashion till", "item name"),
			tr("Fountain", "item name"),
			tr("Gate desk", "item name"),
			tr("Gate seats", "item name"),
			tr("Grab-and-go stall", "item name"),
			tr("Info desk", "item name"),
			tr("Info screen", "item name"),
			tr("Kiosk counter", "item name"),
			tr("Lounge armchair", "item name"),
			tr("Lounge sofa", "item name"),
			tr("Nap pod", "item name"),
			tr("Pharmacy counter", "item name"),
			tr("Pharmacy shelf", "item name"),
			tr("Pickup table", "item name"),
			tr("Plant pot", "item name"),
			tr("Planter", "item name"),
			tr("Play blocks", "item name"),
			tr("Play slide", "item name"),
			tr("Post", "item name"),
			tr("Prize podium", "item name"),
			tr("Restaurant booth", "item name"),
			tr("Restaurant table", "item name"),
			tr("Screen", "item name"),
			tr("Security arch", "item name"),
			tr("Security scanner", "item name"),
			tr("Shower", "item name"),
			tr("Sink", "item name"),
			tr("Statue", "item name"),
			tr("Toilet stall", "item name"),
			tr("Tray table", "item name"),
			tr("Tree", "item name"),
			tr("Tree bench", "item name"),
			tr("Work desk", "item name"),
			tr("X-ray belt", "item name"),
			# Room type names (RoomTypes.RoomType.display_name)
			tr("ATM", "room type"),
			tr("Bag room", "room type"),
			tr("Bar", "room type"),
			tr("Cafe", "room type"),
			tr("Duty free", "room type"),
			tr("Exchange", "room type"),
			tr("Fashion store", "room type"),
			tr("Grab-and-go stall", "room type"),
			tr("Kiosk", "room type"),
			tr("Lounge", "room type"),
			tr("Nap pod", "room type"),
			tr("Pharmacy", "room type"),
			tr("Play area", "room type"),
			tr("Restaurant", "room type"),
			tr("Shower", "room type"),
			tr("Toilet", "room type"),
			# The same room names in lower case, inside a sentence ("a cafe needs...")
			tr("atm", "room name, mid-sentence"),
			tr("bag room", "room name, mid-sentence"),
			tr("bar", "room name, mid-sentence"),
			tr("cafe", "room name, mid-sentence"),
			tr("duty free", "room name, mid-sentence"),
			tr("exchange", "room name, mid-sentence"),
			tr("fashion store", "room name, mid-sentence"),
			tr("grab-and-go stall", "room name, mid-sentence"),
			tr("kiosk", "room name, mid-sentence"),
			tr("lounge", "room name, mid-sentence"),
			tr("nap pod", "room name, mid-sentence"),
			tr("pharmacy", "room name, mid-sentence"),
			tr("play area", "room name, mid-sentence"),
			tr("restaurant", "room name, mid-sentence"),
			tr("shower", "room name, mid-sentence"),
			tr("toilet", "room name, mid-sentence"),
			# Landside place names (LandsidePlacement.NAMES)
			tr("Curb bay", "landside place"),
			tr("Multi-storey car park", "landside place"),
			tr("Surface lot", "landside place"),
			# Room requirement notes, the room panel and card
			tr("Needs a belt end", "room need"),
			tr("Needs a clothes rail", "room need"),
			tr("Needs a counter", "room need"),
			tr("Needs a display stand", "room need"),
			tr("Needs a kiosk counter", "room need"),
			tr("Needs a nap pod", "room need"),
			tr("Needs a pharmacy counter", "room need"),
			tr("Needs a shelf", "room need"),
			tr("Needs a shower", "room need"),
			tr("Needs a sink", "room need"),
			tr("Needs a slide", "room need"),
			tr("Needs a sofa", "room need"),
			tr("Needs a table", "room need"),
			tr("Needs a till", "room need"),
			tr("Needs a toilet stall", "room need"),
			tr("Needs an ATM", "room need"),
			tr("Needs an exchange counter", "room need"),
			tr("Needs play blocks", "room need"),
			tr("Needs a door or open side to the walkway", "room need"),
			# The same notes in lower case, after "Not ready,"
			tr("needs a belt end", "status reason"),
			tr("needs a clothes rail", "status reason"),
			tr("needs a counter", "status reason"),
			tr("needs a display stand", "status reason"),
			tr("needs a kiosk counter", "status reason"),
			tr("needs a nap pod", "status reason"),
			tr("needs a pharmacy counter", "status reason"),
			tr("needs a shelf", "status reason"),
			tr("needs a shower", "status reason"),
			tr("needs a sink", "status reason"),
			tr("needs a slide", "status reason"),
			tr("needs a sofa", "status reason"),
			tr("needs a table", "status reason"),
			tr("needs a till", "status reason"),
			tr("needs a toilet stall", "status reason"),
			tr("needs an atm", "status reason"),
			tr("needs an exchange counter", "status reason"),
			tr("needs play blocks", "status reason"),
			tr("needs a door or open side to the walkway", "status reason"),
			# Security lane statuses, lower case, after "Not ready,"
			tr("a wall cuts through the lane", "status reason"),
			tr("clear the floor for the queue", "status reason"),
			tr("clear the floor for the repack spot", "status reason"),
			tr("clear the helper's spot by the repack spot", "status reason"),
			tr("clear the officer's spot by the x-ray belt", "status reason"),
			tr("clear the way back from the repack spot", "status reason"),
			tr("clear the way out past the pickup table", "status reason"),
			tr("clear the way through the arch", "status reason"),
			tr("needs a pickup table", "status reason"),
			tr("needs a tray table", "status reason"),
			tr("needs an x-ray belt", "status reason"),
			tr("no arch", "status reason"),
			tr("parts face different ways", "status reason"),
			# Why a station is closed, lower case, after "Closed,"
			tr("closed by you", "status reason"),
			tr("staff spot blocked", "status reason"),
			tr("staff can't reach the staff spot", "status reason"),
			tr("no staff on duty", "status reason"),
			tr("scanner fault", "status reason"),
		]
