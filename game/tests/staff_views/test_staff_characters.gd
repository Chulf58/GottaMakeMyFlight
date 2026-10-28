class_name TestStaffCharacters
extends GdUnitTestSuite
## Staff are drawn with their role's model: walking with the walk clip while
## they head to a station, idle on duty on the station's staff spot facing the
## passenger side, and between ticks with the clock's alpha.

const CHECKIN := StaffMember.Role.CHECKIN
const SECURITY := StaffMember.Role.SECURITY
const LIMIT_TICKS := 600

var _w: PassengerTestWorld
var _views: StaffCharacters
var _ids: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_w = PassengerTestWorld.reference_world()
	_w.auto_staff = false
	_ids = ReferenceTerminal.object_ids(_w.grid)
	_views = _make_views(_w)


func after_test() -> void:
	_views.free()
	_w.free_all()


func _make_views(world: PassengerTestWorld) -> StaffCharacters:
	var views := StaffCharacters.new()
	views.clock = world.clock
	views.staff = world.staff
	add_child(views)
	return views


## Steps until the member is on duty; returns the ticks it took, or -1.
func _until_on_duty(m: StaffMember) -> int:
	var start := _w.clock.tick
	while _w.clock.tick - start < LIMIT_TICKS:
		_w.step()
		if m.state == StaffMember.State.ON_DUTY:
			return _w.clock.tick - start
	return -1


func _clip(node: Node3D) -> String:
	return (node.get_node("AnimationPlayer") as AnimationPlayer).current_animation


func test_a_hired_agent_is_drawn_once_it_leaves_the_pool_and_walks() -> void:
	var id := _w.staff.hire(CHECKIN)
	_views._process(0.0)
	assert_bool(_w.staff.get_member(id).in_pool()).is_true()
	assert_int(_views.active_count()).is_equal(0)
	_w.step()
	_w.step()
	var node := _views.node_for(id)
	assert_object(node).is_not_null()
	assert_str(node.scene_file_path).is_equal(StaffCharacters.CHARACTERS[CHECKIN].resource_path)
	assert_str(_clip(node)).is_equal("walk")
	var moved := _views.tick_position(id, false).distance_to(_views.tick_position(id, true))
	print("agent moved %.3f m in one tick" % moved)
	assert_float(moved).is_greater(0.05)


func test_staff_models_are_not_passenger_models() -> void:
	for scene in StaffCharacters.CHARACTERS:
		for passenger_scene in PassengerViews.CHARACTERS:
			assert_str(scene.resource_path).is_not_equal(passenger_scene.resource_path)
	assert_str(StaffCharacters.CHARACTERS[CHECKIN].resource_path).is_not_equal(
		StaffCharacters.CHARACTERS[SECURITY].resource_path
	)


func test_an_agent_walks_onto_the_spot_behind_the_counter_with_no_jump() -> void:
	var m := _w.staff.get_member(_w.staff.hire(CHECKIN))
	var ticks := _until_on_duty(m)
	assert_int(ticks).is_greater(0)
	var desk := m.station
	var post := _views.post_position(desk)
	var service := _w.grid.cell_to_world(_w.sim.layout.lanes[desk][0])
	var front_2d := TerminalLayout.front_of(_w.grid.get_object(desk)["facing"])
	var front := Vector3(front_2d.x, 0.0, front_2d.y)
	var before := _views.tick_position(m.id, false)
	print(
		(
			"desk %d spot %s service cell %s, arrived from %s after %d ticks"
			% [desk, post, service, before, ticks]
		)
	)
	assert_that(post).is_equal(_w.grid.cell_to_world(StaffSpots.spot_of(_w.grid, desk)))
	# On the arrival tick the agent is drawn on the spot, one walking step on
	# from the tick before: no jump onto it.
	assert_that(_views.tick_position(m.id, true)).is_equal(post)
	assert_float(before.distance_to(post)).is_greater(0.0)
	assert_float(before.distance_to(post)).is_less_equal(PassengerSim.WALK_MM / 1000.0 + 0.0001)
	assert_float((post - service).dot(front)).is_less(-1.5)
	var node := _views.node_for(m.id)
	assert_str(_clip(node)).is_equal("idle")
	assert_float(node.rotation.y).is_equal_approx(atan2(front.x, front.z), 0.0001)


func test_a_scanner_officer_stands_beside_the_arch_facing_the_lane() -> void:
	var m := _w.staff.get_member(_w.staff.hire(SECURITY))
	assert_int(_until_on_duty(m)).is_greater(0)
	var scanner := m.station
	assert_bool((_ids["scanners"] as Array).has(scanner)).is_true()
	var expected := _w.grid.cell_to_world(StaffSpots.spot_of(_w.grid, scanner))
	# One tick standing on the spot, so the drawn position no longer blends in
	# the last step onto it.
	_w.step()
	_views.draw()
	var node := _views.node_for(m.id)
	print("scanner %d officer at %s" % [scanner, node.position])
	assert_float(node.position.distance_to(expected)).is_less(0.0001)
	assert_str(node.scene_file_path).is_equal(StaffCharacters.CHARACTERS[SECURITY].resource_path)
	assert_str(_clip(node)).is_equal("idle")
	assert_float(node.rotation.y).is_equal_approx(_views.post_yaw(scanner), 0.0001)


