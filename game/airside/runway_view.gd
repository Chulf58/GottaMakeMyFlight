class_name RunwayView
extends Node3D
## Draws the runway at the size FlightSim.runway holds (Runway.build): at scene
## start, on a load and when the works end. It sits on the runway line, so the
## pieces are placed about its own origin (Runway.pieces centres them on x 0).
## The view keeps one child, named for the size it shows, and swaps it when
## Runway.size_changed fires.

@export var flights: FlightSim

var _shown := ""


func _ready() -> void:
	if flights == null:
		push_error("RunwayView: flights must be set, so no runway is drawn")
		return
	flights.runway.size_changed.connect(_show)
	_show(flights.runway.size)


## The size drawn now, "" before the first draw.
func shown_size() -> String:
	return _shown


func _show(size: String) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_shown = ""
	if not Runway.STRIPS.has(size):
		push_error("RunwayView: no runway of size '%s' to draw" % size)
		return
	add_child(Runway.build(size))
	_shown = size
