class_name SaveGame
extends Node
## The whole-world save (decision flights-and-economy-design-tick-derived-
## calendar-timetable-o, point 8, under standing sim-architecture-fixed-tick-
## data-records-snapshot-saves-grid-astar: "Saves are a JSON snapshot at a tick
## boundary with save_version"). One JSON dictionary with one save_version
## holds every part of the world that is state, one key per entry of parts().
## Views, UI and caches are not saved; they are rebuilt from the parts.
##
## Saving happens only between ticks. The pre-save step, save_problem(), runs
## before any part is read: it refuses inside a tick (SimClock.is_in_tick())
## and between a grid edit and the next tick (CafeSim.deadlines_stale), because
## only that tick's reconcile may settle the cafe; settling it at save time
## would run it a tick early. Each part's to_snapshot() only reads, so a
## game saved and played on plays exactly like one never saved. The staff are
## saved as they stand, a leaving member whose service just ended included;
## the next tick's staff step lets it go, loaded or not.
## The bags wait for the same tick (BaggageSim.routes_stale): their route
## field is rebuilt from the grid on the tick after an edit, never at save
## time. request_save() keeps a refused save waiting, with its message kept
## on screen while it waits (a paused game can wait a long time), and
## retries it after each frame's clock advance (process_priority puts this
## node after SimClock).
##
## Loading checks everything before it changes anything. Each part is loaded
## into a staged copy built from the save alone (a grid, then a bare
## PassengerSim on that grid for the passengers and the staff, a fresh
## instance for the rest), then the parts are checked against each other: one
## tick for all, and every id one part saves that names something in another
## (SaveLinks). Only when every check passes are the live parts installed,
## in parts() order. A refused load leaves the world as it was.
##
## A part named in OPTIONAL_PARTS may be missing from a save made before it
## existed. It is then not staged, and its install is the part's own "none
## saved" step: the DayLedger counts today's money from the load
## (DayLedger.start_since_load).
##
## Files go to user://saves/ as JSON, written to a .tmp file and renamed over
## the old save. F5 quick-saves and F8 quick-loads (F9 is left unbound; the
## playtest hook tests press it as a key bound to nothing). Every failure is
## pushed as an error and shown on screen.
##
## The first tick of each new game day queues an autosave into the SaveSlots
## autosave that is due (the two files take turns), written from _process once
## save_problem() allows it (decision title-menu-with-continue-new-airport-load-
## and-quit-autosave). The title screen boots main.tscn in Load mode through
## GameBoot.load_path: _ready takes the path and loads it once the whole scene
## is ready.

## A save or load finished; `ok` false when it was refused or failed.
signal saved(path: String, ok: bool)
signal loaded(ok: bool)