func test_a_walker_keeps_interpolating_on_the_tick_another_goes_on_duty() -> void:
	var a := _w.staff.get_member(_w.staff.hire(CHECKIN))
	var b := _w.staff.get_member(_w.staff.hire(CHECKIN))
	var start := _w.clock.tick
	while (
		a.state != StaffMember.State.ON_DUTY
		and b.state != StaffMember.State.ON_DUTY
		and _w.clock.tick - start < LIMIT_TICKS
	):
		_w.step()
	var arrived := a if a.state == StaffMember.State.ON_DUTY else b
	var walker := b if arrived == a else a
	assert_int(arrived.state).is_equal(StaffMember.State.ON_DUTY)
	assert_int(walker.state).is_equal(StaffMember.State.TO_STATION)
	var before := _views.tick_position(walker.id, false)
	var after := _views.tick_position(walker.id, true)
	# The next frame, half a tick on: nothing left over from the arrival may
	# snap the walker; it is drawn halfway along its step.
	_w.clock.advance(SimClock.STEP * 0.5)
	_views._process(0.016)
	var drawn := _views.node_for(walker.id).position
	print(
		(
			"member %d on duty; member %d moved %.3f m that tick, drawn %s"
			% [arrived.id, walker.id, before.distance_to(after), drawn]
		)
	)
	assert_float(before.distance_to(after)).is_greater(0.05)
	assert_float(drawn.distance_to(before.lerp(after, 0.5))).is_less(0.001)


func test_drawn_position_interpolates_with_the_clock_alpha() -> void:
	var id := _w.staff.hire(CHECKIN)
	for i in 5:
		_w.step()
	var before := _views.tick_position(id, false)
	var after := _views.tick_position(id, true)
	assert_float(before.distance_to(after)).is_greater(0.05)
	_w.clock.advance(SimClock.STEP * 0.5)
	assert_float(_w.clock.alpha).is_equal_approx(0.5, 0.001)
	_views.draw()
	assert_float(_views.node_for(id).position.distance_to(before.lerp(after, 0.5))).is_less(0.001)


func test_walk_clip_speed_follows_the_clock_speed_and_stops_when_paused() -> void:
	var id := _w.staff.hire(SECURITY)
	_w.step()
	_w.step()
	var player := _views.node_for(id).get_node("AnimationPlayer") as AnimationPlayer
	var base := (
		(PassengerSim.WALK_MM * SimClock.TICK_RATE / 1000.0)
		/ StaffCharacters.CLIP_WALK_MPS[SECURITY]
	)
	_views.draw()
	assert_float(player.speed_scale).is_equal_approx(base, 0.0001)
	_w.clock.set_speed(3)
	_views.draw()
	assert_float(player.speed_scale).is_equal_approx(base * 3.0, 0.0001)
	_w.clock.set_paused(true)
	_views.draw()
	assert_float(player.speed_scale).is_equal(0.0)


func test_drawing_never_changes_the_sim() -> void:
	_w.staff.hire(CHECKIN)
	_w.staff.hire(SECURITY)
	for i in 30:
		_w.step()
	var staff_before := JSON.stringify(_w.staff.to_snapshot())
	var sim_before := JSON.stringify(_w.sim.to_snapshot())
	for i in 5:
		_views.sync()
		_views.sync(true)
		_views._process(0.016)
		_views.draw()
	assert_str(JSON.stringify(_w.staff.to_snapshot())).is_equal(staff_before)
	assert_str(JSON.stringify(_w.sim.to_snapshot())).is_equal(sim_before)
	assert_int(_views.active_count()).is_equal(2)


func test_desk_spots_turn_with_the_desk_in_all_four_facings() -> void:
	for facing in 4:
		var grid := PassengerTestWorld.floored(Vector2i(12, 12))
		PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 11), 3)
		var desk := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(5, 5), facing)
		var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(30, 40))
		world.auto_staff = false
		var views := _make_views(world)
		assert_int(StaffTestKit.staff_all(world.staff)).is_equal(1)
		views.sync(true)
		var id: int = world.staff.staff_at(desk)
		var front_2d := TerminalLayout.front_of(facing)
		var front := Vector3(front_2d.x, 0.0, front_2d.y)
		# The counter is the anchor cell; the spot is the cell behind it.
		var expected := grid.cell_to_world(Vector2i(5, 5) - front_2d)
		var drawn := views.tick_position(id, true)
		print("facing %d post %s expected %s" % [facing, drawn, expected])
		assert_float(drawn.distance_to(expected)).is_less(0.0001)
		var yaw := views.node_for(id).rotation.y
		assert_float(Vector3(sin(yaw), 0.0, cos(yaw)).distance_to(front)).is_less(0.0001)
		views.free()
		world.free_all()
