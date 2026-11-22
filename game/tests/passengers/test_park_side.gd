class_name TestParkSide
extends GdUnitTestSuite
## A sofa roller visitor holds one hand (SecurityLooks.hand_of(), ParkSide)
## for its whole stay, from the set-down to the walk-off, and the bag's own
## place agrees with it on every frame (board a40fdbaf): the lounge pick-up
## took the roller in the right hand while it lay at the left hand's floor
## spot, and drew it in the sofa (activity_bags_plates_probe lounge_pick_up
## frames 2-5).

var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
		_views = null
	if _world != null:
		_world.free_all()
		_world = null


## One frame `ticks` sim ticks on, as the game draws them.
func _frame(ticks: float) -> void:
	_world.clock.advance(SimClock.STEP * ticks)
	await get_tree().process_frame
	await get_tree().create_timer(0.0, true, false, true).timeout
	_views.carry_on_props()._unposed()


## The lounge's roller visitor, from the first tick of its stay to the tick it
## leaves: the hand hand_of() names and the hand of the bag's place agree, and
## neither changes. Control: the roller went down to the floor and back to the
## hand in the stay.
func test_a_sofa_roller_visitor_keeps_one_hand_for_its_whole_stay() -> void:
	var grid := BuildGrid.new()
	ActivityTestLayout.build(grid, &"lounge")
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	_world.auto_staff_roles = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]
	_world.run_to(10)
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)
	var p := ShopTestLayout.airside_guest(_world, 0)
	while SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.ROLLER:
		p = ShopTestLayout.airside_guest(_world, 0)
	p.boredom = 80
	p.carry_on = 1
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
	while p.stage != Passenger.Stage.SHOP_BROWSE and _world.clock.tick < 3000:
		await _frame(1.0)
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_BROWSE)
	var props := _views.carry_on_props()
	var seen := {}
	var log: Array[String] = []
	var homes := {}
	while p.stage == Passenger.Stage.SHOP_BROWSE:
		var sim_hand := SecurityLooks.hand_of(_world.sim, p, 0)
		var place := int(props.bag_state(p.id, 0).get("place", -1))
		var drawn := CarryLead.hand_of(place)
		seen[sim_hand * 10 + drawn] = true
		homes[place / 4] = true
		log.append("t%d at %s h%d d%d" % [_world.clock.tick, p.at, sim_hand, drawn])
		await _frame(1.0)
	print("sofa roller stay: hands (sim * 10 + drawn) %s, homes %s" % [seen.keys(), homes.keys()])
	if seen.size() > 1:
		print("\n".join(log))
	assert_bool(homes.has(SecurityLooks.Home.FLOOR)).is_true()
	assert_bool(homes.has(SecurityLooks.Home.HAND)).is_true()
	assert_int(seen.size()).is_equal(1)
	var only: int = seen.keys()[0]
	assert_int(only / 10).is_equal(only % 10)


func _gate_roller_setup(piece_def: StringName, anchor: Vector2i, facing: int) -> Dictionary:
	var grid := PassengerTestWorld.floored(Vector2i(10, 10))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(1, 9), 2)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(1, 0), 0)
	PassengerTestWorld.place(grid, piece_def, anchor, facing)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(900, 1600))
	var seat: Dictionary = _world.sim.layout.seats[0]
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.ROLLER:
		ToiletTestLayout.calm(p)
		p.carry_on = 0
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 1
	p.cleared = true
	var out: Vector2i = (seat["front"] as Vector2i) - (seat["cell"] as Vector2i)
	_world.sim._seat_claims[seat["key"]] = p.id
	p.seat_object = seat["object_id"]
	p.seat_cell = seat["cell"]
	p.seat_front = seat["front"]
	p.seat_piece = Relocation.placement(grid, seat["object_id"])
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _world.clock.tick
	p.at = (seat["front"] as Vector2i) + out
	p.clear_path()
	return {
		"p": p,
		"seat": seat,
		"right": BuildGrid.SIDE_STEP.find(Vector2i(-out.y, out.x)),
		"left": BuildGrid.SIDE_STEP.find(Vector2i(out.y, -out.x)),
	}


func test_gate_chair_stamp_revalidates_on_wall_while_carried() -> void:
	var ctx := _gate_roller_setup(&"seat_row", Vector2i(4, 3), 0)
	var p: Passenger = ctx["p"]
	var seat: Dictionary = ctx["seat"]
	assert_int(ParkSide.hand(_world.sim, p, 0)).is_equal(0)
	assert_bool(_world.grid.apply(BuildEdit.place_wall(seat["front"], ctx["right"])).ok).is_true()
	assert_int(ParkSide.hand(_world.sim, p, 0)).is_equal(1)
	assert_int(SecurityLooks.hand_of(_world.sim, p, 0)).is_equal(1)
	var stamps: Dictionary = _world.sim.get_meta(ParkSide.STAMPS, {})
	assert_array(stamps.get(p.id, [])).is_equal(["gate %s" % p.seat_cell, 1])


