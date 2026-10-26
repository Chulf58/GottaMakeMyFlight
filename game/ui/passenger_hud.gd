class_name PassengerHud
extends CanvasLayer
## The passenger HUD. Top-right: elapsed sim time, the flight and its doors
## countdown, made and missed counts, and the speed buttons (Space toggles the
## pause, Shift+1/2/3 set the speed; plain number keys stay the build tool keys).
## Bottom-left: the followed passenger's story, kept left of BuildMenu's
## centre column and growing upward when it wraps. Bottom-right: a collapsed
## Debug panel (a 300-passenger batch, a starter terminal, the batch seed and
## their status). Clicking a passenger while no build tool is active follows
## it: the selection is a stable passenger id, and the camera follows
## PassengerViews.follow_anchor, never a pooled node. When a flight's doors
## close, a dismissible FlightResultPanel opens under the top-right panel:
## made, missed and the main reasons.

const DEBUG_BATCH := 300
## Where the follow text's bottom edge sits, up from the bottom of the screen.
const FOLLOW_BOTTOM := 64.0
const FOLLOW_TOP := 96.0
const SPEED_KEYS := {KEY_1: 1, KEY_2: 2, KEY_3: 3}
## The Debug panel's fixed width; its labels wrap inside it.
const DEBUG_W := 260.0
## The result panel's top edge, below the flight panel and well above the
## build tray.
const RESULT_TOP := 200.0
const STAGE_TEXT := {
	Passenger.Stage.SPAWNED: "Arriving",
	Passenger.Stage.TO_CHECKIN: "Heading to check-in",
	Passenger.Stage.CHECKIN_QUEUE: "Queuing for check-in",
	Passenger.Stage.CHECKIN: "Checking in",
	Passenger.Stage.TO_SECURITY: "Heading to security",
	Passenger.Stage.SECURITY_QUEUE: "Queuing for security",
	Passenger.Stage.SECURITY: "Going through security",
	Passenger.Stage.TO_GATE: "Heading to the gate",
	Passenger.Stage.SITTING_DOWN: "Sitting down",
	Passenger.Stage.SEATED: "Waiting at the gate",
	Passenger.Stage.STANDING: "Standing at the gate",
	Passenger.Stage.STANDING_UP: "Getting up to board",
	Passenger.Stage.TO_EXIT: "Heading to the exit",
	Passenger.Stage.APRON: "Walking to the plane",
	Passenger.Stage.MADE: "Boarded",
	Passenger.Stage.MISSED: "Missed the flight",
}

@export var clock: SimClock
@export var flights: FlightSim
@export var sim: PassengerSim
@export var views: PassengerViews
@export var camera: TycoonCamera
@export var build_mode: BuildMode

var _flight_label := Label.new()
var _counts_label := Label.new()
var _seed_label := Label.new()
var _follow_label := Label.new()
var _status_label := Label.new()
var _status := ""
var _time_label := Label.new()
var _speed_buttons: Array[Button] = []
var _debug_panel := PanelContainer.new()
var _result := FlightResultPanel.new()
## The flight whose doors closed and whose result is not shown yet. The sim
## marks the passengers missed after the doors_closed signal, so the panel
## waits for the next refresh.
var _unreported := ""


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.name = "FlightPanel"
	panel.add_theme_stylebox_override("panel", BuildMenu.panel_style())
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-460.0, 12.0)
	panel.custom_minimum_size = Vector2(440.0, 0.0)
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	for label in [_time_label, _flight_label, _counts_label]:
		label.add_theme_font_size_override("font_size", 22)
		column.add_child(label)
	var speeds := HBoxContainer.new()
	column.add_child(speeds)
	for value in [0, 1, 2, 3]:
		var button := Button.new()
		button.text = "Pause" if value == 0 else "%dx" % value
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(72.0, 36.0)
		BuildMenu.style_button(button)
		if value == 0:
			button.pressed.connect(press_pause_toggle)
		else:
			button.pressed.connect(press_speed.bind(value))
		speeds.add_child(button)
		_speed_buttons.append(button)
	var hint := Label.new()
	hint.text = "Space pause   Shift+1/2/3 speed"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	column.add_child(hint)
	_result.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_result.position = Vector2(-460.0, RESULT_TOP)
	add_child(_result)
	if flights != null:
		flights.doors_closed.connect(_on_doors_closed)
	_build_debug()
	_follow_label.name = "FollowText"
	_follow_label.add_theme_font_size_override("font_size", 22)
	_follow_label.add_theme_constant_override("outline_size", 6)
	_follow_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_follow_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_follow_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_follow_label)
	_fit_follow()
	get_viewport().size_changed.connect(_fit_follow)
	refresh()


