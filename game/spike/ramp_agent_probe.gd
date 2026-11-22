extends SceneTree

const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/ramp_agent"
const MAIN_SCENE := "res://main/main.tscn"
const ROOM := Rect2i(13, 14, 4, 4)
const DESK2_ENTRY := Vector2i(15, 10)
const CORNER_CELL := Vector2i(16, 10)
const END_CELL := Vector2i(16, 14)
const CART_CELL := Vector2i(14, 15)
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 60000
const TOTAL_LIMIT_MS := 240000
const WAIT_LIMIT_MS := 150000
const STALL_LIMIT_MS := 10000
const TICK_LIMIT := 40000
const OCCLUDER_OWNERS: Array[String] = [
	"Airside/Terminal",
	"BuildMode",
	"PlaneView",
	"PlaneView2",
	"PlaneFleet",
	"PassengerViews",
	"BaggageViews",
	"StaffCharacters"
]

var _out_dir := ""
var _failed := false
var _stage := "init"
var _heartbeat_ms := 0
var _guard_mutex := Mutex.new()
var _guard_stop := false
var _guard: Thread
var _main: Node3D
var _cam: Camera3D
var _rig: TycoonCamera
var _clock: SimClock
var _hud: PassengerHud
var _build: BuildMode
var _menu: BuildMenu
var _unlocks: BuildUnlocks
var _staff: StaffSim
var _chars: StaffCharacters
var _panel: StaffPanel
var _flights: FlightSim
var _fleet: PlaneFleet
var _baggage: BaggageSim
var _baggage_views: BaggageViews
var _grid: BuildGrid
var _offset := Vector2i.ZERO


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_beat("init")
	_guard = Thread.new()
	_guard.start(_watch)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	_beat(_stage)
	return false


func _beat(stage: String) -> void:
	_guard_mutex.lock()
	_stage = stage
	_heartbeat_ms = Time.get_ticks_msec()
	_guard_mutex.unlock()


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_guard_mutex.lock()
		var stop := _guard_stop
		var idle_ms := Time.get_ticks_msec() - _heartbeat_ms
		var stage := _stage
		_guard_mutex.unlock()
		if stop:
			return
		var total_ms := Time.get_ticks_msec()
		if idle_ms > HANG_LIMIT_MS or total_ms > TOTAL_LIMIT_MS:
			print(
				(
					"PROBE_INVALID hang stage=%s no heartbeat for %d ms, %d ms in all"
					% [stage, idle_ms, total_ms]
				)
			)
			OS.crash("ramp agent probe hung")


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	await _boot()
	if not _failed:
		await _capture_staff_panel_plate()
	if not _failed:
		await _capture_shuttle_plate()
	if not _failed:
		await _capture_pushback_plate()
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _boot() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	root.content_scale_factor = 1.5
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	var seed := randi()
	_clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	root.add_child(_main)
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	_hud = _main.get_node("PassengerHud")
	_build = _main.get_node("BuildMode")
	_menu = _main.get_node("BuildMenu")
	_unlocks = _main.get_node("BuildUnlocks")
	_staff = _main.get_node("Staff")
	_chars = _main.get_node("StaffCharacters")
	_panel = _main.get_node("StaffPanel")
	_flights = _main.get_node("FlightSim")
	_fleet = _main.get_node("PlaneFleet")
	_baggage = _main.get_node("BaggageSim")
	_baggage_views = _main.get_node("BaggageViews")
	_grid = _build.grid
	await _frames(5)
	_hud.press_starter_terminal()
	_offset = ReferenceTerminal.offset_on(_grid)
	var room_rect := Rect2i(ROOM.position + _offset, ROOM.size)
	var room := RoomTool.mark(_grid, room_rect, &"bag_room", _build.wallet())
	if not room.ok:
		_invalid("bag_room refused: %s" % room.reason_text())
		return
	var view := _build.get_node("BuildView") as BuildView
	view.refresh(_grid)
	_build.set_tool(BuildMode.Tool.BELT)
	var belt_h := _build.lay_belt(DESK2_ENTRY + _offset, CORNER_CELL + _offset)
	var belt_v := _build.lay_belt(CORNER_CELL + _offset, END_CELL + _offset)
	_build.set_tool(BuildMode.Tool.NONE)
	if not belt_h.ok or not belt_v.ok:
		_invalid("belt layout failed")
		return
	var cart := _grid.apply(BuildEdit.place_object(&"baggage_cart", CART_CELL + _offset, 0))
	if not cart.ok:
		_invalid("baggage_cart refused: %s" % cart.reason_text())
		return
	view.refresh(_grid)
	for object_id in _grid.object_ids():
		match StringName(_grid.get_object(object_id)["def"]):
			&"checkin_desk":
				_staff.hire(StaffMember.Role.CHECKIN)
			&"security_scanner":
				_staff.hire(StaffMember.Role.SECURITY)
			&"gate_desk":
				_staff.hire(StaffMember.Role.GATE)
	_staff.hire(StaffMember.Role.RAMP)
	_staff.hire(StaffMember.Role.RAMP)
	_unlocks._tier = 2
	_unlocks.tier_changed.emit(2)
	_flights.runway.size = PlaneClasses.MEDIUM
	_hud.press_speed(3)
	if not await _until("wait_open", func() -> bool: return _flights.opened_tick >= 0):
		return
	print(
		"PROBE open tick=",
		_clock.tick,
		" tier=",
		_unlocks.tier(),
		" layout=",
		root.get_visible_rect().size
	)


