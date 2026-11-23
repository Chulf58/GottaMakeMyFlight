class_name TestGermanLiveSwitch
extends GdUnitTestSuite
## Regression tests for the five UI strings reported untranslated after a live
## switch to German ("de"): GameMenu camera-angle selector and quit-log note,
## DeparturesBoard doors-close line, StaffPanel starter open cue, and AlertStack
## closed-station cards.

const LOCALE_SETTINGS := preload("res://locale/locale_settings.gd")

var _w: PassengerTestWorld
var _cleanup_paths: Array[String] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	PseudoLocale.disable()
	_set_locale("en")


func after_test() -> void:
	PseudoLocale.disable()
	_set_locale("en")
	if _w != null:
		_w.free_all()
		_w = null
	for path in _cleanup_paths:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")
	_cleanup_paths.clear()


func _set_locale(code: String) -> void:
	var settings := get_node_or_null("/root/LocaleSettings") as LOCALE_SETTINGS
	if settings != null:
		settings.apply_locale(code, false)
	else:
		TranslationServer.set_locale(code)


func test_game_menu_camera_angle_and_quit_log_note_switch_live_to_german() -> void:
	var cam_path := SaveTestKit.run_path("german_live_cam").replace(".json", ".cfg")
	var qlog_path := SaveTestKit.run_path("german_live_qlog").replace(".json", ".cfg")
	_cleanup_paths.append(cam_path)
	_cleanup_paths.append(qlog_path)

	var kit := IncidentPanelKit.new()
	kit.build(self)
	var cam_scene: PackedScene = load("res://camera/tycoon_camera.tscn")
	var cam := cam_scene.instantiate() as TycoonCamera
	cam.settings_path = cam_path
	kit.port.add_child(cam)

	var qlog := QuitLogRecorder.new()
	qlog.settings_path = qlog_path
	qlog.log_dir = SaveTestKit.run_dir("german_live_qlog_dir")
	kit.port.add_child(qlog)

	var menu := GameMenu.new()
	menu.director = kit.director
	menu.clock = kit.clock
	menu.save_game = kit.save
	menu.quit_log = qlog
	menu.camera = cam
	kit.port.add_child(menu)

	menu.open()
	menu.press_settings()

	var cam_label := menu.camera_angle_picker.get_node("Label") as Label
	var cam_opt := menu.camera_angle_option
	var qlog_note := menu.find_child("QuitLogNote", true, false) as Label
	assert_object(qlog_note).is_not_null()
	assert_str(cam_label.text).is_equal("Camera angle")
	assert_str(cam_opt.get_item_text(0)).is_equal("Low (38°)")
	assert_str(cam_opt.get_item_text(1)).is_equal("Medium (54°)")
	assert_str(cam_opt.get_item_text(2)).is_equal("Top-Down (70°)")
	assert_str(qlog_note.text).starts_with("Records where you stop playing:")

	TranslationServer.set_locale("de")

	assert_str(cam_label.text).is_equal("Kamerawinkel")
	assert_str(cam_opt.get_item_text(0)).is_equal("Niedrig (38°)")
	assert_str(cam_opt.get_item_text(1)).is_equal("Mittel (54°)")
	assert_str(cam_opt.get_item_text(2)).is_equal("Draufsicht (70°)")
	assert_str(qlog_note.text).starts_with("Speichert, wo du aufhörst:")
	assert_str(qlog_note.text).contains("nichts wird gesendet.")

	cam.set_pitch_degrees(46.2)
	assert_int(cam_opt.item_count).is_equal(4)
	assert_str(cam_opt.get_item_text(3)).is_equal("Benutzerdefiniert (46°)")

	kit.port.free()


func test_departures_board_doors_close_switches_live_to_german() -> void:
	var cfg_path := SaveTestKit.run_path("german_live_departures").replace(".json", ".cfg")
	_cleanup_paths.append(cfg_path)

	var flights := auto_free(FlightSim.new()) as FlightSim
	var clock := auto_free(SimClock.new()) as SimClock
	flights.open_airport()
	var tick := GameCalendar.tick_at(0, 9 * 60, 0)
	for t in range(1, tick + 1):
		flights.on_tick(t)
	clock.tick = tick
	var terms := TestFlightContracts.terms("EARLY", 11 * 60 + 20)
	terms["destination"] = "Oslo"
	terms["airline"] = "Gotta Air"
	assert_bool(flights.accept_contract(terms)).is_true()

	var board := auto_free(DeparturesBoard.new()) as DeparturesBoard
	board.settings_path = cfg_path
	board.flights = flights
	board.clock = clock
	add_child(board)
	board.set_shown(true)

	var doors_label := board.find_child("DoorsClose", true, false) as Label
	assert_object(doors_label).is_not_null()
	assert_str(doors_label.text).is_equal("doors close 11:17")

	TranslationServer.set_locale("de")

	var updated_label := board.find_child("DoorsClose", true, false) as Label
	assert_object(updated_label).is_not_null()
	assert_str(updated_label.text).is_equal("Türen schließen 11:17")
	assert_array(board.shown_lines()).contains(["11:20  Oslo  Gotta Air  Türen schließen 11:17"])


