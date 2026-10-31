class_name PlaneView
extends Node3D
## Draws one Toon plane for the flights of one gate: from a sky lead-in before
## APPROACH, through landing, the stand and takeoff, to a climb-out after
## DEPARTED. Every frame it lists the gate's flights that are in the sky window
## at the clock's interpolated time, oldest first, and draws the one at index
## `slot`, so a second PlaneView (slot 1) draws the arriving plane while the one
## before it is still climbing out. Everything comes from the sim's tick, each
## flight's start ticks and the clock's alpha; it keeps nothing between frames
## and never writes back. Past the sun's shadow distance it draws the plane's
## sun silhouette on the ground, so a far plane in the air still reads as
## airborne.

const PLANE_SCENE := preload("res://assets/planes/tp_plane_05a.glb")
## pose_at phases beside the FlightSim states it passes through.
const PHASE_LEAD_IN := -1
const PHASE_CLIMB_OUT := FlightSim.State.DEPARTED
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
## Darkness of the far ground silhouette once the real shadow has faded out.
const FAR_SHADOW_ALPHA := 0.4
## Stencil value the silhouette marks its pixels with.
const FAR_SHADOW_STENCIL := 7
## Lift of the silhouette off the ground, against z-fighting.
const FAR_SHADOW_LIFT := 0.06
## Thickness the projection keeps per metre of height, so the basis inverts.
const FAR_SHADOW_FLATTEN := 0.002

@export var clock: SimClock
@export var sim: FlightSim
@export var airside: Airside
## Casts the shadow the far silhouette stands in for; none draws no silhouette.
@export var sun: DirectionalLight3D
@export var gate := FlightSim.DEFAULT_GATE
## Which of the gate's sighted flights this view draws, oldest first.
@export var slot := 0
## Moves the model so its middle sits on the pose point (the glb origin is near
## the nose end).
@export var model_offset := Vector3(0.0, 0.0, 1.7)
@export var model_yaw_degrees := 0.0

## The flight drawn on the last update_pose(), or "".
var flight_id := ""
## Its pose_at phase on the last update_pose().
var phase := PHASE_LEAD_IN

var _paths: Dictionary = {}
var _far_shadow: Node3D
var _far_material: StandardMaterial3D


func _ready() -> void:
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	add_child(pivot)
	pivot.add_child(_new_model())
	_far_material = StandardMaterial3D.new()
	_far_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_far_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_far_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Each pixel is darkened once, where the flattened wing, body and tail overlap.
	_far_material.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	_far_material.stencil_flags = (
		BaseMaterial3D.STENCIL_FLAG_READ | BaseMaterial3D.STENCIL_FLAG_WRITE
	)
	_far_material.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_NOT_EQUAL
	_far_material.stencil_reference = FAR_SHADOW_STENCIL
	_far_material.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	_far_shadow = Node3D.new()
	_far_shadow.name = "FarShadow"
	_far_shadow.top_level = true
	add_child(_far_shadow)
	var silhouette := _new_model()
	_far_shadow.add_child(silhouette)
	for mesh in silhouette.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = _far_material
		mesh.material_overlay = null
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


func _process(_delta: float) -> void:
	update_pose()


## Places the plane for the sim's tick and the clock's alpha.
func update_pose() -> void:
	var time := maxf(float(sim.tick) - 1.0, 0.0) + clock.alpha
	var shown := sightings(time)
	flight_id = shown[slot]["id"] if slot < shown.size() else ""
	visible = flight_id != ""
	if not visible:
		return
	phase = shown[slot]["phase"]
	transform = shown[slot]["transform"]
	_place_far_shadow()


