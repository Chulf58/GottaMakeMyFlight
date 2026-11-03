class_name TestRoomMoveActivity
extends GdUnitTestSuite
## Visitors of the lounge sofa and the shower when their piece moves (decision
## move-rooms-technical-design-roommove-plan-of-existing-edits, parts 4 to 6),
## on ActivityTestLayout's airside room with the piece at x 22, y 3 (the first
## slot is the cell south of it). The piece is moved by hand as a room move
## moves it: removed and placed again under its id with its paid, here to
## x 25 (MOVED_TO).
##
## A sitter or shower user plays the exit of an ordinary end of stay at the old
## spot, with nothing settled, and is then admitted again for the piece at its
## new spot with the stay it still owes, or ends unpaid. Steps are measured on
## the drawn position a PassengerViews records each tick (tick_position()).

const MAX_STEP_M := PassengerSim.WALK_MM / 1000.0 + 0.002
const MOVED_TO := Vector2i(25, 3)

var _world: PassengerTestWorld
var _views: PassengerViews
var _ids: Dictionary
var _balance := 0


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


func _make(type := &"lounge") -> void:
	var grid := BuildGrid.new()
	_ids = ActivityTestLayout.build(grid, type)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	# The room is self-service: no staff are needed.
	_world.auto_staff_roles = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	_world.run_to(10)
	_balance = _world.sim.wallet.balance


func _shops() -> ShopSim:
	return _world.sim.shops


func _at() -> Vector2i:
	return ReferenceTerminal.offset_on(_world.grid)


func _dwell(type := &"lounge") -> int:
	return ShopSim.browse_ticks(RoomTypes.get_type(type))


## A bored airside passenger committed to the room's piece, run until it is
## browsing there and then `spent` ticks more.
func _visitor_at(spent: int, walking_only := false) -> Passenger:
	var p := ShopTestLayout.airside_guest(_world, 80)
	p.mood = 50
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
	var until := _world.clock.tick + 1500
	if not walking_only:
		while p.stage != Passenger.Stage.SHOP_BROWSE and _world.clock.tick < until:
			_world.step()
		assert_int(p.stage).is_equal(Passenger.Stage.SHOP_BROWSE)
	for i in spent:
		_world.step()
	return p


## Steps until `done` holds or `limit` ticks pass, failing when the drawn
## position moves more than MAX_STEP_M on any tick (the message names the
## tick and stage), unless `measure` is false.
func _walk_until(p: Passenger, done: Callable, limit := 1500, measure := true) -> void:
	var last := _views.tick_position(p.id, true)
	var largest := 0.0
	var worst := ""
	var until := _world.clock.tick + limit
	while not done.call() and _world.clock.tick < until:
		_world.step()
		var now := _views.tick_position(p.id, true)
		if now.distance_to(last) > largest:
			largest = now.distance_to(last)
			worst = "tick %d stage %d step %.3f" % [_world.clock.tick, p.stage, largest]
		last = now
	assert_bool(done.call()).is_true()
	if measure:
		assert_float(largest).override_failure_message(worst).is_less(MAX_STEP_M)


func _earned() -> int:
	return _world.sim.wallet.balance - _balance


