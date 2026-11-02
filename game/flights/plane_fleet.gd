class_name PlaneFleet
extends Node3D
## The pool of plane views (decision gates-technical-design-gate-desks-link-to-
## north-exits-one-st, point 3): every gate with a live flight gets two
## PlaneViews, slot 0 and slot 1, so its arriving plane can show while the one
## before it still climbs out. Before the views draw each frame
## (process_priority), the fleet lists the gates of the live flights in letter
## order and hands the views out in that order, gate by gate, making more views
## when there are more gates; a view left over gets no gate and hides. The
## views it starts with (`views`, main.tscn's PlaneView and PlaneView2) come
## first, so they draw the first gate.
##
## Not guaranteed: a view keeps nothing between frames, so when a gate's
## flights end and the views shift up, a plane may be drawn by another view
## from the next frame on; it looks the same.

const SLOTS := 2

## The plane views to hand out first; the fleet adds its own after them.
@export var views: Array[PlaneView] = []
@export var clock: SimClock
@export var sim: FlightSim
@export var airside: Airside
@export var sun: DirectionalLight3D

## The gates handed out on the last update, in order.
var gates: Array[String] = []


func _ready() -> void:
	process_priority = -1


func _process(_delta: float) -> void:
	update_views()


## Hands the views out to the gates of the live flights.
func update_views() -> void:
	gates = live_gates()
	while views.size() < gates.size() * SLOTS:
		views.append(_new_view())
	for i in views.size():
		var gate_index := floori(float(i) / SLOTS)
		views[i].gate = gates[gate_index] if gate_index < gates.size() else ""
		views[i].slot = i % SLOTS


## The gates the live flights are at, each once, in letter order.
func live_gates() -> Array[String]:
	var out: Array[String] = []
	for id in sim.flight_ids():
		var gate := sim.flight_gate(id)
		if gate != "" and not out.has(gate):
			out.append(gate)
	out.sort()
	return out


func _new_view() -> PlaneView:
	var view := PlaneView.new()
	view.name = "FleetPlane%d" % views.size()
	view.clock = clock
	view.sim = sim
	view.airside = airside
	view.sun = sun
	add_child(view)
	return view
