extends SceneTree
## Windowed 1920x1080 Steam store gameplay screenshots probe (board D6c, fe3e175c;
## finding bb598d8c; decisions a7f1b1e4 and 26acd3c7). Writes 6 verified
## 1920x1080 PNGs + contact_sheet.png under tools/blender/out/screenshots/.

const IntroClose := preload("res://spike/intro_close.gd")
const PlateSight := preload("res://spike/plate_sight.gd")
const DEFAULT_SEED := 20261119
const SCREEN := Vector2i(1920, 1080)
const SETTINGS := "user://store_screenshots_probe_settings.cfg"
const SHOTS := (
	"shot_01_build_terminal,shot_02_queues_and_belts,shot_03_follow_passenger,"
	+ "shot_04_cafes_and_shops,shot_05_apron_boarding,shot_06_airline_offers"
)
const ROOMS := (
	"22:3:6:6:cafe,22:10:6:6:cafe,29:3:6:6:kiosk,29:10:6:6:pharmacy,"
	+ "36:3:5:4:toilet,36:12:5:4:toilet"
)
const PIECES := (
	"cafe_counter:23:3,cafe_table:24:4,cafe_table:24:6,cafe_counter:23:10,"
	+ "cafe_table:24:11,cafe_table:24:13,kiosk_counter:29:3,kiosk_display:32:3,"
	+ "kiosk_display:32:6,pharmacy_counter:29:10,pharmacy_shelf:32:10,"
	+ "pharmacy_shelf:32:13,toilet_stall:36:3,toilet_stall:37:3,toilet_sink:39:3,"
	+ "toilet_stall:36:12,toilet_stall:37:12,toilet_sink:39:12,screen_stand:17:4,"
	+ "plant_pot_1a:10:4,trash_can:28:4,trash_can:35:4,trash_can:35:13"
)

var _guard := Thread.new()
var _mutex := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _done := false
var _failed := false
var _out_dir := ""
var _saved: Dictionary = {}
var _main: Node3D
var _clock: SimClock
var _flights: FlightSim
var _sim: PassengerSim
var _views: PassengerViews
var _hud: PassengerHud
var _mode: BuildMode
var _grid: BuildGrid
var _rig: TycoonCamera
var _cam: Camera3D
var _at := Vector2i.ZERO


func _initialize() -> void:
	_beat("init")
	_guard.start(_watch)
	var rel := "res://../tools/blender/out/screenshots"
	_out_dir = ProjectSettings.globalize_path(rel).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	for name: String in Array(SHOTS.split(",")) + ["contact_sheet"]:
		var old := _out_dir.path_join("%s.png" % name)
		if FileAccess.file_exists(old):
			DirAccess.remove_absolute(old)
	print("PROBE out_dir=%s" % _out_dir)
	_run.call_deferred()


func _run() -> void:
	DirAccess.remove_absolute(SETTINGS)
	if await _boot_and_size() and _build_terminal():
		await _frames(8)
		if await _shot_02_queues_and_belts():
			await _shot_03_follow_passenger()
			await _shot_04_cafes_and_shops()
			await _shot_05_apron_boarding()
			await _shot_01_build_terminal()
			await _shot_06_airline_offers()
	DirAccess.remove_absolute(SETTINGS)
	DirAccess.remove_absolute(SETTINGS + ".tmp")
	print("PROBE shots=%d failed=%s" % [_saved.size(), _failed])
	_mutex.lock()
	_done = true
	_mutex.unlock()
	if _guard.is_started():
		_guard.wait_to_finish()
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
	quit(1 if _failed or _saved.size() != 6 else 0)


