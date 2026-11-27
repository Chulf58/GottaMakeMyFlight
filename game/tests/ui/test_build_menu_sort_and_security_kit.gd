class_name TestBuildMenuSortAndSecurityKit
extends GdUnitTestSuite
## Regression tests for:
## 1) [Items]-left / [Rooms]-right ordering across every BuildMenuCatalog tab
##    and live BuildMenu rows (including DemoMode Tier-3 teasers).
## 2) Security Lane Build Menu overhaul: hiding the 4 loose core parts from
##    Operations while surfacing Scanner -> Security lane -> Search table ->
##    Confiscation bin, a distinct 4-part Security Lane thumbnail, sharpened
##    ItemInfo copy, and intact underlying 4-part placement / stamp / save-load.

var _port: SubViewport
var _rating: AirportRating
var _pax: PassengerSim
var _unlocks: BuildUnlocks
var _mode: BuildMode
var _menu: BuildMenu


func before() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1536, 864)
	add_child(_port)
	_rating = AirportRating.new()
	_port.add_child(_rating)
	_pax = PassengerSim.new()
	_port.add_child(_pax)
	_unlocks = BuildUnlocks.new()
	_unlocks.rating = _rating
	_unlocks.passengers = _pax
	_unlocks.manual = true
	_port.add_child(_unlocks)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_mode.unlocks = _unlocks
	_mode.require_unlocks = false
	_port.add_child(_mode)
	_mode.set_process(false)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)


func after_test() -> void:
	DemoMode.clear_override()
	PseudoLocale.disable()
	TranslationServer.pseudolocalization_enabled = false
	TranslationServer.reload_pseudolocalization()
	_mode.require_unlocks = false
	_unlocks.set_unlock_all(false)
	_unlocks.from_snapshot({"tier": 1, "made": 0, "shown": [], "seen": [], "firsts": []})
	_mode.set_tool(BuildMode.Tool.NONE)
	_menu._refresh_cards()


func after() -> void:
	DemoMode.clear_override()
	_port.free()


func _visible_row_tools(cat_idx: int) -> Array[BuildMode.Tool]:
	var row := _menu._rows[cat_idx]
	var out: Array[BuildMode.Tool] = []
	for child in row.get_children():
		var btn := child as Button
		if btn == null or not btn.visible:
			continue
		for tool: BuildMode.Tool in BuildMenuCatalog.CATEGORIES[cat_idx]["tools"]:
			if _menu.card(tool) == btn:
				out.append(tool)
				break
	return out


func _assert_items_left_rooms_right(tools: Array, label: String) -> void:
	var seen_room := false
	for tool: BuildMode.Tool in tools:
		if BuildMenuCatalog.is_room_tool(tool):
			seen_room = true
		else:
			(
				assert_bool(seen_room)
				. override_failure_message("%s: non-room tool %d after room tool" % [label, tool])
				. is_false()
			)


func test_every_catalog_tab_places_items_left_and_rooms_right() -> void:
	for i in BuildMenuCatalog.CATEGORIES.size():
		var cat: Dictionary = BuildMenuCatalog.CATEGORIES[i]
		_assert_items_left_rooms_right(cat["tools"], "catalog:%s" % cat["id"])
	var fac: Array = (
		BuildMenuCatalog.CATEGORIES[BuildMenuCatalog.category_index("facilities")]["tools"]
	)
	assert_bool(BuildMenuCatalog.is_room_tool(fac[0])).is_false()
	assert_bool(BuildMenuCatalog.is_room_tool(fac[fac.size() - 1])).is_true()
	var food: Array = BuildMenuCatalog.CATEGORIES[BuildMenuCatalog.category_index("food")]["tools"]
	assert_int(food[0]).is_equal(BuildMode.Tool.GRAB_STALL)
	assert_bool(BuildMenuCatalog.is_room_tool(food[1])).is_true()


func test_live_menu_rows_keep_items_left_and_rooms_right_in_full_and_demo_modes() -> void:
	# Full game (all tiers open).
	DemoMode.set_override_for_test(false)
	_mode.require_unlocks = false
	_menu._refresh_cards()
	for i in BuildMenu.REMOVE_CATEGORY:
		_menu.press_category(i)
		var tools := _visible_row_tools(i)
		_assert_items_left_rooms_right(tools, "full:%s" % BuildMenuCatalog.category_id(i))

	# DemoMode Tier 2 (mixes OPEN and TEASER cards across mixed tabs).
	DemoMode.set_override_for_test(true)
	_mode.require_unlocks = true
	for _i in 60:
		_rating.record_passenger(0, true, PassengerSim.MOOD_MAX)
	for n in 25:
		_pax.outcome.emit(n, true)
	_unlocks.check()
	assert_int(_unlocks.tier()).is_equal(DemoMode.MAX_PLAYABLE_TIER)
	_menu._refresh_cards()
	for i in BuildMenu.REMOVE_CATEGORY:
		_menu.press_category(i)
		var cat_id := BuildMenuCatalog.category_id(i)
		var tools := _visible_row_tools(i)
		_assert_items_left_rooms_right(tools, "demo:%s" % cat_id)
		var seen_item_teaser := false
		var seen_room_teaser := false
		for tool in tools:
			var is_teaser := _menu.card_price_text(tool) == BuildUnlocks.IN_FULL_GAME_TEXT
			if BuildMenuCatalog.is_room_tool(tool):
				if is_teaser:
					seen_room_teaser = true
				else:
					(
						assert_bool(seen_room_teaser)
						. override_failure_message("demo:%s open room after teaser room" % cat_id)
						. is_false()
					)
			else:
				if is_teaser:
					seen_item_teaser = true
				else:
					(
						assert_bool(seen_item_teaser)
						. override_failure_message("demo:%s open item after teaser item" % cat_id)
						. is_false()
					)