func _capture_staff_panel_plate() -> void:
	_hud.press_speed(0)
	_menu.staff_button.pressed.emit()
	await _frames(5)
	var card := _panel.card()
	var cols := (card.get_child(0) as Control).get_children()
	var visible_cols := 0
	var rects: Array[Rect2] = []
	for child in cols:
		var ctrl := child as Control
		if ctrl.visible:
			visible_cols += 1
			var r := ctrl.get_global_rect()
			for prev in rects:
				if prev.intersects(r):
					_invalid("staff panel columns overlap: %s vs %s" % [prev, r])
			rects.append(r)
	var card_rect := card.get_global_rect()
	var layer_w := root.get_visible_rect().size.x
	print(
		(
			"PANEL_TIER2 visible_cols=%d card_rect=%s layer_w=%.1f ramp_btn=%s"
			% [visible_cols, card_rect, layer_w, _panel.hire_button(StaffMember.Role.RAMP).text]
		)
	)
	if visible_cols != 6:
		_invalid("expected 6 visible columns at Tier 2, got %d" % visible_cols)
	if card_rect.position.x < 0.0 or card_rect.end.x > layer_w or card_rect.size.y > 220.0:
		_invalid("staff panel card %s invalid for 1280x720 (layer_w=%.1f)" % [card_rect, layer_w])
	var img: Image = await PlateSight.grab(self)
	_save(img, "03_ramp_staff_panel_tier2_1280")
	_menu.staff_button.pressed.emit()
	await _frames(2)
	_hud.press_speed(3)


func _capture_shuttle_plate() -> void:
	if not await _until("wait_shuttle", func() -> bool: return not _baggage.shuttles().is_empty()):
		return
	var shuttle := _baggage.shuttles()[0]
	var mid_tick := int((shuttle.start_tick + shuttle.arrive_tick) / 2.0)
	if not await _until("wait_shuttle_mid", func() -> bool: return _clock.tick >= mid_tick):
		return
	_hud.press_speed(0)
	await _frames(4)
	var cart_node := _baggage_views.shuttle_node_for(shuttle.id)
	var ramp_node := _chars.node_for(shuttle.driver_staff_id)
	if cart_node == null or ramp_node == null:
		_invalid("missing shuttle=%s or ramp=%s node" % [cart_node, ramp_node])
		return
	var focus := (cart_node.global_position + ramp_node.global_position) * 0.5
	var subjects := {ramp_node: "ramp_shuttle_worker", cart_node: "shuttle"}
	var best := {}
	for yaw in [PI * 0.25, -PI * 0.25, PI * 0.45, -PI * 0.65]:
		_aim(focus, 9.5, yaw)
		await _frames(8)
		best = await _check_subjects(subjects, 18.0)
		if best["shown"] == 2:
			break
	_save(best["image"], "01_ramp_baggage_shuttle")
	if best["shown"] < 2:
		_invalid("01_ramp_baggage_shuttle: only %d/2 subjects clear" % best["shown"])
	_hud.press_speed(3)


