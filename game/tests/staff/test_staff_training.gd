class_name TestStaffTraining
extends GdUnitTestSuite
## In-panel Staff Training L1 -> L3 (Slice S3-P2c; decision b764f946).

const CHECKIN := StaffMember.Role.CHECKIN
const SECURITY := StaffMember.Role.SECURITY
const SHOP := StaffMember.Role.SHOP
const CLEANER := StaffMember.Role.CLEANER
const GATE := StaffMember.Role.GATE
const RAMP := StaffMember.Role.RAMP
const TRAITS := [
	[1, false, false],
	[2, true, false],
	[0, false, true],
	[1, false, false],
]

var _w: PassengerTestWorld
var _other: PassengerTestWorld
var _sec_worlds: Array[SecurityTestWorld] = []
var _port: SubViewport


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	SecurityForecast.every_tick = false
	PseudoLocale.disable()
	for sw in _sec_worlds:
		sw.world.free_all()
	_sec_worlds.clear()
	for w in [_w, _other]:
		if w != null:
			w.free_all()
	_w = null
	_other = null
	if _port != null:
		_port.free()
		_port = null


func _ref_world() -> PassengerTestWorld:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	var w := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	w.auto_staff = false
	return w


func test_train_costs_validation_and_sandbox_unlimited_funds() -> void:
	assert_int(PriceTable.staff_train_cost(1)).is_equal(400)
	assert_int(PriceTable.staff_train_cost(2)).is_equal(800)
	assert_int(PriceTable.staff_train_cost(3)).is_equal(0)
	assert_int(PriceTable.staff_train_cost(4)).is_equal(0)

	_w = _ref_world()
	var id := _w.staff.hire(CHECKIN)
	var m := _w.staff.get_member(id)
	assert_int(m.level).is_equal(1)

	var trained_events := []
	_w.staff.member_trained.connect(
		func(mid: int, lvl: int) -> void: trained_events.append([mid, lvl])
	)

	var wallet := Wallet.new(1199)
	# L1 -> L2 costs $400 (leaves $799).
	assert_bool(_w.staff.train(id, wallet)).is_true()
	assert_int(m.level).is_equal(2)
	assert_int(wallet.balance).is_equal(799)
	assert_array(trained_events).is_equal([[id, 2]])

	# L2 -> L3 costs $800 -> refused at $799!
	assert_bool(_w.staff.train(id, wallet)).is_false()
	assert_int(m.level).is_equal(2)
	assert_int(wallet.balance).is_equal(799)

	# Credit $1 -> $800 -> L2 -> L3 succeeds!
	assert_bool(wallet.credit(1, Wallet.Category.GRANT)).is_true()
	assert_bool(_w.staff.train(id, wallet)).is_true()
	assert_int(m.level).is_equal(3)
	assert_int(wallet.balance).is_equal(0)
	assert_array(trained_events).is_equal([[id, 2], [id, 3]])

	# L3 -> L4 refused even with no wallet / unlimited funds.
	assert_bool(_w.staff.train(id, null)).is_false()
	assert_int(m.level).is_equal(3)

	# Sandbox unlimited_funds: trains L1 -> L2 -> L3 at $0 balance without deducting.
	var sandbox_wallet := Wallet.new(0)
	sandbox_wallet.unlimited_funds = true
	var id2 := _w.staff.hire(SECURITY)
	assert_bool(_w.staff.train(id2, sandbox_wallet)).is_true()
	assert_bool(_w.staff.train(id2, sandbox_wallet)).is_true()
	assert_bool(_w.staff.train(id2, sandbox_wallet)).is_false()
	assert_int(_w.staff.get_member(id2).level).is_equal(3)
	assert_int(sandbox_wallet.balance).is_equal(0)

	# Fired / non-existent members refused.
	assert_bool(_w.staff.train(999, sandbox_wallet)).is_false()
	assert_bool(_w.staff.fire(SECURITY)).is_true()
	assert_bool(_w.staff.train(id2, sandbox_wallet)).is_false()


