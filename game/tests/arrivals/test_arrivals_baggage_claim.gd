class_name TestArrivalsBaggageClaim
extends GdUnitTestSuite
## Arrivals Slice A3: Tier-2 baggage_claim room + claim_carousel, component-
## isolated BeltShaper, inbound BagRoutes & BaggagePortOverlay, connect-gated
## inbound BaggageShuttle + circling carousel + CHECKED_BAG_BONUS + cart
## chaining, arriving passenger TO_CLAIM/AT_CLAIM pickup + deleted-carousel
## fallback, and SaveGame v48 round-trip + v47 refusal + SaveLinks checks.

var _mains: Array[Node] = []
var _worlds: Array[PassengerTestWorld] = []
var _nodes: Array[Node] = []
var _save_path := SaveTestKit.run_path("test_arrivals_baggage_claim")


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for m in _mains:
		if is_instance_valid(m):
			m.free()
	_mains.clear()
	for w in _worlds:
		w.free_all()
	_worlds.clear()
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	DirAccess.remove_absolute(_save_path)
	DirAccess.remove_absolute(_save_path + ".tmp")


func _boot_main(seed := 202612) -> Node:
	var m := SaveTestKit.boot(self, seed)
	_mains.append(m)
	SaveTestKit.start_airport(m)
	var flights: FlightSim = m.get_node("FlightSim")
	for _i in 300:
		SaveTestKit.step(m)
		if flights.opened_tick >= 0:
			break
	return m


func _apply_belt_line(grid: BuildGrid, cells: Array[Vector2i]) -> void:
	for i in cells.size():
		var from: Vector2i = cells[i]
		var to: Vector2i = cells[i]
		var planned := BeltShaper.plan_line(grid, from, to, 0)
		assert_bool(planned.result.ok).is_true()
		for res in grid.apply_batch(planned.edits):
			assert_bool(res.ok).is_true()


