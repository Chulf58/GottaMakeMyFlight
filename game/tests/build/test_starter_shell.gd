class_name TestStarterShell
extends GdUnitTestSuite
## The new-game starter shell (decision terminal-growth-and-starter-building-
## move-the-airside-north, points 2 to 4): floor, outer walls, one entrance and
## one exit on ReferenceTerminal's 12x16 footprint and nothing inside; every
## piece saved at its price so a demolition refunds half; the debug fill adds
## the reference interior. Built on the airport site's grid, no scene.

const SITE := "res://build/terminal_site.tres"
const FLOOR_CELLS := 12 * 16

var _site: SiteDefinition


func before() -> void:
	_site = load(SITE)


func _shell_grid() -> BuildGrid:
	var grid := BuildGrid.new(_site.grid_size, _site.grid_origin)
	assert_bool(StarterShell.place(grid)).is_true()
	return grid


func _count_floor(grid: BuildGrid) -> int:
	var count := 0
	for y in grid.size.y:
		for x in grid.size.x:
			if grid.floor_at(Vector2i(x, y)) != BuildGrid.FLOOR_NONE:
				count += 1
	return count


## The wall edges in the divider row (the interior wall across y = 9).
func _count_divider(grid: BuildGrid) -> int:
	var count := 0
	for x in range(ReferenceTerminal.FLOOR_MIN.x, ReferenceTerminal.FLOOR_MAX.x + 1):
		if grid.has_wall(Vector2i(x, ReferenceTerminal.DIVIDER_Y), BuildGrid.Side.NORTH):
			count += 1
	return count


func _kinds(grid: BuildGrid) -> Dictionary:
	return ReferenceTerminal.object_ids(grid)


## What a grid holds, as "piece@cell" lines without ids or prices.
func _layout_of(grid: BuildGrid) -> PackedStringArray:
	var lines := PackedStringArray()
	for id in grid.object_ids():
		var record := grid.get_object(id)
		lines.append("%s@%s/%d" % [record["def"], record["anchor"], record["facing"]])
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			if grid.floor_at(cell) != BuildGrid.FLOOR_NONE:
				lines.append("floor@%s" % cell)
			for side in BuildGrid.SIDE_STEP.size():
				if grid.has_wall(cell, side):
					lines.append("wall@%s/%d" % [cell, side])
	lines.sort()
	return lines


func test_the_shell_floors_the_reference_footprint_and_walls_it_in() -> void:
	var grid := _shell_grid()
	assert_int(_count_floor(grid)).is_equal(FLOOR_CELLS)
	var low := ReferenceTerminal.FLOOR_MIN
	var high := ReferenceTerminal.FLOOR_MAX
	assert_int(grid.floor_at(low)).is_not_equal(BuildGrid.FLOOR_NONE)
	assert_int(grid.floor_at(high)).is_not_equal(BuildGrid.FLOOR_NONE)
	assert_bool(grid.has_wall(low, BuildGrid.Side.WEST)).is_true()
	assert_bool(grid.has_wall(low, BuildGrid.Side.NORTH)).is_true()
	assert_bool(grid.has_wall(high, BuildGrid.Side.EAST)).is_true()
	assert_bool(grid.has_wall(high, BuildGrid.Side.SOUTH)).is_true()


func test_the_shell_has_one_entrance_one_exit_and_no_desks() -> void:
	var kinds := _kinds(_shell_grid())
	assert_int((kinds["entrances"] as Array).size()).is_equal(1)
	assert_int((kinds["exits"] as Array).size()).is_equal(1)
	for kind in ["desks", "scanners", "seats", "belts"]:
		assert_int((kinds[kind] as Array).size()).is_equal(0)


func test_the_exit_is_on_the_north_edge_and_the_entrance_on_the_south() -> void:
	var grid := _shell_grid()
	var kinds := _kinds(grid)
	var exit_record := grid.get_object((kinds["exits"] as Array)[0])
	var entrance_record := grid.get_object((kinds["entrances"] as Array)[0])
	assert_int(exit_record["anchor"].y).is_equal(ReferenceTerminal.FLOOR_MIN.y)
	assert_int(entrance_record["anchor"].y).is_equal(ReferenceTerminal.FLOOR_MAX.y)


func test_the_shell_has_no_divider() -> void:
	assert_int(_count_divider(_shell_grid())).is_equal(0)


func test_every_shell_piece_is_saved_at_its_price() -> void:
	var grid := _shell_grid()
	var saved := 0
	for edit in ReferenceTerminal.shell_edits():
		match edit.kind:
			BuildEdit.Kind.PAINT_FLOOR:
				saved += grid.floor_paid(edit.cell)
			BuildEdit.Kind.PLACE_WALL:
				saved += grid.wall_paid(edit.cell, edit.side)
			BuildEdit.Kind.PLACE_OBJECT:
				saved += int(grid.get_object(grid.object_at(edit.cell))["paid"])
	assert_int(StarterShell.price()).is_greater(0)
	assert_int(saved).is_equal(StarterShell.price())


func test_the_shell_costs_floor_walls_and_two_doors() -> void:
	var walls := 2 * 12 - 2 + 2 * 16
	var expected := (
		FLOOR_CELLS * PriceTable.price_of_floor()
		+ walls * PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)
		+ PriceTable.price_of_object(&"entrance_door")
		+ PriceTable.price_of_object(&"exit_door")
	)
	assert_int(StarterShell.price()).is_equal(expected)


