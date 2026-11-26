class_name UnlockGuide
extends Node
## What the player is told when a build tier opens (decision new-unlock-tier-
## phone-ring-and-a-short-per-family-dialog-onc). Two things:
##
## - A short dialog, the IntroDialogue's portrait and box with a crisp intro beat,
##   per-family chips (UnlockFamilies), and a clock-guidance footer. It shows once
##   per tier. It holds
##   the clock paused while it is open (a hold on SimClock.holds that does not
##   give way to the player, as its text promises), and closing it releases
##   the hold, so the player's own speed applies again unless another hold
##   still pauses the game. It is one of the exclusive dialogs: opened while
##   another has the turn (the Offers sheet), it shows when that one closes.
##   When the call arrives, `phone_ring` fires, `GameAudio` plays `&"phone_ring"`,
##   and `IntroDialogue.PhoneRingCue` rings at bottom-centre before the dialog
##   opens (auto-opening after `RING_DURATION_S`, or early on click / Space /
##   Enter).
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
## only big firsts. Plays GameAudio phone_ring and shows PhoneRingCue when shown.
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
## The dialog box's height: compact two-beat layout with icon chips.
const BOX_HEIGHT := 320.0
## The starter contract's day-0 occurrence issued on the opening tick.
const STARTER_OCCURRENCE := "GMF101-d0"
const FAMILY_ICONS := {
	UnlockFamilies.FOOD: preload("res://assets/ui/icons/food.svg"),
	UnlockFamilies.SECURITY: preload("res://assets/ui/icons/security.svg"),
	UnlockFamilies.BAGGAGE: preload("res://assets/ui/icons/baggage.svg"),
	UnlockFamilies.COMFORT: preload("res://assets/ui/icons/leisure.svg"),
	UnlockFamilies.RUNWAY: preload("res://assets/ui/icons/gates.svg"),
	UnlockFamilies.OTHER: preload("res://assets/ui/icons/templates.svg"),
}
const FAMILY_TINTS := {
	UnlockFamilies.FOOD: Color(0.86, 0.50, 0.18, 1.0),
	UnlockFamilies.SECURITY: Color(0.82, 0.54, 0.18, 1.0),
	UnlockFamilies.BAGGAGE: Color(0.20, 0.56, 0.64, 1.0),
	UnlockFamilies.COMFORT: Color(0.22, 0.58, 0.36, 1.0),
	UnlockFamilies.RUNWAY: Color(0.24, 0.48, 0.78, 1.0),
	UnlockFamilies.OTHER: Color(0.42, 0.46, 0.58, 1.0),
}

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
## Optional: target panels opened by contextual call actions ("Open Offers", "Open Runway").
var offer_panel: OfferPanel
var runway_card: RunwayCard

var _layer: CanvasLayer
var _dialog: IntroDialogue
var _ring_cue: IntroDialogue.PhoneRingCue
var _ringing_tiers: Array = []
var _ringing_firsts: Array = []
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
	_free_ring_cue()
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
	return _is_active()


func is_ringing() -> bool:
	return _ring_cue != null and _ring_cue.is_ringing()


## The open dialog, or null while ringing or closed.
func dialog() -> IntroDialogue:
	return _dialog


## The ringing-phone icon cue on the active unlock layer, or null.
func ring_cue() -> IntroDialogue.PhoneRingCue:
	return _ring_cue


## Answers an incoming ringing cue early, opening the queued dialog box now.
func answer_ring() -> bool:
	if _ring_cue == null or not _ring_cue.is_ringing():
		return false
	_ring_cue.answer()
	return true


## Closes the open dialog as Continue would, or cancels an active ring beat.
func dismiss() -> void:
	if _dialog != null:
		_dialog.dismiss()
	elif _layer != null and _is_active():
		_close_dialog(_layer)


## Closes any open or waiting unlock dialog and releases its clock hold.
func close_for_modal() -> void:
	var was_open := _is_active()
	_free_dialog()
	_release_clock()
	if was_open:
		dialog_changed.emit(false)