func _build_claim_facility(grid: BuildGrid, offset: Vector2i) -> Dictionary:
	# Expand East wing for bag_room at (22..25, 11..15) so outbound y=11 and inbound y=13
	# stay 2 cells apart, and place landside baggage_claim at (12..17, 13..16).
	var wing := Rect2i(Vector2i(22, 11) + offset, Vector2i(4, 5))
	var edits: Array[BuildEdit] = []
	for y in range(wing.position.y, wing.end.y):
		for x in range(wing.position.x, wing.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for res in grid.apply_batch(edits):
		assert_bool(res.ok).is_true()
	var wall_edits: Array[BuildEdit] = []
	for x in range(wing.position.x, wing.end.x):
		wall_edits.append(BuildEdit.place_wall(Vector2i(x, wing.position.y), BuildGrid.Side.NORTH))
		wall_edits.append(BuildEdit.place_wall(Vector2i(x, wing.end.y - 1), BuildGrid.Side.SOUTH))
	for y in range(wing.position.y, wing.end.y):
		wall_edits.append(BuildEdit.place_wall(Vector2i(wing.end.x - 1, y), BuildGrid.Side.EAST))
	for res in grid.apply_batch(wall_edits):
		assert_bool(res.ok).is_true()

	var bag_room_rect := wing
	# Leave a doorway gap on the interior edge (21, 14) -> (22, 14) so has_opening() is true.
	(
		assert_bool(
			grid.apply(BuildEdit.remove_wall(Vector2i(21, 14) + offset, BuildGrid.Side.EAST)).ok
		)
		. is_true()
	)
	var bag_room_res := grid.apply(BuildEdit.place_room(bag_room_rect, BeltShaper.BAG_ROOM))
	assert_bool(bag_room_res.ok).is_true()

	var claim_rect := Rect2i(Vector2i(12, 13) + offset, Vector2i(6, 4))
	var claim_res := grid.apply(BuildEdit.place_room(claim_rect, BeltShaper.BAGGAGE_CLAIM))
	assert_bool(claim_res.ok).is_true()

	var carousel_res := grid.apply(
		BuildEdit.place_object(BeltShaper.CLAIM_CAROUSEL, Vector2i(13, 14) + offset, 0)
	)
	assert_bool(carousel_res.ok).is_true()

	var cart_res := grid.apply(
		BuildEdit.place_object(BaggageSim.CART_DEF, Vector2i(24, 14) + offset, 0)
	)
	assert_bool(cart_res.ok).is_true()

	var end_res := grid.apply(BuildEdit.place_object(BeltShaper.END, Vector2i(22, 13) + offset, 1))
	assert_bool(end_res.ok).is_true()

	var belt_cells: Array[Vector2i] = []
	for x in range(15, 22):
		belt_cells.append(Vector2i(x, 13) + offset)
	_apply_belt_line(grid, belt_cells)
	# Open belt hatch after both adjacent belts exist, then reshape end & belts.
	(
		assert_bool(
			(
				grid
				. apply(
					BuildEdit.set_belt_hatch(Vector2i(21, 13) + offset, BuildGrid.Side.EAST, true)
				)
				. ok
			)
		)
		. is_true()
	)
	var all_cells: Array[Vector2i] = belt_cells.duplicate()
	all_cells.append(Vector2i(22, 13) + offset)
	var reshape := BeltShaper.reshape_edits(grid, all_cells)
	for res in grid.apply_batch(reshape):
		assert_bool(res.ok).is_true()
	assert_bool(RoomRules.status(grid, bag_room_res.room_id).ok).is_true()
	assert_bool(RoomRules.status(grid, claim_res.room_id).ok).is_true()

	return {
		"bag_room_id": bag_room_res.room_id,
		"claim_room_id": claim_res.room_id,
		"carousel_id": carousel_res.object_id,
		"cart_id": cart_res.object_id,
		"end_cell": Vector2i(22, 13) + offset,
		"inlet_cell": Vector2i(15, 13) + offset,
	}


func test_belt_shaper_rejects_outbound_inbound_bridges_on_all_edit_paths() -> void:
	var grid := BuildGrid.new(Vector2i(24, 16))
	var floor_edits: Array[BuildEdit] = []
	for y in range(2, 12):
		for x in range(2, 20):
			floor_edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for res in grid.apply_batch(floor_edits):
		assert_bool(res.ok).is_true()

	# Outbound desk at (4, 4) facing 0 -> outlet port (5, 4) -> (5, 3)..(8, 3).
	assert_bool(grid.apply(BuildEdit.place_object(BeltShaper.DESK, Vector2i(4, 4), 0)).ok).is_true()
	_apply_belt_line(grid, [Vector2i(5, 3), Vector2i(6, 3), Vector2i(7, 3), Vector2i(8, 3)])

	# Inbound claim room + carousel at (13, 6) facing 0 -> inlet port (15, 6) -> (15, 5).
	(
		assert_bool(
			grid.apply(BuildEdit.place_room(Rect2i(11, 4, 7, 5), BeltShaper.BAGGAGE_CLAIM)).ok
		)
		. is_true()
	)
	(
		assert_bool(
			grid.apply(BuildEdit.place_object(BeltShaper.CLAIM_CAROUSEL, Vector2i(13, 6), 0)).ok
		)
		. is_true()
	)
	_apply_belt_line(grid, [Vector2i(15, 5), Vector2i(14, 5), Vector2i(13, 5), Vector2i(12, 5)])

	# 1. Direct belt bridge between outbound (8, 3) and inbound (12, 5) refused.
	var bridge := BeltShaper.plan_line(grid, Vector2i(9, 3), Vector2i(11, 5), 0)
	assert_bool(bridge.result.ok).is_false()
	assert_int(bridge.result.reason).is_equal(BuildResult.Reason.BELT_MIXED_FLOW)
	var short_reason: String = GhostReason.SHORT_TEXT.get(BuildResult.Reason.BELT_MIXED_FLOW, "")
	assert_str(short_reason).is_not_empty()
	assert_int(short_reason.length()).is_less_equal(GhostReason.MAX_SHORT)

	# 2. Adjacent 1-cell parallel belt merge beside inbound (12, 5) while touching outbound (8, 3).
	_apply_belt_line(grid, [Vector2i(9, 3), Vector2i(10, 3), Vector2i(11, 3), Vector2i(11, 4)])
	var parallel := BeltShaper.plan_line(grid, Vector2i(11, 5), Vector2i(11, 5), 0)
	assert_bool(parallel.result.ok).is_false()
	assert_int(parallel.result.reason).is_equal(BuildResult.Reason.BELT_MIXED_FLOW)

	# 3. PLACE_OBJECT: desk at (11, 6) -> outlet (12, 6) into inbound (12, 5);
	# carousel at (6, 4) -> inlet (8, 4) into outbound (8, 3).
	var desk_on_inbound := BuildEdit.place_object(BeltShaper.DESK, Vector2i(11, 6), 0)
	var desk_res := BeltShaper.crossing_problem(grid, desk_on_inbound)
	assert_object(desk_res).is_not_null()
	assert_int(desk_res.reason).is_equal(BuildResult.Reason.BELT_MIXED_FLOW)
	var carousel_on_outbound := BuildEdit.place_object(BeltShaper.CLAIM_CAROUSEL, Vector2i(6, 4), 0)
	var carousel_res := BeltShaper.crossing_problem(grid, carousel_on_outbound)
	assert_object(carousel_res).is_not_null()
	assert_int(carousel_res.reason).is_equal(BuildResult.Reason.BELT_MIXED_FLOW)

	# 4 & 5. Wall separating outbound (11, 4) and inbound (12, 4): REMOVE_WALL & SET_BELT_HATCH refuse.
	assert_bool(grid.apply(BuildEdit.place_wall(Vector2i(11, 4), BuildGrid.Side.EAST)).ok).is_true()
	_apply_belt_line(grid, [Vector2i(12, 4)])
	var rm_res := BeltShaper.crossing_problem(
		grid, BuildEdit.remove_wall(Vector2i(11, 4), BuildGrid.Side.EAST)
	)
	assert_object(rm_res).is_not_null()
	assert_int(rm_res.reason).is_equal(BuildResult.Reason.BELT_MIXED_FLOW)
	var hatch_res := BeltShaper.crossing_problem(
		grid, BuildEdit.set_belt_hatch(Vector2i(11, 4), BuildGrid.Side.EAST, true)
	)
	assert_object(hatch_res).is_not_null()
	assert_int(hatch_res.reason).is_equal(BuildResult.Reason.BELT_MIXED_FLOW)


func test_baggage_claim_room_tier2_airside_warning_overlay_and_routes_isolation() -> void:
	var grid := BuildGrid.new(Vector2i(32, 24))
	ReferenceTerminal.build(grid)

	# Tier-2 unlock check for both tools.
	assert_int(BuildUnlocks.tier_of(BuildMode.Tool.BAGGAGE_CLAIM)).is_equal(2)
	assert_int(BuildUnlocks.tier_of(BuildMode.Tool.CLAIM_CAROUSEL)).is_equal(2)

	# Clear north seat rows so airside baggage_claim room fits cleanly.
	for sx in [11, 14]:
		var sid := grid.object_at(Vector2i(sx, 3))
		if sid != 0:
			assert_bool(grid.apply(BuildEdit.remove_object(sid)).ok).is_true()
	var air_room := grid.apply(BuildEdit.place_room(Rect2i(11, 2, 6, 4), BeltShaper.BAGGAGE_CLAIM))
	assert_bool(air_room.ok).is_true()
	var air_carousel := BuildEdit.place_object(BeltShaper.CLAIM_CAROUSEL, Vector2i(12, 3), 0)
	assert_bool(grid.apply(air_carousel).ok).is_true()
	var air_status := RoomRules.status(grid, air_room.room_id)
	assert_bool(air_status.ok).is_true()
	assert_bool(air_status.airside_warning).is_true()

	var mode := BuildMode.new()
	mode.grid_size = grid.size
	add_child(mode)
	_nodes.append(mode)
	mode.set_process(false)
	mode.grid = grid
	var panel := RoomPanel.new()
	add_child(panel)
	_nodes.append(panel)
	panel.watch(mode)
	panel.show_room(air_room.room_id)
	var amber_found := false
	for label in panel.find_children("*", "Label", true, false):
		if (label as Label).text == "In airside zone: move to landside":
			amber_found = true
			assert_str(str((label as Label).theme_type_variation)).is_equal("HudAttentionText")
	assert_bool(amber_found).is_true()

	# Landside baggage_claim + connected bag_room with both outbound and inbound lines.
	var info := _build_claim_facility(grid, Vector2i.ZERO)
	var land_status := RoomRules.status(grid, info["claim_room_id"])
	assert_bool(land_status.ok).is_true()
	assert_bool(land_status.airside_warning).is_false()

	# Outbound desk (14, 11) outlet (15, 10) -> (16, 10) -> (16..21, 11) -> (22, 11).
	var out_end := grid.apply(BuildEdit.place_object(BeltShaper.END, Vector2i(22, 11), 1))
	assert_bool(out_end.ok).is_true()
	var out_line: Array[Vector2i] = [Vector2i(15, 10), Vector2i(16, 10)]
	for x in range(16, 22):
		out_line.append(Vector2i(x, 11))
	_apply_belt_line(grid, out_line)
	(
		assert_bool(
			grid.apply(BuildEdit.set_belt_hatch(Vector2i(21, 11), BuildGrid.Side.EAST, true)).ok
		)
		. is_true()
	)
	var out_all: Array[Vector2i] = out_line.duplicate()
	out_all.append(Vector2i(22, 11))
	for res in grid.apply_batch(BeltShaper.reshape_edits(grid, out_all)):
		assert_bool(res.ok).is_true()

	var routes := BagRoutes.build(grid)
	assert_bool(routes.has_connected_baggage_claim()).is_true()
	assert_array(routes.connected_carousels()).is_equal([info["carousel_id"]])
	assert_bool(routes.has_inbound_route(info["end_cell"])).is_true()
	assert_bool(routes.has_route(info["end_cell"])).is_false()
	assert_bool(routes.has_route(Vector2i(15, 10))).is_true()
	assert_bool(routes.has_inbound_route(Vector2i(15, 10))).is_false()

	# BaggagePortOverlay renders for CLAIM_CAROUSEL tool and separates flows.
	var overlay := BaggagePortOverlay.new()
	add_child(overlay)
	_nodes.append(overlay)
	overlay.watch(mode, grid)
	mode.set_tool(BuildMode.Tool.CLAIM_CAROUSEL)
	assert_bool(overlay.visible).is_true()
	var has_carousel_marker := false
	var has_inbound_end := false
	var has_outbound_end := false
	for m: Dictionary in overlay.markers():
		if m["kind"] == &"carousel_inlet":
			has_carousel_marker = true
		elif m["kind"] == &"belt_end" and m.get("flow") == &"inbound":
			has_inbound_end = true
		elif m["kind"] == &"belt_end" and m.get("flow") == &"outbound":
			has_outbound_end = true
	assert_bool(has_carousel_marker).is_true()
	assert_bool(has_inbound_end).is_true()
	assert_bool(has_outbound_end).is_true()


func test_connect_gating_inbound_shuttle_claim_bonus_and_cart_chaining() -> void:
	# Part A: Without connected baggage_claim, AT_STAND creates zero inbound bags.
	var m_no_claim := _boot_main(202613)
	var f_no: FlightSim = m_no_claim.get_node("FlightSim")
	var b_no: BaggageSim = m_no_claim.get_node("BaggageSim")
	var starter := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	var at_stand_t := f_no.state_start(starter, FlightSim.State.AT_STAND)
	while m_no_claim.get_node("SimClock").tick < at_stand_t + 5:
		SaveTestKit.step(m_no_claim)
	var inbound_before := 0
	for bag in b_no.bags():
		if bag.inbound:
			inbound_before += 1
	assert_int(inbound_before).is_equal(0)

	# Part B: With connected baggage_claim + Ramp agent + outbound & inbound in same bag_room.
	var m := _boot_main(202614)
	var clock: SimClock = m.get_node("SimClock")
	var flights: FlightSim = m.get_node("FlightSim")
	var pax: PassengerSim = m.get_node("PassengerSim")
	var bag_sim: BaggageSim = m.get_node("BaggageSim")
	var staff: StaffSim = m.get_node("Staff")
	var finances: Finances = m.get_node("Finances")
	var grid: BuildGrid = pax.grid
	var offset: Vector2i = pax.site.starter_offset

	var place_exit := BuildEdit.place_object(
		BuildCatalog.AIRSIDE_EXIT_ID, Vector2i(13, 8) + offset, 2
	)
	for edit: BuildEdit in DoorPlacement.edits_for(grid, place_exit):
		assert_bool(grid.apply(edit).ok).is_true()
	var info := _build_claim_facility(grid, offset)

	# Also connect outbound belt end in the SAME bag_room to test cart chaining!
	(
		assert_bool(
			grid.apply(BuildEdit.place_object(BeltShaper.END, Vector2i(22, 11) + offset, 1)).ok
		)
		. is_true()
	)
	var out_cells: Array[Vector2i] = [Vector2i(15, 10) + offset, Vector2i(16, 10) + offset]
	for x in range(16, 22):
		out_cells.append(Vector2i(x, 11) + offset)
	_apply_belt_line(grid, out_cells)
	(
		assert_bool(
			(
				grid
				. apply(
					BuildEdit.set_belt_hatch(Vector2i(21, 11) + offset, BuildGrid.Side.EAST, true)
				)
				. ok
			)
		)
		. is_true()
	)
	var out_all: Array[Vector2i] = out_cells.duplicate()
	out_all.append(Vector2i(22, 11) + offset)
	var reshape := BeltShaper.reshape_edits(grid, out_all)
	for res in grid.apply_batch(reshape):
		assert_bool(res.ok).is_true()

	# Hire a Ramp agent so RampDispatch approves shuttles cleanly.
	assert_int(staff.hire(StaffMember.Role.RAMP)).is_greater(0)

	# Advance to AT_STAND so inbound bags spawn and inbound shuttle dispatches.
	var at_stand := flights.state_start(starter, FlightSim.State.AT_STAND)
	while clock.tick < at_stand + 4:
		SaveTestKit.step(m)

	var inbound_bags: Array[Bag] = []
	for bag in bag_sim.bags():
		if bag.inbound and bag.flight == starter:
			inbound_bags.append(bag)
	assert_int(inbound_bags.size()).is_greater(0)

	# Verify inbound shuttle has driver_staff_id > 0 and carrying_bags() == true only on RETURNING.
	var seen_returning_carrying := false
	var seen_carousel_orbit := false
	var thought_found := false
	var claimed_signals: Array[int] = []
	bag_sim.inbound_bag_claimed.connect(
		func(bag_id: int, _pid: int, _fid: String) -> void: claimed_signals.append(bag_id)
	)
	var fees_credited := [0]
	finances.wallet.transaction.connect(
		func(amount: int, category: int, _claimed: Dictionary, _t: int) -> void:
			if category == Wallet.Category.FEES and amount > 0:
				fees_credited[0] += amount
	)

	# Advance until inbound bags reach carousel and returning shuttle frees the cart,
	# then run an outbound check-in bag on the SAME bag_room to verify cart chaining!
	var chain_bag: Bag = null
	for _step in 2600:
		SaveTestKit.step(m)
		for s: BaggageShuttle in bag_sim.shuttles():
			if s.inbound:
				assert_int(s.driver_staff_id).is_greater(0)
				if s.phase == BaggageShuttle.Phase.OUTBOUND:
					assert_bool(s.carrying_bags()).is_false()
				elif s.phase == BaggageShuttle.Phase.RETURNING:
					assert_bool(s.carrying_bags()).is_true()
					seen_returning_carrying = true
		for bag in inbound_bags:
			if bag.state == Bag.State.ON_CAROUSEL:
				var xf: Variant = BaggageViews.carousel_transform(grid, bag, clock.tick + 10)
				assert_bool(xf is Transform3D).is_true()
				seen_carousel_orbit = true
		for pid in pax.passenger_ids():
			var p := pax.get_passenger(pid)
			if p != null and p.is_arriving() and p.has_claimed_bag:
				for entry: Dictionary in PassengerThoughts.entries(p):
					if int(entry["kind"]) == PassengerThoughts.Kind.CLAIMED_BAG:
						thought_found = true
		if chain_bag == null and seen_returning_carrying and bag_sim.shuttles().is_empty():
			# Cart just freed from inbound return: check in an outbound bag that will
			# reach cutoff after riding the 10-cell belt and reuse the exact same cart!
			chain_bag = bag_sim.check_in(99001, starter, grid.object_at(Vector2i(14, 11) + offset))
			if chain_bag != null:
				chain_bag.cutoff_tick = clock.tick + 240
		if bag_sim.inbound_claimed_total >= inbound_bags.size():
			break

	assert_bool(seen_returning_carrying).is_true()
	assert_bool(seen_carousel_orbit).is_true()
	assert_int(bag_sim.inbound_claimed_total).is_equal(inbound_bags.size())
	assert_int(claimed_signals.size()).is_equal(inbound_bags.size())
	assert_int(fees_credited[0]).is_greater_equal(
		inbound_bags.size() * PriceTable.CHECKED_BAG_BONUS
	)
	assert_int(bag_sim.missed_total).is_equal(0)
	assert_bool(thought_found).is_true()

	# Also wait for the chained outbound bag to dispatch on the freed cart.
	assert_object(chain_bag).is_not_null()
	for _j in 600:
		SaveTestKit.step(m)
		if chain_bag.state == Bag.State.LOADED:
			break
	assert_int(chain_bag.state).is_equal(Bag.State.LOADED)


func test_deleted_carousel_mid_flight_unblocks_waiting_passenger_cleanly() -> void:
	var m := _boot_main(202615)
	var clock: SimClock = m.get_node("SimClock")
	var flights: FlightSim = m.get_node("FlightSim")
	var pax: PassengerSim = m.get_node("PassengerSim")
	var bag_sim: BaggageSim = m.get_node("BaggageSim")
	var staff: StaffSim = m.get_node("Staff")
	var grid: BuildGrid = pax.grid
	var offset: Vector2i = pax.site.starter_offset

	var place_exit := BuildEdit.place_object(
		BuildCatalog.AIRSIDE_EXIT_ID, Vector2i(13, 8) + offset, 2
	)
	for edit: BuildEdit in DoorPlacement.edits_for(grid, place_exit):
		assert_bool(grid.apply(edit).ok).is_true()
	var info := _build_claim_facility(grid, offset)
	assert_int(staff.hire(StaffMember.Role.RAMP)).is_greater(0)

	var starter := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	var deboard := flights.state_start(starter, FlightSim.State.DEBOARDING)
	while clock.tick < deboard + 5:
		SaveTestKit.step(m)

	# Wait until at least one arriving passenger is in TO_CLAIM or AT_CLAIM.
	var waiter: Passenger = null
	for _i in 600:
		SaveTestKit.step(m)
		for pid in pax.passenger_ids():
			var p := pax.get_passenger(pid)
			if (
				p != null
				and p.is_arriving()
				and not p.has_claimed_bag
				and (p.stage == Passenger.Stage.TO_CLAIM or p.stage == Passenger.Stage.AT_CLAIM)
			):
				waiter = p
				break
		if waiter != null:
			break
	assert_object(waiter).is_not_null()

	# Delete the claim_carousel while the passenger is waiting/walking to it!
	assert_bool(grid.apply(BuildEdit.remove_object(info["carousel_id"])).ok).is_true()
	SaveTestKit.step(m)
	SaveTestKit.step(m)

	# Passenger must immediately fall back out of claim toward exit without freezing,
	# and inbound lost count > 0.
	var left_claim := (
		waiter.stage != Passenger.Stage.TO_CLAIM and waiter.stage != Passenger.Stage.AT_CLAIM
	)
	assert_bool(left_claim).is_true()
	assert_int(bag_sim.inbound_lost_total).is_greater(0)


func test_save_v49_round_trip_v47_refusal_and_save_links_validation() -> void:
	var m := _boot_main(202616)
	var clock: SimClock = m.get_node("SimClock")
	var flights: FlightSim = m.get_node("FlightSim")
	var pax: PassengerSim = m.get_node("PassengerSim")
	var bag_sim: BaggageSim = m.get_node("BaggageSim")
	var staff: StaffSim = m.get_node("Staff")
	var grid: BuildGrid = pax.grid
	var offset: Vector2i = pax.site.starter_offset

	var place_exit := BuildEdit.place_object(
		BuildCatalog.AIRSIDE_EXIT_ID, Vector2i(13, 8) + offset, 2
	)
	for edit: BuildEdit in DoorPlacement.edits_for(grid, place_exit):
		assert_bool(grid.apply(edit).ok).is_true()
	var info := _build_claim_facility(grid, offset)
	assert_int(staff.hire(StaffMember.Role.RAMP)).is_greater(0)

	var starter := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	var at_stand := flights.state_start(starter, FlightSim.State.AT_STAND)
	while clock.tick < at_stand + 10:
		SaveTestKit.step(m)

	# Step until at least one inbound bag is ON_CAROUSEL or an inbound shuttle is RETURNING,
	# AND at least one arriving passenger is in TO_CLAIM or AT_CLAIM.
	var claimer_id := 0
	for _i in 600:
		SaveTestKit.step(m)
		for pid in pax.passenger_ids():
			var p := pax.get_passenger(pid)
			if (
				p != null
				and p.is_arriving()
				and (p.stage == Passenger.Stage.TO_CLAIM or p.stage == Passenger.Stage.AT_CLAIM)
			):
				claimer_id = p.id
				break
		if claimer_id != 0:
			break
	assert_int(claimer_id).is_greater(0)

	# SaveGame v49 round-trip.
	assert_bool(SaveTestKit.save_game(m).save_to_file(_save_path)).is_true()
	var loaded := SaveTestKit.boot(self, 998)
	_mains.append(loaded)
	assert_bool(SaveTestKit.save_game(loaded).load_from_file(_save_path)).is_true()

	var l_pax: PassengerSim = loaded.get_node("PassengerSim")
	var l_bag: BaggageSim = loaded.get_node("BaggageSim")
	var lp := l_pax.get_passenger(claimer_id)
	assert_object(lp).is_not_null()
	assert_int(lp.claim_carousel).is_equal(info["carousel_id"])
	assert_int(lp.claim_bag_id).is_greater(0)

	# Continue loaded world until claim finishes cleanly.
	for _j in 2000:
		SaveTestKit.step(loaded)
		if l_bag.inbound_claimed_total > 0 and lp.has_claimed_bag:
			break
	assert_bool(lp.has_claimed_bag).is_true()
	assert_int(l_bag.inbound_claimed_total).is_greater(0)

	# Version 47 refusal.
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_save_path))
	assert_int(int(raw["save_version"])).is_equal(50)
	var v47: Dictionary = raw.duplicate(true)
	v47["save_version"] = 47
	FileAccess.open(_save_path, FileAccess.WRITE).store_string(JSON.stringify(v47))
	var reject_v47 := SaveTestKit.boot(self, 997)
	_mains.append(reject_v47)
	assert_bool(SaveTestKit.save_game(reject_v47).load_from_file(_save_path)).is_false()

	# SaveLinks refusal: claimer pointing to bogus carousel id.
	var broken: Dictionary = raw.duplicate(true)
	for rec: Dictionary in broken["passengers"]["passengers"]:
		if int(rec["id"]) == claimer_id:
			rec["claim_carousel"] = 99999
	FileAccess.open(_save_path, FileAccess.WRITE).store_string(JSON.stringify(broken))
	var reject_link := SaveTestKit.boot(self, 996)
	_mains.append(reject_link)
	assert_bool(SaveTestKit.save_game(reject_link).load_from_file(_save_path)).is_false()


