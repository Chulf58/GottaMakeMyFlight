class_name PassengerHud
extends CanvasLayer
## The passenger HUD: the flight and its doors countdown, made and missed
## counts, speed buttons, the followed passenger's story, and debug buttons
## (a 300-passenger batch, a starter terminal). Clicking a passenger while no
## build tool is active follows it: the selection is a stable passenger id,
## and the camera follows PassengerViews.follow_anchor, never a pooled node.

const DEBUG_BATCH := 300
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


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-460.0, 12.0)
	panel.custom_minimum_size = Vector2(440.0, 0.0)
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	for label in [_flight_label, _counts_label]:
		label.add_theme_font_size_override("font_size", 22)
		column.add_child(label)
	var speeds := HBoxContainer.new()
	column.add_child(speeds)
	for value in [0, 1, 2, 3]:
		var button := Button.new()
		button.text = "Pause" if value == 0 else "%dx" % value
		button.pressed.connect(press_speed.bind(value))
		speeds.add_child(button)
	var debug := HBoxContainer.new()
	column.add_child(debug)
	var batch := Button.new()
	batch.text = "Spawn %d (debug)" % DEBUG_BATCH
	batch.pressed.connect(press_debug_spawn)
	debug.add_child(batch)
	var starter := Button.new()
	starter.text = "Starter terminal (debug)"
	starter.pressed.connect(press_starter_terminal)
	debug.add_child(starter)
	column.add_child(_seed_label)
	column.add_child(_status_label)
	_follow_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_follow_label.position = Vector2(16.0, -96.0)
	_follow_label.add_theme_font_size_override("font_size", 22)
	add_child(_follow_label)
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


func refresh() -> void:
	_flight_label.text = flight_text()
	_counts_label.text = counts_text()
	_seed_label.text = seed_text()
	_status_label.text = _status
	_follow_label.text = follow_text()


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
	sim.spawn_batch(DEBUG_BATCH, seed)
	print("DEBUG_BATCH spawn %d passengers seed=%d tick=%d" % [DEBUG_BATCH, seed, clock.tick])


## 0 pauses; 1 to 3 run at that speed.
func press_speed(value: int) -> void:
	clock.set_paused(value == 0)
	if value > 0:
		clock.set_speed(value)


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
