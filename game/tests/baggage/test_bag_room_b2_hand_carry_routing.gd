class_name TestBagRoomB2HandCarryRouting
extends GdUnitTestSuite
## Bag Room Rethink Slice B2 acceptance tests:
## 1) Bay-door-only orthogonal routing (>= 0.85 m clearance, no wall/passenger-door
##    shortcuts, _reconcile() replan on fallback door & clean cancel when none).
## 2) Ramp Agent bay-door entry/exit walk with zero wall-teleport jumps.
## 3) 2-bag hand-carry in TRANSFER_OUT & post-RETURNING TRANSFER_IN with
##    incremental visual continuity and Hand.R / Hand.L suitcase props.
## 4) Round-trip-guarded BOARDING outbound waves, flight-specific filtering,
##    1-cart AT_STAND inbound priority, and final cutoff sweep.
## 5) Mid-TO_BAG_ROOM, mid-TRANSFER_OUT, and mid-TRANSFER_IN SaveGame v51
##    round-trips and v50 refusal.

const RAMP := StaffMember.Role.RAMP
const SITE := preload("res://build/terminal_site.tres")

var _mains: Array[Node] = []
var _nodes: Array[Node] = []
var _save_path := SaveTestKit.run_path("test_bag_room_b2")


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for m in _mains:
		if is_instance_valid(m):
			m.free()
	_mains.clear()
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	DirAccess.remove_absolute(_save_path)
	DirAccess.remove_absolute(_save_path + ".tmp")


func _boot_main(seed := 51201) -> Node:
	var m := SaveTestKit.boot(self, seed)
	_mains.append(m)
	SaveTestKit.start_airport(m)
	var flights: FlightSim = m.get_node("FlightSim")
	for _i in 300:
		SaveTestKit.step(m)
		if flights.opened_tick >= 0:
			break
	return m


func _build_ramp_bag_world(doors := 600) -> Dictionary:
	var w := BagTestWorld.make(self, doors)
	var desk := w.line()
	var cart_id := PassengerTestWorld.place(w.grid, &"baggage_cart", Vector2i(11, 7), 0)
	var staff := auto_free(StaffSim.new()) as StaffSim
	var pax := auto_free(PassengerSim.new()) as PassengerSim
	pax.clock = w.clock
	pax.flights = w.flights
	pax.grid = w.grid
	pax.layout = TerminalLayout.new()
	pax.layout.rebuild(w.grid)
	pax.staff = staff
	staff.sim = pax
	var finances := auto_free(Finances.new()) as Finances
	finances.clock = w.clock
	finances.start_new_game()
	var dispatch := auto_free(RampDispatch.new()) as RampDispatch
	dispatch.bind(w.clock, staff, w.sim, w.flights, finances, null)
	var chars := auto_free(StaffCharacters.new()) as StaffCharacters
	chars.clock = w.clock
	chars.staff = staff
	chars.baggage = w.sim
	chars.flights = w.flights
	add_child(chars)
	var bviews := auto_free(BaggageViews.new()) as BaggageViews
	bviews.clock = w.clock
	bviews.sim = w.sim
	add_child(bviews)
	return {
		"world": w,
		"desk": desk,
		"cart_id": cart_id,
		"staff": staff,
		"dispatch": dispatch,
		"chars": chars,
		"bviews": bviews,
	}


func _bag_swatch_color(node: Node3D) -> Color:
	var mesh_instance: MeshInstance3D = (
		(
			node as MeshInstance3D
			if node is MeshInstance3D
			else node.find_child("BaggageBag_Body", true, false)
		)
		as MeshInstance3D
	)
	assert_object(mesh_instance).is_not_null()
	var mat := mesh_instance.get_active_material(0) as ShaderMaterial
	assert_object(mat).is_not_null()
	var tex := mat.get_shader_parameter("albedo_texture") as Texture2D
	assert_object(tex).is_not_null()
	var img: Image = tex.get_image()
	assert_object(img).is_not_null()
	var cell_w := maxi(1, int(img.get_width() / 32.0))
	return img.get_pixel(31 * cell_w + 1, 1)