func _process(_delta: float) -> void:
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if views == null or camera == null or build_mode == null:
		return
	if build_mode.tool != BuildMode.Tool.NONE:
		return
	views.selected_id = views.pick(camera.get_node("Camera3D") as Camera3D, click.position)
	if views.selected_id != 0:
		camera.follow(views.follow_anchor)
	else:
		camera.stop_follow()


## Space toggles the pause; Shift+1/2/3 set the speed. These run before
## BuildMode's unhandled input, so Shift+1 never also picks the Floor tool.
## A held key's repeats are swallowed without acting again.
func _shortcut_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or clock == null:
		return
	if key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
		return
	if key.physical_keycode == KEY_SPACE and not key.shift_pressed:
		if not key.echo:
			press_pause_toggle()
		get_viewport().set_input_as_handled()
	elif key.shift_pressed and SPEED_KEYS.has(key.physical_keycode):
		if not key.echo:
			press_speed(SPEED_KEYS[key.physical_keycode])
		get_viewport().set_input_as_handled()


func refresh() -> void:
	if _unreported != "":
		show_result_for(_unreported)
		_unreported = ""
	_time_label.text = time_text()
	_flight_label.text = flight_text()
	_counts_label.text = counts_text()
	_seed_label.text = seed_text()
	_seed_label.visible = _seed_label.text != ""
	_status_label.text = _status
	_status_label.visible = _status != ""
	_follow_label.text = follow_text()
	if clock != null:
		for i in _speed_buttons.size():
			var on := clock.paused if i == 0 else not clock.paused and clock.speed == i
			_speed_buttons[i].set_pressed_no_signal(on)


## Elapsed sim time as m:ss.
func time_text() -> String:
	var seconds := clock.tick / SimClock.TICK_RATE
	@warning_ignore("integer_division")
	return "Time %d:%02d" % [seconds / 60, seconds % 60]


func flight_text() -> String:
	var ids := flights.flight_ids()
	if ids.is_empty():
		return "No flights"
	var id := ids[0]
	if flights.is_doors_closed(id):
		return "%s  Doors closed" % id
	var state: String = FlightSim.State.find_key(flights.state_of(id))
	var left := maxi(0, flights.doors_close_tick(id) - clock.tick) / SimClock.TICK_RATE
	@warning_ignore("integer_division")
	return "%s  %s  doors close in %d:%02d" % [id, state.capitalize(), left / 60, left % 60]


func counts_text() -> String:
	return (
		"Made %d   Missed %d   In terminal %d"
		% [sim.made_count(), sim.missed_count(), sim.active_count()]
	)


func seed_text() -> String:
	if sim.last_batch_seed == 0:
		return ""
	return "Debug batch: %d passengers, seed %d" % [DEBUG_BATCH, sim.last_batch_seed]


func status_text() -> String:
	return _status


func follow_text() -> String:
	if views == null or views.selected_id == 0:
		return ""
	var p := sim.get_passenger(views.selected_id)
	if p == null:
		return ""
	var parts := PackedStringArray(["Passenger %d" % p.id, STAGE_TEXT[p.stage], "mood %d" % p.mood])
	var bubble := sim.bubble_text(p)
	if bubble != "":
		parts.append('"%s"' % bubble)
	return "   ".join(parts)


## Spawns the debug batch through normal spawning. The seed comes from the
## cosmetic RNG, so pressing the button leaves the saved sim RNG untouched.
func press_debug_spawn() -> void:
	var seed := randi() + 1
	if not sim.spawn_batch(DEBUG_BATCH, seed):
		_status = "Spawn refused: no flight is open for passengers"
		return
	_status = "Spawned %d passengers" % DEBUG_BATCH
	print("DEBUG_BATCH spawn %d passengers seed=%d tick=%d" % [DEBUG_BATCH, seed, clock.tick])