func _boot_and_size() -> bool:
	DisplayServer.window_set_position(Vector2i.ZERO)
	DisplayServer.window_set_size(SCREEN)
	await _frames(8)
	if root.size != SCREEN:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		DisplayServer.window_set_size(SCREEN)
		await _frames(8)
	var vis_sz := root.get_visible_rect().size
	print("PROBE window=%s layout=%s" % [root.size, vis_sz])
	_verify(root.size == SCREEN and vis_sz.is_equal_approx(Vector2(1536.0, 864.0)), "size")
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	_clock = _main.get_node("SimClock")
	var world_seed := DEFAULT_SEED
	for arg in OS.get_cmdline_user_args():
		world_seed = int(arg.get_slice("=", 1)) if arg.begins_with("--seed=") else world_seed
	seed(world_seed)
	_clock.seed_rng(world_seed)
	print("SEED=%d" % world_seed)
	_hud = _main.get_node("PassengerHud")
	_hud.debug_tools = false
	_hud.alert_settings_path = SETTINGS
	_hud.departures_settings_path = SETTINGS
	(_main.get_node("MoodOverlay") as MoodOverlay).settings_path = SETTINGS
	_rig = _main.get_node("TycoonCamera")
	_rig.settings_path = SETTINGS
	_mode = _main.get_node("BuildMode")
	_mode.starter_shell = false
	root.add_child(_main)
	current_scene = _main
	await _frames(5)
	_verify(IntroClose.close(_main) == "", "intro hold")
	_clock.set_paused(true)
	_flights = _main.get_node("FlightSim")
	_sim = _main.get_node("PassengerSim")
	_views = _main.get_node("PassengerViews")
	_grid = _mode.grid
	_cam = _rig.get_node("Camera3D")
	_cam.make_current()
	(_main.get_node("Finances") as Finances).wallet.credit(28000, Wallet.Category.FEES)
	var seen: Array[String] = []
	for info: Dictionary in BuildUnlocks.TIERS.slice(1, 3):
		for tool: BuildMode.Tool in info["tools"]:
			seen.append(String(BuildMode.Tool.find_key(tool)))
	var snap := {"tier": 3, "made": 200, "shown": [2, 3], "seen": seen, "firsts": []}
	_mode.unlocks.from_snapshot(snap)
	return not _failed


