class_name TestCheckedBagContinuity
extends GdUnitTestSuite
## Acceptance tests for checked bag continuity (decision
## checked-bag-continuity-passenger-handoff-no-cart-teleport-and-visible-cart-loading):
## 1) Passengers carry a deterministic colored checked suitcase pre-checkin,
##    hand it off onto the belt with the same color, and missed/retired
##    passengers clean it up cleanly.
## 2) Bag rooms without a placed baggage_cart do not teleport bags at cutoff;
##    adding a cart enables shuttle loading and dispatch.
## 3) Waiting belt-end bags load onto the cart visibly one-by-one across ticks
##    before the shuttle departs, preserving each bag's color on the cart.
## 4) Mid-load snapshots round-trip colors and loading progress, and previous
##    save versions are rejected cleanly.


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func _bag_swatch_color(node: Node3D) -> Color:
	var mesh_instance: MeshInstance3D = null
	if node is MeshInstance3D:
		mesh_instance = node as MeshInstance3D
	else:
		mesh_instance = node.find_child("BaggageBag_Body", true, false) as MeshInstance3D
	assert_object(mesh_instance).is_not_null()
	var mat := mesh_instance.get_active_material(0) as ShaderMaterial
	assert_object(mat).is_not_null()
	var tex := mat.get_shader_parameter("albedo_texture") as Texture2D
	assert_object(tex).is_not_null()
	var img: Image = tex.get_image()
	assert_object(img).is_not_null()
	var cell_w := maxi(1, int(img.get_width() / 32.0))
	return img.get_pixel(31 * cell_w + 1, 1)


func test_passenger_checked_suitcase_color_handoff_to_belt_and_views() -> void:
	var pw := PassengerTestWorld.reference_world(7)
	BagRoomKit.connect_reference_desk2(pw.grid)
	var bags: BaggageSim = auto_free(BaggageSim.new())
	bags.bind(pw.clock, pw.flights, pw.grid, pw.sim)
	var pviews := PassengerTestWorld.views()
	pviews.clock = pw.clock
	pviews.sim = pw.sim
	add_child(pviews)
	var bviews: BaggageViews = auto_free(BaggageViews.new())
	bviews.clock = pw.clock
	bviews.sim = bags
	add_child(bviews)

	var seen_colors := {}
	var checked_colors := {}
	var pids: Array[int] = []
	for i in 12:
		pids.append(pw.sim.spawn_now(PassengerTestWorld.FLIGHT, 0))
	pw.step()

	for pid in pids:
		var p := pw.passenger(pid)
		assert_object(p).is_not_null()
		seen_colors[p.checked_bag_color] = true
		var p_bag: Node3D = pviews.checked_bag_node_for(pid)
		assert_object(p_bag).is_not_null()
		assert_bool(p_bag.visible).is_true()
		(
			assert_bool(
				_bag_swatch_color(p_bag).is_equal_approx(Bag.suitcase_color(p.checked_bag_color))
			)
			. is_true()
		)
		checked_colors[pid] = p.checked_bag_color
	assert_int(seen_colors.size()).is_greater(1)

	var handed_off := {}
	var belt_views_verified := {}
	for _step in 500:
		pw.step()
		for bag in bags.bags():
			if not handed_off.has(bag.passenger):
				handed_off[bag.passenger] = bag
				var expected_color: int = checked_colors[bag.passenger]
				assert_int(bag.color).is_equal(expected_color)
				assert_object(pviews.checked_bag_node_for(bag.passenger)).is_null()
			if not belt_views_verified.has(bag.id):
				if bag.state == Bag.State.RIDING or bag.state == Bag.State.IN_ROOM:
					var b_node: Node3D = bviews.node_for(bag.id)
					assert_object(b_node).is_not_null()
					(
						assert_bool(
							_bag_swatch_color(b_node).is_equal_approx(Bag.suitcase_color(bag.color))
						)
						. is_true()
					)
					belt_views_verified[bag.id] = true
		if belt_views_verified.size() >= 3 and handed_off.size() >= 6:
			break
	assert_int(handed_off.size()).is_greater_equal(6)
	assert_int(belt_views_verified.size()).is_greater_equal(2)
	pviews.free()
	pw.free_all()


