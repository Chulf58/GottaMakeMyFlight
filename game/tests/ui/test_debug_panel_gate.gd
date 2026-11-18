class_name TestDebugPanelGate
extends GdUnitTestSuite
## The HUD's Debug toggle and panel exist only in dev builds (decision
## debug-panel-is-for-dev-builds-only-the-hud-s-debug-toggle-an, board t0b).
## PassengerHud.debug_tools defaults to OS.is_debug_build(); a test flips it
## before add_child.

const DEBUG_NODES := ["DebugCorner", "DebugPanelDock", "DebugToggle", "DebugPanel"]

var _world: PassengerTestWorld
var _hud: PassengerHud


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))


func after_test() -> void:
	if _hud != null:
		_hud.free()
		_hud = null
	_world.free_all()


func _new_hud() -> void:
	_hud = PassengerHud.new()
	_hud.clock = _world.clock
	_hud.flights = _world.flights
	_hud.sim = _world.sim


func _hud_with(debug_tools: bool) -> void:
	_new_hud()
	_hud.debug_tools = debug_tools
	add_child(_hud)


## The HUD is added to the tree so after_test() frees it with its members: a HUD
## that never enters the tree leaves the nodes its field initialisers make (92 of
## them) as orphans, because only _ready() parents them.
func test_the_gate_follows_the_build_type_by_default() -> void:
	_new_hud()
	add_child(_hud)
	assert_bool(_hud.debug_tools).is_equal(OS.is_debug_build())
	# The control: the built nodes agree with the flag, so the default was acted on.
	var toggle := _hud.find_child("DebugToggle", true, false)
	assert_bool(toggle != null).is_equal(OS.is_debug_build())


func test_without_the_gate_no_debug_node_is_built() -> void:
	_hud_with(false)
	for node_name: String in DEBUG_NODES:
		assert_object(_hud.find_child(node_name, true, false)).is_null()
	assert_bool(_hud.is_debug_open()).is_false()
	# Control: the rest of the HUD is built, so the missing nodes are the gate's doing.
	assert_object(_hud.find_child("FollowText", true, false)).is_not_null()


func test_without_the_gate_the_debug_shortcuts_are_not_reachable_from_the_tree() -> void:
	_hud_with(false)
	for button in _hud.find_children("*", "Button", true, false):
		var text := (button as Button).text
		assert_str(text).is_not_equal("Debug")
		assert_str(text).is_not_equal("Starter terminal")
		assert_str(text).is_not_equal("Spawn %d passengers" % PassengerHud.DEBUG_BATCH)


func test_with_the_gate_the_toggle_and_panel_exist() -> void:
	_hud_with(true)
	for node_name: String in DEBUG_NODES:
		assert_object(_hud.find_child(node_name, true, false)).is_not_null()
	var toggle := _hud.find_child("DebugToggle", true, false) as Button
	assert_bool(_hud.is_debug_open()).is_false()
	toggle.button_pressed = true
	assert_bool(_hud.is_debug_open()).is_true()
