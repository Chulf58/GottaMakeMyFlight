class_name UnlockGuide
extends Node
## What the player is told when a build tier opens (decision new-unlock-tier-
## phone-ring-and-a-short-per-family-dialog-onc). Two things:
##
## - A short dialog, the IntroDialogue's portrait and box with one line per
##   family the tier brings (UnlockFamilies). It shows once per tier. It holds
##   the clock paused while it is open (a hold on SimClock.holds that does not
##   give way to the player, as its text promises), and closing it releases
##   the hold, so the player's own speed applies again unless another hold
##   still pauses the game. It is one of the exclusive dialogs: opened while
##   another has the turn (the Offers sheet), it shows when that one closes.
##   The phone ring is a silent hook for now: `phone_ring` fires as the dialog
##   opens and the audio work (board e612caf3) plays it later.
## - The same dialog and ring also come the first time each big moment happens
##   in a game (BigFirsts, decisions phone-ring-and-help-dialog-also-on-big-
##   firsts-first-runway-u, opening-phone-call-right-after-the-airport-opens-
##   the-airline and day-clock-stops-until-the-airport-opens-the-opening-call-
##   pau): the airport opens (AirportGate.opened, taking the clock hold
##   synchronously on the opening tick with Gotta Air's station manager
##   speaker), the runway works finish (Runway.works_done, which a load never
##   emits) and a major incident is presented (IncidentDirector.major_presented).
##   A first shows once per game, kept in BuildUnlocks with the shown tiers;
##   one that comes while this dialog is open waits for it to close, and the
##   Gotta Air opening call never shares one box with the Terminal Manager's
##   lines. A load drops a first that was waiting.
## - A "New" mark on every unlocked card the player has not hovered or picked
##   yet (is_new()), however many tiers ago it opened. BuildMenu tints them.
##
## What was shown and seen is game state, kept in BuildUnlocks (dialog_shown(),
## tool_seen()) and so in the save's "unlocks" part: a new game starts with none,
## a load restores them. A load opens no dialog (it emits no tiers_opened) and
## ends one that is open or waiting, leaving the clock as loaded. The
## dialog shows for exactly the tiers not shown yet, so a tier skip never shows a
## tier twice. The guide is off (mode OFF: no dialog, no mark) in a probe, a test
## or a PlaytestHook run, like the hints; PassengerHud sets the mode.

## The dialog opened or closed (PassengerHud holds the camera still meanwhile).
signal dialog_changed(open: bool)
## The marks changed: BuildMenu repaints its cards.
signal changed
## The phone ring for a newly opened tier, or NO_TIER for a dialog that holds
## only big firsts. Nothing plays it yet.
## TODO(audio board e612caf3): play the ring here once the audio work lands.
signal phone_ring(tier: int)

enum Mode { OFF, PROFILE }

## What phone_ring sends for a dialog with no tier in it.
const NO_TIER := 0

## The dialog's canvas layer: with the intro, over the HUD and the build menu.
const LAYER := 10
## The English msgids of the dialog's title and footer. The dialog itself says tr()
## of the same literals, because the POT extractor reads only literals.
const TITLE_TEXT := "Your airport has grown"
const FOOTER_TEXT := "The clock goes on when you close this."
## The dialog box's height: taller than the intro's, for a line per family.
const BOX_HEIGHT := 400.0
## The starter contract's day-0 occurrence issued on the opening tick.
const STARTER_OCCURRENCE := "GMF101-d0"

var mode := Mode.OFF
var unlocks: BuildUnlocks
var clock: SimClock
## Optional: a load ends an open dialog.
var save_game: SaveGame
## Optional: the airport gate whose opening shows Gotta Air's call, and the
## flight sim whose starter departure time it reads. Under PassengerHud in
## main.tscn, _ready() finds ../../AirportGate and ../../FlightSim when unset.
var gate: AirportGate
var flights: FlightSim
## Optional: the runway whose first upgrade shows a dialog.
var runway: Runway
## Optional: the director whose first major incident shows a dialog.
var director: IncidentDirector

