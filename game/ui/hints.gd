class_name Hints
extends Node
## The first-time hints (HUD 7/7, decision first-time-hints-above-the-build-bar-
## moment-of-need-per-profile-memory): one small card at a time in the banner
## slot of the top-left column (decision checklist-card-moves-to-the-top-left-
## column-slim-at-304-px-t, LeftColumn), shared with the status banner
## (StaffPanel), which waits while a hint shows. The Hints toggle is the column's
## third button. HintRules says what each hint teaches and when its cause is true.
##
## A hint is due on an opportunity, not a timer: the player opens the build
## category it is about, or its cause has just become true. A player who does
## neither for IDLE_S seconds gets it anyway. The cause must also hold for
## HintRules.HOLD_S, so a flicker shows nothing. A hint counts as seen once it
## shows. Dwell counts only while the card is visible and no modal (the intro,
## the Offers sheet) is open, and nothing is picked while one is.
##
## The seen memory and the on/off choice live per profile in the shared HUD
## settings file (HudFlagSetting; keys "hint_seen_<id>" and "hints"), never in a
## save. The left column holds the on/off toggle (key H) and, in the row under
## it, Reset hints (LeftColumn.SLOT_RESET). Off, hints show nothing and mark nothing seen.
##
## Hints run in a normal launch only. A probe, a test or a PlaytestHook run has
## them off, with no row; the explicit switch (--hints, or GMMF_HINTS=1) turns
## them on with a memory file of their own (ISOLATED_PATH), emptied at start, so
## an onboarding playtest never reads or changes the player's profile.

signal shown(id: StringName)

enum Mode { OFF, PROFILE, ISOLATED }

const PLAYTEST_HOOK := preload("res://debug/playtest_hook.gd")
## The input action for the toggle key, bound to H in project.godot.
const ACTION := &"toggle_hints"
const SETTING_KEY := "hints"
const SEEN_PREFIX := "hint_seen_"
const WHO := "Hints"
const ISOLATED_PATH := "user://hud_settings_hints_isolated.cfg"
const SWITCH_ARG := "--hints"
const SWITCH_ENV := "GMMF_HINTS"
## Seconds after a world starts (or loads) in which nothing is picked.
const GRACE_S := 10.0
## Seconds a hint stays up, and the least it stays once its cause is solved.
const DWELL_S := 12.0
const MIN_SHOW_S := 3.0
## The least seconds between one hint ending and the next showing.
const MIN_GAP_S := 20.0
## Seconds without a build edit or a category opened before a due hint shows
## with no other opportunity.
const IDLE_S := 45.0
## How often the world is read, in seconds.
const READ_EVERY_S := 0.25

## Tests set the mode; a launch works it out in _ready().
var forced_mode := -1
## Where the memory and the setting are kept; empty is the mode's own file.
var settings_path := ""
## The HUD the world and the intro come from.
var hud: PassengerHud
## The node holding BuildMenu, StaffPanel and OfferPanel as children, found by
## name each time because they build themselves after the HUD.
var scene_root: Node
## An extra modal test for tests and probes; true holds the hints back.
var modal := Callable()
## The status banner whose slot a hint takes; found under scene_root when null.
var staff_panel: StaffPanel
## False leaves the card's docking and fade running but stops _process reading the
## world, so a probe drives advance() itself.
var reads_world := true

var _mode := Mode.OFF
var _enabled := true
var _seen := {}
var _shown_id: StringName = &""
var _dwell := 0.0
var _since_end := INF
var _idle := 0.0
var _grace := GRACE_S
var _baselined := false
var _prev: Array[StringName] = []
var _held := {}
## Hint ids whose cause became true and whose hint has not shown yet: an
## opportunity that stays until the cause clears or the hint shows.
var _latched := {}
var _clock := 0.0
var _last_open: Array = []
var _read_acc := 0.0
var _sim: PassengerSim
var _card := PanelContainer.new()
var _caption := Label.new()
var _body := Label.new()
var _row := VBoxContainer.new()
var _toggle := Button.new()
var _reset := Button.new()


