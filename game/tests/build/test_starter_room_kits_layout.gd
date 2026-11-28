class_name TestStarterRoomKitsLayout
extends GdUnitTestSuite
## Layout, staff-spot, doorway clearance, walkability, Words.msgids(), and
## indoor Break Room tests across all 14 starter room kits and all 4 rotations.

var _finances: Finances
var _mode: BuildMode


func before_test() -> void:
	_finances = Finances.new()
	_finances.wallet.credit(100000, Wallet.Category.FEES)
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(24, 24)
	_mode.initial_tool = BuildMode.Tool.NONE
	_mode.finances = _finances
	add_child(_mode)
	_mode.set_process(false)
	var edits: Array[BuildEdit] = []
	for y in range(2, 22):
		for x in range(2, 22):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)
	# Place a terminal entrance and seal perimeter so staff_reach() and
	# is_passenger_cell() reflect real terminal conditions.
	(
		assert_bool(
			_mode.grid.apply(BuildEdit.place_object(&"entrance_door", Vector2i(2, 10), 3)).ok
		)
		. is_true()
	)
	EnclosureKit.close_floor(_mode.grid)


func after_test() -> void:
	_mode.free()
	_finances.free()


func _reachable_cells(grid: BuildGrid, start: Vector2i) -> Dictionary:
	var seen := {}
	if not grid.is_walkable(start):
		return seen
	var queue: Array[Vector2i] = [start]
	seen[start] = true
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		for step in BuildGrid.SIDE_STEP:
			var nxt: Vector2i = cur + step
			if not seen.has(nxt) and grid.can_step(cur, nxt):
				seen[nxt] = true
				queue.append(nxt)
	return seen


func _place_kit(kit_id: StringName, centre: Vector2i, turns: int) -> int:
	_mode.starter_kit.arm(kit_id)
	_mode.starter_kit.turns = turns
	var res := _mode.starter_kit.place_at(centre)
	(
		assert_bool(res.ok)
		. override_failure_message("%s turn=%d failed: %s" % [kit_id, turns, res.reason_text()])
		. is_true()
	)
	return res.room_id


