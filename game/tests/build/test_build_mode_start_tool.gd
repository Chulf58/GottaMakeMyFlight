class_name TestBuildModeStartTool
extends GdUnitTestSuite
## A new game starts with no build tool (smoke playtest 5 note g): a stray click
## on the world must not buy a floor tile. BuildMode.initial_tool is the tool
## it starts on; main.tscn sets it to None, and the class default stays Floor
## so the tests that build a bare BuildMode keep painting without picking one.


## The value main.tscn stores for `property` on its BuildMode node, or null.
func _scene_value(property: StringName) -> Variant:
	var state := (load("res://main/main.tscn") as PackedScene).get_state()
	for i in state.get_node_count():
		if state.get_node_name(i) != &"BuildMode":
			continue
		for p in state.get_node_property_count(i):
			if state.get_node_property_name(i, p) == property:
				return state.get_node_property_value(i, p)
	return null


func test_a_bare_build_mode_still_starts_on_floor() -> void:
	var mode: BuildMode = auto_free(BuildMode.new())
	add_child(mode)
	assert_int(mode.tool).is_equal(BuildMode.Tool.FLOOR)


func test_initial_tool_sets_the_tool_it_starts_on() -> void:
	var mode := BuildMode.new()
	mode.initial_tool = BuildMode.Tool.NONE
	add_child(mode)
	auto_free(mode)
	assert_int(mode.tool).is_equal(BuildMode.Tool.NONE)


func test_a_click_on_the_world_with_no_tool_builds_nothing() -> void:
	var mode := BuildMode.new()
	mode.initial_tool = BuildMode.Tool.NONE
	add_child(mode)
	auto_free(mode)
	assert_object(mode.edit_at(mode.grid.cell_to_world(Vector2i(3, 3)))).is_null()


func test_the_game_scene_starts_with_no_tool() -> void:
	assert_int(_scene_value(&"initial_tool")).is_equal(BuildMode.Tool.NONE)
