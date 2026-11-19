extends SceneTree
## Reproducible 1920x1080 @ 30 fps live gameplay trailer capture probe (board D8b,
## decision 888d509e; Steam trailer rules bb598d8c; VSE mux finding 6e1afa0d).
##
## Run windowed (holding the one project-wide windowed Godot slot):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy --fixed-fps 30 \
##     --resolution 1920x1080 --path <game> \
##     -s res://spike/gameplay_trailer_probe.gd [-- --seed=N] [-- --smoke] < /dev/null
##
## Saves 1920x1080 PNG frames ONLY during active recorded shots (skipping boot,
## settle and inter-shot simulation steps) as <out>/frames/shotNNNNNNNN.png, plus
## shots.json (or shots_smoke.json) with frame-accurate audio events and visible
## HUD panel rects in 1920x1080 screen pixels.

const StarterFlight := preload("res://spike/starter_flight.gd")
const IntroClose := preload("res://spike/intro_close.gd")
const PlateSight := preload("res://spike/plate_sight.gd")

const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/gameplay-trailer"
const SETTINGS := "user://gameplay_trailer_probe_settings.cfg"
const DEFAULT_SEED := 20261119
const SCREEN := Vector2i(1920, 1080)
const FPS := 30
const BEAT := 18
const HANDLE := 8
const SETTLE := 18
const MARGIN_PX := 36.0
const NO_TAG := "no_subject"
const LOW := 0
const MEDIUM := 1
const TRY_YAWS: Array[float] = [0.0, 0.35, -0.35, 0.75, -0.75, PI]
const FIXED_YAW: Array[float] = [0.0]

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
	+ "screen_stand:49:4,plant_pot_1a:10:4,plant_pot_1a:42:4,trash_can:28:4,"
	+ "trash_can:35:4,trash_can:35:13"
)
const OCCLUDER_OWNERS: Array[String] = [
	"Ground",
	"BuildMode",
	"Airside",
	"PlaneView",
	"PlaneView2",
	"PlaneFleet",
	"ApronStand",
	"PassengerViews",
	"BaggageViews",
	"StaffCharacters",
	"LandsideViews",
	"RoofView",
]

var _guard := Thread.new()
var _mutex := Mutex.new()
var _beat_ms := 0
var _stage_name := "init"
var _done := false
var _failed := false
var _smoke := false
var _handle := HANDLE
var _settle := SETTLE
var _out_dir := ""
var _frames_dir := ""
var _seed := DEFAULT_SEED
var _frame_seq := 0
var _shots: Array[Dictionary] = []
var _recording := false
var _cur_events: Array[Dictionary] = []
var _cur_frame := 0
var _last_place_frame := -99
var _last_cash_frame := -99
var _built := false
var _control_done := false
var _at := Vector2i.ZERO
var _arch_id := 0
var _hero := 0
var _flight_a := ""
var _flight_b := ""

var _main: Node3D
var _clock: SimClock
var _mode: BuildMode
var _grid: BuildGrid
var _menu: BuildMenu
var _hud: PassengerHud
var _rig: TycoonCamera
var _cam: Camera3D
var _sim: PassengerSim
var _views: PassengerViews
var _flights: FlightSim
var _staff: StaffSim
var _staff_views: StaffCharacters
var _landside: LandsideSim
var _cars: LandsideViews
var _bag_sim: BaggageSim
var _bag_views: BaggageViews


func _initialize() -> void:
	_beat("init")
	_guard.start(_watch)
	for arg in OS.get_cmdline_user_args():
		if arg == "--smoke":
			_smoke = true
		elif arg.begins_with("--seed="):
			_seed = int(arg.get_slice("=", 1))
	if _smoke:
		_handle = 4
		_settle = 8
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	_frames_dir = _out_dir.path_join("frames")
	DirAccess.make_dir_recursive_absolute(_frames_dir)
	_clean_old_frames()
	_run.call_deferred()


