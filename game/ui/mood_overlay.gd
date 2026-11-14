class_name MoodOverlay
extends Node3D
## The queue and mood floor overlay (HUD 5/7, decision hud-steal-list-self-
## clearing-alert-cards-money-hover-departu, point 5; Two Point Hospital and
## Parkitect have the same toggled overlays): a key tints the floor under the
## passengers from green (fine) through yellow to red (queuing long, unhappy
## or stuck), by MoodTint's mapping, with a small legend while it is on. Five
## buttons on the legend card pick the mode: Mood, or Hunger, Toilet or Boredom,
## which tint the same patches green, orange or red for that need (decision
## crowd-need-display-mood-overlay-gains-hunger-toilet-and-bore), or Late, which
## tints only where late passengers stand, in soft amber. PassengerViews
## floats a need's icons over the passengers only while its mode is on
## (shown_need(); decision need-icons-show-only-in-the-mood-overlay-need-modes-
## n-key-removed), the shopping wish bubbles only in Boredom mode
## (shows_wishes()) and the late bubbles only in Late mode (shows_late());
## decision calm-cozy-default-view-quiet-world-detail-on-ask-soft-statio,
## part 3.
## Nothing is tinted where no passenger stands. View only: it reads the
## PassengerSim and changes nothing in it, and it is never saved with a game.
##
## It is an optional piece with an on/off setting, so the HUD can be rolled
## back if it turns into information overload: a toggle button (always
## visible) and the M key show and hide it, and the choice is kept in the HUD
## settings file under "mood_overlay" (HudFlagSetting), the last mode under
## "mood_overlay_mode". Off is the default:
## the overlay is a view the player asks for. M is free of the build tool keys
## 1 to 0, R, Z, B, Escape, the speed keys (Space, Shift+1/2/3), the camera
## keys (WASD, Q, E, Home) and the save keys (F5, F8).
##
## Like BuildView it draws in world space, so it sits at the world origin.
## While off it does no work. Without a PassengerSim and a grid on it there is
## nothing to read: _ready() reports which one is missing, the button is
## disabled, the key does nothing and nothing is saved. A grid that appears
## later (set after _ready) is accepted at the next frame.

## The input action for the toggle key, bound to M in project.godot.
const ACTION := &"toggle_mood_overlay"
const SETTING_KEY := "mood_overlay"
const WHO := "MoodOverlay"
const SETTING_MODE_KEY := "mood_overlay_mode"
## shown_need() when no need's icons show.
const NO_NEED := -1
## The legend line per mode, indexed by MoodTint.Mode.
const LEGEND_TEXTS: Array[String] = [
	"green fine, red waiting long or unhappy",
	"green fed, orange hungry, red starving",
	"green fine, orange needs the toilet, red desperate",
	"green content, orange bored, red very bored",
	"amber where passengers are running late",
]
## The mode buttons' captions, indexed by MoodTint.Mode; the node is "Mode" + it.
const MODE_NAMES: Array[String] = ["Mood", "Hunger", "Toilet", "Boredom", "Late"]
## The tint lies this far over the grid's floor height, above the floor tiles.
const LIFT_M := 0.06
## The tint is redrawn when the sim has moved on this many ticks (a quarter
## of a second). A grid edit redraws it on the next frame regardless.
const REFRESH_TICKS := 5

@export var sim: PassengerSim
## Where the on/off choice and the mode are kept; tests point it at a per-process file.
var settings_path := HudFlagSetting.PATH

var _shown := false
var _mode := MoodTint.Mode.MOOD
var _cells := {}
var _last_tick := -1
## True while the grid's edits have not been drawn yet.
var _dirty := false
## True once a sim with a grid is there and the saved choice has been read.
var _active := false
## The grid whose graph_changed this is connected to.
var _watched: BuildGrid
var _tint := MultiMeshInstance3D.new()
var _layer := CanvasLayer.new()
var _toggle := Button.new()
var _legend := Label.new()
## The legend's card: bare text is unreadable over the dark ground at the top left.
var _legend_card := PanelContainer.new()
var _mode_buttons: Array[Button] = []


