class_name TestBuiltSelectionReveal
extends GdUnitTestSuite
## On the real main scene, with the real camera rig, clicking a built desk with
## no build tool keeps the camera still while the desk is on screen and clear of
## the inspect window, and glides just far enough to show it when the window
## that opens would cover it or it is off screen (decision clicking-a-built-
## desk-outside-build-mode-moves-the-camera-on).

const SEED := 6_113_312
const VIEW_DISTANCE := 40.0
## Frames after a click before the reveal has been decided.
const DECIDE_FRAMES := 4

var _settings_path := SaveTestKit.run_path("built_selection_reveal_alerts")
var _camera_settings_path := SaveTestKit.run_path("built_selection_reveal_camera")

var _main: Node
var _hud: PassengerHud
var _mode: BuildMode
var _sim: PassengerSim
var _rig: TycoonCamera
var _eye: Camera3D
var _inspect: PassengerInspect
var _desk := 0


func before() -> void:
	_main = load(SaveTestKit.MAIN).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(SEED)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	(_main.get_node("PassengerHud") as PassengerHud).alert_settings_path = _settings_path
	(_main.get_node("TycoonCamera") as TycoonCamera).settings_path = _camera_settings_path
	add_child(_main)
	_hud = _main.get_node("PassengerHud")
	_mode = _main.get_node("BuildMode")
	_sim = _main.get_node("PassengerSim")
	_rig = _main.get_node("TycoonCamera")
	_eye = _main.get_node("TycoonCamera/Camera3D")
	_inspect = _hud.find_child("PassengerInspect", true, false) as PassengerInspect
	_hud.press_starter_terminal()
	StaffTestKit.staff_all(_main.get_node("Staff"))
	_desk = _sim.layout.desks[0]


func after() -> void:
	_main.free()
	DirAccess.remove_absolute(_settings_path)
	DirAccess.remove_absolute(_camera_settings_path)


func before_test() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	_selection().clear()
	_hud.refresh()


func _selection() -> BuiltSelection:
	return _inspect.built_card.selection


func _desk_world() -> Vector3:
	return _mode.grid.cell_to_world(_mode.grid.get_object(_desk)["anchor"])


func _desk_rect() -> Rect2:
	return _selection().outline_rect(_mode.grid, _mode.landside_placement())


func _viewport() -> Rect2:
	return _eye.get_viewport().get_visible_rect()


## Puts the camera's focus on `world` and lets the camera settle there.
func _focus_on(world: Vector3) -> void:
	_rig.position = Vector3(world.x, 0.0, world.z)
	_rig.distance = VIEW_DISTANCE
	await _settle()


## Runs the camera's frames by hand until a glide and the room easing are done.
func _settle() -> void:
	for i in 60:
		_rig._process(0.1)
	await await_idle_frame()


func _click_world(at: Vector3) -> void:
	var screen := _eye.unproject_position(at)
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	_mode.pointer_override = screen
	get_viewport().push_input(motion, true)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = screen
	click.global_position = screen
	get_viewport().push_input(click, true)
	for i in DECIDE_FRAMES:
		await await_idle_frame()
	_mode.pointer_override = Vector2(-1.0, -1.0)


func _desk_top() -> Vector3:
	return _desk_world() + Vector3(0.0, 0.4, 0.0)


func test_a_desk_in_view_and_clear_of_the_window_keeps_the_camera_still() -> void:
	await _focus_on(_desk_world())
	var before := _rig.position
	await _click_world(_desk_top())
	print("camera %s -> %s, gliding %s" % [before, _rig.position, _rig.is_gliding()])
	assert_int(_selection().id).is_equal(_desk)
	assert_bool(_inspect.visible).is_true()
	assert_bool(_rig.is_gliding()).is_false()
	assert_bool(_rig.position.is_equal_approx(before)).is_true()


func test_a_desk_that_will_sit_under_the_window_glides_clear_of_it() -> void:
	await _focus_on(_desk_world())
	await _click_world(_desk_top())
	var window := _inspect.get_global_rect()
	assert_bool(window.has_area()).is_true()
	_selection().clear()
	_hud.refresh()
	await _park_under(window.get_center())
	var at := _eye.unproject_position(_desk_world())
	print("desk at %s, window %s" % [at, window])
	assert_bool(window.has_point(at)).is_true()
	var before := _rig.position
	await _click_world(_desk_top())
	assert_int(_selection().id).is_equal(_desk)
	var opened := _inspect.get_global_rect()
	assert_bool(_rig.is_gliding()).is_true()
	await _settle()
	var box := SelectReveal.screen_box(_eye, _desk_rect(), _mode.grid.origin.y)
	print("moved %s, desk box %s, window %s" % [_rig.position - before, box, opened])
	assert_bool(_rig.position.is_equal_approx(before)).is_false()
	assert_bool(box.intersects(_inspect.get_global_rect())).is_false()
	assert_bool(_viewport().encloses(box)).is_true()


func test_a_selected_desk_off_screen_glides_into_view() -> void:
	await _focus_on(_desk_world())
	await _click_world(_desk_top())
	assert_bool(_rig.is_gliding()).is_false()
	_rig.position += Vector3(90.0, 0.0, 0.0)
	await _settle()
	assert_bool(_viewport().has_point(_eye.unproject_position(_desk_world()))).is_false()
	_hud._reveal_built()
	assert_bool(_rig.is_gliding()).is_true()
	await _settle()
	var box := SelectReveal.screen_box(_eye, _desk_rect(), _mode.grid.origin.y)
	print("desk box after the glide %s in %s" % [box, _viewport()])
	assert_bool(_viewport().encloses(box)).is_true()
	assert_bool(box.intersects(_inspect.get_global_rect())).is_false()


## Moves the focus so the desk stands at screen point `at`.
func _park_under(at: Vector2) -> void:
	await _focus_on(_desk_world())
	var landing: Variant = BuildMode.ground_point(
		_eye.project_ray_origin(at), _eye.project_ray_normal(at), 0.0
	)
	assert_bool(landing != null).is_true()
	var move: Vector3 = _desk_world() - (landing as Vector3)
	_rig.position += Vector3(move.x, 0.0, move.z)
	await _settle()