## The gate's flights in their sky window at sim time `time` (a tick plus the
## clock's alpha), oldest first: {id, phase, transform} each. A departed
## occurrence stays listed by the sim until it is pruned, which is how its
## climb-out is found after flight_at_gate lets it go.
func sightings(time: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in sim.flight_ids():
		if _gate_of(id) != gate:
			continue
		var at := pose_at(starts_of(id), time)
		if not at.is_empty():
			at["id"] = id
			out.append(at)
	return out


## The flight's eleven start ticks.
func starts_of(id: String) -> Array[int]:
	var starts: Array[int] = []
	for state in FlightSim.STATE_COUNT:
		starts.append(sim.state_start(id, state))
	return starts


## Where a flight with `starts` is at sim time `time`: {phase, transform}, or
## {} outside its sky window (before its lead-in, after its climb-out).
func pose_at(starts: Array[int], time: float) -> Dictionary:
	var approach := starts[FlightSim.State.APPROACH]
	var departed := starts[FlightSim.State.DEPARTED]
	if time < approach:
		var track := lead_in_track()
		var speed := lead_in_speed(starts)
		var distance := FlightPose.path_length(track) - speed * (approach - time)
		if speed <= 0.0 or distance < 0.0:
			return {}
		return {"phase": PHASE_LEAD_IN, "transform": FlightPose.lead_in_pose(track, distance)}
	if time >= departed:
		var track := climb_out_track()
		var distance := climb_out_speed(starts) * (time - departed)
		if distance > FlightPose.path_length(track):
			return {}
		return {"phase": PHASE_CLIMB_OUT, "transform": FlightPose.climb_out_pose(track, distance)}
	var state := FlightSim.State.APPROACH
	while state < FlightSim.State.TAKEOFF and time >= starts[state + 1]:
		state += 1
	var moving: int = REST_AFTER.get(state, state)
	var progress := 1.0
	if not REST_AFTER.has(state) and starts[state + 1] > starts[state]:
		progress = (time - starts[state]) / float(starts[state + 1] - starts[state])
	return {
		"phase": state,
		"transform": FlightPose.pose(moving, progress, _path(moving), _entry_dir(moving)),
	}


## Flat metres per tick of the lead-in: the approach's own flat speed, so the
## plane does not speed up or slow down where the two meet.
func lead_in_speed(starts: Array[int]) -> float:
	var ticks := starts[FlightSim.State.LANDING] - starts[FlightSim.State.APPROACH]
	var path := _path(FlightSim.State.APPROACH)
	return FlightPose.flat_speed(FlightSim.State.APPROACH, 0.0, path, ticks)


## Flat metres per tick of the climb-out: the flat speed the takeoff ends at.
func climb_out_speed(starts: Array[int]) -> float:
	var ticks := starts[FlightSim.State.DEPARTED] - starts[FlightSim.State.TAKEOFF]
	var path := _path(FlightSim.State.TAKEOFF)
	return FlightPose.flat_speed(FlightSim.State.TAKEOFF, 1.0, path, ticks)


func lead_in_track() -> PackedVector3Array:
	if not _paths.has(PHASE_LEAD_IN):
		_paths[PHASE_LEAD_IN] = airside.lead_in_track()
	return _paths[PHASE_LEAD_IN]


func climb_out_track() -> PackedVector3Array:
	if not _paths.has(PHASE_CLIMB_OUT):
		_paths[PHASE_CLIMB_OUT] = airside.climb_out_track()
	return _paths[PHASE_CLIMB_OUT]


## Where the sun drops the plane's origin onto the ground (y 0), or the point
## below it when there is no sun to cast it.
func shadow_ground_point() -> Vector3:
	return ground_point_of(global_position)


## Where the sun drops `point` onto the ground (y 0).
func ground_point_of(point: Vector3) -> Vector3:
	if sun == null:
		return Vector3(point.x, 0.0, point.z)
	var on_ground := _ground_projection() * point
	return Vector3(on_ground.x, 0.0, on_ground.z)


## The far silhouette's darkness on the last update_pose(): 0 while the real
## shadow is drawn, rising to FAR_SHADOW_ALPHA past the sun's shadow distance.
func far_shadow_alpha() -> float:
	return _far_material.albedo_color.a if _far_material != null else 0.0


## A one-off flight's gate is not public; FlightSim refuses one at a gate
## outside FlightSim.GATES, which is only DEFAULT_GATE so far. A second gate
## needs FlightSim to say which gate a one-off holds.
func _gate_of(id: String) -> String:
	return sim.contract_of(sim.flight_contract_id(id)).get("gate", FlightSim.DEFAULT_GATE)


func _new_model() -> Node3D:
	var model: Node3D = PLANE_SCENE.instantiate()
	model.position = model_offset
	model.rotation_degrees.y = model_yaw_degrees
	return model


## Projects along the sun's light onto the ground, keeping a sliver of height.
func _ground_projection() -> Transform3D:
	var light := -sun.global_basis.z
	var height_axis := Vector3(-light.x / light.y, FAR_SHADOW_FLATTEN, -light.z / light.y)
	return Transform3D(
		Basis(Vector3.RIGHT, height_axis, Vector3.BACK), Vector3.UP * FAR_SHADOW_LIFT
	)


func _place_far_shadow() -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if sun == null or camera == null or -sun.global_basis.z.y > -0.05:
		_far_shadow.visible = false
		return
	_far_shadow.visible = true
	_far_shadow.global_transform = _ground_projection() * global_transform
	var ground := shadow_ground_point()
	var depth := -(camera.global_transform.affine_inverse() * ground).z
	var far := sun.directional_shadow_max_distance
	var fade := smoothstep(far * sun.directional_shadow_fade_start, far, depth)
	_far_material.albedo_color.a = FAR_SHADOW_ALPHA * fade


func _path(state: int) -> PackedVector3Array:
	if not _paths.has(state):
		_paths[state] = airside.phase_path(state)
	return _paths[state]


func _entry_dir(state: int) -> Vector3:
	if PREVIOUS_MOVE.has(state):
		return FlightPose.exit_dir(_path(PREVIOUS_MOVE[state]))
	var path := _path(state)
	return (path[1] - path[0]).slide(Vector3.UP).normalized()