func test_missed_unchecked_passenger_keeps_suitcase_until_retired() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(10, 10))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 8), 3)
	var desk_id := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(2, 6), 0)
	var cells: Array[Vector2i] = []
	for port in BuildCatalog.belt_ports(&"checkin_desk", Vector2i(2, 6), 0):
		cells.append(port["cell"] + port["side"])
	grid.apply_batch(BeltShaper.reshape_edits(grid, cells))
	BagRoomKit.add(grid, Rect2i(2, 2, 3, 3))
	var plan := BeltShaper.plan_line(grid, Vector2i(3, 5), Vector2i(2, 2), 0)
	assert_bool(plan.result.ok).is_true()
	for r in grid.apply_batch(plan.edits):
		assert_bool(r.ok).is_true()
	assert_int(desk_id).is_greater(0)

	var pw := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(20, 30), 3)
	var pviews := PassengerTestWorld.views()
	pviews.clock = pw.clock
	pviews.sim = pw.sim
	add_child(pviews)

	var pid := pw.sim.spawn_now(PassengerTestWorld.FLIGHT, 0)
	pw.step()
	assert_object(pviews.checked_bag_node_for(pid)).is_not_null()
	pw.run_to(35)
	var p := pw.passenger(pid)
	assert_object(p).is_not_null()
	assert_int(p.stage).is_equal(Passenger.Stage.MISSED)
	assert_object(pviews.checked_bag_node_for(pid)).is_not_null()
	pw.run_to(30 + PassengerViews.MISSED_LINGER_TICKS + 2)
	assert_object(pw.passenger(pid)).is_null()
	assert_object(pviews.checked_bag_node_for(pid)).is_null()
	var bags_view := pviews.get("_checked_bags") as CheckedSuitcaseViews
	assert_int(bags_view.active_count()).is_equal(0)
	pviews.free()
	pw.free_all()


func test_no_cart_teleport_stays_waiting_and_adding_cart_enables_dispatch() -> void:
	var w := BagTestWorld.make(self, 600)
	var desk := w.line()
	var room_id := w.grid.room_at(BagTestWorld.END)
	assert_bool(RoomRules.bag_room_dispatch_ready(w.grid, room_id)).is_false()

	var bag := w.sim.check_in(1, BagTestWorld.FLIGHT, desk, 3)
	w.run_to(BagTestWorld.ARRIVAL)
	assert_int(bag.state).is_equal(Bag.State.IN_ROOM)

	w.run_to(bag.cutoff_tick + 20)
	assert_int(bag.state).is_equal(Bag.State.IN_ROOM)
	assert_int(bag.shuttle_id).is_equal(0)
	assert_array(w.sim.shuttles()).is_empty()
	assert_int(w.sim.loaded_total).is_equal(0)

	PassengerTestWorld.place(w.grid, &"baggage_cart", Vector2i(11, 7), 0)
	assert_bool(RoomRules.bag_room_dispatch_ready(w.grid, room_id)).is_true()
	w.step()
	assert_int(w.sim.shuttles().size()).is_equal(1)
	var shuttle := w.sim.shuttles()[0]
	w.run_to(shuttle.unload_tick)
	assert_int(bag.state).is_equal(Bag.State.LOADED)
	assert_int(w.sim.loaded_total).is_equal(1)


func test_no_cart_before_doors_close_misses_bag_late() -> void:
	var w := BagTestWorld.make(self, 600)
	var desk := w.line()
	var bag := w.sim.check_in(1, BagTestWorld.FLIGHT, desk, 1)
	w.run_to(bag.cutoff_tick + 50)
	assert_int(bag.state).is_equal(Bag.State.IN_ROOM)
	w.run_to(600)
	assert_int(bag.state).is_equal(Bag.State.MISSED)
	assert_int(bag.cause).is_equal(Bag.Cause.LATE)
	assert_int(w.sim.loaded_total).is_equal(0)
	assert_int(w.sim.missed_total).is_equal(1)


