class_name PlannerBar
extends Button
## One flight's bar on a flight planner row. A plain click is the button's press
## (the planner opens Move to and End); dragging it past Godot's drag threshold
## picks the flight up instead, and the press is dropped. The drag carries
## {contract, day, gate} and shows a small bar in the gate's colour under the
## pointer. A disabled bar (a one-off flight or an ended contract) cannot be
## picked up; clicking it emits disabled_clicked so the planner can explain why.
## A drop over a bar is the drop on its row: the bar hands the check and the
## drop to its PlannerTrack.

signal disabled_clicked

## The contract id, "" for a one-off flight.
var contract := ""
## The day this bar's flight leaves on.
var day := -1
## The gate whose row the bar is on.
var gate := ""


## The drag data a planner bar carries, or {} when `data` is something else.
static func drag_of(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {}
	var dict: Dictionary = data
	if dict.size() != 3 or not dict.has_all(["contract", "day", "gate"]):
		return {}
	return dict


func _gui_input(event: InputEvent) -> void:
	if not disabled:
		return
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		disabled_clicked.emit()
		accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if disabled or contract == "":
		return null
	set_drag_preview(_preview())
	return {"contract": contract, "day": day, "gate": gate}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var track := get_parent() as PlannerTrack
	return track != null and track.can_take(data)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var track := get_parent() as PlannerTrack
	if track != null:
		track.take(data)


## A copy of the bar, in its gate's colour and at its size, that follows the
## pointer. Its look comes from the theme variation like the bar's own.
func _preview() -> Control:
	var copy := Button.new()
	copy.theme = BuildMenu.HUD_THEME
	copy.theme_type_variation = GateColours.variation_of(gate, true)
	copy.text = FlightPlanner.bar_text(self)
	copy.clip_text = true
	copy.alignment = HORIZONTAL_ALIGNMENT_LEFT
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.size = size
	return copy
