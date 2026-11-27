class_name TestBaggageShuttle
extends GdUnitTestSuite
## Functional baggage_cart shuttle during LOAD_LEAD_TICKS (decision
## baggage-loop-completion-connect-gated-penalties-visible-wait): a placed
## baggage_cart dispatches an animated shuttle out to the parked plane's stand
## during LOAD_LEAD_TICKS carrying IN_ROOM bags before settling them LOADED;
## without a cart, IN_ROOM bags stay waiting until doors close and miss LATE.
## Also checks BaggageViews
## cart rendering, mid-shuttle snapshot round-trips, cart removal mid-trip,
## and the Tier-2 Ramp Agent hooks (shuttle_can_dispatch / assign_shuttle_driver).

const CART_CELL := Vector2i(11, 7)

var _world: BagTestWorld
var _views: BaggageViews
var _desk := 0


func before_test() -> void:
	_world = BagTestWorld.make(self, 600)
	_desk = _world.line()
	_views = auto_free(BaggageViews.new())
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)


func _place_cart(cell := CART_CELL) -> int:
	return PassengerTestWorld.place(_world.grid, &"baggage_cart", cell, 0)


func test_cart_shuttle_animates_out_to_stand_during_load_lead_and_settles_loaded() -> void:
	var cart_id := _place_cart()
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)
	var dispatched := []
	var arrived := []
	var returned := []
	_world.sim.shuttle_dispatched.connect(
		func(sid: int, fid: String, cid: int) -> void: dispatched.append([sid, fid, cid])
	)
	_world.sim.shuttle_arrived.connect(
		func(sid: int, fid: String) -> void: arrived.append([sid, fid])
	)
	_world.sim.shuttle_returned.connect(
		func(sid: int, cid: int) -> void: returned.append([sid, cid])
	)
	_world.run_to(BagTestWorld.ARRIVAL)
	assert_int(bag.state).is_equal(Bag.State.IN_ROOM)
	assert_array(_world.sim.shuttles()).is_empty()
	# Cutoff is doors (600) - LOAD_LEAD_TICKS (200) = 400.
	_world.run_to(bag.cutoff_tick)
	assert_array(dispatched).is_equal([[1, BagTestWorld.FLIGHT, cart_id]])
	assert_int(_world.sim.shuttles().size()).is_equal(1)
	var shuttle := _world.sim.shuttles()[0]
	assert_int(shuttle.phase).is_equal(BaggageShuttle.Phase.LOADING)
	assert_int(bag.shuttle_id).is_equal(shuttle.id)
	assert_int(bag.state).is_equal(Bag.State.IN_ROOM)
	assert_bool(shuttle.carrying_bags()).is_true()
	assert_int(shuttle.unload_tick).is_less(_world.flights.doors_close_tick(BagTestWorld.FLIGHT))
	# Bag leaves the end stack once loaded onto the cart; cart node appears with Cart_Bags visible.
	assert_object(_views.node_for(bag.id)).is_null()
	var cart_node := _views.shuttle_node_for(shuttle.id)
	assert_object(cart_node).is_not_null()
	var cart_bags := cart_node.find_child(BaggageViews.CART_BAGS_NODE, true, false) as Node3D
	assert_object(cart_bags).is_not_null()
	assert_bool(cart_bags.visible).is_true()
	_world.run_to(shuttle.start_tick)
	assert_int(shuttle.phase).is_equal(BaggageShuttle.Phase.OUTBOUND)
	# Mid-outbound: cart moves smoothly toward the plane stand cargo point.
	var mid_tick := int((shuttle.start_tick + shuttle.arrive_tick) / 2.0)
	_world.run_to(mid_tick)
	_views.draw()
	var mid_dist := cart_node.transform.origin.distance_to(shuttle.target_world)
	var start_dist := shuttle.origin_world.distance_to(shuttle.target_world)
	assert_float(mid_dist).is_less(start_dist * 0.75)
	assert_float(mid_dist).is_greater(start_dist * 0.25)
	# Arrives at plane, unloads, settles LOADED before doors close, and hides Cart_Bags on return.
	_world.run_to(shuttle.arrive_tick)
	assert_array(arrived).is_equal([[shuttle.id, BagTestWorld.FLIGHT]])
	assert_int(shuttle.phase).is_equal(BaggageShuttle.Phase.UNLOADING)
	_world.run_to(shuttle.unload_tick)
	assert_int(bag.state).is_equal(Bag.State.LOADED)
	assert_int(_world.sim.loaded_total).is_equal(1)
	assert_int(shuttle.phase).is_equal(BaggageShuttle.Phase.RETURNING)
	assert_bool(shuttle.carrying_bags()).is_false()
	assert_bool(cart_bags.visible).is_false()
	# Returns to bag room and clears active shuttle.
	_world.run_to(shuttle.return_tick)
	assert_array(returned).is_equal([[shuttle.id, cart_id]])
	assert_array(_world.sim.shuttles()).is_empty()
	assert_int(_views.active_shuttle_count()).is_equal(0)