func test_speed_multipliers_tired_stacking_and_checkin_ticks() -> void:
	_w = _ref_world()
	StaffTestKit.staff_all(_w.staff, [CHECKIN, SECURITY])
	var desk := _w.sim.layout.desks[0]
	var agent := _w.staff.get_member(_w.staff.staff_at(desk))
	assert_float(agent.level_speed_factor()).is_equal_approx(1.00, 0.001)
	assert_float(agent.work_speed_factor()).is_equal_approx(1.00, 0.001)
	assert_int(PassengerStations._checkin_ticks(_w.sim, desk)).is_equal(60)

	assert_bool(_w.staff.train(agent.id)).is_true()
	assert_float(agent.level_speed_factor()).is_equal_approx(1.15, 0.001)
	assert_float(agent.work_speed_factor()).is_equal_approx(1.15, 0.001)
	assert_int(PassengerStations._checkin_ticks(_w.sim, desk)).is_equal(52)

	assert_bool(_w.staff.train(agent.id)).is_true()
	assert_float(agent.level_speed_factor()).is_equal_approx(1.30, 0.001)
	assert_float(agent.work_speed_factor()).is_equal_approx(1.30, 0.001)
	assert_int(PassengerStations._checkin_ticks(_w.sim, desk)).is_equal(46)

	# Tired L1 = 0.80 (75 ticks), tired L2 = 0.92 (65 ticks), tired L3 = 1.04 (58 ticks).
	agent.energy = StaffMember.TIRED_THRESHOLD
	assert_float(agent.work_speed_factor()).is_equal_approx(1.04, 0.001)
	assert_int(PassengerStations._checkin_ticks(_w.sim, desk)).is_equal(58)
	agent.level = 2
	assert_float(agent.work_speed_factor()).is_equal_approx(0.92, 0.001)
	assert_int(PassengerStations._checkin_ticks(_w.sim, desk)).is_equal(65)
	agent.level = 1
	assert_float(agent.work_speed_factor()).is_equal_approx(0.80, 0.001)
	assert_int(PassengerStations._checkin_ticks(_w.sim, desk)).is_equal(75)

	# Restored L3 agent serves actual passenger in 46 ticks, and eta/wait_ticks match.
	agent.energy = StaffMember.ENERGY_MAX
	for cid in _w.staff.member_ids():
		var cm := _w.staff.get_member(cid)
		if cm.role == CHECKIN:
			cm.level = 3
	var p := _w.passenger(_w.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while p.stage != Passenger.Stage.CHECKIN and _w.clock.tick < 1200:
		_w.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CHECKIN)
	assert_int(p.service_end - _w.clock.tick).is_equal(46)
	assert_int(PassengerStations.wait_ticks(_w.sim, p)).is_equal(46)


func _run_security_throughput(use_lane: bool, level: int, tired: bool) -> Array:
	var sw := SecurityTestWorld.make(use_lane)
	_sec_worlds.append(sw)
	StaffTestKit.staff_all(sw.world.staff, [SECURITY])
	var officer := sw.world.staff.get_member(sw.world.staff.staff_at(sw.station))
	for _i in level - 1:
		assert_bool(sw.world.staff.train(officer.id)).is_true()
	if tired:
		officer.energy = StaffMember.TIRED_THRESHOLD
	var ids := sw.send_all(TRAITS)
	var start_tick := sw.world.clock.tick
	var wrong := []
	var steps := 0
	while not ids.all(func(id: int) -> bool: return sw.cleared.has(id)) and steps < 2000:
		var mine := []
		for id in ids:
			if sw.world.sim.get_passenger(id).station == sw.station and not sw.cleared.has(id):
				mine.append(id)
		var skipping := SecurityForecast.clearances(sw.world.sim, sw.station, mine)
		SecurityForecast.every_tick = true
		var every := SecurityForecast.clearances(sw.world.sim, sw.station, mine)
		SecurityForecast.every_tick = false
		for id: int in every:
			if skipping.get(id, -1) != every[id]:
				wrong.append([sw.world.clock.tick, id, skipping.get(id, -1), every[id]])
		sw.world.step()
		steps += 1
	(
		assert_array(wrong)
		. override_failure_message(
			"lane=%s level=%d tired=%s drift: %s" % [use_lane, level, tired, wrong]
		)
		. is_empty()
	)
	var speed := sw.world.sim.security.officer_work_speed_percent(
		sw.station, SecurityRuntime.Phase.SCAN
	)
	return [sw.world.clock.tick - start_tick, speed]