## 2: the bags (part "baggage"); version 1 saves are refused.
## 3: the landside (part "landside": arrival bookings, cars, taxis and car
## parks); version 2 saves are refused (no migration before a release).
## 4: the room templates (part "templates"); version 3 saves are refused.
## 5: the messes, bin fill and use counters (part "messes", MessSim); version 4
## saves are refused (no migration before a release).
## 6: cleaners (staff save version 4: each member's job and work left, and
## mess claims checked against them); version 5 saves are refused.
## 7: the player-built terminal on the airport site (the grid in the site's
## frame, no Toon shell); version 6 saves are refused (no migration before a
## release).
## 8: the live plane stand (part "apron", ApronStand) and longer TAXI_IN and
## TAXI_OUT phases, which move every flight's start ticks; version 7 saves
## are refused (no migration before a release).
## 9: the land plots (part "land"); version 8 saves are refused.
## 10: the gates (part "gates", GateDesks: each gate's letter, desk and exit)
## and one stand per gate in the apron part; version 9 saves are refused (no
## migration before a release).
## 11: the stations the player closed (staff save version 5, StationClosures);
## version 10 saves are refused (no migration before a release).
## 12: the build unlocks (part "unlocks", BuildUnlocks: the highest tier and the
## made-flight count); version 11 saves are refused (no migration before a
## release).
## 13: the runway's size (part "runway", Runway); version 12 saves are refused
## (no migration before a release).
## 14: the runway part holds the upgrade works too (Runway save version 2:
## RunwayWorks, the size they build and the ticks they run); version 13 saves
## are refused (no migration before a release).
## 15: the unlocks part also holds the tiers whose unlock dialog showed and the
## tools the player has seen (BuildUnlocks "shown" and "seen"); version 14 saves
## are refused (no migration before a release).
## 16: the rating part holds the incident adjustments (AirportRating save
## version 2, RatingAdjustments); version 15 saves are refused (no migration
## before a release).
## 17: the incidents (part "incidents", IncidentDirector: on or off, the last
## rolled day, the next day a major may come and every incident's saved ticks);
## required whenever the scene has a director. Version 16 saves are refused (no
## migration before a release).
## 18: every saved incident also says whether its announcement was shown
## (IncidentSnapshot version 2, "shown"); version 17 saves are refused (no
## migration before a release).
## 19: the major incidents (inspector, rush, VIP, favour) keep what they decided
## in a saved plan (IncidentSnapshot version 3, "plan"); version 18 saves are
## refused (no migration before a release).
## 20: an inspector's plan also keeps the messes and full-queue passengers its
## visit counted (IncidentSnapshot version 4); version 19 saves are refused (no
## migration before a release).
## 21: the settlement part requires "bonuses_paid" (the contracts whose Signing
## bonus was paid), the offers part is OfferBoard save version 5 (the Loyal
## airline count) and the day ledger holds the fines and the signing bonus;
## version 20 saves are refused (no migration before a release).
## 22: the offers part is OfferBoard save version 6 (Odd hours offers depart
## 06:00 to 22:00, and offers may carry Exit fee); version 21 saves are refused
## (no migration before a release).
## 23: the unlocks part also holds the big firsts whose dialog showed
## (BuildUnlocks "firsts": the runway upgrade and the major incident); version
## 22 saves are refused (no migration before a release).
## 24: the site grid is 256 cells wide with side land west and east (the grid
## part's frame and cells, the land part's 12 plot columns); version 23 saves
## are refused (no migration before a release).
## 25: the clock part holds the calendar epoch and whether the calendar is held
## (SimClock save version 2; decision closed-airport-calendar-design-an-
## explicit-calendar-epoch-pa), and every saved day and time reads at that
## epoch; version 24 saves are refused (no migration before a release).
## 26: the day ledger part holds cumulative positive revenue ("total_earned");
## version 25 saves are refused (no migration before a release).
const SAVE_VERSION := 26
## Parts a version 2 save may lack: "day_ledger" came after the version.
const OPTIONAL_PARTS := ["day_ledger"]
const SAVE_DIR := "user://saves"
const QUICK_SAVE_PATH := "user://saves/quicksave.json"
const QUICK_SAVE_KEY := KEY_F5
const QUICK_LOAD_KEY := KEY_F8
## How long a message stays on screen.
const MESSAGE_SECONDS := 4.0

@export var clock: SimClock
@export var build_mode: BuildMode
@export var flights: FlightSim
@export var passengers: PassengerSim
@export var staff: StaffSim
@export var finances: Finances
@export var settlement: Settlement
@export var rescue_grant: RescueGrant
@export var offer_desk: OfferDesk
@export var rating: AirportRating
@export var baggage: BaggageSim
@export var day_ledger: DayLedger
@export var landside: LandsideSim
## The plane stand; none (a test world) saves no "apron" part.
@export var apron: ApronStand
## The gate desks; none (a test world) saves no "gates" part.
@export var gates: GateDesks
## The build unlocks; none (a test world) saves no "unlocks" part.
@export var unlocks: BuildUnlocks
## The incidents; none (a test world) saves no "incidents" part. With one, a
## save without the part is refused.
@export var incidents: IncidentDirector
## Where F5 and F8 save and load. Tests point it at their own file. Left at
## QUICK_SAVE_PATH, _ready makes it SaveSlots.manual_path().
@export var quick_save_path := QUICK_SAVE_PATH

## The file a refused request_save() is waiting to write, or "".
var pending_path := ""
## The autosave a day rollover queued, written once a save is allowed, or "".
var autosave_pending := ""

## The game day the last autosave was queued for (or the loaded or starting day).
var _autosave_day := 0
## The autosave the next day writes around: the one this node wrote last, or the
## one just loaded, so the next day writes the other. Empty after a manual load.
var _last_autosave := ""

var _message := ""
var _message_left := 0.0
## The on-screen message, made when the node enters the tree.
var _label: Label


func _ready() -> void:
	process_priority = 100
	var layer := CanvasLayer.new()
	layer.layer = 3
	layer.name = "SaveMessage"
	_label = Label.new()
	_label.name = "Message"
	_label.position = Vector2(16.0, 56.0)
	_label.visible = false
	layer.add_child(_label)
	add_child(layer)
	if quick_save_path == QUICK_SAVE_PATH:
		quick_save_path = SaveSlots.manual_path()
	if clock != null:
		_autosave_day = GameCalendar.day_of(clock.tick, clock.epoch)
		clock.ticked.connect(on_tick)
	var boot_path := GameBoot.take_load_path()
	if boot_path != "":
		if clock != null:
			clock.set_paused(true)
		_boot_load.call_deferred(boot_path)
	GameBoot.clear_new_airport.call_deferred()


