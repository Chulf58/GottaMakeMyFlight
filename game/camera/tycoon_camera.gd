class_name TycoonCamera
extends Node3D
## Free tycoon camera. The rig sits on the ground at the focus point and yaws;
## the child Camera3D orbits it at a clamped distance. Zooming changes only the
## distance; the tilt is the player's angle setting, three steps (low, medium,
## top-down) kept in the HUD settings file, with V cycling them (decision
## camera-angle-is-a-player-setting-fixed-while-zooming). WASD or a
## middle-mouse drag pans, Q/E or a right-mouse drag rotates, the wheel zooms,
## Home glides back to the start view. `glide_to` and `follow` move the focus
## from code; any manual pan cancels both. The focus appears at the middle of
## `room`, the screen share the open HUD panels leave free (PanelRoom sets it),
## not of the whole screen.

## The angle steps, from lowest to most top-down.
enum AngleStep { LOW, MEDIUM, TOP_DOWN }

## The whole viewport, as fractions of it (x, y, width, height from the top left).
const WHOLE_VIEW := Rect2(0.0, 0.0, 1.0, 1.0)
## The camera pitch of each step, in degrees above the ground. Top-down stops
## short of straight down so walls and passengers keep some side on. Low is the
## old close-in tilt, medium close to the old home-view tilt (57).
const STEP_PITCH_DEGREES: Array[float] = [38.0, 54.0, 70.0]
## The settings-file key of the angle step, beside the other HUD settings.
const ANGLE_KEY := "camera_angle"
## The key that cycles the angle step.
const ANGLE_KEYCODE := KEY_V
## The steepest the view ray through the free area's middle may point away from
## the ground (y of its direction), so a far-off aim never misses the ground.
const MIN_RAY_DOWN := 0.05

## Closest and farthest zoom, in metres from the focus point.
@export var min_distance := 6.0
@export var max_distance := 300.0
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
## Half the size of the square the focus point stays inside. The runway at
## z = -338 lies 78 m beyond the north edge of the default, so it is seen from the edge.
@export var bounds_half_extent := 260.0
## The start view, on the build area, and where Home returns to.
@export var home_position := Vector3.ZERO
@export var home_distance := 80.0
@export var home_yaw := 0.0
## How much roomier than the area itself a framed view is. The HUD panels are
## already cut out of the room the area is fitted in (PanelRoom, the bottom bar
## included), so this is only a little breathing space around it.
@export var frame_margin := 1.15
## The height the area's walls reach, in metres: a framed view keeps the wall
## tops inside the room too, since the far wall's top shows above its foot.
@export var frame_height := 2.5

var yaw := 0.0
## The chosen angle step (see AngleStep); read from the settings file at _ready,
## changed with set_angle_step.
var angle_step := AngleStep.TOP_DOWN
## The HUD settings file the angle step is kept in; tests point it elsewhere.
var settings_path := HudFlagSetting.PATH
## The share of the screen the open HUD panels leave free, as fractions of the
## viewport. The focus point sits at its middle, not the screen's, and easing
## toward `set_room`'s target moves it there. The whole viewport when no panel
## is open.
var room := WHOLE_VIEW
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
var _room_target := WHOLE_VIEW
## The area the start view frames, kept so Home and a panel opening refit it.
var _home_area := Rect2()
## True from framing the start view or Home until the player pans, zooms,
## rotates, follows or glides: a panel opening then also refits the distance.
var _at_home := false

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	angle_step = _clamped_step(
		HudFlagSetting.load_int(settings_path, ANGLE_KEY, AngleStep.TOP_DOWN, "TycoonCamera")
	)
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
	_step_room(delta)
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_home"):
		go_home()
	elif (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.physical_keycode == ANGLE_KEYCODE
		and not event.ctrl_pressed
		and not event.meta_pressed
		and not event.alt_pressed
	):
		cycle_angle_step()
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


## The camera pitch in degrees: the chosen step's, the same at every zoom.
func pitch_degrees() -> float:
	return STEP_PITCH_DEGREES[angle_step]


