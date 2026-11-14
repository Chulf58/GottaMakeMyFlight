class_name PlannerTrack
extends Control
## One gate row's 24-hour strip in the flight planner: a pale lane with a line at
## each hour, and while `now` is set a coral line where the clock stands. The
## bars are buttons the planner puts on top.

const LANE := Color(0.93, 0.9, 0.82, 1.0)
const LINE := Color(0.1, 0.13, 0.26, 0.16)
const NOON_LINE := Color(0.1, 0.13, 0.26, 0.32)
const NOW := Color(0.85, 0.3, 0.27, 1.0)

## The fraction of the day (0 to 1) the clock stands at, or -1 for no marker.
var now := -1.0:
	set(value):
		now = value
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), LANE)
	for hour in range(0, 25):
		var x := size.x * float(hour) / 24.0
		var colour := NOON_LINE if hour % 6 == 0 else LINE
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), colour, 1.0)
	if now >= 0.0 and now <= 1.0:
		var x := size.x * now
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), NOW, 2.0)