func test_without_a_cart_cutoff_does_not_teleport_and_misses_at_doors_close() -> void:
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)
	_world.run_to(bag.cutoff_tick)
	assert_array(_world.sim.shuttles()).is_empty()
	assert_int(bag.state).is_equal(Bag.State.IN_ROOM)
	assert_int(bag.outcome_tick).is_equal(-1)
	_world.run_to(600)
	assert_int(bag.state).is_equal(Bag.State.MISSED)
	assert_int(bag.cause).is_equal(Bag.Cause.LATE)


func test_mid_shuttle_snapshot_round_trips_and_plays_like_control() -> void:
	_place_cart()
	var control := BagTestWorld.make(self, 600)
	var control_desk := control.line()
	PassengerTestWorld.place(control.grid, &"baggage_cart", CART_CELL, 0)
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)
	var c_bag := control.sim.check_in(1, BagTestWorld.FLIGHT, control_desk)
	_world.run_to(410)
	control.run_to(410)
	assert_int(_world.sim.shuttles().size()).is_equal(1)
	var ctrl_shuttle := control.sim.shuttles()[0]
	assert_bool(control.sim.assign_shuttle_driver(ctrl_shuttle.id, 77)).is_true()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(control.sim.to_snapshot()))
	assert_int(int(saved["save_version"])).is_equal(BaggageSnapshot.SAVE_VERSION)
	assert_bool(_world.sim.from_snapshot(saved)).is_true()
	assert_int(_world.sim.shuttles().size()).is_equal(1)
	var loaded_shuttle := _world.sim.shuttles()[0]
	var loaded_bag := _world.sim.get_bag(c_bag.id)
	assert_int(loaded_shuttle.phase).is_equal(ctrl_shuttle.phase)
	assert_array(loaded_shuttle.bag_ids).is_equal(ctrl_shuttle.bag_ids)
	assert_int(loaded_shuttle.waypoints.size()).is_equal(ctrl_shuttle.waypoints.size())
	for i in ctrl_shuttle.waypoints.size():
		assert_vector(loaded_shuttle.waypoints[i]).is_equal_approx(
			ctrl_shuttle.waypoints[i], Vector3.ONE * 0.001
		)
	assert_int(loaded_shuttle.driver_staff_id).is_equal(77)
	assert_int(loaded_bag.shuttle_id).is_equal(loaded_shuttle.id)
	assert_str(_world.signature()).is_equal(control.signature())
	_world.run_to(650)
	control.run_to(650)
	assert_str(_world.signature()).is_equal(control.signature())
	assert_array(_world.settled).is_equal(control.settled)
	assert_int(_world.sim.loaded_total).is_equal(1)
	assert_int(bag.id).is_equal(c_bag.id)