func test_a_seated_visitor_stands_up_in_the_old_sofa_then_sits_on_the_moved_one_for_what_is_left(
) -> void:
	_make()
	var p := _visitor_at(60)
	var visit := _shops().visit_of(p.id)
	var old := Relocation.placement(_world.grid, _ids["use"])
	var old_approach: Vector2i = visit.slot["approach"]
	var seated := ActivityPoses.offset(_world.sim, p)
	assert_int(ActivityPoses.pose(_world.sim, p)).is_equal(StageKinds.Pose.SEATED)
	var started := p.stage_tick
	ShopMoveKit.move_piece(_world, _ids["use"], MOVED_TO)
	# Before the next tick nobody has moved: still seated on the old sofa.
	assert_int(ActivityPoses.pose(_world.sim, p)).is_equal(StageKinds.Pose.SEATED)
	assert_vector(ActivityPoses.offset(_world.sim, p)).is_equal(seated)
	assert_int(Relocation.ghosts(_world.sim).size()).is_equal(1)
	_world.step()
	var moved_at := _world.clock.tick
	assert_object(visit.relocation).is_not_null()
	assert_bool(visit.relocation.exiting).is_true()
	assert_dict(visit.relocation.source).is_equal(old)
	assert_int(visit.relocation.left).is_equal(_dwell() - (moved_at - started))
	assert_int(ActivityPoses.pose(_world.sim, p)).is_equal(StageKinds.Pose.STANDING_UP)
	assert_int(ActivityPoses.clip_ticks(_world.sim, p)).is_equal(0)
	assert_vector(p.at).is_equal(old_approach)
	assert_int(Relocation.ghosts(_world.sim).size()).is_equal(1)
	_walk_until(p, func() -> bool: return p.stage == Passenger.Stage.SHOP_WALK)
	assert_int(_world.clock.tick - moved_at).is_equal(PassengerSim.STAND_UP_TICKS)
	assert_int(Relocation.ghosts(_world.sim).size()).is_equal(0)
	assert_int(_earned()).is_equal(0)
	_walk_until(p, func() -> bool: return p.stage == Passenger.Stage.SHOP_BROWSE)
	assert_vector(p.at).is_equal(MOVED_TO + Vector2i(0, 1) + _at())
	var arrived := _world.clock.tick
	assert_int(ActivityPoses.pose(_world.sim, p)).is_equal(StageKinds.Pose.SITTING_DOWN)
	assert_bool(visit.relocation.exiting).is_false()
	# The rest is an ordinary stay: it ends after the stay still owed.
	var owed: int = visit.relocation.left
	while _shops().visit_of(p.id) != null and _world.clock.tick < arrived + 1000:
		_world.step()
	assert_int(_world.clock.tick - arrived).is_equal(owed)
	assert_int(p.boredom).is_equal(0)
	assert_int(p.mood).is_equal(50 + RoomTypes.get_type(&"lounge").mood_bonus)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)


func test_a_visitor_still_sitting_down_gets_up_again_and_comes_back() -> void:
	_make()
	var p := _visitor_at(5)
	var visit := _shops().visit_of(p.id)
	ShopMoveKit.move_piece(_world, _ids["use"], MOVED_TO)
	_world.step()
	assert_bool(visit.relocation.exiting).is_true()
	assert_int(ActivityPoses.pose(_world.sim, p)).is_equal(StageKinds.Pose.STANDING_UP)
	_walk_until(p, func() -> bool: return p.stage == Passenger.Stage.SHOP_WALK, 1500, false)
	_walk_until(p, func() -> bool: return p.stage == Passenger.Stage.SHOP_BROWSE)
	assert_vector(p.at).is_equal(MOVED_TO + Vector2i(0, 1) + _at())
	while _shops().visit_of(p.id) != null and _world.clock.tick < 3000:
		_world.step()
	assert_int(p.boredom).is_equal(0)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)


func test_a_visitor_already_standing_up_finishes_there_and_settles() -> void:
	_make()
	var p := _visitor_at(_dwell() - 10)
	var visit := _shops().visit_of(p.id)
	var old_approach: Vector2i = visit.slot["approach"]
	assert_int(ActivityPoses.pose(_world.sim, p)).is_equal(StageKinds.Pose.STANDING_UP)
	ShopMoveKit.move_piece(_world, _ids["use"], MOVED_TO)
	_world.step()
	assert_int(visit.relocation.left).is_equal(-1)
	assert_bool(visit.relocation.exiting).is_true()
	var walked := [false]
	var until := _world.clock.tick + 100
	while _shops().visit_of(p.id) != null and _world.clock.tick < until:
		assert_vector(p.at).is_equal(old_approach)
		walked[0] = walked[0] or p.stage == Passenger.Stage.SHOP_WALK
		_world.step()
	assert_bool(walked[0]).is_false()
	assert_int(p.boredom).is_equal(0)
	assert_int(p.mood).is_equal(50 + RoomTypes.get_type(&"lounge").mood_bonus)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)