func _init() -> void:
	_tint.name = "MoodTint"
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	_tint.multimesh = multimesh
	_tint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tint)


func _ready() -> void:
	name = "MoodOverlay"
	_layer.name = "MoodOverlayHud"
	_layer.add_child(_build_controls())
	add_child(_layer)
	_toggle.toggled.connect(set_shown)
	if sim == null:
		push_error("%s: sim (PassengerSim) is not set, the overlay is disabled" % WHO)
	elif sim.grid == null:
		push_error("%s: sim has no grid yet, the overlay is disabled until it has one" % WHO)
	_apply_shown()
	_try_activate()


func _process(_delta: float) -> void:
	if not _active:
		_try_activate()
		return
	if sim.grid != _watched:
		_watch(sim.grid)
	if _shown and (_dirty or absi(sim.tick - _last_tick) >= REFRESH_TICKS):
		refresh()


## True while the tint is on.
func is_shown() -> bool:
	return _shown


## Shows or hides the tint and keeps the choice. The toggle button and the key
## both come through here.
func set_shown(value: bool) -> void:
	if not _active:
		_toggle.set_pressed_no_signal(false)
		return
	if value == _shown:
		return
	_shown = value
	_apply_shown()
	HudFlagSetting.save_flag(settings_path, SETTING_KEY, _shown, WHO)
	refresh()


## The mode the tint is drawn in (MoodTint.Mode).
func mode() -> MoodTint.Mode:
	return _mode


## The need (NeedIcons.Need) whose icons PassengerViews shows while the overlay
## is on in a Hunger, Toilet or Boredom mode, else NO_NEED: plain Mood mode and
## an overlay that is off show no need icons.
func shown_need() -> int:
	if not _shown:
		return NO_NEED
	match _mode:
		MoodTint.Mode.HUNGER:
			return NeedIcons.Need.HUNGER
		MoodTint.Mode.TOILET:
			return NeedIcons.Need.TOILET
		MoodTint.Mode.BOREDOM:
			return NeedIcons.Need.BOREDOM
	return NO_NEED


## True while the overlay is on in Boredom mode, where every shopping wish
## bubble shows (decision calm-cozy-default-view-quiet-world-detail-on-ask-
## soft-statio, part 3).
func shows_wishes() -> bool:
	return _shown and _mode == MoodTint.Mode.BOREDOM


## True while the overlay is on in Late mode, where every late passenger shows
## its late bubble (MoodTint.is_late()).
func shows_late() -> bool:
	return _shown and _mode == MoodTint.Mode.LATE


## Picks what the tint shows and keeps the choice. The mode buttons come through
## here; it works with the overlay off too, so M reopens at the last mode.
func set_mode(value: MoodTint.Mode) -> void:
	if value == _mode:
		return
	_mode = value
	_apply_mode()
	if _active:
		HudFlagSetting.save_int(settings_path, SETTING_MODE_KEY, _mode, WHO)
	refresh()


## Cell -> badness of the tint now drawn: empty while the overlay is off.
func tinted_cells() -> Dictionary:
	return _cells


## Redraws the tint from the sim. A hidden overlay reads nothing.
func refresh() -> void:
	if not _shown or not _active:
		return
	_dirty = false
	_last_tick = sim.tick
	_cells = MoodTint.cells_for(sim, _mode)
	_redraw()


## M toggles; a held key's repeats and modified presses are left alone.
func _shortcut_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not _active or key == null or not key.pressed or not event.is_action_pressed(ACTION):
		return
	if key.ctrl_pressed or key.alt_pressed or key.meta_pressed or key.shift_pressed:
		return
	if not key.echo:
		set_shown(not _shown)
	get_viewport().set_input_as_handled()