func _clean_old_frames() -> void:
	var dir := DirAccess.open(_frames_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.begins_with("shot") and fname.ends_with(".png"):
			DirAccess.remove_absolute(_frames_dir.path_join(fname))
		fname = dir.get_next()
	dir.list_dir_end()


func _run() -> void:
	DirAccess.remove_absolute(SETTINGS)
	if await _boot():
		var seq: Array[Callable] = [
			_shot_01_shell,
			_shot_02_furnish,
			_shot_03_staff,
			_shot_04_curb,
			_shot_05_follow,
			_shot_06_security,
			_shot_07_shops,
			_shot_08_offers,
			_shot_09_boarding,
			_shot_10_pullback,
			_shot_11_takeoff,
		]
		for step in seq:
			if _main == null or _failed:
				break
			await step.call()
	_write_manifest()
	DirAccess.remove_absolute(SETTINGS)
	DirAccess.remove_absolute(SETTINGS + ".tmp")
	print("PROBE done failed=%s shots=%d final_frame=%d" % [_failed, _shots.size(), _frame_seq])
	_mutex.lock()
	_done = true
	_mutex.unlock()
	if _guard.is_started():
		_guard.wait_to_finish()
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
	quit(1 if _failed or _shots.size() != 11 else 0)


func _boot() -> bool:
	_beat("boot")
	DisplayServer.window_set_position(Vector2i.ZERO)
	DisplayServer.window_set_size(SCREEN)
	await _frames(8)
	if root.size != SCREEN:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		DisplayServer.window_set_size(SCREEN)
		await _frames(8)
	var vis_sz := root.get_visible_rect().size
	print("PROBE seed=%d smoke=%s window=%s layout=%s" % [_seed, _smoke, root.size, vis_sz])
	if root.size != SCREEN or not vis_sz.is_equal_approx(Vector2(1536.0, 864.0)):
		_invalid("window size %s / layout %s != 1920x1080 / 1536x864" % [root.size, vis_sz])
		return false
	var main := (load(MAIN_SCENE) as PackedScene).instantiate() as Node3D
	_clock = main.get_node("SimClock")
	seed(_seed)
	_clock.seed_rng(_seed)
	_hud = main.get_node("PassengerHud")
	_hud.debug_tools = false
	_hud.alert_settings_path = SETTINGS
	_hud.departures_settings_path = SETTINGS
	(main.get_node("MoodOverlay") as MoodOverlay).settings_path = SETTINGS
	_rig = main.get_node("TycoonCamera")
	_rig.settings_path = SETTINGS
	_mode = main.get_node("BuildMode")
	_mode.starter_shell = false
	root.add_child(main)
	current_scene = main
	_clock.set_process(false)
	await _frames(5)
	var problem := IntroClose.close(main)
	if problem != "":
		_invalid(problem)
		return false
	_main = main
	_mode.set_process(false)
	_mode.set_tool(BuildMode.Tool.NONE)
	(_mode.get_node("Ghost") as Node3D).visible = false
	(_main.get_node("HoverTarget") as Node).set_process(false)
	_rig.set_process_unhandled_input(false)
	_grid = _mode.grid
	_menu = _main.get_node("BuildMenu")
	_cam = _rig.get_node("Camera3D")
	_cam.make_current()
	_sim = _main.get_node("PassengerSim")
	_views = _main.get_node("PassengerViews")
	_flights = _main.get_node("FlightSim")
	_staff = _main.get_node("Staff")
	_staff_views = _main.get_node("StaffCharacters")
	_landside = _main.get_node("LandsideSim")
	_cars = _main.get_node("LandsideViews")
	_bag_sim = _main.get_node("BaggageSim")
	_bag_views = _main.get_node("BaggageViews")
	(_main.get_node("Finances") as Finances).wallet.credit(52000, Wallet.Category.FEES)
	_unlock_all_tiers()
	_buy_land_silently()
	_at = ReferenceTerminal.offset_on(_grid)
	for b: Dictionary in (_main.get_node("Airside") as Airside).props.bridges.values():
		(b["node"] as Node3D).visible = false
	_grid.edit_applied.connect(_on_grid_edit_applied)
	_sim.cafes.paid.connect(_on_shop_or_cafe_paid)
	_sim.shops.paid.connect(_on_shop_or_cafe_paid)
	_clock.set_speed(1)
	_clock.set_paused(false)
	return true


func _unlock_all_tiers() -> void:
	var seen: Array[String] = []
	for info: Dictionary in BuildUnlocks.TIERS.slice(1, 3):
		for tool: BuildMode.Tool in info["tools"]:
			seen.append(String(BuildMode.Tool.find_key(tool)))
	var snap := {"tier": 3, "made": 200, "shown": [2, 3], "seen": seen, "firsts": []}
	_mode.unlocks.from_snapshot(snap)


func _buy_land_silently() -> void:
	var land := _mode.land_tool.land
	for _i in 64:
		if land.buyable_plots().is_empty() or not land.buy(land.buyable_plots()[0], null).ok:
			break


func _on_grid_edit_applied(edit: BuildEdit, _result: BuildResult) -> void:
	if not _recording or edit == null:
		return
	var removals := [
		BuildEdit.Kind.REMOVE_FLOOR,
		BuildEdit.Kind.REMOVE_WALL,
		BuildEdit.Kind.REMOVE_OBJECT,
		BuildEdit.Kind.REMOVE_ROOM,
	]
	if removals.has(edit.kind):
		if _cur_frame - _last_place_frame >= 3:
			_last_place_frame = _cur_frame
			_log_sfx("build_remove")
	elif _cur_frame - _last_place_frame >= 3:
		_last_place_frame = _cur_frame
		_log_sfx("build_place")


func _on_shop_or_cafe_paid(_pid: int, _room_id: int, _amount: int) -> void:
	if _recording and _cur_frame - _last_cash_frame >= 8:
		_last_cash_frame = _cur_frame
		_log_sfx("cash_chime")


func _log_sfx(kind: String, extra: Dictionary = {}) -> void:
	var ev := {"shot_frame": _cur_frame, "type": kind}
	ev.merge(extra)
	_cur_events.append(ev)


## Shot 01 (12 beats = 7.20 s): Empty plot -> 2-gate terminal shell snapping in.
func _shot_01_shell() -> void:
	_beat("s01_shell")
	var batches := _shell_batches()
	var centre := _cell(Vector2(32.0, 10.0))
	var points := _two_gate_points()
	await _frames(_settle)
	var near := maxf(_fit(LOW, centre, 0.24, 42.0, points.values()), 42.0) + 4.0
	var view := await _stage("s01_shell", LOW, centre, 0.40, near * 1.12, points, null, FIXED_YAW)
	var far: float = view["dist"]
	var total_b := batches.size()
	var drive := func(i: int, total: int) -> void:
		var t := float(i) / float(maxi(1, total - 1))
		_aim(LOW, centre, lerpf(0.40, 0.24, t), lerpf(far, near, t))
		var span := maxi(1, total - 2 * _handle)
		if i >= _handle and i < total - _handle:
			var target_done := int(round(float(i - _handle + 1) / float(span) * float(total_b)))
			while total_b - batches.size() < target_done and not batches.is_empty():
				_apply_next(batches)
	await _record("s01_shell", 12, drive, false)
	_flush(batches)
	EnclosureKit.close_floor(_grid)
	(_mode.get_node("BuildView") as BuildView).refresh(_grid)
	(_main.get_node("RoofView") as RoofView).rebuild()
	_end_check("s01_shell", points)


## Shot 02 (13 beats = 7.80 s): Furnish check-in, bag belt, 4-part security lane,
## Gate A & Gate B desks/seats/screens, cafes, kiosk, pharmacy & bi-fold toilets.
func _shot_02_furnish() -> void:
	_beat("s02_furnish")
	var batches := _furnish_batches()
	var f_start := _cell(Vector2(18.5, 9.8))
	var f_end := _cell(Vector2(29.5, 9.5))
	var points := {
		"checkin": _cell(Vector2(13.5, 11.5)),
		"sec_lane": _cell(Vector2(20.5, 9.5)),
		"cafes": _cell(Vector2(24.5, 6.5)),
	}
	var view := await _stage("s02_furnish", LOW, f_start, 0.26, 25.0, points, null, FIXED_YAW)
	var dist: float = view["dist"]
	var total_b := batches.size()
	var opened_tray := [false]
	var drive := func(i: int, total: int) -> void:
		var t := smoothstep(0.0, 1.0, float(i) / float(maxi(1, total - 1)))
		_aim(LOW, f_start.lerp(f_end, t), lerpf(0.26, -0.16, t), lerpf(dist, dist * 0.96, t))
		var span := maxi(1, total - 2 * _handle - 24)
		if i >= _handle and i < _handle + span:
			var target_done := int(round(float(i - _handle + 1) / float(span) * float(total_b)))
			while total_b - batches.size() < target_done and not batches.is_empty():
				_apply_next(batches)
		if not _smoke and i == _handle + 126 and not opened_tray[0]:
			opened_tray[0] = true
			_mode.set_tool(BuildMode.Tool.SEATS)
			_mode.pointer_override = _cam.unproject_position(_cell(Vector2(28.5, 8.5)))
			_log_sfx("ui_click")
	await _record("s02_furnish", 13, drive, false)
	_flush(batches)
	_mode.pointer_override = Vector2(-1.0, -1.0)
	_mode.set_tool(BuildMode.Tool.NONE)
	if _menu.is_tray_open():
		_menu.press_category(_menu.open_category())
	_finalize_terminal_build()
	_end_check(
		"s02_furnish", {"cafes": _cell(Vector2(24.5, 6.5)), "kiosk": _cell(Vector2(31.0, 6.0))}
	)


func _finalize_terminal_build() -> void:
	for b: Dictionary in (_main.get_node("Airside") as Airside).props.bridges.values():
		(b["node"] as Node3D).visible = false
	for rid in _grid.room_ids():
		if not RoomRules.status(_grid, rid).ok:
			_invalid("room %d invalid: %s" % [rid, RoomRules.status(_grid, rid).text()])
	_sim.cafes.refresh()
	_sim.toilets.refresh()
	var arch_at := Vector2i(20, 9) + _at
	_arch_id = _grid.object_at(arch_at)
	var stalls := _sim.toilets.layout.stalls.size()
	if not _sim.layout.security_lanes.is_complete(_arch_id) or stalls != 4:
		_invalid(
			(
				"4-part lane complete=%s stalls=%d"
				% [_sim.layout.security_lanes.is_complete(_arch_id), stalls]
			)
		)
	(_mode.get_node("BuildView") as BuildView).refresh(_grid)
	(_main.get_node("RoofView") as RoofView).rebuild()
	_built = true


## Shot 03 (10 beats = 6.00 s): Staff up & open the airport.
func _shot_03_staff() -> void:
	_beat("s03_staff")
	await _frames(4)
	var roles: Array[StaffMember.Role] = []
	for _c in _sim.staff.stations_of(StaffMember.Role.SHOP):
		roles.append(StaffMember.Role.SHOP)
	for _d in _sim.layout.desks:
		roles.append(StaffMember.Role.CHECKIN)
	for _s in _sim.layout.scanners:
		roles.append(StaffMember.Role.SECURITY)
	var hired := 0
	for role in roles:
		hired += int(_staff.hire(role) != 0)
		StarterFlight.advance_until(_clock, func() -> bool: return false, 14)
	print("PROBE s03_staff hired=%d gates=%s" % [hired, _flights.gate_ids()])
	if hired < 6 or _flights.gate_ids() != ["A", "B"]:
		_invalid("s03_staff: hired=%d gates=%s" % [hired, _flights.gate_ids()])
		return
	var hall := _cell(Vector2(18.5, 12.5))
	_aim(MEDIUM, hall, -0.22, 22.0)
	var seen := func() -> bool: return _walking_staff().size() >= 2
	StarterFlight.advance_until(_clock, seen, 600)
	await _skip_done()
	var subject: Node3D = null
	var best_d := INF
	for sid in _walking_staff():
		var sn := _staff_views.node_for(sid)
		if sn != null and _cam.global_position.distance_to(sn.global_position) < best_d:
			best_d = _cam.global_position.distance_to(sn.global_position)
			subject = sn
	var points := {"hall": hall, "entrance": _cell(Vector2(17.5, 15.5))}
	var view := await _stage("s03_staff", MEDIUM, hall, -0.22, 22.0, points, subject, TRY_YAWS)
	var yaw: float = view["yaw"]
	var dist: float = view["dist"]
	var toggled := [false, false]
	var drive := func(i: int, total: int) -> void:
		var t := float(i) / float(maxi(1, total - 1))
		_aim(MEDIUM, hall, yaw + 0.14 * t, lerpf(dist, dist * 0.90, t))
		if not _smoke and i == _handle + 4 and not toggled[0]:
			toggled[0] = true
			_menu.press_staff()
			_log_sfx("ui_click")
		if not _smoke and i == _handle + 68 and not toggled[1]:
			toggled[1] = true
			if _menu.staff_open:
				_menu.press_staff()
				_log_sfx("ui_click")
	await _record("s03_staff", 10, drive, true)
	if _menu.staff_open:
		_menu.press_staff()
	_end_check("s03_staff", points)
	if _staff_in_frame().is_empty():
		_invalid("s03_staff: no staff member in frame at end")


## Shot 04 (12 beats = 7.20 s): Curb drop-off, rollers/totes in check-in, red bags on belt.
func _shot_04_curb() -> void:
	_beat("s04_curb")
	StaffTestKit.staff_all(_staff)
	StaffTestKit.seat(_staff, _arch_id, StaffMember.Slot.HELPER)
	_staff.hire(StaffMember.Role.CLEANER)
	_staff.hire(StaffMember.Role.CLEANER)
	_flight_a = StarterFlight.first_flight()
	var is_open := func() -> bool:
		return _flights.opened_tick >= 0 and _flights.flight_ids().has(_flight_a)
	if not StarterFlight.advance_until(_clock, is_open, 4500):
		_invalid("s04_curb: airport did not open by tick %d" % _clock.tick)
		return
	_dismiss_popups()
	_schedule_extra_flights()
	var berth_car := [0]
	var car_ready := func() -> bool:
		berth_car[0] = _car_in(LandsideVehicle.Lane.BERTH)
		return berth_car[0] != 0
	StarterFlight.advance_until(_clock, car_ready, 2400)
	for i in 12:
		var pid := _sim.spawn_now(_flight_a)
		var p := _sim.get_passenger(pid)
		p.carry_on = 1 + (i % 2)
		p.liquids = false
		p.alarm = false
		p.hunger = 54 if i % 3 == 0 else p.hunger
		p.boredom = 74 if i % 3 == 1 else p.boredom
		StarterFlight.advance_until(_clock, func() -> bool: return false, 8)
	var q_in: Array[int] = [Passenger.Stage.CHECKIN_QUEUE, Passenger.Stage.CHECKIN]
	var ready := func() -> bool:
		if _car_in(LandsideVehicle.Lane.BERTH) != 0:
			berth_car[0] = _car_in(LandsideVehicle.Lane.BERTH)
		return _pax_in(q_in).size() >= 2 and _bag_views.active_count() >= 1
	StarterFlight.advance_until(_clock, ready, 600)
	await _skip_done()
	_dismiss_popups()
	var entrance := _cell(Vector2(ReferenceTerminal.ENTRANCE_CELL) + Vector2(0.5, 1.0))
	var berth := entrance + Vector3(0.0, 0.0, 12.0)
	if berth_car[0] != 0 and _landside.get_vehicle(berth_car[0]) != null:
		berth = _landside.definition.berth_position(_landside.get_vehicle(berth_car[0]).stop)
	var focus := berth.lerp(_cell(Vector2(15.0, 11.5)), 0.52)
	var points := {
		"berth": berth,
		"entrance": entrance,
		"checkin": _cell(Vector2(14.0, 11.5)),
	}
	var subject: Node3D = null
	if berth_car[0] != 0 and _cars.has_vehicle(berth_car[0]):
		subject = _cars.node_for(berth_car[0])
	var view := await _stage("s04_curb", LOW, focus, 0.22, 28.0, points, subject, TRY_YAWS)
	var yaw: float = view["yaw"]
	var dist: float = view["dist"]
	var logged := [false]
	var drive := func(i: int, total: int) -> void:
		if not logged[0] and i == _handle:
			logged[0] = true
			_log_sfx("car_arrive")
			_log_sfx("roller", {"dur": 90})
		var t := float(i) / float(maxi(1, total - 1))
		_aim(
			LOW,
			focus.lerp(_cell(Vector2(15.5, 12.5)), 0.35 * t),
			yaw - 0.12 * t,
			lerpf(dist * 1.04, dist * 0.94, t)
		)
	await _record("s04_curb", 12, drive, true)
	_end_check("s04_curb", {"entrance": entrance, "checkin": _cell(Vector2(14.0, 11.5))})


func _schedule_extra_flights() -> void:
	var base_min: int = _flights.contract_of(FlightSim.DEFAULT_ID)["departure_minute"]
	for later in range(18, 75):
		var terms := StarterSlot.departing(
			StarterSlot.whole_minute(FlightTimetable.issue_lead(), 0), 0
		)
		terms.merge({"id": "GMF202", "airline": "Blue Fjord", "destination": "Bergen"}, true)
		terms["departure_minute"] = (base_min + later) % GameCalendar.MINUTES_PER_DAY
		if _flights.accept_gate(terms) == "B" and _flights.accept_contract(terms):
			_flight_b = FlightTimetable.occurrence_id("GMF202", int(_flights.start_days["GMF202"]))
			break
	var specs := "GMF303:720:Lisbon:Sunhop,GMF404:900:Vienna:Nordic Wing"
	for spec in specs.split(","):
		var p := spec.split(":")
		for m_off in [0, 30, 60, 90]:
			var t := TestFlightContracts.terms(p[0], int(p[1]) + m_off)
			t.merge({"destination": p[2], "airline": p[3], "plane_size": "small"}, true)
			t["booked_passengers"] = 14
			if _flights.accept_problem(t) == "" and _flights.accept_contract(t):
				break


## Shot 05 (14 beats = 8.40 s): Follow every passenger — Check-in to Security.
func _shot_05_follow() -> void:
	_beat("s05_follow")
	_dismiss_popups()
	var flow_st: Array[int] = [
		Passenger.Stage.CHECKIN_QUEUE,
		Passenger.Stage.CHECKIN,
		Passenger.Stage.TO_SECURITY,
		Passenger.Stage.SECURITY_QUEUE,
	]
	if _pax_in(flow_st).is_empty():
		for i in 3:
			var fp := _spawn_positioned(_flight_a, Vector2i(14, 13 + i), false)
			fp.carry_on = 1 + (i % 2)
			fp.liquids = false
			fp.alarm = false
	_hero = _pick_hero_passenger()
	if _hero == 0:
		_invalid("s05_follow: no suitable passenger to follow")
		return
	await _skip_done()
	var node := _views.node_for(_hero)
	_views.selected_id = _hero
	_views.follow_anchor.global_position = node.global_position
	var points := {"hero": node.global_position}
	var view := await _stage(
		"s05_follow", MEDIUM, node.global_position, 0.32, 15.5, points, node, TRY_YAWS
	)
	var yaw: float = view["yaw"]
	var dist: float = view["dist"]
	_rig.follow(_views.follow_anchor)
	await _frames(6)
	var inspect := _hud.find_child("PassengerInspect", true, false) as Control
	if inspect == null or not inspect.is_visible_in_tree():
		_invalid("s05_follow: PassengerInspect card is not visible")
	var clicked := [false]
	var drive := func(i: int, total: int) -> void:
		if not clicked[0] and i == _handle:
			clicked[0] = true
			_log_sfx("ui_click")
			_log_sfx("roller", {"dur": 120})
		var t := float(i) / float(maxi(1, total - 1))
		_rig.yaw = wrapf(yaw - 0.22 * t, -PI, PI)
		_rig.distance = lerpf(dist, dist * 0.92, t)
	await _record("s05_follow", 14, drive, true)
	_rig.stop_follow()
	if is_instance_valid(node):
		_end_check("s05_follow", {"hero": node.global_position})
	_views.selected_id = 0
	await _frames(3)


func _pick_hero_passenger() -> int:
	var target_stages: Array[int] = [
		Passenger.Stage.CHECKIN,
		Passenger.Stage.TO_SECURITY,
		Passenger.Stage.SECURITY_QUEUE,
		Passenger.Stage.CHECKIN_QUEUE,
	]
	for _step in 40:
		var fallback := 0
		for pid in _sim.passenger_ids():
			var p := _sim.get_passenger(pid)
			if p == null or _views.node_for(pid) == null or p.is_done():
				continue
			if target_stages.has(int(p.stage)):
				fallback = pid
				if p.carry_on >= 1 and not PassengerThoughts.entries(p).is_empty():
					p.liquids = false
					p.alarm = false
					return pid
		if fallback != 0 and _step >= 12:
			var pf := _sim.get_passenger(fallback)
			pf.carry_on = maxi(1, pf.carry_on)
			pf.liquids = false
			pf.alarm = false
			return fallback
		StarterFlight.advance_until(_clock, func() -> bool: return false, 8)
	return 0


## Shot 06 (12 beats = 7.20 s): Security tray & carry-on pickup close-up.
func _shot_06_security() -> void:
	_beat("s06_security")
	_dismiss_popups()
	for i in 5:
		var p := _spawn_positioned(_flight_a, Vector2i(18 + (i % 2), 11 + (i / 2)), false)
		p.carry_on = 1 + (i % 2)
		p.liquids = false
		p.alarm = false
	var at_lane := func() -> bool:
		for pid in _pax_in([Passenger.Stage.SECURITY]):
			var p := _sim.get_passenger(pid)
			if p.station == _arch_id:
				return true
		return false
	StarterFlight.advance_until(_clock, at_lane, 600)
	await _skip_done()
	var lane_pos := _cell(Vector2(20.2, 9.2))
	var points := {
		"tray": _cell(Vector2(21.2, 9.8)),
		"arch": _cell(Vector2(20.5, 9.2)),
		"pickup": _cell(Vector2(18.8, 8.8)),
	}
	var subject: Node3D = null
	for pid in _pax_in([Passenger.Stage.SECURITY, Passenger.Stage.SECURITY_QUEUE]):
		var pn := _views.node_for(pid)
		if pn != null and pn.global_position.distance_to(lane_pos) < 4.5:
			subject = pn
			break
	var view := await _stage(
		"s06_security", MEDIUM, lane_pos, -0.22, 13.5, points, subject, TRY_YAWS
	)
	var yaw: float = view["yaw"]
	var dist: float = view["dist"]
	var beeped := {}
	var drive := func(i: int, total: int) -> void:
		var t := float(i) / float(maxi(1, total - 1))
		_aim(MEDIUM, lane_pos, yaw + 0.30 * t, lerpf(dist, dist * 0.92, t))
		for pid in _pax_in([Passenger.Stage.SECURITY]):
			var p := _sim.get_passenger(pid)
			if p.station == _arch_id and p.security_phase == SecurityRuntime.Phase.PICKUP:
				if not beeped.has(pid):
					beeped[pid] = true
					_log_sfx("scanner_beep")
	await _record("s06_security", 12, drive, true)
	_end_check(
		"s06_security", {"arch": _cell(Vector2(20.5, 9.2)), "pickup": _cell(Vector2(18.8, 8.8))}
	)


## Shot 07 (12 beats = 7.20 s): Bustling cafes, kiosk, pharmacy & bi-fold toilets + cash pops.
func _shot_07_shops() -> void:
	_beat("s07_shops")
	_dismiss_popups()
	var active_occ := _flight_a
	if _flight_b != "" and _flights.flight_ids().has(_flight_b):
		active_occ = _flight_b
	var spots: Array[Vector2i] = [
		Vector2i(21, 6),
		Vector2i(21, 11),
		Vector2i(27, 6),
		Vector2i(27, 11),
		Vector2i(34, 6),
		Vector2i(34, 11),
		Vector2i(26, 8),
		Vector2i(31, 8),
		Vector2i(26, 14),
		Vector2i(31, 14),
	]
	for i in spots.size():
		var is_airside := spots[i].y < 9
		var p := _spawn_positioned(active_occ, spots[i], is_airside)
		p.carry_on = 1
		if i % 3 == 0:
			p.hunger = 76
		elif i % 3 == 1:
			p.boredom = 84
		else:
			p.toilet_need = 82
	var cafe_st: Array[int] = [
		Passenger.Stage.CAFE_QUEUE,
		Passenger.Stage.CAFE_ORDER,
		Passenger.Stage.CAFE_SEATED,
	]
	var shop_st: Array[int] = [Passenger.Stage.SHOP_WALK, Passenger.Stage.SHOP_BROWSE]
	var wc_st: Array[int] = [
		Passenger.Stage.TOILET_WALK,
		Passenger.Stage.TOILET_ENTER,
		Passenger.Stage.TOILET_SITTING_DOWN,
		Passenger.Stage.TOILET_USE,
		Passenger.Stage.TOILET_EXIT,
	]
	var ready := func() -> bool:
		return (
			_pax_in(cafe_st).size() >= 2
			and not _pax_in(shop_st).is_empty()
			and not _pax_in(wc_st).is_empty()
		)
	StarterFlight.advance_until(_clock, ready, 900)
	await _skip_done()
	var f_start := _cell(Vector2(26.5, 8.8))
	var f_end := _cell(Vector2(32.5, 8.8))
	var points := {
		"cafe": _cell(Vector2(24.0, 5.5)),
		"kiosk": _cell(Vector2(31.0, 5.5)),
		"toilet": _cell(Vector2(37.0, 4.5)),
	}
	var open_busy := _pax_in(cafe_st + shop_st)
	var busy := open_busy if not open_busy.is_empty() else _pax_in(wc_st)
	var subject: Node3D = _views.node_for(busy[0]) if not busy.is_empty() else null
	var view := await _stage("s07_shops", LOW, f_start, -0.18, 20.5, points, subject, TRY_YAWS)
	var yaw: float = view["yaw"]
	var dist: float = view["dist"]
	var drive := func(i: int, total: int) -> void:
		var t := smoothstep(0.0, 1.0, float(i) / float(maxi(1, total - 1)))
		_aim(LOW, f_start.lerp(f_end, t), yaw + 0.24 * t, lerpf(dist, dist * 0.96, t))
		# Trigger staggered extra shoppers at frame 35 and 85 so fresh +$ pops rise on camera!
		if not _smoke and (i == _handle + 24 or i == _handle + 78):
			var sp := _spawn_positioned(active_occ, Vector2i(23, 5), true)
			sp.hunger = 85
			var sp2 := _spawn_positioned(active_occ, Vector2i(30, 5), true)
			sp2.boredom = 88
	await _record("s07_shops", 12, drive, true)
	_end_check(
		"s07_shops", {"kiosk": _cell(Vector2(31.0, 5.5)), "toilet": _cell(Vector2(37.0, 4.5))}
	)


## Shot 08 (10 beats = 6.00 s): Today's airline contract offers — open & sign live.
func _shot_08_offers() -> void:
	_beat("s08_offers")
	_dismiss_popups()
	var desk := _main.get_node("OfferDesk") as OfferDesk
	desk.board.from_snapshot({"save_version": OfferBoard.SAVE_VERSION, "offers": [], "loyalty": {}})
	desk._draw(GameCalendar.day_of(_clock.tick, _clock.epoch))
	var offers := _main.get_node("OfferPanel") as OfferPanel
	var focus := _cell(Vector2(24.0, 10.0))
	var points := {
		"hall_w": _cell(Vector2(18.5, 12.5)),
		"curb": _cell(Vector2(20.0, 18.0)),
	}
	var view := await _stage("s08_offers", LOW, focus, 0.20, 23.5, points, null, TRY_YAWS)
	var yaw: float = view["yaw"]
	var dist: float = view["dist"]
	offers.open()
	_clock.set_paused(false)
	await _frames(6)
	var sheet := offers.sheet()
	if sheet == null or not sheet.is_visible_in_tree() or offers.card_ids().is_empty():
		_invalid("s08_offers: OfferSheet did not open with cards")
	var pick_id := ""
	for cid in offers.card_ids():
		var rec := desk.board.offer_of(cid)
		if _flights.accept_problem(OfferBoard.terms_of(rec)) == "":
			pick_id = cid
			break
	if pick_id == "":
		_invalid("s08_offers: no fitting offer card to accept")
	var signed := [false, false]
	var sign_frame := _handle + (2 if _smoke else 96)
	var drive := func(i: int, total: int) -> void:
		if not signed[0] and i == _handle:
			signed[0] = true
			_log_sfx("ui_click")
		if not signed[1] and i == sign_frame and pick_id != "":
			signed[1] = true
			var btn := offers.accept_button(pick_id)
			if btn != null:
				btn.pressed.emit()
				_log_sfx("ui_click")
				_log_sfx("cash_chime")
		var t := float(i) / float(maxi(1, total - 1))
		_aim(LOW, focus, yaw - 0.08 * t, lerpf(dist, dist * 0.96, t))
	await _record("s08_offers", 10, drive, true)
	offers.close()
	_clock.set_paused(false)
	await _frames(4)
	_end_check("s08_offers", points)


## Shot 09 (12 beats = 7.20 s): Two-gate apron boarding & yellow pushback tug.
func _shot_09_boarding() -> void:
	_beat("s09_boarding")
	_dismiss_popups()
	if _flight_b != "":
		StarterFlight.advance_until(
			_clock, func() -> bool: return _flights.flight_ids().has(_flight_b), 3200
		)
	var push_a := _flights.state_start(_flight_a, FlightSim.State.PUSHBACK)
	var board_b := (
		_flights.state_start(_flight_b, FlightSim.State.BOARDING) if _flight_b != "" else push_a
	)
	var prep_tick := maxi(push_a - 40, board_b + 2)
	if _clock.tick < prep_tick:
		StarterFlight.advance_until(
			_clock, func() -> bool: return _clock.tick >= prep_tick, prep_tick - _clock.tick + 10
		)
	var board_occ := (
		_flight_b if _flight_b != "" and _flights.flight_ids().has(_flight_b) else _flight_a
	)
	for _i in 8:
		var bp := _spawn_positioned(board_occ, Vector2i(51, 4), true)
		bp.carry_on = 1
		StarterFlight.advance_until(_clock, func() -> bool: return false, 5)
	if _clock.tick < push_a + 4:
		StarterFlight.advance_until(
			_clock, func() -> bool: return _clock.tick >= push_a + 4, push_a + 10 - _clock.tick
		)
	var fleet := (_main.get_node("PlaneFleet") as PlaneFleet).views
	var ready := func() -> bool:
		fleet = (_main.get_node("PlaneFleet") as PlaneFleet).views
		(_main.get_node("PlaneFleet") as PlaneFleet).update_views()
		var walkers := _pax_in([Passenger.Stage.APRON]).size()
		var tug_on := false
		for v in fleet:
			tug_on = tug_on or (v.get_node("Props") as PlaneProps).tug.is_visible_in_tree()
		return walkers >= 2 and tug_on
	StarterFlight.advance_until(_clock, ready, 60)
	await _skip_done()
	_dismiss_popups()
	var view_a: PlaneView = null
	var view_b: PlaneView = null
	for v in fleet:
		view_a = v if v.gate == "A" and v.visible else view_a
		view_b = v if v.gate == "B" and v.visible else view_b
	var tug_pt := _cell(Vector2(18.0, 0.0)) + Vector3(0.0, 1.2, -10.0)
	if view_a != null:
		tug_pt = (
			(view_a.get_node("Props") as PlaneProps).tug.global_position + Vector3(0.0, 1.2, 0.0)
		)
	var b_pt := _cell(Vector2(50.0, 0.0)) + Vector3(0.0, 2.2, -10.0)
	if view_b != null:
		b_pt = view_b.global_position + Vector3(2.5, 2.2, 0.0)
	var focus := Vector3((tug_pt.x + b_pt.x) * 0.5 + 3.0, 0.0, -104.0)
	var points := {"gate_a_tug": tug_pt, "gate_b_plane": b_pt}
	var pick_view: PlaneView = view_b if view_b != null else view_a
	var subject: Node3D = (pick_view.get("_model") as Node3D) if pick_view != null else null
	var top_step := int(TycoonCamera.AngleStep.TOP_DOWN)
	var view := await _stage("s09_boarding", top_step, focus, 0.04, 34.0, points, subject, TRY_YAWS)
	var yaw: float = view["yaw"]
	var dist: float = view["dist"]
	var logged := [false]
	var drive := func(i: int, total: int) -> void:
		if not logged[0] and i == _handle:
			logged[0] = true
			_log_sfx("pa_chime")
			_log_sfx("prop_idle", {"dur": 180})
		var t := float(i) / float(maxi(1, total - 1))
		_aim(top_step, focus, yaw + 0.08 * t, lerpf(dist, dist * 0.94, t))
	await _record("s09_boarding", 12, drive, true)
	_end_check("s09_boarding", {"gate_b_plane": b_pt})


## Shot 10 (8 beats = 4.80 s): Peak-hour sweeping pull-back over the 2-gate airport.
func _shot_10_pullback() -> void:
	_beat("s10_pullback")
	_dismiss_popups()
	var centre := _cell(Vector2(32.0, 9.0))
	var points := _two_gate_points()
	await _frames(_settle)
	var far := maxf(_fit(LOW, centre, 0.26, 88.0, points.values()), 88.0) + 4.0
	var near_pts := {
		"apron_w": _cell(Vector2(18.0, 0.5)),
		"apron_e": _cell(Vector2(44.0, 0.5)),
		"curb": _cell(Vector2(30.0, 18.5)),
	}
	var view := await _stage("s10_pullback", LOW, centre, 0.52, 42.0, near_pts, null, FIXED_YAW)
	var near: float = view["dist"]
	var drive := func(i: int, total: int) -> void:
		var t := smoothstep(0.0, 1.0, float(i) / float(maxi(1, total - 1)))
		_aim(LOW, centre, lerpf(0.52, 0.26, t), lerpf(near, far, t))
	await _record("s10_pullback", 8, drive, true)
	_end_check("s10_pullback", points)


## Shot 11 (10 beats = 6.00 s + handle + hold): Runway takeoff + Option A Logo & End Card.
func _shot_11_takeoff() -> void:
	_beat("s11_takeoff")
	var dep_flight := _flight_a
	var rolling := func() -> bool:
		for fid in _flights.flight_ids():
			if _flights.state_of(fid) == FlightSim.State.TAKEOFF:
				var since := _clock.tick - _flights.state_start(fid, FlightSim.State.TAKEOFF)
				if since >= 45:
					dep_flight = fid
					return true
		return false
	if not StarterFlight.advance_until(_clock, rolling, 5000):
		_invalid("s11_takeoff: no flight entered takeoff roll by tick %d" % _clock.tick)
		return
	await _skip_done()
	var plane := _plane_model_for(dep_flight)
	if plane == null:
		_invalid("s11_takeoff: no plane model for %s" % dep_flight)
		return
	var entry := (_main.get_node("Airside/RunwayEntry") as Node3D).global_position
	var liftoff := (_main.get_node("Airside/Liftoff") as Node3D).global_position
	var along := (liftoff - entry).normalized()
	var yaw := atan2(-along.z, along.x)
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	if forward.dot(_cell(Vector2(32.0, 9.0)) - plane.global_position) < 0.0:
		yaw += PI
		forward = -forward
	yaw += 0.28
	var lift := 0.7 / tan(deg_to_rad(TycoonCamera.STEP_PITCH_DEGREES[LOW]))
	var spot := func() -> Vector3:
		var at := plane.global_position
		return Vector3(at.x, 0.0, at.z) + forward * at.y * lift
	var points := {"plane": plane.global_position}
	var view := await _stage("s11_takeoff", LOW, spot.call(), yaw, 52.0, points, plane, TRY_YAWS)
	yaw = view["yaw"]
	var dist: float = view["dist"]
	var hidden := _hide_hud()
	var logged := [false]
	var drive := func(i: int, total: int) -> void:
		if not logged[0] and i == _handle:
			logged[0] = true
			_log_sfx("prop_rev", {"dur": 165})
			_log_sfx("takeoff_whoosh")
		var t := float(i) / float(maxi(1, total - 1))
		var to: Vector3 = spot.call()
		_aim(LOW, _rig.position.lerp(to, 0.32), yaw - 0.14 * t, lerpf(dist, dist * 0.86, t))
	await _record("s11_takeoff", 10, drive, true)
	for node in hidden:
		node.set("visible", true)
	_end_check("s11_takeoff", {"plane": plane.global_position})


func _shell_batches() -> Array:
	var east := _at + Vector2i(32, 0)
	var out: Array = []
	for x in range(10, 54):
		var y0 := 3 if (x >= 22 and x <= 41) else 2
		var y1 := 17 if (x >= 22 and x <= 41) else 18
		var col: Array[BuildEdit] = []
		for y in range(y0, y1):
			col.append(BuildEdit.paint_floor(Vector2i(x, y) + _at, BuildGrid.FLOOR_TILE, 1))
		out.append(col)
	var shell_a := ReferenceTerminal.shell_edits(_at)
	var shell_b := ReferenceTerminal.shell_edits(east)
	var span := ReferenceTerminal.FLOOR_MAX - ReferenceTerminal.FLOOR_MIN + Vector2i.ONE
	var skip := span.x * span.y
	for edit in shell_a.slice(skip) + shell_b.slice(skip):
		out.append(_one(edit))
	var join_walls: Array[BuildEdit] = []
	for y in [4, 5, 6, 7, 11, 12, 13, 14, 15]:
		join_walls.append(BuildEdit.remove_wall(Vector2i(21, y) + _at, BuildGrid.Side.EAST))
		join_walls.append(BuildEdit.remove_wall(Vector2i(42, y) + _at, BuildGrid.Side.WEST))
	for i in range(0, join_walls.size(), 4):
		out.append(join_walls.slice(i, i + 4))
	out.append(func() -> void: EnclosureKit.close_floor(_grid))
	return out


func _furnish_batches() -> Array:
	var east := _at + Vector2i(32, 0)
	var out: Array = []
	var div: Array[BuildEdit] = []
	for x in range(22, 42):
		div.append(BuildEdit.place_wall(Vector2i(x, 9) + _at, BuildGrid.Side.NORTH))
	out.append(div)
	for edit in ReferenceTerminal.interior_edits(_at) + ReferenceTerminal.interior_edits(east):
		out.append(_one(edit))
	out.append(_one(ReferenceTerminal.gate_desk_edit(_at)))
	out.append(_one(ReferenceTerminal.gate_desk_edit(east)))
	out.append(func() -> void: _install_four_part_lane())
	var bag_rc := Rect2i(Vector2i(15, 12) + _at, Vector2i(2, 3))
	out.append(func() -> void: RoomTool.mark(_grid, bag_rc, &"bag_room", null))
	out.append(func() -> void: _lay_bag_belts())
	for spec in ROOMS.split(","):
		var r := spec.split(":")
		var rc := Rect2i(Vector2i(int(r[0]), int(r[1])) + _at, Vector2i(int(r[2]), int(r[3])))
		out.append(_one(BuildEdit.place_room(rc, StringName(r[4]))))
	for spec in PIECES.split(","):
		var p := spec.split(":")
		var pos := Vector2i(int(p[1]), int(p[2])) + _at
		out.append(_one(BuildEdit.place_object(StringName(p[0]), pos, 0)))
	return out


func _install_four_part_lane() -> void:
	var edits: Array[BuildEdit] = []
	for sx in ReferenceTerminal.SCANNER_XS:
		var old := _grid.object_at(Vector2i(sx, ReferenceTerminal.DIVIDER_Y - 1) + _at)
		if old != 0:
			edits.append(BuildEdit.remove_object(old))
	edits.append(BuildEdit.place_wall(Vector2i(17, 9) + _at, BuildGrid.Side.NORTH))
	var arch_at := Vector2i(20, 9) + _at
	var lane := SecurityLanes.geometry(arch_at, 0, SecurityLanes.LEFT)
	for k in range(-1, 3):
		var cell: Vector2i = arch_at + (lane["side"] as Vector2i) * k
		if _grid.has_wall(cell, BuildGrid.Side.NORTH):
			edits.append(BuildEdit.remove_wall(cell, BuildGrid.Side.NORTH))
	edits.append(BuildEdit.place_object(SecurityLanes.ARCH, arch_at, 0))
	for part in [SecurityLanes.TRAY_TABLE, SecurityLanes.XRAY_BELT, SecurityLanes.PICKUP_TABLE]:
		edits.append(BuildEdit.place_object(part, lane[part], 0))
	for res in _grid.apply_batch(edits):
		if not res.ok:
			_invalid("4-part security lane edit refused: %s" % res.reason_text())


func _lay_bag_belts() -> void:
	_mode.set_tool(BuildMode.Tool.BELT)
	for s in [[12, 10, 12, 9], [12, 9, 16, 9], [15, 10, 15, 9], [16, 9, 16, 12]]:
		if not _mode.lay_belt(Vector2i(s[0], s[1]) + _at, Vector2i(s[2], s[3]) + _at).ok:
			_invalid("lay_belt failed for %s" % [s])
	_mode.set_tool(BuildMode.Tool.NONE)


func _spawn_positioned(occ: String, local_cell: Vector2i, clr: bool) -> Passenger:
	var p := _sim.get_passenger(_sim.spawn_now(occ))
	p.cleared = clr
	var target := local_cell + _at
	if _grid.object_at(target) != 0:
		for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)]:
			if _grid.object_at(target + d) == 0 and _grid.has_floor(target + d):
				target += d
				break
	p.at = target
	p.stage = Passenger.Stage.TO_GATE if clr else Passenger.Stage.TO_SECURITY
	p.stage_tick = _clock.tick
	p.clear_path()
	return p


