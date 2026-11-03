class_name TestRoomMoveShop
extends GdUnitTestSuite
## Kiosk browsers when their display stand moves (decision move-rooms-
## technical-design-roommove-plan-of-existing-edits, parts 4 to 6), on
## ShopTestLayout's airside kiosk with one display stand at x 25, y 3 (its two
## slots are the cells south of it). The stand is moved by hand as a room move
## moves it: removed and placed again under its id with its paid, here to
## y 6. A browser has no exit to play, so it sets off for the stand at its new
## spot at once, with the browse it still owes, or ends unpaid.

const MOVED_TO := Vector2i(25, 6)

var _world: PassengerTestWorld
var _ids: Dictionary
## [passenger id, room id, amount] per paid signal.
var _paid: Array = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null
	_paid.clear()


func _make() -> void:
	var grid := BuildGrid.new()
	_ids = ShopTestLayout.build(grid, ["air"], 1)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	_world.sim.shops.paid.connect(
		func(id: int, room: int, amount: int) -> void: _paid.append([id, room, amount])
	)
	# Staff come on duty on the first ticks; until then the kiosk is closed.
	_world.run_to(10)


func _shops() -> ShopSim:
	return _world.sim.shops


func _display() -> int:
	return _ids["air_displays"][0]


func _at() -> Vector2i:
	return ReferenceTerminal.offset_on(_world.grid)


## A bored airside passenger committed to the display stand, run until it is
## browsing and then `spent` ticks more (not at all with `walking_only`).
func _browser_at(spent: int, walking_only := false) -> Passenger:
	var p := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
	p.mood = 60
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
	var until := _world.clock.tick + 1500
	while not walking_only and p.stage != Passenger.Stage.SHOP_BROWSE and _world.clock.tick < until:
		_world.step()
	assert_int(p.stage).is_equal(
		Passenger.Stage.SHOP_WALK if walking_only else Passenger.Stage.SHOP_BROWSE
	)
	for i in spent:
		_world.step()
	return p


func _run_to_browse(p: Passenger) -> void:
	var until := _world.clock.tick + 1500
	while p.stage != Passenger.Stage.SHOP_BROWSE and _world.clock.tick < until:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_BROWSE)


func test_a_browser_walks_to_the_moved_stand_and_browses_what_is_left_then_pays_once() -> void:
	_make()
	var p := _browser_at(40)
	var visit := _shops().visit_of(p.id)
	var old_approach: Vector2i = visit.slot["approach"]
	var started := p.stage_tick
	var balance := _world.sim.wallet.balance
	ShopMoveKit.move_piece(_world, _display(), MOVED_TO)
	assert_int(Relocation.ghosts(_world.sim).size()).is_equal(1)
	_world.step()
	var owed: int = ShopSim.BROWSE_TICKS - (_world.clock.tick - started)
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_WALK)
	assert_int(Relocation.ghosts(_world.sim).size()).is_equal(0)
	assert_bool(visit.relocation.exiting).is_false()
	assert_int(visit.relocation.left).is_equal(owed)
	assert_bool(visit.slot["approach"] != old_approach).is_true()
	assert_int(_shops().slot_holder(visit.slot_key())).is_equal(p.id)
	_run_to_browse(p)
	assert_vector(p.at).is_equal(visit.slot["approach"])
	assert_vector(p.at).is_equal(MOVED_TO + Vector2i(0, 1) + _at())
	var arrived := _world.clock.tick
	var expected := ShopSim.spend(RoomTypes.get_type(&"kiosk").base_spend, p.mood, true)
	while _shops().visit_of(p.id) != null and _world.clock.tick < arrived + 1000:
		_world.step()
	assert_int(_world.clock.tick - arrived).is_equal(owed)
	assert_array(_paid).is_equal([[p.id, _ids["air_room"], expected]])
	assert_int(_world.sim.wallet.balance - balance).is_equal(expected)
	assert_int(p.boredom).is_equal(0)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)


func test_a_walker_is_sent_to_the_moved_stand_for_the_whole_browse() -> void:
	_make()
	var p := _browser_at(3, true)
	var visit := _shops().visit_of(p.id)
	ShopMoveKit.move_piece(_world, _display(), MOVED_TO)
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_WALK)
	assert_vector(visit.slot["approach"]).is_equal(MOVED_TO + Vector2i(0, 1) + _at())
	assert_object(visit.relocation).is_null()
	_run_to_browse(p)
	assert_vector(p.at).is_equal(MOVED_TO + Vector2i(0, 1) + _at())
	var arrived := _world.clock.tick
	while _shops().visit_of(p.id) != null and _world.clock.tick < arrived + 1000:
		_world.step()
	assert_int(_world.clock.tick - arrived).is_equal(ShopSim.BROWSE_TICKS)
	assert_int(_paid.size()).is_equal(1)


func test_a_second_move_while_walking_back_only_changes_where_the_walk_goes() -> void:
	_make()
	var p := _browser_at(40)
	var visit := _shops().visit_of(p.id)
	ShopMoveKit.move_piece(_world, _display(), MOVED_TO)
	_world.step()
	var owed: int = visit.relocation.left
	_world.step()
	ShopMoveKit.move_piece(_world, _display(), Vector2i(23, 6))
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_WALK)
	assert_int(visit.relocation.left).is_equal(owed)
	_run_to_browse(p)
	assert_vector(p.at).is_equal(Vector2i(23, 7) + _at())


func test_the_cell_a_browser_stands_on_is_kept_clear_and_a_walker_has_none() -> void:
	_make()
	var p := _browser_at(0, true)
	assert_array(Relocation.exit_cells(_world.sim)).is_empty()
	_run_to_browse(p)
	var approach: Vector2i = _shops().visit_of(p.id).slot["approach"]
	assert_array(Relocation.exit_cells(_world.sim)).contains_exactly([approach])
	assert_array(_world.sim.move_exit_cells()).contains_exactly([approach])


func test_save_and_load_while_walking_back_keeps_the_stay_owed() -> void:
	_make()
	var p := _browser_at(40)
	# Not bored any more, as a load judges a fallback flag (ShopSnapshot).
	p.boredom = 0
	var visit := _shops().visit_of(p.id)
	ShopMoveKit.move_piece(_world, _display(), MOVED_TO)
	for i in 3:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_WALK)
	var text := ShopMoveKit.save_text(_world)
	assert_str(text).contains("relocation")
	var twin := ShopMoveKit.load_twin(JSON.parse_string(text))
	assert_object(twin).is_not_null()
	var seen := twin.sim.shops.visit_of(p.id)
	assert_int(seen.relocation.left).is_equal(visit.relocation.left)
	assert_bool(seen.relocation.exiting).is_false()
	assert_dict(seen.piece).is_equal(visit.piece)
	assert_dict(seen.slot).is_equal(visit.slot)
	twin.free_all()