func _build_controls() -> Control:
	var row := HBoxContainer.new()
	row.name = "MoodOverlayControls"
	row.theme = BuildMenu.HUD_THEME
	row.position = Vector2(HudLayout.MARGIN, LeftColumn.slot_top(LeftColumn.SLOT_MOOD))
	row.add_theme_constant_override("separation", 8)
	_toggle.name = "MoodToggle"
	_toggle.text = "Mood (M)"
	LeftColumn.size_toggle(_toggle)
	_toggle.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_toggle.toggle_mode = true
	_toggle.focus_mode = Control.FOCUS_NONE
	row.add_child(_toggle)
	_legend.name = "MoodLegend"
	_legend.text = LEGEND_TEXTS[_mode]
	_legend.theme_type_variation = &"HudHint"
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card_body := VBoxContainer.new()
	card_body.add_theme_constant_override("separation", 4)
	card_body.add_child(_legend)
	card_body.add_child(_build_mode_buttons())
	_legend_card.name = "MoodLegendCard"
	_legend_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_legend_card.add_child(card_body)
	row.add_child(_legend_card)
	return row


## The small Mood, Hunger, Toilet, Boredom and Late buttons under the legend line.
func _build_mode_buttons() -> Control:
	var buttons := HBoxContainer.new()
	buttons.name = "MoodModes"
	buttons.add_theme_constant_override("separation", 4)
	var group := ButtonGroup.new()
	for mode in MODE_NAMES.size():
		var button := Button.new()
		button.name = "Mode" + MODE_NAMES[mode]
		button.text = MODE_NAMES[mode]
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, HudLayout.CHIP_H)
		button.set_pressed_no_signal(mode == _mode)
		button.toggled.connect(_on_mode_toggled.bind(mode))
		buttons.add_child(button)
		_mode_buttons.append(button)
	return buttons


## Takes the saved choice and starts watching the grid once a sim with a grid
## is there. Until then the button stays disabled and nothing is read or saved.
func _try_activate() -> void:
	_toggle.disabled = sim == null or sim.grid == null
	if _toggle.disabled:
		return
	_active = true
	_watch(sim.grid)
	_shown = HudFlagSetting.load_flag(settings_path, SETTING_KEY, false, WHO)
	var saved := HudFlagSetting.load_int(settings_path, SETTING_MODE_KEY, MoodTint.Mode.MOOD, WHO)
	_mode = saved if saved in MoodTint.Mode.values() else MoodTint.Mode.MOOD
	_apply_mode()
	_apply_shown()
	refresh()


## Marks the overlay dirty on every graph_changed of the grid, so an edit made
## while the sim is paused is drawn on the next frame.
func _watch(grid: BuildGrid) -> void:
	if is_instance_valid(_watched) and _watched.graph_changed.is_connected(_on_graph_changed):
		_watched.graph_changed.disconnect(_on_graph_changed)
	_watched = grid
	_dirty = true
	if _watched != null:
		_watched.graph_changed.connect(_on_graph_changed)


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	_dirty = true


## A mode button went down (its group lets the one before it up, which is ignored).
func _on_mode_toggled(on: bool, mode: MoodTint.Mode) -> void:
	if on:
		set_mode(mode)


func _apply_mode() -> void:
	_legend.text = LEGEND_TEXTS[_mode]
	for i in _mode_buttons.size():
		_mode_buttons[i].set_pressed_no_signal(i == _mode)


func _apply_shown() -> void:
	_tint.visible = _shown
	_legend.visible = _shown
	_legend_card.visible = _shown
	_toggle.set_pressed_no_signal(_shown)
	if not _shown:
		_cells = {}
		_last_tick = -1
		_tint.multimesh.instance_count = 0


func _redraw() -> void:
	var multimesh := _tint.multimesh
	multimesh.instance_count = _cells.size()
	var lift := Vector3(0.0, LIFT_M, 0.0)
	var i := 0
	for cell: Vector2i in _cells:
		multimesh.set_instance_transform(
			i, Transform3D(Basis.IDENTITY, sim.grid.cell_to_world(cell) + lift)
		)
		multimesh.set_instance_color(i, MoodTint.color_of(_cells[cell], _mode))
		i += 1