func _build_terminal() -> bool:
	_beat("build_terminal")
	_at = ReferenceTerminal.offset_on(_grid)
	var land := _mode.land_tool.land
	for _i in 64:
		if land.buyable_plots().is_empty() or not land.buy(land.buyable_plots()[0], null).ok:
			break
	var east := _at + Vector2i(32, 0)
	var edits := ReferenceTerminal.edits(_at) + ReferenceTerminal.edits(east)
	edits.append(ReferenceTerminal.gate_desk_edit(_at))
	edits.append(ReferenceTerminal.gate_desk_edit(east))
	for y in range(3, 17):
		for x in range(22, 42):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y) + _at, BuildGrid.FLOOR_TILE, 1))
	for x in range(22, 42):
		edits.append(BuildEdit.place_wall(Vector2i(x, 9) + _at, BuildGrid.Side.NORTH))
	for y in [4, 5, 6, 7, 11, 12, 13, 14, 15]:
		edits.append(BuildEdit.remove_wall(Vector2i(21, y) + _at, BuildGrid.Side.EAST))
		edits.append(BuildEdit.remove_wall(Vector2i(42, y) + _at, BuildGrid.Side.WEST))
	var ok := _grid.apply_batch(edits).all(func(r: BuildResult) -> bool: return r.ok)
	EnclosureKit.close_floor(_grid)
	var f_edits: Array[BuildEdit] = []
	for sx in ReferenceTerminal.SCANNER_XS:
		var old := _grid.object_at(Vector2i(sx, ReferenceTerminal.DIVIDER_Y - 1) + _at)
		if old != 0:
			f_edits.append(BuildEdit.remove_object(old))
	f_edits.append(BuildEdit.place_wall(Vector2i(17, 9) + _at, BuildGrid.Side.NORTH))
	var arch_at := Vector2i(20, 9) + _at
	var lane := SecurityLanes.geometry(arch_at, 0, SecurityLanes.LEFT)
	for k in range(-1, 3):
		var cell: Vector2i = arch_at + (lane["side"] as Vector2i) * k
		if _grid.has_wall(cell, BuildGrid.Side.NORTH):
			f_edits.append(BuildEdit.remove_wall(cell, BuildGrid.Side.NORTH))
	f_edits.append(BuildEdit.place_object(SecurityLanes.ARCH, arch_at, 0))
	for part in [SecurityLanes.TRAY_TABLE, SecurityLanes.XRAY_BELT, SecurityLanes.PICKUP_TABLE]:
		f_edits.append(BuildEdit.place_object(part, lane[part], 0))
	for spec in PIECES.split(","):
		var p := spec.split(":")
		var pos := Vector2i(int(p[1]), int(p[2])) + _at
		f_edits.append(BuildEdit.place_object(StringName(p[0]), pos, 0))
	var bag_rc := Rect2i(Vector2i(15, 12) + _at, Vector2i(2, 3))
	ok = ok and _grid.apply_batch(f_edits).all(func(r: BuildResult) -> bool: return r.ok)
	ok = ok and RoomTool.mark(_grid, bag_rc, &"bag_room", null).ok
	for spec in ROOMS.split(","):
		var r := spec.split(":")
		var rc := Rect2i(Vector2i(int(r[0]), int(r[1])) + _at, Vector2i(int(r[2]), int(r[3])))
		ok = ok and _grid.apply(BuildEdit.place_room(rc, StringName(r[4]))).ok
	_mode.set_tool(BuildMode.Tool.BELT)
	for s in [[12, 10, 12, 9], [12, 9, 16, 9], [15, 10, 15, 9], [16, 9, 16, 12]]:
		_beat("belt")
		ok = ok and _mode.lay_belt(Vector2i(s[0], s[1]) + _at, Vector2i(s[2], s[3]) + _at).ok
	_mode.set_tool(BuildMode.Tool.NONE)
	for rid in _grid.room_ids():
		ok = ok and RoomRules.status(_grid, rid).ok
	_sim.cafes.refresh()
	_sim.toilets.refresh()
	var stalls := _sim.toilets.layout.stalls.size()
	ok = ok and _sim.layout.security_lanes.is_complete(_grid.object_at(arch_at)) and stalls == 4
	if not _verify(ok, "terminal build failed"):
		return false
	(_mode.get_node("BuildView") as BuildView).refresh(_grid)
	(_main.get_node("RoofView") as RoofView).rebuild()
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StaffTestKit.staff_all(staff)
	StaffTestKit.seat(staff, _grid.object_at(arch_at), StaffMember.Slot.HELPER)
	staff.hire(StaffMember.Role.CLEANER)
	staff.hire(StaffMember.Role.CLEANER)
	var two_gates: Array[String] = ["A", "B"]
	print("PROBE staffed=%d stalls=%d gates=%s" % [hired, stalls, _flights.gate_ids()])
	_verify(_flights.gate_ids() == two_gates and hired >= 6, "gates/staff")
	return not _failed