func test_same_tick_save_on_inbound_bag_loss_and_needs_policy_isolation() -> void:
	var m := _boot_main(202617)
	var clock: SimClock = m.get_node("SimClock")
	var flights: FlightSim = m.get_node("FlightSim")
	var pax: PassengerSim = m.get_node("PassengerSim")
	var bag_sim: BaggageSim = m.get_node("BaggageSim")
	var staff: StaffSim = m.get_node("Staff")
	var grid: BuildGrid = pax.grid
	var offset: Vector2i = pax.site.starter_offset

	var place_exit := BuildEdit.place_object(
		BuildCatalog.AIRSIDE_EXIT_ID, Vector2i(13, 8) + offset, 2
	)
	for edit: BuildEdit in DoorPlacement.edits_for(grid, place_exit):
		assert_bool(grid.apply(edit).ok).is_true()
	_build_claim_facility(grid, offset)
	assert_int(staff.hire(StaffMember.Role.RAMP)).is_greater(0)

	var starter := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	var at_stand := flights.state_start(starter, FlightSim.State.AT_STAND)
	while clock.tick < at_stand + 10:
		SaveTestKit.step(m)

	# Wait for an arriving passenger in TO_CLAIM/AT_CLAIM whose inbound bag is off the
	# shuttle (IN_ROOM or RIDING) and not yet ON_CAROUSEL, then break its route.
	var target_pax: Passenger = null
	var target_bag: Bag = null
	for _i in 900:
		SaveTestKit.step(m)
		for pid in pax.passenger_ids():
			var p := pax.get_passenger(pid)
			if p == null or not p.is_arriving():
				continue
			if p.stage != Passenger.Stage.TO_CLAIM and p.stage != Passenger.Stage.AT_CLAIM:
				continue
			var bag := bag_sim.get_bag(p.claim_bag_id)
			if (
				bag != null
				and not bag.is_settled()
				and bag.shuttle_id == 0
				and (bag.state == Bag.State.IN_ROOM or bag.on_belt())
			):
				target_pax = p
				target_bag = bag
				break
		if target_pax != null:
			break
	assert_object(target_pax).is_not_null()
	assert_object(target_bag).is_not_null()

	# NeedsPolicy must never interrupt a passenger in TO_CLAIM or AT_CLAIM.
	target_pax.toilet_need = ToiletSim.NEED_MAX
	target_pax.hunger = CafeSim.HUNGER_MAX
	assert_int(int(NeedsPolicy.choose(pax, target_pax)["need"])).is_equal(NeedsPolicy.Need.NONE)

	# Remove the belt/end cell holding the bag while claim_carousel stays placed, then run ONE
	# single tick T: BaggageSim._reconcile settles the bag LOST, and PassengerSim._on_inbound_bag_lost
	# must immediately clear claim fields and leave TO_CLAIM/AT_CLAIM on tick T itself.
	var remove_cell := (
		target_bag.physical_cell() if target_bag.on_belt() else Vector2i(22, 13) + offset
	)
	var obj_id := grid.object_at(remove_cell)
	assert_int(obj_id).is_greater(0)
	assert_bool(grid.apply(BuildEdit.remove_object(obj_id)).ok).is_true()
	SaveTestKit.step(m)

	assert_int(target_pax.claim_bag_id).is_equal(0)
	assert_int(target_pax.claim_carousel).is_equal(0)
	var exited_claim := (
		target_pax.stage != Passenger.Stage.TO_CLAIM
		and target_pax.stage != Passenger.Stage.AT_CLAIM
	)
	assert_bool(exited_claim).is_true()
	assert_int(bag_sim.inbound_lost_total).is_greater(0)

	# Saving immediately at the end of tick T must pass SaveGame & SaveLinks cleanly.
	assert_bool(SaveTestKit.save_game(m).save_to_file(_save_path)).is_true()
	var loaded := SaveTestKit.boot(self, 995)
	_mains.append(loaded)
	assert_bool(SaveTestKit.save_game(loaded).load_from_file(_save_path)).is_true()