## SimClock.ticked: the first tick of a new game day queues the autosave that
## is due. A script run on the player's save folder queues none (SaveSlots).
func on_tick(tick: int) -> void:
	var day := GameCalendar.day_of(tick, clock.epoch)
	if day <= _autosave_day:
		return
	_autosave_day = day
	if not SaveSlots.is_shielded():
		autosave_pending = SaveSlots.next_autosave(_last_autosave)


## Writes the queued autosave if save_problem() now allows it. True when it did.
func retry_autosave() -> bool:
	if autosave_pending == "" or save_problem() != "":
		return false
	var path := autosave_pending
	autosave_pending = ""
	if not save_to_file(path):
		return false
	_last_autosave = path
	return true


## The save's parts in install order. The grid comes first (the passengers
## are checked against it), the passengers before the staff, then the rest. A
## new part is one more entry here.
func parts() -> Array[SavePart]:
	var list: Array[SavePart] = [
		SavePart.new("grid", build_mode.grid.to_snapshot, _stage_grid, build_mode.load_snapshot),
		# Kept staged: the flights, the rating and the bookings read its calendar epoch.
		SavePart.new(
			"clock",
			clock.to_snapshot,
			SavePart.scratch(SimClock, &"from_snapshot", "clock"),
			clock.from_snapshot
		),
		SavePart.new(
			"runway",
			flights.runway.to_snapshot,
			SavePart.scratch(Runway, &"from_snapshot", "runway"),
			flights.runway.from_snapshot
		),
		# Checked against the saved gates (or, with no gate desks, the live ones).
		SavePart.new("flights", flights.to_snapshot, _stage_flights, flights.from_snapshot),
		SavePart.new(
			"passengers", passengers.to_snapshot, _stage_passengers, passengers.from_snapshot
		),
		# Checked against the staged grid; installed after the grid it is on.
		SavePart.new(
			"messes", passengers.messes.to_snapshot, _stage_messes, passengers.messes.from_snapshot
		),
		SavePart.new("staff", staff.to_snapshot, _stage_staff, staff.from_snapshot),
		# The bookings are PassengerSim's; the part holds them with the cars.
		SavePart.new(
			"landside",
			func() -> Dictionary: return landside.to_snapshot(passengers.arrivals, passengers.tick),
			_stage_landside,
			func(data: Dictionary) -> bool: return landside.from_snapshot(data, passengers.arrivals)
		),
		SavePart.new(
			"baggage",
			baggage.to_snapshot,
			SavePart.checked(
				"baggage", func(data: Dictionary) -> Dictionary: return BaggageSnapshot.load(data)
			),
			baggage.from_snapshot
		),
		# Finances.restore(), never start_new_game(): a load is not a new game.
		SavePart.new(
			"wallet",
			finances.wallet.to_snapshot,
			SavePart.scratch(Finances, &"restore"),
			finances.restore
		),
		SavePart.new(
			"settlement",
			settlement.to_snapshot,
			SavePart.scratch(Settlement),
			settlement.from_snapshot
		),
		SavePart.new(
			"day_ledger",
			day_ledger.to_snapshot,
			SavePart.scratch(DayLedger),
			day_ledger.from_snapshot
		),
		SavePart.new(
			"rescue_grant",
			rescue_grant.to_snapshot,
			SavePart.scratch(RescueGrant),
			rescue_grant.from_snapshot
		),
		# The board holds no RNG: the next day's draw continues from the clock's.
		SavePart.new(
			"offers",
			offer_desk.board.to_snapshot,
			SavePart.scratch(OfferBoard, &"from_snapshot", "offers"),
			offer_desk.board.from_snapshot
		),
		SavePart.new("rating", rating.to_snapshot, _stage_rating, _install_rating),
		SavePart.new(
			"templates",
			build_mode.templates.library.to_snapshot,
			SavePart.scratch(RoomTemplates),
			build_mode.templates.library.from_snapshot
		),
	]
	if build_mode.land_tool != null and build_mode.land_tool.land != null:
		# Right after the grid, whose built cells must stand on owned land.
		list.insert(
			1,
			SavePart.new(
				"land",
				build_mode.land_tool.land.to_snapshot,
				_stage_land,
				build_mode.land_tool.land.from_snapshot
			)
		)
	if gates != null:
		# After the grid (and its land), whose desks and exits the gates are,
		# and before the flights, which are checked against the gates.
		var after := list.find_custom(func(part: SavePart) -> bool: return part.key == "clock")
		list.insert(
			after, SavePart.new("gates", gates.to_snapshot, _stage_gates, gates.from_snapshot)
		)
	if apron != null:
		# After the flights, which say whether the stand is in use, and
		# before the passengers, whose exits walk to its plane door.
		var at := list.find_custom(func(part: SavePart) -> bool: return part.key == "passengers")
		list.insert(at, SavePart.new("apron", apron.to_snapshot, _stage_apron, apron.from_snapshot))
	if unlocks != null:
		list.append(
			SavePart.new(
				"unlocks",
				unlocks.to_snapshot,
				SavePart.scratch(BuildUnlocks),
				unlocks.from_snapshot
			)
		)
	if incidents != null:
		# Last: its install follows the clock, whose tick sets the day it is on.
		list.append(
			SavePart.new(
				"incidents",
				incidents.to_snapshot,
				SavePart.checked(
					"incidents",
					func(data: Dictionary) -> Dictionary: return IncidentSnapshot.load(data)
				),
				incidents.from_snapshot
			)
		)
	return list


