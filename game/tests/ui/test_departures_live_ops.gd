class_name TestDeparturesLiveOps
extends GdUnitTestSuite
## Live Ops drawer and actionable HUD telemetry (decision 35d321c7):
## - dynamic Departures (B) toggle label + HudButtonYellow emphasis when late
## - self-clearing AlertStack late-runner card when DeparturesPanel is hidden
## - live Boarded / Booked counts on Today rows
## - clicking a flight row pans camera to that flight's gate desk
## - header In terminal: N + clickable · K late + rolling 3-day On time: XX%

const SITE := preload("res://build/terminal_site.tres")
const FLIGHT_B := "GA200"

var _world: PassengerTestWorld
var _gates: GateDesks
var _rating: AirportRating
var _views: PassengerViews
var _camera: TycoonCamera
var _mode: BuildMode
var _hud: PassengerHud
var _board: DeparturesBoard
var _alerts: AlertStack


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := SiteGrid.new(SITE)
	assert_bool(ReferenceTerminal.build(grid)).is_true()
	var desk_edit := ReferenceTerminal.gate_desk_edit(ReferenceTerminal.offset_on(grid))
	assert_bool(grid.apply(desk_edit).ok).is_true()
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(1500, 1800))
	_world.flights.open_airport()
	_gates = auto_free(GateDesks.new()) as GateDesks
	_gates.bind(_world.grid, _world.flights)
	_gates.refresh()
	assert_array(_gates.gate_ids()).is_not_empty()
	_rating = AirportRating.new()
	_rating.bind(_world.clock, _world.flights, _world.sim)
	add_child(_rating)
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	_mode = BuildMode.new()
	_mode.set_process(false)
	_mode.tool = BuildMode.Tool.NONE
	add_child(_mode)
	_mode.grid = _world.grid
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
	_hud.build_mode = _mode
	_hud.camera = _camera
	_hud.rating = _rating
	_hud.gates = _gates
	_hud.alert_settings_path = SaveTestKit.run_path("live_ops_alerts")
	_hud.departures_settings_path = SaveTestKit.run_path("live_ops_board")
	add_child(_hud)
	_board = _hud.find_child("DeparturesBoard", true, false) as DeparturesBoard
	_alerts = _hud.find_child("AlertStack", true, false) as AlertStack


func after_test() -> void:
	DirAccess.remove_absolute(_hud.alert_settings_path)
	DirAccess.remove_absolute(_hud.departures_settings_path)
	_hud.free()
	_camera.free()
	_mode.free()
	_views.free()
	_rating.free()
	_world.free_all()


func _toggle() -> Button:
	return _board.find_child("DeparturesToggle", true, false) as Button


func _accept(id: String, minute: int, destination: String, booked: int) -> String:
	var terms := TestFlightContracts.terms(id, minute)
	terms["destination"] = destination
	terms["plane_size"] = PlaneClasses.SMALL
	terms["booked_passengers"] = booked
	assert_bool(_world.flights.accept_contract(terms)).is_true()
	return FlightTimetable.occurrence_id(id, 0)


func test_toggle_label_tracks_empty_today_and_late_counts_with_yellow_emphasis() -> void:
	var empty: FlightSim = auto_free(FlightSim.new())
	empty.bind_clock(_world.clock)
	_hud.flights = empty
	_hud.refresh()
	assert_str(_toggle().text).is_equal("Departures (B)")
	assert_str(String(_toggle().theme_type_variation)).is_equal("")
	_hud.flights = _world.flights
	_accept("GA100", 11 * 60, "Oslo", 6)
	_hud.refresh()
	assert_bool(_board.is_shown()).is_false()
	assert_str(_toggle().text).is_equal("Departures (B) · 2 today")
	assert_str(String(_toggle().theme_type_variation)).is_equal("")
	var pid := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.passenger(pid).late = true
	_world.sim.mark_changed()
	_hud.refresh()
	assert_str(_toggle().text).is_equal("Departures (B) · 1 late")
	assert_str(String(_toggle().theme_type_variation)).is_equal("HudButtonYellow")
	_world.passenger(pid).late = false
	_world.sim.mark_changed()
	_hud.refresh()
	assert_str(_toggle().text).is_equal("Departures (B) · 2 today")
	assert_str(String(_toggle().theme_type_variation)).is_equal("")


