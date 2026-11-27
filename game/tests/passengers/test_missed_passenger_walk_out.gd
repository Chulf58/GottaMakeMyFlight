class_name TestMissedPassengerWalkOut
extends GdUnitTestSuite
## Missed passengers keep instant MISSED accounting and release every hold,
## record a missed thought, pause briefly (~30 ticks) in dismay, then walk
## back out through the nearest entrance (even from airside across security)
## and down the outside sidewalk to the road before retiring, with a bounded
## no-route timeout and deterministic snapshot replay.

const SITE := preload("res://build/terminal_site.tres")
const TEST_OFFSET := Vector2i(85, 110)
const ENTRANCE_REL := Vector2i(16, 29)
const EXIT_REL := Vector2i(16, 0)
const DIVIDER_REL_Y := 14

var _world: PassengerTestWorld
var _twin: PassengerTestWorld
var _views: PassengerViews
var _site: SiteDefinition


func _test_site() -> SiteDefinition:
	if _site == null:
		_site = SITE.duplicate() as SiteDefinition
		_site.starter_offset = TEST_OFFSET
	return _site


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
		_views = null
	for w in [_world, _twin]:
		if w != null:
			w.free_all()
	_world = null
	_twin = null


func _make_site_world(boarding := 500, doors := 560, with_entrance := true) -> PassengerTestWorld:
	var grid := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	var off := TEST_OFFSET
	var edits: Array[BuildEdit] = []
	for y in range(0, 30):
		for x in range(12, 21):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y) + off, BuildGrid.FLOOR_TILE, 1))
	for x in range(12, 21):
		if x != 16:
			edits.append(
				BuildEdit.place_wall(Vector2i(x, DIVIDER_REL_Y) + off, BuildGrid.Side.NORTH)
			)
	grid.apply_batch(edits)
	if with_entrance:
		PassengerTestWorld.place(grid, &"entrance_door", ENTRANCE_REL + off, 2)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(13, 22) + off, 0)
	PassengerTestWorld.place(grid, &"security_scanner", Vector2i(16, DIVIDER_REL_Y - 1) + off, 0)
	PassengerTestWorld.place(grid, &"seat_row", Vector2i(13, 5) + off, 0)
	PassengerTestWorld.place(grid, &"exit_door", EXIT_REL + off, 0)
	EnclosureKit.close_floor(grid)
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(boarding, doors))
	world.sim.site = _test_site()
	return world


func test_pre_security_missed_passenger_pauses_walks_to_road_and_retires() -> void:
	_world = _make_site_world(400, 460)
	var outcomes: Array = []
	_world.sim.outcome.connect(func(pid: int, made: bool) -> void: outcomes.append([pid, made]))
	# Spawn early enough to walk in from the road, then close doors while pre-security inside.
	_world.run_to(250)
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	assert_int(id).is_greater(0)
	while p.stage != Passenger.Stage.CHECKIN_QUEUE and _world.clock.tick < 459:
		if p.stage == Passenger.Stage.TO_CHECKIN:
			break
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.TO_CHECKIN)
	assert_bool(p.cleared).is_false()

	_world.run_to(460)
	# Instant MISSED accounting and queue release.
	assert_int(p.stage).is_equal(Passenger.Stage.MISSED)
	assert_bool(p.is_done()).is_true()
	assert_int(_world.sim.missed_count()).is_equal(1)
	assert_array(outcomes).is_equal([[id, false]])
	assert_str(PassengerLifecycle.settled_leftovers(_world.sim, p)).is_equal("")
	var entries := PassengerThoughts.entries(p)
	assert_int(entries.size()).is_greater(0)
	assert_int(entries[0]["kind"]).is_equal(PassengerThoughts.Kind.MISSED_FLIGHT)
	assert_str(entries[0]["text"]).is_equal("Missed my flight!")
	assert_bool(entries[0]["positive"]).is_false()

	# Brief dismay pause (~30 ticks): holds position in place.
	var pause_pos := _world.sim.world_position(p)
	for _i in 29:
		_world.step()
		assert_object(_world.passenger(id)).is_not_null()
		assert_vector(_world.sim.world_position(p)).is_equal_approx(pause_pos, Vector3.ONE * 0.001)

	# Walks back to entrance, then down the outside sidewalk to the road, then retires cleanly.
	var saw_inside_walk := false
	var saw_outside_walk := false
	var entrance_cell := ENTRANCE_REL + TEST_OFFSET
	var max_z := pause_pos.z
	while _world.passenger(id) != null and _world.clock.tick < 1200:
		_world.step()
		if _world.passenger(id) == null:
			break
		var pos := _world.sim.world_position(p)
		if p.apron.is_empty() and p.is_moving():
			saw_inside_walk = true
		if not p.apron.is_empty() and p.apron_mm > 0:
			saw_outside_walk = true
			max_z = maxf(max_z, pos.z)
	assert_bool(saw_inside_walk).is_true()
	assert_bool(saw_outside_walk).is_true()
	assert_float(max_z).is_greater(_world.grid.cell_to_world(entrance_cell).z + 2.0)
	assert_float(max_z).is_equal_approx(SITE.road_z, 0.25)
	assert_object(_world.passenger(id)).is_null()
	assert_int(_world.sim.retire_refused).is_equal(0)


