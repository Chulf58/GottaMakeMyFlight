class_name TestStaffPanelShop
extends GdUnitTestSuite
## The hiring panel's shop staff column: Hire and Fire go through StaffSim,
## the counts follow a server going on duty, and the hint asks for shop staff
## once a ready cafe or kiosk stands and nobody is hired for it.

const SHOP := StaffMember.Role.SHOP

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


func _make(cafes: bool) -> void:
	if cafes:
		var grid := BuildGrid.new()
		CafeTestLayout.build(grid)
		_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(1000000))
	else:
		_w = PassengerTestWorld.reference_world()
	_w.auto_staff = false
	_panel = auto_free(StaffPanel.new())
	_panel.staff = _w.staff
	add_child(_panel)


func test_the_panel_has_a_shop_staff_column_with_hire_and_fire() -> void:
	_make(true)
	assert_array(StaffPanel.ROLES).contains([SHOP])
	assert_str(_panel.hire_button(SHOP).name).is_equal("HireShop")
	assert_str(_panel.fire_button(SHOP).name).is_equal("FireShop")
	assert_bool(_panel.fire_button(SHOP).disabled).is_true()


func test_hire_adds_a_server_and_the_count_follows_it_on_duty() -> void:
	_make(true)
	assert_str(_panel.counts_text(SHOP)).is_equal("0 hired, 0 on duty")
	_panel.hire_button(SHOP).pressed.emit()
	assert_int(_w.staff.count(SHOP)).is_equal(1)
	assert_str(_panel.counts_text(SHOP)).is_equal("1 hired, 0 on duty")
	assert_bool(_panel.fire_button(SHOP).disabled).is_false()
	while _w.staff.on_duty_count(SHOP) == 0 and _w.clock.tick < 900:
		_w.step()
	assert_str(_panel.counts_text(SHOP)).is_equal("1 hired, 1 on duty")
	_panel.fire_button(SHOP).pressed.emit()
	assert_int(_w.staff.count(SHOP)).is_equal(0)


func test_the_hint_asks_for_shop_staff_only_while_a_ready_cafe_has_none() -> void:
	_make(true)
	assert_str(_panel.hint_text()).contains("Hire shop staff")
	_w.staff.hire(SHOP)
	assert_str(_panel.hint_text()).not_contains("Hire shop staff")


func test_without_a_cafe_or_kiosk_the_hint_does_not_ask_for_shop_staff() -> void:
	_make(false)
	assert_str(_panel.hint_text()).not_contains("Hire shop staff")