func test_a_walker_is_sent_to_the_moved_sofa_for_the_whole_stay() -> void:
	_make()
	var p := _visitor_at(3, true)
	var visit := _shops().visit_of(p.id)
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_WALK)
	ShopMoveKit.move_piece(_world, _ids["use"], MOVED_TO)
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_WALK)
	assert_vector(visit.slot["approach"]).is_equal(MOVED_TO + Vector2i(0, 1) + _at())
	assert_object(visit.relocation).is_null()
	_walk_until(p, func() -> bool: return p.stage == Passenger.Stage.SHOP_BROWSE)
	assert_vector(p.at).is_equal(MOVED_TO + Vector2i(0, 1) + _at())
	var arrived := _world.clock.tick
	while _shops().visit_of(p.id) != null and _world.clock.tick < arrived + 1000:
		_world.step()
	assert_int(_world.clock.tick - arrived).is_equal(_dwell())
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)


func test_the_cells_a_sitter_needs_to_leave_are_kept_clear_until_it_has() -> void:
	_make()
	var p := _visitor_at(60, false)
	var visit := _shops().visit_of(p.id)
	var approach: Vector2i = visit.slot["approach"]
	var seat: Vector2i = approach + (visit.slot["facing"] as Vector2i)
	var cells := Relocation.exit_cells(_world.sim)
	assert_array(cells).contains_exactly([approach, seat])
	assert_array(_world.sim.move_exit_cells()).contains_exactly([approach, seat])
	ShopMoveKit.move_piece(_world, _ids["use"], MOVED_TO)
	_world.step()
	assert_array(Relocation.exit_cells(_world.sim)).contains_exactly([approach, seat])
	_walk_until(p, func() -> bool: return p.stage == Passenger.Stage.SHOP_WALK, 1500, false)
	assert_array(Relocation.exit_cells(_world.sim)).is_empty()


func test_a_second_move_while_leaving_only_changes_where_the_walk_goes() -> void:
	_make()
	var p := _visitor_at(60)
	var visit := _shops().visit_of(p.id)
	var old := Relocation.placement(_world.grid, _ids["use"])
	ShopMoveKit.move_piece(_world, _ids["use"], MOVED_TO)
	_world.step()
	var relocation := visit.relocation
	var stage_tick := p.stage_tick
	for i in 5:
		_world.step()
	ShopMoveKit.move_piece(_world, _ids["use"], Vector2i(23, 6))
	_world.step()
	assert_object(visit.relocation).is_same(relocation)
	assert_dict(visit.relocation.source).is_equal(old)
	assert_int(p.stage_tick).is_equal(stage_tick)
	_walk_until(p, func() -> bool: return p.stage == Passenger.Stage.SHOP_WALK, 1500, false)
	_walk_until(p, func() -> bool: return p.stage == Passenger.Stage.SHOP_BROWSE, 1500, false)
	assert_vector(p.at).is_equal(Vector2i(23, 7) + _at())


func test_save_and_load_while_leaving_the_old_sofa_plays_on() -> void:
	_make()
	var p := _visitor_at(60)
	ShopMoveKit.move_piece(_world, _ids["use"], MOVED_TO)
	for i in 10:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_BROWSE)
	var text := ShopMoveKit.save_text(_world)
	assert_str(text).contains("relocation")
	var twin := ShopMoveKit.load_twin(JSON.parse_string(text))
	assert_object(twin).is_not_null()
	var q := twin.passenger(p.id)
	assert_int(Relocation.ghosts(twin.sim).size()).is_equal(1)
	assert_vector(ActivityPoses.offset(twin.sim, q)).is_equal(ActivityPoses.offset(_world.sim, p))
	assert_int(ActivityPoses.pose(twin.sim, q)).is_equal(StageKinds.Pose.STANDING_UP)
	assert_array(Relocation.exit_cells(twin.sim)).is_equal(Relocation.exit_cells(_world.sim))
	for i in 120:
		_world.step()
		twin.step()
		assert_int(q.stage).is_equal(p.stage)
		assert_vector(twin.sim.world_position(q)).is_equal(_world.sim.world_position(p))
	assert_int(q.stage).is_equal(Passenger.Stage.SHOP_BROWSE)
	assert_vector(q.at).is_equal(MOVED_TO + Vector2i(0, 1) + _at())
	twin.free_all()