func _build_claim_and_outbound_in_main(m: Node) -> Dictionary:
	var pax: PassengerSim = m.get_node("PassengerSim")
	var grid: BuildGrid = pax.grid
	var offset: Vector2i = pax.site.starter_offset
	var place_exit := BuildEdit.place_object(
		BuildCatalog.AIRSIDE_EXIT_ID, Vector2i(13, 8) + offset, 2
	)
	for edit: BuildEdit in DoorPlacement.edits_for(grid, place_exit):
		assert_bool(grid.apply(edit).ok).is_true()

	var wing := Rect2i(Vector2i(22, 11) + offset, Vector2i(4, 5))
	var edits: Array[BuildEdit] = []
	for y in range(wing.position.y, wing.end.y):
		for x in range(wing.position.x, wing.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for res in grid.apply_batch(edits):
		assert_bool(res.ok).is_true()
	var walls: Array[BuildEdit] = []
	for x in range(wing.position.x, wing.end.x):
		walls.append(BuildEdit.place_wall(Vector2i(x, wing.position.y), BuildGrid.Side.NORTH))
		walls.append(BuildEdit.place_wall(Vector2i(x, wing.end.y - 1), BuildGrid.Side.SOUTH))
	for y in range(wing.position.y, wing.end.y):
		walls.append(BuildEdit.place_wall(Vector2i(wing.end.x - 1, y), BuildGrid.Side.EAST))
	for res in grid.apply_batch(walls):
		assert_bool(res.ok).is_true()
	(
		assert_bool(
			grid.apply(BuildEdit.remove_wall(Vector2i(21, 14) + offset, BuildGrid.Side.EAST)).ok
		)
		. is_true()
	)
	assert_bool(grid.apply(BuildEdit.place_room(wing, BeltShaper.BAG_ROOM)).ok).is_true()
	var bay_edit := BuildEdit.place_object(BuildCatalog.BAY_DOOR_ID, Vector2i(25, 12) + offset, 1)
	var bay_id := 0
	for edit: BuildEdit in DoorPlacement.edits_for(grid, bay_edit):
		var res := grid.apply(edit)
		assert_bool(res.ok).is_true()
		if res.object_id > 0:
			bay_id = res.object_id

	var claim_rect := Rect2i(Vector2i(12, 13) + offset, Vector2i(6, 4))
	assert_bool(grid.apply(BuildEdit.place_room(claim_rect, BeltShaper.BAGGAGE_CLAIM)).ok).is_true()
	(
		assert_bool(
			(
				grid
				. apply(
					BuildEdit.place_object(BeltShaper.CLAIM_CAROUSEL, Vector2i(13, 14) + offset, 0)
				)
				. ok
			)
		)
		. is_true()
	)
	var cart_res := grid.apply(
		BuildEdit.place_object(BaggageSim.CART_DEF, Vector2i(24, 14) + offset, 0)
	)
	assert_bool(cart_res.ok).is_true()
	(
		assert_bool(
			grid.apply(BuildEdit.place_object(BeltShaper.END, Vector2i(22, 13) + offset, 1)).ok
		)
		. is_true()
	)
	var in_cells: Array[Vector2i] = []
	for x in range(15, 22):
		in_cells.append(Vector2i(x, 13) + offset)
	for c in in_cells:
		var plan := BeltShaper.plan_line(grid, c, c, 0)
		assert_bool(plan.result.ok).is_true()
		for res in grid.apply_batch(plan.edits):
			assert_bool(res.ok).is_true()
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
	var all_in := in_cells.duplicate()
	all_in.append(Vector2i(22, 13) + offset)
	for res in grid.apply_batch(BeltShaper.reshape_edits(grid, all_in)):
		assert_bool(res.ok).is_true()

	(
		assert_bool(
			grid.apply(BuildEdit.place_object(BeltShaper.END, Vector2i(22, 11) + offset, 1)).ok
		)
		. is_true()
	)
	var out_cells: Array[Vector2i] = [Vector2i(15, 10) + offset, Vector2i(16, 10) + offset]
	for x in range(16, 22):
		out_cells.append(Vector2i(x, 11) + offset)
	for c in out_cells:
		var plan := BeltShaper.plan_line(grid, c, c, 0)
		assert_bool(plan.result.ok).is_true()
		for res in grid.apply_batch(plan.edits):
			assert_bool(res.ok).is_true()
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
	var all_out := out_cells.duplicate()
	all_out.append(Vector2i(22, 11) + offset)
	for res in grid.apply_batch(BeltShaper.reshape_edits(grid, all_out)):
		assert_bool(res.ok).is_true()
	return {
		"bay_id": bay_id,
		"cart_id": cart_res.object_id,
		"desk2_id": grid.object_at(Vector2i(14, 11) + offset),
	}


func test_bay_door_orthogonal_anchors_corridor_clearance_and_reconcile() -> void:
	var w := BagTestWorld.make(self, 600)
	var desk := w.line()
	w.cart()
	# Add a second bay door on the north wall of ROOM (10..12, 6..8).
	var bay_doors := BaggageShuttle.valid_bay_doors_in_room(w.grid, BagTestWorld.ROOM)
	assert_int(bay_doors.size()).is_equal(1)
	var primary_door_id: int = bay_doors[0]["bay_door_id"]
	var anchors: Dictionary = bay_doors[0]
	var bay_in: Vector3 = anchors["inside_clear"]
	var bay_door: Vector3 = anchors["door_center"]
	var bay_out: Vector3 = anchors["outside_clear"]
	var out_step: Vector2i = anchors["out_step"]
	var out_dir := Vector3(float(out_step.x), 0.0, float(out_step.y))
	assert_vector((bay_door - bay_in).normalized()).is_equal_approx(out_dir, Vector3.ONE * 0.01)
	assert_vector((bay_out - bay_door).normalized()).is_equal_approx(out_dir, Vector3.ONE * 0.01)
	assert_float(bay_out.distance_to(bay_door)).is_greater_equal(0.95)

	# Apron corner clearance >= 0.85 m: diagonal grazing a terminal corner is rejected.
	var corner_a := w.grid.cell_to_world(Vector2i(13, 9))
	var corner_b := w.grid.cell_to_world(Vector2i(13, 5))
	assert_float(BaggageShuttle.APRON_CLEAR_HALF_WIDTH_M).is_greater_equal(0.85)
	var corner_route := BaggageShuttle.plan_route(w.grid, corner_a, corner_b)
	for i in corner_route.size() - 1:
		var seg_a := corner_route[i]
		var seg_b := corner_route[i + 1]
		assert_bool(BaggageShuttle.segment_hits_wall(w.grid, seg_a, seg_b, false)).is_false()
		var flat := Vector2(seg_b.x - seg_a.x, seg_b.z - seg_a.z)
		if flat.length() > 0.1:
			var perp := Vector2(-flat.y, flat.x).normalized() * 0.84
			var off := Vector3(perp.x, 0.0, perp.y)
			(
				assert_bool(
					BaggageShuttle.segment_hits_wall(w.grid, seg_a + off, seg_b + off, false)
				)
				. is_false()
			)
			(
				assert_bool(
					BaggageShuttle.segment_hits_wall(w.grid, seg_a - off, seg_b - off, false)
				)
				. is_false()
			)

	# Place a second valid bay door on north wall of (10..12, 6..8) -> (10, 6) facing 0.
	w._clear_bay_apron_north(10, 6)
	var second_door_id := 0
	for edit in DoorPlacement.edits_for(
		w.grid, BuildEdit.place_object(BuildCatalog.BAY_DOOR_ID, Vector2i(10, 6), 0)
	):
		var r := w.grid.apply(edit)
		assert_bool(r.ok).is_true()
		if r.object_id > 0:
			second_door_id = r.object_id
	assert_int(second_door_id).is_greater(0)

	# Dispatch shuttle, delete its relied-on bay door mid-OUTBOUND -> replans to surviving door.
	var bag := w.sim.check_in(1, BagTestWorld.FLIGHT, desk)
	w.run_to(bag.cutoff_tick)
	var shuttle := w.sim.shuttles()[0]
	var used_door := shuttle.bay_door_id
	var other_door := second_door_id if used_door == primary_door_id else primary_door_id
	w.run_to(shuttle.start_tick + 2)
	assert_int(shuttle.phase).is_equal(BaggageShuttle.Phase.OUTBOUND)
	assert_bool(w.grid.apply(BuildEdit.remove_object(used_door)).ok).is_true()
	w.step()
	assert_int(w.sim.shuttles().size()).is_equal(1)
	assert_int(shuttle.bay_door_id).is_equal(other_door)

	# Delete the remaining bay door mid-trip -> _reconcile() cleanly cancels without stranding.
	assert_bool(w.grid.apply(BuildEdit.remove_object(other_door)).ok).is_true()
	w.step()
	assert_array(w.sim.shuttles()).is_empty()
	assert_int(bag.state).is_equal(Bag.State.MISSED)
	assert_int(bag.cause).is_equal(Bag.Cause.LOST)
	assert_int(bag.shuttle_id).is_equal(0)


func test_ramp_agent_walks_through_bay_door_with_zero_wall_teleport() -> void:
	var ctx := _build_ramp_bag_world(600)
	var w: BagTestWorld = ctx["world"]
	var staff: StaffSim = ctx["staff"]
	var chars: StaffCharacters = ctx["chars"]
	var bviews: BaggageViews = ctx["bviews"]
	var ramp_id := staff.hire(RAMP)
	var bag0 := w.sim.check_in(1, BagTestWorld.FLIGHT, ctx["desk"], 0)
	var bag1 := w.sim.check_in(2, BagTestWorld.FLIGHT, ctx["desk"], 2)
	var bag2 := w.sim.check_in(3, BagTestWorld.FLIGHT, ctx["desk"], 4)
	w.run_to(BagTestWorld.ARRIVAL + 60)
	chars.sync(true)
	chars.draw()
	var node := chars.node_for(ramp_id)
	assert_object(node).is_not_null()
	var prev_pos := node.position
	assert_bool(w.grid.is_indoor(w.grid.world_to_cell(prev_pos))).is_false()

	var saw_to_bag_room := false
	var saw_transfer_out := false
	var saw_two_hand_carry := false
	var saw_cart_increment := false
	var saw_exited_back_to_apron := false
	var max_step_m := 0.0

	for _i in 650:
		w.step()
		chars.draw()
		bviews.draw()
		var cur_pos := node.position
		var dist := Vector2(cur_pos.x - prev_pos.x, cur_pos.z - prev_pos.z).length()
		max_step_m = maxf(max_step_m, dist)
		(
			assert_bool(BaggageShuttle.segment_hits_wall(w.grid, prev_pos, cur_pos, false))
			. override_failure_message(
				(
					"Ramp Agent crossed a solid wall at tick=%d %s -> %s"
					% [w.clock.tick, prev_pos, cur_pos]
				)
			)
			. is_false()
		)
		prev_pos = cur_pos

		if not w.sim.shuttles().is_empty():
			var s := w.sim.shuttles()[0]
			if s.phase == BaggageShuttle.Phase.TO_BAG_ROOM:
				saw_to_bag_room = true
			elif s.phase == BaggageShuttle.Phase.TRANSFER_OUT:
				saw_transfer_out = true
				if s.carried_bag_ids.size() == 2:
					saw_two_hand_carry = true
					var props := StaffHandProps.prop_nodes(node, StaffHandProps.PropKind.SUITCASES)
					assert_int(props.size()).is_equal(2)
					assert_bool(props[0].visible).is_true()
					assert_bool(props[1].visible).is_true()
					(
						assert_bool(
							_bag_swatch_color(props[0]).is_equal_approx(Bag.suitcase_color(0))
						)
						. is_true()
					)
					(
						assert_bool(
							_bag_swatch_color(props[1]).is_equal_approx(Bag.suitcase_color(2))
						)
						. is_true()
					)
				if s.bag_ids.size() == 2 and s.pending_bag_ids.size() == 1:
					saw_cart_increment = true
					assert_int(bviews.shuttle_bag_count(s.id)).is_equal(2)
					assert_int(bviews.active_count()).is_equal(1)
		elif (
			saw_transfer_out
			and staff.get_member(ramp_id).ramp_job == StaffMember.RampJob.NONE
			and w.grid.room_at(w.grid.world_to_cell(cur_pos)) == 0
		):
			saw_exited_back_to_apron = true
			break

	assert_bool(saw_to_bag_room).is_true()
	assert_bool(saw_transfer_out).is_true()
	assert_bool(saw_two_hand_carry).is_true()
	assert_bool(saw_cart_increment).is_true()
	assert_bool(saw_exited_back_to_apron).is_true()
	assert_float(max_step_m).is_less(1.0)
	for b in [bag0, bag1, bag2]:
		assert_int(b.state).is_equal(Bag.State.LOADED)


func test_thirty_bags_hand_carry_completes_inside_load_lead_window() -> void:
	var ctx := _build_ramp_bag_world(600)
	var w: BagTestWorld = ctx["world"]
	var staff: StaffSim = ctx["staff"]
	staff.hire(RAMP)
	var bags: Array[Bag] = []
	for i in 30:
		var b := w.sim.check_in(i + 1, BagTestWorld.FLIGHT, ctx["desk"], i % 6)
		b.state = Bag.State.IN_ROOM
		b.cell = BagTestWorld.END
		b.rest_tick = 10 + i
		bags.append(b)
	w.run_to(bags[0].cutoff_tick)
	assert_int(w.sim.shuttles().size()).is_equal(1)
	var s := w.sim.shuttles()[0]
	assert_int(s.unload_tick).is_less(600)
	w.run_to(s.unload_tick)
	assert_int(w.sim.loaded_total).is_equal(30)


func test_boarding_waves_guard_round_trip_flight_specificity_and_inbound_priority() -> void:
	var ctx := _build_ramp_bag_world(4000)
	var w: BagTestWorld = ctx["world"]
	var staff: StaffSim = ctx["staff"]
	staff.hire(RAMP)
	# Flight A: BOARDING from 200 to 1200 (final_cutoff = 1000).
	# Flight B: BOARDING from 200 to 1200 (final_cutoff = 1000).
	# Flight C: AT_STAND from 195 to 260 (inbound priority test).
	var starts_a: Array[int] = [0, 1, 2, 3, 100, 150, 200, 1200, 1260, 1380, 1680, 1880]
	var starts_b: Array[int] = [0, 1, 2, 3, 100, 150, 200, 1200, 1260, 1380, 1680, 1880]
	w.flights.add_flight("GMF202", starts_a)
	w.flights.add_flight("GMF303", starts_b)
	w.step()
	# Manually test flight-specific BOARDING wave: bags for GMF202 and GMF303 in room at tick 200.
	var a0 := w.sim.check_in(1, "GMF202", ctx["desk"], 0)
	var a1 := w.sim.check_in(2, "GMF202", ctx["desk"], 1)
	var b0 := w.sim.check_in(3, "GMF303", ctx["desk"], 2)
	for bag in [a0, a1, b0]:
		bag.state = Bag.State.IN_ROOM
		bag.cell = BagTestWorld.END
		bag.rest_tick = 50
	w.run_to(199)
	assert_array(w.sim.shuttles()).is_empty()
	# Tick 200: both enter BOARDING; GMF202 dispatches an early wave loading ONLY GMF202 bags.
	w.step()
	assert_int(w.sim.shuttles().size()).is_equal(1)
	var wave := w.sim.shuttles()[0]
	assert_str(wave.flight).is_equal("GMF202")
	assert_array(wave.pending_bag_ids).is_equal([a0.id, a1.id])
	assert_int(b0.shuttle_id).is_equal(0)

	# Wait for wave to finish and return; GMF303 wave then runs.
	w.run_to(wave.return_tick + 2)
	assert_int(a0.state).is_equal(Bag.State.LOADED)
	assert_int(a1.state).is_equal(Bag.State.LOADED)
	assert_int(w.sim.shuttles().size()).is_equal(1)
	assert_str(w.sim.shuttles()[0].flight).is_equal("GMF303")
	w.run_to(w.sim.shuttles()[0].return_tick + 1)
	assert_int(b0.state).is_equal(Bag.State.LOADED)

	# Guard test: at tick 950 (50 ticks before final_cutoff = 1000), est_return > 1000 -> holds off!
	w.run_to(950)
	var late_a := w.sim.check_in(4, "GMF202", ctx["desk"], 3)
	late_a.state = Bag.State.IN_ROOM
	late_a.cell = BagTestWorld.END
	late_a.rest_tick = 950
	w.step()
	assert_array(w.sim.shuttles()).is_empty()
	# Held until final_cutoff = 1000, then final sweep dispatches and loads before 1200!
	w.run_to(999)
	assert_array(w.sim.shuttles()).is_empty()
	w.run_to(1000)
	assert_int(w.sim.shuttles().size()).is_equal(1)
	w.run_to(w.sim.shuttles()[0].unload_tick)
	assert_int(late_a.state).is_equal(Bag.State.LOADED)

	# 1-cart AT_STAND inbound priority: when an AT_STAND flight has pending ON_PLANE
	# inbound bags, an early BOARDING wave on the same 1-cart bag room must wait.
	var grid2 := PassengerTestWorld.floored(Vector2i(20, 14))
	for y in range(0, 4):
		for x in range(0, 20):
			grid2.apply(BuildEdit.remove_floor(Vector2i(x, y)))
	for y in range(4, 14):
		grid2.apply(BuildEdit.remove_floor(Vector2i(19, y)))
	(
		assert_bool(grid2.apply(BuildEdit.place_room(Rect2i(13, 4, 4, 5), BeltShaper.BAG_ROOM)).ok)
		. is_true()
	)
	var bay2 := BuildEdit.place_object(BuildCatalog.BAY_DOOR_ID, Vector2i(14, 4), 0)
	for edit: BuildEdit in DoorPlacement.edits_for(grid2, bay2):
		assert_bool(grid2.apply(edit).ok).is_true()
	assert_int(PassengerTestWorld.place(grid2, &"baggage_cart", Vector2i(15, 5), 0)).is_greater(0)
	var desk2_id := PassengerTestWorld.place(grid2, BeltShaper.DESK, Vector2i(2, 7), 0)
	var out_plan := BeltShaper.plan_line(grid2, Vector2i(3, 6), Vector2i(13, 6), 0)
	assert_bool(out_plan.result.ok).is_true()
	for res in grid2.apply_batch(out_plan.edits):
		assert_bool(res.ok).is_true()
	(
		assert_bool(
			grid2.apply(BuildEdit.place_room(Rect2i(7, 8, 6, 4), BeltShaper.BAGGAGE_CLAIM)).ok
		)
		. is_true()
	)
	(
		assert_bool(
			grid2.apply(BuildEdit.place_object(BeltShaper.CLAIM_CAROUSEL, Vector2i(8, 9), 0)).ok
		)
		. is_true()
	)
	(
		assert_bool(grid2.apply(BuildEdit.place_object(BeltShaper.END, Vector2i(13, 8), 1)).ok)
		. is_true()
	)
	var in_cells: Array[Vector2i] = [Vector2i(10, 8), Vector2i(11, 8), Vector2i(12, 8)]
	for c in in_cells:
		var plan := BeltShaper.plan_line(grid2, c, c, 0)
		assert_bool(plan.result.ok).is_true()
		for res in grid2.apply_batch(plan.edits):
			assert_bool(res.ok).is_true()
	in_cells.append(Vector2i(13, 8))
	for res in grid2.apply_batch(BeltShaper.reshape_edits(grid2, in_cells)):
		assert_bool(res.ok).is_true()

	var clock2 := auto_free(SimClock.new()) as SimClock
	var flights2 := auto_free(FlightSim.new()) as FlightSim
	flights2.bind_clock(clock2)
	var prio_in: Array[int] = [0, 1, 2, 3, 150, 200, 260, 1260, 1320, 1440, 1740, 1940]
	var prio_out: Array[int] = [0, 1, 2, 3, 100, 150, 200, 1200, 1260, 1380, 1680, 1880]
	assert_bool(flights2.add_flight("GMF_IN", prio_in)).is_true()
	assert_bool(flights2.add_flight("GMF_OUT", prio_out)).is_true()
	var sim2 := auto_free(BaggageSim.new()) as BaggageSim
	sim2.bind(clock2, flights2, grid2)
	var pax2 := auto_free(PassengerSim.new()) as PassengerSim
	pax2.clock = clock2
	pax2.flights = flights2
	pax2.grid = grid2
	pax2.layout = TerminalLayout.new()
	pax2.layout.rebuild(grid2)
	var staff2 := auto_free(StaffSim.new()) as StaffSim
	pax2.staff = staff2
	staff2.sim = pax2
	staff2.hire(RAMP)
	var fin2 := auto_free(Finances.new()) as Finances
	fin2.clock = clock2
	fin2.start_new_game()
	var disp2 := auto_free(RampDispatch.new()) as RampDispatch
	disp2.bind(clock2, staff2, sim2, flights2, fin2, null)
	clock2.advance(SimClock.STEP)
	assert_bool(sim2.routes.has_connected_baggage_claim()).is_true()

	while clock2.tick < 200:
		clock2.advance(SimClock.STEP)
	var out_early := sim2.check_in(5, "GMF_OUT", desk2_id, 4)
	out_early.state = Bag.State.IN_ROOM
	out_early.cell = Vector2i(13, 6)
	out_early.rest_tick = clock2.tick
	var in_bag := Bag.new()
	in_bag.id = sim2._next_id
	sim2._next_id += 1
	in_bag.inbound = true
	in_bag.flight = "GMF_IN"
	in_bag.state = Bag.State.ON_PLANE
	in_bag.created_tick = clock2.tick
	in_bag.wait_tick = clock2.tick
	in_bag.cutoff_tick = 1740
	sim2._bags.append(in_bag)
	sim2._by_id[in_bag.id] = in_bag
	clock2.advance(SimClock.STEP)
	assert_int(sim2.shuttles().size()).is_equal(1)
	assert_bool(sim2.shuttles()[0].inbound).is_true()
	assert_str(sim2.shuttles()[0].flight).is_equal("GMF_IN")
	assert_int(out_early.shuttle_id).is_equal(0)


func test_inbound_transfer_in_two_bag_hand_carry_and_at_stand_priority() -> void:
	var m := _boot_main(51202)
	var clock: SimClock = m.get_node("SimClock")
	var flights: FlightSim = m.get_node("FlightSim")
	var pax: PassengerSim = m.get_node("PassengerSim")
	var bag_sim: BaggageSim = m.get_node("BaggageSim")
	var staff: StaffSim = m.get_node("Staff")
	var chars: StaffCharacters = m.get_node("StaffCharacters")
	var bviews: BaggageViews = m.get_node("BaggageViews")
	var info := _build_claim_and_outbound_in_main(m)
	var ramp_id := staff.hire(RAMP)

	# Add an extra flight whose BOARDING window starts while starter enters AT_STAND.
	var starter := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	var at_stand := flights.state_start(starter, FlightSim.State.AT_STAND)
	while clock.tick < at_stand:
		SaveTestKit.step(m)

	# Inbound shuttle should claim the 1 cart in TO_BAG_ROOM, then drive, then TRANSFER_IN.
	var saw_to_bag_room := false
	var saw_transfer_in := false
	var saw_hand_carry_in := false
	var saw_incremental_drop := false
	var ramp_node := chars.node_for(ramp_id)
	var prev_pos := ramp_node.position if ramp_node != null else Vector3.ZERO
	for _i in 900:
		SaveTestKit.step(m)
		chars.draw()
		bviews.draw()
		ramp_node = chars.node_for(ramp_id)
		if ramp_node != null and prev_pos != Vector3.ZERO:
			(
				assert_bool(
					BaggageShuttle.segment_hits_wall(pax.grid, prev_pos, ramp_node.position, false)
				)
				. is_false()
			)
		if ramp_node != null:
			prev_pos = ramp_node.position
		for s: BaggageShuttle in bag_sim.shuttles():
			if s.inbound and s.phase == BaggageShuttle.Phase.TO_BAG_ROOM:
				saw_to_bag_room = true
			elif s.inbound and s.phase == BaggageShuttle.Phase.TRANSFER_IN:
				saw_transfer_in = true
				# On first tick of TRANSFER_IN, bags are NOT all dumped to belt at once!
				if not s.carried_bag_ids.is_empty():
					saw_hand_carry_in = true
					var props := StaffHandProps.prop_nodes(
						ramp_node, StaffHandProps.PropKind.SUITCASES
					)
					assert_bool(props[0].visible).is_true()
				if not s.bag_ids.is_empty():
					saw_incremental_drop = true
		if saw_transfer_in and bag_sim.shuttles().is_empty():
			break

	assert_bool(saw_to_bag_room).is_true()
	assert_bool(saw_transfer_in).is_true()
	assert_bool(saw_hand_carry_in).is_true()
	assert_bool(saw_incremental_drop).is_true()
	assert_int(info["cart_id"]).is_greater(0)

	# Wait for all inbound bags to be claimed on the carousel.
	for _i in 1800:
		SaveTestKit.step(m)
		if bag_sim.inbound_claimed_total > 0 and bag_sim.shuttles().is_empty():
			var all_done := true
			for b in bag_sim.bags():
				if b.inbound and not b.is_settled():
					all_done = false
					break
			if all_done:
				break
	assert_int(bag_sim.inbound_claimed_total).is_greater(0)
	assert_int(bag_sim.inbound_lost_total).is_equal(0)


func test_save_v51_round_trips_mid_to_bag_room_transfer_out_and_transfer_in() -> void:
	# 1. Mid-TO_BAG_ROOM and mid-TRANSFER_OUT SaveGame v51 round-trip + v50 refusal.
	var m := _boot_main(51203)
	var clock: SimClock = m.get_node("SimClock")
	var flights: FlightSim = m.get_node("FlightSim")
	var bag_sim: BaggageSim = m.get_node("BaggageSim")
	var staff: StaffSim = m.get_node("Staff")
	var save := SaveTestKit.save_game(m)
	var info := _build_claim_and_outbound_in_main(m)
	staff.hire(RAMP)
	var starter := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	var at_stand := flights.state_start(starter, FlightSim.State.AT_STAND)
	while clock.tick < at_stand:
		SaveTestKit.step(m)
	# Wait until mid-TO_BAG_ROOM of the inbound shuttle, save & load.
	var s_entry: BaggageShuttle = null
	for _i in 50:
		if not bag_sim.shuttles().is_empty():
			s_entry = bag_sim.shuttles()[0]
			break
		SaveTestKit.step(m)
	assert_object(s_entry).is_not_null()
	assert_int(s_entry.phase).is_equal(BaggageShuttle.Phase.TO_BAG_ROOM)
	assert_bool(save.save_to_file(_save_path)).is_true()
	var raw_entry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_save_path))
	assert_int(int(raw_entry["save_version"])).is_equal(51)
	var v50 := raw_entry.duplicate(true)
	v50["save_version"] = 50
	var reject := _boot_main(51204)
	assert_bool(SaveTestKit.save_game(reject).load_world(v50)).is_false()
	var loaded_entry := _boot_main(51205)
	assert_bool(SaveTestKit.save_game(loaded_entry).load_from_file(_save_path)).is_true()
	var le_shuttle: BaggageShuttle = (
		(loaded_entry.get_node("BaggageSim") as BaggageSim).shuttles()[0]
	)
	assert_int(le_shuttle.phase).is_equal(BaggageShuttle.Phase.TO_BAG_ROOM)
	assert_int(le_shuttle.bay_door_id).is_equal(info["bay_id"])

	# Advance original world until mid-TRANSFER_IN, save & load!
	var saw_transfer_in := false
	for _i in 900:
		SaveTestKit.step(m)
		if (
			not bag_sim.shuttles().is_empty()
			and bag_sim.shuttles()[0].phase == BaggageShuttle.Phase.TRANSFER_IN
		):
			saw_transfer_in = true
			break
	assert_bool(saw_transfer_in).is_true()
	assert_bool(save.save_to_file(_save_path)).is_true()
	var loaded_in := _boot_main(51206)
	assert_bool(SaveTestKit.save_game(loaded_in).load_from_file(_save_path)).is_true()
	var li_bag: BaggageSim = loaded_in.get_node("BaggageSim")
	assert_int(li_bag.shuttles()[0].phase).is_equal(BaggageShuttle.Phase.TRANSFER_IN)
	assert_array(li_bag.shuttles()[0].carried_bag_ids).is_equal(
		bag_sim.shuttles()[0].carried_bag_ids
	)

	# Inject 3 outbound bags into bag_room and save mid-TRANSFER_OUT!
	while not bag_sim.shuttles().is_empty():
		SaveTestKit.step(m)
	var b0 := bag_sim.check_in(88001, starter, info["desk2_id"], 1)
	var b1 := bag_sim.check_in(88002, starter, info["desk2_id"], 2)
	var b2 := bag_sim.check_in(88003, starter, info["desk2_id"], 3)
	for b in [b0, b1, b2]:
		b.state = Bag.State.IN_ROOM
		b.cell = Vector2i(22, 11) + (m.get_node("PassengerSim") as PassengerSim).site.starter_offset
		b.rest_tick = clock.tick
	var saw_transfer_out := false
	for _i in 60:
		SaveTestKit.step(m)
		if (
			not bag_sim.shuttles().is_empty()
			and bag_sim.shuttles()[0].phase == BaggageShuttle.Phase.TRANSFER_OUT
		):
			saw_transfer_out = true
			break
	assert_bool(saw_transfer_out).is_true()
	assert_bool(save.save_to_file(_save_path)).is_true()
	var loaded_out := _boot_main(51207)
	assert_bool(SaveTestKit.save_game(loaded_out).load_from_file(_save_path)).is_true()
	var lo_bag: BaggageSim = loaded_out.get_node("BaggageSim")
	assert_int(lo_bag.shuttles()[0].phase).is_equal(BaggageShuttle.Phase.TRANSFER_OUT)
	assert_array(lo_bag.shuttles()[0].carried_bag_ids).is_equal(
		bag_sim.shuttles()[0].carried_bag_ids
	)
	for _i in 500:
		SaveTestKit.step(loaded_out)
		if lo_bag.loaded_total >= 3:
			break
	assert_int(lo_bag.loaded_total).is_greater_equal(3)


