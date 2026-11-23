class_name MoodOverlay
extends Node3D
## The queue, mood, congestion and room prestige floor overlay (HUD 5/7,
## decisions hud-steal-list-self-clearing-alert-cards-money-hover-departu
## point 5 and stage-3-steam-1-0-launch-polish-overlays-achievements-autocloud-
## and-po-pass): a key tints the floor under the passengers or inside built
## rooms, with a small legend while it is on. Seven buttons on the legend card
## pick the mode: Mood, Hunger, Toilet, Boredom, Late, Congestion, or Prestige.
## PassengerViews floats a need's icons over the passengers only while a need
## mode is on (shown_need(); decision need-icons-show-only-in-the-mood-overlay-
## need-modes-n-key-removed), the shopping wish bubbles only in Boredom mode
## (shows_wishes()) and the late bubbles only in Late mode (shows_late());
## decision calm-cozy-default-view-quiet-world-detail-on-ask-soft-statio,
## part 3.
## Unoccupied cells (and non-room cells in Prestige mode) stay untinted. View
## only: it reads PassengerSim and BuildGrid and changes nothing in them, and
## it is never saved with a game.
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

## Overlay modes. Modes 0..4 share MoodTint.Mode values; CONGESTION and PRESTIGE
## live on MoodOverlay directly.
enum Mode {
	MOOD = MoodTint.Mode.MOOD,
	HUNGER = MoodTint.Mode.HUNGER,
	TOILET = MoodTint.Mode.TOILET,
	BOREDOM = MoodTint.Mode.BOREDOM,
	LATE = MoodTint.Mode.LATE,
	CONGESTION = 5,
	PRESTIGE = 6,
}

## The input action for the toggle key, bound to M in project.godot.
const ACTION := &"toggle_mood_overlay"
const SETTING_KEY := "mood_overlay"
const WHO := "MoodOverlay"
const SETTING_MODE_KEY := "mood_overlay_mode"
## shown_need() when no need's icons show.
const NO_NEED := -1
## The toggle key, a placeholder in the toggle's caption.
const HOTKEY := "M"
## The mode buttons' node names, indexed by Mode; the node is "Mode" + it.
## The captions the player reads come from _mode_caption().
const MODE_NAMES: Array[String] = [
	"Mood",
	"Hunger",
	"Toilet",
	"Boredom",
	"Late",
	"Congestion",
	"Prestige",
]
## The tint lies this far over the grid's floor height, above the floor tiles.
const LIFT_M := 0.06
## The tint is redrawn when the sim has moved on this many ticks (a quarter
## of a second). A grid edit redraws it on the next frame regardless.
const REFRESH_TICKS := 5
## The legend card's x while the Departures row fits its grid: a GAP right of the
## column's list width, where the Planner toggle ends.
const LEGEND_LEFT := float(HudLayout.MARGIN + HudLayout.LIST_W + HudLayout.GAP)
## Fallback horizontal padding when the panel stylebox has unset content margins.
const LEGEND_FALLBACK_PAD := 24.0
const SWATCH_SIZE := Vector2(12, 12)
const MAX_SWATCHES := 5
## Congestion load weights and ramp (1 pax = 1.0, queue wait +0.5..+2.0, stuck +2.0).
const CONGESTION_SPREAD := 0.25
const CONGESTION_QUEUE_WEIGHT := 0.5
const CONGESTION_WAIT_WEIGHT := 1.5
const CONGESTION_STUCK_WEIGHT := 2.0
const CONGESTION_LIGHT_LOAD := 1.0
const CONGESTION_BUSY_LOAD := 2.5
const CONGESTION_HIGH_LOAD := 4.0
const CONGESTION_LIGHT_COLOR := Color(0.28, 0.78, 0.56)
const CONGESTION_BUSY_COLOR := Color(0.96, 0.72, 0.20)
const CONGESTION_HIGH_COLOR := Color(0.92, 0.30, 0.26)
## Room Prestige Lv. 1..5 color ramp: muted slate -> sage -> teal -> gold-amber -> royal gold.
const PRESTIGE_COLORS: Array[Color] = [
	Color(0.46, 0.54, 0.64),
	Color(0.50, 0.74, 0.54),
	Color(0.16, 0.66, 0.56),
	Color(0.95, 0.68, 0.22),
	Color(1.00, 0.84, 0.16),
]