func test_late_runner_alert_card_shows_when_collapsed_or_aside_and_clears_when_open() -> void:
	var pid := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.passenger(pid).late = true
	_world.sim.mark_changed()
	_hud.refresh()
	assert_bool(_board.is_shown()).is_false()
	assert_array(_alerts.card_keys()).contains([LateCount.ALERT_KEY])
	assert_str(_alerts.card_text(LateCount.ALERT_KEY)).contains("1 running late")
	# Expanding the drawer clears the alert card immediately so it never duplicates.
	_board.set_shown(true)
	_hud.refresh()
	assert_array(_alerts.card_keys()).not_contains([LateCount.ALERT_KEY])
	# Stepping aside while inspecting brings the self-clearing card back.
	var other_id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_views.select(other_id)
	_hud.refresh()
	assert_bool(_board.is_aside()).is_true()
	assert_array(_alerts.card_keys()).contains([LateCount.ALERT_KEY])
	# Clicking the alert card follows the tightest running-late passenger.
	assert_bool(_alerts.press_card(LateCount.ALERT_KEY)).is_true()
	assert_int(_views.selected_id).is_equal(pid)
	assert_bool(_camera.is_following()).is_true()
	# Clearing lateness removes the card automatically.
	_world.passenger(pid).late = false
	_world.sim.mark_changed()
	_hud.refresh()
	assert_array(_alerts.card_keys()).not_contains([LateCount.ALERT_KEY])


func test_boarded_booked_progress_updates_live_on_today_row() -> void:
	var occ := _accept("GA100", 11 * 60, "Oslo", 6)
	_board.set_shown(true)
	_hud.refresh()
	var boarded_label := _board.find_child("Boarded_%s" % occ, true, false) as Label
	assert_object(boarded_label).is_not_null()
	assert_str(boarded_label.text).is_equal("0/6 boarded")
	var pid := _world.sim.spawn_now(occ)
	_world.sim._finish(_world.passenger(pid), true)
	_hud.refresh()
	boarded_label = _board.find_child("Boarded_%s" % occ, true, false) as Label
	assert_object(boarded_label).is_not_null()
	assert_str(boarded_label.text).is_equal("1/6 boarded")


func _click_at(at: Vector2) -> void:
	var port := get_viewport()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	port.push_input(motion, true)
	await await_idle_frame()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.position = at
	press.global_position = at
	port.push_input(press, true)
	await await_idle_frame()
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.button_mask = 0
	release.position = at
	release.global_position = at
	port.push_input(release, true)
	await await_idle_frame()