func test_security_throughput_improves_and_forecast_stays_tick_exact() -> void:
	var l1_basic := _run_security_throughput(false, 1, false)
	var l2_basic := _run_security_throughput(false, 2, false)
	var l3_basic := _run_security_throughput(false, 3, false)
	var l2_tired := _run_security_throughput(false, 2, true)
	var l3_tired := _run_security_throughput(false, 3, true)
	assert_int(l1_basic[1]).is_equal(100)
	assert_int(l2_basic[1]).is_equal(115)
	assert_int(l3_basic[1]).is_equal(130)
	assert_int(l2_tired[1]).is_equal(92)
	assert_int(l3_tired[1]).is_equal(104)
	assert_int(l2_basic[0]).is_less(l1_basic[0])
	assert_int(l3_basic[0]).is_less(l2_basic[0])

	var l1_lane := _run_security_throughput(true, 1, false)
	var l3_lane := _run_security_throughput(true, 3, false)
	var l3_lane_tired := _run_security_throughput(true, 3, true)
	assert_int(l3_lane[0]).is_less(l1_lane[0])
	assert_int(l3_lane_tired[1]).is_equal(104)


func _clean_ticks(level: int) -> int:
	var w := MessTestKit.open_world()
	_w = w
	var cleaner := CleanerTestKit.cleaner_at(w, Vector2i(10, 10))
	for _i in level - 1:
		assert_bool(w.staff.train(cleaner.id)).is_true()
	w.sim.messes.add(MessSim.Kind.TOILET, Vector2i(10, 10))
	var ticks := 0
	while w.sim.messes.mess_count() > 0 and ticks < 400:
		w.step()
		ticks += 1
	assert_int(w.sim.messes.mess_count()).is_equal(0)
	w.free_all()
	_w = null
	return ticks


func test_cleaner_l3_cleans_faster_than_l1() -> void:
	var t1 := _clean_ticks(1)
	var t2 := _clean_ticks(2)
	var t3 := _clean_ticks(3)
	assert_int(t2).is_less(t1)
	assert_int(t3).is_less(t2)


