class_name TycoonCamera
extends Node3D
## Free tycoon camera. The rig sits on the ground at the focus point and yaws;
## the child Camera3D orbits it at a clamped distance. Zooming changes only the
## distance; the pitch stays fixed during zoom (ruling
## camera-free-vertical-tilt-on-right-drag-and-angle-presets-in-settings).
## Vertical right-mouse drag tilts pitch freely in [35, 75] degrees (dragging
## down tilts steeper toward top-down, dragging up tilts toward the horizon),
## while horizontal right-mouse drag rotates yaw. V (InputMap action
## `camera_angle`) cycles the three presets (LOW 38, MEDIUM 54, TOP_DOWN 70),
## and both preset and continuous pitch persist in user://hud_settings.cfg.
## WASD or middle-mouse drag pans, Q/E rotates, the wheel zooms, Home glides
## back to the start view. `glide_to` and `follow` move the focus from code; any
## manual pan cancels both. The focus appears at the middle of `room`, the screen
## share the open HUD panels leave free (PanelRoom sets it), not of the whole
## screen.

signal pitch_changed(degrees: float)

## The angle steps, from lowest to most top-down.
enum AngleStep { LOW, MEDIUM, TOP_DOWN }

## The whole viewport, as fractions of it (x, y, width, height from the top left).
const WHOLE_VIEW := Rect2(0.0, 0.0, 1.0, 1.0)
## Minimum and maximum free-tilt pitch, in degrees above the ground.
const MIN_PITCH_DEGREES := 35.0
const MAX_PITCH_DEGREES := 75.0
const CUSTOM_PITCH_EPSILON := 0.05
## The camera pitch of each step, in degrees above the ground. Top-down stops
## short of straight down so walls and passengers keep some side on. Low is the
## close-in tilt, medium close to the old home-view tilt (57).
const STEP_PITCH_DEGREES: Array[float] = [38.0, 54.0, 70.0]
## The settings-file keys of the angle step and free pitch, beside the other HUD settings.
const ANGLE_KEY := "camera_angle"
const PITCH_KEY := "camera_pitch"
## InputMap action and key that cycle the angle presets.
const ANGLE_ACTION := &"camera_angle"
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
@export var drag_tilt_speed := 0.25
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
## The chosen or nearest angle step (see AngleStep); assigning it directly
## jumps the pitch to that preset without writing settings.
var angle_step: AngleStep:
	get:
		return _angle_step
	set(value):
		_angle_step = _clamped_step(value)
		_pitch_degrees = STEP_PITCH_DEGREES[_angle_step]
## The HUD settings file the angle step and pitch are kept in; tests point it elsewhere.
var settings_path := HudFlagSetting.PATH
## The share of the screen the open HUD panels leave free, as fractions of the
## viewport. The focus point sits at its middle, not the screen's, and easing
## toward `set_room`'s target moves it there; on the start view a right-rail
## card moves it only as far as keeps the start area clear of the tray stack
## (_room_goal()). The whole viewport when no panel is open.
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

var _angle_step := AngleStep.TOP_DOWN
var _pitch_degrees := STEP_PITCH_DEGREES[AngleStep.TOP_DOWN]
var _tilt_dirty := false
var _distance := 80.0
var _follow_target: Node3D
var _gliding := false
## Counts the glides begun, so a caller can stop its own glide and no later one.
var _glide_serial := 0
var _glide_position := Vector3.ZERO
var _glide_yaw := NAN
var _room_target := WHOLE_VIEW
## The free share the start view's distance is fitted in: the room without the
## right rail's cards, which only shift the view and never zoom it (AlertStack).
var _fit_target := WHOLE_VIEW
## The area the start view frames, kept so Home and a panel opening refit it.
var _home_area := Rect2()
## True from framing the start view or Home until the player pans, zooms,
## rotates, follows or glides: a panel opening then also refits the distance.
var _at_home := false

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_load_saved_angle()
	position = home_position
	yaw = home_yaw
	distance = home_distance
	_apply()


func _exit_tree() -> void:
	_flush_tilt()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_flush_tilt()


func _input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and not event.pressed
		and event.button_index == MOUSE_BUTTON_RIGHT
	):
		_flush_tilt()


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
	elif event.is_action_pressed(ANGLE_ACTION, false, true):
		cycle_angle_step()
	elif event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom(1.0 / zoom_factor)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom(zoom_factor)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_flush_tilt()
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			pan(-event.relative * drag_pan_speed)
		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			if event.relative.x != 0.0:
				rotate_yaw(-event.relative.x * drag_rotate_speed)
			if event.relative.y != 0.0:
				tilt_pitch(event.relative.y * drag_tilt_speed)


## The camera pitch in degrees, clamped to [35, 75] and unchanged by zoom.
func pitch_degrees() -> float:
	return _pitch_degrees


## True when the current pitch does not match any of the three angle presets.
func is_custom_pitch() -> bool:
	for preset in STEP_PITCH_DEGREES:
		if absf(_pitch_degrees - preset) <= CUSTOM_PITCH_EPSILON:
			return false
	return true