## Why no save may be taken now, or "" when one may. Checked before any part
## is read.
func save_problem() -> String:
	if clock.is_in_tick():
		return "the game is in the middle of a tick"
	var land_tool := build_mode.land_tool
	if land_tool != null and land_tool.land != null and land_tool.land.error != "":
		return "the site's land plots were refused: %s" % land_tool.land.error
	if passengers.cafes.deadlines_stale or baggage.routes_stale or passengers.messes.stale:
		return "the last build change settles on the next tick"
	return ""


## The whole world as one JSON-safe dictionary, or {} (with an error shown)
## when save_problem() refuses.
func snapshot() -> Dictionary:
	var problem := save_problem()
	if problem != "":
		_fail("Save", problem)
		return {}
	var data := {"save_version": SAVE_VERSION}
	for part in parts():
		data[part.key] = part.save.call()
	return data


## Loads a snapshot() dictionary, including one that went through JSON. Every
## part is checked before any is installed; on a refusal the world is left as
## it was, the reason is shown and false returned.
func load_world(data: Variant) -> bool:
	var problem := "the game is in the middle of a tick" if clock.is_in_tick() else ""
	if problem == "":
		problem = _shape_problem(data)
	if problem == "":
		var staged := {}
		problem = _stage_all(data, staged)
		for value in staged.values():
			if value is Node:
				value.free()
	if problem != "":
		_fail("Load", problem)
		loaded.emit(false)
		return false
	pending_path = ""
	for part in parts():
		if not _install(part, data):
			# Unreachable while each install repeats its own stage check; said
			# loudly, because the world is then partly loaded.
			_fail("Load", "the %s part was refused after it was checked" % part.key)
			loaded.emit(false)
			return false
	# The rescue grant's repair bound, worked out now rather than in a tick.
	if rescue_grant != null:
		rescue_grant.prepare()
	# Speed and pause are not save data (decision loading-a-save-always-comes-
	# back-paused-at-1x-speed-with-hin): the clock part just installed the
	# saved ones, and a load always waits for the player. Before the signal, so
	# listeners see the final clock.
	clock.set_paused(true)
	clock.set_speed(1)
	# A queued autosave was for the old world; days count from the loaded one.
	autosave_pending = ""
	_autosave_day = GameCalendar.day_of(clock.tick, clock.epoch)
	GameBoot.clear_new_airport()
	_say("Loaded", false)
	loaded.emit(true)
	return true


## Saves the world to `path`: written to `path`.tmp, then renamed over `path`.
## False (with the reason shown) when the save is refused or the file cannot
## be written; an old save at `path` is then left as it was.
func save_to_file(path: String) -> bool:
	var data := snapshot()
	if data.is_empty():
		saved.emit(path, false)
		return false
	var problem := _write_replacing(path, JSON.stringify(data, "", true, true))
	if problem != "":
		_fail("Save", problem)
		saved.emit(path, false)
		return false
	_say("Saved to %s" % path, false)
	saved.emit(path, true)
	return true


## Loads the save at `path`. False (with the reason shown) when the file is
## missing, unreadable, not JSON or refused by load_world().
func load_from_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		_fail("Load", "there is no save at %s" % path)
		loaded.emit(false)
		return false
	var text := FileAccess.get_file_as_string(path)
	var open_error := FileAccess.get_open_error()
	if open_error != OK:
		_fail("Load", "cannot read %s (%s)" % [path, error_string(open_error)])
		loaded.emit(false)
		return false
	var json := JSON.new()
	if json.parse(text) != OK:
		_fail(
			"Load",
			(
				"%s is not a save (line %d: %s)"
				% [path, json.get_error_line(), json.get_error_message()]
			)
		)
		loaded.emit(false)
		return false
	if not load_world(json.data):
		return false
	# Rotation follows the loaded timeline: a loaded autosave is the last one
	# written, so the next rollover keeps it as the fallback and writes the other.
	# A manual or other save names no slot, so the older autosave is written.
	var slot := SaveSlots.autosave_paths().find(path)
	_last_autosave = path if slot >= 0 else ""
	return true