func test_staff_panel_training_ui_wallet_sandbox_and_retranslation() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_w = _ref_world()
	var wallet := Wallet.new(1200)
	var panel := StaffPanel.new()
	panel.staff = _w.staff
	panel.wallet = wallet
	_port.add_child(panel)

	var id := _w.staff.hire(CHECKIN)
	assert_str(panel.member_level_text(id)).is_equal("Lv. 1")
	var btn := panel.train_button(id)
	assert_object(btn).is_not_null()
	assert_str(btn.text).is_equal("Train $400")
	assert_bool(btn.disabled).is_false()

	# Train L1 -> L2 ($400, $800 remaining).
	btn.pressed.emit()
	assert_int(_w.staff.get_member(id).level).is_equal(2)
	assert_int(wallet.balance).is_equal(800)
	assert_str(panel.member_level_text(id)).is_equal("Lv. 2")
	btn = panel.train_button(id)
	assert_str(btn.text).is_equal("Train $800")
	assert_bool(btn.disabled).is_false()

	# Drop wallet below $800 -> button disables live via wallet.changed.
	assert_bool(wallet.spend(1, Wallet.Category.BUILD)).is_true()
	assert_bool(panel.train_button(id).disabled).is_true()
	assert_bool(wallet.credit(1, Wallet.Category.GRANT)).is_true()
	assert_bool(panel.train_button(id).disabled).is_false()

	# Train L2 -> L3 ($800, $0 remaining) -> shows Max label, no Train button.
	panel.train_button(id).pressed.emit()
	assert_int(_w.staff.get_member(id).level).is_equal(3)
	assert_int(wallet.balance).is_equal(0)
	assert_str(panel.member_level_text(id)).is_equal("Lv. 3")
	assert_object(panel.train_button(id)).is_null()
	var max_lbl := panel.card().find_child("Max%d" % id, true, false) as Label
	assert_object(max_lbl).is_not_null()
	assert_str(max_lbl.text).is_equal("Max")

	# Retranslation updates level, Train button, and Max labels.
	var id2 := _w.staff.hire(SECURITY)
	PseudoLocale.enable(0.4)
	panel.notification(Node.NOTIFICATION_TRANSLATION_CHANGED)
	assert_str(panel.member_level_text(id)).starts_with("[")
	assert_str(panel.train_button(id2).text).starts_with("[")
	var max_lbl_tr := panel.card().find_child("Max%d" % id, true, false) as Label
	assert_str(max_lbl_tr.text).starts_with("[")
	PseudoLocale.disable()
	panel.notification(Node.NOTIFICATION_TRANSLATION_CHANGED)

	# Sandbox unlimited_funds enables Train button even at $0 balance.
	wallet.unlimited_funds = true
	panel.refresh()
	assert_bool(panel.train_button(id2).disabled).is_false()
	panel.train_button(id2).pressed.emit()
	assert_int(_w.staff.get_member(id2).level).is_equal(2)
	assert_int(wallet.balance).is_equal(0)

	# All 6 role columns with hired & trained members fit inside 1280x720 without overlap.
	for role in StaffPanel.ROLES:
		_w.staff.hire(role)
	await await_idle_frame()
	var cols := (panel.card().get_child(0) as Control).get_children()
	var col_rects: Array[Rect2] = []
	for c in cols:
		var ctrl := c as Control
		if ctrl.visible:
			var r := ctrl.get_global_rect()
			assert_bool(r.has_area()).is_true()
			for prev in col_rects:
				assert_bool(prev.intersects(r)).is_false()
			col_rects.append(r)
	var card_rect := panel.card().get_global_rect()
	assert_float(card_rect.position.x).is_greater_equal(0.0)
	assert_float(card_rect.end.x).is_less_equal(1280.0)
	assert_float(card_rect.position.y).is_greater_equal(0.0)
	assert_float(card_rect.end.y).is_less_equal(720.0)


func test_staff_snapshot_v10_save_game_v40_round_trip_and_corrupt_level_refused() -> void:
	assert_int(StaffSim.SAVE_VERSION).is_greater_equal(10)
	assert_int(SaveGame.SAVE_VERSION).is_greater_equal(40)

	_w = _ref_world()
	var id1 := _w.staff.hire(CHECKIN)
	var id2 := _w.staff.hire(SECURITY)
	assert_bool(_w.staff.train(id1)).is_true()
	assert_bool(_w.staff.train(id2)).is_true()
	assert_bool(_w.staff.train(id2)).is_true()
	_w.run_to(120)

	_other = StaffTestKit.load_world(StaffTestKit.save_text(_w))
	assert_int(_other.staff.get_member(id1).level).is_equal(2)
	assert_int(_other.staff.get_member(id2).level).is_equal(3)
	for _i in 60:
		_w.step()
		_other.step()
	assert_str(StaffTestKit.signature(_other.staff)).is_equal(StaffTestKit.signature(_w.staff))

	var good: Dictionary = JSON.parse_string(JSON.stringify(_w.staff.to_snapshot()))
	for bad_val in [0, 4, "two"]:
		var bad := good.duplicate(true)
		bad["members"][0]["level"] = bad_val
		assert_bool(_w.staff.from_snapshot(bad)).is_false()
	var missing := good.duplicate(true)
	missing["members"][0].erase("level")
	assert_bool(_w.staff.from_snapshot(missing)).is_false()