func _shot_02_queues_and_belts() -> bool:
	_beat("shot_02")
	await _step_ticks(40)
	if _hud.unlock_guide() != null and _hud.unlock_guide().is_open():
		_hud.unlock_guide().dialog().dismiss()
	var base_min: int = _flights.contract_of(FlightSim.DEFAULT_ID)["departure_minute"]
	var got_b := false
	for later in range(38, 70):
		var terms := StarterSlot.departing(
			StarterSlot.whole_minute(FlightTimetable.issue_lead(), 0), 0
		)
		terms.merge({"id": "GMF202", "airline": "Blue Fjord", "destination": "Bergen"}, true)
		terms["departure_minute"] = (base_min + later) % GameCalendar.MINUTES_PER_DAY
		if _flights.accept_gate(terms) == "B" and _flights.accept_contract(terms):
			got_b = true
			break
	var ex_specs := (
		"GMF303:720:Lisbon:Sunhop,GMF404:900:Vienna:Nordic Wing," + "GMF505:1080:Zurich:Alpen Air"
	)
	for spec in ex_specs.split(","):
		var p := spec.split(":")
		var t := TestFlightContracts.terms(p[0], int(p[1]))
		t.merge({"destination": p[2], "airline": p[3], "plane_size": "small"}, true)
		t["booked_passengers"] = 14
		_flights.accept_contract(t)
	var first := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	var has_f := func() -> bool: return _flights.flight_ids().has(first)
	if (
		not _verify(_flights.opened_tick >= 0 and got_b, "open")
		or not await _advance_until("f1", 3000, has_f)
	):
		return false
	for i in 14:
		var p := _sim.get_passenger(_sim.spawn_now(first))
		p.hunger = 52 if i % 3 == 0 else p.hunger
		p.boredom = 72 if i % 3 == 0 else p.boredom
		await _step_ticks(12)
	var bv := _main.get_node("BaggageViews") as BaggageViews
	var bs := _main.get_node("BaggageSim") as BaggageSim
	var q_in := [Passenger.Stage.CHECKIN_QUEUE, Passenger.Stage.CHECKIN]
	var q_sec := [Passenger.Stage.SECURITY_QUEUE, Passenger.Stage.SECURITY]
	var ready := func() -> bool:
		var has_q := not _pax_in(q_in).is_empty() and not _pax_in(q_sec).is_empty()
		return has_q and bv.active_count() >= 2
	if await _advance_until("queues_and_belts", 2400, ready):
		_aim(_cell(Vector2i(15, 10), 0.0), 20.0, 0.22)
		await _frames(10)
		var sub: Array = [[_cell(Vector2i(20, 9), 1.8)]]
		for b in bs.bags():
			var bn := bv.node_for(b.id)
			if bn != null and bn.is_visible_in_tree() and sub.size() == 1:
				sub.append([bn.global_position + Vector3(0.0, 0.65, 0.0), bn])
		for pid in _pax_in(q_in + q_sec).slice(0, 2):
			var pn := _views.node_for(pid)
			sub.append([pn.global_position + Vector3(0.0, 1.35, 0.0), pn])
		var bar := (_main.get_node("BuildMenu") as BuildMenu).bar()
		await _capture("shot_02_queues_and_belts", sub, {"bar": bar})
	return not _failed


func _shot_03_follow_passenger() -> void:
	_beat("shot_03")
	await _step_ticks(260)
	var chosen := 0
	for k in 30:
		var fallback := 0
		for pid in _sim.passenger_ids():
			var p := _sim.get_passenger(pid)
			var ok_p := _views.node_for(pid) != null and p.stage < Passenger.Stage.MADE
			if ok_p and not PassengerThoughts.entries(p).is_empty():
				fallback = pid
				chosen = pid if p.cleared else chosen
		chosen = fallback if chosen == 0 and k >= 12 else chosen
		if chosen != 0:
			break
		await _step_ticks(15)
	if not _verify(chosen != 0, "shot_03: no passenger with thoughts"):
		return
	var pn := _views.node_for(chosen)
	_views.selected_id = chosen
	_views.follow_anchor.global_position = pn.global_position
	_aim(Vector3(pn.global_position.x, 0.0, pn.global_position.z), 14.5, 0.38)
	_rig.follow(_views.follow_anchor)
	await _frames(12)
	var inspect := _hud.find_child("PassengerInspect", true, false) as Control
	var thought0 := inspect.find_child("Thought0", true, false) as Control
	_verify(thought0 != null and thought0.is_visible_in_tree(), "shot_03: Thought0 hidden")
	pn = _views.node_for(chosen)
	var head := pn.global_position + Vector3(0.0, 1.35, 0.0)
	var mid_box := Rect2(440.0, 120.0, 760.0, 560.0)
	_verify(mid_box.has_point(_cam.unproject_position(head)), "shot_03: off-center")
	await _capture("shot_03_follow_passenger", [[head, pn]], {"inspect": inspect})
	_views.selected_id = 0
	_rig.stop_follow()
	await _frames(4)