func test_demolishing_sole_bay_door_holds_indoor_agent_until_door_rebuilt() -> void:
	var ctx := _build_ramp_bag_world(600)
	var w: BagTestWorld = ctx["world"]
	var staff: StaffSim = ctx["staff"]
	var chars: StaffCharacters = ctx["chars"]
	var ramp_id := staff.hire(RAMP)
	var bay_doors := BaggageShuttle.valid_bay_doors_in_room(w.grid, BagTestWorld.ROOM)
	assert_int(bay_doors.size()).is_equal(1)
	var bay_id: int = bay_doors[0]["bay_door_id"]
	var bay_rec := w.grid.get_object(bay_id).duplicate(true)

	var bags: Array[Bag] = []
	for p in 6:
		bags.append(w.sim.check_in(p + 1, BagTestWorld.FLIGHT, ctx["desk"], p))
	w.run_to(bags[0].cutoff_tick - 1)
	chars.sync(true)
	chars.draw()
	var ramp_node := chars.node_for(ramp_id)
	assert_object(ramp_node).is_not_null()
	var bay_out: Vector3 = bay_doors[0]["outside_clear"]
	chars._cur[ramp_id] = bay_out
	chars._prev[ramp_id] = bay_out
	ramp_node.position = bay_out

	for _i in 30:
		w.step()
		chars.draw()
		if (
			not w.sim.shuttles().is_empty()
			and w.sim.shuttles()[0].phase == BaggageShuttle.Phase.TRANSFER_OUT
			and w.grid.is_indoor(w.grid.world_to_cell(ramp_node.position))
		):
			break
	assert_bool(w.grid.is_indoor(w.grid.world_to_cell(ramp_node.position))).is_true()
	var hold_pos: Vector3 = chars._cur[ramp_id]
	assert_bool(w.grid.is_indoor(w.grid.world_to_cell(hold_pos))).is_true()

	for edit in DoorPlacement.edits_for(w.grid, BuildEdit.remove_object(bay_id)):
		assert_bool(w.grid.apply(edit).ok).is_true()
	for _t in 4:
		w.step()
		chars.draw()
		assert_array(w.sim.shuttles()).is_empty()
		assert_bool(w.grid.is_indoor(w.grid.world_to_cell(ramp_node.position))).is_true()
		assert_float(ramp_node.position.distance_to(hold_pos)).is_less(0.05)

	var place_back := BuildEdit.place_object(
		BuildCatalog.BAY_DOOR_ID, bay_rec["anchor"], bay_rec["facing"]
	)
	for edit in DoorPlacement.edits_for(w.grid, place_back):
		assert_bool(w.grid.apply(edit).ok).is_true()

	var exited := false
	var prev_pos := ramp_node.position
	for _i in 120:
		w.step()
		chars.draw()
		(
			assert_bool(
				BaggageShuttle.segment_hits_wall(w.grid, prev_pos, ramp_node.position, false)
			)
			. is_false()
		)
		prev_pos = ramp_node.position
		if not w.grid.is_indoor(w.grid.world_to_cell(ramp_node.position)):
			exited = true
			break
	assert_bool(exited).is_true()


