class_name TestDepartureBoard
extends GdUnitTestSuite
## Departure Board (&"info_screen", decision
## info-screen-renamed-departure-board-with-passive-wayfinding-and-calm):
## renamed from "Info screen" to "Departure Board" with $300 price and $6/day
## upkeep, distinct from boredom-halving Screen (&"screen_stand", 692a4f19)
## and staffed Info desk (&"info_desk"). Covers a 5-row sight fan ahead
## (previewed in BuildGhost), providing mild passive calm and faster passive
## wayfinding/replan without staff.

const SIZE := Vector2i(24, 14)
const BOARDING := 5000
const DOORS := 6000
const START_MOOD := 50
const BEAT := PassengerSim.BEAT_TICKS
const BEATS := 20


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func _make_world() -> PassengerTestWorld:
	var grid := PassengerTestWorld.floored(SIZE)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(2, 0), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(2, SIZE.y - 1), 2)
	PassengerTestWorld.place(grid, &"seat_row", Vector2i(3, 12), 0)
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(BOARDING, DOORS), 7)
	world.sim.apron_waypoints = PackedVector3Array()
	world.run_to(10)
	return world


func _guest(
	world: PassengerTestWorld, stage: Passenger.Stage, cell: Vector2i, mood := START_MOOD
) -> Passenger:
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = stage
	p.stage_tick = world.clock.tick
	p.at = cell
	p.clear_path()
	p.mood = mood
	p.boredom = 20
	p.shop_cooldown = 0
	return p


func _run_beats(world: PassengerTestWorld, p: Passenger, beats: int) -> void:
	for i in beats:
		var t := world.clock.tick + 1
		while posmod(t, BEAT) != posmod(p.id, BEAT):
			t += 1
		world.run_to(t)


func test_catalog_menu_and_item_info_name_departure_board_and_distinguish_roles() -> void:
	var def := BuildCatalog.get_def(&"info_screen")
	assert_object(def).is_not_null()
	assert_str(def.display_name).is_equal("Departure Board")
	assert_int(PriceTable.price_of_object(&"info_screen")).is_equal(300)
	assert_int(PriceTable.INFO_SCREEN_UPKEEP).is_equal(6)
	assert_str(str(FurnitureTools.OBJECTS[BuildMode.Tool.INFO_SCREEN])).is_equal("info_screen")
	assert_str(FurnitureTools.ITEMS[BuildMode.Tool.INFO_SCREEN][0]).is_equal("Departure Board")
	assert_array(FurnitureTools.Words.new().msgids()).contains(["Departure Board"])
	assert_array(DisplayWords.Words.new().msgids()).contains(["Departure Board"])
	assert_array(BuildWords.msgids()).contains(["departure board"])
	assert_str(BuildCatalog.get_def(&"screen_stand").display_name).is_equal("Screen")
	assert_str(BuildCatalog.get_def(&"info_desk").display_name).is_equal("Info desk")

	var board_info := ItemInfo.of(BuildMode.Tool.INFO_SCREEN)
	assert_int(board_info.size()).is_equal(3)
	var board_joined := " ".join(PackedStringArray(board_info)).to_lower()
	assert_str(board_joined).contains("departure board")
	assert_str(board_joined).contains("calm")
	assert_str(board_joined).contains("info desk")
	assert_str(board_joined).not_contains("scenery")
	assert_str(board_joined).not_contains("nothing in the game reacts")

	var screen_info := ItemInfo.of(BuildMode.Tool.SCREEN)
	assert_int(screen_info.size()).is_equal(3)
	var screen_joined := " ".join(PackedStringArray(screen_info)).to_lower()
	assert_str(screen_joined).contains("boredom")
	assert_str(screen_joined).contains("half as fast")
	assert_str(screen_joined).contains("kiosk")


