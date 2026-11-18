class_name TestFollowInvite
extends GdUnitTestSuite
## What the follow hint reads and its Show me button does (FollowInvite, decision
## follow-invitation-and-passenger-card-a-click-a-passenger-fir): the hint is
## ready while a passenger is drawn in the terminal, a selected passenger or
## vehicle counts as followed, and Show me selects the passenger with the
## longest way to go the way a click does, so the camera follows and their
## bubble shows.

var _world: PassengerTestWorld
var _views: PassengerViews
var _camera: TycoonCamera
var _hud: PassengerHud
var _settings := ""
var _path := ""
var _alerts := ""


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	_camera = TycoonCamera.new()
	var eye := Camera3D.new()
	eye.name = "Camera3D"
	_camera.add_child(eye)
	add_child(_camera)
	_hud = PassengerHud.new()
	_hud.clock = _world.clock
	_hud.flights = _world.flights
	_hud.sim = _world.sim
	_hud.views = _views
	_hud.camera = _camera
	_settings = SaveTestKit.run_path("follow_invite_board")
	_hud.departures_settings_path = _settings
	_alerts = SaveTestKit.run_path("follow_invite_alerts")
	_hud.alert_settings_path = _alerts
	add_child(_hud)
	_path = SaveTestKit.run_path("follow_invite_hints")


func after_test() -> void:
	_hud.free()
	_camera.free()
	_views.free()
	_world.free_all()
	for path in [_settings, _alerts, _path]:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")


func test_nobody_in_the_terminal_means_nothing_to_show() -> void:
	assert_int(FollowInvite.candidate(_world.sim, _views)).is_equal(0)
	var read := FollowInvite.read(_world.sim, _views, null)
	assert_bool(read["follow_ready"]).is_false()
	assert_bool(read["followed"]).is_false()
	assert_int(FollowInvite.show_me(_world.sim, _views, _camera, null)).is_equal(0)
	assert_int(_views.selected_id).is_equal(0)
	assert_bool(_camera.is_following()).is_false()


func test_a_passenger_in_the_terminal_makes_the_hint_ready_until_one_is_selected() -> void:
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.step()
	var read := FollowInvite.read(_world.sim, _views, null)
	assert_bool(read["follow_ready"]).is_true()
	assert_bool(read["followed"]).is_false()
	_views.selected_id = id
	assert_bool(FollowInvite.read(_world.sim, _views, null)["followed"]).is_true()


func test_a_passenger_who_has_boarded_is_not_offered() -> void:
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.step()
	_world.passenger(id).stage = Passenger.Stage.MADE
	assert_int(FollowInvite.candidate(_world.sim, _views)).is_equal(0)
	assert_bool(FollowInvite.read(_world.sim, _views, null)["follow_ready"]).is_false()


func test_show_me_picks_the_passenger_with_the_longest_way_to_go_and_follows_them() -> void:
	var far := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var near := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.step()
	_world.passenger(far).stage = Passenger.Stage.TO_GATE
	_world.passenger(near).stage = Passenger.Stage.TO_CHECKIN
	print("far %d near %d" % [far, near])
	assert_int(FollowInvite.candidate(_world.sim, _views)).is_equal(near)
	assert_int(FollowInvite.show_me(_world.sim, _views, _camera, null)).is_equal(near)
	assert_int(_views.selected_id).is_equal(near)
	assert_bool(_camera.is_following()).is_true()
	# Selected, the passenger's bubble is the one the view shows (pinned).
	assert_bool(_views.focused(near)).is_true()
	assert_bool(_views.focused(far)).is_false()


func test_the_hint_button_selects_a_passenger_and_counts_the_hint_seen() -> void:
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.step()
	var hints := Hints.new()
	hints.forced_mode = Hints.Mode.PROFILE
	hints.settings_path = _path
	hints.hud = _hud
	hints.reads_world = false
	add_child(hints)
	auto_free(hints)
	assert_int(hints.press_show_me()).is_equal(id)
	assert_int(_views.selected_id).is_equal(id)
	assert_bool(_camera.is_following()).is_true()
	(
		assert_bool(HudFlagSetting.load_flag(_path, "hint_seen_follow_passenger", false, "Hints"))
		. is_true()
	)