func test_one_by_one_visible_cart_loading_preserves_colors_across_ticks() -> void:
	var w := BagTestWorld.make(self, 600)
	var desk := w.line()
	PassengerTestWorld.place(w.grid, &"baggage_cart", Vector2i(11, 7), 0)
	var views: BaggageViews = auto_free(BaggageViews.new())
	views.clock = w.clock
	views.sim = w.sim
	add_child(views)

	var b0 := w.sim.check_in(1, BagTestWorld.FLIGHT, desk, 0)
	var b1 := w.sim.check_in(2, BagTestWorld.FLIGHT, desk, 2)
	var b2 := w.sim.check_in(3, BagTestWorld.FLIGHT, desk, 4)
	w.run_to(250)
	for bag in [b0, b1, b2]:
		assert_int(bag.state).is_equal(Bag.State.IN_ROOM)
	assert_int(views.active_count()).is_equal(3)

	w.run_to(b0.cutoff_tick)
	assert_int(w.sim.shuttles().size()).is_equal(1)
	var shuttle := w.sim.shuttles()[0]
	assert_int(shuttle.phase).is_equal(BaggageShuttle.Phase.LOADING)
	assert_int(shuttle.bag_ids.size()).is_equal(1)
	assert_int(shuttle.pending_bag_ids.size()).is_equal(2)
	assert_int(views.shuttle_bag_count(shuttle.id)).is_equal(1)
	assert_int(views.active_count()).is_equal(2)

	w.run_to(b0.cutoff_tick + shuttle.load_step_ticks)
	assert_int(shuttle.phase).is_equal(BaggageShuttle.Phase.LOADING)
	assert_int(shuttle.bag_ids.size()).is_equal(2)
	assert_int(shuttle.pending_bag_ids.size()).is_equal(1)
	assert_int(views.shuttle_bag_count(shuttle.id)).is_equal(2)
	assert_int(views.active_count()).is_equal(1)

	w.run_to(b0.cutoff_tick + shuttle.load_step_ticks * 2)
	assert_int(shuttle.bag_ids.size()).is_equal(3)
	assert_int(shuttle.pending_bag_ids.size()).is_equal(0)
	assert_int(views.shuttle_bag_count(shuttle.id)).is_equal(3)
	assert_int(views.active_count()).is_equal(0)

	var cart_nodes: Array[Node3D] = views.shuttle_bag_nodes(shuttle.id)
	assert_int(cart_nodes.size()).is_equal(3)
	assert_bool(_bag_swatch_color(cart_nodes[0]).is_equal_approx(Bag.suitcase_color(0))).is_true()
	assert_bool(_bag_swatch_color(cart_nodes[1]).is_equal_approx(Bag.suitcase_color(2))).is_true()
	assert_bool(_bag_swatch_color(cart_nodes[2]).is_equal_approx(Bag.suitcase_color(4))).is_true()

	w.run_to(shuttle.start_tick)
	assert_int(shuttle.phase).is_equal(BaggageShuttle.Phase.OUTBOUND)
	w.run_to(shuttle.unload_tick)
	assert_int(w.sim.loaded_total).is_equal(3)
	assert_int(shuttle.phase).is_equal(BaggageShuttle.Phase.RETURNING)
	assert_int(views.shuttle_bag_count(shuttle.id)).is_equal(0)


func test_mid_load_snapshot_round_trip_and_rejects_previous_save_version() -> void:
	var ctrl := BagTestWorld.make(self, 600)
	var desk := ctrl.line()
	PassengerTestWorld.place(ctrl.grid, &"baggage_cart", Vector2i(11, 7), 0)
	var c0 := ctrl.sim.check_in(1, BagTestWorld.FLIGHT, desk, 1)
	var c1 := ctrl.sim.check_in(2, BagTestWorld.FLIGHT, desk, 3)
	var c2 := ctrl.sim.check_in(3, BagTestWorld.FLIGHT, desk, 5)
	ctrl.run_to(c0.cutoff_tick)
	var shuttle := ctrl.sim.shuttles()[0]
	ctrl.run_to(shuttle.load_start_tick + shuttle.load_step_ticks)
	assert_int(shuttle.phase).is_equal(BaggageShuttle.Phase.LOADING)
	assert_int(shuttle.bag_ids.size()).is_equal(2)
	assert_int(shuttle.pending_bag_ids.size()).is_equal(1)

	var snap: Dictionary = JSON.parse_string(JSON.stringify(ctrl.sim.to_snapshot()))
	assert_int(int(snap["save_version"])).is_equal(BaggageSnapshot.SAVE_VERSION)

	var old_snap := snap.duplicate(true)
	old_snap["save_version"] = BaggageSnapshot.SAVE_VERSION - 1
	assert_bool(BaggageSnapshot.load(old_snap).has("error")).is_true()

	var loaded := BagTestWorld.make(self, 600)
	loaded.line()
	PassengerTestWorld.place(loaded.grid, &"baggage_cart", Vector2i(11, 7), 0)
	loaded.run_to(ctrl.clock.tick)
	assert_bool(loaded.sim.from_snapshot(snap)).is_true()

	var l_views: BaggageViews = auto_free(BaggageViews.new())
	l_views.clock = loaded.clock
	l_views.sim = loaded.sim
	add_child(l_views)
	l_views.snap()

	assert_int(loaded.sim.shuttles().size()).is_equal(1)
	var ls := loaded.sim.shuttles()[0]
	assert_int(ls.phase).is_equal(BaggageShuttle.Phase.LOADING)
	assert_int(ls.bag_ids.size()).is_equal(2)
	assert_int(ls.pending_bag_ids.size()).is_equal(1)
	assert_int(l_views.shuttle_bag_count(ls.id)).is_equal(2)
	assert_int(loaded.sim.get_bag(c0.id).color).is_equal(1)
	assert_int(loaded.sim.get_bag(c1.id).color).is_equal(3)
	assert_int(loaded.sim.get_bag(c2.id).color).is_equal(5)
	var l_nodes: Array[Node3D] = l_views.shuttle_bag_nodes(ls.id)
	assert_bool(_bag_swatch_color(l_nodes[0]).is_equal_approx(Bag.suitcase_color(1))).is_true()
	assert_bool(_bag_swatch_color(l_nodes[1]).is_equal_approx(Bag.suitcase_color(3))).is_true()

	while not ctrl.sim.shuttles().is_empty():
		ctrl.step()
		loaded.step()
	assert_int(loaded.sim.loaded_total).is_equal(ctrl.sim.loaded_total)
	assert_int(loaded.sim.loaded_total).is_equal(3)