func test_sight_fan_coverage_is_blocked_by_walls_and_previewed_in_ghost() -> void:
	var mode: BuildMode = auto_free(BuildMode.new())
	mode.grid_size = Vector2i(14, 14)
	add_child(mode)
	mode.set_tool(BuildMode.Tool.FLOOR)
	for y in 14:
		for x in 14:
			mode.apply_at(mode.grid.cell_to_world(Vector2i(x, y)))

	var cell := Vector2i(6, 3)
	mode.set_tool(BuildMode.Tool.INFO_SCREEN)
	var point := mode.grid.cell_to_world(cell)
	var expected := ScreenCoverage.covered_cells(mode.grid, cell, mode.facing)
	assert_int(expected.size()).is_greater(10)
	assert_array(mode.coverage_preview(mode.edit_at(point))).is_equal(expected)
	mode._update_ghost(point)
	var ghost_tiles := 0
	for child in mode.get_node("Ghost").get_children():
		if not child.is_queued_for_deletion() and str(child.name).contains("Coverage"):
			ghost_tiles += 1
	assert_int(ghost_tiles).is_equal(expected.size())

	# Plain wall blocks the sight fan; glass lets it through; turning moves it.
	(
		assert_bool(
			mode.grid.apply(BuildEdit.place_wall(cell + Vector2i(0, 1), BuildGrid.Side.SOUTH)).ok
		)
		. is_true()
	)
	var walled := mode.coverage_preview(mode.edit_at(point))
	assert_int(walled.size()).is_less(expected.size())
	assert_bool(walled.has(cell + Vector2i(0, 3))).is_false()
	(
		assert_bool(
			(
				mode
				. grid
				. apply(
					BuildEdit.place_wall(
						cell + Vector2i(0, 1), BuildGrid.Side.SOUTH, BuildGrid.WallKind.GLASS
					)
				)
				. ok
			)
		)
		. is_true()
	)
	assert_bool(mode.coverage_preview(mode.edit_at(point)).has(cell + Vector2i(0, 3))).is_true()
	mode.rotate_facing()
	var turned := mode.coverage_preview(mode.edit_at(point))
	assert_bool(turned.has(cell + Vector2i(-1, 0))).is_true()
	assert_bool(turned.has(cell + Vector2i(0, 1))).is_false()

	# Placing a Departure Board updates departure_boards coverage, not screen_stand upkeep.
	mode.facing = 0
	var placed := mode.apply_at(point)
	assert_bool(placed.ok).is_true()
	assert_array(ScreenCoverage.screen_ids(mode.grid)).is_empty()
	assert_int(ScreenCoverage.daily_upkeep(mode.grid)).is_equal(0)
	assert_array(ScreenCoverage.ids_for(mode.grid, ScreenCoverage.INFO_SCREEN_ID)).is_equal(
		[placed.object_id]
	)


func test_departure_board_coverage_frees_with_its_grid() -> void:
	var grid := BuildGrid.new(Vector2i(8, 8))
	var before := grid.graph_changed.get_connections().size()
	var coverage := ScreenCoverage.new(ScreenCoverage.INFO_SCREEN_ID)
	coverage.bind(grid)
	var bound := grid.graph_changed.get_connections().size()
	var cov_ref: WeakRef = weakref(coverage)
	coverage = null
	var grid_ref: WeakRef = weakref(grid)
	assert_int(bound).is_equal(before + 1)
	assert_bool(cov_ref.get_ref() == null).is_true()
	assert_int(grid.graph_changed.get_connections().size()).is_equal(before)
	grid = null
	assert_bool(grid_ref.get_ref() == null).is_true()


func test_passive_calm_helps_mood_inside_fan_not_boredom_and_weaker_than_desk() -> void:
	# 1. Waiting non-stuck guest inside sight fan gains mild calm, boredom unchanged.
	var with_board := _make_world()
	var board_cell := Vector2i(12, 4)
	var guest_cell := Vector2i(12, 6)
	PassengerTestWorld.place(with_board.grid, &"info_screen", board_cell, 0)
	var covered := _guest(with_board, Passenger.Stage.STANDING, guest_cell, START_MOOD)
	_run_beats(with_board, covered, BEATS)

	var control := _make_world()
	var uncovered := _guest(control, Passenger.Stage.STANDING, guest_cell, START_MOOD)
	_run_beats(control, uncovered, BEATS)

	print(
		(
			"passive calm over %d beats: covered mood %d (boredom %d), control mood %d (boredom %d)"
			% [BEATS, covered.mood, covered.boredom, uncovered.mood, uncovered.boredom]
		)
	)
	assert_int(covered.mood).is_greater(uncovered.mood)
	assert_int(covered.mood).is_equal(
		START_MOOD + DecorEffect.BOARD_CALM * BEATS / DecorEffect.PERIOD_BEATS
	)
	assert_int(covered.boredom).is_equal(uncovered.boredom)
	assert_bool(_has_nice_decor_thought(covered)).is_false()
	with_board.free_all()
	control.free_all()

	# 2. Late passenger inside sight fan loses mood slightly slower than uncovered.
	var late_board := _make_world()
	PassengerTestWorld.place(late_board.grid, &"info_screen", board_cell, 0)
	var late_cov := _guest(late_board, Passenger.Stage.STANDING, guest_cell, 70)
	late_cov.late = true
	_run_beats(late_board, late_cov, DecorEffect.PERIOD_BEATS)

	var late_ctrl := _make_world()
	var late_uncov := _guest(late_ctrl, Passenger.Stage.STANDING, guest_cell, 70)
	late_uncov.late = true
	_run_beats(late_ctrl, late_uncov, DecorEffect.PERIOD_BEATS)

	assert_int(late_cov.mood).is_greater(late_uncov.mood)
	late_board.free_all()
	late_ctrl.free_all()

	# 3. Stuck passenger: Departure Board loses less mood than uncovered,
	#    but noticeably more (weaker) than a staffed Info Desk.
	var stuck_board := InfoDeskTestLayout.world(false)
	PassengerTestWorld.place(stuck_board.grid, &"info_screen", Vector2i(9, 8), 0)
	var sb := InfoDeskTestLayout.guest(stuck_board, Vector2i(9, 10), 88)
	_run_beats(stuck_board, sb, 6)

	var stuck_none := InfoDeskTestLayout.world(false)
	var sn := InfoDeskTestLayout.guest(stuck_none, Vector2i(9, 10), 88)
	_run_beats(stuck_none, sn, 6)

	var stuck_desk := InfoDeskTestLayout.world(true)
	var sd := InfoDeskTestLayout.guest(stuck_desk, Vector2i(9, 10), 88)
	_run_beats(stuck_desk, sd, 6)

	print(
		(
			"stuck mood after 6 beats (start 88): none=%d, board=%d, staffed desk=%d"
			% [sn.mood, sb.mood, sd.mood]
		)
	)
	assert_int(sb.mood).is_greater(sn.mood)
	assert_int(sb.mood).is_less(sd.mood)
	stuck_board.free_all()
	stuck_none.free_all()
	stuck_desk.free_all()


