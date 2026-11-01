class_name TestRescueGrantSite
extends GdUnitTestSuite
## The rescue grant on the airport site plans with the site (RepairPlan.make()
## with PassengerSim.site): a new entrance must have a walk in from the road.
## The reference terminal stands on a site grid without its entrance, and a
## walled pocket of open ground hugs its landside hall, so every door spot
## on the hall's outer walls opens into the pocket and has no walk to the
## road. A plan made without the site takes such a spot (the control); the
## grant's plan does not.

const SITE := preload("res://build/terminal_site.tres")
## The pocket's cells: a ring one cell wide round the landside hall.
const POCKET := Rect2i(9, 9, 14, 10)

var _world: PassengerTestWorld
var _grant: RescueGrant


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	assert_bool(ReferenceTerminal.build(grid)).is_true()
	var entrance: int = ReferenceTerminal.object_ids(grid)["entrances"][0]
	var edits: Array[BuildEdit] = [
		BuildEdit.remove_object(entrance),
		BuildEdit.place_wall(ReferenceTerminal.ENTRANCE_CELL, BuildGrid.Side.SOUTH),
	]
	for y in range(POCKET.position.y, POCKET.end.y):
		edits.append(BuildEdit.place_wall(Vector2i(POCKET.position.x, y), BuildGrid.Side.WEST))
		edits.append(BuildEdit.place_wall(Vector2i(POCKET.end.x - 1, y), BuildGrid.Side.EAST))
	for x in range(POCKET.position.x, POCKET.end.x):
		edits.append(BuildEdit.place_wall(Vector2i(x, POCKET.end.y - 1), BuildGrid.Side.SOUTH))
	edits.append(BuildEdit.place_wall(POCKET.position, BuildGrid.Side.NORTH))
	edits.append(BuildEdit.place_wall(Vector2i(POCKET.end.x - 1, POCKET.position.y), 0))
	# With the only entrance gone staff cannot reach their spots: the grid
	# takes these edits past the staff reach rule, as an old save could hold.
	grid.check_staff_reach = false
	for result in grid.apply_batch(edits):
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	grid.check_staff_reach = true
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(100000))
	_world.sim.site = SITE
	_grant = auto_free(RescueGrant.new())
	_grant.bind(_world.clock, _world.sim, _world.sim.wallet)


func after_test() -> void:
	_world.free_all()
	_world = null


## The layout `plan`'s edits leave on a copy of the world's grid, with the
## site.
func _built(plan: RepairPlan) -> Array:
	var grid := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	assert_bool(grid.from_snapshot(_world.grid.to_snapshot())).is_true()
	for edit in plan.edits:
		var result := grid.apply(edit)
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	var layout := TerminalLayout.new()
	layout.site = SITE
	layout.rebuild(grid)
	return [grid, layout]


func test_the_grant_plans_an_entrance_with_a_walk_in_from_the_road() -> void:
	assert_bool(_grant.has_working_path()).is_false()
	var plan := _grant.repair_plan()
	assert_bool(plan.ok).is_true()
	var built := _built(plan)
	var layout: TerminalLayout = built[1]
	print(
		(
			"site plan: %d edits, entrances %s, for passengers %s, out of service %s"
			% [
				plan.edits.size(),
				layout.entrances,
				layout.passenger_entrances,
				layout.out_of_service
			]
		)
	)
	assert_array(layout.out_of_service).is_empty()
	assert_array(layout.passenger_entrances).has_size(1)
	assert_bool(RepairPlan.has_working_path(built[0], layout)).is_true()


## The control: without the site the plan's entrance opens into the pocket.
func test_a_plan_without_the_site_takes_a_door_with_no_walk_out() -> void:
	var plan := RepairPlan.make(_world.grid)
	assert_bool(plan.ok).is_true()
	var layout: TerminalLayout = _built(plan)[1]
	print(
		(
			"site-less plan: entrances %s, out of service %s"
			% [layout.entrances, layout.out_of_service]
		)
	)
	assert_array(layout.entrances).has_size(1)
	assert_array(layout.out_of_service).contains_exactly(layout.entrances)