func test_staff_panel_open_cue_switches_live_to_german() -> void:
	_w = PassengerTestWorld.make(
		PassengerTestWorld.floored(Vector2i(12, 12)), FlightSim.schedule_starts(0)
	)
	_w.auto_staff = false
	var gate := auto_free(AirportGate.new()) as AirportGate
	gate.bind(_w.flights, _w.staff)
	var panel := auto_free(StaffPanel.new()) as StaffPanel
	panel.staff = _w.staff
	panel.gate = gate
	add_child(panel)

	assert_bool(gate.open()).is_true()
	assert_str(panel.hint_label().text).is_equal("Open! Starter contract: Gotta Air to Oslo, daily")

	TranslationServer.set_locale("de")

	assert_str(panel.hint_label().text.split("\n")[0]).is_equal(
		"Geöffnet! Startvertrag: Gotta Air nach Oslo, täglich"
	)
	assert_str(panel.hint_text().split("\n")[0]).is_equal(
		"Geöffnet! Startvertrag: Gotta Air nach Oslo, täglich"
	)


func _seat_desk(desk: int) -> void:
	var id := _w.staff.hire(StaffMember.Role.CHECKIN)
	var m := _w.staff.get_member(id)
	m.station = desk
	m.at = _w.staff.spot_of(desk)
	m.clear_path()
	m.state = StaffMember.State.ON_DUTY
	_w.staff.rederive()


func _assert_live_card(
	stack: AlertStack, key: StringName, en_text: String, de_text: String
) -> void:
	_set_locale("en")
	stack.refresh()
	_w.run_to(_w.sim.tick + AlertSources.QUEUE_HOLD_TICKS)
	stack.refresh()
	assert_str(stack.card_text(key)).is_equal(en_text)
	TranslationServer.set_locale("de")
	assert_str(stack.card_text(key)).is_equal(de_text)


func _blocked_spots_world(anchors: Array) -> void:
	var source := BuildGrid.new()
	ReferenceTerminal.build(source)
	var data := source.to_snapshot()
	var next: int = data["next_object_id"]
	for anchor: Array in anchors:
		(data["objects"] as Array).append(
			{"id": next, "def": "seat_row", "anchor": anchor, "facing": 0}
		)
		next += 1
	data["next_object_id"] = next
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(JSON.parse_string(JSON.stringify(data)))).is_true()
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_w.auto_staff = false
	StaffTestKit.staff_all(_w.staff)
	_w.step()


func test_alert_stack_closed_station_card_switches_live_to_german() -> void:
	var cfg_path := SaveTestKit.run_path("german_live_alerts").replace(".json", ".cfg")
	_cleanup_paths.append(cfg_path)

	# 1) "hire staff" (2 stations -> 1 station) and "on the way" (1 station -> 2 stations).
	_w = PassengerTestWorld.reference_world()
	_w.auto_staff = false
	StaffTestKit.staff_all(
		_w.staff, [StaffMember.Role.SECURITY, StaffMember.Role.GATE, StaffMember.Role.SHOP]
	)
	var desks := _w.sim.layout.desks
	assert_int(desks.size()).is_equal(2)

	var stack := auto_free(AlertStack.new()) as AlertStack
	stack.settings_path = cfg_path
	stack.sim = _w.sim
	add_child(stack)

	# 2 stations idle -> hire staff (plural).
	_assert_live_card(
		stack,
		AlertSources.NO_STAFF,
		"Nobody on duty\n2 stations are closed · hire staff on the Staff card",
		"Niemand im Dienst\n2 Stationen sind geschlossen · Personal auf der Personalkarte einstellen"
	)

	# Seat desks[1]; 1 station idle -> hire staff (singular).
	_seat_desk(desks[1])
	_assert_live_card(
		stack,
		AlertSources.NO_STAFF,
		"Nobody on duty\n1 station is closed · hire staff on the Staff card",
		"Niemand im Dienst\n1 Station ist geschlossen · Personal auf der Personalkarte einstellen"
	)

	# Hire for desks[0]; 1 station with walker -> on the way (singular).
	_w.staff.hire(StaffMember.Role.CHECKIN)
	_w.step()
	_assert_live_card(
		stack,
		AlertSources.NO_STAFF,
		"Nobody on duty\n1 station is closed · staff are on the way",
		"Niemand im Dienst\n1 Station ist geschlossen · Personal ist unterwegs"
	)

	# Re-create world with both desks having walkers -> on the way (plural).
	_w.free_all()
	_w = PassengerTestWorld.reference_world()
	_w.auto_staff = false
	StaffTestKit.staff_all(
		_w.staff, [StaffMember.Role.SECURITY, StaffMember.Role.GATE, StaffMember.Role.SHOP]
	)
	for _i in desks.size():
		_w.staff.hire(StaffMember.Role.CHECKIN)
	_w.step()
	stack.sim = _w.sim
	stack.reset()
	_assert_live_card(
		stack,
		AlertSources.NO_STAFF,
		"Nobody on duty\n2 stations are closed · staff are on the way",
		"Niemand im Dienst\n2 Stationen sind geschlossen · Personal ist unterwegs"
	)

	# 2) "staff can't reach the staff spot" / "Staff can't get to work" (2 -> 1).
	_w.free_all()
	_blocked_spots_world([[11, 10], [14, 10]])
	stack.sim = _w.sim
	stack.reset()
	_assert_live_card(
		stack,
		AlertSources.STAFF_SPOT,
		"Staff can't get to work\n2 stations are closed · staff can't reach the staff spot",
		(
			"Personal kommt nicht zur Arbeit\n"
			+ "2 Stationen sind geschlossen · Personal erreicht den Arbeitsplatz nicht"
		)
	)

	var second_blocker: int = _w.sim.grid.object_at(Vector2i(14, 10))
	assert_bool(_w.grid.apply(BuildEdit.remove_object(second_blocker)).ok).is_true()
	_w.step()
	_assert_live_card(
		stack,
		AlertSources.STAFF_SPOT,
		"Staff can't get to work\n1 station is closed · staff can't reach the staff spot",
		(
			"Personal kommt nicht zur Arbeit\n"
			+ "1 Station ist geschlossen · Personal erreicht den Arbeitsplatz nicht"
		)
	)


