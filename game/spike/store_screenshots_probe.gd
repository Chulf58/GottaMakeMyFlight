extends SceneTree
## Windowed 1920x1080 Steam store gameplay screenshots probe (board D6c, 3c5a08a9;
## finding bb598d8c; decisions a7f1b1e4 and 26acd3c7). Writes 6 verified
## 1920x1080 PNGs + contact_sheet.png under tools/blender/out/screenshots/.

const IntroClose := preload("res://spike/intro_close.gd")
const PlateSight := preload("res://spike/plate_sight.gd")
const SCREEN := Vector2i(1920, 1080)
const SETTINGS := "user://store_screenshots_probe_settings.cfg"
const PIECES := (
	"cafe_counter:23:3,cafe_table:24:4,cafe_table:24:6,cafe_counter:23:10,"
	+ "cafe_table:24:11,cafe_table:24:13,kiosk_counter:29:3,kiosk_display:32:3,"
	+ "kiosk_display:32:6,pharmacy_counter:29:10,pharmacy_shelf:32:10,"
	+ "pharmacy_shelf:32:13,screen_stand:17:4,plant_pot_1a:10:4,trash_can:28:4"
)

var _guard := Thread.new()
var _mutex := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _done := false
var _failed := false
var _out_dir := ""
var _saved: Array[String] = []
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
	print("PROBE out_dir=%s" % _out_dir)
	_run.call_deferred()


func _run() -> void:
	DirAccess.remove_absolute(SETTINGS)
	if await _boot_and_size() and _build_terminal():
		await _frames(8)
		await _shot_01_build_terminal()
		if await _shot_02_queues_and_belts():
			await _shot_03_follow_passenger()
			await _shot_04_cafes_and_shops()
			await _shot_05_apron_boarding()
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
	_check(root.size == SCREEN and vis_sz.is_equal_approx(Vector2(1536.0, 864.0)), "size")
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	_clock = _main.get_node("SimClock")
	var world_seed := IntroClose.seed_or_random()
	_clock.seed_rng(world_seed)
	print("PROBE world_seed=%d" % world_seed)
	_hud = _main.get_node("PassengerHud")
	_hud.debug_tools = false
	_hud.alert_settings_path = SETTINGS
	_hud.departures_settings_path = SETTINGS
	(_main.get_node("MoodOverlay") as MoodOverlay).settings_path = SETTINGS
	_mode = _main.get_node("BuildMode")
	_mode.starter_shell = false
	root.add_child(_main)
	current_scene = _main
	await _frames(5)
	_check(IntroClose.close(_main) == "", "intro hold")
	_clock.set_paused(true)
	_flights = _main.get_node("FlightSim")
	_sim = _main.get_node("PassengerSim")
	_views = _main.get_node("PassengerViews")
	_grid = _mode.grid
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	_cam.make_current()
	(_main.get_node("Finances") as Finances).wallet.credit(24000, Wallet.Category.FEES)
	var rating := _main.get_node("AirportRating") as AirportRating
	for _i in 220:
		rating.record_passenger(_clock.tick, true, 92)
	var seen: Array[String] = []
	for info: Dictionary in BuildUnlocks.TIERS.slice(1, 3):
		for tool: BuildMode.Tool in info["tools"]:
			seen.append(String(BuildMode.Tool.find_key(tool)))
	var snap := {"tier": 3, "made": 220, "shown": [2, 3], "seen": seen, "firsts": []}
	_mode.unlocks.from_snapshot(snap)
	return not _failed