func _capture_pushback_plate() -> void:
	var min_now := GameCalendar.minute_of_day(_clock.tick, _clock.epoch)
	var dep_min := clampi(
		min_now + 130, FlightContract.FIRST_DEPARTURE_MINUTE, FlightContract.LAST_DEPARTURE_MINUTE
	)
	var accepted := false
	for offset_m in range(0, 300, 15):
		var candidate_min := mini(dep_min + offset_m, FlightContract.LAST_DEPARTURE_MINUTE)
		var terms := {
			"id": "T2P",
			"airline": "Nordic Jet",
			"destination": "Bergen",
			"departure_minute": candidate_min,
			"plane_size": PlaneClasses.MEDIUM,
			"booked_passengers": 30,
			"fee_per_passenger": 30,
		}
		if _flights.accept_problem(terms) == "":
			accepted = _flights.accept_contract(terms)
			print("PROBE tier2_contract dep_min=%d accepted=%s" % [candidate_min, accepted])
			break
	if not accepted:
		_invalid("could not accept a medium Tier-2 contract for pushback plate")
		return

	var found := {"fid": ""}
	var find_approach := func() -> bool:
		for fid: String in _flights.flight_ids():
			var model := PlaneClasses.flight_model(_flights, fid)
			if PlaneClasses.self_taxis(model):
				continue
			var st := _flights.state_of(fid)
			if st == FlightSim.State.DOORS_CLOSED or st == FlightSim.State.PUSHBACK:
				found["fid"] = fid
				return true
		return false
	if not await _until("wait_medium_doors", find_approach, 8):
		return
	var pushback_fid: String = found["fid"]
	_hud.press_speed(1)
	var in_pushback := func() -> bool:
		return _flights.state_of(pushback_fid) == FlightSim.State.PUSHBACK
	if not await _until("wait_medium_pushback", in_pushback):
		return
	var target_tick := mini(
		_clock.tick + 12, _flights.state_start(pushback_fid, FlightSim.State.TAXI_OUT) - 10
	)
	if not await _until("wait_pushback_couple", func() -> bool: return _clock.tick >= target_tick):
		return
	_hud.press_speed(0)
	await _frames(4)
	var tug_node: Node3D = null
	for v in _fleet.views:
		if v.flight_id == pushback_fid and v.tug_visible():
			tug_node = v._props.tug
			break
	var ramp_node: Node3D = null
	for sid in _staff.member_ids():
		var m := _staff.get_member(sid)
		if (
			m.role == StaffMember.Role.RAMP
			and m.ramp_job == StaffMember.RampJob.PUSHBACK
			and m.ramp_flight_id == pushback_fid
		):
			ramp_node = _chars.node_for(sid)
			break
	print(
		(
			"PUSHBACK_PROBE fid=%s state=%d tug=%s ramp=%s"
			% [pushback_fid, _flights.state_of(pushback_fid), tug_node != null, ramp_node != null]
		)
	)
	if tug_node == null or ramp_node == null:
		_invalid("missing tug=%s or ramp=%s node during pushback" % [tug_node, ramp_node])
		return
	for b in _main.find_children("*", "Button", true, false):
		var btn := b as Button
		if btn.visible and btn.text == tr("Dismiss"):
			btn.pressed.emit()
	await _frames(3)
	var focus := (tug_node.global_position + ramp_node.global_position) * 0.5
	var subjects := {ramp_node: "ramp_pushback_worker", tug_node: "pushback_tug"}
	var best := {}
	for yaw in [-PI * 0.30, -PI * 0.12, -PI * 0.02, PI * 0.10]:
		_aim(focus, 12.0, yaw)
		await _frames(8)
		best = await _check_subjects(subjects, 16.0, true)
		if best["shown"] == 2:
			break
	_save(best["image"], "02_ramp_pushback_tug")
	if best["shown"] < 2:
		_invalid("02_ramp_pushback_tug: only %d/2 subjects clear" % best["shown"])


