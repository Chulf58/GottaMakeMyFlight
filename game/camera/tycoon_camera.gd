class_name TycoonCamera
extends Node3D
## Free tycoon camera. The rig sits on the ground at the focus point and yaws;
## the child Camera3D orbits it at a fixed pitch and a clamped distance.
## WASD or a middle-mouse drag pans, Q/E or a right-mouse drag rotates, the
## wheel zooms.

@export var min_distance := 12.0
@export var max_distance := 120.0
@export var pitch_degrees := 55.0
## Pan speed in focus-distance units per second at distance 1.
@export var key_pan_speed := 0.6
@export var drag_pan_speed := 0.0016
@export var key_rotate_speed := 1.6
@export var drag_rotate_speed := 0.005
@export var zoom_factor := 1.12
## Half the size of the square the focus point stays inside.
@export var bounds_half_extent := 95.0

var distance := 60.0
var yaw := 0.0

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_apply()


func _process(delta: float) -> void:
	var move := Input.get_vector("cam_left", "cam_right", "cam_forward", "cam_back")
	if move != Vector2.ZERO:
		pan(move * key_pan_speed * delta)
	var turn := Input.get_axis("cam_rotate_left", "cam_rotate_right")
	if turn != 0.0:
		rotate_yaw(turn * key_rotate_speed * delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(1.0 / zoom_factor)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(zoom_factor)
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			pan(-event.relative * drag_pan_speed)
		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			rotate_yaw(-event.relative.x * drag_rotate_speed)


## Moves the focus across the ground. `amount` is in the rig's own right and
## back axes (x right, y back) and scales with the zoom distance.
func pan(amount: Vector2) -> void:
	var step := global_transform.basis * Vector3(amount.x, 0.0, amount.y) * distance
	var target := position + step
	target.x = clampf(target.x, -bounds_half_extent, bounds_half_extent)
	target.z = clampf(target.z, -bounds_half_extent, bounds_half_extent)
	position = target


func rotate_yaw(radians: float) -> void:
	yaw = wrapf(yaw + radians, -PI, PI)
	_apply()


## Multiplies the distance by `factor` and clamps it.
func zoom(factor: float) -> void:
	distance = clampf(distance * factor, min_distance, max_distance)
	_apply()


func _apply() -> void:
	rotation.y = yaw
	var pitch := deg_to_rad(pitch_degrees)
	_camera.position = Vector3(0.0, distance * sin(pitch), distance * cos(pitch))
	_camera.rotation = Vector3(-pitch, 0.0, 0.0)