func test_gate_chair_stamp_stays_locked_after_set_down() -> void:
	var ctx := _gate_roller_setup(&"seat_row", Vector2i(4, 3), 0)
	var p: Passenger = ctx["p"]
	var seat: Dictionary = ctx["seat"]
	assert_int(ParkSide.hand(_world.sim, p, 0)).is_equal(0)
	p.stage = Passenger.Stage.SITTING_DOWN
	p.stage_tick = _world.clock.tick
	assert_bool(_world.grid.apply(BuildEdit.place_wall(seat["front"], ctx["right"])).ok).is_true()
	assert_int(ParkSide.hand(_world.sim, p, 0)).is_equal(0)
	p.stage = Passenger.Stage.SEATED
	assert_int(ParkSide.hand(_world.sim, p, 0)).is_equal(0)
	p.stage = Passenger.Stage.STANDING_UP
	assert_int(ParkSide.hand(_world.sim, p, 0)).is_equal(0)


func test_gate_chair_stamp_keeps_right_on_unrelated_wall_while_carried() -> void:
	var ctx := _gate_roller_setup(&"seat_row", Vector2i(4, 3), 0)
	var p: Passenger = ctx["p"]
	var seat: Dictionary = ctx["seat"]
	assert_int(ParkSide.hand(_world.sim, p, 0)).is_equal(0)
	assert_bool(_world.grid.apply(BuildEdit.place_wall(Vector2i(8, 8), 0)).ok).is_true()
	assert_int(ParkSide.hand(_world.sim, p, 0)).is_equal(0)
	assert_bool(_world.grid.apply(BuildEdit.place_wall(seat["front"], ctx["left"])).ok).is_true()
	assert_int(ParkSide.hand(_world.sim, p, 0)).is_equal(0)
	assert_bool(_world.grid.apply(BuildEdit.place_wall(seat["front"], ctx["right"])).ok).is_true()
	assert_int(ParkSide.hand(_world.sim, p, 0)).is_equal(0)


func test_bench_1a_stamp_revalidates_while_carried_and_locks_after_set_down() -> void:
	var ctx := _gate_roller_setup(&"bench_1a", Vector2i(5, 3), 0)
	var p: Passenger = ctx["p"]
	var seat: Dictionary = ctx["seat"]
	assert_int(ParkSide.hand(_world.sim, p, 0)).is_equal(0)
	assert_bool(_world.grid.apply(BuildEdit.place_wall(seat["front"], ctx["right"])).ok).is_true()
	assert_int(ParkSide.hand(_world.sim, p, 0)).is_equal(1)

	_world.free_all()
	_world = null
	var ctx_locked := _gate_roller_setup(&"bench_1a", Vector2i(5, 3), 0)
	var q: Passenger = ctx_locked["p"]
	var locked_seat: Dictionary = ctx_locked["seat"]
	assert_int(ParkSide.hand(_world.sim, q, 0)).is_equal(0)
	q.stage = Passenger.Stage.SITTING_DOWN
	q.stage_tick = _world.clock.tick
	(
		assert_bool(
			_world.grid.apply(BuildEdit.place_wall(locked_seat["front"], ctx_locked["right"])).ok
		)
		. is_true()
	)
	assert_int(ParkSide.hand(_world.sim, q, 0)).is_equal(0)


func test_gate_chair_stamp_revalidates_on_sim_tick_entering_sitting_down() -> void:
	var ctx := _gate_roller_setup(&"seat_row", Vector2i(4, 3), 0)
	var p: Passenger = ctx["p"]
	var seat: Dictionary = ctx["seat"]
	p.at = seat["front"]
	assert_int(ParkSide.hand(_world.sim, p, 0)).is_equal(0)
	assert_bool(_world.grid.apply(BuildEdit.place_wall(seat["front"], ctx["right"])).ok).is_true()
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SITTING_DOWN)
	assert_int(ParkSide.hand(_world.sim, p, 0)).is_equal(1)
	assert_int(SecurityLooks.hand_of(_world.sim, p, 0)).is_equal(1)


func test_gate_chair_stamp_revalidates_left_to_right_while_carried() -> void:
	var ctx := _gate_roller_setup(&"seat_row", Vector2i(4, 3), 0)
	var p: Passenger = ctx["p"]
	var seat: Dictionary = ctx["seat"]
	assert_bool(_world.grid.apply(BuildEdit.place_wall(seat["front"], ctx["right"])).ok).is_true()
	assert_int(ParkSide.hand(_world.sim, p, 0)).is_equal(1)
	assert_bool(_world.grid.apply(BuildEdit.remove_wall(seat["front"], ctx["right"])).ok).is_true()
	assert_bool(_world.grid.apply(BuildEdit.place_wall(seat["front"], ctx["left"])).ok).is_true()
	assert_int(ParkSide.hand(_world.sim, p, 0)).is_equal(0)
	assert_int(SecurityLooks.hand_of(_world.sim, p, 0)).is_equal(0)