func test_operations_hides_four_loose_core_parts_and_orders_security_progression() -> void:
	for hidden_tool: BuildMode.Tool in BuildMode.LANE_TOOLS:
		for cat: Dictionary in BuildMenuCatalog.CATEGORIES:
			(
				assert_bool(cat["tools"].has(hidden_tool))
				. override_failure_message("hidden tool %d still in %s" % [hidden_tool, cat["id"]])
				. is_false()
			)
		assert_int(BuildMenuCatalog.category_of(hidden_tool)).is_equal(BuildMenuCatalog.NO_CATEGORY)
		assert_object(_menu.card(hidden_tool)).is_null()

	var ops := BuildMenuCatalog.category_index("operations")
	var tools: Array = BuildMenuCatalog.CATEGORIES[ops]["tools"]
	var i_scanner := tools.find(BuildMode.Tool.SCANNER)
	assert_int(i_scanner).is_greater_equal(0)
	assert_int(tools[i_scanner + 1]).is_equal(BuildMode.Tool.SECURITY_LANE)
	assert_int(tools[i_scanner + 2]).is_equal(BuildMode.Tool.SEARCH_TABLE)
	assert_int(tools[i_scanner + 3]).is_equal(BuildMode.Tool.CONFISCATION_BIN)


func test_security_lane_has_distinct_thumbnail_and_sharpened_item_info() -> void:
	for hidden_tool: BuildMode.Tool in BuildMode.LANE_TOOLS:
		assert_array(BuildMenuCatalog.item(hidden_tool)).is_empty()
		assert_array(ItemInfo.of(hidden_tool)).is_empty()

	var lane_item := BuildMenuCatalog.item(BuildMode.Tool.SECURITY_LANE)
	var lane_thumb := str(lane_item[1])
	assert_str(lane_thumb).is_equal("security_lane")
	for other_thumb in ["scanner", "arch", "xray_belt", "tray_table", "pickup_table"]:
		assert_str(lane_thumb).is_not_equal(other_thumb)
	assert_str(lane_thumb).is_not_equal(str(BuildMenuCatalog.item(BuildMode.Tool.SCANNER)[1]))

	var lane_path := BuildMenuCatalog.THUMBNAIL_DIR % lane_thumb
	assert_bool(ResourceLoader.exists(lane_path)).is_true()
	var lane_bytes := FileAccess.get_file_as_bytes(lane_path)
	assert_int(lane_bytes.size()).is_greater(0)
	for other_thumb in ["arch", "scanner", "xray_belt"]:
		(
			assert_bool(
				(
					lane_bytes
					!= FileAccess.get_file_as_bytes(BuildMenuCatalog.THUMBNAIL_DIR % other_thumb)
				)
			)
			. is_true()
		)

	var card := _menu.card(BuildMode.Tool.SECURITY_LANE)
	assert_object(card).is_not_null()
	var picture := card.find_children("*", "TextureRect", true, false)[0] as TextureRect
	assert_object(picture.texture).is_not_null()
	assert_str(picture.texture.resource_path).is_equal(lane_path)
	assert_int(picture.find_children("*", "ColorRect", true, false).size()).is_equal(0)

	var scanner_info := " ".join(PackedStringArray(ItemInfo.of(BuildMode.Tool.SCANNER))).to_lower()
	assert_str(scanner_info).contains("starter")
	assert_str(scanner_info).contains("block")

	var lane_info := (
		" ".join(PackedStringArray(ItemInfo.of(BuildMode.Tool.SECURITY_LANE))).to_lower()
	)
	assert_str(lane_info).contains("1.9x")
	assert_str(lane_info).contains("repack")
	assert_str(lane_info).contains("2x")
	assert_str(lane_info).contains("fast-track")

	PseudoLocale.enable(0.4)
	for part: String in (
		ItemInfo.of(BuildMode.Tool.SCANNER) + ItemInfo.of(BuildMode.Tool.SECURITY_LANE)
	):
		assert_str(part).starts_with("[")