## Sets the camera pitch directly (clamped to [35, 75]) and optionally persists
## it in the settings file.
func set_pitch_degrees(degrees: float, persist := true) -> void:
	_pitch_degrees = clampf(degrees, MIN_PITCH_DEGREES, MAX_PITCH_DEGREES)
	_angle_step = _nearest_step(_pitch_degrees)
	if persist:
		_tilt_dirty = false
		_save_angle_settings()
	else:
		_tilt_dirty = true
	_apply()
	pitch_changed.emit(_pitch_degrees)


## Tilts pitch by `delta_degrees` (+ tilts steeper toward 75 deg top-down,
## - lowers toward 35 deg horizon view), deferring disk save until drag release.
func tilt_pitch(delta_degrees: float) -> void:
	_at_home = false
	set_pitch_degrees(_pitch_degrees + delta_degrees, false)


## Chooses the angle step (clamped to the three) and remembers it in the
## settings file. The view tilts now; the start view, when still the current
## view, is fitted again at the new angle.
func set_angle_step(step: int) -> void:
	angle_step = step
	_tilt_dirty = false
	_save_angle_settings()
	set_room(_room_target, true, _fit_target)
	_apply()
	pitch_changed.emit(_pitch_degrees)


## Moves to the next angle step, from top-down round to low.
func cycle_angle_step() -> void:
	var base := _nearest_step(_pitch_degrees) if is_custom_pitch() else _angle_step
	set_angle_step((base + 1) % STEP_PITCH_DEGREES.size())


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
## to `to_distance` unless that is negative. Cancels any follow. Returns the
## glide's serial, for stop_glide().
func glide_to(world_point: Vector3, to_distance := -1.0) -> int:
	_begin_glide(world_point, to_distance, NAN)
	return _glide_serial


## Glides back to the start view: position, distance and yaw. A framed start
## view is fitted again to the screen share the panels leave free right now.
func go_home() -> void:
	if _home_area.has_area():
		var view := framing_for(_home_area, _fit_target)
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
	_fit_target = free
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
## fits the start area inside `fit`, unless `refit` is false (the panels only
## changed size, which should move the view a little, not zoom it). `fit` is
## `free` without what only shifts the view (the right rail's cards); an empty
## `fit` means `free`.
func set_room(free: Rect2, refit := true, fit := Rect2()) -> void:
	_room_target = free
	_fit_target = fit if fit.has_area() else free
	if refit and _at_home and _home_area.has_area():
		home_distance = framing_for(_home_area, _fit_target)["distance"]
		target_distance = clampf(home_distance, min_distance, max_distance)


## Keeps the focus on `node` until a manual pan, `glide_to`, `go_home` or
## `stop_follow`, or until the node is freed.
func follow(node: Node3D) -> void:
	_gliding = false
	_at_home = false
	_follow_target = node


func stop_follow() -> void:
	_follow_target = null


## Drops the glide with this serial (from glide_to) where the camera stands.
## A later glide, a Home press or a pan since then is left alone.
func stop_glide(serial: int) -> void:
	if serial == _glide_serial:
		_gliding = false


func is_following() -> bool:
	return _follow_target != null


func is_gliding() -> bool:
	return _gliding


func _begin_glide(world_point: Vector3, to_distance: float, to_yaw: float) -> void:
	stop_follow()
	_at_home = false
	_gliding = true
	_glide_serial += 1
	_glide_position = _clamp_to_bounds(Vector3(world_point.x, 0.0, world_point.z))
	_glide_yaw = to_yaw
	if to_distance >= 0.0:
		target_distance = clampf(to_distance, min_distance, max_distance)


func _clamped_step(step: int) -> AngleStep:
	if step < 0 or step >= STEP_PITCH_DEGREES.size():
		return AngleStep.TOP_DOWN
	return step as AngleStep


func _nearest_step(degrees: float) -> AngleStep:
	var best := AngleStep.TOP_DOWN
	var best_diff := INF
	for i in STEP_PITCH_DEGREES.size():
		var diff := absf(degrees - STEP_PITCH_DEGREES[i])
		if diff < best_diff:
			best_diff = diff
			best = i as AngleStep
	return best


func _load_saved_angle() -> void:
	angle_step = _clamped_step(
		HudFlagSetting.load_int(settings_path, ANGLE_KEY, AngleStep.TOP_DOWN, "TycoonCamera")
	)
	var saved_pitch := _load_saved_pitch()
	if not is_nan(saved_pitch):
		_pitch_degrees = clampf(saved_pitch, MIN_PITCH_DEGREES, MAX_PITCH_DEGREES)
		_angle_step = _nearest_step(_pitch_degrees)


func _load_saved_pitch() -> float:
	if HudFlagSetting.is_shielded(settings_path):
		return NAN
	var cfg := ConfigFile.new()
	var err := cfg.load(settings_path)
	if err == ERR_FILE_NOT_FOUND:
		return NAN
	if err != OK:
		push_error("TycoonCamera: cannot read %s (error %d)" % [settings_path, err])
		return NAN
	if not cfg.has_section_key(HudFlagSetting.SECTION, PITCH_KEY):
		return NAN
	var value: Variant = cfg.get_value(HudFlagSetting.SECTION, PITCH_KEY)
	if value is float or value is int:
		return float(value)
	return NAN


