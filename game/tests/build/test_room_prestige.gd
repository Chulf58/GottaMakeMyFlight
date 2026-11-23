class_name TestRoomPrestige
extends GdUnitTestSuite
## Room Prestige L1-5 (Slice S3-P2a; decision b764f946): deterministic scoring
## from room size, decor with diminishing returns, functional pieces, and
## Annual Awards trophies; RoomPanel display; CafeSim and ShopSim spend lift.

var _world: PassengerTestWorld
var _port: SubViewport


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null
	if _port != null:
		_port.free()
		_port = null


func _floored_grid(size := Vector2i(20, 20)) -> BuildGrid:
	var grid := BuildGrid.new(size)
	var edits: Array[BuildEdit] = []
	for y in range(1, size.y - 1):
		for x in range(1, size.x - 1):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(edits)
	return grid


func _place(grid: BuildGrid, def_id: StringName, anchor: Vector2i, facing := 0) -> int:
	var res := grid.apply(BuildEdit.place_object(def_id, anchor, facing))
	assert_bool(res.ok).override_failure_message(res.reason_text()).is_true()
	return res.object_id


func _panel_texts(panel: RoomPanel) -> Array[String]:
	var out: Array[String] = []
	for label in panel.find_children("*", "Label", true, false):
		if (label as Label).is_visible_in_tree():
			out.append((label as Label).text)
	return out


func test_bare_starter_rooms_score_level_one_with_zero_bonus() -> void:
	var grid := _floored_grid()
	var room_id := grid.apply(BuildEdit.place_room(Rect2i(2, 2, 4, 4), &"cafe")).room_id
	_place(grid, &"cafe_counter", Vector2i(2, 2))
	_place(grid, &"cafe_table", Vector2i(2, 5))
	var eval := RoomPrestige.evaluate_room(grid, room_id)
	assert_int(eval["level"]).is_equal(1)
	assert_int(eval["spend_bonus_percent"]).is_equal(0)
	assert_int(eval["break_bonus_percent"]).is_equal(0)
	assert_int(eval["decor_count"]).is_equal(0)
	assert_int(eval["unique_decor"]).is_equal(0)
	assert_int(RoomPrestige.room_level_at(grid, Vector2i(3, 3))).is_equal(1)
	assert_int(RoomPrestige.room_level_at(grid, Vector2i(0, 0))).is_equal(1)
	assert_int(RoomPrestige.apply_spend_bonus(15, 1)).is_equal(15)

	# Existing 6x6 reference layouts must stay L1 so baseline economy tests hold.
	var cafe_grid := BuildGrid.new()
	var cafe_ids := CafeTestLayout.build(cafe_grid, true)
	assert_int(RoomPrestige.evaluate_room(cafe_grid, cafe_ids["air_room"])["level"]).is_equal(1)
	var shop_grid := BuildGrid.new()
	var shop_ids := ShopTestLayout.build(shop_grid, ["air", "land"])
	assert_int(RoomPrestige.evaluate_room(shop_grid, shop_ids["air_room"])["level"]).is_equal(1)
	assert_int(RoomPrestige.evaluate_room(shop_grid, shop_ids["land_room"])["level"]).is_equal(1)


func test_bonus_tables_and_half_up_spend_rounding() -> void:
	assert_int(RoomPrestige.spend_bonus_percent(1)).is_equal(0)
	assert_int(RoomPrestige.spend_bonus_percent(2)).is_equal(3)
	assert_int(RoomPrestige.spend_bonus_percent(3)).is_equal(7)
	assert_int(RoomPrestige.spend_bonus_percent(4)).is_equal(11)
	assert_int(RoomPrestige.spend_bonus_percent(5)).is_equal(15)
	assert_int(RoomPrestige.break_recovery_bonus_percent(1)).is_equal(0)
	assert_int(RoomPrestige.break_recovery_bonus_percent(2)).is_equal(2)
	assert_int(RoomPrestige.break_recovery_bonus_percent(3)).is_equal(5)
	assert_int(RoomPrestige.break_recovery_bonus_percent(4)).is_equal(8)
	assert_int(RoomPrestige.break_recovery_bonus_percent(5)).is_equal(10)
	# 20 * 1.15 = 23; 10 * 1.15 = 11.5 -> 12 (half-up); 15 * 1.07 = 16.05 -> 16.
	assert_int(RoomPrestige.apply_spend_bonus(20, 5)).is_equal(23)
	assert_int(RoomPrestige.apply_spend_bonus(10, 5)).is_equal(12)
	assert_int(RoomPrestige.apply_spend_bonus(15, 3)).is_equal(16)
	assert_int(RoomPrestige.apply_spend_bonus(0, 5)).is_equal(0)