## How a launch runs hints: ISOLATED with the explicit switch (in any context),
## PROFILE in a normal launch of the running scene, OFF otherwise (a probe or
## test that builds the scene by hand, any run started with -s / --script even
## when it makes the game scene current, or a PlaytestHook run).
static func mode_for(
	in_current_scene: bool,
	playtest_on: bool,
	script_run: bool,
	user_args: PackedStringArray,
	env_value: String
) -> Mode:
	if user_args.has(SWITCH_ARG) or env_value == "1":
		return Mode.ISOLATED
	if in_current_scene and not playtest_on and not script_run:
		return Mode.PROFILE
	return Mode.OFF


## True when the engine arguments run a script (-s or --script): a probe, a test
## runner or a spike, never the player's launch.
static func launched_by_script(engine_args: PackedStringArray) -> bool:
	return engine_args.has("-s") or engine_args.has("--script")


func _ready() -> void:
	name = "Hints"
	_mode = (
		forced_mode as Mode
		if forced_mode >= 0
		else mode_for(
			_in_current_scene(),
			_playtest_switch_on(),
			launched_by_script(OS.get_cmdline_args()),
			OS.get_cmdline_user_args(),
			OS.get_environment(SWITCH_ENV)
		)
	)
	_build()
	_row.visible = _mode != Mode.OFF
	set_process(_mode != Mode.OFF)
	if _mode == Mode.OFF:
		return
	if _mode == Mode.ISOLATED and settings_path == "":
		DirAccess.remove_absolute(memory_path())
	_load_memory()
	if hud != null and hud.save_game != null:
		hud.save_game.loaded.connect(_on_loaded)


func _exit_tree() -> void:
	_yield_banner(false)


## Where the memory and the setting are kept.
func memory_path() -> String:
	if settings_path != "":
		return settings_path
	return ISOLATED_PATH if _mode == Mode.ISOLATED else HudFlagSetting.PATH


func mode() -> Mode:
	return _mode


func is_enabled() -> bool:
	return _enabled


func is_showing() -> bool:
	return _shown_id != &""


## The id of the hint on screen, or "".
func shown_id() -> StringName:
	return _shown_id


func is_seen(id: StringName) -> bool:
	return _seen.get(id, false)


func card() -> PanelContainer:
	return _card


func body_label() -> Label:
	return _body


func settings_row() -> Control:
	return _row


func toggle_button() -> Button:
	return _toggle


func reset_button() -> Button:
	return _reset


## Turns hints on or off and keeps the choice. Off hides the hint on screen.
func set_enabled(value: bool) -> void:
	_toggle.set_pressed_no_signal(value)
	if value == _enabled:
		return
	_enabled = value
	HudFlagSetting.save_flag(memory_path(), SETTING_KEY, value, WHO)
	if not value:
		_end_hint()


## Forgets every hint seen, in memory and in the file, and drops the one on
## screen, so the next due hint shows at once.
func reset_seen() -> void:
	for id in HintRules.IDS:
		_seen[id] = false
		HudFlagSetting.save_flag(memory_path(), SEEN_PREFIX + id, false, WHO)
	_end_hint()
	_since_end = INF


## The player did something: the inactivity clock starts again.
func note_activity() -> void:
	_idle = 0.0


## A different or reloaded world: nothing on screen, the start grace again and
## every cause read afresh. What was seen stays seen.
func reset_session() -> void:
	_end_hint()
	_grace = GRACE_S
	_baselined = false
	_prev = []
	_held = {}
	_latched = {}
	_idle = 0.0
	_since_end = INF
	_read_acc = 0.0