func test_open_apron_far_agent_approaches_smoothly_and_never_teleports_on_phase_change() -> void:
	var ctx := _build_ramp_bag_world(600)
	var w: BagTestWorld = ctx["world"]
	var staff: StaffSim = ctx["staff"]
	var chars: StaffCharacters = ctx["chars"]
	var ramp_id := staff.hire(RAMP)

	# Verify entry_path_from_apron avoids internal Bag Room partitions.
	var part_grid := BuildGrid.new(Vector2i(10, 10))
	for y in range(2, 7):
		for x in range(2, 7):
			part_grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for x in range(2, 7):
		part_grid.apply(BuildEdit.place_wall(Vector2i(x, 2), BuildGrid.Side.NORTH))
		part_grid.apply(BuildEdit.place_wall(Vector2i(x, 6), BuildGrid.Side.SOUTH))
	for y in range(2, 7):
		part_grid.apply(BuildEdit.place_wall(Vector2i(2, y), BuildGrid.Side.WEST))
		part_grid.apply(BuildEdit.place_wall(Vector2i(6, y), BuildGrid.Side.EAST))
	(
		assert_bool(
			part_grid.apply(BuildEdit.place_room(Rect2i(2, 2, 5, 5), BeltShaper.BAG_ROOM)).ok
		)
		. is_true()
	)
	var part_door_id := 0
	for edit in DoorPlacement.edits_for(
		part_grid, BuildEdit.place_object(BuildCatalog.BAY_DOOR_ID, Vector2i(3, 2), 0)
	):
		var r := part_grid.apply(edit)
		assert_bool(r.ok).is_true()
		if r.object_id > 0:
			part_door_id = r.object_id
	part_grid.apply(BuildEdit.place_wall(Vector2i(4, 3), BuildGrid.Side.NORTH))
	part_grid.apply(BuildEdit.place_wall(Vector2i(4, 3), BuildGrid.Side.WEST))
	part_grid.apply(BuildEdit.place_wall(Vector2i(4, 4), BuildGrid.Side.WEST))
	var part_dest := part_grid.cell_to_world(Vector2i(4, 4))
	var entry_pts := BaggageShuttle.entry_path_from_apron(part_grid, part_door_id, part_dest)
	assert_int(entry_pts.size()).is_greater(4)
	for i in entry_pts.size() - 1:
		(
			assert_bool(
				BaggageShuttle.segment_hits_wall(part_grid, entry_pts[i], entry_pts[i + 1], false)
			)
			. is_false()
		)

	# Place agent ~18 m north of bay_outside on open apron right before dispatch.
	var bag := w.sim.check_in(1, BagTestWorld.FLIGHT, ctx["desk"])
	w.run_to(bag.cutoff_tick - 1)
	chars.sync(true)
	chars.draw()
	var ramp_node := chars.node_for(ramp_id)
	assert_object(ramp_node).is_not_null()
	var bay_doors := BaggageShuttle.valid_bay_doors_in_room(w.grid, BagTestWorld.ROOM)
	var bay_out: Vector3 = bay_doors[0]["outside_clear"]
	var far_apron := bay_out + Vector3(20.0, 0.0, 0.0)
	chars._cur[ramp_id] = far_apron
	chars._prev[ramp_id] = far_apron
	ramp_node.position = far_apron
	var prev_pos := far_apron

	w.step()
	chars.sync(false)
	chars.draw()
	assert_int(w.sim.shuttles().size()).is_equal(1)

	var max_jump := prev_pos.distance_to(ramp_node.position)
	var steps_moved := 1 if max_jump > 0.01 else 0
	prev_pos = ramp_node.position
	for _i in 220:
		w.step()
		chars.sync(false)
		chars.draw()
		var jump := prev_pos.distance_to(ramp_node.position)
		if jump > 0.01:
			steps_moved += 1
		max_jump = maxf(max_jump, jump)
		(
			assert_bool(
				BaggageShuttle.segment_hits_wall(w.grid, prev_pos, ramp_node.position, false)
			)
			. is_false()
		)
		prev_pos = ramp_node.position
		if w.sim.shuttles().is_empty():
			break
	assert_float(max_jump).is_less(0.70)
	assert_int(steps_moved).is_greater(10)