func test_all_14_kits_have_clear_doorways_and_walkable_interior_spots_in_all_rotations() -> void:
	var centre := Vector2i(12, 12)
	var bag_centres := {0: Vector2i(12, 3), 1: Vector2i(20, 12), 3: Vector2i(3, 15)}
	var kits := StarterRoomKits.kit_ids()
	assert_int(kits.size()).is_equal(14)
	for kit_id: StringName in kits:
		for turns in 4:
			var tag := "%s turn=%d" % [kit_id, turns]
			if kit_id == &"bag_room" and turns == 2:
				_mode.starter_kit.arm(kit_id)
				_mode.starter_kit.turns = turns
				var south_refusal := _mode.starter_kit.place_at(Vector2i(12, 20))
				assert_bool(south_refusal.ok).is_false()
				assert_int(south_refusal.reason).is_equal(BuildResult.Reason.KIT_NEEDS_APRON_WALL)
				var indoor_refusal := _mode.starter_kit.place_at(centre)
				assert_bool(indoor_refusal.ok).is_false()
				assert_int(indoor_refusal.reason).is_equal(BuildResult.Reason.KIT_NEEDS_APRON_WALL)
				continue
			var kit_centre: Vector2i = bag_centres[turns] if kit_id == &"bag_room" else centre
			var room_id := _place_kit(kit_id, kit_centre, turns)
			var grid := _mode.grid
			var room := grid.get_room(room_id)
			var area: Rect2i = room["rect"]
			var status := RoomRules.status(grid, room_id)
			(
				assert_bool(status.ok)
				. override_failure_message("%s not ready: %s" % [tag, str(status.notes)])
				. is_true()
			)

			var door := StarterRoomKits.door_edge(kit_id, kit_centre, turns)
			var door_cell: Vector2i = door["cell"]
			var door_side: int = door["side"]
			var outside: Vector2i = door["outside"]
			var inward := door_cell - BuildGrid.SIDE_STEP[door_side]
			(
				assert_int(grid.object_at(door_cell))
				. override_failure_message("%s doorway cell %s occupied" % [tag, door_cell])
				. is_equal(0)
			)
			(
				assert_bool(grid.is_walkable(door_cell))
				. override_failure_message("%s doorway cell %s not walkable" % [tag, door_cell])
				. is_true()
			)
			(
				assert_int(grid.object_at(inward))
				. override_failure_message("%s inward entry cell %s occupied" % [tag, inward])
				. is_equal(0)
			)
			(
				assert_bool(grid.is_walkable(inward))
				. override_failure_message("%s inward entry cell %s not walkable" % [tag, inward])
				. is_true()
			)
			(
				assert_bool(grid.can_step(outside, door_cell))
				. override_failure_message(
					"%s cannot step from %s to %s" % [tag, outside, door_cell]
				)
				. is_true()
			)

			var reach := _reachable_cells(grid, outside)
			var staff_reach := grid.staff_reach()

			for oid in grid.object_ids():
				var rec := grid.get_object(oid)
				var def_id := StringName(rec["def"])
				if def_id == &"entrance_door":
					continue
				var def := BuildCatalog.get_def(def_id)
				var anchor: Vector2i = rec["anchor"]
				var facing: int = rec["facing"]
				for fp_cell in def.footprint(anchor, facing):
					(
						assert_bool(area.has_point(fp_cell))
						. override_failure_message(
							"%s %s footprint %s outside %s" % [tag, def_id, fp_cell, area]
						)
						. is_true()
					)
				var inter := def.interaction_cell(anchor, facing)
				if inter != BuildObjectDef.NO_CELL:
					(
						assert_bool(area.has_point(inter))
						. override_failure_message(
							"%s %s interaction %s outside %s" % [tag, def_id, inter, area]
						)
						. is_true()
					)
					(
						assert_bool(reach.has(inter))
						. override_failure_message(
							"%s %s interaction %s unreachable" % [tag, def_id, inter]
						)
						. is_true()
					)
				for seat in def.seat_descriptors(anchor, facing):
					var approach: Vector2i = seat["approach"]
					(
						assert_bool(area.has_point(approach))
						. override_failure_message(
							"%s %s seat approach %s outside %s" % [tag, def_id, approach, area]
						)
						. is_true()
					)
					(
						assert_bool(reach.has(approach))
						. override_failure_message(
							"%s %s seat approach %s unreachable" % [tag, def_id, approach]
						)
						. is_true()
					)
				if ShopCounters.is_counter(grid, oid):
					(
						assert_bool(ShopCounters.usable(grid, oid))
						. override_failure_message("%s counter %s not usable" % [tag, def_id])
						. is_true()
					)
					(
						assert_bool(ShopCounters.blocked(grid, oid))
						. override_failure_message(
							"%s counter %s staff spot blocked" % [tag, def_id]
						)
						. is_false()
					)
					var rear_spot := anchor + BuildObjectDef.rotate_offset(Vector2i(0, -1), facing)
					(
						assert_bool(area.has_point(rear_spot))
						. override_failure_message(
							"%s counter %s rear spot %s outside %s" % [tag, def_id, rear_spot, area]
						)
						. is_true()
					)
					(
						assert_that(ShopCounters.spot(grid, oid))
						. override_failure_message(
							"%s counter %s spot should be rear %s" % [tag, def_id, rear_spot]
						)
						. is_equal(rear_spot)
					)
					(
						assert_bool(reach.has(rear_spot))
						. override_failure_message(
							(
								"%s counter %s rear spot %s unreachable from door"
								% [tag, def_id, rear_spot]
							)
						)
						. is_true()
					)
					(
						assert_bool(staff_reach.has(rear_spot))
						. override_failure_message(
							(
								"%s counter %s rear spot %s not in staff_reach"
								% [tag, def_id, rear_spot]
							)
						)
						. is_true()
					)

			assert_bool(_mode.undo().ok).override_failure_message(tag).is_true()