## The dialog's crisp intro beat for the listed tiers.
func body_for(_tiers: Array) -> String:
	return tr("New builds unlocked! Pick them up in the build bar below.")


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


func _is_active() -> bool:
	return _dialog != null or _ring_cue != null


func _is_gotta_air_active() -> bool:
	if _dialog != null:
		return _dialog.speaker() == IntroDialogue.Speaker.GOTTA_AIR
	return (
		_ring_cue != null and _ringing_tiers.is_empty() and _ringing_firsts == [BigFirsts.OPENING]
	)


## Pauses the clock and shows the dialog for `tiers` and `firsts`: at once, or
## queued behind an open Gotta Air call, or replacing an open Terminal Manager
## dialog in place, or waiting while another exclusive dialog has the turn.
func open_dialog(tiers: Array, firsts: Array = []) -> void:
	if _is_gotta_air_active():
		_append_unique(_queued_tiers, tiers)
		_append_unique(_queued_firsts, firsts)
		return
	if clock == null or _is_active():
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
	if _is_active():
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


## The dialog's title, beats, chips, footer, action and speaker for the tiers
## and big firsts it holds. Combined batches stay strictly within 1-2 beats.
func _words(tiers: Array, firsts: Array) -> Dictionary:
	var footer := tr("The clock goes on when you close this.")
	if tiers.is_empty() and firsts == [BigFirsts.OPENING]:
		var dep := _departure_for_opening()
		var opening_beats := BigFirsts.beats_for(firsts, dep)
		return {
			"title": BigFirsts.opening_title_text(),
			"body": "\n".join(opening_beats),
			"beats": opening_beats,
			"chips": BigFirsts.chips_for(firsts, dep),
			"footer": footer,
			"speaker": IntroDialogue.Speaker.GOTTA_AIR,
			"action_label": tr("Open Offers"),
			"action_callback": _open_offers,
		}
	var speaker := IntroDialogue.Speaker.TERMINAL_MANAGER
	var title := tr("Your airport has grown")
	if firsts.is_empty():
		var intro := body_for(tiers)
		return {
			"title": title,
			"body": intro,
			"beats": [intro],
			"chips": _family_chips(tiers),
			"footer": footer,
			"speaker": speaker,
		}
	if tiers.is_empty():
		var first_beats := BigFirsts.beats_for(firsts)
		var out := {
			"title": BigFirsts.title_text(),
			"body": "\n".join(first_beats),
			"beats": first_beats,
			"chips": BigFirsts.chips_for(firsts),
			"footer": footer,
			"speaker": speaker,
		}
		if firsts.has(BigFirsts.RUNWAY):
			out["action_label"] = tr("Open Runway")
			out["action_callback"] = _open_runway
		return out
	var second_beat := (
		BigFirsts.beats_for(firsts)[0]
		if firsts.size() == 1
		else BigFirsts.combined_beat_for(firsts)
	)
	var combined_beats: Array[String] = [body_for(tiers)]
	if second_beat != "":
		combined_beats.append(second_beat)
	var combined_chips := _family_chips(tiers)
	combined_chips.append_array(BigFirsts.chips_for(firsts))
	var combined := {
		"title": title,
		"body": "\n".join(combined_beats),
		"beats": combined_beats,
		"chips": combined_chips,
		"footer": footer,
		"speaker": speaker,
	}
	if firsts.has(BigFirsts.RUNWAY):
		combined["action_label"] = tr("Open Runway")
		combined["action_callback"] = _open_runway
	return combined


func _family_chips(tiers: Array) -> Array[Dictionary]:
	var chips: Array[Dictionary] = []
	var words := UnlockFamilies.Words.new()
	var groups := UnlockFamilies.grouped(tiers)
	for family: StringName in groups:
		var pieces := ""
		if family == UnlockFamilies.OTHER:
			pieces = ListWords.join(PackedStringArray(UnlockFamilies._names(groups[family])))
		(
			chips
			. append(
				{
					"icon": FAMILY_ICONS.get(family),
					"label": _family_label(family),
					"tint": FAMILY_TINTS.get(family, Color(0.24, 0.48, 0.78, 1.0)),
					"tooltip": words.line(family, pieces),
				}
			)
		)
	return chips