## Moves the hints on by `delta` seconds of real time for `world` (HintRules.
## read_world()) with the build categories open now by name (HintRules.
## STAFF_CARD for the Staff card). The tests drive this directly.
func advance(delta: float, world: Dictionary, open_names: Array) -> void:
	if _mode == Mode.OFF or not _enabled or _modal():
		return
	if open_names != _last_open:
		if not open_names.is_empty():
			note_activity()
		_last_open = open_names.duplicate()
	_clock += delta
	if _grace > 0.0:
		_grace -= delta
		if _grace > 0.0:
			return
	var causes := HintRules.causes(world)
	if not _baselined:
		_baselined = true
		_prev = causes
		for id in HintRules.IDS:
			_held[id] = 0.0
		return
	_track(causes, delta)
	if is_showing():
		_dwell += delta
		if _dwell >= DWELL_S or (_dwell >= MIN_SHOW_S and not causes.has(_shown_id)):
			_end_hint()
		return
	_since_end += delta
	_idle += delta
	if _since_end < MIN_GAP_S:
		return
	var due := HintRules.pick(causes, _seen, _held, _triggers(open_names))
	if due != &"":
		_show(due)


## The H key turns hints on or off, unless a modifier is held or a modal is open.
func _shortcut_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if _mode == Mode.OFF or key == null or not key.pressed or not event.is_action_pressed(ACTION):
		return
	if key.ctrl_pressed or key.alt_pressed or key.meta_pressed or key.shift_pressed or _modal():
		return
	if not key.echo:
		set_enabled(not _enabled)
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	LeftColumn.follow(_card)
	fade_for(_ghost_rect(), delta)
	if not reads_world:
		return
	var sim := hud.sim if hud != null else null
	if sim != _sim:
		_bind(sim)
	_read_acc += delta
	if sim == null or _read_acc < READ_EVERY_S:
		return
	var step := _read_acc
	_read_acc = 0.0
	var panel := _banner()
	var hiring: Array = []
	if panel != null and panel.staff != null:
		hiring = panel.hiring_hint_roles()
	advance(step, HintRules.read_world(sim, hiring), _open_names())


## Fades the card to the banner's faded opacity while `ghost` (the build ghost
## on screen, empty when none) overlaps it, as the banner does in its slot.
func fade_for(ghost: Rect2, delta: float) -> void:
	var covered := ghost.has_area() and _card.visible and _card.get_global_rect().intersects(ghost)
	var target := StaffPanel.FADED_ALPHA if covered else 1.0
	_card.modulate.a = move_toward(_card.modulate.a, target, delta * StaffPanel.FADE_SPEED)


func _ghost_rect() -> Rect2:
	var menu := _find("BuildMenu") as BuildMenu
	if menu == null or not _card.visible:
		return Rect2()
	return GhostBounds.build_rect(menu.build_mode, get_viewport().get_camera_3d())


## Per hint: how long its cause has held, and whether it just became true.
func _track(causes: Array[StringName], delta: float) -> void:
	for id in HintRules.IDS:
		if causes.has(id):
			if not _prev.has(id):
				_held[id] = 0.0
				# A seen hint is never picked, so latching it would leave a stale
				# opportunity for Reset hints to fire at once.
				if not _seen.get(id, false):
					_latched[id] = true
			_held[id] = float(_held.get(id, 0.0)) + delta
			if _seen.get(id, false):
				_latched.erase(id)
		else:
			_held[id] = 0.0
			_latched.erase(id)
	_prev = causes


## Which hints have an opportunity now: their category is open, their cause has
## become true and not been shown yet (latched, so it survives another hint on
## screen and the gap after it), or the player has been idle for IDLE_S.
func _triggers(open_names: Array) -> Dictionary:
	var out := {}
	for id in HintRules.IDS:
		var category_open := false
		for category in HintRules.categories_for(id):
			category_open = category_open or open_names.has(category)
		out[id] = category_open or _latched.has(id) or _idle >= IDLE_S
	return out


func _show(id: StringName) -> void:
	_shown_id = id
	_latched.erase(id)
	_dwell = 0.0
	_body.text = HintRules.text(id)
	_card.visible = true
	_card.modulate.a = 1.0
	_yield_banner(true)
	_mark_seen(id)
	shown.emit(id)


func _end_hint() -> void:
	if _shown_id == &"":
		return
	_shown_id = &""
	_card.visible = false
	_since_end = 0.0
	_yield_banner(false)