@export var sim: PassengerSim
## Where the on/off choice and the mode are kept; tests point it at a per-process file.
var settings_path := HudFlagSetting.PATH

var _shown := false
var _mode: int = Mode.MOOD
var _cells := {}
var _last_tick := -1
## True while the grid's edits have not been drawn yet.
var _dirty := false
## True once a sim with a grid is there and the saved choice has been read.
var _active := false
## The grid whose graph_changed and edit_applied this is connected to.
var _watched: BuildGrid
var _tint := MultiMeshInstance3D.new()
var _layer := CanvasLayer.new()
var _toggle := Button.new()
var _legend := Label.new()
var _swatches := HFlowContainer.new()
var _swatch_items: Array[Dictionary] = []
var _mode_flow := HFlowContainer.new()
## The legend's card: bare text is unreadable over the dark ground at the top left.
var _legend_card := PanelContainer.new()
## Holds the legend card right of the Departures row (_place_legend).
var _legend_gap := Control.new()
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


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_retranslate()


func _retranslate() -> void:
	_toggle.text = tr("Mood ({key})").format({"key": HOTKEY})
	_legend.text = _legend_text(_mode)
	for i in _mode_buttons.size():
		_mode_buttons[i].text = _mode_caption(i)
	_apply_swatches()
	if is_inside_tree():
		_fit_legend_width(
			LeftColumn.right_of(get_tree(), LeftColumn.PLANNER_TOGGLE_GROUP, LEGEND_LEFT)
		)
		_legend_card.reset_size()


func _process(_delta: float) -> void:
	_place_legend()
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


## The mode the tint is drawn in (MoodOverlay.Mode / MoodTint.Mode).
func mode() -> int:
	return _mode


## The need (NeedIcons.Need) whose icons PassengerViews shows while the overlay
## is on in a Hunger, Toilet or Boredom mode, else NO_NEED: Mood, Late,
## Congestion and Prestige modes and an overlay that is off show no need icons.
func shown_need() -> int:
	if not _shown:
		return NO_NEED
	match _mode:
		Mode.HUNGER:
			return NeedIcons.Need.HUNGER
		Mode.TOILET:
			return NeedIcons.Need.TOILET
		Mode.BOREDOM:
			return NeedIcons.Need.BOREDOM
	return NO_NEED


## True while the overlay is on in Boredom mode, where every shopping wish
## bubble shows (decision calm-cozy-default-view-quiet-world-detail-on-ask-
## soft-statio, part 3).
func shows_wishes() -> bool:
	return _shown and _mode == Mode.BOREDOM


## True while the overlay is on in Late mode, where every late passenger shows
## its late bubble (MoodTint.is_late()).
func shows_late() -> bool:
	return _shown and _mode == Mode.LATE


## Picks what the tint shows and keeps the choice. The mode buttons come through
## here; it works with the overlay off too, so M reopens at the last mode.
func set_mode(value: int) -> void:
	if value == _mode or not value in Mode.values():
		return
	_mode = value
	_apply_mode()
	if _active:
		HudFlagSetting.save_int(settings_path, SETTING_MODE_KEY, _mode, WHO)
	refresh()


## Cell -> value of the tint now drawn (badness 0..1 for MoodTint modes, load
## >= 0.25 for Congestion, level 1..5 for Prestige): empty while the overlay is off.
func tinted_cells() -> Dictionary:
	return _cells


## Redraws the tint from the sim. A hidden overlay reads nothing.
func refresh() -> void:
	if not _shown or not _active:
		return
	_dirty = false
	_last_tick = sim.tick
	match _mode:
		Mode.CONGESTION:
			_cells = congestion_cells(sim)
		Mode.PRESTIGE:
			_cells = prestige_cells(sim.grid)
		_:
			_cells = MoodTint.cells_for(sim, _mode)
	_redraw()


