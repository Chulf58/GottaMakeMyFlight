class_name UnlockGuide
extends Node
## What the player is told when a build tier opens (decision new-unlock-tier-
## phone-ring-and-a-short-per-family-dialog-onc). Two things:
##
## - A short dialog, the IntroDialogue's portrait and box with one line per
##   family the tier brings (UnlockFamilies). It shows once per tier. It pauses
##   the clock while it is open and gives back the speed the player had when it
##   closes, as the Offers sheet does (decision 64aef33b; OfferPanel.open()).
##   The phone ring is a silent hook for now: `phone_ring` fires as the dialog
##   opens and the audio work (board e612caf3) plays it later.
## - A "New" mark on every unlocked card the player has not hovered or picked
##   yet (is_new()), however many tiers ago it opened. BuildMenu tints them.
##
## What was shown and seen is game state, kept in BuildUnlocks (dialog_shown(),
## tool_seen()) and so in the save's "unlocks" part: a new game starts with none,
## a load restores them. A load opens no dialog (it emits no tiers_opened) and
## ends one that is open, giving the clock back as it was before the dialog. The
## dialog shows for exactly the tiers not shown yet, so a tier skip never shows a
## tier twice. The guide is off (mode OFF: no dialog, no mark) in a probe, a test
## or a PlaytestHook run, like the hints; PassengerHud sets the mode.

## The dialog opened or closed (PassengerHud holds the camera still meanwhile).
signal dialog_changed(open: bool)
## The marks changed: BuildMenu repaints its cards.
signal changed
## The phone ring for a newly opened tier. Nothing plays it yet.
## TODO(audio board e612caf3): play the ring here once the audio work lands.
signal phone_ring(tier: int)

enum Mode { OFF, PROFILE }

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

var _layer: CanvasLayer
var _dialog: IntroDialogue
var _held_paused := false
var _held_speed := 1
var _holding_clock := false


func _ready() -> void:
	name = "UnlockGuide"
	set_process(false)
	if unlocks == null or mode == Mode.OFF:
		return
	unlocks.tier_changed.connect(_on_tier_changed)
	unlocks.tiers_opened.connect(_on_tiers_opened)
	if save_game != null:
		save_game.loaded.connect(_on_loaded)


func _process(_delta: float) -> void:
	if _holding_clock and (not clock.paused or clock.speed != _held_speed):
		_holding_clock = false


## A guide that leaves the tree while its dialog is open must not leave the
## game paused.
func _exit_tree() -> void:
	_restore_clock()


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


func open_dialog(tiers: Array) -> void:
	if _dialog != null:
		_free_dialog()
	_layer = CanvasLayer.new()
	_layer.name = "UnlockLayer"
	_layer.layer = LAYER
	_dialog = IntroDialogue.new(TITLE_TEXT, body_for(tiers), BOX_HEIGHT)
	_layer.add_child(_dialog)
	add_child(_layer)
	_dialog.dismissed.connect(_close_dialog)
	_dialog.tree_exiting.connect(_close_dialog)
	_layer.tree_exiting.connect(_close_dialog)
	if clock != null and not _holding_clock:
		_held_paused = clock.paused
		_held_speed = clock.speed
		clock.set_paused(true)
		_holding_clock = true
		set_process(true)
	phone_ring.emit(tiers.back())
	dialog_changed.emit(true)


func _close_dialog() -> void:
	if _dialog == null:
		return
	_free_dialog()
	_restore_clock()
	dialog_changed.emit(false)


## A load replaced the world, clock included: SaveGame.load_world() leaves it
## paused at 1x before it emits `loaded` (decision loading-a-save-always-comes-
## back-paused-at-1x-speed-with-hin). The dialog ends and its hold is dropped
## without touching the clock.
func _on_loaded(ok: bool) -> void:
	if not ok or _dialog == null:
		return
	_free_dialog()
	set_process(false)
	_holding_clock = false
	dialog_changed.emit(false)


func _free_dialog() -> void:
	var layer := _layer
	_layer = null
	_dialog = null
	if is_instance_valid(layer) and not layer.is_queued_for_deletion():
		layer.queue_free()


## Gives back the paused state the player had, unless they changed the clock
## while the dialog was open.
func _restore_clock() -> void:
	set_process(false)
	if clock == null or not _holding_clock:
		return
	_holding_clock = false
	if not clock.paused or clock.speed != _held_speed:
		return
	clock.set_paused(_held_paused)