func test_plain_wall_blocks_departure_board_calm() -> void:
	var world := _make_world()
	var board_cell := Vector2i(12, 4)
	var guest_cell := Vector2i(12, 6)
	PassengerTestWorld.place(world.grid, &"info_screen", board_cell, 0)
	(
		assert_bool(world.grid.apply(BuildEdit.place_wall(board_cell, BuildGrid.Side.SOUTH)).ok)
		. is_true()
	)
	var p := _guest(world, Passenger.Stage.STANDING, guest_cell, START_MOOD)
	_run_beats(world, p, BEATS)
	assert_int(p.mood).is_equal(START_MOOD)
	world.free_all()


func test_passive_wayfinding_helps_stuck_passengers_replan_quicker_without_staff() -> void:
	# Both worlds have no Info Desk and no Shop staff; wall cuts exit off.
	var board_world := InfoDeskTestLayout.world(false)
	PassengerTestWorld.place(board_world.grid, &"info_screen", Vector2i(9, 8), 0)
	var p_board := InfoDeskTestLayout.guest(board_world, Vector2i(9, 10), START_MOOD)

	var ctrl_world := InfoDeskTestLayout.world(false)
	var p_ctrl := InfoDeskTestLayout.guest(ctrl_world, Vector2i(9, 10), START_MOOD)

	# Run just past the first beat so both are stuck NO_ROUTE and normal retry is ~19 ticks away.
	_run_beats(board_world, p_board, 1)
	_run_beats(ctrl_world, p_ctrl, 1)
	board_world.step()
	ctrl_world.step()
	assert_int(p_board.stuck).is_equal(Passenger.Stuck.NO_ROUTE)
	assert_int(p_ctrl.stuck).is_equal(Passenger.Stuck.NO_ROUTE)
	assert_bool(board_world.sim.info_desks.holds(p_board)).is_false()

	# Open the wall and step only WAYFINDING_RETRY_TICKS (5 ticks << BEAT_TICKS 20).
	InfoDeskTestLayout.open_wall(board_world.grid)
	InfoDeskTestLayout.open_wall(ctrl_world.grid)
	for i in PassengerSim.WAYFINDING_RETRY_TICKS:
		board_world.step()
		ctrl_world.step()

	print(
		(
			"after %d ticks post-open: board stuck=%d moving=%s, ctrl stuck=%d moving=%s"
			% [
				PassengerSim.WAYFINDING_RETRY_TICKS,
				p_board.stuck,
				p_board.is_moving(),
				p_ctrl.stuck,
				p_ctrl.is_moving(),
			]
		)
	)
	assert_int(p_board.stuck).is_equal(Passenger.Stuck.NONE)
	assert_bool(p_board.is_moving()).is_true()
	assert_int(p_ctrl.stuck).is_equal(Passenger.Stuck.NO_ROUTE)
	assert_bool(p_ctrl.is_moving()).is_false()

	board_world.free_all()
	ctrl_world.free_all()


func test_plain_wall_blocks_passive_wayfinding_boost() -> void:
	var world := InfoDeskTestLayout.world(false)
	var board_cell := Vector2i(9, 8)
	PassengerTestWorld.place(world.grid, &"info_screen", board_cell, 0)
	(
		assert_bool(world.grid.apply(BuildEdit.place_wall(board_cell, BuildGrid.Side.SOUTH)).ok)
		. is_true()
	)
	var p := InfoDeskTestLayout.guest(world, Vector2i(9, 10), START_MOOD)
	_run_beats(world, p, 1)
	world.step()
	assert_int(p.stuck).is_equal(Passenger.Stuck.NO_ROUTE)
	InfoDeskTestLayout.open_wall(world.grid)
	for i in PassengerSim.WAYFINDING_RETRY_TICKS:
		world.step()
	assert_int(p.stuck).is_equal(Passenger.Stuck.NO_ROUTE)
	assert_bool(p.is_moving()).is_false()
	world.free_all()


func _has_nice_decor_thought(p: Passenger) -> bool:
	for entry in PassengerThoughts.entries(p):
		if entry["kind"] == PassengerThoughts.Kind.NICE_DECOR:
			return true
	return false