func _until(stage: String, done: Callable, fast_steps := 0) -> bool:
	_beat(stage)
	var start_ms := Time.get_ticks_msec()
	var moved_ms := start_ms
	var last_tick := _clock.tick
	while not done.call():
		if fast_steps > 0:
			var was_paused := _clock.paused
			_clock.set_paused(false)
			for _i in fast_steps:
				if done.call():
					break
				_clock.advance(SimClock.STEP)
			_clock.set_paused(was_paused)
			if done.call():
				break
		var now_ms := Time.get_ticks_msec()
		if _clock.tick != last_tick:
			last_tick = _clock.tick
			moved_ms = now_ms
		if _clock.tick >= TICK_LIMIT:
			_invalid("%s: not met by tick %d" % [stage, TICK_LIMIT])
			return false
		if now_ms - start_ms > WAIT_LIMIT_MS:
			_invalid("%s: not met in %d ms (tick %d)" % [stage, WAIT_LIMIT_MS, _clock.tick])
			return false
		if now_ms - moved_ms > STALL_LIMIT_MS:
			_invalid("%s: clock stalled at tick %d" % [stage, _clock.tick])
			return false
		await process_frame
	return true


func _aim(at: Vector3, distance: float, yaw: float) -> void:
	_rig.stop_follow()
	_rig.position = Vector3(at.x, 0.0, at.z)
	_rig.yaw = yaw
	_rig.distance = distance


func _check_subjects(
	subjects: Dictionary, min_px: float, allow_nose_overhang := false
) -> Dictionary:
	paused = true
	var img: Image = await PlateSight.grab(self)
	var owners: Array[Node] = []
	for path in OCCLUDER_OWNERS:
		owners.append(_main.get_node(path))
	var holder := PlateSight.colliders(root, owners, subjects)
	var bounds: Dictionary = holder.get_meta("bounds")
	await physics_frame
	await physics_frame
	var twin: Dictionary = await PlateSight.hud_twin(self, _main)
	var bare: Image = twin["image"]
	var frame := Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)
	var shown := 0
	var results := {}
	for tag in subjects.values():
		var box: AABB = bounds.get(str(tag), AABB())
		var seen := PlateSight.person_shown(_cam, box, str(tag), frame, img, bare, min_px)
		var ok: bool = seen["ok"]
		if not ok and allow_nose_overhang and str(tag) == "pushback_tug":
			var external := false
			for blocker in seen["blockers"]:
				if not str(blocker).ends_with("Fuselage"):
					external = true
			ok = (
				not external
				and int(seen.get("on", 0)) >= 6
				and seen.get("in_frame", false)
				and int(seen.get("hud_px", 0)) == 0
				and float(seen.get("height_px", 0.0)) >= min_px
			)
		print(
			(
				"VISIBLE tag=%s height_px=%.0f on=%d blockers=%s in_frame=%s hud_px=%d ok=%s"
				% [
					tag,
					seen.get("height_px", 0.0),
					seen["on"],
					seen["blockers"],
					seen.get("in_frame"),
					seen.get("hud_px", 0),
					ok,
				]
			)
		)
		results[tag] = seen
		shown += int(ok)
	holder.free()
	paused = false
	return {"shown": shown, "image": img, "results": results}


func _save(img: Image, name: String) -> void:
	var path := _out_dir.path_join(name + ".png")
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