func test_a_load_refuses_a_relocation_that_cannot_have_happened() -> void:
	_make()
	var p := _visitor_at(60)
	ShopMoveKit.move_piece(_world, _ids["use"], MOVED_TO)
	for i in 10:
		_world.step()
	var text := ShopMoveKit.save_text(_world)
	var corrupt := {
		"a piece that is no browse piece": ["def", "toilet_stall"],
		"an exit that has run out": ["left", 0],
		"a service owed beyond the stay": ["left", _dwell() + 1],
	}
	for what: String in corrupt:
		var data: Dictionary = JSON.parse_string(text)
		var visits: Array = data["passengers"]["shop"]["visits"]
		var entry: Dictionary = visits[0]
		assert_int(int(entry["passenger"])).is_equal(p.id)
		entry["relocation"][corrupt[what][0]] = corrupt[what][1]
		var twin := ShopMoveKit.load_twin(data)
		assert_object(twin).override_failure_message(what).is_null()
	var data: Dictionary = JSON.parse_string(text)
	data["passengers"]["shop"]["visits"][0]["relocation"]["exiting"] = false
	assert_object(ShopMoveKit.load_twin(data)).override_failure_message("a return").is_null()


func test_a_ghost_view_draws_the_sofa_at_its_old_spot_until_the_visitor_has_left() -> void:
	_make()
	var p := _visitor_at(60)
	var old := Relocation.placement(_world.grid, _ids["use"])
	var ghosts := RelocationGhosts.new()
	ghosts.sim = _world.sim
	add_child(ghosts)
	ShopMoveKit.move_piece(_world, _ids["use"], MOVED_TO)
	ghosts.sync()
	assert_int(ghosts.count()).is_equal(1)
	var entry := old.duplicate()
	entry["id"] = _ids["use"]
	var cells := BuildCatalog.get_def(&"lounge_sofa").footprint(old["anchor"], old["facing"])
	var where := BuildView.object_transform(_world.grid, cells, old["facing"]).origin
	assert_vector(ghosts.node_of(entry).position).is_equal(where)
	_walk_until(p, func() -> bool: return p.stage == Passenger.Stage.SHOP_WALK, 1500, false)
	ghosts.sync()
	assert_int(ghosts.count()).is_equal(0)
	ghosts.free()


func test_a_showering_visitor_steps_out_at_the_old_cubicle_and_showers_in_the_moved_one() -> void:
	_make(&"shower")
	var p := _visitor_at(80)
	var visit := _shops().visit_of(p.id)
	assert_int(ActivityPoses.kind(_world.sim, p)).is_equal(ActivityPoses.Kind.SHOWER)
	assert_float(ActivityPoses.foam(_world.sim, p)).is_equal(1.0)
	var old_approach: Vector2i = visit.slot["approach"]
	ShopMoveKit.move_piece(_world, _ids["use"], MOVED_TO)
	_world.step()
	var moved_at := _world.clock.tick
	assert_bool(visit.relocation.exiting).is_true()
	assert_vector(p.at).is_equal(old_approach)
	_walk_until(p, func() -> bool: return p.stage == Passenger.Stage.SHOP_WALK)
	assert_int(_world.clock.tick - moved_at).is_equal(ActivityPoses.EASE_TICKS)
	_walk_until(p, func() -> bool: return p.stage == Passenger.Stage.SHOP_BROWSE)
	assert_vector(p.at).is_equal(MOVED_TO + Vector2i(0, 1) + _at())
	assert_float(ActivityPoses.foam(_world.sim, p)).is_equal(0.0)
	while _shops().visit_of(p.id) != null and _world.clock.tick < 4000:
		_world.step()
	assert_int(p.boredom).is_equal(0)
	assert_int(_earned()).is_greater(0)