func _shot_04_cafes_and_shops() -> void:
	_beat("shot_04")
	var occ_b := FlightTimetable.occurrence_id("GMF202", int(_flights.start_days["GMF202"]))
	var has_b := func() -> bool: return _flights.flight_ids().has(occ_b)
	if not await _advance_until("issue_b_04", 2400, has_b):
		return
	for i in 8:
		var cell := Vector2i(20, 6) if i % 2 == 0 else Vector2i(20, 12)
		var p := _place_pax(occ_b, cell, i % 2 == 0, 58 if i % 2 == 0 else 46, 78)
		p.toilet_need = 74 if i == 3 else p.toilet_need
	var cafe_st := [Passenger.Stage.CAFE_ORDER, Passenger.Stage.CAFE_SEATED]
	var shop_st := [Passenger.Stage.SHOP_BROWSE]
	var ready := func() -> bool:
		return _pax_in(cafe_st).size() >= 2 and not _pax_in(shop_st).is_empty()
	if not await _advance_until("cafes_and_shops", 1200, ready):
		return
	_aim(_cell(Vector2i(29, 8), 0.0), 20.5, -0.20)
	await _frames(10)
	var sub: Array = [[_cell(Vector2i(23, 3), 1.1)], [_cell(Vector2i(32, 3), 1.1)]]
	for pid in _pax_in(cafe_st + shop_st).slice(0, 2):
		var pn := _views.node_for(pid)
		sub.append([pn.global_position + Vector3(0.0, 1.15, 0.0), pn])
	var bar := (_main.get_node("BuildMenu") as BuildMenu).bar()
	await _capture("shot_04_cafes_and_shops", sub, {"bar": bar})


func _shot_05_apron_boarding() -> void:
	_beat("shot_05")
	var occ_a := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	var occ_b := FlightTimetable.occurrence_id("GMF202", int(_flights.start_days["GMF202"]))
	var both := func() -> bool:
		return _flights.flight_ids().has(occ_a) and _flights.flight_ids().has(occ_b)
	if not await _advance_until("issue_ab", 3000, both):
		return
	var push_a := _flights.state_start(occ_a, FlightSim.State.PUSHBACK)
	for _i in 240:
		if _clock.tick >= push_a - 105:
			break
		await _step_ticks(mini(30, push_a - 105 - _clock.tick))
	for _i in 8:
		_place_pax(occ_b, Vector2i(51, 4), true, 10, 10)
		await _step_ticks(8)
	for _i in 40:
		if _clock.tick >= push_a + 8:
			break
		await _step_ticks(mini(6, push_a + 8 - _clock.tick))
	var fleet := (_main.get_node("PlaneFleet") as PlaneFleet).views
	var ready := func() -> bool:
		var w := 0
		for pid in _pax_in([Passenger.Stage.APRON]):
			w += int(_views.node_for(pid).global_position.z < -100.5)
		var tug_on := false
		var b_on := false
		for v in fleet:
			tug_on = tug_on or (v.get_node("Props") as PlaneProps).tug.is_visible_in_tree()
			b_on = b_on or (v.gate == "B" and v.visible)
		return w >= 2 and tug_on and b_on
	if not await _advance_until("apron_boarding", 120, ready):
		return
	var view_a: PlaneView = null
	var view_b: PlaneView = null
	for v in fleet:
		view_a = v if v.gate == "A" and v.visible else view_a
		view_b = v if v.gate == "B" and v.visible else view_b
	var tug_pt := (view_a.get_node("Props") as PlaneProps).tug.global_position + Vector3(0, 1.2, 0)
	var b_pt := view_b.global_position + Vector3(3.5, 2.2, 0.0)
	var focus := Vector3((tug_pt.x + b_pt.x) * 0.5, 0.0, -103.5)
	for dist: float in [32.5, 35.0]:
		_aim(focus, dist, 0.04)
		await _frames(4)
		var mid_px := (_cam.unproject_position(tug_pt).x + _cam.unproject_position(b_pt).x) * 0.5
		focus.x += (mid_px - 900.0) / 27.0
		_aim(focus, dist, 0.04)
		await _frames(4)
		if _cam.unproject_position(tug_pt).x >= 350.0 and _cam.unproject_position(b_pt).x <= 1470.0:
			break
	await _frames(8)
	var dep := _main.find_child("DeparturesPanel", true, false) as Control
	_verify(_cam.unproject_position(tug_pt).x >= 340.0, "shot_05: tug behind DeparturesBoard")
	var sub: Array = [[view_b.global_position + Vector3(0.0, 2.6, 0.0), view_b], [tug_pt, view_a]]
	for pid in _pax_in([Passenger.Stage.APRON]):
		var n := _views.node_for(pid)
		var pt := n.global_position + Vector3(0.0, 1.45, 0.0)
		if n.global_position.z < -100.5 and _occluder(pt, n) == "" and sub.size() < 4:
			sub.append([pt, n])
	_verify(sub.size() >= 4, "shot_05: fewer than 2 unoccluded apron walkers")
	await _capture("shot_05_apron_boarding", sub, {"departures_board": dep})