func _dismiss_popups() -> void:
	if _hud.unlock_guide() != null and _hud.unlock_guide().is_open():
		_hud.unlock_guide().dialog().dismiss()
	if _hud.is_result_open():
		_hud.dismiss_result()


func _stage(
	shot: String,
	step: int,
	focus: Vector3,
	yaw: float,
	dist: float,
	points: Dictionary,
	subject: Node3D,
	turns: Array[float]
) -> Dictionary:
	var fitted := dist
	for turn in turns:
		fitted = _fit(step, focus, yaw + turn, dist, points.values())
		if fitted < 0.0:
			continue
		await _frames(_settle)
		_aim(step, focus, yaw + turn, fitted)
		if await _prove(shot, points, subject):
			return {"yaw": yaw + turn, "dist": fitted}
	_invalid("%s: no camera yaw tried shows subject in frame and unoccluded" % shot)
	return {"yaw": yaw, "dist": maxf(fitted, dist)}


func _prove(shot: String, points: Dictionary, subject: Node3D) -> bool:
	var ok := true
	var size := root.get_visible_rect().size
	var dbg := _hud.find_child("DebugCorner", true, false) as Control
	if dbg != null and dbg.is_visible_in_tree():
		_invalid("%s: DebugCorner is visible" % shot)
		ok = false
	if _built:
		var causes := HintRules.causes(HintRules.read_world(_sim, []))
		if causes.has(HintRules.TOILET):
			_invalid("%s: toilet gap warning active" % shot)
			ok = false
		for pid in _sim.passenger_ids():
			var p := _sim.get_passenger(pid)
			if p != null and not p.is_done() and p.stuck == Passenger.Stuck.NO_ROUTE:
				_invalid("%s: passenger %d stuck NO_ROUTE at %s" % [shot, pid, p.at])
				ok = false
				break
	for key: String in points:
		var pt: Vector3 = points[key]
		var inside := _in_frame(pt)
		ok = ok and inside
		print(
			(
				"PROBE %s in_frame %s world=%s screen=%s of %s inside=%s"
				% [shot, key, pt.round(), _px(pt), size, inside]
			)
		)
	var subjects := {}
	if subject != null:
		subjects[subject] = "subject"
	var holder := PlateSight.colliders(root, _owners(), subjects)
	await physics_frame
	await physics_frame
	var space := _cam.get_world_3d().direct_space_state
	var eye := _cam.global_position
	if _built and not _control_done:
		_control_done = true
		_control(space)
	if subject != null:
		var bounds: Dictionary = holder.get_meta("bounds")
		var box: AABB = bounds.get("subject", AABB())
		var lines := PlateSight.sight_lines(space, eye, _box_targets(box), "subject")
		var on: Array[Vector3] = lines["on_subject"]
		print(
			(
				"PROBE %s sight subject=%s on=%d blockers=%s"
				% [shot, subject.name, on.size(), lines["blockers"]]
			)
		)
		ok = ok and not on.is_empty()
	else:
		var clear := 0
		for key: String in points:
			var targets: Array[Vector3] = [points[key] + Vector3.UP * 0.15]
			var blockers: Array[String] = (
				PlateSight.sight_lines(space, eye, targets, NO_TAG)["blockers"]
			)
			clear += int(blockers.is_empty())
		print("PROBE %s sight clear=%d of %d" % [shot, clear, points.size()])
		ok = ok and clear >= 1
	holder.queue_free()
	await _frames(2)
	return ok


