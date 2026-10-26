class_name PlaneView
extends Node3D
## Draws one flight's Toon plane. Reads the sim every frame and places the
## plane between the last two ticks with the clock's alpha; it never writes
## back. Hidden before the flight appears and after it departs.

const PLANE_SCENE := preload("res://assets/planes/tp_plane_05a.glb")
## The previous moving state, whose path ends where this one begins.
const PREVIOUS_MOVE := {
	FlightSim.State.LANDING: FlightSim.State.APPROACH,
	FlightSim.State.TAXI_IN: FlightSim.State.LANDING,
	FlightSim.State.PUSHBACK: FlightSim.State.TAXI_IN,
	FlightSim.State.TAXI_OUT: FlightSim.State.PUSHBACK,
	FlightSim.State.TAKEOFF: FlightSim.State.TAXI_OUT,
}
## The moving state a standing state rests at the end of.
const REST_AFTER := {
	FlightSim.State.AT_STAND: FlightSim.State.TAXI_IN,
	FlightSim.State.BOARDING: FlightSim.State.TAXI_IN,
	FlightSim.State.DOORS_CLOSED: FlightSim.State.TAXI_IN,
}

@export var clock: SimClock
@export var sim: FlightSim
@export var airside: Airside
@export var flight_id := FlightSim.DEFAULT_ID
## Moves the model so its middle sits on the pose point (the glb origin is near
## the nose end).
@export var model_offset := Vector3(0.0, 0.0, 1.7)
@export var model_yaw_degrees := 0.0

var _model: Node3D
var _paths: Dictionary = {}


func _ready() -> void:
	_model = PLANE_SCENE.instantiate()
	_model.position = model_offset
	_model.rotation_degrees.y = model_yaw_degrees
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	add_child(pivot)
	pivot.add_child(_model)
	visible = false


func _process(_delta: float) -> void:
	update_pose()


## Places the plane for the sim's current state and the clock's alpha.
func update_pose() -> void:
	var state := sim.state_of(flight_id)
	visible = state > FlightSim.State.SCHEDULED and state < FlightSim.State.DEPARTED
	if not visible:
		return
	var time := maxf(float(sim.tick) - 1.0, 0.0) + clock.alpha
	var moving: int = REST_AFTER.get(state, state)
	var progress := 1.0 if REST_AFTER.has(state) else sim.phase_progress(flight_id, time)
	transform = FlightPose.pose(moving, progress, _path(moving), _entry_dir(moving))


func _path(state: int) -> PackedVector3Array:
	if not _paths.has(state):
		_paths[state] = airside.phase_path(state)
	return _paths[state]


func _entry_dir(state: int) -> Vector3:
	if PREVIOUS_MOVE.has(state):
		return FlightPose.exit_dir(_path(PREVIOUS_MOVE[state]))
	var path := _path(state)
	return (path[1] - path[0]).slide(Vector3.UP).normalized()