func test_underlying_four_core_lane_tools_placement_stamp_and_save_load_intact() -> void:
	var port: SubViewport = auto_free(SubViewport.new())
	port.size = Vector2i(1280, 720)
	add_child(port)
	var mode := BuildMode.new()
	mode.grid_size = Vector2i(18, 18)
	port.add_child(mode)
	mode.set_process(false)
	var menu := BuildMenu.new()
	menu.build_mode = mode
	port.add_child(menu)
	var grid := mode.grid
	var floor_edits: Array[BuildEdit] = []
	for y in range(2, 16):
		for x in range(2, 16):
			floor_edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(floor_edits)
	assert_int(grid.floor_at(Vector2i(5, 6))).is_equal(BuildGrid.FLOOR_TILE)

	# Individual 4-part placement + BuildUndo + re-apply forms a COMPLETE lane.
	var geom := SecurityLanes.geometry(Vector2i(5, 6), 0, SecurityLanes.RIGHT)
	var tool_cells := [
		[BuildMode.Tool.TRAY_TABLE, geom["tray_table"], "Tray table"],
		[BuildMode.Tool.XRAY_BELT, geom["xray_belt"], "X-ray belt"],
		[BuildMode.Tool.ARCH, geom["arch"], "Security arch"],
		[BuildMode.Tool.PICKUP_TABLE, geom["pickup_table"], "Pickup table"],
	]
	mode.facing = 0
	for pair in tool_cells:
		var pt := grid.cell_to_world(pair[1])
		mode.set_tool(pair[0])
		assert_int(mode.tool).is_equal(pair[0])
		assert_bool(mode.apply_at(pt).ok).is_true()
	var undo_part := mode.undo()
	assert_bool(undo_part != null and undo_part.ok).is_true()
	assert_int(grid.object_at(geom["pickup_table"])).is_equal(0)
	mode.set_tool(BuildMode.Tool.PICKUP_TABLE)
	assert_bool(mode.apply_at(grid.cell_to_world(geom["pickup_table"])).ok).is_true()

	var lanes := SecurityLanes.new()
	lanes.rebuild(grid)
	var arch_id := grid.object_at(geom["arch"])
	assert_int(arch_id).is_greater(0)
	assert_bool(lanes.is_complete(arch_id)).is_true()

	# Eyedropper picking each hidden part arms its tool without crashing BuildMenu,
	# and BuiltItemCard inspects each placed piece cleanly even without ItemInfo.
	var sim := PassengerSim.new()
	sim.grid = grid
	port.add_child(sim)
	sim.set_process(false)
	sim.layout.rebuild(grid)
	var sel := BuiltSelection.new()
	var card := BuiltItemCard.new()
	card.sim = sim
	card.build_mode = mode
	card.selection = sel
	port.add_child(card)
	for pair in tool_cells:
		var tool_id: BuildMode.Tool = pair[0]
		var cell: Vector2i = pair[1]
		var expected_name: String = pair[2]
		mode.set_tool(BuildMode.Tool.NONE)
		assert_bool(mode.pick_eyedropper_at(grid.cell_to_world(cell))).is_true()
		assert_int(mode.tool).is_equal(tool_id)
		assert_int(menu.open_category()).is_equal(BuildMenu.NO_CATEGORY)
		assert_bool(menu.is_tray_open()).is_false()
		var obj_id := grid.object_at(cell)
		assert_int(obj_id).is_greater(0)
		sel.select_object(obj_id)
		card.refresh()
		assert_bool(card.visible).is_true()
		assert_str(card.name_text()).is_equal(expected_name)
		assert_bool(card.fast_track_button().visible).is_true()

	# Save/load round-trip preserves all 4 core lane parts and COMPLETE recognition.
	var snap := BuildGridSave.to_snapshot(grid)
	var reloaded := BuildGrid.new(Vector2i(18, 18))
	assert_bool(BuildGridSave.load_into(reloaded, snap)).is_true()
	var reloaded_lanes := SecurityLanes.new()
	reloaded_lanes.rebuild(reloaded)
	var reloaded_arch := reloaded.object_at(geom["arch"])
	assert_bool(reloaded_lanes.is_complete(reloaded_arch)).is_true()
	assert_int(reloaded.object_at(geom["tray_table"])).is_greater(0)
	assert_int(reloaded.object_at(geom["xray_belt"])).is_greater(0)
	assert_int(reloaded.object_at(geom["pickup_table"])).is_greater(0)

	# 1-click SecurityLaneStamp placement + BuildUndo + re-apply forms a COMPLETE lane.
	mode.set_tool(BuildMode.Tool.SECURITY_LANE)
	var stamp_pt := grid.cell_to_world(Vector2i(11, 6))
	var stamp_anchor := SecurityLaneStamp.anchor_for(grid, stamp_pt, 0)
	assert_bool(mode.apply_at(stamp_pt).ok).is_true()
	lanes.rebuild(grid)
	assert_bool(lanes.is_complete(grid.object_at(stamp_anchor))).is_true()
	var undo_stamp := mode.undo()
	assert_bool(undo_stamp != null and undo_stamp.ok).is_true()
	assert_int(grid.object_at(stamp_anchor)).is_equal(0)
	assert_bool(mode.apply_at(stamp_pt).ok).is_true()
	lanes.rebuild(grid)
	assert_bool(lanes.is_complete(grid.object_at(stamp_anchor))).is_true()
