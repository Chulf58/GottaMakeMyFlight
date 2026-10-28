class_name TestStaffCharactersSync
extends GdUnitTestSuite
## Staff characters follow hires, fires, edits and loads: between ticks the
## next frame resyncs with no glide, nodes go back to their role's pool, and a
## member fired mid-service stays on its spot until the service ends, then
## walks out.

const CHECKIN := StaffMember.Role.CHECKIN
const SECURITY := StaffMember.Role.SECURITY
const LIMIT_TICKS := 1500

var _w: PassengerTestWorld
var _other: PassengerTestWorld
var _views: StaffCharacters


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_w = PassengerTestWorld.reference_world(5)
	_w.auto_staff = false
	_views = StaffCharacters.new()
	_views.clock = _w.clock
	_views.staff = _w.staff
	add_child(_views)


func after_test() -> void:
	_views.free()
	for world in [_w, _other]:
		if world != null:
			world.free_all()
	_other = null


func _in_service(world: PassengerTestWorld, station: int) -> bool:
	for id in world.sim.passenger_ids():
		var p := world.passenger(id)
		if p.station == station and p.stage == Passenger.Stage.CHECKIN:
			return true
	return false


func test_seating_and_firing_while_paused_show_on_the_next_frame() -> void:
	_w.clock.set_paused(true)
	var tick := _w.clock.tick
	assert_int(StaffTestKit.staff_all(_w.staff)).is_equal(4)
	assert_int(_views.active_count()).is_equal(0)
	_views._process(0.0)
	assert_int(_views.active_count()).is_equal(4)
	var desk: int = _w.sim.layout.desks[1]
	var id: int = _w.staff.staff_at(desk)
	assert_that(_views.node_for(id).position).is_equal(_views.post_position(desk))
	assert_bool(_w.staff.fire(CHECKIN)).is_true()
	assert_int(_w.staff.get_member(id).state).is_equal(StaffMember.State.WALKING_OUT)
	_w.clock.advance(SimClock.STEP * 3.0)
	_views._process(0.0)
	# Still drawn on its spot while paused, now with the walk clip.
	assert_int(_views.active_count()).is_equal(4)
	var node := _views.node_for(id)
	assert_that(node.position).is_equal(_views.post_position(desk))
	assert_str((node.get_node("AnimationPlayer") as AnimationPlayer).current_animation).is_equal(
		"walk"
	)
	assert_int(_w.clock.tick).is_equal(tick)


func test_a_fired_members_node_is_reused_by_the_next_hire_of_its_role() -> void:
	var first := _w.staff.hire(CHECKIN)
	_w.step()
	_w.step()
	var node := _views.node_for(first)
	assert_object(node).is_not_null()
	assert_bool(_w.staff.fire(CHECKIN)).is_true()
	while _w.staff.get_member(first) != null and _w.clock.tick < LIMIT_TICKS:
		_w.step()
	_views._process(0.0)
	assert_bool(node.visible).is_false()
	var officer := _w.staff.hire(SECURITY)
	var second := _w.staff.hire(CHECKIN)
	_w.step()
	_w.step()
	assert_object(_views.node_for(officer)).is_not_same(node)
	assert_object(_views.node_for(second)).is_same(node)
	assert_bool(node.visible).is_true()


func test_a_removed_station_moves_its_member_off_the_post_at_once() -> void:
	StaffTestKit.staff_all(_w.staff)
	_views._process(0.0)
	var desk: int = _w.sim.layout.desks[0]
	var m := _w.staff.get_member(_w.staff.staff_at(desk))
	assert_bool(_w.grid.apply(BuildEdit.remove_object(desk)).ok).is_true()
	assert_int(m.state).is_equal(StaffMember.State.IDLE)
	_views._process(0.0)
	var drawn := _views.node_for(m.id).position
	print("member %d drawn at %s, service cell %s" % [m.id, drawn, _w.staff.world_position(m)])
	assert_that(drawn).is_equal(_w.staff.world_position(m))
	assert_that(_views.tick_position(m.id, false)).is_equal(drawn)


func test_a_member_reloaded_under_the_same_id_with_another_role_gets_that_model() -> void:
	var agent := _w.staff.hire(CHECKIN)
	for i in 10:
		_w.step()
	assert_str(_views.node_for(agent).scene_file_path).is_equal(
		StaffCharacters.CHARACTERS[CHECKIN].resource_path
	)
	_other = PassengerTestWorld.reference_world(5)
	_other.auto_staff = false
	var officer := _other.staff.hire(SECURITY)
	for i in 10:
		_other.step()
	assert_int(officer).is_equal(agent)
	assert_bool(_w.staff.from_snapshot(_other.staff.to_snapshot())).is_true()
	_views._process(0.0)
	var node := _views.node_for(agent)
	assert_str(node.scene_file_path).is_equal(StaffCharacters.CHARACTERS[SECURITY].resource_path)


func test_a_load_followed_by_a_tick_before_the_frame_does_not_glide() -> void:
	var id := _w.staff.hire(CHECKIN)
	for i in 10:
		_w.step()
	_other = PassengerTestWorld.reference_world(5)
	_other.auto_staff = false
	assert_int(_other.staff.hire(CHECKIN)).is_equal(id)
	for i in 60:
		_other.step()
	var old := _views.tick_position(id, true)
	assert_bool(_w.staff.from_snapshot(_other.staff.to_snapshot())).is_true()
	_w.step()
	var now := _views.tick_position(id, true)
	print("drawn %s before the load, %s after" % [old, now])
	assert_float(old.distance_to(now)).is_greater(1.0)
	assert_that(_views.tick_position(id, false)).is_equal(now)


func test_a_member_fired_mid_service_stays_on_its_spot_until_it_walks_out() -> void:
	for i in 4:
		_w.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var m := _w.staff.get_member(_w.staff.hire(CHECKIN))
	while _w.clock.tick < LIMIT_TICKS:
		_w.step()
		if m.state == StaffMember.State.ON_DUTY and _in_service(_w, m.station):
			break
	assert_bool(_in_service(_w, m.station)).is_true()
	assert_bool(_w.staff.fire(CHECKIN)).is_true()
	assert_bool(m.leaving).is_true()
	_views._process(0.0)
	var node := _views.node_for(m.id)
	var post := _views.post_position(m.station)
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	var ticks := 0
	while m.leaving and ticks < LIMIT_TICKS:
		assert_that(node.position).is_equal(post)
		assert_str(player.current_animation).is_equal("idle")
		_w.step()
		_views.draw()
		ticks += 1
	print("left its spot %d ticks after being fired" % ticks)
	assert_int(ticks).is_greater(1)
	assert_int(m.state).is_equal(StaffMember.State.WALKING_OUT)
	var walked := 0
	while _w.staff.get_member(m.id) != null and ticks < LIMIT_TICKS:
		walked += int(player.current_animation == "walk")
		_w.step()
		_views.draw()
		ticks += 1
	print("walked out for %d ticks" % walked)
	assert_int(walked).is_greater(10)
	assert_object(_views.node_for(m.id)).is_null()
	assert_bool(node.visible).is_false()
	# It left inside the tick (staff_changed from _reconcile): that tick's sync
	# already showed it, so nothing is left to snap on the next frame.
	assert_bool(_views._dirty).is_false()
