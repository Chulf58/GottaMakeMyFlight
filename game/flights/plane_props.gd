class_name PlaneProps
extends Node3D
## The airside props that go with one drawn plane (board 4c08b8e5, Runway R11;
## article airside-props). PlaneView calls follow() after every update_pose():
## - during PUSHBACK the towbarless tug (pushback_tug.glb) stands with its
##   Mount_NoseGear on the model's nose wheel ground contact, facing the way
##   the plane faces, so it rides the whole pushback and its swing;
## - while the plane stands at its gate (AT_STAND, BOARDING, DOORS_CLOSED) the
##   drawn model's name (its flight's model) is reported to the Airside's
##   AirsideProps, whose bridge docks at that model's door; the report is
##   withdrawn when the plane leaves the stand, hides or leaves the tree.
## Visual only: it reads the drawn model and never the sim.
##
## The nose wheel is found in each model by its mesh names: the meshes named
## like NOSE_GEAR (TP_Plane_03A_Wheel_F, the 04's Wheel_F.L and .R pair, the
## 06's and 07's Wheels_F). Their merged bounds' middle, at their lowest point,
## is the contact (nose_gear_contact()), measured once per model.

const TUG_SCENE := preload("res://assets/airside/props/pushback_tug.glb")
## A nose wheel mesh name: the pack's "_Wheel_F" or "_Wheels_F", with an
## optional .L or .R (which Godot imports as _L, _R).
const NOSE_GEAR := "_Wheels?_F([._][LR])?$"
## The states in which the plane stands at its gate and the bridge docks.
const AT_GATE: Array[int] = [
	FlightSim.State.AT_STAND, FlightSim.State.BOARDING, FlightSim.State.DOORS_CLOSED
]

## Model name -> its nose wheel contact in the model's own space.
static var _contacts: Dictionary = {}

var tug: Node3D
## The Airside this plane's door was last reported to and the key it used, so
## the report is withdrawn when the plane leaves the tree (a freed PlaneView).
var _reported_to: Airside
var _reported_key := 0


func _ready() -> void:
	top_level = true
	tug = TUG_SCENE.instantiate()
	tug.name = "PushbackTug"
	tug.visible = false
	add_child(tug)


func _exit_tree() -> void:
	if is_instance_valid(_reported_to) and is_instance_valid(_reported_to.props):
		_reported_to.props.release_plane(_reported_key)
	_reported_to = null


## Places the props for `model` (the drawn model's root node, `model_name` its
## PlaneModels name) at pose_at phase `phase`, for a view at gate `gate` that
## is on show when `shown`. `airside` takes the bridge reports; null skips them.
## `key` names the reporting view.
func follow(
	shown: bool,
	model: Node3D,
	model_name: String,
	phase: int,
	gate: String,
	airside: Airside,
	key: int
) -> void:
	var pushing := shown and model != null and phase == FlightSim.State.PUSHBACK
	tug.visible = pushing
	if pushing:
		tug.global_transform = tug_transform(
			model.global_transform, nose_gear_contact(model, model_name)
		)
	if airside == null:
		return
	if shown and model != null and AT_GATE.has(phase) and PlaneModels.PLANES.has(model_name):
		airside.props.dock_plane(key, gate, model_name)
		_reported_to = airside
		_reported_key = key
	else:
		airside.props.release_plane(key)
		_reported_to = null


## The tug's transform for a model at `model_xform` whose nose wheel touches
## the ground at `contact` (model space): on the contact, turned only about
## the vertical to the model's facing.
static func tug_transform(model_xform: Transform3D, contact: Vector3) -> Transform3D:
	var ahead := model_xform.basis.z.slide(Vector3.UP).normalized()
	return Transform3D(Basis(Vector3.UP, atan2(ahead.x, ahead.z)), model_xform * contact)


## The nose wheel's ground contact of `model` (an instanced plane, named
## `model_name`) in the model's own space, or Vector3.INF (with an error)
## when no mesh matches NOSE_GEAR.
static func nose_gear_contact(model: Node3D, model_name: String) -> Vector3:
	if _contacts.has(model_name):
		return _contacts[model_name]
	var wheels := nose_gear_bounds(model)
	if wheels.size == Vector3.ZERO:
		push_error("PlaneProps: no nose wheel mesh in '%s'" % model_name)
		return Vector3.INF
	var mid := wheels.get_center()
	_contacts[model_name] = Vector3(mid.x, wheels.position.y, mid.z)
	return _contacts[model_name]


## The merged bounds, in `model`'s own space, of its meshes named like
## NOSE_GEAR; a zero-size AABB when there are none.
static func nose_gear_bounds(model: Node3D) -> AABB:
	var pattern := RegEx.create_from_string(NOSE_GEAR)
	var box := AABB()
	var found := false
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if pattern.search(String(mesh.name)) == null:
			continue
		var part := _to_model(mesh, model) * mesh.get_aabb()
		box = part if not found else box.merge(part)
		found = true
	return box


## `node`'s transform in `model`'s space, by its parents' local transforms, so
## it holds outside the tree.
static func _to_model(node: Node3D, model: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != model:
		if at is Node3D:
			xform = (at as Node3D).transform * xform
		at = at.get_parent()
	return xform