func test_cleared_airside_missed_passenger_walks_back_through_security_to_road() -> void:
	_world = _make_site_world(1600, 1700)
	_world.step()
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	while p.stage != Passenger.Stage.SEATED and _world.clock.tick < 1200:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SEATED)
	assert_bool(p.cleared).is_true()
	assert_int(p.seat_object).is_greater(0)

	# Keep passenger seated past doors close so they miss airside from their seat.
	p.boarding_tick = 1000000
	_world.run_to(1700)
	assert_int(p.stage).is_equal(Passenger.Stage.MISSED)
	assert_bool(p.is_done()).is_true()
	assert_int(p.seat_object).is_equal(0)
	assert_str(PassengerLifecycle.settled_leftovers(_world.sim, p)).is_equal("")

	var start_z := _world.sim.world_position(p).z
	var crossed_divider := false
	var reached_road := false
	var divider_world_z := _world.grid.cell_to_world(Vector2i(16, DIVIDER_REL_Y) + TEST_OFFSET).z
	while _world.passenger(id) != null and _world.clock.tick < 2600:
		_world.step()
		if _world.passenger(id) == null:
			break
		var pos := _world.sim.world_position(p)
		if pos.z > divider_world_z + 1.0:
			crossed_divider = true
		if pos.z >= SITE.road_z - 0.25:
			reached_road = true
	assert_float(start_z).is_less(divider_world_z)
	assert_bool(crossed_divider).is_true()
	assert_bool(reached_road).is_true()
	assert_object(_world.passenger(id)).is_null()
	assert_int(_world.sim.retire_refused).is_equal(0)


func test_no_route_missed_passenger_retires_after_bounded_timeout() -> void:
	_world = _make_site_world(400, 460)
	_world.run_to(250)
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	while p.stage != Passenger.Stage.TO_CHECKIN and _world.clock.tick < 459:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.TO_CHECKIN)
	# Remove the entrance door so there is no route out.
	var entrance_id := _world.sim.layout.entrances[0]
	_world.grid.check_staff_reach = false
	assert_bool(_world.grid.apply(BuildEdit.remove_object(entrance_id)).ok).is_true()
	_world.run_to(460)
	assert_int(p.stage).is_equal(Passenger.Stage.MISSED)
	assert_object(_world.passenger(id)).is_not_null()

	# Must remain during dismay pause, then retire cleanly within bounded timeout.
	_world.run_to(460 + 25)
	assert_object(_world.passenger(id)).is_not_null()
	_world.run_to(460 + 30 + PassengerSim.MISSED_NO_ROUTE_TIMEOUT_TICKS + 5)
	assert_object(_world.passenger(id)).is_null()
	assert_int(_world.sim.passenger_ids().size()).is_equal(0)
	assert_int(_world.sim.retire_refused).is_equal(0)


