class_name TestEscClosesSelection
extends GdUnitTestSuite
## On the real main scene, Esc with a built item selected (its inspect card
## open) or a passenger followed closes the card and clears the selection; it
## does not open the game menu. The next Esc opens the menu, as it does with
## nothing selected. Esc still belongs to build mode first: with a tray open it
## closes the tray, leaves the card alone and opens nothing. The keys are pushed
## through the viewport so every input owner sees them (anti-pattern: a test
## that calls one handler directly misses a second owner).

const SEED := 6_113_411
const FLIGHT_ID := "GMF101"
const STRUCTURE := 0

var _settings_path := SaveTestKit.run_path("esc_selection_alerts")
var _departures_path := SaveTestKit.run_path("esc_selection_departures")

var _main: Node
var _hud: PassengerHud
var _mode: BuildMode
var _sim: PassengerSim
var _views: PassengerViews
var _eye: Camera3D
var _inspect: PassengerInspect
var _menu: GameMenu
var _clock: SimClock
var _build_menu: BuildMenu
var _desk := 0


func before() -> void:
	_main = load(SaveTestKit.MAIN).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(SEED)
	_clock.set_paused(true)
	_hud = _main.get_node("PassengerHud")
	_hud.alert_settings_path = _settings_path
	_hud.departures_settings_path = _departures_path
	add_child(_main)
	_mode = _main.get_node("BuildMode")
	_sim = _main.get_node("PassengerSim")
	_views = _main.get_node("PassengerViews")
	_menu = _main.get_node("GameMenu")
	_build_menu = _main.get_node("BuildMenu")
	(_main.get_node("IncidentDirector") as IncidentDirector).set_enabled(false)
	(_main.get_node("TycoonCamera") as TycoonCamera).set_process(false)
	_eye = _main.get_node("TycoonCamera/Camera3D")
	_inspect = _hud.find_child("PassengerInspect", true, false) as PassengerInspect
	_hud.press_starter_terminal()
	StaffTestKit.staff_all(_main.get_node("Staff"))
	_desk = _sim.layout.desks[0]


func after() -> void:
	_main.free()
	DirAccess.remove_absolute(_settings_path)
	DirAccess.remove_absolute(_departures_path)


func before_test() -> void:
	_menu.close()
	await await_idle_frame()
	_mode.set_tool(BuildMode.Tool.NONE)
	_views.selected_id = 0
	_selection().clear()
	_look_at(_mode.grid.cell_to_world(_desk_anchor()))
	_hud.refresh()


func _selection() -> BuiltSelection:
	return _inspect.built_card.selection


func _desk_anchor() -> Vector2i:
	return _mode.grid.get_object(_desk)["anchor"]


func _look_at(target: Vector3) -> void:
	_eye.look_at_from_position(target + Vector3(0.0, 30.0, 4.0), target)


## A real left click on a world point, pushed through the viewport.
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
	await await_idle_frame()
	_mode.pointer_override = Vector2(-1.0, -1.0)
	_hud.refresh()


func _esc() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	get_viewport().push_input(event, true)


func _select_desk() -> void:
	var top := _mode.grid.cell_to_world(_desk_anchor()) + Vector3(0.0, 0.4, 0.0)
	await _click_world(top)
	assert_int(_selection().kind).is_equal(BuiltSelection.Kind.OBJECT)
	assert_bool(_inspect.visible).is_true()


func test_esc_with_an_item_selected_closes_the_card_and_opens_no_menu() -> void:
	await _select_desk()
	_esc()
	_hud.refresh()
	assert_int(_selection().kind).is_equal(BuiltSelection.Kind.NONE)
	assert_bool(_inspect.visible).is_false()
	assert_bool(_menu.is_open()).is_false()
	assert_bool(_menu.has_hold()).is_false()
	assert_bool(_clock.holds.is_holding()).is_false()


func test_the_next_esc_opens_the_menu() -> void:
	await _select_desk()
	_esc()
	_hud.refresh()
	assert_bool(_menu.is_open()).is_false()
	_esc()
	assert_bool(_menu.is_open()).is_true()
	assert_bool(_clock.holds.is_holding()).is_true()


func test_esc_with_nothing_selected_opens_the_menu() -> void:
	assert_bool(_selection().is_selected()).is_false()
	_esc()
	assert_bool(_menu.is_open()).is_true()


func test_esc_with_a_passenger_followed_clears_it_and_opens_no_menu() -> void:
	var passenger := _sim.spawn_now(FLIGHT_ID)
	_views.sync()
	var at := _mode.grid.cell_to_world(_desk_anchor())
	_views.node_for(passenger).position = at
	await _click_world(at + Vector3(0.0, 1.0, 0.0))
	assert_int(_views.selected_id).is_equal(passenger)
	assert_bool(_inspect.visible).is_true()
	_esc()
	_hud.refresh()
	assert_int(_views.selected_id).is_equal(0)
	assert_bool(_inspect.visible).is_false()
	assert_bool(_menu.is_open()).is_false()
	assert_bool(_menu.has_hold()).is_false()
	# The control: the next Esc opens the menu.
	_esc()
	assert_bool(_menu.is_open()).is_true()


func test_esc_with_a_tray_open_closes_the_tray_and_leaves_the_selected_card() -> void:
	await _select_desk()
	_build_menu.press_category(STRUCTURE)
	_build_menu.build_session.sync()
	assert_bool(_build_menu.is_tray_open()).is_true()
	_esc()
	assert_bool(_build_menu.is_tray_open()).is_false()
	assert_bool(_menu.is_open()).is_false()
	assert_bool(_menu.has_hold()).is_false()
	assert_int(_selection().kind).is_equal(BuiltSelection.Kind.OBJECT)
	_build_menu.build_session.sync()
	# With build mode over, the next Esc closes the card, the one after opens the menu.
	_esc()
	assert_int(_selection().kind).is_equal(BuiltSelection.Kind.NONE)
	assert_bool(_menu.is_open()).is_false()
	_esc()
	assert_bool(_menu.is_open()).is_true()