func _control(space: PhysicsDirectSpaceState3D) -> void:
	var rays: Array = [
		[Vector2(7.0, 5.5), Vector2(12.0, 5.5)],
		[Vector2(7.0, 13.5), Vector2(12.0, 13.5)],
		[Vector2(13.5, 0.0), Vector2(13.5, 5.0)],
		[Vector2(12.5, 19.5), Vector2(12.5, 14.5)],
	]
	var blocked := 0
	for ray in rays:
		var from := _cell(ray[0]) + Vector3.UP * 1.5
		var targets: Array[Vector3] = [_cell(ray[1]) + Vector3.UP * 1.5]
		var blockers: Array[String] = (
			PlateSight.sight_lines(space, from, targets, NO_TAG)["blockers"]
		)
		blocked += int(not blockers.is_empty())
	print("PROBE control walls blocked=%d of %d" % [blocked, rays.size()])
	if blocked == 0:
		_invalid("control: no ray through a terminal wall was blocked")


func _record(shot: String, beats: int, drive: Callable, live: bool) -> void:
	var body := 6 if _smoke else beats * BEAT
	var total := body + 2 * _handle
	var first := _frame_seq + 1
	_cur_events = []
	_last_place_frame = -99
	_last_cash_frame = -99
	_recording = true
	var hud_union: Dictionary = {}
	for i in total:
		_beat("%s:%d/%d" % [shot, i + 1, total])
		_cur_frame = i
		drive.call(i, total)
		if live:
			_clock.advance(1.0 / float(FPS))
		if _hud != null and is_instance_valid(_hud):
			_hud.refresh()
		await process_frame
		await RenderingServer.frame_post_draw
		_sample_hud_rects(hud_union)
		_frame_seq += 1
		var img := root.get_texture().get_image()
		var out_path := _frames_dir.path_join("shot%08d.png" % _frame_seq)
		if img == null or img.get_size() != SCREEN or img.save_png(out_path) != OK:
			_invalid("%s: failed saving %s" % [shot, out_path])
			break
	_recording = false
	(
		_shots
		. append(
			{
				"name": shot,
				"first": first,
				"frames": total,
				"handle": _handle,
				"body": body,
				"events": _cur_events.duplicate(true),
				"hud_rects": hud_union,
			}
		)
	)
	print(
		(
			"PROBE shot %s first=%d frames=%d handle=%d body=%d events=%d"
			% [shot, first, total, _handle, body, _cur_events.size()]
		)
	)