func _placeholders(text: String) -> Array[String]:
	var re := RegEx.create_from_string("\\{[^}]+\\}")
	var out: Array[String] = []
	for m in re.search_all(text):
		out.append(m.get_string())
	out.sort()
	return out


func test_all_five_strings_and_variants_are_in_pot_and_de_po() -> void:
	var pot_entries := PotEntries.parse(FileAccess.get_file_as_string("res://locale/messages.pot"))
	var de_entries := PotEntries.parse(FileAccess.get_file_as_string("res://locale/de.po"))
	assert_array(PotEntries.malformed(de_entries)).is_empty()
	assert_array(PotEntries.duplicates(de_entries)).is_empty()
	var required := [
		["", "Camera angle", ""],
		["", "Low (38°)", ""],
		["", "Medium (54°)", ""],
		["", "Top-Down (70°)", ""],
		["", "Custom ({angle}°)", ""],
		[
			"",
			(
				"Records where you stop playing: the day, money, stars, builds, flights "
				+ "and alerts, never what you click or type. The file stays on this "
				+ "computer and nothing is sent."
			),
			"",
		],
		["", "doors close {time}", ""],
		["", "Open! Starter contract: {airline} to {destination}, daily", ""],
		["", "Nobody on duty", ""],
		[
			"",
			"{count} station is closed · staff are on the way",
			"{count} stations are closed · staff are on the way",
		],
		[
			"",
			"{count} station is closed · hire staff on the Staff card",
			"{count} stations are closed · hire staff on the Staff card",
		],
		[
			"",
			"{count} station is closed · staff can't reach the staff spot",
			"{count} stations are closed · staff can't reach the staff spot",
		],
		["", "Staff can't get to work", ""],
	]
	_set_locale("de")
	for item: Array in required:
		var ctx: String = item[0]
		var msgid: String = item[1]
		var plural: String = item[2]
		assert_int(PotEntries.complete(pot_entries, ctx, msgid, plural)).is_equal(1)
		assert_int(PotEntries.complete(de_entries, ctx, msgid, plural)).is_equal(1)
		var expected_tokens := _placeholders(msgid)
		if plural == "":
			var translated := TranslationServer.translate(msgid, ctx)
			assert_str(translated).is_not_empty()
			assert_str(translated).is_not_equal(msgid)
			assert_array(_placeholders(translated)).is_equal(expected_tokens)
		else:
			var singular_de := TranslationServer.translate_plural(msgid, plural, 1, ctx)
			var plural_de := TranslationServer.translate_plural(msgid, plural, 2, ctx)
			assert_str(singular_de).is_not_empty()
			assert_str(plural_de).is_not_empty()
			assert_str(singular_de).is_not_equal(msgid)
			assert_str(plural_de).is_not_equal(plural)
			assert_str(singular_de).is_not_equal(plural_de)
			assert_array(_placeholders(singular_de)).is_equal(expected_tokens)
			assert_array(_placeholders(plural_de)).is_equal(expected_tokens)