var _layer: CanvasLayer
var _dialog: IntroDialogue
## The dialog's hold on the clock, from open_dialog() until it closes or a load
## drops it. It does not give way to the player.
var _hold := ClockHolds.NONE
## The tiers of a dialog waiting for its turn.
var _waiting_tiers: Array = []
## The big firsts of a dialog waiting for its turn.
var _waiting_firsts: Array = []
## Tiers and big firsts queued while this guide's own dialog is open (or split
## behind the Gotta Air opening call): they show next under the same hold.
var _queued_tiers: Array = []
var _queued_firsts: Array = []
## Formatted starter departure time captured on the opening tick.
var _opening_departure := ""


## How a launch runs the guide: PROFILE when the onboarding hints switch
## (--hints or GMMF_HINTS=1, decision first-10-minutes-playtest-d3-an-ai-
## playtest-with-first-time) is on even under PlaytestHook, OFF in a plain
## PlaytestHook run, and PROFILE in a normal launch.
static func mode_for(args: PackedStringArray, env_hints: String, playtest_on: bool) -> Mode:
	if args.has(Hints.SWITCH_ARG) or env_hints == "1":
		return Mode.PROFILE
	if playtest_on:
		return Mode.OFF
	return Mode.PROFILE


func _ready() -> void:
	name = "UnlockGuide"
	if unlocks == null or mode == Mode.OFF:
		return
	if gate == null:
		gate = get_node_or_null("../../AirportGate") as AirportGate
	if flights == null and gate != null:
		flights = gate.flights
	if flights == null:
		flights = get_node_or_null("../../FlightSim") as FlightSim
	unlocks.tier_changed.connect(_on_tier_changed)
	unlocks.tiers_opened.connect(_on_tiers_opened)
	if gate != null:
		gate.opened.connect(_on_airport_opened)
	if runway != null:
		runway.works_done.connect(_on_works_done)
	if director != null:
		director.major_presented.connect(_on_major_presented)
	if save_game != null:
		save_game.loaded.connect(_on_loaded)


## A guide that leaves the tree while its dialog is open must not leave the
## game paused (the holds also end a hold whose owner leaves).
func _exit_tree() -> void:
	_release_clock()


## True for an unlocked card the player has not hovered or picked yet.
func is_new(tool: BuildMode.Tool) -> bool:
	if mode == Mode.OFF or unlocks == null:
		return false
	var tier := BuildUnlocks.tier_of(tool)
	return tier >= BuildUnlocks.CAFE_TIER and tier <= unlocks.tier() and not unlocks.tool_seen(tool)


## The player hovered or picked the card: it is no longer new, for good.
func mark_seen(tool: BuildMode.Tool) -> void:
	if not is_new(tool):
		return
	unlocks.mark_tool_seen(tool)
	changed.emit()


func is_open() -> bool:
	return _dialog != null


## The open dialog, or null.
func dialog() -> IntroDialogue:
	return _dialog


## Closes the open dialog as Continue would.
func dismiss() -> void:
	if _dialog != null:
		_dialog.dismiss()


## Closes any open or waiting unlock dialog and releases its clock hold.
func close_for_modal() -> void:
	var was_open := _dialog != null
	_free_dialog()
	_release_clock()
	if was_open:
		dialog_changed.emit(false)


## The dialog's text for the listed tiers: one line per family, then the note
## about the clock.
func body_for(tiers: Array) -> String:
	return (
		"\n".join(UnlockFamilies.lines(tiers)) + "\n" + tr("The clock goes on when you close this.")
	)


func _on_tier_changed(_tier: int) -> void:
	changed.emit()


## Tiers opened by play: the dialog shows for the ones not shown before, and
## only those.
func _on_tiers_opened(first: int, last: int) -> void:
	changed.emit()
	var due := []
	for tier in range(first, last + 1):
		if not unlocks.dialog_shown(tier):
			due.append(tier)
			unlocks.mark_dialog_shown(tier)
	if not due.is_empty():
		open_dialog(due)


