class_name TestNeedIconsFacilityGate
extends GdUnitTestSuite
## A need's icon is hidden while nothing built can meet that need (decision
## crowd-need-display-mood-overlay-gains-hunger-toilet-and-bore, point 3), and
## shows once a facility for it stands. Each need is driven through the real
## views: a room with no piece (the control) then the piece placed in the same
## world.

var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if is_instance_valid(_views):
		_views.free()
	_world.free_all()


func _start(grid: BuildGrid) -> void:
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.run_to(10)
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)


## The number of need icons drawn over a calm passenger after `setup` has set
## its needs, one tick and a draw later.
func _icons(id: int) -> int:
	_world.step()
	_views.draw()
	return _views.node_for(id).get_meta(&"needs", -1)


## A calm passenger with no shopping wish (a bored wisher shows its wish bubble
## instead of the hourglass, WishIconView), `setup` having set its needs.
func _calm_passenger(setup: Callable) -> int:
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	ToiletTestLayout.calm(p)
	setup.call(p)
	return id


func _place(grid: BuildGrid, def_id: StringName, anchor: Vector2i) -> void:
	var result := grid.apply(BuildEdit.place_object(def_id, anchor, 0))
	assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()


func test_the_toilet_icon_waits_for_a_stall() -> void:
	var grid := BuildGrid.new()
	ToiletTestLayout.build(grid, 0)
	_start(grid)
	var id := _calm_passenger(func(p: Passenger) -> void: p.toilet_need = ToiletSim.NEED_MAX)
	assert_int(_icons(id)).is_equal(0)
	var at := ReferenceTerminal.offset_on(grid)
	_place(grid, &"toilet_stall", Vector2i(ToiletTestLayout.STALL_X, 3) + at)
	assert_int(_icons(id)).is_equal(1)
	(
		assert_array(NeedIcons.shown(_world.passenger(id), false, NeedIcons.provided(_world.sim)))
		. is_equal([NeedIcons.Need.TOILET])
	)


func test_the_hunger_icon_waits_for_a_cafe() -> void:
	var grid := BuildGrid.new()
	# A cafe room and counter with no table is not ready: no cafe stands yet.
	CafeTestLayout.build(grid, false, &"cafe", false)
	_start(grid)
	var id := _calm_passenger(func(p: Passenger) -> void: p.hunger = CafeSim.HUNGER_MAX)
	assert_int(_icons(id)).is_equal(0)
	_place(grid, &"cafe_table", CafeTestLayout.AIR_TABLE + ReferenceTerminal.offset_on(grid))
	assert_int(_icons(id)).is_equal(1)


func test_the_boredom_icon_waits_for_a_kiosk() -> void:
	var grid := BuildGrid.new()
	# A kiosk room and counter with no display stand has no browse slot.
	ShopTestLayout.build(grid, ["air"], 0)
	_start(grid)
	var id := _calm_passenger(func(p: Passenger) -> void: p.boredom = BoredomSim.MAX)
	assert_int(_icons(id)).is_equal(0)
	var at := ReferenceTerminal.offset_on(grid)
	var room := ShopTestLayout.AIRSIDE_ROOM
	_place(
		grid, &"kiosk_display", Vector2i(ShopTestLayout.DISPLAY_X + at.x, room.position.y + at.y)
	)
	assert_int(_icons(id)).is_equal(1)


func test_the_boredom_icon_shows_for_a_screen_stand_alone() -> void:
	var grid := BuildGrid.new()
	ToiletTestLayout.build(grid, 0)
	_start(grid)
	var id := _calm_passenger(func(p: Passenger) -> void: p.boredom = BoredomSim.MAX)
	assert_int(_icons(id)).is_equal(0)
	_place(grid, &"screen_stand", ShopTestLayout.AIRSIDE_CELL + ReferenceTerminal.offset_on(grid))
	assert_int(_icons(id)).is_equal(1)


func test_a_money_store_does_not_meet_boredom() -> void:
	# A store that sells for money does not relieve boredom (RoomType.
	# relieves_boredom), so it does not unhide the icon.
	var grid := BuildGrid.new()
	MoneyTestLayout.build(grid, &"exchange")
	_start(grid)
	var built := NeedIcons.provided(_world.sim)
	assert_bool(_world.sim.shops.layout.shops.is_empty()).is_false()
	assert_bool(built[NeedIcons.Need.BOREDOM]).is_false()


func test_a_need_not_named_is_not_gated() -> void:
	var p := Passenger.new()
	p.stage = Passenger.Stage.TO_SECURITY
	p.hunger = CafeSim.HUNGER_MAX
	p.toilet_need = ToiletSim.NEED_MAX
	p.boredom = BoredomSim.MAX
	var none := {
		NeedIcons.Need.HUNGER: false, NeedIcons.Need.TOILET: false, NeedIcons.Need.BOREDOM: false
	}
	assert_array(NeedIcons.shown(p, false, none)).is_empty()
	assert_array(NeedIcons.shown(p, false, {NeedIcons.Need.TOILET: false})).is_equal(
		[NeedIcons.Need.HUNGER, NeedIcons.Need.BOREDOM]
	)
	assert_array(NeedIcons.shown(p)).has_size(3)