func _shot_01_build_terminal() -> void:
	_beat("shot_01")
	var occ := ""
	for cid: String in ["GMF303", "GMF404", "GMF202"]:
		var cand_occ := FlightTimetable.occurrence_id(cid, int(_flights.start_days.get(cid, 0)))
		var open_st := _flights.flight_ids().has(cand_occ)
		if open_st and _flights.flight_state(cand_occ) <= FlightSim.State.BOARDING:
			occ = cand_occ
			break
	for i in 10 if occ != "" else 0:
		var p := _sim.get_passenger(_sim.spawn_now(occ))
		p.hunger = 54 if i % 2 == 0 else p.hunger
		p.boredom = 74 if i % 3 == 0 else p.boredom
		await _step_ticks(12)
	await _step_ticks(60)
	var rating := _main.get_node("AirportRating") as AirportRating
	_verify(rating.has_data() and _sim.passenger_ids().size() >= 6, "shot_01: active state")
	var menu := _main.get_node("BuildMenu") as BuildMenu
	_aim(_cell(Vector2i(19, 9), 0.0), 24.0, 0.25)
	_mode.set_tool(BuildMode.Tool.SEATS)
	await _frames(6)
	var ghost := _mode.get_node("Ghost") as Node3D
	for cand in [Vector2i(11, 14), Vector2i(17, 6), Vector2i(11, 13)]:
		_mode.pointer_override = _cam.unproject_position(_cell(cand, 0.0))
		await _frames(4)
		if ghost.visible and _mode.status_text().begins_with("Facing"):
			break
	print("SHOT01 ghost_vis=%s status='%s'" % [ghost.visible, _mode.status_text()])
	_verify(ghost.visible and _mode.status_text().begins_with("Facing"), "shot_01: ghost invalid")
	var pts := [[_cell(Vector2i(14, 11), 1.1)], [_cell(Vector2i(20, 9), 1.8)]]
	var ui := {"tray": menu.tray(), "bar": menu.bar(), "status": menu.status_card()}
	await _capture("shot_01_build_terminal", pts, ui)
	_mode.pointer_override = Vector2(-1.0, -1.0)
	_mode.set_tool(BuildMode.Tool.NONE)
	if menu.is_tray_open():
		menu.press_category(menu.open_category())
	await _frames(4)