## Pauses the clock and shows the dialog for `tiers` and `firsts`: at once, or
## queued behind an open Gotta Air call, or replacing an open Terminal Manager
## dialog in place, or waiting while another exclusive dialog has the turn.
func open_dialog(tiers: Array, firsts: Array = []) -> void:
	if _dialog != null and _dialog.speaker() == IntroDialogue.Speaker.GOTTA_AIR:
		_append_unique(_queued_tiers, tiers)
		_append_unique(_queued_firsts, firsts)
		return
	if clock == null or _dialog != null:
		_present_batch(tiers, firsts)
		return
	if clock.holds.has(_hold):
		_append_unique(_waiting_tiers, tiers)
		_append_unique(_waiting_firsts, firsts)
		return
	_waiting_tiers = tiers.duplicate()
	_waiting_firsts = firsts.duplicate()
	_hold = clock.holds.take_turn(self, _on_turn)


func _on_turn() -> void:
	var tiers := _waiting_tiers
	var firsts := _waiting_firsts
	_waiting_tiers = []
	_waiting_firsts = []
	_present_batch(tiers, firsts)


## The airport just opened with its starter contract accepted and issued.
func _on_airport_opened(_tick: int) -> void:
	if unlocks.first_shown(BigFirsts.OPENING):
		return
	_opening_departure = _starter_departure_text()
	_open_first(BigFirsts.OPENING)


## The runway works finished and built a bigger size.
func _on_works_done(_new_size: String) -> void:
	_open_first(BigFirsts.RUNWAY)


## A major incident was announced or offered.
func _on_major_presented(_incident: Dictionary) -> void:
	_open_first(BigFirsts.INCIDENT)


## Shows the dialog of the big first `kind` the first time it happens in this
## game. While this guide's own dialog is open it waits for it to close.
func _open_first(kind: String) -> void:
	if unlocks.first_shown(kind):
		return
	unlocks.mark_first_shown(kind)
	if _dialog != null:
		_append_unique(_queued_firsts, [kind])
		return
	open_dialog([], [kind])


## Keeps Gotta Air's opening call in its own dialog, never mixed with the
## Terminal Manager's tiers or firsts.
func _present_batch(tiers: Array, firsts: Array) -> void:
	if firsts.has(BigFirsts.OPENING) and (not tiers.is_empty() or firsts.size() > 1):
		var rest := firsts.filter(func(k: Variant) -> bool: return k != BigFirsts.OPENING)
		var next_tiers: Array = []
		_append_unique(next_tiers, tiers)
		_append_unique(next_tiers, _queued_tiers)
		var next_firsts: Array = []
		_append_unique(next_firsts, rest)
		_append_unique(next_firsts, _queued_firsts)
		_queued_tiers = next_tiers
		_queued_firsts = next_firsts
		_show_dialog([], [BigFirsts.OPENING])
		return
	_show_dialog(tiers, firsts)


func _append_unique(into: Array, items: Array) -> void:
	for item: Variant in items:
		if not into.has(item):
			into.append(item)


func _starter_departure_text() -> String:
	if flights == null:
		return ""
	var departure_tick := flights.state_start(STARTER_OCCURRENCE, FlightSim.State.PUSHBACK)
	if departure_tick < 0:
		return ""
	var epoch := clock.epoch if clock != null else flights.epoch
	return GameCalendar.clock_text(departure_tick, epoch)


func _departure_for_opening() -> String:
	return _opening_departure if _opening_departure != "" else _starter_departure_text()