func test_shop_cafe_order_and_info_desk_help_speed_up_and_save_at_l3() -> void:
	# CafeSim order_ticks: L1=60, L2=52, L3=46, including CafeForecast _order_eta & CafeSnapshot.
	var grid := BuildGrid.new()
	var ids := CafeTestLayout.build(grid, false)
	_w = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(3000, 6000), 4242)
	_w.auto_staff = false
	_w.sim.cafes.refresh()
	StaffTestKit.staff_all(_w.staff, [SECURITY])
	var land_counter: int = ids["land_counter"]
	var server_id := StaffTestKit.seat_server(_w.staff, land_counter)
	var server := _w.staff.get_member(server_id)
	assert_int(_w.sim.cafes._order_eta(int(ids["land_room"]), land_counter)).is_equal(60)

	assert_bool(_w.staff.train(server_id)).is_true()
	assert_int(_w.sim.cafes._order_eta(int(ids["land_room"]), land_counter)).is_equal(52)

	assert_bool(_w.staff.train(server_id)).is_true()
	assert_int(server.level).is_equal(3)
	assert_int(_w.sim.cafes._order_eta(int(ids["land_room"]), land_counter)).is_equal(46)

	var guest := _w.passenger(_w.sim.spawn_now(PassengerTestWorld.FLIGHT))
	guest.hunger = 60
	guest.cafe_cooldown = 0
	guest.stage = Passenger.Stage.TO_SECURITY
	guest.at = ReferenceTerminal.offset_on(grid) + Vector2i(20, 12)
	guest.clear_path()
	assert_bool(_w.sim.cafes.try_visit(guest)).is_true()
	while guest.stage != Passenger.Stage.CAFE_ORDER and _w.clock.tick < 400:
		_w.step()
	assert_int(guest.stage).is_equal(Passenger.Stage.CAFE_ORDER)
	var visit := _w.sim.cafes.visit_of(guest.id)
	assert_int(visit.service_end - _w.clock.tick).is_equal(46)

	# Mid-order L3 CafeSnapshot saves and loads cleanly.
	var snap: Dictionary = JSON.parse_string(JSON.stringify(_w.sim.to_snapshot()))
	var fresh_grid := BuildGrid.new()
	assert_bool(fresh_grid.from_snapshot(_w.grid.to_snapshot())).is_true()
	_other = PassengerTestWorld.make(fresh_grid, PassengerTestWorld.starts_with(3000, 6000), 4242)
	_other.auto_staff = false
	assert_bool(_other.sim.from_snapshot(snap)).is_true()
	_w.free_all()
	_w = null
	_other.free_all()
	_other = null

	# InfoDesk HELP_TICKS: L1=60, L2=52, L3=46.
	_w = InfoDeskTestLayout.world(true, [SHOP])
	StaffTestKit.staff_all(_w.staff, [SHOP])
	var desk := _w.staff.stations_of(SHOP)[0]
	var info_server := _w.staff.get_member(_w.staff.staff_at(desk))
	assert_bool(_w.staff.train(info_server.id)).is_true()
	var lost := InfoDeskTestLayout.guest(_w, InfoDeskTestLayout.DESK_FRONT, 50)
	var guard := 0
	while not _w.sim.info_desks.holds(lost) and guard < 60:
		_w.step()
		guard += 1
	assert_bool(_w.sim.info_desks.holds(lost)).is_true()
	var help_ticks := 0
	while _w.sim.info_desks.holds(lost) and help_ticks < 100:
		_w.step()
		help_ticks += 1
	# +1 step before entering, then 52 ticks of help -> strictly faster than 60.
	assert_int(help_ticks).is_less(60)
	assert_bool(_w.staff.train(info_server.id)).is_true()
	assert_int(_w.sim.info_desks._help_ticks(desk)).is_equal(46)