func test_passenger_views_keeps_missed_passenger_visible_calm_and_frees_on_retire() -> void:
	_world = _make_site_world(400, 460)
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	_world.run_to(250)
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	while p.stage != Passenger.Stage.TO_CHECKIN and _world.clock.tick < 459:
		_world.step()
	_world.run_to(460)
	_views.draw()

	var node := _views.node_for(id)
	assert_object(node).is_not_null()
	assert_bool(node.visible).is_true()
	assert_bool(_views.shows(p)).is_true()
	# Calm default view (5f3dbac4): unhovered bubble stays hidden.
	var bubble := node.get_node("Bubble") as Label3D
	assert_str(bubble.text).is_empty()
	assert_str(String(node.get_meta(&"clip", ""))).is_equal("idle")

	# After dismay pause, view stays visible and plays walk clip while walking out.
	_world.run_to(495)
	_views.draw()
	assert_object(_views.node_for(id)).is_same(node)
	assert_bool(node.visible).is_true()
	assert_str(String(node.get_meta(&"clip", ""))).is_equal("walk")

	while _world.passenger(id) != null and _world.clock.tick < 1200:
		_world.step()
	assert_object(_world.passenger(id)).is_null()
	assert_object(_views.node_for(id)).is_null()
	assert_int(_views.active_count()).is_equal(0)


func test_snapshot_mid_walk_out_replays_deterministically_and_rejects_old_version() -> void:
	_world = _make_site_world(400, 460)
	_world.run_to(250)
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	while p.stage != Passenger.Stage.TO_CHECKIN and _world.clock.tick < 459:
		_world.step()
	_world.run_to(495)
	assert_int(p.stage).is_equal(Passenger.Stage.MISSED)
	assert_int(p.missed_phase).is_equal(Passenger.MissedPhase.TO_ENTRANCE)
	assert_object(_world.passenger(id)).is_not_null()

	var saved: Dictionary = JSON.parse_string(JSON.stringify(_world.sim.to_snapshot()))
	_twin = _make_site_world(400, 460)
	var old_ver := saved.duplicate(true)
	old_ver["save_version"] = PassengerSim.SAVE_VERSION - 1
	assert_bool(_twin.sim.from_snapshot(old_ver)).is_false()
	assert_bool(_twin.sim.from_snapshot(saved)).is_true()
	_twin.clock.tick = _world.clock.tick

	var mismatch := -1
	while (
		(_world.passenger(id) != null or _twin.passenger(id) != null) and _world.clock.tick < 1200
	):
		_world.step()
		_twin.step()
		if _world.signature() != _twin.signature():
			mismatch = _world.clock.tick
			break
	assert_int(mismatch).is_equal(-1)
	assert_object(_world.passenger(id)).is_null()
	assert_object(_twin.passenger(id)).is_null()


func test_apron_return_walk_out_from_mid_apron_to_road() -> void:
	_world = _make_site_world(900, 1700)
	_world.step()
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	while not (p.stage == Passenger.Stage.APRON and p.apron_mm > 3000) and _world.clock.tick < 1690:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.APRON)
	assert_int(p.apron_mm).is_greater(3000)

	# Close flight doors while passenger is mid-apron walk to the plane.
	_world.flights.add_flight(
		"CLOSE_NOW", PassengerTestWorld.starts_with(10, _world.clock.tick + 1)
	)
	p.flight_id = "CLOSE_NOW"
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.MISSED)
	assert_int(p.missed_stage).is_equal(Passenger.Stage.APRON)
	assert_int(p.missed_phase).is_equal(Passenger.MissedPhase.PAUSE)

	var seen_phases := {}
	while _world.passenger(id) != null and _world.clock.tick < 3000:
		seen_phases[p.missed_phase] = true
		_world.step()
	assert_bool(seen_phases.has(Passenger.MissedPhase.APRON_RETURN)).is_true()
	assert_bool(seen_phases.has(Passenger.MissedPhase.TO_ENTRANCE)).is_true()
	assert_bool(seen_phases.has(Passenger.MissedPhase.TO_ROAD)).is_true()
	assert_object(_world.passenger(id)).is_null()
	assert_int(_world.sim.retire_refused).is_equal(0)