## The dialog's title, text and speaker for the tiers and big firsts it holds.
func _words(tiers: Array, firsts: Array) -> Dictionary:
	if tiers.is_empty() and firsts == [BigFirsts.OPENING]:
		return {
			"title": BigFirsts.opening_title_text(),
			"body": BigFirsts.body_for(firsts, _departure_for_opening()),
			"speaker": IntroDialogue.Speaker.GOTTA_AIR,
		}
	var speaker := IntroDialogue.Speaker.TERMINAL_MANAGER
	var title := tr("Your airport has grown")
	if firsts.is_empty():
		return {"title": title, "body": body_for(tiers), "speaker": speaker}
	if tiers.is_empty():
		return {
			"title": BigFirsts.title_text(),
			"body": BigFirsts.body_for(firsts),
			"speaker": speaker,
		}
	var lines := "\n".join(UnlockFamilies.lines(tiers))
	return {
		"title": title,
		"body": lines + "\n" + BigFirsts.body_for(firsts),
		"speaker": speaker,
	}


func _show_dialog(tiers: Array, firsts: Array = []) -> void:
	# A dialog that replaces an open one is the same open: dialog_changed keeps
	# one true and one false, which PassengerHud counts to hold the camera.
	var replacing := _dialog != null
	if replacing:
		_free_dialog()
	_layer = CanvasLayer.new()
	_layer.name = "UnlockLayer"
	_layer.layer = LAYER
	var words := _words(tiers, firsts)
	var speaker: IntroDialogue.Speaker = words["speaker"]
	_dialog = IntroDialogue.new(words["title"], words["body"], BOX_HEIGHT, false, speaker)
	_layer.add_child(_dialog)
	add_child(_layer)
	# Each close names its own layer, so a replaced dialog's layer leaving the
	# tree a frame later cannot close the dialog that replaced it.
	var close := _close_dialog.bind(_layer)
	_dialog.dismissed.connect(_on_dismissed.bind(_layer))
	_dialog.tree_exiting.connect(close)
	_layer.tree_exiting.connect(close)
	phone_ring.emit(tiers.back() if not tiers.is_empty() else NO_TIER)
	if not replacing:
		dialog_changed.emit(true)


## The player closed the dialog on `layer`: any tiers or firsts queued meanwhile
## show next, in place of it and under the same hold on the clock. Releasing the
## hold first would hand the turn to a dialog waiting behind it (the incident
## panel), which would then open before them. Only a close by the player does
## this, never one by leaving the tree.
func _on_dismissed(layer: CanvasLayer) -> void:
	if (
		_dialog == null
		or layer != _layer
		or (_queued_tiers.is_empty() and _queued_firsts.is_empty())
	):
		_close_dialog(layer)
		return
	var tiers := _queued_tiers
	var firsts := _queued_firsts
	_queued_tiers = []
	_queued_firsts = []
	_present_batch(tiers, firsts)


## Closes the dialog shown on `layer`; a layer that is no longer the current
## one (replaced, or already closed) closes nothing. True when it closed one.
func _close_dialog(layer: CanvasLayer) -> bool:
	if _dialog == null or layer != _layer:
		return false
	_free_dialog()
	_release_clock()
	dialog_changed.emit(false)
	return true


## A load replaced the world, clock included: SaveGame.load_world() leaves it
## paused at 1x before it emits `loaded` (decision loading-a-save-always-comes-
## back-paused-at-1x-speed-with-hin), and installing the clock dropped every
## hold. The dialog ends, or stops waiting, and the clock is left as loaded.
func _on_loaded(ok: bool) -> void:
	if not ok:
		return
	var was_open := _dialog != null
	_free_dialog()
	_release_clock()
	if was_open:
		dialog_changed.emit(false)


func _free_dialog() -> void:
	var layer := _layer
	_layer = null
	_dialog = null
	if is_instance_valid(layer) and not layer.is_queued_for_deletion():
		layer.queue_free()


## Ends the dialog's hold, waiting or shown. Nothing is restored: with no hold
## left, the player's own pause and speed apply.
func _release_clock() -> void:
	_waiting_tiers = []
	_waiting_firsts = []
	_queued_tiers = []
	_queued_firsts = []
	_opening_departure = ""
	if is_instance_valid(clock):
		clock.holds.release(_hold)
	_hold = ClockHolds.NONE
