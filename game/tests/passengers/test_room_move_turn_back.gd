class_name TestRoomMoveTurnBack
extends GdUnitTestSuite
## An activity visitor whose piece moves while the start of its stay is still
## under way turns that start back from where it had reached (board 23ddd6bc;
## decision move-rooms-technical-design-roommove-plan-of-existing-edits, parts
## 4 to 6; as CafeSim turns a sit-down back): a sofa sitter stands up for as
## long as it had been sitting down, a nap pod sitter leans forward for as long
## as it had leant back, a showering visitor steps out for as long as it had
## been stepping in. The drawn body never moves further onto the seat or into
## the shower first. ActivityTestLayout's piece stands at x 22, y 3 and is
## moved to x 25; the drawn position is the one PassengerViews records each
## tick (tick_position()).

const MOVED_TO := Vector2i(25, 3)
## How much nearer the seat a drawn body may come on one tick of the exit:
## float noise only.
const NEARER_M := 0.0005

var _world: PassengerTestWorld
var _views: PassengerViews
var _ids: Dictionary


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


func _make(type: StringName) -> void:
	var grid := BuildGrid.new()
	_ids = ActivityTestLayout.build(grid, type)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	# The room is self-service: no staff are needed.
	_world.auto_staff_roles = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	_world.run_to(10)


## A bored airside passenger with `bags` carry-on bags, run until it stays at
## the room's piece and then `spent` ticks more.
func _visitor_at(spent: int, bags := 0) -> Passenger:
	var p := ShopTestLayout.airside_guest(_world, 80)
	p.mood = 50
	p.carry_on = bags
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
	var until := _world.clock.tick + 1500
	while p.stage != Passenger.Stage.SHOP_BROWSE and _world.clock.tick < until:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_BROWSE)
	for i in spent:
		_world.step()
	return p


## The ground distance from the drawn body of `p` to `spot`.
func _away(p: Passenger, spot: Vector3) -> float:
	var at := _views.tick_position(p.id, true)
	return Vector2(at.x, at.z).distance_to(Vector2(spot.x, spot.z))


## Steps until `p` walks off from the old piece, failing when its drawn body
## comes nearer `spot` than it was on the tick before (the message names the
## tick). Returns the ticks the exit took from the move's tick on.
func _leave_without_nearing(p: Passenger, spot: Vector3, moved_at: int) -> int:
	var last := _away(p, spot)
	var worst := 0.0
	var where := ""
	var until := _world.clock.tick + 200
	while p.stage == Passenger.Stage.SHOP_BROWSE and _world.clock.tick < until:
		_world.step()
		var now := _away(p, spot)
		if last - now > worst:
			worst = last - now
			where = "tick %d: %.3f m nearer the seat" % [_world.clock.tick, worst]
		last = now
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_WALK)
	assert_float(worst).override_failure_message(where).is_less(NEARER_M)
	return _world.clock.tick - moved_at


## A sofa visitor `settle` ticks into its sit-down when the sofa moves.
func _sofa_turn_back(settle: int) -> void:
	_make(&"lounge")
	var p := _visitor_at(settle)
	assert_int(ActivityPoses.pose(_world.sim, p)).is_equal(StageKinds.Pose.SITTING_DOWN)
	var seat := ActivityPoses.stay_frame(_world.sim, p).origin
	# The sit-down's ticks on the tick the move is seen.
	var spent := _world.clock.tick + 1 - p.stage_tick
	var before_move := _away(p, seat)
	ShopMoveKit.move_piece(_world, _ids["use"], MOVED_TO)
	_world.step()
	var moved_at := _world.clock.tick
	assert_bool(_world.sim.shops.visit_of(p.id).relocation.exiting).is_true()
	assert_float(before_move - _away(p, seat)).is_less(NEARER_M)
	# It stands up from where the sit-down had reached, not from seated.
	assert_int(ActivityPoses.pose(_world.sim, p)).is_equal(StageKinds.Pose.STANDING_UP)
	assert_int(ActivityPoses.clip_ticks(_world.sim, p)).is_equal(
		PassengerSim.STAND_UP_TICKS - spent
	)
	# Getting up takes as long as sitting down took.
	assert_int(_leave_without_nearing(p, seat, moved_at)).is_equal(spent)


func test_a_sofa_visitor_moved_5_ticks_into_its_sit_down_stands_up_from_there() -> void:
	_sofa_turn_back(5)


func test_a_sofa_visitor_moved_18_ticks_into_its_sit_down_stands_up_from_there() -> void:
	_sofa_turn_back(18)


func test_a_nap_pod_sitter_moved_while_leaning_back_leans_forward_from_there() -> void:
	_make(&"nap_pod")
	# 8 ticks into the lean back (SIT_DOWN_TICKS 24, then EASE_TICKS 20).
	var p := _visitor_at(PassengerSim.SIT_DOWN_TICKS + 8)
	var lean := ActivityPoses.recline(_world.sim, p)
	assert_float(lean).is_greater(0.0)
	assert_float(lean).is_less(0.5)
	var leaning := _world.clock.tick + 1 - p.stage_tick - PassengerSim.SIT_DOWN_TICKS
	ShopMoveKit.move_piece(_world, _ids["use"], MOVED_TO)
	_world.step()
	var moved_at := _world.clock.tick
	# The lean goes on from where it was: no jump to a full lean.
	assert_float(ActivityPoses.recline(_world.sim, p)).is_less_equal(lean)
	assert_int(ActivityPoses.pose(_world.sim, p)).is_equal(StageKinds.Pose.SEATED)
	var seat := ActivityPoses.stay_frame(_world.sim, p).origin
	var ticks := _leave_without_nearing(p, seat, moved_at)
	assert_int(ticks).is_equal(leaning + PassengerSim.STAND_UP_TICKS)


func test_a_showering_visitor_moved_while_stepping_in_steps_out_from_there() -> void:
	_make(&"shower")
	var p := _visitor_at(6)
	assert_float(ActivityPoses.share(_world.sim, p)).is_less(1.0)
	var tray := ActivityPoses.stay_frame(_world.sim, p).origin
	var foam := ActivityPoses.foam(_world.sim, p)
	var spent := _world.clock.tick + 1 - p.stage_tick
	ShopMoveKit.move_piece(_world, _ids["use"], MOVED_TO)
	_world.step()
	var moved_at := _world.clock.tick
	assert_float(ActivityPoses.foam(_world.sim, p)).is_less_equal(foam)
	assert_int(_leave_without_nearing(p, tray, moved_at)).is_equal(spent)


## Control for the wait at the door: a showering visitor with bags, moved
## while it still stands at the door setting them down, picks them up there
## and never steps into the cubicle.
func test_a_showering_visitor_with_bags_moved_at_the_door_never_steps_in() -> void:
	_make(&"shower")
	var p := _visitor_at(5, 1)
	assert_float(ActivityPoses.share(_world.sim, p)).is_equal(0.0)
	var tray := ActivityPoses.stay_frame(_world.sim, p).origin
	ShopMoveKit.move_piece(_world, _ids["use"], MOVED_TO)
	_world.step()
	var moved_at := _world.clock.tick
	assert_float(ActivityPoses.share(_world.sim, p)).is_equal(0.0)
	assert_bool(ActivityPoses.bags_down(_world.sim, p)).is_false()
	var ticks := _leave_without_nearing(p, tray, moved_at)
	assert_int(ticks).is_equal(ActivityPoses.DOOR_OUT_TICKS)
