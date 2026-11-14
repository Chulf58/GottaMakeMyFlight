class_name TestEntranceLineFacing
extends GdUnitTestSuite
## Passengers standing in the line outside the entrance face the door, the way
## the line moves, not the direction of the step that brought them to their
## place (board 814a5cfd, decision entrance-waiting-line-as-built-16-places-
## beside-the-walk-in).

const WAITERS := 8
const EPS := 0.01

var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
	if _world != null:
		_world.free_all()
	_views = null
	_world = null


func _open_views() -> void:
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)


func _standing(p: Passenger) -> bool:
	return p.stage == Passenger.Stage.SPAWNED and p.apron_mm >= p.apron_total_mm()


func test_standing_waiters_face_the_door_not_their_last_step() -> void:
	_world = TestEntranceLine._full_hall()
	_open_views()
	var sim := _world.sim
	var ids := TestEntranceLine._arrive(_world, WAITERS)
	for i in 400:
		_world.step()
		if ids.all(func(id: int) -> bool: return _standing(_world.passenger(id))):
			break
	for i in PassengerTurns.TURN_TICKS * 2:
		_world.step()
	_views.draw()
	var out := Vector2(sim.layout.door_outward(sim.grid, sim.layout.passenger_entrances[0]))
	var want := atan2(-out.x, -out.y)
	var standing := 0
	var wrong := 0
	for id in ids:
		var p := _world.passenger(id)
		if not _standing(p):
			continue
		standing += 1
		var yaw := _views.node_for(id).rotation.y
		var step := _views.tick_position(id, true) - _views.tick_position(id, false)
		if absf(angle_difference(yaw, want)) > EPS:
			wrong += 1
		print("waiter %d yaw %.3f want %.3f step %s" % [id, yaw, want, step])
	prints("standing", standing, "wrong", wrong, "door out", out)
	# Control: the line formed and its members stood on their places.
	assert_int(standing).is_equal(WAITERS)
	assert_int(sim.entrance.order.size()).is_equal(WAITERS)
	assert_int(wrong).is_equal(0)


## Control: an admitted arrival (it holds a claim, it is not in the line) has
## no line facing, so it keeps facing its walk in.
func test_an_admitted_arrival_has_no_line_facing() -> void:
	_world = HoldLineKit.desk_hall()
	_world.step()
	var ids := TestEntranceLine._arrive(_world, 1)
	var sim := _world.sim
	assert_bool(sim.entrance.has_claim(ids[0])).is_true()
	assert_bool(sim.entrance.waiting(ids[0])).is_false()
	assert_vector(EntranceLooks.face(sim, _world.passenger(ids[0]))).is_equal(Vector2.ZERO)