func _shot_06_airline_offers() -> void:
	_beat("shot_06")
	_verify((_main.get_node("AirportRating") as AirportRating).has_data(), "shot_06: rating empty")
	var desk := _main.get_node("OfferDesk") as OfferDesk
	desk.board = OfferBoard.new()
	desk._draw(GameCalendar.day_of(_clock.tick, _clock.epoch))
	var offers := _main.get_node("OfferPanel") as OfferPanel
	_aim(_cell(Vector2i(22, 9), 0.0), 35.0, 0.22)
	offers.open()
	await _frames(10)
	var badge := _main.get_node("RatingBadge").find_child("*", true, false) as Control
	var clock_pnl := _hud.find_child("FlightPanel", true, false)
	var ui := {"offers": offers.sheet(), "clock": clock_pnl, "rating": badge}
	await _capture("shot_06_airline_offers", [[_cell(Vector2i(12, 11), 1.0)]], ui)
	offers.close()
	await _frames(4)


func _place_pax(occ: String, cell: Vector2i, clr: bool, hun: int, bor: int) -> Passenger:
	var p := _sim.get_passenger(_sim.spawn_now(occ))
	p.cleared = clr
	p.carry_on = 0
	p.at = cell + _at
	p.stage = Passenger.Stage.TO_GATE if clr else Passenger.Stage.TO_SECURITY
	p.stage_tick = _clock.tick
	p.clear_path()
	p.hunger = hun
	p.boredom = bor
	return p