func test_removing_cart_mid_outbound_loses_its_carried_bags() -> void:
	var cart_id := _place_cart()
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)
	_world.run_to(bag.cutoff_tick + 5)
	assert_int(_world.sim.shuttles().size()).is_equal(1)
	assert_bool(_world.grid.apply(BuildEdit.remove_object(cart_id)).ok).is_true()
	_world.step()
	assert_array(_world.sim.shuttles()).is_empty()
	assert_int(bag.state).is_equal(Bag.State.MISSED)
	assert_int(bag.cause).is_equal(Bag.Cause.LOST)
	assert_int(_world.settled.size()).is_equal(1)


func test_ramp_agent_hook_gates_dispatch_and_records_driver() -> void:
	var cart_id := _place_cart()
	var allow := [false]
	_world.sim.shuttle_can_dispatch = func(_cid: int, _fid: String) -> bool: return allow[0]
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)
	_world.run_to(bag.cutoff_tick + 10)
	assert_array(_world.sim.shuttles()).is_empty()
	assert_int(bag.state).is_equal(Bag.State.IN_ROOM)
	allow[0] = true
	_world.step()
	assert_int(_world.sim.shuttles().size()).is_equal(1)
	var shuttle := _world.sim.shuttles()[0]
	assert_int(shuttle.cart_id).is_equal(cart_id)
	assert_bool(_world.sim.assign_shuttle_driver(shuttle.id, 42)).is_true()
	assert_int(shuttle.driver_staff_id).is_equal(42)


func test_permanently_denied_shuttle_hook_settles_in_room_bags_missed_not_loaded() -> void:
	_place_cart()
	_world.sim.shuttle_can_dispatch = func(_cid: int, _fid: String) -> bool: return false
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)
	_world.run_to(610)
	assert_array(_world.sim.shuttles()).is_empty()
	assert_int(bag.state).is_equal(Bag.State.MISSED)
	assert_int(bag.cause).is_equal(Bag.Cause.LATE)
	assert_int(_world.sim.loaded_total).is_equal(0)
	assert_int(_world.sim.missed_total).is_equal(1)


func test_overlapping_flights_share_one_cart_and_too_late_misses() -> void:
	var cart_id := _place_cart()
	(
		assert_bool(_world.flights.add_flight("GMF202", PassengerTestWorld.starts_with(540, 640)))
		. is_true()
	)
	(
		assert_bool(_world.flights.add_flight("GMF203", PassengerTestWorld.starts_with(780, 880)))
		. is_true()
	)
	var b1 := _world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)
	var b2 := _world.sim.check_in(2, "GMF202", _desk)
	var b3 := _world.sim.check_in(3, "GMF203", _desk)
	_world.run_to(400)
	assert_int(_world.sim.shuttles().size()).is_equal(1)
	var first_shuttle := _world.sim.shuttles()[0]
	# GMF202's cutoff arrives at 440 while cart is away until first_shuttle.return_tick.
	_world.run_to(640)
	assert_int(b1.state).is_equal(Bag.State.LOADED)
	assert_int(b2.state).is_equal(Bag.State.MISSED)
	assert_int(b2.cause).is_equal(Bag.Cause.LATE)
	assert_int(b3.state).is_equal(Bag.State.IN_ROOM)
	# Once cart returns, GMF203 dispatches on the same cart and settles LOADED before 880.
	_world.run_to(first_shuttle.return_tick + 1)
	assert_int(_world.sim.shuttles().size()).is_equal(1)
	assert_int(_world.sim.shuttles()[0].cart_id).is_equal(cart_id)
	assert_str(_world.sim.shuttles()[0].flight).is_equal("GMF203")
	_world.run_to(900)
	assert_int(b3.state).is_equal(Bag.State.LOADED)


func test_decorative_cart_outside_bag_room_does_not_service_that_room() -> void:
	PassengerTestWorld.place(_world.grid, &"baggage_cart", Vector2i(1, 2), 0)
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)
	_world.run_to(bag.cutoff_tick)
	assert_array(_world.sim.shuttles()).is_empty()
	assert_int(bag.state).is_equal(Bag.State.IN_ROOM)
	_world.run_to(600)
	assert_int(bag.state).is_equal(Bag.State.MISSED)
	assert_int(bag.cause).is_equal(Bag.Cause.LATE)


