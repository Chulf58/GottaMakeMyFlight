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