## Saves to `path` now, or, when save_problem() refuses for now, waits and
## saves after the first frame's clock advance that allows it. True when it
## saved now.
func request_save(path := quick_save_path) -> bool:
	var problem := save_problem()
	if problem == "":
		pending_path = ""
		return save_to_file(path)
	pending_path = path
	_say("Saving after the next tick: %s" % problem, false)
	return false


## Writes the waiting save if save_problem() now allows it. True when it did.
func retry_pending() -> bool:
	if pending_path == "" or save_problem() != "":
		return false
	var path := pending_path
	pending_path = ""
	return save_to_file(path)


func quick_save() -> bool:
	return request_save(quick_save_path)


## Drops a waiting save: the loaded world replaces the one it was for.
func quick_load() -> bool:
	pending_path = ""
	return load_from_file(quick_save_path)


## The last message shown, "" when none.
func message_text() -> String:
	return _message


func _process(delta: float) -> void:
	retry_pending()
	retry_autosave()
	if pending_path != "":
		_message_left = MESSAGE_SECONDS
	elif _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0 and _label != null:
			_label.visible = false


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.ctrl_pressed or key.alt_pressed or key.shift_pressed or key.meta_pressed:
		return
	if key.keycode == QUICK_SAVE_KEY:
		get_viewport().set_input_as_handled()
		quick_save()
	elif key.keycode == QUICK_LOAD_KEY:
		get_viewport().set_input_as_handled()
		quick_load()


## The title screen's Continue or Load. A refused load leaves its message in
## GameBoot.refusal and, in the running game, goes back to the title to show
## it; a test or probe that added the scene by hand keeps the scene.
func _boot_load(path: String) -> void:
	if load_from_file(path):
		return
	GameBoot.refusal = _message
	var current := get_tree().current_scene
	if current != null and (current == self or current.is_ancestor_of(self)):
		get_tree().change_scene_to_file(GameBoot.TITLE_SCENE)


## Installs one part, or its "none saved" step when an older save lacks it.
func _install(part: SavePart, data: Dictionary) -> bool:
	if data.has(part.key):
		return part.install.call(data[part.key])
	if part.key == "day_ledger":
		day_ledger.start_since_load()
		return true
	return false


func _shape_problem(data: Variant) -> String:
	if typeof(data) != TYPE_DICTIONARY:
		return "the save is not a dictionary"
	var keys := ["save_version"]
	for part in parts():
		keys.append(part.key)
	for key in (data as Dictionary).keys():
		if not keys.has(key):
			return "unknown key '%s'" % key
	for key in keys:
		if not (data as Dictionary).has(key) and not OPTIONAL_PARTS.has(key):
			return "missing key '%s'" % key
	if not WholeNumber.is_whole(data["save_version"]) or int(data["save_version"]) != SAVE_VERSION:
		return "save_version must be %d" % SAVE_VERSION
	for key in keys.slice(1):
		if (data as Dictionary).has(key) and typeof(data[key]) != TYPE_DICTIONARY:
			return "part '%s' is not a dictionary" % key
	return ""


func _stage_all(data: Dictionary, staged: Dictionary) -> String:
	for part in parts():
		if not data.has(part.key):
			continue
		var problem: String = part.stage.call(data[part.key], staged)
		if problem != "":
			return "%s: %s" % [part.key, problem]
	var across := _ticks_problem(data)
	if across == "":
		across = _epoch_problem(data)
	if across == "":
		across = SaveLinks.problem(data, staged)
	if across == "":
		across = _entrance_links_problem(staged)
	if across == "" and staged.has("incidents"):
		# Every active spill names a SPILL mess at its own cell.
		across = IncidentSnapshot.links_problem(staged["incidents"], staged["messes"])
		if across == "" and data.has("staff"):
			# Every active scanner fault is the staff's own, with its repair tick.
			across = IncidentFault.links_problem(
				staged["incidents"]["incidents"], data["staff"]["faults"], staged["sim"].grid
			)
		across = "incidents: %s" % across if across != "" else ""
	if across == "":
		across = _runway_problem(data, staged)
	return across


