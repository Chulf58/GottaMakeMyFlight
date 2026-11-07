class_name PlaneView
extends Node3D
## Draws one Toon plane for the flights of one gate (FlightSim.flight_gate(),
## so an occurrence issued before its contract moved is drawn at its own
## gate), on that gate's stand paths (PlaneFleet sets the gate): from a sky
## lead-in before
## APPROACH, through landing, the stand and takeoff, to a climb-out after
## DEPARTED. Every frame it lists the gate's flights that are in the sky window
## at the clock's interpolated time, oldest first, and draws the one at index
## `slot`, so a second PlaneView (slot 1) draws the arriving plane while the one
## before it is still climbing out. Everything comes from the sim's tick, each
## flight's start ticks and the clock's alpha; it keeps nothing between frames
## and never writes back. A flight that may have been listed after its full
## lead-in began (a contract's first day, a one-off) flies a short straight-in
## from SCHEDULED instead, entering where no camera can see it. A one-off added
## after its own SCHEDULED tick (FlightSim.add_flight allows past starts; tests
## and debug only) still appears partway along the straight-in. Past the sun's
## shadow distance it draws the plane's
## sun silhouette on the ground, so a far plane in the air still reads as
## airborne.
##
## On the ground (taxi in, at the stand, pushback, taxi out) the plane rides on
## the surface under it: the terminal site's paving (ground_height, y 0.2) on
## the site, the grass and taxiway (y 0) off it, with a PAVING_RAMP_M ramp just
## outside the site's edge (ground_height_at()). Only the height changes; the
## Airside paths, and so the taxi lengths and timings, stay as they are.

## The plane models by PlaneModels.PLANES name. The model drawn for a flight
## comes from its airline and plane class (PlaneClasses.model_for) and is never
## saved; a one-off flight, which has no contract, is drawn as the starter's.
const PLANE_SCENES := {
	"tp_plane_03a": preload("res://assets/planes/tp_plane_03a.glb"),
	"tp_plane_04a": preload("res://assets/planes/tp_plane_04a.glb"),
	"tp_plane_05a": preload("res://assets/planes/tp_plane_05a.glb"),
	"tp_plane_06a": preload("res://assets/planes/tp_plane_06a.glb"),
	"tp_plane_07a": preload("res://assets/planes/tp_plane_07a.glb"),
}
## The terminal site, whose whole grid is paved flat at its ground_height
## (tools/blender/terminal_site/build_terminal_site.py; user ruling plane-guard-
## area-shows-only-in-build-mode-the-site-paving-ex, point 2).
const SITE := preload("res://build/terminal_site.tres")
## How far outside the site's edge the ground rises from y 0 to the paving.
const PAVING_RAMP_M := 4.0
## The moving states whose poses roll on the ground.
const ON_GROUND: Array[int] = [
	FlightSim.State.TAXI_IN, FlightSim.State.PUSHBACK, FlightSim.State.TAXI_OUT
]
## pose_at phases beside the FlightSim states it passes through.
const PHASE_LEAD_IN := -1
const PHASE_CLIMB_OUT := FlightSim.State.DEPARTED
## Cache key of the straight-in track (drawn as PHASE_LEAD_IN).
const PHASE_STRAIGHT_IN := -2
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
@export var model_yaw_degrees := 0.0

## The flight drawn on the last update_pose(), or "".
var flight_id := ""
## The PlaneModels name of the model on show.
var model_name := ""
## Its pose_at phase on the last update_pose().
var phase := PHASE_LEAD_IN

## Phase and sky paths read from the airside, kept while its stands stay
## where they were and the gate is the one they were read for (_paths_stand,
## Airside.stand_moves, _paths_gate).
var _paths: Dictionary = {}
var _paths_stand := 0
var _paths_gate := ""
var _pivot: Node3D
var _far_shadow: Node3D
var _far_material: StandardMaterial3D


func _ready() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
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
	show_model(starter_model())
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
	show_model(model_of(flight_id))
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
		if sim.flight_gate(id) != gate:
			continue
		var at := pose_at(starts_of(id), time, has_full_lead_in(id))
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


## True when the flight was surely listed before its full lead-in starts, so
## the whole lead-in can be drawn. FlightSim keeps no record of when a flight
## was added, so this asks what the timetable guarantees: a contract's later
## days are issued ISSUE_LEAD_TICKS before SCHEDULED. Its first day may be
## accepted as late as its SCHEDULED tick, the starter's included (AirportGate
## searches ahead for a free slot but accepts at the current tick, so a gate
## filled by contracts accepted while closed can push the starter's first day
## to start at the opening). A one-off may be added at any time.
func has_full_lead_in(id: String) -> bool:
	var occurrence := FlightTimetable.parse_occurrence(id)
	if occurrence.is_empty():
		return false
	var first: int = sim.start_days.get(occurrence["contract"], occurrence["day"])
	return occurrence["day"] > first