## Chooses the angle step (clamped to the three) and remembers it in the
## settings file. The view tilts now; the start view, when still the current
## view, is fitted again at the new angle.
func set_angle_step(step: int) -> void:
	angle_step = _clamped_step(step)
	HudFlagSetting.save_int(settings_path, ANGLE_KEY, angle_step, "TycoonCamera")
	set_room(_room_target)
	_apply()


## Moves to the next angle step, from top-down round to low.
func cycle_angle_step() -> void:
	set_angle_step((angle_step + 1) % STEP_PITCH_DEGREES.size())


## Moves the focus across the ground. `amount` is in the rig's own right and
## back axes (x right, y back) and scales with the zoom distance. A manual pan,
## so it cancels any follow and glide.
func pan(amount: Vector2) -> void:
	stop_follow()
	_gliding = false
	_at_home = false
	var step := global_transform.basis * Vector3(amount.x, 0.0, amount.y) * _distance
	position = _clamp_to_bounds(position + step)


func rotate_yaw(radians: float) -> void:
	_at_home = false
	yaw = wrapf(yaw + radians, -PI, PI)
	_apply()


## Multiplies the target distance by `factor` and clamps it. The distance eases
## toward it over the next frames.
func zoom(factor: float) -> void:
	_at_home = false
	target_distance = clampf(target_distance * factor, min_distance, max_distance)
	_apply()


## Glides the focus to `world_point` (its height is ignored), and the distance
## to `to_distance` unless that is negative. Cancels any follow.
func glide_to(world_point: Vector3, to_distance := -1.0) -> void:
	_begin_glide(world_point, to_distance, NAN)


## Glides back to the start view: position, distance and yaw. A framed start
## view is fitted again to the screen share the panels leave free right now.
func go_home() -> void:
	if _home_area.has_area():
		var view := framing_for(_home_area, _room_target)
		home_position = view["position"]
		home_distance = view["distance"]
	_begin_glide(home_position, home_distance, home_yaw)
	_at_home = true


## The focus point and distance that fit `area`, a ground rectangle in the
## world's x and z, seen at yaw 0 (x across the screen, z into it): the
## nearest distance, inside the zoom limits, at which the area grown by
## `frame_margin`, with its walls `frame_height` high, is wholly inside `free`,
## the share of the screen the open
## panels leave (fractions of the viewport; the whole viewport by default),
## with the focus at the middle of `free`, at the chosen angle. The distance is
## found by bisection.
func framing_for(area: Rect2, free := WHOLE_VIEW) -> Dictionary:
	var half := area.size * 0.5 * frame_margin
	var fit := max_distance
	if _fits(half, min_distance, free):
		fit = min_distance
	elif _fits(half, max_distance, free):
		var low := min_distance
		for _i in 30:
			var mid := (low + fit) / 2.0
			if _fits(half, mid, free):
				fit = mid
			else:
				low = mid
	var centre := area.get_center()
	return {"position": _clamp_to_bounds(Vector3(centre.x, 0.0, centre.y)), "distance": fit}


## Makes the view that fits `area` inside `free` the start view: Home returns
## to it, and the camera jumps there now, with no glide.
func frame_start_view(area: Rect2, free := WHOLE_VIEW) -> void:
	_home_area = area
	_room_target = free
	room = free
	var view := framing_for(area, free)
	home_position = view["position"]
	home_distance = view["distance"]
	stop_follow()
	_gliding = false
	position = home_position
	yaw = home_yaw
	distance = home_distance
	_at_home = true
	_apply()


## Tells the camera which share of the screen the open panels leave free
## (fractions of the viewport). The focus eases to the middle of it. When the
## camera is still on the start view, the distance also eases to the one that
## fits the start area inside `free`, unless `refit` is false (the panels only
## changed size, which should move the view a little, not zoom it).
func set_room(free: Rect2, refit := true) -> void:
	_room_target = free
	if refit and _at_home and _home_area.has_area():
		home_distance = framing_for(_home_area, free)["distance"]
		target_distance = clampf(home_distance, min_distance, max_distance)


## Keeps the focus on `node` until a manual pan, `glide_to`, `go_home` or
## `stop_follow`, or until the node is freed.
func follow(node: Node3D) -> void:
	_gliding = false
	_at_home = false
	_follow_target = node