## "" or why the saved runway cannot take a saved offer's plane class. (A saved
## contract is checked with the staged flights: FlightSim.load_problem.) The
## runway only grows, so every offer drawn and every contract accepted had a
## class its runway took.
func _runway_problem(data: Dictionary, staged: Dictionary) -> String:
	var runway: Runway = staged["runway"]
	# The works end on a tick the sim has not reached (Runway.settle() runs on
	# every tick), so a saved booking that is already over is not a state of play.
	var tick := str(data["clock"]["tick"]).to_int()
	if runway.works.scheduled() and runway.works.finish <= tick:
		return (
			"runway: the works end at tick %d, the clock is on tick %d"
			% [runway.works.finish, tick]
		)
	for offer: Dictionary in data["offers"]["offers"]:
		if not runway.takes(offer["plane_size"]):
			return (
				"offers: offer %s is a %s plane but the runway is %s"
				% [offer["id"], offer["plane_size"], runway.size]
			)
	return ""


## The rating (RatingSnapshot.load()) at the saved clock's calendar epoch.
func _stage_rating(data: Dictionary, staged: Dictionary) -> String:
	var loaded := RatingSnapshot.load(data, _staged_epoch(staged))
	if loaded.has("error"):
		return str(loaded["error"])
	staged["rating"] = loaded
	return ""


## The calendar epoch of the staged clock, or 0 when a unit test stages a part
## on its own without a clock part.
static func _staged_epoch(staged: Dictionary) -> int:
	return SimClock.epoch_of(staged.get("clock") as SimClock)


## The calendar is held exactly while the airport is closed, and once it is
## open its epoch is the opening tick (decision closed-airport-calendar-design-
## an-explicit-calendar-epoch-pa, point 3). A world with no AirportGate (a
## test's) never holds its calendar, so only the first holds there.
func _epoch_problem(data: Dictionary) -> String:
	var held: bool = data["clock"]["calendar_held"]
	var epoch := SimClock.saved_epoch(data["clock"])
	var opened := int(data["flights"]["opened_tick"])
	if held and opened >= 0:
		return "clock: the calendar is held, but the airport opened on tick %d" % opened
	if flights.gate == null:
		return ""
	if opened < 0 and not held:
		return "clock: the airport is closed, but its calendar is not held"
	if opened >= 0 and epoch != opened:
		return "clock: the calendar epoch %d is not the opening tick %d" % [epoch, opened]
	return ""


## Every part that keeps the tick was saved on the same one.
func _ticks_problem(data: Dictionary) -> String:
	var tick := str(data["clock"]["tick"]).to_int()
	for key in ["flights", "passengers", "messes", "rating", "baggage", "landside"]:
		var value: Variant = data[key]["tick"]
		var other := str(value).to_int() if typeof(value) == TYPE_STRING else int(value)
		if other != tick:
			return "%s was saved on tick %d, the clock on tick %d" % [key, other, tick]
	return ""


## The site's frame check, then the grid's own, on a staged grid.
func _stage_grid(data: Dictionary, staged: Dictionary) -> String:
	if build_mode.site != null:
		var problem := build_mode.site.snapshot_problem(data)
		if problem != "":
			return problem
	var grid := BuildGrid.new()
	if not grid.from_snapshot(data):
		return "it was refused (see the error log)"
	staged["grid"] = grid
	return ""


## The gates (GateDesks.checked()) against the staged grid; kept for the
## flights, the stands and the passengers.
func _stage_gates(data: Dictionary, staged: Dictionary) -> String:
	var loaded := GateDesks.checked(data, staged["grid"])
	if loaded.has("error"):
		return str(loaded["error"])
	staged["gates"] = loaded["gates"]
	staged["spurs"] = loaded["spurs"]
	return ""


## The flights against the saved gates (with no gate desks, the live gate set)
## and their stands on the staged grid, taxi plans included: a save whose
## re-plan fails is refused here, before anything is installed (Runway R7).
## The data is kept too, for the passengers' check of their gates.
func _stage_flights(data: Dictionary, staged: Dictionary) -> String:
	var gate_set := flights.gate_ids()
	if staged.has("gates"):
		gate_set = _letters(staged["gates"])
	var loaded := FlightSnapshot.load(data, gate_set, _staged_epoch(staged))
	if loaded.has("error"):
		return str(loaded["error"])
	var planner := _staged_flight_sim(staged)
	var problem := planner.load_problem(data)
	planner.free()
	if problem != "":
		return problem
	staged["flights"] = loaded
	staged["flights_data"] = data
	return ""


