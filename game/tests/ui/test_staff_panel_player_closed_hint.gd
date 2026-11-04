class_name TestStaffPanelPlayerClosedHint
extends GdUnitTestSuite
## The hire hint ignores stations the player closed (decision select-placed-
## items-design-click-order-gold-footprint-highli): a closed desk asks for no
## agent, and the hint still shows while a desk the player left open has
## nobody to work it.

const CHECKIN := StaffMember.Role.CHECKIN

var _w: PassengerTestWorld
var _panel: StaffPanel
var _a := 0
var _b := 0


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_w = PassengerTestWorld.reference_world(5)
	_w.auto_staff = false
	var desks := _w.sim.layout.desks.duplicate()
	desks.sort()
	_a = desks[0]
	_b = desks[1]
	_panel = auto_free(StaffPanel.new())
	_panel.staff = _w.staff
	add_child(_panel)


func after_test() -> void:
	_w.free_all()
	_w = null


func _hinted() -> bool:
	return _panel.hiring_hint_roles().has(CHECKIN)


func test_an_open_desk_without_staff_shows_the_hint_and_closed_desks_do_not() -> void:
	var with_none := _hinted()
	_w.staff.closures.set_closed(_a, true)
	var one_open := _hinted()
	_w.staff.closures.set_closed(_b, true)
	var all_closed := _hinted()
	print(
		(
			"hint with desks open %s, one closed %s, all closed %s; text '%s'"
			% [with_none, one_open, all_closed, _panel.hint_label().text]
		)
	)
	assert_bool(with_none).is_true()
	assert_bool(one_open).is_true()
	assert_bool(all_closed).is_false()
	# The banner was refreshed by the closure itself (staff_changed).
	assert_str(_panel.hint_label().text).not_contains(StaffPanel.HINTS[CHECKIN])


func test_a_closed_desk_beside_a_staffed_desk_shows_no_hint() -> void:
	_w.staff.closures.set_closed(_a, true)
	_w.staff.hire(CHECKIN)
	_w.run_to(_w.clock.tick + 600)
	print("desk %d open %s, desk %d closed; hint %s" % [_b, _w.staff.is_open(_b), _a, _hinted()])
	assert_bool(_w.staff.is_open(_b)).is_true()
	assert_bool(_hinted()).is_false()
	assert_str(_panel.hint_label().text).not_contains(StaffPanel.HINTS[CHECKIN])