func test_tight_avail_dispatch_saves_and_reloads_cleanly_on_every_tick() -> void:
	var ctx := _build_ramp_bag_world(600)
	var w: BagTestWorld = ctx["world"]
	var staff: StaffSim = ctx["staff"]
	staff.hire(RAMP)
	var stand := w.flights.flight_stand(BagTestWorld.FLIGHT)
	var plan := w.sim._shuttle_plan(ctx["cart_id"], BagTestWorld.FLIGHT, stand)
	assert_bool(bool(plan["ok"])).is_true()
	var travel := int(plan["travel"])
	var doors_close := w.flights.doors_close_tick(BagTestWorld.FLIGHT)
	var tight_tick := doors_close - travel - BaggageShuttle.UNLOAD_TICKS - 5
	for p in 3:
		var bag := w.sim.check_in(p + 1, BagTestWorld.FLIGHT, ctx["desk"], p)
		bag.state = Bag.State.IN_ROOM
		bag.cell = BagTestWorld.END
		bag.rest_tick = 100
		bag.cutoff_tick = tight_tick
	w.run_to(tight_tick)
	assert_int(w.sim.shuttles().size()).is_equal(1)
	var shuttle: BaggageShuttle = w.sim.shuttles()[0]
	assert_int(shuttle.transfer_start_tick - shuttle.load_start_tick).is_equal(1)
	assert_int(shuttle.start_tick - shuttle.transfer_start_tick).is_equal(3)

	for _i in 200:
		var snap: Dictionary = JSON.parse_string(JSON.stringify(w.sim.to_snapshot()))
		var clone := auto_free(BaggageSim.new()) as BaggageSim
		clone.bind(w.clock, w.flights, w.grid)
		assert_bool(clone.from_snapshot(snap)).is_true()
		w.step()
		if w.sim.shuttles().is_empty():
			break
	assert_int(w.sim.loaded_total).is_equal(3)


