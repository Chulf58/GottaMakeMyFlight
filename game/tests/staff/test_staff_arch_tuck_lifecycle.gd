class_name TestStaffArchTuckLifecycle
extends GdUnitTestSuite
## A drawn member's arch tuck (StaffCharacters with StaffArchTuck) through a
## load, a release to the pool and a role change: a load starts the tuck over
## from the loaded world, a body let go mid-arch goes back to the pool with its
## arms off, and the next member drawn with it starts settled. Each case
## changes the world (hires, loads), so each builds its own; a build is a few
## milliseconds.

var _w: PassengerTestWorld
var _views: StaffCharacters
var _arch := 0


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var built := LaneStaffWorld.two_lanes()
	_arch = built[1]
	_w = PassengerTestWorld.make(built[0], PassengerTestWorld.starts_with(3000, 6000), 7)
	_w.auto_staff = false
	# Both lanes' primaries on duty, so no vacancy recalls the walking helper.
	StaffTestKit.staff_all(_w.staff)
	_views = StaffCharacters.new()
	_views.clock = _w.clock
	_views.staff = _w.staff
	add_child(_views)


func after_test() -> void:
	_views.free()
	_w.free_all()


## Steps until `done` holds (at most 200 ticks), drawing each tick.
func _step_until(done: Callable) -> bool:
	for i in 200:
		if done.call():
			return true
		_w.step()
		_views.draw()
	return done.call()


## Steps member `id` into the arch cell, fully tucked.
func _into_the_arch(id: int) -> void:
	var arch: Vector2i = LaneStaffWorld.lane_of(_w, _arch)["arch"]
	var m := _w.staff.get_member(id)
	var tucked := func() -> bool: return m.at == arch and _views.tuck_of(id) >= 1.0
	assert_bool(_step_until(tucked)).is_true()


## The drawn weights of `body`'s tuck arms: front_weight when active, else 0.
func _arm_weights(body: Node3D) -> Array:
	var out := []
	for arm: CarryArm in StaffArchTuck.arms_of(body):
		out.append(arm.front_weight if arm.active else 0.0)
	return out


## The snapshots a save holds for the clock and the staff, through JSON.
func _save() -> Array:
	return [
		JSON.parse_string(JSON.stringify(_w.clock.to_snapshot())),
		JSON.parse_string(JSON.stringify(_w.staff.to_snapshot())),
	]


func _load(saved: Array) -> void:
	assert_bool(_w.clock.from_snapshot(saved[0])).is_true()
	assert_bool(_w.staff.from_snapshot(saved[1])).is_true()
	_views.sync(true)
	_views.draw()


func test_a_load_back_to_before_the_arch_draws_the_member_untucked() -> void:
	var id := LaneStaffWorld.send_through_arch(_w, _arch)
	_views.sync(true)
	var saved := _save()
	var m := _w.staff.get_member(id)
	assert_bool(_step_until(func() -> bool: return m.state == StaffMember.State.ON_DUTY)).is_true()
	print("on duty at tick %d" % _w.clock.tick)
	_load(saved)
	var body := _views.node_for(id)
	var loaded := _w.staff.get_member(id)
	var rows := [[_w.clock.tick, _views.tuck_of(id), _arm_weights(body)]]
	for i in 3:
		_w.step()
		_views.draw()
		rows.append([_w.clock.tick, _views.tuck_of(id), _arm_weights(body)])
	var inside := StaffArchTuck.in_arch_passage(_w.grid, loaded)
	print("loaded at %s, in passage %s: %s" % [loaded.at, inside, rows])
	assert_bool(inside).is_false()
	for row: Array in rows:
		assert_float(row[1]).is_equal(0.0)
		assert_array(row[2]).is_equal([0.0, 0.0])


func test_a_body_let_go_mid_arch_goes_to_the_pool_untucked_and_starts_the_next_settled() -> void:
	var before_hire := _save()
	var id := LaneStaffWorld.send_through_arch(_w, _arch)
	_views.sync(true)
	_into_the_arch(id)
	var body := _views.node_for(id)
	var tucked := _arm_weights(body)
	# Loading the save from before the hire takes the member off the floor.
	_load(before_hire)
	var pooled := _arm_weights(body)
	print("tucked %s, pooled %s, visible %s" % [tucked, pooled, body.visible])
	assert_array(tucked).is_equal([1.0, 1.0])
	assert_object(_views.node_for(id)).is_null()
	assert_bool(body.visible).is_false()
	assert_array(pooled).is_equal([0.0, 0.0])
	# The next officer drawn takes the same body, outside the arch: swinging.
	var next := LaneStaffWorld.send_through_arch(_w, _arch)
	_views.sync()
	_views.draw()
	print("next member %d drawn with the same body: %s" % [next, _views.node_for(next) == body])
	assert_object(_views.node_for(next)).is_same(body)
	assert_float(_views.tuck_of(next)).is_equal(0.0)
	assert_array(_arm_weights(body)).is_equal([0.0, 0.0])


func test_a_role_change_mid_arch_lets_the_body_go_and_draws_the_new_one_settled() -> void:
	var id := LaneStaffWorld.send_through_arch(_w, _arch)
	_views.sync(true)
	_into_the_arch(id)
	var old := _views.node_for(id)
	_w.staff.get_member(id).role = StaffMember.Role.CHECKIN
	_views.sync()
	_views.draw()
	var fresh := _views.node_for(id)
	print(
		(
			"old body arms %s, new body arms %s, tuck %f"
			% [_arm_weights(old), _arm_weights(fresh), _views.tuck_of(id)]
		)
	)
	assert_object(fresh).is_not_same(old)
	assert_array(_arm_weights(old)).is_equal([0.0, 0.0])
	# Still in the arch: the new body is drawn tucked at once, with no turn.
	assert_float(_views.tuck_of(id)).is_equal(1.0)
	assert_array(_arm_weights(fresh)).is_equal([1.0, 1.0])
