class_name TestRepairPlanLaneCells
extends GdUnitTestSuite
## A repair plan never builds on the cells a whole security lane names (its
## berth, return route, exit, pickup and officer spots), so the plan that
## gives a terminal its missing check-in desk leaves the lane whole.
##
## The terminal is a small room, floored x 3..8 and y 0..9, with the lane
## rooted at (5, 6), an exit at (5, 0), and an entrance on the south edge at
## each x in turn. It has no check-in desk, so the plan must buy one, and
## the free floor beside the lane is the cheapest place to put it.

const ARCH_AT := Vector2i(5, 6)
const ROOM := Rect2i(3, 0, 6, 10)


static func _grid(entrance_x: int) -> BuildGrid:
	var grid := BuildGrid.new(Vector2i(12, 16))
	for y in ROOM.size.y:
		for x in range(ROOM.position.x, ROOM.end.x):
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(entrance_x, 9), 2)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(5, 0), 0)
	SecurityLaneBuilder.build(grid, ARCH_AT, 0, SecurityLanes.RIGHT)
	return grid


func test_the_plan_for_a_missing_desk_builds_on_no_lane_cell() -> void:
	var checked := 0
	for entrance_x in range(ROOM.position.x, ROOM.end.x):
		var grid := _grid(entrance_x)
		var lanes := SecurityLaneBuilder.recognise(grid)
		if lanes.complete_arches().is_empty():
			continue
		var lane := lanes.lane(lanes.complete_arches()[0])
		var named := SecurityLanes.lane_cells(lane)
		var plan := RepairPlan.make(grid)
		var desks := plan.edits.filter(
			func(e: BuildEdit) -> bool:
				return e.kind == BuildEdit.Kind.PLACE_OBJECT and e.def_id == &"checkin_desk"
		)
		print("entrance x %d: ok %s, desk edits %d" % [entrance_x, plan.ok, desks.size()])
		assert_bool(plan.ok).is_true()
		assert_int(desks.size()).is_equal(1)
		for edit: BuildEdit in plan.edits:
			if edit.kind == BuildEdit.Kind.PLACE_OBJECT:
				var def := BuildCatalog.get_def(edit.def_id)
				for cell in def.footprint(edit.cell, edit.facing):
					assert_bool(named.has(cell)).is_false()
		for edit: BuildEdit in plan.edits:
			assert_bool(grid.apply(edit).ok).is_true()
		var after := SecurityLaneBuilder.recognise(grid)
		assert_array(after.complete_arches()).is_equal(lanes.complete_arches())
		checked += 1
	# The room must hold a whole lane for at least one entrance, or nothing
	# was checked.
	assert_int(checked).is_greater(0)


func test_the_plan_for_a_missing_exit_uses_the_lane_and_keeps_it_whole() -> void:
	var grid := SecurityTestWorld.build_grid(true)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(1, 13), 0)
	for id in grid.object_ids():
		if StringName(grid.get_object(id)["def"]) == &"exit_door":
			assert_bool(grid.apply(BuildEdit.remove_object(id)).ok).is_true()
	var lanes := SecurityLaneBuilder.recognise(grid)
	assert_int(lanes.complete_arches().size()).is_equal(1)
	var layout := TerminalLayout.new()
	layout.rebuild(grid)
	assert_bool(RepairPlan.has_working_path(grid, layout)).is_false()
	var plan := RepairPlan.make(grid)
	var kinds := {}
	for edit: BuildEdit in plan.edits:
		if edit.kind == BuildEdit.Kind.PLACE_OBJECT:
			kinds[edit.def_id] = int(kinds.get(edit.def_id, 0)) + 1
	print("plan ok %s, objects bought %s" % [plan.ok, kinds])
	assert_bool(plan.ok).is_true()
	# The lane is the security leg: only an exit is bought.
	assert_dict(kinds).is_equal({&"exit_door": 1})
	for edit: BuildEdit in plan.edits:
		assert_bool(grid.apply(edit).ok).is_true()
	layout.rebuild(grid)
	assert_array(layout.security_lanes.complete_arches()).is_equal(lanes.complete_arches())
	assert_bool(RepairPlan.has_working_path(grid, layout)).is_true()