func test_malformed_loading_snapshot_and_cross_flight_bags_are_refused() -> void:
	var w := BagTestWorld.make(self, 600)
	var desk := w.line()
	PassengerTestWorld.place(w.grid, &"baggage_cart", Vector2i(11, 7), 0)
	assert_bool(w.flights.add_flight("GMF202", PassengerTestWorld.starts_with(550, 650))).is_true()
	var b0 := w.sim.check_in(1, BagTestWorld.FLIGHT, desk, 0)
	w.sim.check_in(2, BagTestWorld.FLIGHT, desk, 1)
	w.sim.check_in(3, BagTestWorld.FLIGHT, desk, 2)
	var xbag := w.sim.check_in(4, "GMF202", desk, 3)
	w.run_to(b0.cutoff_tick)
	assert_int(w.sim.shuttles().size()).is_equal(1)
	var shuttle := w.sim.shuttles()[0]
	assert_int(shuttle.phase).is_equal(BaggageShuttle.Phase.LOADING)
	assert_int(shuttle.bag_ids.size()).is_equal(1)
	assert_int(shuttle.pending_bag_ids.size()).is_equal(2)

	var base: Dictionary = JSON.parse_string(JSON.stringify(w.sim.to_snapshot()))

	var zero_step := base.duplicate(true)
	zero_step["shuttles"][0]["load_step_ticks"] = 0
	assert_bool(BaggageSnapshot.load(zero_step).has("error")).is_true()

	var over_step := base.duplicate(true)
	over_step["shuttles"][0]["load_step_ticks"] = BaggageShuttle.LOAD_STEP_TICKS + 1
	assert_bool(BaggageSnapshot.load(over_step).has("error")).is_true()

	var stale_next := base.duplicate(true)
	stale_next["shuttles"][0]["next_load_tick"] = int(base["tick"])
	assert_bool(BaggageSnapshot.load(stale_next).has("error")).is_true()

	var late_next := base.duplicate(true)
	late_next["shuttles"][0]["next_load_tick"] = int(base["shuttles"][0]["start_tick"]) + 1
	assert_bool(BaggageSnapshot.load(late_next).has("error")).is_true()

	var misaligned_next := base.duplicate(true)
	misaligned_next["shuttles"][0]["next_load_tick"] = (
		int(base["shuttles"][0]["next_load_tick"]) + 1
	)
	assert_bool(BaggageSnapshot.load(misaligned_next).has("error")).is_true()

	var mismatched_counts := base.duplicate(true)
	var moved_id: int = mismatched_counts["shuttles"][0]["pending_bag_ids"].pop_front()
	mismatched_counts["shuttles"][0]["bag_ids"].append(moved_id)
	for entry: Dictionary in mismatched_counts["bags"]:
		if int(entry["id"]) == moved_id:
			entry["shuttle_id"] = shuttle.id
	assert_bool(BaggageSnapshot.load(mismatched_counts).has("error")).is_true()

	var dup_bag := base.duplicate(true)
	dup_bag["shuttles"][0]["pending_bag_ids"][0] = int(dup_bag["shuttles"][0]["bag_ids"][0])
	assert_bool(BaggageSnapshot.load(dup_bag).has("error")).is_true()

	var cross_pending := base.duplicate(true)
	cross_pending["shuttles"][0]["pending_bag_ids"][0] = xbag.id
	assert_bool(BaggageSnapshot.load(cross_pending).has("error")).is_true()

	var cross_loaded := base.duplicate(true)
	var orig_id: int = cross_loaded["shuttles"][0]["bag_ids"][0]
	cross_loaded["shuttles"][0]["bag_ids"][0] = xbag.id
	for entry: Dictionary in cross_loaded["bags"]:
		if int(entry["id"]) == orig_id:
			entry["shuttle_id"] = 0
		elif int(entry["id"]) == xbag.id:
			entry["shuttle_id"] = shuttle.id
	assert_bool(BaggageSnapshot.load(cross_loaded).has("error")).is_true()