func _sample_hud_rects(into: Dictionary) -> void:
	var vis := root.get_visible_rect().size
	var sx := float(SCREEN.x) / vis.x
	var sy := float(SCREEN.y) / vis.y
	var inspect := _hud.find_child("PassengerInspect", true, false) as Control
	var dep := _main.find_child("DeparturesPanel", true, false) as Control
	var offers := (_main.get_node("OfferPanel") as OfferPanel).sheet()
	var staff_card := (_main.get_node("StaffPanel") as StaffPanel).card()
	var pairs := {
		"bar": _menu.bar(),
		"tray": _menu.tray(),
		"staff_panel": staff_card,
		"passenger_inspect": inspect,
		"offers_sheet": offers,
		"departures_panel": dep,
	}
	for k: String in pairs:
		var c := pairs[k] as Control
		if c == null or not c.is_visible_in_tree():
			continue
		var r := c.get_global_rect()
		if not r.has_area():
			continue
		var px_rect := [
			int(floorf(r.position.x * sx)),
			int(floorf(r.position.y * sy)),
			int(ceilf(r.end.x * sx)),
			int(ceilf(r.end.y * sy)),
		]
		if not into.has(k):
			into[k] = px_rect
		else:
			var prev: Array = into[k]
			into[k] = [
				mini(prev[0], px_rect[0]),
				mini(prev[1], px_rect[1]),
				maxi(prev[2], px_rect[2]),
				maxi(prev[3], px_rect[3]),
			]