## Where a flight with `starts` is at sim time `time`: {phase, transform}, or
## {} outside its sky window (before its lead-in, after its climb-out). With
## `full_lead_in` false the arrival is the straight-in, drawn from SCHEDULED.
func pose_at(starts: Array[int], time: float, full_lead_in := true) -> Dictionary:
	var approach := starts[FlightSim.State.APPROACH]
	var departed := starts[FlightSim.State.DEPARTED]
	if time < approach:
		var track := lead_in_track() if full_lead_in else straight_in_track()
		var speed := lead_in_speed(starts)
		var to_go := speed * (approach - time)
		if not full_lead_in:
			to_go = straight_in_to_go(starts, time)
		var distance := FlightPose.path_length(track) - to_go
		if speed <= 0.0 or distance < 0.0 or to_go < 0.0:
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
	var pose := FlightPose.pose(moving, progress, _path(moving), _entry_dir(moving))
	if ON_GROUND.has(moving):
		pose.origin.y += ground_height_at(pose.origin)
	return {"phase": state, "transform": pose}


## The ground's height under `point`: the site's paving height on the site,
## 0 from PAVING_RAMP_M outside its edge, and a straight ramp between.
static func ground_height_at(point: Vector3) -> float:
	var low := Vector2(SITE.grid_origin.x, SITE.grid_origin.z)
	var high := low + Vector2(SITE.grid_size)
	var at := Vector2(point.x, point.z)
	var outside := at.distance_to(at.clamp(low, high))
	return SITE.ground_height * clampf(1.0 - outside / PAVING_RAMP_M, 0.0, 1.0)


## Flat metres per tick of the lead-in: the approach's own flat speed, so the
## plane does not speed up or slow down where the two meet.
func lead_in_speed(starts: Array[int]) -> float:
	var ticks := starts[FlightSim.State.LANDING] - starts[FlightSim.State.APPROACH]
	var path := _path(FlightSim.State.APPROACH)
	return FlightPose.flat_speed(FlightSim.State.APPROACH, 0.0, path, ticks)


## Metres the straight-in still has to fly at `time`, or -1 before SCHEDULED.
## It covers its whole track between SCHEDULED and APPROACH, slowing evenly so
## it meets the approach at the approach's own speed.
func straight_in_to_go(starts: Array[int], time: float) -> float:
	var span := float(starts[FlightSim.State.APPROACH] - starts[FlightSim.State.SCHEDULED])
	var left := float(starts[FlightSim.State.APPROACH]) - time
	if span <= 0.0 or left > span:
		return -1.0
	var speed := lead_in_speed(starts)
	var slowing := (FlightPose.path_length(straight_in_track()) - speed * span) / (span * span)
	return speed * left + slowing * left * left


## Flat metres per tick of the climb-out: the flat speed the takeoff ends at.
func climb_out_speed(starts: Array[int]) -> float:
	var ticks := starts[FlightSim.State.DEPARTED] - starts[FlightSim.State.TAKEOFF]
	var path := _path(FlightSim.State.TAKEOFF)
	return FlightPose.flat_speed(FlightSim.State.TAKEOFF, 1.0, path, ticks)


func lead_in_track() -> PackedVector3Array:
	if not _paths.has(PHASE_LEAD_IN):
		_paths[PHASE_LEAD_IN] = airside.lead_in_track()
	return _paths[PHASE_LEAD_IN]


func straight_in_track() -> PackedVector3Array:
	if not _paths.has(PHASE_STRAIGHT_IN):
		_paths[PHASE_STRAIGHT_IN] = airside.straight_in_track()
	return _paths[PHASE_STRAIGHT_IN]


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


## The model a flight is drawn with: its contract's airline and plane class, or
## the starter's for a one-off flight.
func model_of(id: String) -> String:
	var contract := sim.contract_of(sim.flight_contract_id(id))
	if contract.is_empty():
		return starter_model()
	return PlaneClasses.model_for(contract["airline"], contract["plane_size"])


## The model of the starter contract, which a one-off flight is drawn with.
static func starter_model() -> String:
	var terms := FlightSim.STARTER_TERMS
	return PlaneClasses.model_for(terms["airline"], terms["plane_size"])


## Puts `model` on show, with its silhouette; nothing changes if it already is.
func show_model(model: String) -> void:
	if model == model_name or not PLANE_SCENES.has(model):
		return
	model_name = model
	for child in _pivot.get_children():
		_pivot.remove_child(child)
		child.queue_free()
	for child in _far_shadow.get_children():
		_far_shadow.remove_child(child)
		child.queue_free()
	_pivot.add_child(_new_model())
	var silhouette := _new_model()
	_far_shadow.add_child(silhouette)
	for mesh in silhouette.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = _far_material
		mesh.material_overlay = null
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## One instance of the model on show, its middle on the pose point.
func _new_model() -> Node3D:
	var packed: PackedScene = PLANE_SCENES[model_name]
	var model: Node3D = packed.instantiate()
	model.position = PlaneModels.PLANES[model_name]["model_offset"]
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
	if _paths_stand != airside.stand_moves or _paths_gate != gate:
		_paths.clear()
		_paths_stand = airside.stand_moves
		_paths_gate = gate
	if not _paths.has(state):
		_paths[state] = airside.phase_path(state, gate)
	return _paths[state]


func _entry_dir(state: int) -> Vector3:
	if PREVIOUS_MOVE.has(state):
		return FlightPose.exit_dir(_path(PREVIOUS_MOVE[state]))
	var path := _path(state)
	return (path[1] - path[0]).slide(Vector3.UP).normalized()