func test_mid_loading_cart_room_and_belt_end_removals() -> void:
	# Case A: removing cart mid-LOADING loses carried bag_ids and keeps pending IN_ROOM.
	var wa := BagTestWorld.make(self, 600)
	var desk_a := wa.line()
	var cart_a := wa.cart()
	var a0 := wa.sim.check_in(1, BagTestWorld.FLIGHT, desk_a, 0)
	var a1 := wa.sim.check_in(2, BagTestWorld.FLIGHT, desk_a, 1)
	var a2 := wa.sim.check_in(3, BagTestWorld.FLIGHT, desk_a, 2)
	wa.run_to(a0.cutoff_tick)
	assert_int(wa.sim.shuttles()[0].bag_ids.size()).is_equal(1)
	assert_int(wa.sim.shuttles()[0].pending_bag_ids.size()).is_equal(2)
	assert_bool(wa.grid.apply(BuildEdit.remove_object(cart_a)).ok).is_true()
	wa.step()
	assert_array(wa.sim.shuttles()).is_empty()
	assert_int(a0.state).is_equal(Bag.State.MISSED)
	assert_int(a0.cause).is_equal(Bag.Cause.LOST)
	assert_int(a1.state).is_equal(Bag.State.IN_ROOM)
	assert_int(a2.state).is_equal(Bag.State.IN_ROOM)
	assert_int(a1.shuttle_id).is_equal(0)
	assert_int(a2.shuttle_id).is_equal(0)

	# Case B: removing bag_room mid-LOADING drops pending bags LOST and delivers loaded bag.
	var wb := BagTestWorld.make(self, 600)
	var desk_b := wb.line()
	wb.cart()
	var b0 := wb.sim.check_in(1, BagTestWorld.FLIGHT, desk_b, 0)
	var b1 := wb.sim.check_in(2, BagTestWorld.FLIGHT, desk_b, 1)
	var b2 := wb.sim.check_in(3, BagTestWorld.FLIGHT, desk_b, 2)
	wb.run_to(b0.cutoff_tick)
	var sb := wb.sim.shuttles()[0]
	var room_id := wb.grid.room_at(BagTestWorld.END)
	assert_bool(wb.grid.apply(BuildEdit.remove_room(room_id)).ok).is_true()
	wb.step()
	assert_int(b1.state).is_equal(Bag.State.MISSED)
	assert_int(b1.cause).is_equal(Bag.Cause.LOST)
	assert_int(b2.state).is_equal(Bag.State.MISSED)
	assert_array(sb.pending_bag_ids).is_empty()
	wb.run_to(sb.unload_tick)
	assert_int(b0.state).is_equal(Bag.State.LOADED)

	# Case C: removing belt end mid-LOADING drops pending bags LOST and delivers loaded bag.
	var wc := BagTestWorld.make(self, 600)
	var desk_c := wc.line()
	wc.cart()
	var c0 := wc.sim.check_in(1, BagTestWorld.FLIGHT, desk_c, 0)
	var c1 := wc.sim.check_in(2, BagTestWorld.FLIGHT, desk_c, 1)
	var c2 := wc.sim.check_in(3, BagTestWorld.FLIGHT, desk_c, 2)
	wc.run_to(c0.cutoff_tick)
	var sc := wc.sim.shuttles()[0]
	wc.unlay(BagTestWorld.END)
	wc.step()
	assert_int(c1.state).is_equal(Bag.State.MISSED)
	assert_int(c1.cause).is_equal(Bag.Cause.LOST)
	assert_int(c2.state).is_equal(Bag.State.MISSED)
	assert_array(sc.pending_bag_ids).is_empty()
	wc.run_to(sc.unload_tick)
	assert_int(c0.state).is_equal(Bag.State.LOADED)