## The stands (ApronStand.checked()); with gate desks, each saved gate's
## stand, straight out from its exit on the staged grid.
func _stage_apron(data: Dictionary, staged: Dictionary) -> String:
	var loaded := ApronStand.checked(data, apron.site)
	if loaded.has("error"):
		return str(loaded["error"])
	if loaded.has("stands") != staged.has("gates"):
		return "the save's stands are not of this airport's kind"
	if staged.has("gates"):
		var problem := ApronStand.stands_problem(
			loaded["stands"], staged["gates"], staged["grid"], staged["spurs"]
		)
		if problem != "":
			return problem
	staged["apron"] = loaded
	return ""


## An empty FlightSim on the staged gates: each saved gate's stand straight out
## from its exit on the staged grid, on its side's saved spur, and its max_class
## there, as GateDesks refresh() works them out (GateDesks.grounds_on()). With no
## gate desks, the live sim's sources.
func _staged_flight_sim(staged: Dictionary) -> FlightSim:
	var sim := FlightSim.new()
	sim.epoch = _staged_epoch(staged)
	if staged.has("runway"):
		sim.runway = staged["runway"]
	if not staged.has("gates"):
		sim.gate_source = flights.gate_source
		sim.stand_source = flights.stand_source
		sim.spur_source = flights.spur_source
		return sim
	var grid: BuildGrid = staged["grid"]
	var bindings: Array[Dictionary] = staged["gates"]
	var letters := _letters(bindings)
	# The saved spurs, each side's wanted x from the staged grid (SideSpurs.wanted()).
	var wanted := SideSpurs.wanted(grid, bindings.map(func(b: Dictionary) -> int: return b["exit"]))
	var grounds := GateDesks.grounds_on(grid, bindings, staged["spurs"], wanted)
	var spurs := SideSpurs.spurs_at(staged["spurs"], wanted)
	sim.gate_source = func() -> Array[String]: return letters
	sim.stand_source = func() -> Dictionary: return grounds
	sim.spur_source = func() -> Dictionary: return spurs
	return sim


