class_name TycoonCamera
extends Node3D
## Free tycoon camera. The rig sits on the ground at the focus point and yaws;
## the child Camera3D orbits it at a clamped distance. The pitch follows the
## distance: steep and wide when far out, low and close in. WASD or a
## middle-mouse drag pans, Q/E or a right-mouse drag rotates, the wheel zooms,
## Home glides back to the start view. `glide_to` and `follow` move the focus
## from code; any manual pan cancels both.

## Closest and farthest zoom, in metres from the focus point.
@export var min_distance := 6.0
@export var max_distance := 300.0
## Pitch at the closest and the farthest zoom.
@export var near_pitch_degrees := 35.0
@export var far_pitch_degrees := 65.0
## Pan speed in focus-distance units per second at distance 1.
@export var key_pan_speed := 0.6
@export var drag_pan_speed := 0.0016
@export var key_rotate_speed := 1.6
@export var drag_rotate_speed := 0.005
@export var zoom_factor := 1.12
## Exponential catch-up rates per second for zoom, glide and follow.
@export var zoom_rate := 10.0
@export var glide_rate := 5.0
@export var follow_rate := 6.0
## Half the size of the square the focus point stays inside. The default
## covers the whole airport: the runway at z = -200 runs x = -192 to 192.
@export var bounds_half_extent := 260.0
## The start view, on the build area, and where Home returns to.
@export var home_position := Vector3.ZERO
@export var home_distance := 80.0
@export var home_yaw := 0.0

var yaw := 0.0
## The distance the wheel is zooming toward; `distance` catches up to it.
var target_distance := 80.0
## The current distance. Setting it jumps there with no easing.
var distance: float:
	get:
		return _distance
	set(value):
		_distance = clampf(value, min_distance, max_distance)
		target_distance = _distance

var _distance := 80.0
var _follow_target: Node3D
var _gliding := false
var _glide_position := Vector3.ZERO
var _glide_yaw := NAN

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	position = home_position
	yaw = home_yaw
	distance = home_distance
	_apply()


func _process(delta: float) -> void:
	var move := Input.get_vector("cam_left", "cam_right", "cam_forward", "cam_back")
	if move != Vector2.ZERO:
		pan(move * key_pan_speed * delta)
	var turn := Input.get_axis("cam_rotate_left", "cam_rotate_right")
	if turn != 0.0:
		rotate_yaw(turn * key_rotate_speed * delta)
	_step_focus(delta)
	_step_distance(delta)
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_home"):
		go_home()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(1.0 / zoom_factor)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(zoom_factor)
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			pan(-event.relative * drag_pan_speed)
		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			rotate_yaw(-event.relative.x * drag_rotate_speed)


## Pitch in degrees for a zoom distance. Smoothstep on the log of the distance,
## so each wheel notch changes the tilt by the same share and the curve is flat
## at both ends: `near_pitch_degrees` at `min_distance`, `far_pitch_degrees` at
## `max_distance`, and never steeper or lower than those.
func pitch_for_distance(from_distance: float) -> float:
	var t := inverse_lerp(log(min_distance), log(max_distance), log(from_distance))
	return lerpf(near_pitch_degrees, far_pitch_degrees, smoothstep(0.0, 1.0, t))


## Moves the focus across the ground. `amount` is in the rig's own right and
## back axes (x right, y back) and scales with the zoom distance. A manual pan,
## so it cancels any follow and glide.
func pan(amount: Vector2) -> void:
	stop_follow()
	_gliding = false
	var step := global_transform.basis * Vector3(amount.x, 0.0, amount.y) * _distance
	position = _clamp_to_bounds(position + step)


func rotate_yaw(radians: float) -> void:
	yaw = wrapf(yaw + radians, -PI, PI)
	_apply()


## Multiplies the target distance by `factor` and clamps it. The distance eases
## toward it over the next frames.
func zoom(factor: float) -> void:
	target_distance = clampf(target_distance * factor, min_distance, max_distance)
	_apply()


## Glides the focus to `world_point` (its height is ignored), and the distance
## to `to_distance` unless that is negative. Cancels any follow.
func glide_to(world_point: Vector3, to_distance := -1.0) -> void:
	_begin_glide(world_point, to_distance, NAN)


## Glides back to the start view: position, distance and yaw.
func go_home() -> void:
	_begin_glide(home_position, home_distance, home_yaw)


## Keeps the focus on `node` until a manual pan, `glide_to`, `go_home` or
## `stop_follow`, or until the node is freed.
func follow(node: Node3D) -> void:
	_gliding = false
	_follow_target = node


func stop_follow() -> void:
	_follow_target = null


func is_following() -> bool:
	return _follow_target != null


func is_gliding() -> bool:
	return _gliding


func _begin_glide(world_point: Vector3, to_distance: float, to_yaw: float) -> void:
	stop_follow()
	_gliding = true
	_glide_position = _clamp_to_bounds(Vector3(world_point.x, 0.0, world_point.z))
	_glide_yaw = to_yaw
	if to_distance >= 0.0:
		target_distance = clampf(to_distance, min_distance, max_distance)


func _clamp_to_bounds(point: Vector3) -> Vector3:
	return Vector3(
		clampf(point.x, -bounds_half_extent, bounds_half_extent),
		0.0,
		clampf(point.z, -bounds_half_extent, bounds_half_extent)
	)


func _step_focus(delta: float) -> void:
	if _follow_target != null:
		if not is_instance_valid(_follow_target):
			_follow_target = null
			return
		var seek := _clamp_to_bounds(_follow_target.global_position)
		position = position.lerp(seek, 1.0 - exp(-follow_rate * delta))
	elif _gliding:
		var blend := 1.0 - exp(-glide_rate * delta)
		position = position.lerp(_glide_position, blend)
		var yaw_done := true
		if not is_nan(_glide_yaw):
			yaw = wrapf(lerp_angle(yaw, _glide_yaw, blend), -PI, PI)
			yaw_done = absf(angle_difference(yaw, _glide_yaw)) < 0.001
		var distance_done := absf(_distance - target_distance) < 0.05
		if position.distance_to(_glide_position) < 0.02 and yaw_done and distance_done:
			position = _glide_position
			if not is_nan(_glide_yaw):
				yaw = _glide_yaw
			_distance = target_distance
			_gliding = false


func _step_distance(delta: float) -> void:
	if is_equal_approx(_distance, target_distance):
		_distance = target_distance
		return
	_distance = lerpf(_distance, target_distance, 1.0 - exp(-zoom_rate * delta))


func _apply() -> void:
	rotation.y = yaw
	var pitch := deg_to_rad(pitch_for_distance(_distance))
	_camera.position = Vector3(0.0, _distance * sin(pitch), _distance * cos(pitch))
	_camera.rotation = Vector3(-pitch, 0.0, 0.0)