func _write_manifest() -> void:
	var data := {
		"seed": _seed,
		"fps": FPS,
		"beat": BEAT,
		"final_frame": _frame_seq,
		"shots": _shots,
	}
	var path := _out_dir.path_join("shots_smoke.json" if _smoke else "shots.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_invalid("manifest %s could not be written" % path)
		return
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	print("PROBE manifest %s" % path)


func _hide_hud() -> Array[Node]:
	var hidden: Array[Node] = []
	for node in _main.find_children("*", "CanvasLayer", true, false):
		var layer := node as CanvasLayer
		if layer.visible:
			layer.visible = false
			hidden.append(layer)
	for node in _main.find_children("*", "Control", true, false):
		var control := node as Control
		var parent := control.get_parent()
		if control.visible and not (parent is Control or parent is CanvasLayer):
			control.visible = false
			hidden.append(control)
	return hidden


func _one(edit: BuildEdit) -> Array[BuildEdit]:
	var out: Array[BuildEdit] = [edit]
	return out


func _apply_next(batches: Array) -> void:
	if batches.is_empty():
		return
	var batch: Variant = batches.pop_front()
	if batch is Callable:
		(batch as Callable).call()
	else:
		var edits: Array[BuildEdit] = []
		edits.assign(batch)
		for result in _grid.apply_batch(edits):
			if not result.ok:
				_invalid("build edit refused: %s" % result.reason_text())
	(_mode.get_node("BuildView") as BuildView).refresh(_grid)


func _flush(batches: Array) -> void:
	while not batches.is_empty():
		_apply_next(batches)


func _aim(step: int, focus: Vector3, yaw: float, dist: float) -> void:
	_rig.angle_step = step as TycoonCamera.AngleStep
	_rig.pan(Vector2.ZERO)
	_rig.position = Vector3(focus.x, _rig.position.y, focus.z)
	_rig.yaw = wrapf(yaw, -PI, PI)
	_rig.distance = dist
	_rig.call("_apply")
	var roof := _main.get_node("RoofView") as RoofView
	roof.cutaway.snap(_rig.distance)
	roof.draw_level(roof.cutaway.roof_level)


func _fit(step: int, focus: Vector3, yaw: float, dist: float, points: Array) -> float:
	var at := dist
	while at <= _rig.max_distance:
		_aim(step, focus, yaw, at)
		if points.all(_in_frame):
			return at
		at += 2.0
	return -1.0


func _in_frame(point: Vector3) -> bool:
	if _cam.is_position_behind(point):
		return false
	var at := _cam.unproject_position(point)
	var size := root.get_visible_rect().size
	return (
		at.x > MARGIN_PX
		and at.y > MARGIN_PX
		and at.x < size.x - MARGIN_PX
		and at.y < size.y - MARGIN_PX
	)


func _end_check(shot: String, points: Dictionary) -> void:
	var first := true
	for key: String in points:
		var pt: Vector3 = points[key]
		var inside := _in_frame(pt)
		print("PROBE %s end %s screen=%s inside=%s" % [shot, key, _px(pt), inside])
		if first and not inside:
			_invalid("%s: %s out of frame at end" % [shot, key])
		first = false


func _box_targets(box: AABB) -> Array[Vector3]:
	var centre := box.get_center()
	var targets: Array[Vector3] = []
	for k: float in [0.3, 0.5, 0.75]:
		targets.append(Vector3(centre.x, box.position.y + box.size.y * k, centre.z))
	var side := (
		Vector3(box.size.x, 0.0, 0.0) if box.size.x > box.size.z else Vector3(0.0, 0.0, box.size.z)
	)
	targets.append(centre + side * 0.25)
	targets.append(centre - side * 0.25)
	return targets


func _two_gate_points() -> Dictionary:
	return {
		"centre": _cell(Vector2(32.0, 9.5)),
		"nw": _cell(Vector2(10.0, 3.0)),
		"ne": _cell(Vector2(54.0, 3.0)),
		"sw": _cell(Vector2(10.0, 17.0)),
		"se": _cell(Vector2(54.0, 17.0)),
	}


func _cell(at: Vector2) -> Vector3:
	var corner := _grid.cell_to_world(Vector2i.ZERO) - Vector3(0.5, 0.0, 0.5)
	return corner + Vector3(at.x + float(_at.x), 0.0, at.y + float(_at.y))


func _px(point: Vector3) -> Vector2:
	return _cam.unproject_position(point).round()


func _plane_model_for(fid: String) -> Node3D:
	var views: Array = [_main.get_node("PlaneView"), _main.get_node("PlaneView2")]
	views.append_array((_main.get_node("PlaneFleet") as PlaneFleet).views)
	for view: PlaneView in views:
		if view.flight_id == fid:
			return view.get("_model") as Node3D
	return null


func _pax_in(stages: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for pid in _sim.passenger_ids():
		var p := _sim.get_passenger(pid)
		if p != null and stages.has(int(p.stage)) and _views.node_for(pid) != null:
			out.append(pid)
	return out


func _staff_in_frame() -> Array[int]:
	var out: Array[int] = []
	for id in _staff.member_ids():
		if _in_frame(_staff_views.tick_position(id, true)):
			out.append(id)
	return out


func _walking_staff() -> Array[int]:
	var out: Array[int] = []
	for id in _staff_in_frame():
		if _staff.get_member(id).state != StaffMember.State.ON_DUTY:
			out.append(id)
	return out


func _car_in(lane: LandsideVehicle.Lane) -> int:
	for id in _landside.vehicle_ids():
		var v := _landside.get_vehicle(id)
		if v.lane == lane and v.stage == LandsideVehicle.Stage.DRIVE and _cars.has_vehicle(id):
			return id
	return 0


func _owners() -> Array[Node]:
	var owners: Array[Node] = []
	for path in OCCLUDER_OWNERS:
		var node := _main.get_node_or_null(path)
		if node != null:
			owners.append(node)
	return owners


func _skip_done() -> void:
	(_main.get_node("PlaneFleet") as PlaneFleet).update_views()
	await _frames(4)


func _frames(count: int) -> void:
	for _i in count:
		_beat(_stage_name)
		await process_frame


func _invalid(msg: String) -> void:
	print("PROBE_INVALID %s" % msg)
	_failed = true


func _beat(stage: String) -> void:
	_mutex.lock()
	_stage_name = stage
	_beat_ms = Time.get_ticks_msec()
	_mutex.unlock()


func _watch() -> void:
	var start := Time.get_ticks_msec()
	while true:
		OS.delay_msec(500)
		_mutex.lock()
		var done := _done
		var idle := Time.get_ticks_msec() - _beat_ms
		var stage := _stage_name
		_mutex.unlock()
		if done:
			return
		if idle > 120000 or Time.get_ticks_msec() - start > 900000:
			print("PROBE_INVALID hang in %s (idle %d ms)" % [stage, idle])
			OS.crash("gameplay_trailer_probe hung")
