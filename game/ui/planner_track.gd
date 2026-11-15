class_name PlannerTrack
extends Control
## One gate row's 24-hour strip in the flight planner: a pale lane with a line at
## each hour, and while `now` is set a coral line where the clock stands. The
## bars are buttons the planner puts on top.
##
## While a bar is dragged the planner tells each row whether it takes the flight:
## a row with a `refusal` is greyed, lane and bars, under a grey wash, and refuses
## the drop; a home row (the bar's own row, or its contract's gate) is not greyed
## and takes no drop either.
## Every drop check over the row, its bars included, emits drag_hovered, so the
## planner can say why a row refuses; a drop emits dropped.

signal drag_hovered(track: PlannerTrack)
signal dropped(track: PlannerTrack, drag: Dictionary)

const LANE := Color(0.93, 0.9, 0.82, 1.0)
const LINE := Color(0.1, 0.13, 0.26, 0.16)
const NOON_LINE := Color(0.1, 0.13, 0.26, 0.32)
const NOW := Color(0.85, 0.3, 0.27, 1.0)
const SHADE := Color(0.42, 0.42, 0.45, 0.62)
const SHADE_NAME := "Shade"

## The gate this row is.
var gate := ""
## The fraction of the day (0 to 1) the clock stands at, or -1 for no marker.
var now := -1.0:
	set(value):
		now = value
		queue_redraw()
## Why the dragged flight cannot go to this gate, in the player's words; "" when
## it can, or when nothing is dragged.
var refusal := "":
	set(value):
		refusal = value
		_shade.visible = refusal != ""
## True while this row is the dragged bar's own row or its contract's gate.
var home := false

var _shade := ColorRect.new()


func _init() -> void:
	_shade.name = SHADE_NAME
	_shade.color = SHADE
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Above the bars, which the planner adds as later children.
	_shade.z_index = 1
	_shade.visible = false
	add_child(_shade)


func is_greyed() -> bool:
	return _shade.visible


## Leaves the drag state: not greyed, not anyone's home row.
func clear_drag() -> void:
	refusal = ""
	home = false


## Whether a drop of `data` lands here; says the row was hovered either way.
func can_take(data: Variant) -> bool:
	var drag := PlannerBar.drag_of(data)
	if drag.is_empty():
		return false
	drag_hovered.emit(self)
	return refusal == "" and not home


func take(data: Variant) -> void:
	if can_take(data):
		dropped.emit(self, PlannerBar.drag_of(data))


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return can_take(data)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	take(data)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), LANE)
	for hour in range(0, 25):
		var x := size.x * float(hour) / 24.0
		var colour := NOON_LINE if hour % 6 == 0 else LINE
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), colour, 1.0)
	if now >= 0.0 and now <= 1.0:
		var x := size.x * now
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), NOW, 2.0)