func test_size_and_diverse_decor_progress_monotonically_from_l1_to_l5() -> void:
	var grid := _floored_grid(Vector2i(22, 22))
	var room_id := grid.apply(BuildEdit.place_room(Rect2i(2, 2, 10, 10), &"cafe")).room_id
	_place(grid, &"cafe_counter", Vector2i(2, 2))
	_place(grid, &"cafe_table", Vector2i(2, 4))

	var l1 := RoomPrestige.evaluate_room(grid, room_id)
	assert_int(l1["level"]).is_equal(1)

	_place(grid, &"fountain_indoor", Vector2i(6, 2))
	var l2 := RoomPrestige.evaluate_room(grid, room_id)
	assert_int(l2["level"]).is_equal(2)
	assert_int(l2["score"]).is_greater(l1["score"])

	_place(grid, &"statue_indoor", Vector2i(9, 2))
	_place(grid, &"tree_indoor", Vector2i(6, 5))
	var l3 := RoomPrestige.evaluate_room(grid, room_id)
	assert_int(l3["level"]).is_equal(3)
	assert_int(l3["score"]).is_greater(l2["score"])

	_place(grid, &"bench_2a_indoor", Vector2i(1, 7) + Vector2i(1, 0))
	_place(grid, &"plant_pot_2a", Vector2i(9, 5))
	_place(grid, &"plant_pot_1a", Vector2i(11, 2))
	var l4 := RoomPrestige.evaluate_room(grid, room_id)
	assert_int(l4["level"]).is_equal(4)
	assert_int(l4["score"]).is_greater(l3["score"])

	_place(grid, &"bench_1a", Vector2i(11, 5))
	_place(grid, &"bush", Vector2i(7, 8))
	_place(grid, &"metal_pole", Vector2i(10, 8))
	_place(grid, &"metal_pole_chain", Vector2i(11, 8))
	var l5 := RoomPrestige.evaluate_room(grid, room_id)
	assert_int(l5["level"]).is_equal(5)
	assert_int(l5["next_threshold"]).is_equal(0)
	assert_int(l5["spend_bonus_percent"]).is_equal(15)
	assert_int(l5["break_bonus_percent"]).is_equal(10)
	assert_int(l5["score"]).is_greater(l4["score"])


func test_multicell_decor_piece_counts_once_not_per_cell() -> void:
	var grid := _floored_grid()
	var room_id := grid.apply(BuildEdit.place_room(Rect2i(2, 2, 8, 8), &"cafe")).room_id
	_place(grid, &"fountain_indoor", Vector2i(3, 3))
	var eval := RoomPrestige.evaluate_room(grid, room_id)
	assert_int(eval["decor_count"]).is_equal(1)
	assert_int(eval["unique_decor"]).is_equal(1)
	assert_int(eval["decor_points"]).is_equal(RoomPrestige.decor_points_of(&"fountain_indoor"))