func test_multi_belt_end_estimate_matches_pickup_outbound_batch() -> void:
	var ctx := _build_ramp_bag_world(600)
	var w: BagTestWorld = ctx["world"]
	var staff: StaffSim = ctx["staff"]
	staff.hire(RAMP)
	var second_end := Vector2i(10, 8)
	assert_bool(w.grid.apply(BuildEdit.place_object(BeltShaper.END, second_end, 0)).ok).is_true()
	var b0 := w.sim.check_in(1, BagTestWorld.FLIGHT, ctx["desk"], 0)
	var b1 := w.sim.check_in(2, BagTestWorld.FLIGHT, ctx["desk"], 1)
	var b2 := w.sim.check_in(3, BagTestWorld.FLIGHT, ctx["desk"], 2)
	b0.state = Bag.State.IN_ROOM
	b0.cell = BagTestWorld.END
	b0.rest_tick = 10
	b1.state = Bag.State.IN_ROOM
	b1.cell = second_end
	b1.rest_tick = 11
	b2.state = Bag.State.IN_ROOM
	b2.cell = BagTestWorld.END
	b2.rest_tick = 12
	assert_int(w.sim._trip_count_for_group([b0, b1, b2])).is_equal(2)

	w.run_to(b0.cutoff_tick)
	assert_int(w.sim.shuttles().size()).is_equal(1)
	var s := w.sim.shuttles()[0]
	var batches: Array = []
	var prev_carried: Array[int] = []
	for _i in 30:
		if not s.carried_bag_ids.is_empty() and s.carried_bag_ids != prev_carried:
			batches.append(s.carried_bag_ids.duplicate())
		prev_carried = s.carried_bag_ids.duplicate()
		if s.phase == BaggageShuttle.Phase.OUTBOUND:
			break
		w.step()
	assert_int(batches.size()).is_equal(2)
	assert_array(batches[0]).is_equal([b0.id, b2.id])
	assert_array(batches[1]).is_equal([b1.id])