func _capture(label: String, subjects: Array, ui: Dictionary) -> void:
	await _frames(6)
	var view := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var safe := view.grow(-10.0)
	var dbg := _hud.find_child("DebugCorner", true, false) as Control
	var ok := _verify(dbg == null or not dbg.is_visible_in_tree(), "%s: DebugCorner" % label)
	var causes := HintRules.causes(HintRules.read_world(_sim, []))
	ok = _verify(not causes.has(HintRules.TOILET), "%s: toilet gap active" % label) and ok
	var ctrl_hit := _occluder(Vector3(-27.0, -2.5, -90.0))
	print("PLATE %s control='%s'" % [label, ctrl_hit])
	ok = _verify(ctrl_hit != "", "%s: underground raycast control failed" % label) and ok
	for key in ui:
		var ctrl := ui[key] as Control
		var r := Rect2() if ctrl == null else ctrl.get_global_rect()
		var u_ok := ctrl != null and ctrl.is_visible_in_tree() and r.has_area() and view.encloses(r)
		print("  UI %s %s rect=%s ok=%s" % [label, key, r, u_ok])
		ok = _verify(u_ok, "%s: UI '%s' out of view (%s)" % [label, key, r]) and ok
	for item: Array in subjects:
		var pt: Vector3 = item[0]
		var px := _cam.unproject_position(pt)
		var in_f := not _cam.is_position_behind(pt) and safe.has_point(px)
		var hit := _occluder(pt, item[1]) if item.size() > 1 else ""
		print("  SUBJECT %s pt=%s px=%s hit='%s' in_f=%s" % [label, pt, px.round(), hit, in_f])
		ok = _verify(in_f and hit == "", "%s: %s occluded ('%s') or out" % [label, pt, hit]) and ok
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var btm := PlateSight.empty_bottom(img)
	var blank := Image.create(SCREEN.x, SCREEN.y, false, Image.FORMAT_RGBA8)
	var diff := PlateSight.differing(img, blank, Rect2i(Vector2i.ZERO, SCREEN), 16)
	var img_ok := img.get_size() == SCREEN and diff > 500 and bool(btm["ok"])
	var path := _out_dir.path_join("%s.png" % label)
	if not (_verify(img_ok, "%s: image check failed" % label) and ok):
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	var disk := Image.load_from_file(path) if img.save_png(path) == OK else null
	var d_sz := disk.get_size() if disk != null else Vector2i.ZERO
	print("PLATE %s size=%s non_blank=%d empty_btm=%.3f" % [label, d_sz, diff, btm["share"]])
	if not _verify(d_sz == SCREEN, "%s: disk check failed" % label):
		DirAccess.remove_absolute(path)
		return
	_saved[label] = path
	var order := SHOTS.split(",")
	if not _failed and _saved.size() == order.size():
		var sheet := Image.create(1920, 1620, false, Image.FORMAT_RGBA8)
		for i in order.size():
			var tile := Image.load_from_file(String(_saved[order[i]]))
			tile.convert(Image.FORMAT_RGBA8)
			tile.resize(960, 540, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(tile, Rect2i(0, 0, 960, 540), Vector2i((i % 2) * 960, (i / 2) * 540))
		var out := _out_dir.path_join("contact_sheet.png")
		if _verify(sheet.save_png(out) == OK, "contact_sheet.png failed"):
			print("PLATE contact_sheet %s size=%s" % [out, sheet.get_size()])


func _occluder(subject: Vector3, own: Node = null) -> String:
	var from := _cam.global_position
	var to := subject + (from - subject).normalized() * 0.35
	var ghost := _mode.get_node("Ghost")
	var best := ""
	var best_d := INF
	for node in _main.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or ghost.is_ancestor_of(mi):
			continue
		if own != null and (own == mi or own.is_ancestor_of(mi)):
			continue
		var mat := mi.material_override if mi.material_override else mi.get_active_material(0)
		if mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != 0:
			continue
		var xf := mi.global_transform
		if (xf * mi.get_aabb()).intersects_segment(from, to) == null:
			continue
		var inv := xf.affine_inverse()
		var hit := mi.mesh.generate_triangle_mesh().intersect_segment(inv * from, inv * to)
		if not hit.is_empty() and from.distance_to(xf * hit["position"]) < best_d:
			best_d = from.distance_to(xf * hit["position"])
			best = "%s@%s" % [mi.name, xf * hit["position"]]
	return best


func _aim(world_pos: Vector3, dist: float, yaw: float) -> void:
	_rig.stop_follow()
	_rig.position = world_pos
	_rig.yaw = yaw
	_rig.distance = dist
	_rig.zoom(1.0)
	var roof := _main.get_node("RoofView") as RoofView
	roof.cutaway.snap(_rig.distance)
	roof.draw_level(roof.cutaway.roof_level)


func _cell(local_cell: Vector2i, up: float) -> Vector3:
	return _grid.cell_to_world(local_cell + _at) + Vector3(0.0, up, 0.0)


func _pax_in(stages: Array) -> Array[int]:
	var out: Array[int] = []
	for pid in _sim.passenger_ids():
		if stages.has(_sim.get_passenger(pid).stage) and _views.node_for(pid) != null:
			out.append(pid)
	return out


func _advance_until(stage: String, max_ticks: int, cond: Callable) -> bool:
	for _step in maxi(1, ceili(float(max_ticks) / 4.0)):
		if cond.call():
			break
		await _step_ticks(4)
	return _verify(cond.call(), "%s: timeout at tick %d" % [stage, _clock.tick])


func _step_ticks(count: int) -> void:
	_clock.set_paused(false)
	for _i in count:
		_clock.advance(SimClock.STEP)
	_clock.set_paused(true)
	_beat(_stage)
	await process_frame


func _frames(count: int) -> void:
	for _i in count:
		_beat(_stage)
		if _hud != null and is_instance_valid(_hud):
			_hud.refresh()
		await process_frame
	await RenderingServer.frame_post_draw


func _verify(ok: bool, msg: String) -> bool:
	if not ok:
		print("PROBE_INVALID %s" % msg)
		_failed = true
	return ok


func _beat(stage: String) -> void:
	_mutex.lock()
	_stage = stage
	_beat_ms = Time.get_ticks_msec()
	_mutex.unlock()


func _watch() -> void:
	var start := Time.get_ticks_msec()
	while true:
		OS.delay_msec(500)
		_mutex.lock()
		var done := _done
		var idle := Time.get_ticks_msec() - _beat_ms
		var stage := _stage
		_mutex.unlock()
		if done:
			return
		if idle > 90000 or Time.get_ticks_msec() - start > 480000:
			print("PROBE_INVALID hang in %s (idle %d ms)" % [stage, idle])
			OS.crash("store_screenshots_probe hung")