func test_non_trainable_roles_refuse_train_and_hide_ui_button() -> void:
	for role in [CHECKIN, SECURITY, SHOP, CLEANER]:
		assert_bool(StaffSim.is_role_trainable(role)).is_true()
	for role in [GATE, RAMP]:
		assert_bool(StaffSim.is_role_trainable(role)).is_false()

	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_w = _ref_world()
	var wallet := Wallet.new(2000)
	var panel := StaffPanel.new()
	panel.staff = _w.staff
	panel.wallet = wallet
	_port.add_child(panel)

	var gate_id := _w.staff.hire(GATE)
	var ramp_id := _w.staff.hire(RAMP)
	assert_bool(_w.staff.train(gate_id, wallet)).is_false()
	assert_bool(_w.staff.train(ramp_id, wallet)).is_false()
	assert_int(_w.staff.get_member(gate_id).level).is_equal(1)
	assert_int(_w.staff.get_member(ramp_id).level).is_equal(1)
	assert_int(wallet.balance).is_equal(2000)

	assert_object(panel.train_button(gate_id)).is_null()
	assert_object(panel.train_button(ramp_id)).is_null()
	assert_object(panel.card().find_child("Level%d" % gate_id, true, false)).is_null()
	assert_object(panel.card().find_child("Level%d" % ramp_id, true, false)).is_null()
	for fixed_id in [gate_id, ramp_id]:
		var fixed_lbl := panel.card().find_child("FixedSpeed%d" % fixed_id, true, false) as Label
		assert_object(fixed_lbl).is_not_null()
		assert_str(fixed_lbl.text).is_equal(TranslationServer.translate("Fixed speed"))
		assert_str(String(fixed_lbl.theme_type_variation)).is_equal("HudHint")
		assert_float(fixed_lbl.custom_minimum_size.x).is_greater(0.0)


func test_leaving_and_leaving_shift_refused_while_off_shift_and_break_allowed() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_w = _ref_world()
	var wallet := Wallet.new(5000)
	var panel := StaffPanel.new()
	panel.staff = _w.staff
	panel.wallet = wallet
	_port.add_child(panel)

	# 1. Fired mid-service (leaving = true): refused in StaffSim and disabled in StaffPanel.
	var leaving_id := _w.staff.hire(CHECKIN)
	var leaving_m := _w.staff.get_member(leaving_id)
	leaving_m.state = StaffMember.State.ON_DUTY
	leaving_m.leaving = true
	panel.refresh()
	assert_bool(_w.staff.train(leaving_id, wallet)).is_false()
	assert_int(leaving_m.level).is_equal(1)
	assert_bool(panel.train_button(leaving_id).disabled).is_true()

	# 2. Walking out for overnight off-shift (LEAVING_SHIFT): refused & disabled.
	var shift_id := _w.staff.hire(SECURITY)
	var shift_m := _w.staff.get_member(shift_id)
	shift_m.state = StaffMember.State.LEAVING_SHIFT
	panel.refresh()
	assert_bool(_w.staff.train(shift_id, wallet)).is_false()
	assert_int(shift_m.level).is_equal(1)
	assert_bool(panel.train_button(shift_id).disabled).is_true()

	# 3. OFF_SHIFT and ON_BREAK remain trainable!
	var off_id := _w.staff.hire(CLEANER)
	var off_m := _w.staff.get_member(off_id)
	off_m.state = StaffMember.State.OFF_SHIFT
	var break_id := _w.staff.hire(SHOP)
	var break_m := _w.staff.get_member(break_id)
	break_m.state = StaffMember.State.ON_BREAK
	panel.refresh()
	assert_bool(panel.train_button(off_id).disabled).is_false()
	assert_bool(panel.train_button(break_id).disabled).is_false()
	assert_bool(_w.staff.train(off_id, wallet)).is_true()
	assert_bool(_w.staff.train(break_id, wallet)).is_true()
	assert_int(off_m.level).is_equal(2)
	assert_int(break_m.level).is_equal(2)
	assert_int(wallet.balance).is_equal(4200)
