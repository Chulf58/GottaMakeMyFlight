class_name TestRoomMoveKinds
extends GdUnitTestSuite
## The other kinds of browse piece when their room moves (decision move-rooms-
## technical-design-roommove-plan-of-existing-edits, parts 4 to 6; test_room_
## move_activity.gd has the lounge and the shower): a nap pod sitter leans
## back and stands up (ActivityPoses.exit_ticks(), 44 ticks) and pays its fee
## once, at the new spot; a play area visitor has no exit and sets off at once;
## and a visit that cannot go on at the new spot (the piece ended up in another
## room, or went away during the exit) ends unpaid with everything as it was.
## ActivityTestLayout's piece stands at x 22, y 3 and is moved to x 25.

const MAX_STEP_M := PassengerSim.WALK_MM / 1000.0 + 0.002
const MOVED_TO := Vector2i(25, 3)

var _world: PassengerTestWorld
var _views: PassengerViews
var _ids: Dictionary
## [passenger id, room id, amount] per paid signal.
var _paid: Array = []


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
	_paid.clear()


func _start(grid: BuildGrid) -> void:
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	_world.sim.shops.paid.connect(
		func(id: int, room: int, amount: int) -> void: _paid.append([id, room, amount])
	)
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	_world.run_to(10)


func _activity(type: StringName) -> void:
	var grid := BuildGrid.new()
	_ids = ActivityTestLayout.build(grid, type)
	# The room is self-service: no staff are needed.
	_start(grid)


func _shops() -> ShopSim:
	return _world.sim.shops


func _at() -> Vector2i:
	return ReferenceTerminal.offset_on(_world.grid)


func _dwell(type: StringName) -> int:
	return ShopSim.browse_ticks(RoomTypes.get_type(type))


## A bored airside passenger (50 mood) committed to a piece, run until it is
## browsing and then `spent` ticks more.
func _visitor_at(spent: int, boredom := 80) -> Passenger:
	var p := ShopTestLayout.airside_guest(_world, boredom)
	p.mood = 50
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
	var until := _world.clock.tick + 1500
	while p.stage != Passenger.Stage.SHOP_BROWSE and _world.clock.tick < until:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_BROWSE)
	for i in spent:
		_world.step()
	return p


## Steps until `done` holds or `limit` ticks pass, failing when the drawn
## position moves more than MAX_STEP_M on any tick.
func _walk_until(p: Passenger, done: Callable, limit := 1500) -> void:
	var last := _views.tick_position(p.id, true)
	var largest := 0.0
	var until := _world.clock.tick + limit
	while not done.call() and _world.clock.tick < until:
		_world.step()
		var now := _views.tick_position(p.id, true)
		largest = maxf(largest, now.distance_to(last))
		last = now
	assert_bool(done.call()).is_true()
	assert_float(largest).is_less(MAX_STEP_M)


func _to_stage(p: Passenger, stage: Passenger.Stage) -> void:
	_walk_until(p, func() -> bool: return p.stage == stage)