## Cell -> congestion load (> 0) for occupied floor cells and their wall-clear
## cardinal neighbours: 1.0 per live passenger on floor, +0.5..+2.0 while queuing,
## +2.0 when stuck, with 0.25 spillover to reachable adjacent floor cells.
static func congestion_cells(source: PassengerSim) -> Dictionary:
	var own := {}
	if source == null or source.grid == null:
		return own
	for id in source.passenger_ids():
		var p := source.get_passenger(id)
		if p == null or not MoodTint.on_floor(p):
			continue
		var cell := source.grid.world_to_cell(source.world_position(p))
		own[cell] = float(own.get(cell, 0.0)) + _passenger_congestion_weight(p, source.tick)
	var cells := {}
	for cell: Vector2i in own:
		var load := float(own[cell])
		cells[cell] = float(cells.get(cell, 0.0)) + load
		for step in MoodTint.NEIGHBOURS:
			var side := BuildGrid.SIDE_STEP.find(step)
			if source.grid.has_wall(cell, side):
				continue
			var next := cell + step
			cells[next] = float(cells.get(next, 0.0)) + load * CONGESTION_SPREAD
	for cell: Vector2i in cells.keys():
		if source.grid.floor_at(cell) == BuildGrid.FLOOR_NONE:
			cells.erase(cell)
	return cells


## Cell -> RoomPrestige level (1..5) for every cell belonging to a built room.
## Cells outside rooms stay absent (untinted).
static func prestige_cells(grid: BuildGrid) -> Dictionary:
	var cells := {}
	if grid == null:
		return cells
	for room_id in grid.room_ids():
		var room := grid.get_room(room_id)
		if room.is_empty():
			continue
		var level := clampi(
			int(RoomPrestige.evaluate_room(grid, room_id)["level"]),
			RoomPrestige.MIN_LEVEL,
			RoomPrestige.MAX_LEVEL
		)
		var rect: Rect2i = room["rect"]
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var cell := Vector2i(x, y)
				if grid.room_at(cell) == room_id:
					cells[cell] = float(level)
	return cells


## Color used on the floor MultiMesh for `value` in `target_mode`.
static func color_for(value: float, target_mode: int) -> Color:
	if target_mode == Mode.CONGESTION:
		return _congestion_color(value)
	if target_mode == Mode.PRESTIGE:
		var idx := clampi(int(roundf(value)) - 1, 0, PRESTIGE_COLORS.size() - 1)
		return Color(PRESTIGE_COLORS[idx], MoodTint.ALPHA)
	return MoodTint.color_of(value, target_mode)


static func _passenger_congestion_weight(p: Passenger, tick: int) -> float:
	var weight := 1.0
	if p.stuck != Passenger.Stuck.NONE:
		weight += CONGESTION_STUCK_WEIGHT
	elif p.stage in MoodTint.QUEUE_STAGES:
		weight += (
			CONGESTION_QUEUE_WEIGHT
			+ MoodTint.wait_badness(tick - p.stage_tick) * CONGESTION_WAIT_WEIGHT
		)
	return weight


static func _congestion_color(load: float) -> Color:
	var t := 0.0
	if load > CONGESTION_BUSY_LOAD:
		t = (
			0.5
			+ (
				0.5
				* clampf(
					(load - CONGESTION_BUSY_LOAD) / (CONGESTION_HIGH_LOAD - CONGESTION_BUSY_LOAD),
					0.0,
					1.0
				)
			)
		)
	elif load > CONGESTION_LIGHT_LOAD:
		t = (0.5 * (load - CONGESTION_LIGHT_LOAD) / (CONGESTION_BUSY_LOAD - CONGESTION_LIGHT_LOAD))
	var color := (
		CONGESTION_LIGHT_COLOR.lerp(CONGESTION_BUSY_COLOR, t * 2.0)
		if t < 0.5
		else CONGESTION_BUSY_COLOR.lerp(CONGESTION_HIGH_COLOR, (t - 0.5) * 2.0)
	)
	color.a = MoodTint.ALPHA * clampf(0.35 + 0.65 * (load / CONGESTION_LIGHT_LOAD), 0.35, 1.0)
	return color


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


