class_name TestHintRulesClosed
extends GdUnitTestSuite
## HintRules.read_world(): a desk the player closed (StationClosures) is no
## shortage, so the second_hire hint never asks for a hire to work it
## (decision select-placed-items-design-click-order-gold-footprint-highli). A
## desk left open with nobody to work it still is one.

const CHECKIN := StaffMember.Role.CHECKIN

var _w: PassengerTestWorld
var _desks: Array[int] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(14, 12))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 11), 2)
	_desks = [
		PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(5, 3), 0),
		PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(9, 3), 0),
	]
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_w.auto_staff = false


func after_test() -> void:
	_w.free_all()
	_w = null


func _shortage() -> Array:
	return HintRules.read_world(_w.sim, [])["shortage_roles"]


func test_desks_the_player_closed_are_no_shortage_and_an_open_one_is() -> void:
	var none_closed := _shortage()
	_w.staff.closures.set_closed(_desks[0], true)
	var one_open := _shortage()
	_w.staff.closures.set_closed(_desks[1], true)
	var all_closed := _shortage()
	print(
		"shortage: none closed %s, one open %s, all closed %s" % [none_closed, one_open, all_closed]
	)
	assert_array(none_closed).is_equal([CHECKIN])
	assert_array(one_open).is_equal([CHECKIN])
	assert_array(all_closed).is_empty()
