class_name TestNeedIconSeatedViews
extends GdUnitTestSuite
## The seated icon anchor (NeedIcons.head_anchor, board bd08ed8e) is set by the
## real PassengerViews, not by hand: a passenger settled on a gate chair or a
## lounge sofa gets it; standing up, walking, the upright shower and a released
## and reused node get the standing anchor. The node meta &"seated" keeps its
## wider turn-lock meaning (standing up and the shower still carry it, the
## control that the icon anchor is a narrower signal).

const STANDING := Vector3(0.0, NeedIcons.LIFT_M, 0.0)

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


func _open_views() -> void:
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)


## A passenger put on the first gate chair of the reference terminal by hand
## (as the sim seats one), the views drawing.
func _sitter() -> Passenger:
	_world = PassengerTestWorld.reference_world()
	_world.run_to(10)
	_open_views()
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.cleared = true
	var seat: Dictionary = _world.sim.layout.seats[0]
	p.seat_object = seat["object_id"]
	p.seat_cell = seat["cell"]
	p.seat_front = seat["front"]
	p.at = seat["front"]
	p.clear_path()
	_stage(p, Passenger.Stage.SEATED)
	return p


func _stage(p: Passenger, stage: Passenger.Stage) -> Node3D:
	p.stage = stage
	p.stage_tick = _world.sim.tick
	_views.sync()
	return _views.node_for(p.id)


func test_a_passenger_settled_on_a_gate_chair_gets_the_seated_anchor() -> void:
	var p := _sitter()
	var node := _views.node_for(p.id)
	assert_bool(node.get_meta(&"icon_seated", false)).is_true()
	assert_vector(NeedIcons.head_anchor(node)).is_equal_approx(
		Vector3(0.0, NeedIcons.SEATED_LIFT_M, -NeedIcons.SEATED_BACK_M), Vector3.ONE * 0.0001
	)


func test_standing_up_and_walking_get_the_standing_anchor() -> void:
	var p := _sitter()
	var node := _stage(p, Passenger.Stage.STANDING_UP)
	# The turn lock still holds while standing up; the icon anchor does not.
	assert_bool(node.get_meta(&"seated", false)).is_true()
	assert_bool(node.get_meta(&"icon_seated", true)).is_false()
	assert_vector(NeedIcons.head_anchor(node)).is_equal(STANDING)
	node = _stage(p, Passenger.Stage.TO_GATE)
	assert_bool(node.get_meta(&"seated", true)).is_false()
	assert_vector(NeedIcons.head_anchor(node)).is_equal(STANDING)
	# And back on the chair the seated anchor returns (the control).
	node = _stage(p, Passenger.Stage.SEATED)
	assert_bool(node.get_meta(&"icon_seated", false)).is_true()


func test_a_released_and_reused_node_starts_with_the_standing_anchor() -> void:
	var p := _sitter()
	var node := _views.node_for(p.id)
	assert_bool(node.get_meta(&"icon_seated", false)).is_true()
	_views._release(p.id)
	assert_bool(node.get_meta(&"icon_seated", true)).is_false()
	assert_vector(NeedIcons.head_anchor(node)).is_equal(STANDING)
	# The same passenger, now walking, takes the pooled node back (the only free
	# node of its body) and draws it with the standing anchor.
	var reused := _stage(p, Passenger.Stage.TO_GATE)
	assert_object(reused).is_same(node)
	assert_vector(NeedIcons.head_anchor(reused)).is_equal(STANDING)


## The lounge sofa seats its visitor (the control: an activity world engages the
## seated anchor); the shower's upright visitor carries the turn lock but keeps
## the standing anchor.
func test_a_sofa_sitter_is_seated_and_a_shower_guest_is_not() -> void:
	var want := {&"lounge": true, &"shower": false}
	for type: StringName in want:
		var grid := BuildGrid.new()
		ActivityTestLayout.build(grid, type)
		_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
		_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
		_world.auto_staff_roles = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]
		_world.run_to(10)
		_open_views()
		var p := ShopTestLayout.airside_guest(_world, 80, ShopTestLayout.AIRSIDE_CELL)
		assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
		while p.stage != Passenger.Stage.SHOP_BROWSE and _world.clock.tick < 3000:
			_world.step()
		assert_int(p.stage).is_equal(Passenger.Stage.SHOP_BROWSE)
		_world.run_to(_world.clock.tick + 60)
		var node := _views.node_for(p.id)
		assert_bool(node.get_meta(&"seated", false)).override_failure_message(str(type)).is_true()
		(
			assert_bool(node.get_meta(&"icon_seated", false))
			. override_failure_message(str(type))
			. is_equal(want[type])
		)
		if not want[type]:
			assert_vector(NeedIcons.head_anchor(node)).is_equal(STANDING)
		_views.free()
		_views = null
		_world.free_all()
		_world = null