## Keeps the legend card a GAP right of the Planner toggle, which sits on the
## Departures row the taller card reaches down to, so the card never covers it
## (board T10), and wraps the card contents inside the room left of the right rail.
func _place_legend() -> void:
	var left := LeftColumn.right_of(get_tree(), LeftColumn.PLANNER_TOGGLE_GROUP, LEGEND_LEFT)
	var width := maxf(0.0, left - _toggle.get_global_rect().end.x - 2.0 * HudLayout.GAP)
	if not is_equal_approx(_legend_gap.custom_minimum_size.x, width):
		_legend_gap.custom_minimum_size.x = width
	_fit_legend_width(left)


func _fit_legend_width(legend_left: float) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_w := viewport.get_visible_rect().size.x
	var max_right := viewport_w - float(HudLayout.MARGIN + HudLayout.RAIL_W + HudLayout.GAP)
	var max_card_w := maxf(200.0, max_right - legend_left)
	var max_inner_w := maxf(184.0, max_card_w - _legend_card_pad_x())
	var widest_btn := 0.0
	var buttons_w := 0.0
	for i in _mode_buttons.size():
		var bw := _mode_buttons[i].get_combined_minimum_size().x
		widest_btn = maxf(widest_btn, bw)
		buttons_w += bw + (4.0 if i > 0 else 0.0)
	var flow_w := clampf(buttons_w, minf(widest_btn, max_inner_w), max_inner_w)
	var changed := false
	if not is_equal_approx(_mode_flow.custom_minimum_size.x, flow_w):
		_mode_flow.custom_minimum_size.x = flow_w
		changed = true
	var swatch_w := minf(_swatches_natural_width(), max_inner_w)
	if not is_equal_approx(_swatches.custom_minimum_size.x, swatch_w):
		_swatches.custom_minimum_size.x = swatch_w
		changed = true
	var legend_natural_w := _label_natural_width(_legend)
	var legend_w := minf(legend_natural_w, max_inner_w)
	var want_wrap := (
		TextServer.AUTOWRAP_WORD_SMART
		if legend_natural_w > max_inner_w
		else TextServer.AUTOWRAP_OFF
	)
	if _legend.autowrap_mode != want_wrap:
		_legend.autowrap_mode = want_wrap
		changed = true
	if want_wrap != TextServer.AUTOWRAP_OFF:
		if not is_equal_approx(_legend.custom_minimum_size.x, legend_w):
			_legend.custom_minimum_size.x = legend_w
			changed = true
	elif not is_zero_approx(_legend.custom_minimum_size.x):
		_legend.custom_minimum_size.x = 0.0
		changed = true
	if changed:
		_legend_card.reset_size()


func _legend_card_pad_x() -> float:
	var box := _legend_card.get_theme_stylebox("panel")
	if box == null:
		return LEGEND_FALLBACK_PAD
	var left_pad := box.get_margin(SIDE_LEFT)
	var right_pad := box.get_margin(SIDE_RIGHT)
	if left_pad < 0.0 or right_pad < 0.0:
		return LEGEND_FALLBACK_PAD
	return left_pad + right_pad


func _label_natural_width(label: Label) -> float:
	var font := label.get_theme_font("font")
	if font == null:
		return label.get_combined_minimum_size().x
	var size := label.get_theme_font_size("font_size")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 2.0


func _swatches_natural_width() -> float:
	if not _swatches.visible:
		return 0.0
	var total := 0.0
	var count := 0
	for item: Dictionary in _swatch_items:
		var box := item["box"] as Control
		if not box.visible:
			continue
		var label := item["label"] as Label
		var item_w := SWATCH_SIZE.x + 4.0 + _label_natural_width(label)
		total += item_w + (8.0 if count > 0 else 0.0)
		count += 1
	return total