func test_graph_changed_replan_and_recovery_during_walk_out() -> void:
	_world = _make_site_world(1600, 1700)
	_world.step()
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	while p.stage != Passenger.Stage.SEATED and _world.clock.tick < 1200:
		_world.step()
	p.boarding_tick = 1000000
	_world.run_to(1700)
	_world.run_to(1735)
	assert_int(p.missed_phase).is_equal(Passenger.MissedPhase.TO_ENTRANCE)

	# Wall off the landside hall across y=20 so no path reaches the entrance.
	_world.grid.check_staff_reach = false
	var wall_edits: Array[BuildEdit] = []
	for x in range(12, 21):
		wall_edits.append(BuildEdit.place_wall(Vector2i(x, 20) + TEST_OFFSET, BuildGrid.Side.NORTH))
	for res in _world.grid.apply_batch(wall_edits):
		assert_bool(res.ok).is_true()
	for _i in 40:
		_world.step()
		if p.missed_phase == Passenger.MissedPhase.STUCK_WAIT:
			break
	assert_int(p.missed_phase).is_equal(Passenger.MissedPhase.STUCK_WAIT)

	# Reopen one cell before no-route timeout expires: recovers to TO_ENTRANCE -> retire.
	(
		assert_bool(
			(
				_world
				. grid
				. apply(BuildEdit.remove_wall(Vector2i(16, 20) + TEST_OFFSET, BuildGrid.Side.NORTH))
				. ok
			)
		)
		. is_true()
	)
	_world.step()
	assert_int(p.missed_phase).is_equal(Passenger.MissedPhase.TO_ENTRANCE)
	while _world.passenger(id) != null and _world.clock.tick < 2800:
		_world.step()
	assert_object(_world.passenger(id)).is_null()
	assert_int(_world.sim.retire_refused).is_equal(0)


func test_malformed_missed_phase_and_save_game_v43_rejected() -> void:
	_world = _make_site_world(400, 460)
	_world.run_to(250)
	var missed_id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	while (
		_world.passenger(missed_id).stage != Passenger.Stage.TO_CHECKIN and _world.clock.tick < 459
	):
		_world.step()
	_world.run_to(495)
	assert_int(_world.passenger(missed_id).stage).is_equal(Passenger.Stage.MISSED)

	var saved: Dictionary = JSON.parse_string(JSON.stringify(_world.sim.to_snapshot()))
	# Add a live non-MISSED passenger record by cloning an earlier active snapshot.
	_twin = _make_site_world(900, 1200)
	_twin.run_to(250)
	var live_id := _twin.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_twin.step()
	var live_saved: Dictionary = JSON.parse_string(JSON.stringify(_twin.sim.to_snapshot()))
	var before_sig := _twin.signature()

	for bad_phase in [-1, 99]:
		var bad := saved.duplicate(true)
		bad["passengers"][0]["missed_phase"] = bad_phase
		assert_bool(_twin.sim.from_snapshot(bad)).is_false()
		assert_str(_twin.signature()).is_equal(before_sig)

	var bad_live := live_saved.duplicate(true)
	assert_int(int(bad_live["passengers"][0]["id"])).is_equal(live_id)
	assert_int(int(bad_live["passengers"][0]["stage"])).is_not_equal(Passenger.Stage.MISSED)
	bad_live["passengers"][0]["missed_phase"] = Passenger.MissedPhase.TO_ENTRANCE
	assert_bool(_twin.sim.from_snapshot(bad_live)).is_false()
	assert_str(_twin.signature()).is_equal(before_sig)

	# Whole-world SaveGame rejects v43.
	var main := SaveTestKit.boot(self, 123)
	var sg := SaveTestKit.save_game(main)
	var world_snap: Dictionary = JSON.parse_string(JSON.stringify(sg.snapshot()))
	assert_int(int(world_snap["save_version"])).is_equal(SaveGame.SAVE_VERSION)
	var v43 := world_snap.duplicate(true)
	v43["save_version"] = 43
	assert_bool(sg.load_world(v43)).is_false()
	assert_str(sg.message_text()).contains("older version")
	main.free()


func test_missed_max_walk_out_ticks_forces_retirement() -> void:
	_world = _make_site_world(400, 460)
	_world.run_to(250)
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	while p.stage != Passenger.Stage.TO_CHECKIN and _world.clock.tick < 459:
		_world.step()
	_world.run_to(495)
	assert_int(p.missed_phase).is_equal(Passenger.MissedPhase.TO_ENTRANCE)
	p.outcome_tick = _world.clock.tick - PassengerSim.MISSED_MAX_WALK_OUT_TICKS + 2
	_world.step()
	assert_object(_world.passenger(id)).is_not_null()
	_world.step()
	assert_object(_world.passenger(id)).is_null()
	assert_int(_world.sim.retire_refused).is_equal(0)
