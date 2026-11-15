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
##   in a game (BigFirsts, decision phone-ring-and-help-dialog-also-on-big-
##   firsts-first-runway-u): the runway works finish (Runway.works_done, which a
##   load never emits) and a major incident is presented
##   (IncidentDirector.major_presented). A first shows once per game, kept in
##   BuildUnlocks with the shown tiers; one that comes while this dialog is open
##   waits for it to close. A load drops a first that was waiting.
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
const TITLE_TEXT := "Your airport has grown"
const FOOTER_TEXT := "The clock goes on when you close this."
## The dialog box's height: taller than the intro's, for a line per family.
const BOX_HEIGHT := 400.0

var mode := Mode.OFF
var unlocks: BuildUnlocks
var clock: SimClock
## Optional: a load ends an open dialog.
var save_game: SaveGame
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
## Big firsts that came while this guide's own dialog was open: they show when
## the player closes it.
var _queued_firsts: Array = []


func _ready() -> void:
	name = "UnlockGuide"
	if unlocks == null or mode == Mode.OFF:
		return
	unlocks.tier_changed.connect(_on_tier_changed)
	unlocks.tiers_opened.connect(_on_tiers_opened)
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


## The dialog's text for the listed tiers: one line per family, then the note
## about the clock.
static func body_for(tiers: Array) -> String:
	return "\n".join(UnlockFamilies.lines(tiers)) + "\n" + FOOTER_TEXT


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


## Pauses the clock and shows the dialog for `tiers`: at once, or, while another
## exclusive dialog has the turn (the Offers sheet, the intro), when that one
## closes. Tiers that open while it waits join the same dialog.
func open_dialog(tiers: Array, firsts: Array = []) -> void:
	if clock == null or _dialog != null:
		_show_dialog(tiers, firsts)
		return
	if clock.holds.has(_hold):
		_waiting_tiers.append_array(tiers)
		_waiting_firsts.append_array(firsts)
		return
	_waiting_tiers = tiers.duplicate()
	_waiting_firsts = firsts.duplicate()
	_hold = clock.holds.take_turn(self, _on_turn)


func _on_turn() -> void:
	var tiers := _waiting_tiers
	var firsts := _waiting_firsts
	_waiting_tiers = []
	_waiting_firsts = []
	_show_dialog(tiers, firsts)


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
		_queued_firsts.append(kind)
		return
	open_dialog([], [kind])


## The dialog's title and text for the tiers and big firsts it holds: a dialog
## with a tier is a tier dialog, with the firsts' lines after the families.
func _words(tiers: Array, firsts: Array) -> Dictionary:
	if firsts.is_empty():
		return {"title": TITLE_TEXT, "body": body_for(tiers)}
	if tiers.is_empty():
		return {"title": BigFirsts.TITLE_TEXT, "body": BigFirsts.body_for(firsts)}
	var lines := body_for(tiers).trim_suffix("\n" + FOOTER_TEXT)
	return {"title": TITLE_TEXT, "body": lines + "\n" + BigFirsts.body_for(firsts)}


func _show_dialog(tiers: Array, firsts: Array = []) -> void:
	if _dialog != null:
		_free_dialog()
	_layer = CanvasLayer.new()
	_layer.name = "UnlockLayer"
	_layer.layer = LAYER
	var words := _words(tiers, firsts)
	_dialog = IntroDialogue.new(words["title"], words["body"], BOX_HEIGHT)
	_layer.add_child(_dialog)
	add_child(_layer)
	# Each close names its own layer, so a replaced dialog's layer leaving the
	# tree a frame later cannot close the dialog that replaced it.
	var close := _close_dialog.bind(_layer)
	_dialog.dismissed.connect(_on_dismissed.bind(_layer))
	_dialog.tree_exiting.connect(close)
	_layer.tree_exiting.connect(close)
	phone_ring.emit(tiers.back() if not tiers.is_empty() else NO_TIER)
	dialog_changed.emit(true)


## The player closed the dialog on `layer`: the firsts that came meanwhile show
## next. Only a close by the player does this, never one by leaving the tree.
func _on_dismissed(layer: CanvasLayer) -> void:
	var queued := _queued_firsts.duplicate()
	if _close_dialog(layer) and not queued.is_empty():
		open_dialog([], queued)


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
	_queued_firsts = []
	if is_instance_valid(clock):
		clock.holds.release(_hold)
	_hold = ClockHolds.NONE
