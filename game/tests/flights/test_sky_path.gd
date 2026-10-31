class_name TestSkyPath
extends GdUnitTestSuite
## The plane's sky path around each flight on main.tscn's real layout: a
## lead-in before APPROACH and a climb-out after DEPARTED, drawn by PlaneView
## from the sim's tick, each flight's start ticks and the clock's alpha.

const MAIN_SCENE := "res://main/main.tscn"
## The terminal's floor, from its walls (x -43..43, z -100..-40).
const TERMINAL_FLOOR := Rect2(-43.0, -100.0, 86.0, 60.0)
const FIRST := 3000

var _airside: Airside
var _sun: DirectionalLight3D


## Builds the real Airside markers and Sun from main.tscn's saved state, without
## instantiating the scene, and keeps them in the tree for the whole file.
func before() -> void:
	var state: SceneState = (load(MAIN_SCENE) as PackedScene).get_state()
	_airside = Airside.new()
	_sun = DirectionalLight3D.new()
	for i in state.get_node_count():
		var parent := String(state.get_node_path(i, true))
		var props := {}
		for k in state.get_node_property_count(i):
			props[state.get_node_property_name(i, k)] = state.get_node_property_value(i, k)
		if parent == "./Airside" and state.get_node_type(i) == &"Marker3D":
			var marker := Marker3D.new()
			marker.name = state.get_node_name(i)
			marker.transform = props.get(&"transform", Transform3D.IDENTITY)
			_airside.add_child(marker)
		elif String(state.get_node_path(i)) == "./Airside":
			_airside.links = props[&"links"]
		elif String(state.get_node_path(i)) == "./Sun":
			_sun.transform = props[&"transform"]
	add_child(_airside)
	add_child(_sun)


func after() -> void:
	_airside.free()
	_sun.free()


func _view(sim: FlightSim, clock: SimClock, slot := 0) -> PlaneView:
	var view := PlaneView.new()
	view.sim = sim
	view.clock = clock
	view.airside = _airside
	view.slot = slot
	add_child(view)
	return auto_free(view) as PlaneView


func _sim() -> FlightSim:
	return auto_free(FlightSim.new()) as FlightSim


func _clock() -> SimClock:
	return auto_free(SimClock.new()) as SimClock


func _starts() -> Array[int]:
	return FlightSim.schedule_starts(FIRST)


func _lead_ticks(view: PlaneView, starts: Array[int]) -> float:
	return FlightPose.path_length(view.lead_in_track()) / view.lead_in_speed(starts)


func _climb_ticks(view: PlaneView, starts: Array[int]) -> float:
	return FlightPose.path_length(view.climb_out_track()) / view.climb_out_speed(starts)


