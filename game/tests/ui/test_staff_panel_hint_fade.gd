class_name TestStaffPanelHintFade
extends GdUnitTestSuite
## While the build ghost is over the status banner (the hint card), the banner
## lets clicks through and fades to FADED_ALPHA so the ghost shows through (board
## 9c2b0d32 part 1); it returns to full opacity when the ghost leaves.

var _w: PassengerTestWorld
var _panel: StaffPanel


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _w != null:
		_w.free_all()
	_w = null


## A panel with a closed airport, so the hint card shows, and its layout settled.
func _make() -> void:
	_w = PassengerTestWorld.make(
		PassengerTestWorld.floored(Vector2i(12, 12)), FlightSim.schedule_starts(0)
	)
	_w.auto_staff = false
	var gate: AirportGate = auto_free(AirportGate.new())
	gate.bind(_w.flights, _w.staff)
	_panel = auto_free(StaffPanel.new())
	_panel.staff = _w.staff
	_panel.gate = gate
	add_child(_panel)
	await await_idle_frame()
	await await_idle_frame()


func test_the_banner_and_its_text_let_clicks_through() -> void:
	await _make()
	assert_int(_panel.hint_card().mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(_panel.hint_label().mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_the_banner_fades_while_the_ghost_is_over_it() -> void:
	await _make()
	var banner := _panel.hint_card().get_global_rect()
	assert_bool(banner.has_area()).is_true()
	_panel.fade_for(Rect2(banner.get_center() - Vector2(20, 20), Vector2(40, 40)), 10.0)
	assert_float(_panel.hint_card().modulate.a).is_equal_approx(StaffPanel.FADED_ALPHA, 0.001)
	assert_float(StaffPanel.FADED_ALPHA).is_equal_approx(0.35, 0.001)


func test_a_ghost_that_only_overlaps_the_banner_corner_fades_it() -> void:
	await _make()
	var banner := _panel.hint_card().get_global_rect()
	_panel.fade_for(Rect2(banner.end - Vector2(2, 2), Vector2(30, 30)), 10.0)
	assert_float(_panel.hint_card().modulate.a).is_equal_approx(StaffPanel.FADED_ALPHA, 0.001)


func test_the_banner_is_opaque_while_the_ghost_is_elsewhere_or_absent() -> void:
	await _make()
	var banner := _panel.hint_card().get_global_rect()
	_panel.fade_for(Rect2(banner.get_center(), Vector2(10, 10)), 10.0)
	assert_float(_panel.hint_card().modulate.a).is_equal_approx(StaffPanel.FADED_ALPHA, 0.001)
	_panel.fade_for(Rect2(banner.position - Vector2(200, 200), Vector2(40, 40)), 10.0)
	assert_float(_panel.hint_card().modulate.a).is_equal(1.0)
	_panel.fade_for(Rect2(banner.get_center(), Vector2(10, 10)), 10.0)
	assert_float(_panel.hint_card().modulate.a).is_equal_approx(StaffPanel.FADED_ALPHA, 0.001)
	_panel.fade_for(Rect2(), 10.0)
	assert_float(_panel.hint_card().modulate.a).is_equal(1.0)


func test_the_fade_takes_a_moment_not_a_snap() -> void:
	await _make()
	var banner := _panel.hint_card().get_global_rect()
	_panel.fade_for(Rect2(banner.get_center(), Vector2(10, 10)), 0.01)
	var part: float = _panel.hint_card().modulate.a
	assert_float(part).is_less(1.0)
	assert_float(part).is_greater(StaffPanel.FADED_ALPHA)


func test_with_no_build_mode_the_process_step_keeps_the_banner_opaque() -> void:
	await _make()
	await await_idle_frame()
	assert_float(_panel.hint_card().modulate.a).is_equal(1.0)


func test_ghost_bounds_of_no_build_mode_is_empty() -> void:
	assert_bool(GhostBounds.build_rect(null, null).has_area()).is_false()