func test_diminishing_returns_reward_diverse_decor_over_duplicate_spam() -> void:
	var spam_grid := _floored_grid()
	var spam_room := spam_grid.apply(BuildEdit.place_room(Rect2i(2, 2, 8, 8), &"cafe")).room_id
	_place(spam_grid, &"plant_pot_1a", Vector2i(2, 2))
	_place(spam_grid, &"plant_pot_1a", Vector2i(4, 2))
	_place(spam_grid, &"plant_pot_1a", Vector2i(6, 2))
	var spam_eval := RoomPrestige.evaluate_room(spam_grid, spam_room)

	var mix_grid := _floored_grid()
	var mix_room := mix_grid.apply(BuildEdit.place_room(Rect2i(2, 2, 8, 8), &"cafe")).room_id
	_place(mix_grid, &"plant_pot_1a", Vector2i(2, 2))
	_place(mix_grid, &"plant_pot_2a", Vector2i(4, 2))
	_place(mix_grid, &"bush", Vector2i(6, 2))
	var mix_eval := RoomPrestige.evaluate_room(mix_grid, mix_room)

	assert_int(spam_eval["decor_count"]).is_equal(3)
	assert_int(spam_eval["unique_decor"]).is_equal(1)
	assert_int(mix_eval["decor_count"]).is_equal(3)
	assert_int(mix_eval["unique_decor"]).is_equal(3)
	assert_int(spam_eval["decor_points"]).is_less(mix_eval["decor_points"])
	assert_int(spam_eval["score"]).is_less(mix_eval["score"])


func test_future_award_trophies_and_plaques_contribute_high_prestige() -> void:
	assert_bool(RoomPrestige.is_trophy_kind(&"award_trophy_on_time")).is_true()
	assert_bool(RoomPrestige.is_trophy_kind(&"award_plaque_spotless")).is_true()
	assert_bool(RoomPrestige.is_trophy_kind(&"fountain_indoor")).is_false()
	assert_int(RoomPrestige.trophy_points_of(&"award_trophy_on_time")).is_equal(
		RoomPrestige.DEFAULT_TROPHY_POINTS
	)
	var one := RoomPrestige.evaluate_counts({&"award_trophy_on_time": 1}, Vector2i(4, 4), &"cafe")
	var two_distinct := RoomPrestige.evaluate_counts(
		{&"award_trophy_on_time": 1, &"award_plaque_spotless": 1}, Vector2i(4, 4), &"cafe"
	)
	var two_same := RoomPrestige.evaluate_counts(
		{&"award_trophy_on_time": 2}, Vector2i(4, 4), &"cafe"
	)
	assert_int(one["trophy_points"]).is_equal(30)
	assert_int(two_distinct["trophy_points"]).is_equal(60)
	assert_int(two_same["trophy_points"]).is_less(two_distinct["trophy_points"])
	assert_int(one["level"]).is_greater_equal(2)


func test_cafe_sim_spend_scales_up_in_prestigious_room() -> void:
	var grid := BuildGrid.new()
	var ids := CafeTestLayout.build(grid)
	var at := ReferenceTerminal.offset_on(grid)
	# Decorate airside cafe to L3 (size 9 + setup 2 + fountain 18 + statue 14 + plant 8 = 51 -> L3).
	_place(grid, &"fountain_indoor", Vector2i(26, 3) + at)
	_place(grid, &"statue_indoor", Vector2i(27, 5) + at)
	_place(grid, &"plant_pot_1a", Vector2i(22, 7) + at)
	var eval := RoomPrestige.evaluate_room(grid, ids["air_room"])
	assert_int(eval["level"]).is_equal(3)
	assert_int(eval["spend_bonus_percent"]).is_equal(7)

	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var paid: Array[int] = []
	_world.sim.cafes.paid.connect(func(_id: int, _r: int, amount: int) -> void: paid.append(amount))
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.cafe_cooldown = 1000000
	p.hunger = 30
	while p.stage != Passenger.Stage.TO_GATE and _world.clock.tick < 900:
		_world.step()
	assert_bool(_world.sim.cafes.try_visit(p)).is_true()
	while p.stage != Passenger.Stage.CAFE_SEATED and _world.clock.tick < 1400:
		_world.step()
	var mood := p.mood
	while p.stage == Passenger.Stage.CAFE_SEATED and _world.clock.tick < 1800:
		mood = p.mood
		_world.step()
	var base := CafeSim.spend(15, mood, true, CafeVisit.Outcome.COMPLETE)
	var expected := RoomPrestige.apply_spend_bonus(base, eval["level"])
	assert_int(expected).is_greater(base)
	assert_array(paid).is_equal([expected])