func _angle(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(a.angle_to(b))


func test_the_sky_tracks_join_the_runway_phases() -> void:
	var lead := _airside.lead_in_track()
	var climb := _airside.climb_out_track()
	var approach := _airside.phase_path(FlightSim.State.APPROACH)
	var takeoff := _airside.phase_path(FlightSim.State.TAKEOFF)
	assert_that(lead[lead.size() - 1]).is_equal(approach[0])
	assert_that(climb[0]).is_equal(takeoff[takeoff.size() - 1])
	var lead_end := FlightPose.track_heading(lead, FlightPose.path_length(lead))
	var approach_dir := (approach[1] - approach[0]).slide(Vector3.UP).normalized()
	assert_float(lead_end.dot(approach_dir)).is_equal_approx(1.0, 0.0001)
	var climb_start := FlightPose.track_heading(climb, 0.0)
	assert_float(climb_start.dot(FlightPose.exit_dir(takeoff))).is_equal_approx(1.0, 0.0001)


## Every state edge from the lead-in to the climb-out: the pose just before and
## just after the edge tick are the same place and the same attitude.
func test_the_pose_is_continuous_at_every_phase_edge() -> void:
	var view := _view(_sim(), _clock())
	var starts := _starts()
	for state in range(FlightSim.State.APPROACH, FlightSim.State.DEPARTED + 1):
		var edge := float(starts[state])
		var before_edge: Dictionary = view.pose_at(starts, edge - 0.001)
		var after_edge: Dictionary = view.pose_at(starts, edge + 0.001)
		assert_bool(before_edge.is_empty() or after_edge.is_empty()).is_false()
		var a: Transform3D = before_edge["transform"]
		var b: Transform3D = after_edge["transform"]
		var label := "edge into state %d at tick %d" % [state, starts[state]]
		assert_float(a.origin.distance_to(b.origin)).override_failure_message(label).is_less(0.02)
		assert_float(_angle(a.basis.z, b.basis.z)).override_failure_message(label).is_less(0.05)
		assert_float(_angle(a.basis.x, b.basis.x)).override_failure_message(label).is_less(0.05)
	assert_int(view.pose_at(starts, starts[1] - 0.001)["phase"]).is_equal(PlaneView.PHASE_LEAD_IN)
	assert_int(view.pose_at(starts, starts[10] + 0.001)["phase"]).is_equal(
		PlaneView.PHASE_CLIMB_OUT
	)


## Sampled every half tick from the start of the lead-in to the end of the
## climb-out, the plane never jumps or snaps round; it shows only inside that
## window.
func test_no_jump_from_lead_in_start_to_climb_out_end() -> void:
	var view := _view(_sim(), _clock())
	var starts := _starts()
	var first := float(starts[FlightSim.State.APPROACH]) - _lead_ticks(view, starts)
	var last := float(starts[FlightSim.State.DEPARTED]) + _climb_ticks(view, starts)
	assert_bool(view.pose_at(starts, first - 0.01).is_empty()).is_true()
	assert_bool(view.pose_at(starts, last + 0.01).is_empty()).is_true()
	var previous: Transform3D = view.pose_at(starts, first + 0.001)["transform"]
	# Worst step per half tick: [move in the sky, turn in the sky, turn on the ground].
	var worst := [0.0, 0.0, 0.0]
	var worst_ground_at := 0.0
	var samples := 0
	var time := first + 0.5
	while time < last:
		var at: Dictionary = view.pose_at(starts, time)
		var now: Transform3D = at["transform"]
		var turn := maxf(
			_angle(previous.basis.z, now.basis.z), _angle(previous.basis.x, now.basis.x)
		)
		var in_sky: bool = at["phase"] in [PlaneView.PHASE_LEAD_IN, PlaneView.PHASE_CLIMB_OUT]
		worst[0] = maxf(worst[0], previous.origin.distance_to(now.origin))
		if in_sky:
			worst[1] = maxf(worst[1], turn)
		elif turn > worst[2]:
			worst[2] = turn
			worst_ground_at = time
		previous = now
		samples += 1
		time += 0.5
	print("sky scan samples=%d move=%.3f m sky_turn=%.3f deg" % [samples, worst[0], worst[1]])
	print("sky scan ground_turn=%.3f deg at tick %.1f" % [worst[2], worst_ground_at])
	assert_int(samples).is_greater(6000)
	# The fastest phase is the climb-out at about 3.9 m per tick.
	assert_float(worst[0]).is_greater(1.0).is_less(2.5)
	# Sky turns and bank roll-ins stay gentle; the taxi corners and the pushback
	# swing are the older ground poses, unchanged here.
	assert_float(worst[1]).is_greater(0.1).is_less(1.5)
	assert_float(worst[2]).is_less(6.0)


## The same tick and alpha draw the same pose whether the clock ran there at 1x
## or 3x, and a paused clock keeps it.
func test_the_same_sim_time_gives_the_same_pose_at_1x_3x_and_pause() -> void:
	for target in [float(FIRST) + 50.25, float(FIRST) + 230.5, float(FIRST) + 2650.75]:
		var poses: Array[Transform3D] = []
		for speed in [1, 3, 1]:
			var sim := _sim()
			var clock := _clock()
			sim.bind_clock(clock)
			sim.add_flight("ONE", _starts())
			clock.set_speed(speed)
			var view := _view(sim, clock)
			var left: float = (target + 1.0) * SimClock.STEP / speed
			while left > 0.0:
				var chunk := minf(left, 8.0 * SimClock.STEP / speed)
				clock.advance(chunk)
				left -= chunk
			if poses.size() == 2:
				clock.set_paused(true)
				for i in 30:
					clock.advance(1.0 / 60.0)
			view.update_pose()
			assert_bool(view.visible).is_true()
			assert_float(float(clock.tick) - 1.0 + clock.alpha).is_equal_approx(target, 0.001)
			poses.append(view.transform)
		assert_float(poses[0].origin.distance_to(poses[1].origin)).is_less(0.01)
		assert_float(poses[0].origin.distance_to(poses[2].origin)).is_less(0.01)
		assert_float(_angle(poses[0].basis.z, poses[1].basis.z)).is_less(0.01)


## flight_at_gate lets a flight go at DEPARTED; the view still finds it among
## the sim's listed flights and flies it out, and is done before the prune.
func test_the_climb_out_finds_the_departed_flight_and_ends_before_the_prune() -> void:
	var sim := _sim()
	sim.open_airport()
	assert_bool(sim.accept_contract(TestFlightContracts.terms("AM", 480))).is_true()
	var view := _view(sim, _clock())
	var starts := view.starts_of("AM-d0")
	var departed := starts[FlightSim.State.DEPARTED]
	var climb_ticks := _climb_ticks(view, starts)
	assert_float(climb_ticks).is_greater(100.0).is_less(FlightTimetable.PRUNE_AFTER_TICKS)
	for t in range(1, departed + 21):
		sim.on_tick(t)
	assert_str(sim.flight_at_gate("C")).is_equal("")
	view.update_pose()
	assert_str(view.flight_id).is_equal("AM-d0")
	assert_int(view.phase).is_equal(PlaneView.PHASE_CLIMB_OUT)
	assert_float(view.position.y).is_greater(45.0)
	for t in range(departed + 21, departed + ceili(climb_ticks) + 3):
		sim.on_tick(t)
	view.update_pose()
	assert_bool(view.visible).is_false()
	assert_array(sim.flight_ids()).contains(["AM-d0"])


## A flight that starts the tick the one before departs: slot 0 climbs the
## first out while slot 1 brings the next in, and no moment needs a third.
func test_back_to_back_flights_share_two_slots() -> void:
	var sim := _sim()
	var reserved := FlightTimetable.reserved_ticks()
	for i in 3:
		assert_bool(sim.add_flight("F%d" % i, FlightSim.schedule_starts(i * reserved))).is_true()
	var clock := _clock()
	var first_view := _view(sim, clock, 0)
	var second_view := _view(sim, clock, 1)
	sim.on_tick(reserved + 40)
	first_view.update_pose()
	second_view.update_pose()
	assert_str(first_view.flight_id).is_equal("F0")
	assert_int(first_view.phase).is_equal(PlaneView.PHASE_CLIMB_OUT)
	assert_str(second_view.flight_id).is_equal("F1")
	assert_int(second_view.phase).is_equal(PlaneView.PHASE_LEAD_IN)
	assert_float(first_view.position.distance_to(second_view.position)).is_greater(200.0)
	var most := 0
	for t in range(0, 3 * reserved, 10):
		most = maxi(most, first_view.sightings(float(t)).size())
	assert_int(most).is_equal(2)


## The real layout: 40 to 120 m up, turns at least 90 m wide, the lead-in
## starts while its flight is listed, the climb-out ends before the prune, and
## the arrival's sun shadow crosses the terminal floor.
func test_the_layout_flies_inside_the_ruled_band() -> void:
	var view := _view(_sim(), _clock())
	view.sun = _sun
	var starts := _starts()
	var lowest := INF
	var highest := -INF
	var tightest := INF
	var on_floor := 0
	for kind in ["lead", "straight", "climb"]:
		var track := view.lead_in_track() if kind == "lead" else view.climb_out_track()
		if kind == "straight":
			track = view.straight_in_track()
		var length := FlightPose.path_length(track)
		var at := 0.0
		while at <= length:
			var pose := (
				FlightPose.lead_in_pose(track, at)
				if kind != "climb"
				else FlightPose.climb_out_pose(track, at)
			)
			lowest = minf(lowest, pose.origin.y)
			highest = maxf(highest, pose.origin.y)
			var rate := absf(FlightPose.turn_rate(track, at))
			if rate > 0.0:
				tightest = minf(tightest, 1.0 / rate)
			var shadow := view.ground_point_of(pose.origin)
			if kind == "lead" and TERMINAL_FLOOR.has_point(Vector2(shadow.x, shadow.z)):
				on_floor += 1
			at += 5.0
	var lead_ticks := _lead_ticks(view, starts)
	var climb_ticks := _climb_ticks(view, starts)
	print("sky band low=%.1f high=%.1f turn=%.1f m" % [lowest, highest, tightest])
	print("sky floor_samples=%d lead=%.0f climb=%.0f" % [on_floor, lead_ticks, climb_ticks])
	assert_float(lowest).is_greater_equal(40.0)
	assert_float(highest).is_less_equal(120.0).is_greater(90.0)
	assert_float(tightest).is_greater_equal(90.0)
	assert_int(on_floor).is_greater(10)
	var lead_room := FlightTimetable.ISSUE_LEAD_TICKS + FlightSim.PHASE_TICKS[0]
	assert_float(lead_ticks).is_greater(300.0).is_less_equal(lead_room)
	assert_float(climb_ticks).is_less(FlightTimetable.PRUNE_AFTER_TICKS)


## Sol review regression: an offer accepted after opening whose first SCHEDULED
## is close. AM departs 08:00, so accepted at 06:00 (tick 0) its SCHEDULED is
## tick 440, far inside the full lead-in. The control shows the full lead-in
## would already be mid-air on the first frame; the view must instead show
## nothing until SCHEDULED, then the straight-in from its unseen entry, joining
## the approach without a jump. The next day has the full lead-in again.
func test_an_offer_accepted_late_enters_unseen_on_the_straight_in() -> void:
	var sim := _sim()
	sim.open_airport()
	assert_bool(sim.accept_contract(TestFlightContracts.terms("AM", 480))).is_true()
	var view := _view(sim, _clock())
	var starts := view.starts_of("AM-d0")
	var scheduled := starts[FlightSim.State.SCHEDULED]
	var approach := starts[FlightSim.State.APPROACH]
	assert_int(scheduled).is_equal(440)
	# Control: the full lead-in is already under way at the first frame.
	var full: Dictionary = view.pose_at(starts, 0.0, true)
	assert_bool(full.is_empty()).is_false()
	assert_bool(view.has_full_lead_in("AM-d0")).is_false()
	assert_bool(view.has_full_lead_in("AM-d1")).is_true()
	sim.on_tick(1)
	view.update_pose()
	assert_bool(view.visible).is_false()
	for t in range(2, scheduled + 2):
		sim.on_tick(t)
	view.update_pose()
	assert_bool(view.visible).is_true()
	assert_int(view.phase).is_equal(PlaneView.PHASE_LEAD_IN)
	var entry := _airside.straight_in_track()[0]
	assert_float(view.position.x).is_equal_approx(entry.x, 0.01)
	assert_bool(view.pose_at(starts, scheduled - 0.5, false).is_empty()).is_true()
	var a: Transform3D = view.pose_at(starts, approach - 0.001, false)["transform"]
	var b: Transform3D = view.pose_at(starts, approach + 0.001, false)["transform"]
	assert_float(a.origin.distance_to(b.origin)).is_less(0.02)
	assert_float(_angle(a.basis.z, b.basis.z)).is_less(0.05)
	var first_step := (
		view.straight_in_to_go(starts, scheduled) - view.straight_in_to_go(starts, scheduled + 1)
	)
	assert_float(first_step).is_greater(view.lead_in_speed(starts)).is_less(6.0)


## Where a plane pops in or out (the full lead-in's start, the straight-in's
## entry, the climb-out's end) no camera sees it, on a sample of cameras: 25
## focus points across the camera bounds (edges, halves, centre) x 24 yaws x 5
## zooms from near to full. A sample, not every configuration. A control point
## (ApproachStart) is seen by some sampled camera.
func test_planes_appear_and_vanish_where_no_camera_sees() -> void:
	# The test runner's window is square; a 21:9 view sees wider than the
	# game's 16:9, so it covers ultrawide windows too.
	var screen := auto_free(SubViewport.new()) as SubViewport
	screen.size = Vector2i(2520, 1080)
	add_child(screen)
	var rig: TycoonCamera = load("res://camera/tycoon_camera.tscn").instantiate()
	screen.add_child(rig)
	var cam: Camera3D = rig.get_node("Camera3D")
	var view := _view(_sim(), _clock())
	var lead := view.lead_in_track()
	var climb := view.climb_out_track()
	var hidden_points: Array[Vector3] = []
	var subjects := [
		FlightPose.lead_in_pose(lead, 0.0).origin,
		FlightPose.lead_in_pose(view.straight_in_track(), 0.0).origin,
		FlightPose.climb_out_pose(climb, FlightPose.path_length(climb)).origin,
	]
	for origin: Vector3 in subjects:
		for i in 8:
			hidden_points.append(
				origin + AABB(Vector3(-20, -6, -20), Vector3(40, 12, 40)).get_endpoint(i)
			)
	var control: Vector3 = _airside.phase_path(FlightSim.State.APPROACH)[0]
	var seen := 0
	var control_seen := 0
	var edge := rig.bounds_half_extent
	for fx in [-edge, -edge / 2.0, 0.0, edge / 2.0, edge]:
		for fz in [-edge, -edge / 2.0, 0.0, edge / 2.0, edge]:
			for step in 24:
				for zoom in [6.0, 30.0, 80.0, 150.0, 300.0]:
					rig.position = Vector3(fx, 0.0, fz)
					rig.yaw = step * TAU / 24.0
					rig.distance = zoom
					rig.zoom(1.0)
					control_seen += int(cam.is_position_in_frustum(control))
					for p in hidden_points:
						seen += int(cam.is_position_in_frustum(p))
	print(
		(
			"sky unseen viewport=%s seen=%d control_seen=%d"
			% [cam.get_viewport().get_visible_rect().size, seen, control_seen]
		)
	)
	assert_int(control_seen).is_greater(0)
	assert_int(seen).is_equal(0)


## Sol re-check regression: the starter's first day gets no exception. It is
## accepted at the current tick like any contract, so a gate filled by
## contracts accepted while closed can start it at the opening tick; it flies
## the straight-in, and its later days the full lead-in.
func test_the_starters_first_day_takes_the_straight_in() -> void:
	var sim := _sim()
	sim.open_airport()
	var terms := FlightSim.starter_terms(sim.tick)
	assert_bool(sim.accept_contract(terms)).is_true()
	var view := _view(sim, _clock())
	var first := FlightTimetable.occurrence_id(
		FlightSim.DEFAULT_ID, sim.start_days[FlightSim.DEFAULT_ID]
	)
	var next := FlightTimetable.occurrence_id(
		FlightSim.DEFAULT_ID, sim.start_days[FlightSim.DEFAULT_ID] + 1
	)
	assert_bool(view.has_full_lead_in(first)).is_false()
	assert_bool(view.has_full_lead_in(next)).is_true()
	var starts := view.starts_of(first)
	var scheduled := starts[FlightSim.State.SCHEDULED]
	for t in range(1, scheduled):
		sim.on_tick(t)
	view.update_pose()
	assert_bool(view.visible).is_false()
	sim.on_tick(scheduled)
	sim.on_tick(scheduled + 1)
	view.update_pose()
	assert_bool(view.visible).is_true()
	assert_float(view.position.x).is_equal_approx(_airside.straight_in_track()[0].x, 0.01)