func _mark_seen(id: StringName) -> void:
	_seen[id] = true
	HudFlagSetting.save_flag(memory_path(), SEEN_PREFIX + id, true, WHO)


func _load_memory() -> void:
	var path := memory_path()
	_enabled = HudFlagSetting.load_flag(path, SETTING_KEY, true, WHO)
	_toggle.set_pressed_no_signal(_enabled)
	for id in HintRules.IDS:
		_seen[id] = HudFlagSetting.load_flag(path, SEEN_PREFIX + id, false, WHO)


func _yield_banner(yielded: bool) -> void:
	var panel := _banner()
	if panel != null:
		panel.set_hint_yielded(yielded)


func _banner() -> StaffPanel:
	if staff_panel != null:
		return staff_panel if is_instance_valid(staff_panel) else null
	return _find("StaffPanel") as StaffPanel


## True while the intro, the Offers sheet or an extra modal is open.
func _modal() -> bool:
	if modal.is_valid() and modal.call():
		return true
	if hud != null and hud.intro() != null:
		return true
	var offers := _find("OfferPanel") as OfferPanel
	return offers != null and offers.is_open()


func _open_names() -> Array:
	var names := []
	var menu := _find("BuildMenu") as BuildMenu
	if menu == null:
		return names
	var open := menu.open_category()
	if open != BuildMenu.NO_CATEGORY:
		names.append(BuildMenu.CATEGORIES[open]["name"])
	if menu.staff_open:
		names.append(HintRules.STAFF_CARD)
	return names


func _find(node_name: String) -> Node:
	if scene_root == null:
		return null
	var node := scene_root.get_node_or_null(node_name)
	return node if node != null and node.is_node_ready() else null


## Follows `sim`: a different sim is a different world, and a build edit is
## player activity.
func _bind(sim: PassengerSim) -> void:
	if _sim != null and is_instance_valid(_sim) and _sim.grid != null:
		_sim.grid.edit_applied.disconnect(_on_edit)
	_sim = sim
	reset_session()
	if _sim != null and _sim.grid != null:
		_sim.grid.edit_applied.connect(_on_edit)


func _on_edit(_edit: BuildEdit, _result: BuildResult) -> void:
	note_activity()


func _on_loaded(ok: bool) -> void:
	if ok:
		reset_session()


func _in_current_scene() -> bool:
	var current := get_tree().current_scene
	return current != null and (current == self or current.is_ancestor_of(self))


func _playtest_switch_on() -> bool:
	return PLAYTEST_HOOK.wants_enabled(
		true,
		OS.get_cmdline_user_args(),
		ProjectSettings.get_setting(PLAYTEST_HOOK.SETTING, false),
		OS.get_environment(PLAYTEST_HOOK.ENV)
	)


func _build() -> void:
	_card.name = "HintCard"
	_card.theme = BuildMenu.HUD_THEME
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	add_child(_card)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(column)
	_caption.name = "HintCaption"
	_caption.text = "Hint (H turns hints off)"
	_caption.theme_type_variation = &"HudHint"
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_caption)
	_body.name = "HintText"
	_body.theme_type_variation = &"HudAttentionText"
	_body.add_theme_font_size_override("font_size", HudLayout.CAPTION)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_body)
	LeftColumn.dock_card(_card)
	_row.name = "HintsControls"
	_row.theme = BuildMenu.HUD_THEME
	_row.position = Vector2(HudLayout.MARGIN, LeftColumn.slot_top(LeftColumn.SLOT_HINTS))
	_row.add_theme_constant_override("separation", HudLayout.GAP)
	add_child(_row)
	_toggle.name = "HintsToggle"
	_toggle.text = "Hints (H)"
	LeftColumn.size_toggle(_toggle)
	_toggle.toggle_mode = true
	_toggle.button_pressed = true
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.toggled.connect(set_enabled)
	_row.add_child(_toggle)
	_reset.name = "HintsReset"
	_reset.text = "Reset hints"
	LeftColumn.size_toggle(_reset)
	_reset.focus_mode = Control.FOCUS_NONE
	_reset.pressed.connect(reset_seen)
	_row.add_child(_reset)
