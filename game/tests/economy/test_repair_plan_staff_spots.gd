class_name TestRepairPlanStaffSpots
extends GdUnitTestSuite
## The repair plan respects staff spots (decision staff-spot-design-a-derived-
## staff-spot-behind-each-desk-and). A legacy layout can hold a station whose
## spot is blocked, which StaffSim never staffs, so such a desk is not a way
## through for the rescue grant; and an existing station's spot is reserved
## like an interaction cell, so a candidate that BuildGrid would refuse for it
## does not use up the capped search.

const DESK := &"checkin_desk"
const SCANNER := &"security_scanner"
const SEATS := &"seat_row"

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	RepairPlan.max_candidates = RepairPlan.MAX_CANDIDATES
	RepairPlan.max_tries = RepairPlan.MAX_TRIES
	RepairPlan.max_attempts = RepairPlan.MAX_ATTEMPTS
	if _world != null:
		_world.free_all()
		_world = null


## `grid` reloaded with `extra` ([def, anchor, facing]) put straight into its
## snapshot, past today's placement rules, as a save from before spots would.
func _with_legacy(grid: BuildGrid, extra: Array) -> BuildGrid:
	var data := grid.to_snapshot()
	var next_id: int = data["next_object_id"]
	for entry in extra:
		var anchor: Vector2i = entry[1]
		(
			data["objects"]
			. append(
				{
					"id": next_id,
					"def": str(entry[0]),
					"anchor": [anchor.x, anchor.y],
					"facing": entry[2],
					"paid": 0,
				}
			)
		)
		next_id += 1
	data["next_object_id"] = next_id
	var out := BuildGrid.new()
	assert_bool(out.from_snapshot(JSON.parse_string(JSON.stringify(data)))).is_true()
	return out


func _desk_edit(plan: RepairPlan) -> BuildEdit:
	for edit in plan.edits:
		if edit.kind == BuildEdit.Kind.PLACE_OBJECT and edit.def_id == DESK:
			return edit
	return null


func _blocked_desks_world() -> PassengerTestWorld:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	var covers: Array = []
	for id in ReferenceTerminal.object_ids(grid)["desks"]:
		covers.append([SEATS, StaffSpots.spot_of(grid, id), 0])
	return PassengerTestWorld.make(_with_legacy(grid, covers), FlightSim.schedule_starts(0))


func test_a_desk_with_a_blocked_spot_is_not_a_working_station() -> void:
	_world = _blocked_desks_world()
	var desks: Array[int] = _world.sim.layout.desks
	print("desks %s" % [desks])
	assert_int(desks.size()).is_equal(2)
	for desk in desks:
		assert_bool(StaffSpots.blocked(_world.grid, desk)).is_true()
	assert_bool(RepairPlan.has_working_path(_world.grid, _world.sim.layout)).is_false()


func test_a_broke_airport_whose_only_desks_are_blocked_gets_the_rescue_grant() -> void:
	_world = _blocked_desks_world()
	var grant: RescueGrant = auto_free(RescueGrant.new())
	grant.bind(_world.clock, _world.sim, _world.sim.wallet)
	var granted: Array = []
	grant.granted.connect(func(amount: int, _text: String) -> void: granted.append(amount))
	assert_bool(grant.has_working_path()).is_false()
	var plan := grant.repair_plan()
	print("plan ok %s edits %d" % [plan.ok, plan.edits.size()])
	assert_bool(plan.ok).is_true()
	assert_object(_desk_edit(plan)).is_not_null()
	assert_bool(grant.evaluate()).is_true()
	print("granted %s" % [granted])
	assert_array(granted).has_size(1)
	var paid: int = granted[0] if not granted.is_empty() else -1
	assert_int(paid).is_greater_equal(PriceTable.price_of_object(DESK))


func test_a_capped_search_skips_a_candidate_on_an_existing_spot() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	for id in ReferenceTerminal.object_ids(grid)["desks"]:
		assert_bool(grid.apply(BuildEdit.remove_object(id)).ok).is_true()
	# One choice per leg: the first desk the planner likes must be buildable.
	RepairPlan.max_tries = 1
	var baseline := RepairPlan.make(grid)
	var first := _desk_edit(baseline)
	print("baseline ok %s first desk %s facing %d" % [baseline.ok, first.cell, first.facing])
	assert_bool(baseline.ok).is_true()
	# A legacy scanner whose spot is that desk's own staff spot.
	var spot := StaffSpots.cell_of(DESK, first.cell, first.facing)
	var anchor := spot - StaffSpots.LAYOUT[SCANNER]["spot"]
	var legacy := _with_legacy(grid, [[SCANNER, anchor, 0]])
	var held: int = legacy.object_ids().max()
	assert_vector(StaffSpots.spot_of(legacy, held)).is_equal(spot)
	# The control: BuildGrid refuses that desk, for the spot.
	var refused := legacy.validate(first)
	assert_int(refused.reason).is_equal(BuildResult.Reason.STAFF_SPOT)
	var plan := RepairPlan.make(legacy)
	print("capped ok %s fallback %d edits %d" % [plan.ok, plan.fallback_price, plan.edits.size()])
	assert_bool(plan.ok).is_true()
	assert_int(plan.fallback_price).is_equal(-1)
	var desk := _desk_edit(plan)
	assert_object(desk).is_not_null()
	assert_bool(legacy.validate(desk).ok).is_true()