func stop_follow() -> void:
	_follow_target = null


func is_following() -> bool:
	return _follow_target != null


func is_gliding() -> bool:
	return _gliding


func _begin_glide(world_point: Vector3, to_distance: float, to_yaw: float) -> void:
	stop_follow()
	_at_home = false
	_gliding = true
	_glide_position = _clamp_to_bounds(Vector3(world_point.x, 0.0, world_point.z))
	_glide_yaw = to_yaw
	if to_distance >= 0.0:
		target_distance = clampf(to_distance, min_distance, max_distance)


func _clamped_step(step: int) -> AngleStep:
	if step < 0 or step >= STEP_PITCH_DEGREES.size():
		return AngleStep.TOP_DOWN
	return step as AngleStep


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


func _step_room(delta: float) -> void:
	if room.is_equal_approx(_room_target):
		room = _room_target
		return
	var blend := 1.0 - exp(-glide_rate * delta)
	room = Rect2(
		room.position.lerp(_room_target.position, blend), room.size.lerp(_room_target.size, blend)
	)


func _apply() -> void:
	rotation.y = yaw
	var pitch := deg_to_rad(pitch_degrees())
	_camera.position = _eye_offset(_aim_of(room), _distance)
	_camera.rotation = Vector3(-pitch, 0.0, 0.0)


## The middle of `free` on the screen, in view units: x -1 to 1 left to right,
## y -1 to 1 bottom to top.
func _aim_of(free: Rect2) -> Vector2:
	var centre := free.get_center()
	return Vector2(centre.x * 2.0 - 1.0, 1.0 - centre.y * 2.0)


## Where the eye sits, relative to the focus point on the ground and at yaw 0:
## `from_distance` back along the view ray through `aim` (see _aim_of), so
## the ray meets the ground at the focus and the eye is exactly `from_distance`
## from it. With the aim at the screen's middle this is the old orbit position.
func _eye_offset(aim: Vector2, from_distance: float) -> Vector3:
	var pitch := deg_to_rad(pitch_degrees())
	var half_tan := tan(deg_to_rad(_camera.fov) / 2.0)
	var ray := Vector3(
		aim.x * half_tan * _aspect(),
		-sin(pitch) + aim.y * half_tan * cos(pitch),
		-cos(pitch) - aim.y * half_tan * sin(pitch)
	)
	ray.y = minf(ray.y, -MIN_RAY_DOWN)
	return -ray.normalized() * from_distance


## True when the ground rectangle centred on the focus, `half` wide and deep
## from its middle to its edges, and the wall tops above it, is wholly inside
## `free` (fractions of the viewport) from `from_distance` at the chosen angle,
## with the focus at the middle of `free`.
func _fits(half: Vector2, from_distance: float, free: Rect2) -> bool:
	var pitch := deg_to_rad(pitch_degrees())
	var half_tan := tan(deg_to_rad(_camera.fov) / 2.0)
	var forward := Vector3(0.0, -sin(pitch), -cos(pitch))
	var up := Vector3(0.0, cos(pitch), -sin(pitch))
	var eye := _eye_offset(_aim_of(free), from_distance)
	var low := Vector2(free.position.x * 2.0 - 1.0, 1.0 - free.end.y * 2.0)
	var high := Vector2(free.end.x * 2.0 - 1.0, 1.0 - free.position.y * 2.0)
	for sign_x in [-1.0, 1.0]:
		for sign_z in [-1.0, 1.0]:
			for height in [0.0, frame_height]:
				var to_corner := Vector3(sign_x * half.x, height, sign_z * half.y) - eye
				var depth := to_corner.dot(forward)
				if depth <= 0.0:
					return false
				var across := to_corner.x / (depth * half_tan * _aspect())
				var vertical := to_corner.dot(up) / (depth * half_tan)
				if across < low.x or across > high.x or vertical < low.y or vertical > high.y:
					return false
	return true


## Width over height of the view: the viewport's, or 16:9 outside the tree.
func _aspect() -> float:
	if not is_inside_tree():
		return 16.0 / 9.0
	var size := get_viewport().get_visible_rect().size
	return size.x / maxf(size.y, 1.0)