func _build_terminal() -> bool:
	_beat("build_terminal")
	_at = ReferenceTerminal.offset_on(_grid)
	var land := _mode.land_tool.land
	while not land.buyable_plots().is_empty() and land.buy(land.buyable_plots()[0], null).ok:
		pass
	var east := _at + Vector2i(44, 0)
	var edits := ReferenceTerminal.edits(_at) + ReferenceTerminal.edits(east)
	edits.append_array(
		[ReferenceTerminal.gate_desk_edit(_at), ReferenceTerminal.gate_desk_edit(east)]
	)
	for y in range(3, 17):
		for x in range(22, 35):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y) + _at, BuildGrid.FLOOR_TILE, 1))
	for y in range(5, 14):
		for x in range(35, 54):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y) + _at, BuildGrid.FLOOR_TILE, 1))
	for x in range(22, 54):
		edits.append(BuildEdit.place_wall(Vector2i(x, 9) + _at, BuildGrid.Side.NORTH))
	for y in [4, 5, 6, 7, 11, 12, 13, 14, 15]:
		edits.append(BuildEdit.remove_wall(Vector2i(21, y) + _at, BuildGrid.Side.EAST))
	for y in [6, 7, 11, 12]:
		edits.append(BuildEdit.remove_wall(Vector2i(54, y) + _at, BuildGrid.Side.WEST))
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
		var c := Vector2i(int(p[1]), int(p[2])) + _at
		f_edits.append(BuildEdit.place_object(StringName(p[0]), c, 0))
	var bag_rect := Rect2i(Vector2i(15, 12) + _at, Vector2i(2, 3))
	ok = ok and _grid.apply_batch(f_edits).all(func(r: BuildResult) -> bool: return r.ok)
	ok = ok and RoomTool.mark(_grid, bag_rect, &"bag_room", null).ok
	for r in [[22, 3, &"cafe"], [22, 10, &"cafe"], [29, 3, &"kiosk"], [29, 10, &"pharmacy"]]:
		var rc := Rect2i(Vector2i(r[0], r[1]) + _at, Vector2i(6, 6))
		ok = ok and _grid.apply(BuildEdit.place_room(rc, r[2])).ok
	_mode.set_tool(BuildMode.Tool.BELT)
	for s in [[12, 10, 12, 9], [12, 9, 16, 9], [15, 10, 15, 9], [16, 9, 16, 12]]:
		_beat("belt")
		ok = ok and _mode.lay_belt(Vector2i(s[0], s[1]) + _at, Vector2i(s[2], s[3]) + _at).ok
	_mode.set_tool(BuildMode.Tool.NONE)
	ok = ok and RoomRules.status(_grid, _grid.room_at(bag_rect.position)).ok
	ok = ok and _sim.layout.security_lanes.is_complete(_grid.object_at(arch_at))
	_check(ok, "terminal build failed")
	if not ok:
		return false
	(_mode.get_node("BuildView") as BuildView).refresh(_grid)
	_sim.cafes.refresh()
	(_main.get_node("RoofView") as RoofView).rebuild()
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StaffTestKit.staff_all(staff)
	StaffTestKit.seat(staff, _grid.object_at(arch_at), StaffMember.Slot.HELPER)
	var two_gates: Array[String] = ["A", "B"]
	print("PROBE staffed=%d gates=%s" % [hired, _flights.gate_ids()])
	_check(_flights.gate_ids() == two_gates and hired >= 6, "gates/staff")
	return not _failed


func _shot_01_build_terminal() -> void:
	_beat("shot_01")
	var menu := _main.get_node("BuildMenu") as BuildMenu
	_aim(_cell(Vector2i(19, 9), 0.0), 24.0, 0.26)
	_mode.set_tool(BuildMode.Tool.SEATS)
	await _frames(6)
	var ghost := _mode.get_node("Ghost") as Node3D
	_mode.pointer_override = _cam.unproject_position(_cell(Vector2i(11, 14), 0.0))
	await _frames(6)
	print("SHOT01 ghost_vis=%s status='%s'" % [ghost.visible, _mode.status_text()])
	_check(ghost.visible and _mode.status_text().begins_with("Facing"), "shot_01: ghost invalid")
	var pts := [[_cell(Vector2i(14, 11), 1.1)], [_cell(Vector2i(20, 9), 1.8)]]
	var ui := {"tray": menu.tray(), "bar": menu.bar(), "status": menu.status_card()}
	await _capture("shot_01_build_terminal", pts, ui)
	_mode.pointer_override = Vector2(-1.0, -1.0)
	_mode.set_tool(BuildMode.Tool.NONE)
	if menu.is_tray_open():
		menu.press_category(menu.open_category())
	await _frames(4)


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
		terms.merge({"id": "GMF202", "airline": "Gotta Air", "destination": "Oslo"}, true)
		terms["departure_minute"] = (base_min + later) % GameCalendar.MINUTES_PER_DAY
		if _flights.accept_gate(terms) == "B" and _flights.accept_contract(terms):
			got_b = true
			break
	for ex in [["GMF303", 920, "Lisbon", "Sunhop"], ["GMF404", 1120, "Vienna", "Nordic Wing"]]:
		var t := TestFlightContracts.terms(ex[0], ex[1])
		t.merge({"destination": ex[2], "airline": ex[3], "plane_size": "small"}, true)
		t["booked_passengers"] = 14
		_flights.accept_contract(t)
	var desk := _main.get_node("OfferDesk") as OfferDesk
	desk.board = OfferBoard.new()
	desk._draw(GameCalendar.day_of(_clock.tick, _clock.epoch))
	if _flights.opened_tick < 0 or not got_b:
		_check(false, "open/schedule failed")
		return false
	var first := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	while not _flights.flight_ids().has(first):
		await _step_ticks(20)
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
		var both_q := not _pax_in(q_in).is_empty() and not _pax_in(q_sec).is_empty()
		return both_q and bv.active_count() >= 2
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
	return true


