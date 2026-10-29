class_name TestPlaytestHookMoneyEvents
extends GdUnitTestSuite
## The hook logs a hire, a bag outcome and the wage charge and payment, on the
## real main scene. The bag and wage events come from the sim signals, so the
## cases emit those signals and read what the hook wrote.

const MAIN := "res://main/main.tscn"
const HOOK := preload("res://debug/playtest_hook.gd")
var _dir := SaveTestKit.run_dir("playtest_money_events_test")

var _main: Node
var _hook: Node
var _staff: StaffSim
var _baggage: BaggageSim
var _settlement: Settlement


func before() -> void:
	_main = load(MAIN).instantiate()
	add_child(_main)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	_staff = _main.get_node("Staff")
	_baggage = _main.get_node("BaggageSim")
	_settlement = _main.get_node("Settlement")
	_hook = HOOK.new()
	_hook.configure(true, _dir)
	add_child(_hook)
	assert_bool(_hook.attach(_main)).is_true()


func after() -> void:
	_hook.detach()
	_hook.free()
	_main.free()
	for name in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute("%s/%s" % [_dir, name])
	DirAccess.remove_absolute(_dir)


func _events_of(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event in _hook.events_since(0):
		if event["type"] == type:
			out.append(event)
	return out


func test_a_hire_through_the_pool_is_logged_with_its_role_and_id() -> void:
	var before_count := _events_of("staff_hired").size()
	var id := _staff.hire(StaffMember.Role.SECURITY)
	var hired := _events_of("staff_hired")
	print("staff_hired events %d -> %d, last %s" % [before_count, hired.size(), hired.back()])
	assert_int(hired.size()).is_equal(before_count + 1)
	assert_dict(hired.back()["data"]).is_equal({"id": id, "role": "SECURITY"})


func test_a_hire_through_the_hook_is_logged_once() -> void:
	var before_count := _events_of("staff_hired").size()
	var id: int = _hook.hire_staff("shop")
	var hired := _events_of("staff_hired")
	assert_int(hired.size()).is_equal(before_count + 1)
	assert_dict(hired.back()["data"]).is_equal({"id": id, "role": "SHOP"})


func test_a_loaded_and_a_missed_bag_are_logged_apart() -> void:
	_baggage.bag_settled.emit(4, 12, "FL1", true)
	_baggage.bag_settled.emit(5, 13, "FL1", false)
	var loaded := _events_of("bag_loaded")
	var missed := _events_of("bag_missed")
	assert_dict(loaded.back()["data"]).is_equal({"bag": 4, "passenger": 12, "flight": "FL1"})
	assert_dict(missed.back()["data"]).is_equal({"bag": 5, "passenger": 13, "flight": "FL1"})


func test_the_wage_charge_and_a_later_payment_are_logged() -> void:
	_settlement.wages_charged.emit(3, 100, 40)
	_settlement.wages_paid.emit(40, 0)
	assert_dict(_events_of("wages_charged").back()["data"]).is_equal(
		{"day": 3, "paid": 100, "owed": 40}
	)
	assert_dict(_events_of("wages_paid").back()["data"]).is_equal({"amount": 40, "owed": 0})


func test_the_new_events_are_declared_event_types() -> void:
	for type in ["staff_hired", "bag_loaded", "bag_missed", "wages_charged", "wages_paid"]:
		assert_bool(HOOK.EVENT_TYPES.has(type) or HOOK.OPTIONAL_EVENT_TYPES.has(type)).is_true()


func test_detaching_lets_go_of_the_money_signals() -> void:
	_hook.detach()
	assert_bool(_staff.hired.is_connected(_hook._on_staff_hired)).is_false()
	assert_bool(_baggage.bag_settled.is_connected(_hook._on_bag_settled)).is_false()
	assert_bool(_settlement.wages_charged.is_connected(_hook._on_wages_charged)).is_false()
	assert_bool(_settlement.wages_paid.is_connected(_hook._on_wages_paid)).is_false()
	assert_bool(_hook.attach(_main)).is_true()
	assert_bool(_staff.hired.is_connected(_hook._on_staff_hired)).is_true()
