class_name TestHintsMain
extends GdUnitTestSuite
## Hints in the real scene (HUD 7/7): main.tscn mounts them in PassengerHud, off
## in a test run with no row; with the profile mode forced on, a hint reads the
## real sim, takes the banner's slot while it shows and gives it back, and the
## card docks where the banner does. One boot for the file.

const SEED := 4242

var _main: Node
var _path: String


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	await await_idle_frame()
	await await_idle_frame()


func after() -> void:
	_main.free()


func before_test() -> void:
	_path = SaveTestKit.run_path("hints_main")
	DirAccess.remove_absolute(_path)


func after_test() -> void:
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + ".tmp")


func _hud() -> PassengerHud:
	return _main.get_node("PassengerHud")


func _panel() -> StaffPanel:
	return _main.get_node("StaffPanel")


## A Hints in profile mode on the real HUD, past its start grace.
func _live() -> Hints:
	var hints := Hints.new()
	hints.forced_mode = Hints.Mode.PROFILE
	hints.settings_path = _path
	hints.hud = _hud()
	hints.scene_root = _main
	_hud().add_child(hints)
	# The first frame binds the HUD's sim and starts the grace; do it before the test.
	hints._process(0.0)
	hints.advance(Hints.GRACE_S + 0.1, _world(), [])
	return auto_free(hints)


func _world() -> Dictionary:
	return HintRules.read_world(_hud().sim, _panel().hiring_hint_roles())


func test_the_mounted_hints_are_off_in_a_test_run_and_show_no_row() -> void:
	var mounted := _hud().find_child("Hints", false, false) as Hints
	assert_object(mounted).is_not_null()
	assert_int(mounted.mode()).is_equal(Hints.Mode.OFF)
	assert_bool(mounted.settings_row().visible).is_false()
	assert_bool(mounted.is_showing()).is_false()


func test_a_new_game_world_has_no_desk_so_the_check_in_hint_is_due() -> void:
	var world := _world()
	assert_int(world["desks"]).is_equal(0)
	assert_array(HintRules.causes(world)).is_equal([HintRules.PLACE_CHECKIN])


func test_a_shown_hint_takes_the_banner_slot_and_gives_it_back() -> void:
	var hints := _live()
	assert_bool(_panel().hint_card().visible).is_true()
	for i in 8:
		hints.advance(0.25, _world(), ["Check-in"])
	assert_str(hints.shown_id()).is_equal(HintRules.PLACE_CHECKIN)
	assert_bool(_panel().hint_card().visible).is_false()
	assert_bool(hints.card().visible).is_true()
	hints.set_enabled(false)
	assert_bool(_panel().hint_card().visible).is_true()
	assert_bool(hints.card().visible).is_false()


func test_the_hint_card_docks_where_the_banner_docks() -> void:
	var hints := _live()
	for i in 8:
		hints.advance(0.25, _world(), ["Check-in"])
	await await_idle_frame()
	await await_idle_frame()
	var card := hints.card().get_global_rect()
	assert_bool(card.has_area()).is_true()
	var screen := get_viewport().get_visible_rect().size
	var bottom := screen.y - card.end.y
	assert_float(bottom).is_equal_approx(_panel().hint_dock_bottom(), 1.5)


func test_a_new_game_has_no_staffing_shortage_to_teach() -> void:
	assert_array(_world()["shortage_roles"]).is_empty()


func test_the_card_fades_under_the_build_ghost_and_returns() -> void:
	var hints := _live()
	for i in 8:
		hints.advance(0.25, _world(), ["Check-in"])
	await await_idle_frame()
	await await_idle_frame()
	var card := hints.card().get_global_rect()
	hints.fade_for(Rect2(card.get_center(), Vector2(10, 10)), 10.0)
	assert_float(hints.card().modulate.a).is_equal_approx(StaffPanel.FADED_ALPHA, 0.001)
	hints.fade_for(Rect2(card.position - Vector2(300, 300), Vector2(20, 20)), 10.0)
	assert_float(hints.card().modulate.a).is_equal(1.0)
	assert_int(hints.card().mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_the_process_loop_reads_the_real_sim_and_holds_the_start_grace() -> void:
	var hints := _live()
	hints.reset_session()
	hints._process(Hints.READ_EVERY_S + 0.01)
	hints._process(Hints.READ_EVERY_S + 0.01)
	assert_bool(hints.is_showing()).is_false()
	assert_bool(hints.is_seen(HintRules.PLACE_CHECKIN)).is_false()


func test_a_probe_can_stop_the_world_reading_and_keep_the_card_docking() -> void:
	var hints := Hints.new()
	hints.forced_mode = Hints.Mode.PROFILE
	hints.settings_path = _path
	hints.hud = _hud()
	hints.scene_root = _main
	hints.reads_world = false
	_hud().add_child(hints)
	auto_free(hints)
	hints._process(1.0)
	assert_object(hints._sim).is_null()
	assert_float(hints._dock_bottom).is_equal_approx(_panel().hint_dock_bottom(), 0.01)