func _shot_03_follow_passenger() -> void:
	_beat("shot_03")
	var chosen := 0
	for _k in 40:
		for pid in _sim.passenger_ids():
			var p := _sim.get_passenger(pid)
			if _views.node_for(pid) != null and p.stage < Passenger.Stage.MADE:
				chosen = pid if not PassengerThoughts.entries(p).is_empty() else chosen
		if chosen != 0:
			break
		await _step_ticks(15)
	_check(chosen != 0, "shot_03: no passenger with thoughts")
	if chosen == 0:
		return
	var pn := _views.node_for(chosen)
	_views.selected_id = chosen
	_views.follow_anchor.global_position = pn.global_position
	_aim(Vector3(pn.global_position.x, 0.0, pn.global_position.z), 14.5, 0.38)
	_rig.follow(_views.follow_anchor)
	await _frames(12)
	var inspect := _hud.find_child("PassengerInspect", true, false) as Control
	var thought0 := inspect.find_child("Thought0", true, false) as Control
	_check(thought0 != null and thought0.is_visible_in_tree(), "shot_03: Thought0 hidden")
	pn = _views.node_for(chosen)
	var head := pn.global_position + Vector3(0.0, 1.35, 0.0)
	_check(Rect2(440.0, 120.0, 760.0, 560.0).has_point(_cam.unproject_position(head)), "off-center")
	await _capture("shot_03_follow_passenger", [[head, pn]], {"inspect": inspect})
	_views.selected_id = 0
	_rig.stop_follow()
	await _frames(4)


func _shot_04_cafes_and_shops() -> void:
	_beat("shot_04")
	var first := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	for i in 8:
		var p := _sim.get_passenger(_sim.spawn_now(first))
		p.cleared = i % 2 == 0
		p.carry_on = 0
		p.at = (Vector2i(20, 6) if p.cleared else Vector2i(20, 12)) + _at
		p.stage = Passenger.Stage.TO_GATE if p.cleared else Passenger.Stage.TO_SECURITY
		p.stage_tick = _clock.tick
		p.clear_path()
		p.hunger = 56 if i % 2 == 0 else 44
		p.boredom = 78
	var cafe_st := [Passenger.Stage.CAFE_ORDER, Passenger.Stage.CAFE_SEATED]
	var shop_st := [Passenger.Stage.SHOP_BROWSE]
	var ready := func() -> bool:
		return _pax_in(cafe_st).size() >= 2 and not _pax_in(shop_st).is_empty()
	if not await _advance_until("cafes_and_shops", 1200, ready):
		return
	_aim(_cell(Vector2i(28, 8), 0.0), 19.5, -0.22)
	await _frames(10)
	var sub: Array = [[_cell(Vector2i(23, 3), 1.1)], [_cell(Vector2i(32, 3), 1.1)]]
	for pid in _pax_in(cafe_st + shop_st).slice(0, 2):
		var pn := _views.node_for(pid)
		sub.append([pn.global_position + Vector3(0.0, 1.15, 0.0), pn])
	var bar := (_main.get_node("BuildMenu") as BuildMenu).bar()
	await _capture("shot_04_cafes_and_shops", sub, {"bar": bar})


func _shot_05_apron_boarding() -> void:
	_beat("shot_05")
	var day: int = _flights.start_days["GMF202"]
	var occ_a := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, day)
	var occ_b := FlightTimetable.occurrence_id("GMF202", day)
	while not (_flights.flight_ids().has(occ_a) and _flights.flight_ids().has(occ_b)):
		await _step_ticks(40)
	var push_a := _flights.state_start(occ_a, FlightSim.State.PUSHBACK)
	while _clock.tick < push_a - 105:
		await _step_ticks(mini(30, push_a - 105 - _clock.tick))
	for _i in 8:
		var p := _sim.get_passenger(_sim.spawn_now(occ_b))
		p.cleared = true
		p.carry_on = 0
		p.at = Vector2i(63, 4) + _at
		p.stage = Passenger.Stage.TO_GATE
		p.stage_tick = _clock.tick
		p.clear_path()
		await _step_ticks(8)
	while _clock.tick < push_a + 8:
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
	if not await _advance_until("apron_boarding", 100, ready):
		return
	var view_a: PlaneView = null
	var view_b: PlaneView = null
	for v in fleet:
		view_a = v if v.gate == "A" and v.visible else view_a
		view_b = v if v.gate == "B" and v.visible else view_b
	var tug := (view_a.get_node("Props") as PlaneProps).tug
	var mid := (view_a.global_position + view_b.global_position) * 0.5 + Vector3(-16.0, 0.0, 4.0)
	_aim(Vector3(mid.x, 0.0, mid.z), 56.0, 0.08)
	await _frames(14)
	var dep := _main.find_child("DeparturesPanel", true, false) as Control
	var tug_pt := tug.global_position + Vector3(0.0, 1.2, 0.0)
	_check(_cam.unproject_position(tug_pt).x >= 340.0, "shot_05: tug behind DeparturesBoard")
	var sub: Array = [[view_b.global_position + Vector3(0.0, 2.6, 0.0), view_b], [tug_pt, view_a]]
	for pid in _pax_in([Passenger.Stage.APRON]):
		var n := _views.node_for(pid)
		var pt := n.global_position + Vector3(0.0, 1.45, 0.0)
		if n.global_position.z < -100.5 and _occluder(pt, n) == "" and sub.size() < 4:
			sub.append([pt, n])
	_check(sub.size() >= 4, "shot_05: fewer than 2 unoccluded apron walkers")
	await _capture("shot_05_apron_boarding", sub, {"departures_board": dep})