func _family_label(family: StringName) -> String:
	match family:
		UnlockFamilies.FOOD:
			return tr("Food")
		UnlockFamilies.SECURITY:
			return tr("Security")
		UnlockFamilies.BAGGAGE:
			return tr("Baggage")
		UnlockFamilies.COMFORT:
			return tr("Comfort")
		UnlockFamilies.RUNWAY:
			return tr("Runway")
	return tr("More")


func _open_offers() -> void:
	var panel := (
		offer_panel if is_instance_valid(offer_panel) else get_node_or_null("../../OfferPanel")
		as OfferPanel
	)
	if is_instance_valid(panel):
		panel.open()


func _open_runway() -> void:
	var card := (
		runway_card if is_instance_valid(runway_card) else get_node_or_null("../../RunwayCard")
		as RunwayCard
	)
	if is_instance_valid(card):
		card.open()


func _show_dialog(tiers: Array, firsts: Array = []) -> void:
	# A dialog that replaces an open one is the same open: dialog_changed keeps
	# one true and one false, which PassengerHud counts to hold the camera.
	var had_layer := _layer != null
	var had_dialog := _dialog != null
	if had_layer:
		_free_dialog()
	_layer = CanvasLayer.new()
	_layer.name = "UnlockLayer"
	_layer.layer = LAYER
	add_child(_layer)
	# Each close names its own layer, so a replaced dialog's layer leaving the
	# tree a frame later cannot close the dialog that replaced it.
	_layer.tree_exiting.connect(_close_dialog.bind(_layer))
	if had_dialog:
		_open_dialog_box(_layer, tiers, firsts)
	else:
		_ringing_tiers = tiers.duplicate()
		_ringing_firsts = firsts.duplicate()
		_ring_cue = IntroDialogue.PhoneRingCue.new()
		_layer.add_child(_ring_cue)
		_ring_cue.answered.connect(
			_on_ring_answered.bind(_layer, tiers.duplicate(), firsts.duplicate())
		)
		_ring_cue.start_ring(true, true)
	phone_ring.emit(tiers.back() if not tiers.is_empty() else NO_TIER)
	if not had_layer:
		dialog_changed.emit(true)


func _on_ring_answered(layer: CanvasLayer, tiers: Array, firsts: Array) -> void:
	if layer != _layer or not is_instance_valid(_layer):
		return
	_free_ring_cue()
	_open_dialog_box(_layer, tiers, firsts)


func _open_dialog_box(layer: CanvasLayer, tiers: Array, firsts: Array) -> void:
	var words := _words(tiers, firsts)
	var speaker: IntroDialogue.Speaker = words["speaker"]
	var opts := {
		"beats": words.get("beats", []),
		"chips": words.get("chips", []),
		"footer": words.get("footer", ""),
		"action_label": words.get("action_label", ""),
		"action_callback": words.get("action_callback", Callable()),
	}
	_dialog = IntroDialogue.new(words["title"], words["body"], BOX_HEIGHT, false, speaker, opts)
	layer.add_child(_dialog)
	_dialog.dismissed.connect(_on_dismissed.bind(layer))
	_dialog.tree_exiting.connect(_close_dialog.bind(layer))


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
	if layer == null or layer != _layer or not _is_active():
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
	var was_open := _is_active()
	_free_dialog()
	_release_clock()
	if was_open:
		dialog_changed.emit(false)


func _free_ring_cue() -> void:
	_ringing_tiers = []
	_ringing_firsts = []
	var cue := _ring_cue
	_ring_cue = null
	if is_instance_valid(cue):
		cue.stop_ring()
		if not cue.is_queued_for_deletion():
			cue.queue_free()


func _free_dialog() -> void:
	var layer := _layer
	_layer = null
	_dialog = null
	_free_ring_cue()
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