func test_food_and_shop_starter_kits_build_valid_layouts_with_reachable_slots() -> void:
	var centre := Vector2i(12, 12)
	var terminal := TerminalLayout.new()
	var cafes := CafeLayout.new()
	var shops := ShopLayout.new()

	var food_min_seats := {&"cafe": 2, &"bar": 2, &"restaurant": 4}
	for kit_id: StringName in food_min_seats:
		for turns in 4:
			var tag := "%s turn=%d" % [kit_id, turns]
			var room_id := _place_kit(kit_id, centre, turns)
			terminal.rebuild(_mode.grid)
			cafes.rebuild(_mode.grid, terminal)
			assert_int(cafes.cafes.size()).override_failure_message(tag).is_equal(1)
			assert_int(cafes.cafes[0]["room"]).is_equal(room_id)
			assert_int((cafes.cafes[0]["counters"] as Array).size()).is_equal(1)
			(
				assert_int((cafes.cafes[0]["seats"] as Array).size())
				. override_failure_message(tag)
				. is_equal(food_min_seats[kit_id])
			)
			assert_bool(_mode.undo().ok).is_true()

	var shop_kits: Array[StringName] = [
		&"kiosk", &"pharmacy", &"duty_free", &"fashion", &"play_area", &"lounge", &"shower"
	]
	for kit_id: StringName in shop_kits:
		for turns in 4:
			var tag := "%s turn=%d" % [kit_id, turns]
			var room_id := _place_kit(kit_id, centre, turns)
			shops.rebuild(_mode.grid)
			assert_int(shops.shops.size()).override_failure_message(tag).is_equal(1)
			assert_int(shops.shops[0]["room"]).is_equal(room_id)
			assert_int((shops.shops[0]["slots"] as Array).size()).is_greater(0)
			assert_bool(_mode.undo().ok).is_true()


func test_words_msgids_includes_all_14_starter_kit_names() -> void:
	var msgids := StarterRoomKits.Words.new().msgids()
	for kit_id: StringName in StarterRoomKits.kit_ids():
		var kit_name := StarterRoomKits.display_name(kit_id)
		(
			assert_bool(msgids.has(kit_name))
			. override_failure_message("Missing msgid for %s" % kit_name)
			. is_true()
		)
	assert_bool(msgids.has("Starter Break Room")).is_true()


func test_break_room_kit_is_spacious_indoor_lounge_and_room_type_accepts_seating() -> void:
	assert_int(StarterRoomKits.max_tier(&"break_room")).is_less_equal(DemoMode.MAX_PLAYABLE_TIER)
	assert_int(StarterRoomKits.max_tier(&"break_room")).is_equal(2)
	var kit := StarterRoomKits.get_kit(&"break_room")
	var sz: Vector2i = kit["size"]
	assert_bool(sz.x >= 4 and sz.y >= 4).is_true()
	assert_str(str(kit["thumbnail"])).is_equal("lounge_sofa")
	var defs: Array[StringName] = []
	for piece: Dictionary in kit["pieces"]:
		defs.append(piece["def"])
	assert_bool(defs.has(&"bench_1a")).is_false()
	assert_bool(defs.has(&"lounge_sofa")).is_true()
	assert_bool(defs.has(&"lounge_armchair")).is_true()

	var break_type := RoomTypes.get_type(&"break_room")
	var need_id: StringName = break_type.required[0][0]
	var accepted := break_type.pieces_for(need_id)
	assert_bool(accepted.has(&"lounge_sofa")).is_true()
	assert_bool(accepted.has(&"lounge_armchair")).is_true()
	assert_bool(accepted.has(&"bench_1a")).is_true()

	var room_id := _place_kit(&"break_room", Vector2i(12, 12), 0)
	assert_bool(StaffBreakRooms.is_ready(_mode.grid, room_id)).is_true()
	var spots := StaffBreakRooms.spots_in(_mode.grid, room_id)
	assert_int(spots.size()).is_greater_equal(8)
	assert_bool(_mode.undo().ok).is_true()