func test_plan_route_guarantees_wall_clear_apron_segments() -> void:
	for x in range(4, 9):
		_world.grid.apply(BuildEdit.place_wall(Vector2i(x, 4), BuildGrid.Side.NORTH))
		_world.grid.apply(BuildEdit.place_wall(Vector2i(x, 8), BuildGrid.Side.SOUTH))
	for y in range(4, 9):
		_world.grid.apply(BuildEdit.place_wall(Vector2i(4, y), BuildGrid.Side.WEST))
		_world.grid.apply(BuildEdit.place_wall(Vector2i(8, y), BuildGrid.Side.EAST))
	# Case A: outside origin -> target must keep EVERY segment wall-clear.
	var ext_origin := _world.grid.cell_to_world(Vector2i(6, 9))
	var target := _world.grid.cell_to_world(Vector2i(6, 1))
	var ext_pts := BaggageShuttle.plan_route(_world.grid, ext_origin, target)
	assert_int(ext_pts.size()).is_greater(2)
	for i in ext_pts.size() - 1:
		(
			assert_bool(BaggageShuttle.segment_hits_wall(_world.grid, ext_pts[i], ext_pts[i + 1]))
			. is_false()
		)
	# Case B: enclosed bag_room with an internal partition wall inside room_rect ->
	# routes around the internal partition inside the room, exits once through the
	# exterior wall face, and keeps all subsequent apron segments wall-clear.
	_world.grid.apply(BuildEdit.place_wall(Vector2i(5, 7), BuildGrid.Side.WEST))
	_world.grid.apply(BuildEdit.place_wall(Vector2i(5, 7), BuildGrid.Side.SOUTH))
	var bag_room := Rect2i(4, 6, 3, 3)
	assert_bool(_world.grid.apply(BuildEdit.place_room(bag_room, &"bag_room")).ok).is_true()
	var room_origin := _world.grid.cell_to_world(Vector2i(5, 7))
	var room_pts := BaggageShuttle.plan_route(_world.grid, room_origin, target)
	assert_int(room_pts.size()).is_greater(3)
	var apron_idx := -1
	for i in room_pts.size():
		if not bag_room.has_point(_world.grid.world_to_cell(room_pts[i])):
			apron_idx = i
			break
		assert_int(_world.grid.world_to_cell(room_pts[i]).y).is_greater_equal(bag_room.position.y)
	assert_int(apron_idx).is_greater_equal(2)
	for i in apron_idx - 1:
		(
			assert_bool(
				BaggageShuttle.segment_hits_wall(_world.grid, room_pts[i], room_pts[i + 1], true)
			)
			. override_failure_message("interior seg=%d pts=%s" % [i, room_pts])
			. is_false()
		)
	for i in range(apron_idx, room_pts.size() - 1):
		(
			assert_bool(BaggageShuttle.segment_hits_wall(_world.grid, room_pts[i], room_pts[i + 1]))
			. override_failure_message("apron_idx=%d seg=%d pts=%s" % [apron_idx, i, room_pts])
			. is_false()
		)
	# Case C: exterior DOOR on bag_room -> exits through the door with zero solid wall crossings.
	(
		assert_bool(
			(
				_world
				. grid
				. apply(
					BuildEdit.place_wall(
						Vector2i(4, 7), BuildGrid.Side.WEST, BuildGrid.WallKind.DOOR
					)
				)
				. ok
			)
		)
		. is_true()
	)
	var door_pts := BaggageShuttle.plan_route(_world.grid, room_origin, target)
	assert_int(door_pts.size()).is_greater(3)
	for i in door_pts.size() - 1:
		(
			assert_bool(
				BaggageShuttle.segment_hits_wall(_world.grid, door_pts[i], door_pts[i + 1], true)
			)
			. override_failure_message("door seg=%d pts=%s" % [i, door_pts])
			. is_false()
		)