func test_boundary_straddling_cart_is_rejected_by_both_room_rules_and_sim() -> void:
	var w := BagTestWorld.make(self, 600)
	var desk := w.line()
	var room_id := w.grid.room_at(BagTestWorld.END)
	# Room is Rect2i(10, 6, 3, 3); facing 0 cart at (11, 8) puts (11, 9) outside the room.
	w.cart(Vector2i(11, 8), 0)
	assert_bool(RoomRules.status(w.grid, room_id).ok).is_true()
	assert_bool(RoomRules.bag_room_dispatch_ready(w.grid, room_id)).is_false()
	var bag := w.sim.check_in(1, BagTestWorld.FLIGHT, desk, 2)
	w.run_to(bag.cutoff_tick + 10)
	assert_array(w.sim.shuttles()).is_empty()
	assert_int(bag.state).is_equal(Bag.State.IN_ROOM)
	w.run_to(600)
	assert_int(bag.state).is_equal(Bag.State.MISSED)
	assert_int(bag.cause).is_equal(Bag.Cause.LATE)


func test_checked_suitcase_views_no_room_already_checked_and_pool_reuse() -> void:
	var pw := PassengerTestWorld.reference_world(9)
	var pviews := PassengerTestWorld.views()
	pviews.clock = pw.clock
	pviews.sim = pw.sim
	add_child(pviews)

	var p1 := pw.sim.spawn_now(PassengerTestWorld.FLIGHT, 0)
	pw.step()
	assert_object(pviews.checked_bag_node_for(p1)).is_null()

	BagRoomKit.connect_reference_desk2(pw.grid)
	var bags: BaggageSim = auto_free(BaggageSim.new())
	bags.bind(pw.clock, pw.flights, pw.grid, pw.sim)
	pw.step()
	var node_a := pviews.checked_bag_node_for(p1)
	assert_object(node_a).is_not_null()
	assert_bool(node_a.visible).is_true()

	for _t in 400:
		pw.step()
		if not PassengerBags.BEFORE_DROP.has(pw.passenger(p1).stage):
			break
	assert_bool(PassengerBags.BEFORE_DROP.has(pw.passenger(p1).stage)).is_false()
	assert_object(pviews.checked_bag_node_for(p1)).is_null()
	assert_bool(node_a.visible).is_false()

	var p2 := pw.sim.spawn_now(PassengerTestWorld.FLIGHT, 0)
	pw.step()
	var node_b := pviews.checked_bag_node_for(p2)
	assert_object(node_b).is_same(node_a)
	assert_bool(node_b.visible).is_true()
	(
		assert_bool(
			_bag_swatch_color(node_b).is_equal_approx(
				Bag.suitcase_color(pw.passenger(p2).checked_bag_color)
			)
		)
		. is_true()
	)
	pviews.free()
	pw.free_all()


func test_suitcase_material_regenerates_lower_mipmap_levels() -> void:
	var bag_node := BaggageViews.BAG_SCENE.instantiate() as Node3D
	add_child(bag_node)
	var mi := bag_node.find_child("BaggageBag_Body", true, false) as MeshInstance3D
	assert_object(mi).is_not_null()
	for idx in [1, 3]:
		var mat := Bag.suitcase_material(mi, idx) as ShaderMaterial
		assert_object(mat).is_not_null()
		var tex := mat.get_shader_parameter("albedo_texture") as Texture2D
		assert_object(tex).is_not_null()
		var atlas: Image = tex.get_image()
		assert_object(atlas).is_not_null()
		assert_bool(atlas.has_mipmaps()).is_true()
		assert_int(atlas.get_mipmap_count()).is_greater_equal(2)
		var data := atlas.get_data()
		for level in [1, 2]:
			var mw := maxi(1, atlas.get_width() >> level)
			var mh := maxi(1, atlas.get_height() >> level)
			var start := atlas.get_mipmap_offset(level)
			var end := (
				atlas.get_mipmap_offset(level + 1)
				if level + 1 <= atlas.get_mipmap_count()
				else data.size()
			)
			var mip := Image.create_from_data(
				mw, mh, false, atlas.get_format(), data.slice(start, end)
			)
			var cell_w := maxi(1, int(mw / 32.0))
			var px := mip.get_pixel(31 * cell_w + 1, 1)
			assert_bool(px.is_equal_approx(Bag.suitcase_color(idx))).is_true()
	bag_node.free()