## Opens the result panel for a flight, from the passengers' recorded fates.
func show_result_for(flight_id: String) -> void:
	_result.show_result(FlightResult.summarize(sim, flight_id))


func dismiss_result() -> void:
	_result.dismiss_result()


func is_result_open() -> bool:
	return _result.visible


func result_text() -> String:
	return _result.result_text()


## 0 pauses; 1 to 3 run at that speed.
func press_speed(value: int) -> void:
	clock.set_paused(value == 0)
	if value > 0:
		clock.set_speed(value)


## Pauses, or resumes at the speed the clock had.
func press_pause_toggle() -> void:
	clock.set_paused(not clock.paused)


func is_debug_open() -> bool:
	return _debug_panel.visible


func set_debug_open(value: bool) -> void:
	_debug_panel.visible = value


## Builds ReferenceTerminal on a pristine build grid (no floor, walls or
## objects), a debug shortcut for what BuildMode's tools can also build. Either
## outcome is shown in the status line; a refusal changes nothing.
func press_starter_terminal() -> void:
	if build_mode == null:
		return
	var grid := build_mode.grid
	if not _is_pristine(grid):
		_status = "Starter terminal needs an empty grid"
		return
	if not ReferenceTerminal.build(grid):
		push_error("PassengerHud: the starter terminal did not fit the grid")
		_status = "Starter terminal failed: it did not fit the grid"
		(build_mode.get_node("BuildView") as BuildView).refresh(grid)
		return
	_status = "Starter terminal built"
	(build_mode.get_node("BuildView") as BuildView).refresh(grid)


## The Debug toggle at the bottom-right corner, with its panel above it.
func _build_debug() -> void:
	var corner := VBoxContainer.new()
	corner.name = "DebugCorner"
	corner.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	corner.offset_left = -16.0
	corner.offset_right = -16.0
	corner.offset_top = -BuildMenu.MARGIN
	corner.offset_bottom = -BuildMenu.MARGIN
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	corner.alignment = BoxContainer.ALIGNMENT_END
	add_child(corner)
	_debug_panel.name = "DebugPanel"
	_debug_panel.add_theme_stylebox_override("panel", BuildMenu.panel_style())
	_debug_panel.visible = false
	_debug_panel.custom_minimum_size = Vector2(DEBUG_W, 0.0)
	corner.add_child(_debug_panel)
	var column := VBoxContainer.new()
	_debug_panel.add_child(column)
	var batch := Button.new()
	batch.text = "Spawn %d passengers" % DEBUG_BATCH
	batch.pressed.connect(press_debug_spawn)
	var starter := Button.new()
	starter.text = "Starter terminal"
	starter.pressed.connect(press_starter_terminal)
	for button in [batch, starter]:
		BuildMenu.style_button(button)
		column.add_child(button)
	for label in [_seed_label, _status_label]:
		label.add_theme_font_size_override("font_size", 14)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(label)
	var toggle := Button.new()
	toggle.name = "DebugToggle"
	toggle.text = "Debug"
	toggle.toggle_mode = true
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	BuildMenu.style_button(toggle)
	toggle.toggled.connect(set_debug_open)
	corner.add_child(toggle)


## Keeps the follow text bottom-left, left of BuildMenu's centre column, with
## its bottom edge fixed so wrapped lines grow upward.
func _fit_follow() -> void:
	var width := (get_viewport().get_visible_rect().size.x - BuildMenu.COLUMN_W) / 2.0 - 28.0
	_follow_label.anchor_left = 0.0
	_follow_label.anchor_right = 0.0
	_follow_label.anchor_top = 1.0
	_follow_label.anchor_bottom = 1.0
	_follow_label.offset_left = 16.0
	_follow_label.offset_right = 16.0 + maxf(width, 160.0)
	_follow_label.offset_top = -FOLLOW_TOP
	_follow_label.offset_bottom = -FOLLOW_BOTTOM
	_follow_label.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _on_doors_closed(flight_id: String) -> void:
	_unreported = flight_id


func _is_pristine(grid: BuildGrid) -> bool:
	if not grid.object_ids().is_empty():
		return false
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			if grid.floor_at(cell) != BuildGrid.FLOOR_NONE:
				return false
			for side in BuildGrid.SIDE_STEP.size():
				if grid.has_wall(cell, side):
					return false
	return true