static func _letters(bindings: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for binding in bindings:
		out.append(binding["gate"])
	return out


## The land plots (LandPlots): the site's plot counts, plots on the site, and
## every built cell of the staged grid on owned land.
func _stage_land(data: Dictionary, staged: Dictionary) -> String:
	var problem := LandPlots.problem(data, build_mode.site)
	if problem == "" and staged.has("grid"):
		problem = LandPlots.grid_problem(data, build_mode.site, staged["grid"])
	return problem


## Checked against the staged grid. Keeps the loaded passenger state and a
## bare PassengerSim on that grid, with its layout built, for the staff check
## and the links (SaveLinks).
func _stage_passengers(data: Dictionary, staged: Dictionary) -> String:
	var grid: BuildGrid = staged["grid"]
	var loaded := PassengerSnapshot.load(data, grid)
	if loaded.has("error"):
		return str(loaded["error"])
	var sim := PassengerSim.new()
	sim.grid = grid
	if staged.has("gates") and staged.has("apron"):
		_stage_gate_exits(sim, staged)
	sim.layout.rebuild(grid)
	# The spots are derived past the security lanes' exit cells, which the
	# runtime reads from its host's layout (a live sim binds it in bind()).
	sim.security.bind(sim)
	# The checks PassengerSim.from_snapshot() runs at install: info desks,
	# standing spots, boarding files, ParkSide's saved stamps, the line outside
	# the entrance, then the booking overrides against the staged flights.
	var by_id := {}
	for p: Passenger in loaded["passengers"]:
		by_id[p.id] = p
	var held := sim.checked_info_desks(data, by_id, loaded["tick"])
	if not held.has("error"):
		held = sim.checked_standing(data, by_id)
	if not held.has("error"):
		held = sim.checked_boarding(data, by_id)
	if not held.has("error"):
		held = PassengerSimSave.checked_park_side(data, by_id)
	if not held.has("error"):
		held = PassengerSimSave.checked_entrance(data, by_id)
		staged["entrance_line"] = held.get("line")
	if not held.has("error"):
		held = _checked_booking_overrides(data, staged)
	if held.has("error"):
		sim.free()
		return str(held["error"])
	staged["passengers"] = loaded
	staged["sim"] = sim
	return ""


## The saved booking overrides checked against the staged flights, so the
## class maximum and the contracts are the save's own: the staged FlightSim
## _stage_gate_exits() made, or one made here for the live gate set.
func _checked_booking_overrides(data: Dictionary, staged: Dictionary) -> Dictionary:
	var held: FlightSim = staged.get("staged_flights")
	var own := held == null and staged.has("flights_data")
	if own:
		held = _staged_flight_sim(staged)
		held.from_snapshot(staged["flights_data"])
	var result := BookingOverrides.checked(data, held, _staged_epoch(staged))
	if own:
		held.free()
	return result


## Gives the staged sim the saved gates' exits and stands, and a staged
## FlightSim with the saved flights, so the checks see the exits each
## passenger's gate allows, as the installed world will.
func _stage_gate_exits(sim: PassengerSim, staged: Dictionary) -> void:
	var stands: Dictionary = staged["apron"]["stands"]
	var bindings: Array[Dictionary] = staged["gates"]
	for binding in bindings:
		sim.layout.exit_stands[binding["exit"]] = stands[binding["gate"]]
		sim.layout.exit_gates[binding["exit"]] = binding["gate"]
		sim.layout.gate_desk_ids[binding["gate"]] = binding["desk"]
	sim.layout.by_gate = true
	var staged_flights := _staged_flight_sim(staged)
	staged_flights.from_snapshot(staged["flights_data"])
	staged["staged_flights"] = staged_flights
	sim.flights = staged_flights


## Checked against the staged grid: every mess on its floor, every bin and
## every use counter's source on it. Kept for the staff check of the
## cleaners' claims.
func _stage_messes(data: Dictionary, staged: Dictionary) -> String:
	var loaded := MessSim.checked(data, staged["grid"])
	if loaded.has("error"):
		return str(loaded["error"])
	staged["messes"] = loaded
	return ""


## Checked against the staged layout, and the cleaners' jobs against the
## staged messes.
func _stage_staff(data: Dictionary, staged: Dictionary) -> String:
	return str(StaffSnapshot.load(data, staged["sim"], staged["messes"]).get("error", ""))


## The line outside the entrance (EntranceLine) against the staged landside:
## every booking it holds as kept aboard for the line is a booking still in its
## vehicle, and each flight's misses kept aboard for the line are some of that
## flight's transport misses (ArrivalBookings.missed_by_flight), from 1 up to
## all of them. "" or the first that is not.
static func _entrance_links_problem(staged: Dictionary) -> String:
	var line: EntranceLine = staged.get("entrance_line")
	if line == null:
		return ""
	var landside: Dictionary = staged["landside"]
	var aboard := {}
	for b: ArrivalBooking in landside["bookings"]:
		if b.state == ArrivalBooking.State.IN_VEHICLE:
			aboard[b.id] = true
	for id: int in line.held:
		if not aboard.has(id):
			return "passengers: entrance line held booking %d is not a booking in its vehicle" % id
	var missed: Dictionary = landside["missed"]
	for flight_id: String in line.held_missed:
		var count: int = line.held_missed[flight_id]
		var road := int(missed.get(flight_id, 0))
		if count <= 0 or count > road:
			return (
				"passengers: entrance line held misses of %s (%d) are not among its %d transport misses"
				% [flight_id, count, road]
			)
	return ""


## Checked against the scene's landside definition; kept for the links.
func _stage_landside(data: Dictionary, staged: Dictionary) -> String:
	var loaded := LandsideSnapshot.load(data, landside.definition)
	if loaded.has("error"):
		return str(loaded["error"])
	staged["landside"] = loaded
	return ""


## AirportRating.from_snapshot() then bind (a no-op when already bound to
## these three).
func _install_rating(data: Dictionary) -> bool:
	if not rating.from_snapshot(data):
		return false
	rating.bind(clock, flights, passengers)
	return true


## "" or why the file could not be written. The old file is replaced only
## once the new one is fully written.
func _write_replacing(path: String, text: String) -> String:
	var dir := path.get_base_dir()
	var made := DirAccess.make_dir_recursive_absolute(dir)
	if made != OK:
		return "cannot make the folder %s (%s)" % [dir, error_string(made)]
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return "cannot write %s (%s)" % [temp, error_string(FileAccess.get_open_error())]
	file.store_string(text)
	var written := file.get_error()
	file.close()
	if written != OK:
		DirAccess.remove_absolute(temp)
		return "cannot write %s (%s)" % [temp, error_string(written)]
	var renamed := DirAccess.rename_absolute(temp, path)
	if renamed != OK:
		return "cannot replace %s (%s)" % [path, error_string(renamed)]
	return ""


func _fail(action: String, problem: String) -> void:
	push_error("SaveGame: %s failed: %s" % [action, problem])
	_say("%s failed: %s" % [action, problem], true)


func _say(text: String, is_error: bool) -> void:
	_message = text
	_message_left = MESSAGE_SECONDS
	if _label == null:
		return
	_label.text = text
	_label.modulate = Color(1.0, 0.45, 0.4) if is_error else Color.WHITE
	_label.visible = true