func _build_controls() -> Control:
	var row := HBoxContainer.new()
	row.name = "MoodOverlayControls"
	row.theme = BuildMenu.HUD_THEME
	row.position = Vector2(HudLayout.MARGIN, LeftColumn.slot_top(LeftColumn.SLOT_MOOD))
	row.add_theme_constant_override("separation", HudLayout.GAP)
	_toggle.name = "MoodToggle"
	_toggle.text = tr("Mood ({key})").format({"key": HOTKEY})
	LeftColumn.size_toggle(_toggle)
	_toggle.add_to_group(LeftColumn.TOGGLE_ROW_GROUP)
	_toggle.set_meta(LeftColumn.META_SLOT, LeftColumn.SLOT_MOOD)
	_toggle.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_toggle.toggle_mode = true
	_toggle.focus_mode = Control.FOCUS_NONE
	row.add_child(_toggle)
	_legend_gap.name = "MoodLegendGap"
	_legend_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend_gap.custom_minimum_size.x = (
		LEGEND_LEFT - HudLayout.MARGIN - HudLayout.TOGGLE_W - 2.0 * HudLayout.GAP
	)
	row.add_child(_legend_gap)
	_legend.name = "MoodLegend"
	_legend.text = _legend_text(_mode)
	_legend.theme_type_variation = &"HudHint"
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card_body := VBoxContainer.new()
	card_body.add_theme_constant_override("separation", 4)
	card_body.add_child(_legend)
	card_body.add_child(_build_swatches())
	card_body.add_child(_build_mode_buttons())
	_apply_swatches()
	_legend_card.name = "MoodLegendCard"
	_legend_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_legend_card.add_child(card_body)
	row.add_child(_legend_card)
	return row


func _build_swatches() -> Control:
	_swatches.name = "MoodLegendSwatches"
	_swatches.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_swatches.add_theme_constant_override("h_separation", 8)
	_swatches.add_theme_constant_override("v_separation", 4)
	for i in MAX_SWATCHES:
		var box := HBoxContainer.new()
		box.name = "Swatch%d" % i
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 4)
		var chip := ColorRect.new()
		chip.name = "Color"
		chip.custom_minimum_size = SWATCH_SIZE
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label := Label.new()
		label.name = "Label"
		label.theme_type_variation = &"HudHint"
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(chip)
		box.add_child(label)
		_swatches.add_child(box)
		_swatch_items.append({"box": box, "chip": chip, "label": label})
	return _swatches


## The small mode buttons under the legend line, wrapping cleanly via HFlowContainer.
func _build_mode_buttons() -> Control:
	_mode_flow.name = "MoodModes"
	_mode_flow.add_theme_constant_override("h_separation", 4)
	_mode_flow.add_theme_constant_override("v_separation", 4)
	var group := ButtonGroup.new()
	var buttons_w := 0.0
	for mode in MODE_NAMES.size():
		var button := Button.new()
		button.name = "Mode" + MODE_NAMES[mode]
		button.text = _mode_caption(mode)
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, HudLayout.CHIP_H)
		button.set_pressed_no_signal(mode == _mode)
		button.toggled.connect(_on_mode_toggled.bind(mode))
		_mode_flow.add_child(button)
		_mode_buttons.append(button)
		buttons_w += button.get_combined_minimum_size().x + (4.0 if mode > 0 else 0.0)
	_mode_flow.custom_minimum_size.x = buttons_w
	return _mode_flow


## Takes the saved choice and starts watching the grid once a sim with a grid
## is there. Until then the button stays disabled and nothing is read or saved.
func _try_activate() -> void:
	_toggle.disabled = sim == null or sim.grid == null
	if _toggle.disabled:
		return
	_active = true
	_watch(sim.grid)
	_shown = HudFlagSetting.load_boot_flag(settings_path, SETTING_KEY, false, WHO)
	var saved := HudFlagSetting.load_boot_int(settings_path, SETTING_MODE_KEY, Mode.MOOD, WHO)
	_mode = saved if saved in Mode.values() else Mode.MOOD
	_apply_mode()
	_apply_shown()
	refresh()