func test_adjacent_bag_room_end_directly_on_carousel_inlet_delivers_bags() -> void:
	var m := _boot_main(202618)
	var clock: SimClock = m.get_node("SimClock")
	var flights: FlightSim = m.get_node("FlightSim")
	var pax: PassengerSim = m.get_node("PassengerSim")
	var bag_sim: BaggageSim = m.get_node("BaggageSim")
	var staff: StaffSim = m.get_node("Staff")
	var grid: BuildGrid = pax.grid
	var offset: Vector2i = pax.site.starter_offset

	var place_exit := BuildEdit.place_object(
		BuildCatalog.AIRSIDE_EXIT_ID, Vector2i(13, 8) + offset, 2
	)
	for edit: BuildEdit in DoorPlacement.edits_for(grid, place_exit):
		assert_bool(grid.apply(edit).ok).is_true()

	# Place baggage_claim at (12..17, 14..17) with claim_carousel at (13, 14) -> inlet (15, 13),
	# and place bag_room at (15..18, 12..13) with baggage_belt_end directly on (15, 13) facing South.
	var claim_rect := Rect2i(Vector2i(12, 14) + offset, Vector2i(6, 4))
	assert_bool(grid.apply(BuildEdit.place_room(claim_rect, BeltShaper.BAGGAGE_CLAIM)).ok).is_true()
	var carousel_res := grid.apply(
		BuildEdit.place_object(BeltShaper.CLAIM_CAROUSEL, Vector2i(13, 14) + offset, 0)
	)
	assert_bool(carousel_res.ok).is_true()

	var bag_room_rect := Rect2i(Vector2i(15, 12) + offset, Vector2i(4, 2))
	assert_bool(grid.apply(BuildEdit.place_room(bag_room_rect, BeltShaper.BAG_ROOM)).ok).is_true()
	var end_cell := Vector2i(15, 13) + offset
	assert_bool(grid.apply(BuildEdit.place_object(BeltShaper.END, end_cell, 0)).ok).is_true()
	(
		assert_bool(
			grid.apply(BuildEdit.place_object(BaggageSim.CART_DEF, Vector2i(17, 12) + offset, 0)).ok
		)
		. is_true()
	)

	var routes := BagRoutes.build(grid)
	assert_bool(routes.is_inbound_root(end_cell)).is_true()
	assert_bool(routes.has_inbound_route(end_cell)).is_true()
	assert_vector(routes.inbound_step_from(end_cell)).is_equal(Vector2i.ZERO)
	assert_bool(routes.has_connected_baggage_claim()).is_true()

	assert_int(staff.hire(StaffMember.Role.RAMP)).is_greater(0)
	var starter := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	var at_stand := flights.state_start(starter, FlightSim.State.AT_STAND)
	while clock.tick < at_stand + 10:
		SaveTestKit.step(m)

	var seen_on_carousel := false
	for _step in 2600:
		SaveTestKit.step(m)
		for bag in bag_sim.bags():
			if bag.inbound and bag.state == Bag.State.ON_CAROUSEL:
				seen_on_carousel = true
		if bag_sim.inbound_claimed_total > 0 and seen_on_carousel:
			break

	assert_bool(seen_on_carousel).is_true()
	assert_int(bag_sim.inbound_claimed_total).is_greater(0)