func test_a_nap_pod_sitter_leans_back_and_stands_up_then_sleeps_on_in_the_moved_pod() -> void:
	_activity(&"nap_pod")
	var p := _visitor_at(80)
	var visit := _shops().visit_of(p.id)
	var old_approach: Vector2i = visit.slot["approach"]
	var seat: Vector2i = old_approach + (visit.slot["facing"] as Vector2i)
	assert_float(ActivityPoses.recline(_world.sim, p)).is_equal(1.0)
	var started := p.stage_tick
	var balance := _world.sim.wallet.balance
	ShopMoveKit.move_piece(_world, _ids["use"], MOVED_TO)
	assert_array(_world.sim.move_exit_cells()).contains_exactly([old_approach, seat])
	_world.step()
	var moved_at := _world.clock.tick
	assert_int(visit.relocation.left).is_equal(_dwell(&"nap_pod") - (moved_at - started))
	assert_int(ActivityPoses.exit_ticks(&"nap_pod", 0)).is_equal(
		PassengerSim.STAND_UP_TICKS + ActivityPoses.EASE_TICKS
	)
	# The lean back first, then the stand-up, at the old pod.
	assert_float(ActivityPoses.recline(_world.sim, p)).is_greater(0.9)
	assert_int(ActivityPoses.pose(_world.sim, p)).is_equal(StageKinds.Pose.SEATED)
	assert_array(_world.sim.move_exit_cells()).contains_exactly([old_approach, seat])
	var standing := func() -> bool:
		return ActivityPoses.pose(_world.sim, p) == StageKinds.Pose.STANDING_UP
	_walk_until(p, standing)
	assert_int(_world.clock.tick - moved_at).is_equal(ActivityPoses.EASE_TICKS)
	assert_float(ActivityPoses.recline(_world.sim, p)).is_equal(0.0)
	assert_vector(p.at).is_equal(old_approach)
	_walk_until(p, func() -> bool: return p.stage == Passenger.Stage.SHOP_WALK)
	assert_int(_world.clock.tick - moved_at).is_equal(44)
	assert_array(_world.sim.move_exit_cells()).is_empty()
	assert_int(_world.sim.wallet.balance).is_equal(balance)
	assert_array(_paid).is_empty()
	_to_stage(p, Passenger.Stage.SHOP_BROWSE)
	assert_vector(p.at).is_equal(MOVED_TO + Vector2i(0, 1) + _at())
	var arrived := _world.clock.tick
	var owed: int = visit.relocation.left
	while _shops().visit_of(p.id) != null and _world.clock.tick < arrived + 1000:
		_world.step()
	assert_int(_world.clock.tick - arrived).is_equal(owed)
	var fee := ShopSim.spend(PriceTable.NAP_POD_FEE, 50, true)
	assert_array(_paid).is_equal([[p.id, _ids["room"], fee]])
	assert_int(_world.sim.wallet.balance - balance).is_equal(fee)
	assert_int(p.boredom).is_equal(0)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)


func test_a_play_area_visitor_has_no_exit_and_plays_on_at_the_moved_slide() -> void:
	_activity(&"play_area")
	var p := _visitor_at(50)
	var visit := _shops().visit_of(p.id)
	var old_approach: Vector2i = visit.slot["approach"]
	assert_int(ActivityPoses.exit_ticks(&"play_slide", 0)).is_equal(0)
	# Only the cell it stands on: it neither sits nor lies on the piece.
	assert_array(_world.sim.move_exit_cells()).contains_exactly([old_approach])
	var started := p.stage_tick
	ShopMoveKit.move_piece(_world, _ids["use"], Vector2i(22, 6))
	assert_int(Relocation.ghosts(_world.sim).size()).is_equal(1)
	_world.step()
	var moved_at := _world.clock.tick
	# No exit to play: it sets off on the tick it notices the move.
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_WALK)
	assert_int(Relocation.ghosts(_world.sim).size()).is_equal(0)
	assert_bool(visit.relocation.exiting).is_false()
	assert_int(visit.relocation.left).is_equal(_dwell(&"play_area") - (moved_at - started))
	assert_array(_world.sim.move_exit_cells()).is_empty()
	_to_stage(p, Passenger.Stage.SHOP_BROWSE)
	assert_vector(p.at).is_equal(Vector2i(22, 7) + _at())
	assert_array(_world.sim.move_exit_cells()).contains_exactly([Vector2i(22, 7) + _at()])
	var arrived := _world.clock.tick
	var owed: int = visit.relocation.left
	while _shops().visit_of(p.id) != null and _world.clock.tick < arrived + 1000:
		_world.step()
	assert_int(_world.clock.tick - arrived).is_equal(owed)
	# Free: nothing paid, the mood and boredom settle as for any finished stay.
	assert_array(_paid).is_empty()
	assert_int(p.boredom).is_equal(0)
	assert_int(p.mood).is_equal(50 + RoomTypes.get_type(&"play_area").mood_bonus)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)


