class_name TestHoverTargetSelectSign
extends GdUnitTestSuite
## On the real main scene, a click on a station's own problem sign selects that
## station exactly as a click on the station does, and pins nothing; a sign that
## marks no object (a wall gap) still pins and takes the click. Hovering a sign
## shows its text either way.

const SEED := 6_113_312
const VIEW_DISTANCE := 40.0
const DECIDE_FRAMES := 4
const FLOOR_SIGN := Rect2(700.0, 120.0, 30.0, 30.0)

var _settings_path := SaveTestKit.run_path("select_sign_alerts")
var _camera_settings_path := SaveTestKit.run_path("select_sign_camera")

var _main: Node
var _hud: PassengerHud
var _mode: BuildMode
var _sim: PassengerSim
var _rig: TycoonCamera
var _eye: Camera3D
var _inspect: PassengerInspect
var _hover: HoverTarget
var _markers: MissMarkers
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
	_hover = HoverTarget.find(get_tree())
	_markers = _main.find_children("*", "MissMarkers", true, false)[0] as MissMarkers
	_hud.press_starter_terminal()
	_markers.sync()
	_desk = _sim.layout.desks[0]
	_rig.position = Vector3(_desk_world().x, 0.0, _desk_world().z)
	_rig.distance = VIEW_DISTANCE
	for i in 60:
		_rig._process(0.1)
	await await_idle_frame()


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


## The centre of the Closed sign over the desk, in viewport px.
func _closed_sign_centre() -> Vector2:
	var key := "closed:%d" % _desk
	for entry in _markers.hover_signs():
		if entry["key"] == key:
			assert_int(entry["select"]).is_equal(_desk)
			return (entry["rect"] as Rect2).get_center()
	fail("no closed sign for desk %d: %s" % [_desk, _markers.hover_signs()])
	return Vector2(-1.0, -1.0)


func _hover_at(point: Vector2) -> void:
	_hover.pointer_override = point
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	await await_idle_frame()


func _click_at(point: Vector2) -> void:
	await _hover_at(point)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = point
	click.global_position = point
	get_viewport().push_input(click, true)
	for i in DECIDE_FRAMES:
		await await_idle_frame()


func test_hovering_a_closed_desks_padlock_shows_its_text() -> void:
	var at := _closed_sign_centre()
	await _hover_at(at)
	var shown := _hover.shown_target()
	print("hover at %s: %s" % [at, shown.key if shown != null else null])
	assert_object(shown).is_not_null()
	assert_str(shown.key).is_equal("closed:%d" % _desk)
	assert_str(shown.text).is_not_empty()


func test_clicking_a_closed_desks_padlock_selects_the_desk_and_pins_nothing() -> void:
	var at := _closed_sign_centre()
	await _click_at(at)
	print("click at %s: selection %d, pinned %s" % [at, _selection().id, _hover.pinned_target()])
	assert_int(_selection().kind).is_equal(BuiltSelection.Kind.OBJECT)
	assert_int(_selection().id).is_equal(_desk)
	assert_bool(_inspect.visible).is_true()
	assert_object(_hover.pinned_target()).is_null()
	var status := _inspect.built_card.field_text("status")
	print("card status: %s; sign: %s" % [status, _markers.closed_text(_desk)])
	assert_str(status).starts_with("Status: Closed")


func test_clicking_a_sign_that_marks_no_object_still_pins_it() -> void:
	var provider := FakeSignProvider.new()
	provider.add(&"gap", FLOOR_SIGN, "A gap in the wall")
	_hover.register_provider(provider)
	_selection().select_object(_desk)
	_hud.refresh()
	await _click_at(FLOOR_SIGN.get_center())
	var pinned := _hover.pinned_target()
	print("click at the gap sign: pinned %s, selection %d" % [pinned, _selection().id])
	_hover.unregister_provider(provider)
	assert_object(pinned).is_not_null()
	assert_that(pinned.key).is_equal(&"gap")
	assert_bool(_selection().is_selected()).is_false()
