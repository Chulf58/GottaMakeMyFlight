class_name TestHoverTargetSelectCaption
extends GdUnitTestSuite
## On the real main scene, a click on a station sign that selects the station
## hides that sign's caption while the pointer stays on it; moving off the sign
## and back shows it again. A sign that pins keeps its caption after the click.

const SEED := 6_113_313
const VIEW_DISTANCE := 40.0
const DECIDE_FRAMES := 4
const FLOOR_SIGN := Rect2(700.0, 120.0, 30.0, 30.0)

var _settings_path := SaveTestKit.run_path("select_caption_alerts")
var _camera_settings_path := SaveTestKit.run_path("select_caption_camera")

var _main: Node
var _hud: PassengerHud
var _mode: BuildMode
var _sim: PassengerSim
var _rig: TycoonCamera
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
	# The real _process eases the focus toward the middle of the panel room a few
	# frames later, which moves every sign under the pointer. The view is held.
	_rig.set_process(false)
	await await_idle_frame()


func after() -> void:
	_main.free()
	DirAccess.remove_absolute(_settings_path)
	DirAccess.remove_absolute(_camera_settings_path)


func before_test() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	_selection().clear()
	_hud.refresh()
	_hover.pointer_override = Vector2(2.0, 2.0)


func after_test() -> void:
	_hover.pointer_override = null


func _selection() -> BuiltSelection:
	return _inspect.built_card.selection


func _desk_world() -> Vector3:
	return _mode.grid.cell_to_world(_mode.grid.get_object(_desk)["anchor"])


## The centre of the Closed sign over the desk, in viewport px.
func _closed_sign_centre() -> Vector2:
	var key := "closed:%d" % _desk
	for entry in _markers.hover_signs():
		if entry["key"] == key:
			return (entry["rect"] as Rect2).get_center()
	fail("no closed sign for desk %d: %s" % [_desk, _markers.hover_signs()])
	return Vector2(-1.0, -1.0)


func _tip_visible() -> bool:
	return _hover.tooltip().visible


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


func test_hovering_a_closed_desks_padlock_shows_the_caption() -> void:
	await _hover_at(_closed_sign_centre())
	print("hover: tooltip %s, text %s" % [_tip_visible(), _hover.tooltip().text()])
	assert_bool(_tip_visible()).is_true()
	assert_str(_hover.tooltip().text()).is_not_empty()


func test_clicking_the_padlock_hides_its_caption_while_the_pointer_stays() -> void:
	await _click_at(_closed_sign_centre())
	var hovered := _hover.hovered_target()
	var tip := _tip_visible()
	print("after click: selection %d, hovered %s, tooltip %s" % [_selection().id, hovered, tip])
	assert_int(_selection().id).is_equal(_desk)
	assert_object(hovered).is_not_null()
	assert_bool(tip).is_false()


func test_the_caption_returns_when_the_pointer_leaves_and_re_enters() -> void:
	var at := _closed_sign_centre()
	await _click_at(at)
	assert_bool(_tip_visible()).is_false()
	await _hover_at(Vector2(2.0, 2.0))
	assert_object(_hover.hovered_target()).is_null()
	await _hover_at(at)
	print("re-entered: hovered %s, tooltip %s" % [_hover.hovered_target(), _tip_visible()])
	assert_bool(_tip_visible()).is_true()


func test_a_pinning_sign_keeps_its_caption_after_the_click() -> void:
	var provider := FakeSignProvider.new()
	provider.add(&"gap", FLOOR_SIGN, "A gap in the wall")
	_hover.register_provider(provider)
	await _click_at(FLOOR_SIGN.get_center())
	var shown := _tip_visible()
	var words := _hover.tooltip().text()
	_hover.unregister_provider(provider)
	print("after the pinning click: tooltip %s, text %s" % [shown, words])
	assert_bool(shown).is_true()
	assert_str(words).is_equal("A gap in the wall")
