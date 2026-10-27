class_name TestPassengerHudDebugEconomy
extends GdUnitTestSuite
## The economy policy of the Debug panel (Economy 7/8): its actions are debug
## aids and say so. The starter terminal is free and pays no refund when a
## piece comes down; spawned passengers are normal ones and pay their fee.

var _world: PassengerTestWorld
var _hud: PassengerHud
var _finances: Finances
var _mode: BuildMode


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_world = PassengerTestWorld.make(
		PassengerTestWorld.floored(Vector2i(8, 6)), PassengerTestWorld.starts_with(10, 20)
	)
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.finances = _finances
	add_child(_mode)
	_hud = PassengerHud.new()
	_hud.clock = _world.clock
	_hud.flights = _world.flights
	_hud.sim = _world.sim
	_hud.build_mode = _mode
	add_child(_hud)


func after_test() -> void:
	_hud.free()
	_mode.free()
	_finances.free()
	_world.free_all()


func _label_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for label in _hud.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out


func test_the_starter_terminal_costs_nothing_even_with_a_wallet() -> void:
	var balance := _finances.wallet.balance
	assert_int(balance).is_equal(PriceTable.STARTING_BUDGET)
	_hud.press_starter_terminal()
	assert_str(_hud.status_text()).is_equal("Starter terminal built")
	assert_int(_mode.grid.object_ids().size()).is_greater(0)
	assert_int(_finances.wallet.balance).is_equal(balance)


func test_taking_down_a_starter_terminal_piece_pays_no_refund() -> void:
	_hud.press_starter_terminal()
	var balance := _finances.wallet.balance
	_mode.set_tool(BuildMode.Tool.REMOVE)
	var id := _mode.grid.object_ids()[0]
	var anchor: Vector2i = _mode.grid.get_object(id)["anchor"]
	assert_bool(_mode.apply_at(_mode.grid.cell_to_world(anchor)).ok).is_true()
	assert_int(_finances.wallet.balance).is_equal(balance)


func test_the_debug_panel_states_the_economy_policy() -> void:
	assert_array(_label_texts()).contains([PassengerHud.DEBUG_POLICY_TEXT])
	assert_str(PassengerHud.DEBUG_POLICY_TEXT).starts_with("Debug only")
	assert_str(PassengerHud.DEBUG_POLICY_TEXT).contains("free")
	assert_str(PassengerHud.DEBUG_POLICY_TEXT).contains("fee")