func _save_angle_settings() -> void:
	if HudFlagSetting.is_shielded(settings_path):
		return
	var cfg := ConfigFile.new()
	var err := cfg.load(settings_path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_error("TycoonCamera: cannot read %s (error %d)" % [settings_path, err])
		return
	cfg.set_value(HudFlagSetting.SECTION, ANGLE_KEY, int(_angle_step))
	cfg.set_value(HudFlagSetting.SECTION, PITCH_KEY, _pitch_degrees)
	err = cfg.save(settings_path)
	if err != OK:
		push_error("TycoonCamera: cannot write %s (error %d)" % [settings_path, err])


func _flush_tilt() -> void:
	if not _tilt_dirty:
		return
	_tilt_dirty = false
	_save_angle_settings()


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
	var goal := _room_goal()
	if room.is_equal_approx(goal):
		room = goal
		return
	var blend := 1.0 - exp(-glide_rate * delta)
	room = Rect2(room.position.lerp(goal.position, blend), room.size.lerp(goal.size, blend))


## Where the room eases to: `_room_target`, except on the start view. There a
## right-rail card's shift (from `_fit_target` toward `_room_target`) goes only
## as far as keeps the start area's floor above the bottom of `_fit_target`
## (the tray stack's top while a tray is open) and the area inside its left and
## right edges. The tray wins over the card: the card may overlap the far top
## corner, since the player builds near the tray (conductor ruling, board D3c).
func _room_goal() -> Rect2:
	if not _at_home or not _home_area.has_area() or _room_target.is_equal_approx(_fit_target):
		return _room_target
	var half := _home_area.size * 0.5
	if _clear_of_tray(half, _room_target):
		return _room_target
	var low := 0.0
	var high := 1.0
	for _i in 20:
		var mid := (low + high) / 2.0
		if _clear_of_tray(half, _shifted_room(mid)):
			low = mid
		else:
			high = mid
	return _shifted_room(low)


## The room `share` of the way from `_fit_target` to `_room_target`.
func _shifted_room(share: float) -> Rect2:
	return Rect2(
		_fit_target.position.lerp(_room_target.position, share),
		_fit_target.size.lerp(_room_target.size, share)
	)


## True when the start area, `half` from its middle to its edges, seen at the
## target distance with the focus at the middle of `aim`, has its floor and wall
## tops at or above the bottom of `_fit_target` and inside its left and right
## edges. Its top is not checked.
func _clear_of_tray(half: Vector2, aim: Rect2) -> bool:
	var extent: Variant = _extent(half, target_distance, aim)
	if extent == null:
		return false
	var seen: Rect2 = extent
	return (
		seen.position.x >= _fit_target.position.x * 2.0 - 1.0
		and seen.end.x <= _fit_target.end.x * 2.0 - 1.0
		and seen.position.y >= 1.0 - _fit_target.end.y * 2.0
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
	var extent: Variant = _extent(half, from_distance, free)
	if extent == null:
		return false
	var seen: Rect2 = extent
	var low := Vector2(free.position.x * 2.0 - 1.0, 1.0 - free.end.y * 2.0)
	var high := Vector2(free.end.x * 2.0 - 1.0, 1.0 - free.position.y * 2.0)
	return (
		seen.position.x >= low.x
		and seen.end.x <= high.x
		and seen.position.y >= low.y
		and seen.end.y <= high.y
	)


## Where on the screen, in view units (see _aim_of), the ground rectangle
## centred on the focus, `half` wide and deep from its middle to its edges, and
## the wall tops above it, are seen from `from_distance` at the chosen angle
## with the focus at the middle of `aim` (fractions of the viewport). Null when
## a corner is behind the eye.
func _extent(half: Vector2, from_distance: float, aim: Rect2) -> Variant:
	var pitch := deg_to_rad(pitch_degrees())
	var half_tan := tan(deg_to_rad(_camera.fov) / 2.0)
	var forward := Vector3(0.0, -sin(pitch), -cos(pitch))
	var up := Vector3(0.0, cos(pitch), -sin(pitch))
	var eye := _eye_offset(_aim_of(aim), from_distance)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for sign_x in [-1.0, 1.0]:
		for sign_z in [-1.0, 1.0]:
			for height in [0.0, frame_height]:
				var to_corner := Vector3(sign_x * half.x, height, sign_z * half.y) - eye
				var depth := to_corner.dot(forward)
				if depth <= 0.0:
					return null
				var at := Vector2(
					to_corner.x / (depth * half_tan * _aspect()),
					to_corner.dot(up) / (depth * half_tan)
				)
				low = low.min(at)
				high = high.max(at)
	return Rect2(low, high - low)


## Width over height of the view: the viewport's, or 16:9 outside the tree.
func _aspect() -> float:
	if not is_inside_tree():
		return 16.0 / 9.0
	var size := get_viewport().get_visible_rect().size
	return size.x / maxf(size.y, 1.0)