func test_demolishing_a_starter_wall_refunds_half_its_price() -> void:
	var grid := _shell_grid()
	var wallet := Wallet.new()
	var cell := Vector2i(ReferenceTerminal.FLOOR_MIN.x + 1, ReferenceTerminal.FLOOR_MIN.y)
	var price := PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)
	assert_int(grid.wall_paid(cell, BuildGrid.Side.NORTH)).is_equal(price)
	var plan: Array[BuildEdit] = [BuildEdit.remove_wall(cell, BuildGrid.Side.NORTH)]
	var result := BuildTransaction.commit_plan(grid, plan, wallet)
	assert_bool(result.ok).is_true()
	assert_int(wallet.balance).is_equal(PriceTable.refund_of(price))
	assert_int(wallet.balance).is_equal(price / 2)


func test_demolishing_the_starter_entrance_refunds_half_its_price() -> void:
	var grid := _shell_grid()
	var wallet := Wallet.new()
	var id: int = (_kinds(grid)["entrances"] as Array)[0]
	var price := PriceTable.price_of_object(&"entrance_door")
	assert_int(int(grid.get_object(id)["paid"])).is_equal(price)
	var plan: Array[BuildEdit] = [BuildEdit.remove_object(id)]
	var result := BuildTransaction.commit_plan(grid, plan, wallet)
	assert_bool(result.ok).is_true()
	assert_int(wallet.balance).is_equal(price / 2)


func test_demolishing_a_starter_floor_tile_refunds_half_its_price() -> void:
	var grid := _shell_grid()
	var wallet := Wallet.new()
	var cell := Vector2i(12, 5)
	var plan: Array[BuildEdit] = [BuildEdit.remove_floor(cell)]
	var result := BuildTransaction.commit_plan(grid, plan, wallet)
	assert_bool(result.ok).is_true()
	assert_int(wallet.balance).is_equal(PriceTable.refund_of(PriceTable.price_of_floor()))
	assert_int(wallet.balance).is_greater(0)


func test_the_debug_fill_adds_the_interior_to_the_shell() -> void:
	var grid := _shell_grid()
	assert_int(_count_divider(grid)).is_equal(0)
	var result := ReferenceTerminal.fill_interior(grid)
	assert_bool(result.ok).is_true()
	var kinds := _kinds(grid)
	assert_int((kinds["desks"] as Array).size()).is_equal(2)
	assert_int((kinds["scanners"] as Array).size()).is_equal(2)
	assert_int((kinds["seats"] as Array).size()).is_equal(4)
	assert_int((kinds["entrances"] as Array).size()).is_equal(1)
	assert_int((kinds["exits"] as Array).size()).is_equal(1)
	assert_int(_count_divider(grid)).is_equal(12 - ReferenceTerminal.SCANNER_XS.size())


func test_the_shell_and_the_fill_make_the_reference_terminal() -> void:
	var filled := _shell_grid()
	assert_bool(ReferenceTerminal.fill_interior(filled).ok).is_true()
	var built := BuildGrid.new(_site.grid_size, _site.grid_origin)
	assert_bool(ReferenceTerminal.build(built)).is_true()
	assert_array(Array(_layout_of(filled))).is_equal(Array(_layout_of(built)))


func test_a_second_fill_is_refused_and_changes_nothing() -> void:
	var grid := _shell_grid()
	assert_bool(ReferenceTerminal.fill_interior(grid).ok).is_true()
	var before := JSON.stringify(grid.to_snapshot())
	var again := ReferenceTerminal.fill_interior(grid)
	assert_bool(again.ok).is_false()
	assert_str(JSON.stringify(grid.to_snapshot())).is_equal(before)


func test_a_fill_blocked_part_way_leaves_the_grid_as_it_was() -> void:
	var grid := _shell_grid()
	var in_the_way := grid.apply(BuildEdit.place_object(&"seat_row", Vector2i(14, 6), 0))
	assert_bool(in_the_way.ok).is_true()
	var before := JSON.stringify(grid.to_snapshot())
	var result := ReferenceTerminal.fill_interior(grid)
	assert_bool(result.ok).is_false()
	assert_str(JSON.stringify(grid.to_snapshot())).is_equal(before)


func test_a_bare_build_mode_starts_empty_and_a_flagged_one_starts_with_the_shell() -> void:
	var bare := BuildMode.new()
	bare.site = _site
	add_child(bare)
	auto_free(bare)
	assert_int(_count_floor(bare.grid)).is_equal(0)
	var flagged := BuildMode.new()
	flagged.site = _site
	flagged.starter_shell = true
	add_child(flagged)
	auto_free(flagged)
	assert_int(_count_floor(flagged.grid)).is_equal(FLOOR_CELLS)
	assert_int((_kinds(flagged.grid)["exits"] as Array).size()).is_equal(1)


func test_a_grid_too_small_for_the_footprint_gets_no_shell_and_place_returns_false() -> void:
	var grid := BuildGrid.new(Vector2i(16, 16), null)
	var before := JSON.stringify(grid.to_snapshot())
	var placed := [true]
	(
		assert_error(func() -> void: placed[0] = StarterShell.place(grid))
		. is_push_error("StarterShell: a piece was refused: Outside the building area")
	)
	assert_bool(placed[0]).is_false()
	assert_int(_count_floor(grid)).is_equal(0)
	assert_str(JSON.stringify(grid.to_snapshot())).is_equal(before)


func test_place_on_a_normal_grid_still_places_the_whole_shell() -> void:
	var grid := BuildGrid.new(_site.grid_size, _site.grid_origin)
	assert_bool(StarterShell.place(grid)).is_true()
	assert_int(_count_floor(grid)).is_equal(FLOOR_CELLS)