## Marks the overlay dirty on every graph_changed or edit_applied of the grid,
## so edits made while paused (including room/decor edits) draw on the next frame.
func _watch(grid: BuildGrid) -> void:
	if is_instance_valid(_watched):
		if _watched.graph_changed.is_connected(_on_graph_changed):
			_watched.graph_changed.disconnect(_on_graph_changed)
		if _watched.edit_applied.is_connected(_on_edit_applied):
			_watched.edit_applied.disconnect(_on_edit_applied)
	_watched = grid
	_dirty = true
	if _watched != null:
		_watched.graph_changed.connect(_on_graph_changed)
		_watched.edit_applied.connect(_on_edit_applied)


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	_dirty = true


func _on_edit_applied(_edit: BuildEdit, _result: BuildResult) -> void:
	_dirty = true


## A mode button went down (its group lets the one before it up, which is ignored).
func _on_mode_toggled(on: bool, target_mode: int) -> void:
	if on:
		set_mode(target_mode)


## The legend line for `target_mode` (Mode), one whole sentence each.
func _legend_text(target_mode: int) -> String:
	var text := ""
	match target_mode:
		Mode.HUNGER:
			text = tr("green fed, orange hungry, red starving")
		Mode.TOILET:
			text = tr("green fine, orange needs the toilet, red desperate")
		Mode.BOREDOM:
			text = tr("green content, orange bored, red very bored")
		Mode.LATE:
			text = tr("amber where passengers are running late")
		Mode.CONGESTION:
			text = tr("floor congestion: light flow to bottleneck")
		Mode.PRESTIGE:
			text = tr("room prestige level")
		_:
			text = tr("green fine, red waiting long or unhappy")
	return text


## The caption of the button for `target_mode` (Mode).
func _mode_caption(target_mode: int) -> String:
	var text := ""
	match target_mode:
		Mode.HUNGER:
			text = tr("Hunger", "mood overlay mode")
		Mode.TOILET:
			text = tr("Toilet", "mood overlay mode")
		Mode.BOREDOM:
			text = tr("Boredom", "mood overlay mode")
		Mode.LATE:
			text = tr("Late", "mood overlay mode")
		Mode.CONGESTION:
			text = tr("Congestion", "mood overlay mode")
		Mode.PRESTIGE:
			text = tr("Prestige", "mood overlay mode")
		_:
			text = tr("Mood", "mood overlay mode")
	return text


func _congestion_swatch_label(index: int) -> String:
	var text := ""
	match index:
		0:
			text = tr("Light")
		1:
			text = tr("Busy")
		_:
			text = tr("Congested")
	return text


func _prestige_swatch_label(index: int) -> String:
	var text := ""
	match index:
		0:
			text = tr("Lv. 1")
		1:
			text = tr("Lv. 2")
		2:
			text = tr("Lv. 3")
		3:
			text = tr("Lv. 4")
		_:
			text = tr("Lv. 5")
	return text


func _apply_swatches() -> void:
	if _mode == Mode.CONGESTION:
		var colors: Array[Color] = [
			CONGESTION_LIGHT_COLOR, CONGESTION_BUSY_COLOR, CONGESTION_HIGH_COLOR
		]
		for i in MAX_SWATCHES:
			var item := _swatch_items[i]
			var box := item["box"] as Control
			if i < colors.size():
				box.visible = true
				(item["chip"] as ColorRect).color = colors[i]
				(item["label"] as Label).text = _congestion_swatch_label(i)
			else:
				box.visible = false
		_swatches.visible = true
	elif _mode == Mode.PRESTIGE:
		for i in MAX_SWATCHES:
			var item := _swatch_items[i]
			(item["box"] as Control).visible = true
			(item["chip"] as ColorRect).color = PRESTIGE_COLORS[i]
			(item["label"] as Label).text = _prestige_swatch_label(i)
		_swatches.visible = true
	else:
		_swatches.visible = false


func _apply_mode() -> void:
	_legend.text = _legend_text(_mode)
	_apply_swatches()
	for i in _mode_buttons.size():
		_mode_buttons[i].set_pressed_no_signal(i == _mode)
	if is_inside_tree():
		_fit_legend_width(
			LeftColumn.right_of(get_tree(), LeftColumn.PLANNER_TOGGLE_GROUP, LEGEND_LEFT)
		)
		_legend_card.reset_size()


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
		multimesh.set_instance_color(i, color_for(_cells[cell], _mode))
		i += 1
