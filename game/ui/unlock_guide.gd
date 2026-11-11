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
## - A "New" mark on the cards of the newest opened tier (is_new()), kept until
##   the player hovers or picks the card (mark_seen()). BuildMenu tints them.
##
## Both memories live per profile in the shared HUD settings file, as the
## first-time hints' do (HudFlagSetting; keys "unlock_dialog_<tier>" and
## "unlock_seen_<tool>"), never in a save. A load therefore re-shows neither: a
## load emits no tiers_opened, and a tier opened again by replaying an earlier
## save was already shown. The guide is off (mode OFF: no dialog, no mark) in a
## probe, a test or a PlaytestHook run, like the hints; PassengerHud sets the
## mode, and a test sets it with a settings_path of its own.

## The dialog opened or closed (PassengerHud holds the camera still meanwhile).
signal dialog_changed(open: bool)
## The marks changed: BuildMenu repaints its cards.
signal changed
## The phone ring for a newly opened tier. Nothing plays it yet.
## TODO(audio board e612caf3): play the ring here once the audio work lands.
signal phone_ring(tier: int)

enum Mode { OFF, PROFILE }

const WHO := "UnlockGuide"
const DIALOG_PREFIX := "unlock_dialog_"
const SEEN_PREFIX := "unlock_seen_"
## The dialog's canvas layer: with the intro, over the HUD and the build menu.
const LAYER := 10
const TITLE_TEXT := "Your airport has grown"
const FOOTER_TEXT := "The clock goes on when you close this."
## The dialog box's height: taller than the intro's, for a line per family.
const BOX_HEIGHT := 400.0

var mode := Mode.OFF
## Where the memories are kept.
var settings_path := HudFlagSetting.PATH
var unlocks: BuildUnlocks
var clock: SimClock

var _first_new := 0
var _seen: Dictionary = {}
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
	_on_tier_changed(unlocks.tier())


func _process(_delta: float) -> void:
	if _holding_clock and (not clock.paused or clock.speed != _held_speed):
		_holding_clock = false


## A guide that leaves the tree while its dialog is open must not leave the
## game paused.
func _exit_tree() -> void:
	_restore_clock()


## True for a card of the newest opened tier that the player has not hovered
## or picked yet.
func is_new(tool: BuildMode.Tool) -> bool:
	if mode == Mode.OFF or _first_new < BuildUnlocks.CAFE_TIER or unlocks == null:
		return false
	var tier := BuildUnlocks.tier_of(tool)
	return tier >= _first_new and tier <= unlocks.tier() and not _is_seen(tool)


## The player hovered or picked the card: it is no longer new, for good.
func mark_seen(tool: BuildMode.Tool) -> void:
	if not is_new(tool):
		return
	_seen[tool] = true
	HudFlagSetting.save_flag(settings_path, _seen_key(tool), true, WHO)
	changed.emit()


## True once the dialog for `tier` has been shown on this profile.
func dialog_shown(tier: int) -> bool:
	return HudFlagSetting.load_flag(settings_path, DIALOG_PREFIX + str(tier), false, WHO)


func is_open() -> bool:
	return _dialog != null


## The open dialog, or null.
func dialog() -> IntroDialogue:
	return _dialog


## Closes the open dialog as Continue would.
func dismiss() -> void:
	if _dialog != null:
		_dialog.dismiss()


## The dialog's text for tiers `first` to `last`: one line per family, then the
## note about the clock.
static func body_for(first: int, last: int) -> String:
	return "\n".join(UnlockFamilies.lines(first, last)) + "\n" + FOOTER_TEXT


func _on_tier_changed(tier: int) -> void:
	_first_new = tier if tier >= BuildUnlocks.CAFE_TIER else 0
	changed.emit()


## Tiers opened by play: the marks cover all of them, and the dialog shows for
## the ones not shown before.
func _on_tiers_opened(first: int, last: int) -> void:
	_first_new = first
	changed.emit()
	var due := first
	while due <= last and dialog_shown(due):
		due += 1
	if due > last:
		return
	for tier in range(due, last + 1):
		HudFlagSetting.save_flag(settings_path, DIALOG_PREFIX + str(tier), true, WHO)
	_open_dialog(due, last)


func _open_dialog(first: int, last: int) -> void:
	if _dialog != null:
		_free_dialog()
	_layer = CanvasLayer.new()
	_layer.name = "UnlockLayer"
	_layer.layer = LAYER
	_dialog = IntroDialogue.new(TITLE_TEXT, body_for(first, last), BOX_HEIGHT)
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
	phone_ring.emit(last)
	dialog_changed.emit(true)


func _close_dialog() -> void:
	if _dialog == null:
		return
	_free_dialog()
	_restore_clock()
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


func _is_seen(tool: BuildMode.Tool) -> bool:
	if not _seen.has(tool):
		_seen[tool] = HudFlagSetting.load_flag(settings_path, _seen_key(tool), false, WHO)
	return _seen[tool]


static func _seen_key(tool: BuildMode.Tool) -> String:
	return SEEN_PREFIX + String(BuildMode.Tool.find_key(tool))
