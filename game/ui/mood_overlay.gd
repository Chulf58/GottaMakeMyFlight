class_name MoodOverlay
extends Node3D
## The queue and mood floor overlay (HUD 5/7, decision hud-steal-list-self-
## clearing-alert-cards-money-hover-departu, point 5; Two Point Hospital and
## Parkitect have the same toggled overlays): a key tints the floor under the
## passengers from green (fine) through yellow to red (queuing long, unhappy
## or stuck), by MoodTint's mapping, with a small legend while it is on.
## Nothing is tinted where no passenger stands. View only: it reads the
## PassengerSim and changes nothing in it, and it is never saved with a game.
##
## It is an optional piece with an on/off setting, so the HUD can be rolled
## back if it turns into information overload: a toggle button (always
## visible) and the M key show and hide it, and the choice is kept in the HUD
## settings file under "mood_overlay" (HudFlagSetting). Off is the default:
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
const LEGEND_TEXT := "green fine, red waiting long or unhappy"
## The tint lies this far over the grid's floor height, above the floor tiles.
const LIFT_M := 0.06
## The tint is redrawn when the sim has moved on this many ticks (a quarter
## of a second). A grid edit redraws it on the next frame regardless.
const REFRESH_TICKS := 5
const BUTTON_LEFT := 16.0
const BUTTON_TOP := 292.0

@export var sim: PassengerSim
## Where the on/off choice is kept; tests point it at a per-process file.
var settings_path := HudFlagSetting.PATH

var _shown := false
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


## Cell -> badness of the tint now drawn: empty while the overlay is off.
func tinted_cells() -> Dictionary:
	return _cells


## Redraws the tint from the sim. A hidden overlay reads nothing.
func refresh() -> void:
	if not _shown or not _active:
		return
	_dirty = false
	_last_tick = sim.tick
	_cells = MoodTint.cells_for(sim)
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
	row.position = Vector2(BUTTON_LEFT, BUTTON_TOP)
	row.add_theme_constant_override("separation", 8)
	_toggle.name = "MoodToggle"
	_toggle.text = "Mood (M)"
	_toggle.toggle_mode = true
	_toggle.focus_mode = Control.FOCUS_NONE
	row.add_child(_toggle)
	_legend.name = "MoodLegend"
	_legend.text = LEGEND_TEXT
	_legend.theme_type_variation = &"HudHint"
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_legend)
	return row


## Takes the saved choice and starts watching the grid once a sim with a grid
## is there. Until then the button stays disabled and nothing is read or saved.
func _try_activate() -> void:
	_toggle.disabled = sim == null or sim.grid == null
	if _toggle.disabled:
		return
	_active = true
	_watch(sim.grid)
	_shown = HudFlagSetting.load_flag(settings_path, SETTING_KEY, false, WHO)
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


func _apply_shown() -> void:
	_tint.visible = _shown
	_legend.visible = _shown
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
		multimesh.set_instance_color(i, MoodTint.color_of(_cells[cell]))
		i += 1
