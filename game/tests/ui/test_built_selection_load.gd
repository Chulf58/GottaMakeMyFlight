class_name TestBuiltSelectionLoad
extends GdUnitTestSuite
## A loaded world is a new world: the selected built item is cleared even when
## the loaded world holds an item with the same id, so the window never shows
## an unrelated item.

const SEED := 6_113_312

var _settings_path := SaveTestKit.run_path("built_selection_load_alerts")

var _main: Node
var _hud: PassengerHud
var _sim: PassengerSim


func before() -> void:
	_main = load(SaveTestKit.MAIN).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(SEED)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	(_main.get_node("PassengerHud") as PassengerHud).alert_settings_path = _settings_path
	add_child(_main)
	_hud = _main.get_node("PassengerHud")
	_sim = _main.get_node("PassengerSim")
	(_main.get_node("BuildMode") as BuildMode).set_tool(BuildMode.Tool.NONE)
	_hud.press_starter_terminal()
	StaffTestKit.staff_all(_main.get_node("Staff"))


func after() -> void:
	_main.free()
	DirAccess.remove_absolute(_settings_path)


func test_a_load_clears_the_selection_even_when_the_world_reuses_its_id() -> void:
	var inspect := _hud.find_child("PassengerInspect", true, false) as PassengerInspect
	var selection := inspect.built_card.selection
	var desk: int = _sim.layout.desks[0]
	selection.kind = BuiltSelection.Kind.OBJECT
	selection.id = desk
	_hud.refresh()
	assert_bool(inspect.visible).is_true()
	assert_str(inspect.built_card.name_text()).is_equal("Check-in desk")
	SaveTestKit.step(_main)
	var save: SaveGame = _main.get_node("SaveGame")
	var data := save.snapshot()
	assert_bool(data.is_empty()).is_false()
	assert_bool(save.load_world(data)).is_true()
	_hud.refresh()
	var stands := not _sim.grid.get_object(desk).is_empty()
	print("after load: desk %d stands %s, selection kind %d" % [desk, stands, selection.kind])
	assert_bool(stands).is_true()
	assert_int(selection.kind).is_equal(BuiltSelection.Kind.NONE)
	assert_bool(inspect.visible).is_false()