func test_clicking_flight_row_focuses_gate_desk_while_late_pill_follows_runner() -> void:
	var occ := _accept("GA100", 11 * 60, "Oslo", 6)
	var gate_id: String = _world.flights.contract_of("GA100")["gate"]
	assert_str(gate_id).is_not_empty()
	var pid := _world.sim.spawn_now(occ)
	_world.passenger(pid).late = true
	_world.sim.mark_changed()
	_board.set_shown(true)
	_hud.refresh()
	await await_idle_frame()
	await await_idle_frame()
	var row := _board.find_child("FlightRow_%s" % occ, true, false) as Control
	var head_row := _board.find_child("HeadRow_%s" % occ, true, false) as Control
	var late_btn := _board.late_button(occ)
	assert_object(row).is_not_null()
	assert_object(head_row).is_not_null()
	assert_object(late_btn).is_not_null()
	assert_int(row.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_int(late_btn.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_str(row.tooltip_text).contains(gate_id)
	assert_vector(head_row.size).is_greater(Vector2.ZERO)
	assert_vector(late_btn.size).is_greater(Vector2.ZERO)
	var head_center := head_row.get_global_transform_with_canvas() * (head_row.size / 2.0)
	var pill_center := late_btn.get_global_transform_with_canvas() * (late_btn.size / 2.0)
	assert_bool(row.get_global_rect().has_point(head_center)).is_true()
	assert_bool(late_btn.get_global_rect().has_point(head_center)).is_false()
	assert_bool(late_btn.get_global_rect().has_point(pill_center)).is_true()
	var focused: Array[String] = []
	var followed: Array[String] = []
	_board.focus_gate_requested.connect(func(g: String) -> void: focused.append(g))
	_board.follow_late_requested.connect(func(f: String) -> void: followed.append(f))
	# Clicking the row outside the late pill emits focus_gate_requested and NOT follow_late_requested.
	await _click_at(head_center)
	assert_array(focused).is_equal([gate_id])
	assert_array(followed).is_empty()
	assert_bool(_camera.is_gliding()).is_true()
	var desk_id := int(_gates.binding_of(gate_id)["desk"])
	var expected := AlertSources.object_point(_world.grid, desk_id)
	assert_vector(_camera._glide_position).is_equal_approx(expected, Vector3.ONE * 0.01)
	# Clicking the late pill center triggers follow_late_requested and does NOT bubble to the row.
	focused.clear()
	await _click_at(pill_center)
	assert_array(followed).is_equal([occ])
	assert_array(focused).is_empty()
	assert_int(_views.selected_id).is_equal(pid)
	assert_bool(_camera.is_following()).is_true()


func test_header_on_time_tracks_rolling_three_day_rating_and_header_late_picks_tightest() -> void:
	var gate_id := _gates.gate_ids()[0]
	_world.flights.add_flight(FLIGHT_B, PassengerTestWorld.starts_with(1550, 1900), gate_id)
	var loose_id := _world.sim.spawn_now(FLIGHT_B)
	var tight_id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.step()
	_world.passenger(loose_id).late = true
	_world.passenger(tight_id).late = true
	_world.sim.mark_changed()
	# Record 3 made and 1 missed in AirportRating -> 75% rolling 3-day on-time rate.
	for i in 3:
		_rating.record_passenger(_world.clock.tick, true, 80)
	_rating.record_passenger(_world.clock.tick, false, 0)
	_board.set_shown(true)
	_hud.refresh()
	var on_time := _board.find_child("OnTime", true, false) as Label
	var header_late := _board.find_child("HeaderLate", true, false) as Button
	assert_str(on_time.text).is_equal("On time: 75%")
	assert_str(header_late.text).is_equal("· 2 late")
	header_late.pressed.emit()
	assert_int(_views.selected_id).is_equal(tight_id)
	assert_bool(_camera.is_following()).is_true()


func test_hud_refresh_preserves_board_revision_caches_without_rescan() -> void:
	var occ := _accept("GA100", 11 * 60, "Oslo", 6)
	var pid := _world.sim.spawn_now(occ)
	var p := _world.passenger(pid)
	p.late = true
	_world.sim.mark_changed()
	_board.set_shown(true)
	_hud.refresh()
	var late_key := _board._late_key.duplicate()
	var progress_key := _board._progress_key.duplicate()
	assert_array(late_key).is_not_empty()
	assert_array(progress_key).is_not_empty()
	assert_int(_board.late_count_of(occ)).is_equal(1)
	var boarded_label := _board.find_child("Boarded_%s" % occ, true, false) as Label
	assert_str(boarded_label.text).is_equal("0/6 boarded")
	# Repeated PassengerHud.refresh() calls while revision is unchanged must not invalidate caches.
	p.late = false
	_world.sim.flight_results[occ] = {"made": 1, "missed": 0}
	for i in 5:
		_hud.refresh()
		assert_array(_board._late_key).is_equal(late_key)
		assert_array(_board._progress_key).is_equal(progress_key)
	assert_int(_board.late_count_of(occ)).is_equal(1)
	boarded_label = _board.find_child("Boarded_%s" % occ, true, false) as Label
	assert_str(boarded_label.text).is_equal("0/6 boarded")
	# Advancing revision triggers a single rescan and updates both counts.
	_world.sim.mark_changed()
	_hud.refresh()
	assert_int(_board.late_count_of(occ)).is_equal(0)
	boarded_label = _board.find_child("Boarded_%s" % occ, true, false) as Label
	assert_str(boarded_label.text).is_equal("1/6 boarded")


func test_live_ops_strings_are_in_messages_pot() -> void:
	var template := FileAccess.get_file_as_string("res://locale/messages.pot")
	var entries := PotEntries.parse(template)
	assert_array(PotEntries.malformed(entries)).is_empty()
	assert_array(PotEntries.duplicates(entries)).is_empty()
	var wanted := [
		["", "{boarded}/{booked} boarded"],
		["", "3-day rolling on-time rate (70% of your star rating)"],
		["", "In terminal: {active}"],
		["", "· {count} late"],
		["", "On time: {percent}%"],
		["", "On time: —"],
		["", "Departures ({key}) · {count} late"],
		["", "Departures ({key}) · {count} today"],
		["gate name", "Click to focus Gate {gate}"],
		["", "{time} {destination} · Click to follow"],
		["", "{time} {flight} · Click to follow"],
		["", "{flight} · Click to follow"],
		["", "Click to follow the tightest running-late passenger"],
		["", "Follow the tightest running-late passenger"],
	]
	for pair: Array in wanted:
		var ctx: String = pair[0]
		var id: String = pair[1]
		assert_int(PotEntries.count(entries, ctx, id)).is_equal(1)
		assert_int(PotEntries.complete(entries, ctx, id)).is_equal(1)