func test_shop_sim_spend_scales_up_in_prestigious_room() -> void:
	var grid := BuildGrid.new()
	var ids := ShopTestLayout.build(grid, ["air"])
	var at := ReferenceTerminal.offset_on(grid)
	# Decorate airside kiosk to L3 (size 9 + setup 3 + fountain 18 + statue 14 + plant 8 = 52 -> L3).
	_place(grid, &"fountain_indoor", Vector2i(22, 7) + at)
	_place(grid, &"statue_indoor", Vector2i(27, 3) + at)
	_place(grid, &"plant_pot_1a", Vector2i(27, 5) + at)
	var eval := RoomPrestige.evaluate_room(grid, ids["air_room"])
	assert_int(eval["level"]).is_equal(3)

	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	var paid: Array[int] = []
	_world.sim.shops.paid.connect(func(_id: int, _r: int, amount: int) -> void: paid.append(amount))
	_world.run_to(10)

	var p := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
	p.mood = 60
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
	var visit := _world.sim.shops.visit_of(p.id)
	assert_object(visit).is_not_null()
	assert_int(visit.room).is_equal(ids["air_room"])
	while _world.sim.shops.visit_of(p.id) != null and _world.clock.tick < 3000:
		_world.step()
	var base := ShopSim.spend(RoomTypes.get_type(&"kiosk").base_spend, 60, true)
	var expected := RoomPrestige.apply_spend_bonus(base, eval["level"])
	assert_int(expected).is_greater(base)
	assert_array(paid).is_equal([expected])


func test_room_panel_displays_prestige_and_updates_when_decor_is_added() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	var mode := BuildMode.new()
	mode.grid_size = Vector2i(20, 20)
	_port.add_child(mode)
	mode.set_process(false)
	var menu := BuildMenu.new()
	menu.build_mode = mode
	_port.add_child(menu)
	var edits: Array[BuildEdit] = []
	for y in range(2, 16):
		for x in range(2, 16):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	mode.grid.apply_batch(edits)

	var room_id := mode.grid.apply(BuildEdit.place_room(Rect2i(3, 3, 6, 6), &"cafe")).room_id
	mode.set_tool(BuildMode.Tool.NONE)
	mode.update_room_focus(mode.grid.cell_to_world(Vector2i(4, 4)))
	await get_tree().process_frame

	var panel := menu.room_panel()
	var before_texts := _panel_texts(panel)
	assert_array(before_texts).contains(
		["Prestige: Lv. 1 / 5 (9 pts · +0% spend)", "Add decor or trophies to raise prestige"]
	)

	_place(mode.grid, &"fountain_indoor", Vector2i(6, 4))
	await get_tree().process_frame
	await get_tree().process_frame
	var after_texts := _panel_texts(panel)
	assert_array(after_texts).contains(["Prestige: Lv. 2 / 5 (27 pts · +3% spend)"])
	assert_array(after_texts).contains(["Size 9 · Setup 0 · Decor 18 · Awards 0"])

	# Non-commercial rooms show prestige without "+X% spend".
	var toilet_id := mode.grid.apply(BuildEdit.place_room(Rect2i(10, 3, 3, 3), &"toilet")).room_id
	mode.update_room_focus(mode.grid.cell_to_world(Vector2i(11, 4)))
	await get_tree().process_frame
	assert_int(panel.room_id()).is_equal(toilet_id)
	var toilet_texts := _panel_texts(panel)
	assert_array(toilet_texts).contains(["Prestige: Lv. 1 / 5 (1 pts)"])
	assert_int(room_id).is_greater(0)