func test_a_browser_whose_stand_ended_up_in_another_room_ends_unpaid_and_goes_on() -> void:
	var grid := BuildGrid.new()
	# Two airside kiosks side by side; a display of the first ends up in the second.
	_ids = WishTestLayout.build(grid, [&"kiosk", &"kiosk"])
	_start(grid)
	var p := _visitor_at(40, BoredomSim.MAX)
	var visit := _shops().visit_of(p.id)
	var display := visit.display
	var key := visit.slot_key()
	assert_int(visit.room).is_equal(_ids["rooms"][0])
	var balance := _world.sim.wallet.balance
	ShopMoveKit.move_piece(_world, display, Vector2i(29, 6))
	var second: Rect2i = _world.grid.get_room(_ids["rooms"][1])["rect"]
	assert_bool(second.has_point(Vector2i(29, 6) + _at())).is_true()
	_shops().refresh()
	# The other kiosk is ready and open, and the piece is one of its slots now.
	assert_int(_shops().layout.slot(display, 0)["room"]).is_equal(_ids["rooms"][1])
	assert_bool(ShopCounters.room_open(_world.sim, _ids["rooms"][1])).is_true()
	_world.step()
	assert_object(_shops().visit_of(p.id)).is_null()
	assert_int(_shops().slot_holder(key)).is_equal(0)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
	assert_int(p.boredom).is_equal(BoredomSim.MAX)
	assert_int(p.mood).is_equal(50)
	assert_int(_world.sim.wallet.balance).is_equal(balance)
	assert_array(_paid).is_empty()
	# Nobody was sent to the other kiosk's slot either.
	assert_int(_shops().slot_holder(ShopLayout.key_of(display, 0))).is_equal(0)
	assert_int(visit.room).is_equal(_ids["rooms"][0])


func test_a_shower_visitor_whose_cubicle_goes_away_during_the_exit_ends_unpaid() -> void:
	_activity(&"shower")
	var p := _visitor_at(80)
	var visit := _shops().visit_of(p.id)
	var key := visit.slot_key()
	var balance := _world.sim.wallet.balance
	ShopMoveKit.move_piece(_world, _ids["use"], MOVED_TO)
	_world.step()
	assert_bool(visit.relocation.exiting).is_true()
	for i in 5:
		_world.step()
	assert_bool(_world.grid.apply(BuildEdit.remove_object(_ids["use"])).ok).is_true()
	# The exit goes on at the old spot; the visit ends when it does.
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_BROWSE)
	var until := _world.clock.tick + 100
	while _shops().visit_of(p.id) != null and _world.clock.tick < until:
		_world.step()
	assert_object(_shops().visit_of(p.id)).is_null()
	assert_int(_shops().slot_holder(key)).is_equal(0)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
	assert_int(p.boredom).is_equal(80)
	assert_int(p.mood).is_equal(50)
	assert_int(_world.sim.wallet.balance).is_equal(balance)
	assert_array(_paid).is_empty()


func test_a_load_refuses_a_slot_the_pieces_type_does_not_have() -> void:
	var grid := BuildGrid.new()
	_ids = WishTestLayout.build(grid, [&"pharmacy"])
	_start(grid)
	var p := _visitor_at(10, BoredomSim.MAX)
	p.boredom = 0
	var shelf: Dictionary = Relocation.placement(_world.grid, _shops().visit_of(p.id).display)
	assert_bool(shelf["def"] == &"pharmacy_shelf").is_true()
	var text := ShopMoveKit.save_text(_world)
	assert_object(ShopMoveKit.load_twin(JSON.parse_string(text))).is_not_null()
	# A shelf is two cells wide but has one browse slot (seats_per_piece 1): a
	# relocation leaving its second cell cannot have happened.
	var data: Dictionary = JSON.parse_string(text)
	var entry: Dictionary = data["passengers"]["shop"]["visits"][0]
	entry["slot"] = 1
	entry["relocation"] = {
		"def": "pharmacy_shelf",
		"anchor": [shelf["anchor"].x, shelf["anchor"].y],
		"facing": shelf["facing"],
		"exiting": true,
		"left": -1,
	}
	assert_object(ShopMoveKit.load_twin(data)).is_null()