func _shot_06_airline_offers() -> void:
	_beat("shot_06")
	var offers := _main.get_node("OfferPanel") as OfferPanel
	_aim(_cell(Vector2i(22, 9), 0.0), 38.0, 0.22)
	offers.open()
	await _frames(10)
	var badge := _main.get_node("RatingBadge").find_child("*", true, false) as Control
	var clock_pnl := _hud.find_child("FlightPanel", true, false)
	var ui := {"offers": offers.sheet(), "clock": clock_pnl, "rating": badge}
	await _capture("shot_06_airline_offers", [[_cell(Vector2i(12, 11), 1.0)]], ui)
	offers.close()
	await _frames(4)


func _capture(label: String, subjects: Array, ui: Dictionary) -> void:
	await _frames(6)
	var view := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var safe := view.grow(-10.0)
	var dbg := _hud.find_child("DebugCorner", true, false) as Control
	_check(dbg == null or not dbg.is_visible_in_tree(), "%s: DebugCorner visible" % label)
	var ctrl_hit := _occluder(Vector3(-27.0, -2.5, -90.0))
	print("PLATE %s control='%s'" % [label, ctrl_hit])
	_check(ctrl_hit != "", "%s: underground raycast control failed" % label)
	for key in ui:
		var ctrl := ui[key] as Control
		var r := Rect2() if ctrl == null else ctrl.get_global_rect()
		var ok := ctrl != null and ctrl.is_visible_in_tree() and r.has_area() and view.encloses(r)
		print("  UI %s %s rect=%s ok=%s" % [label, key, r, ok])
		_check(ok, "%s: UI '%s' out of view (%s)" % [label, key, r])
	for item: Array in subjects:
		var pt: Vector3 = item[0]
		var px := _cam.unproject_position(pt)
		var in_f := not _cam.is_position_behind(pt) and safe.has_point(px)
		var hit := _occluder(pt, item[1]) if item.size() > 1 else ""
		print("  SUBJECT %s pt=%s px=%s hit='%s' in_f=%s" % [label, pt, px.round(), hit, in_f])
		_check(in_f and hit == "", "%s: %s occluded ('%s') or out" % [label, pt, hit])
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := _out_dir.path_join("%s.png" % label)
	var disk := Image.load_from_file(path) if img.save_png(path) == OK else null
	var btm := PlateSight.empty_bottom(disk) if disk != null else {"ok": false, "share": 1.0}
	var blank := Image.create(SCREEN.x, SCREEN.y, false, Image.FORMAT_RGBA8)
	var diff := PlateSight.differing(disk, blank, Rect2i(Vector2i.ZERO, SCREEN), 16) if disk else 0
	var sz := disk.get_size() if disk else Vector2i.ZERO
	print("PLATE %s size=%s non_blank=%d empty_btm=%.3f" % [label, sz, diff, btm["share"]])
	_check(sz == SCREEN and diff > 500 and bool(btm["ok"]), "%s: disk check failed" % label)
	_saved.append(path)
	if _saved.size() == 6:
		var sheet := Image.create(1920, 1620, false, Image.FORMAT_RGBA8)
		for i in 6:
			var tile := Image.load_from_file(_saved[i])
			tile.convert(Image.FORMAT_RGBA8)
			tile.resize(960, 540, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(tile, Rect2i(0, 0, 960, 540), Vector2i((i % 2) * 960, (i / 2) * 540))
		var out := _out_dir.path_join("contact_sheet.png")
		_check(sheet.save_png(out) == OK, "contact_sheet.png failed")
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
	var limit := _clock.tick + max_ticks
	while _clock.tick < limit and not cond.call():
		await _step_ticks(4)
	_check(cond.call(), "%s: timeout at tick %d" % [stage, _clock.tick])
	return cond.call()


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


func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("PROBE_INVALID %s" % msg)
		_failed = true


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
