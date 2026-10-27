extends SceneTree
## Windowed plates for the closed airport (board items staff follow-ups 3 and 4):
## the Closed sign over every unstaffed desk and scanner, and the staff panel
## in the bottom category bar with the "Airport closed: ..." hint visible.
## Boots the real main scene with a new random sim seed (printed), builds
## ReferenceTerminal through the HUD's starter-terminal button and hires nobody.
## Plates:
##   01 card closed: Closed signs over the desks and scanners, the hint above
##      the status and cost lines, the Staff button on the bar
##   02 the Staff button pressed: the hiring card above the bar in the tray's
##      place, the hint still shown
## Every plate proves its subjects before it is saved: each station's Closed
## sign, its caption and the station's centre project inside the frame with a
## margin; the plate against a twin rendered with the HUD's canvas layers hidden
## shows no HUD pixel over the signs or captions, and does show the HUD over the
## hint (and the card on plate 02); the hint, the bar and the card rects lie in
## the window and overlap none of each other; the hint text starts with
## "Airport closed:". The control: after one agent and one officer are hired and
## on duty the airport opens, the Closed signs and the hint go, so the probe
## sees the state it checks. Otherwise it prints PROBE_INVALID and exits 1. A
## guard thread calls OS.crash() on a stall.
##
## Run (one windowed Godot run project-wide; take the slot first); --ui-scale
## overrides the content scale from project.godot, and the plate names carry
## the scale:
##   timeout 600 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/staff_closed_plates_probe.gd -- --ui-scale=1.0
##
## Plates go to tools/blender/out/staff_closed/.

const PlateSight := preload("res://spike/plate_sight.gd")
const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/staff_closed"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 60000
const DISTANCE := 24.0
const CAPTION_OUTLINE_PX := 8.0

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
var _sim: PassengerSim
var _markers: MissMarkers
var _menu: BuildMenu
var _panel: StaffPanel
var _scale_tag := ""


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-scale="):
			root.content_scale_factor = float(arg.get_slice("=", 1))
	_scale_tag = "_s%.2f" % root.content_scale_factor
	print("PROBE ui_scale=%.2f" % root.content_scale_factor)
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


## Guard thread: a frozen main thread never reaches _process, so check from here.
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
		if idle_ms > HANG_LIMIT_MS:
			print("PROBE_INVALID hang stage=%s no heartbeat for %d ms" % [stage, idle_ms])
			OS.crash("staff closed plates probe hung")


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
		await _plates()
	if not _failed:
		_control()
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _boot() -> void:
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	var seed := randi()
	_clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	root.add_child(_main)
	_clock.set_paused(true)
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	_sim = _main.get_node("PassengerSim")
	_markers = (_main.get_node("PassengerViews") as PassengerViews).get_node("MissMarkers")
	_menu = _main.get_node("BuildMenu")
	_panel = _main.get_node("StaffPanel")
	await _frames(5)
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	var build := _main.get_node("BuildMode") as BuildMode
	build.set_tool(BuildMode.Tool.NONE)
	await _frames(4)
	print(
		(
			"PROBE terminal desks=%d scanners=%d staff=%d closed_stations=%d"
			% [
				_sim.layout.desks.size(),
				_sim.layout.scanners.size(),
				(_main.get_node("Staff") as StaffSim).member_ids().size(),
				MissSignals.closed_stations(_sim).size()
			]
		)
	)
	if _sim.layout.desks.is_empty() or _sim.layout.scanners.is_empty():
		_invalid("the starter terminal has no desk or scanner")


func _plates() -> void:
	var centre := _stations_centre()
	_aim(centre)
	await _frames(20)
	await _plate("01_closed_signs_and_hint", false)
	_menu.press_staff()
	await _frames(10)
	await _plate("02_staff_card_in_bar", true)
	_menu.press_staff()


func _stations_centre() -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for station: int in MissSignals.closed_stations(_sim):
		var record := _sim.grid.get_object(station)
		var def := BuildCatalog.get_def(StringName(record["def"]))
		var cells := def.footprint(record["anchor"], record["facing"])
		sum += BuildView.object_transform(_sim.grid, cells, record["facing"]).origin
		count += 1
	return sum / maxi(count, 1)


func _aim(at: Vector3) -> void:
	_rig.stop_follow()
	_rig.position = Vector3(at.x, 0.0, at.z)
	_rig.yaw = 0.0
	_rig.distance = DISTANCE


func _frame_rect() -> Rect2:
	return Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)


func _plate(name: String, card_open: bool) -> void:
	_beat(name)
	paused = true
	var img := await PlateSight.grab(self)
	var per_screen := root.get_visible_rect().size.y / float(img.get_height())
	var twin: Dictionary = await PlateSight.hud_twin(self, _main)
	var bare: Image = twin["image"]
	var whole := Rect2i(Vector2i.ZERO, img.get_size())
	var changed := PlateSight.differing(img, bare, whole, 4)
	print("HUD layers_hidden=%d plate_px_changed=%d" % [twin["layers"], changed])
	var ok := changed > 0
	var closed := MissSignals.closed_stations(_sim)
	var expected := _sim.layout.desks.size() + _sim.layout.scanners.size()
	print(
		(
			"PLATE %s%s tick=%d closed_stations=%d of %d"
			% [name, _scale_tag, _clock.tick, closed.size(), expected]
		)
	)
	ok = ok and closed.size() == expected
	var subjects: Array[Rect2] = []
	# A generous screen box under each sign: the desk or scanner it marks.
	var bodies: Array[Rect2] = []
	for station: int in closed:
		var sign := _markers.closed_sign_for(station)
		if sign == null or not sign.visible or _cam.is_position_behind(sign.global_position):
			_invalid(
				"%s: station %d has no visible Closed sign in front of the camera" % [name, station]
			)
			ok = false
			continue
		var anchor := _cam.unproject_position(sign.global_position)
		var sign_px := MissMarkers.SIGN_PX * per_screen
		var icon := Rect2(anchor - Vector2(sign_px / 2.0, sign_px), Vector2.ONE * sign_px)
		var text := _markers.closed_text(station)
		var size := (
			ThemeDB.fallback_font.get_string_size(
				text, HORIZONTAL_ALIGNMENT_LEFT, -1, MissMarkers.CAPTION_FONT
			)
			* per_screen
		)
		var lift := (MissMarkers.SIGN_PX + MissMarkers.CAPTION_GAP_PX) * per_screen + size.y
		var caption := Rect2(anchor + Vector2(-size.x / 2.0, -lift), size).grow(
			CAPTION_OUTLINE_PX * per_screen
		)
		var inside := _frame_rect().encloses(icon) and _frame_rect().encloses(caption)
		print(
			(
				"SIGN station=%d text=%s icon=%s caption=%s in_frame=%s"
				% [station, text, icon, caption, inside]
			)
		)
		ok = ok and inside and text == MissMarkers.CLOSED_CAPTION
		subjects.append(icon)
		subjects.append(caption)
		bodies.append(Rect2(anchor - Vector2(60.0, 0.0), Vector2(120.0, 110.0)))
	var under: Array[int] = []
	for rect in subjects:
		var count := PlateSight.differing(
			img, bare, PlateSight.to_screen(rect, per_screen, img.get_size()), 1
		)
		under.append(count)
		ok = ok and count == 0
	print("HUD px_under_signs=%s" % [under])
	ok = _hud_layout(img, bare, per_screen, card_open) and ok
	ok = _hint_clear_of_stations(bodies, subjects) and ok
	paused = false
	if ok:
		_save(img, name)
	else:
		_invalid("%s: signs, hint, bar or card failed their checks" % name)


## The hint's card must cover no station (the screen box under its sign) and no
## sign or caption: it has its own backing, so it must not hide the world.
func _hint_clear_of_stations(bodies: Array[Rect2], signs: Array[Rect2]) -> bool:
	var card := _panel.hint_label().get_parent() as Control
	var box := card.get_global_rect()
	var ok := true
	for rect in bodies + signs:
		var overlap := box.intersects(rect)
		ok = ok and not overlap
		if overlap:
			print("HINTCARD overlaps %s (card %s)" % [rect, box])
	print("HINTCARD rect=%s stations=%d clear=%s" % [box, bodies.size(), ok])
	return ok


## The hint, the bar and (when open) the card lie in the window, overlap none of
## each other, show HUD pixels in the plate and read as the closed airport.
func _hud_layout(img: Image, bare: Image, per_screen: float, card_open: bool) -> bool:
	var hint := _panel.hint_label()
	var rects := {"hint": hint.get_global_rect(), "bar": _menu.bar().get_global_rect()}
	if card_open:
		rects["card"] = _panel.card().get_global_rect()
	var ok := _panel.card().visible == card_open and hint.is_visible_in_tree()
	ok = ok and hint.text.begins_with("Airport closed:")
	print("HINT visible=%s text='%s'" % [hint.is_visible_in_tree(), hint.text.replace("\n", " | ")])
	var window := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var names := rects.keys()
	for i in names.size():
		var rect: Rect2 = rects[names[i]]
		var drawn := PlateSight.differing(
			img, bare, PlateSight.to_screen(rect, per_screen, img.get_size()), 2
		)
		var inside := window.encloses(rect)
		print("RECT %s=%s in_window=%s hud_px=%d" % [names[i], rect, inside, drawn])
		ok = ok and inside and drawn > 0
		for j in range(i + 1, names.size()):
			var other: Rect2 = rects[names[j]]
			var overlap := rect.intersects(other)
			print("OVERLAP %s/%s=%s" % [names[i], names[j], overlap])
			ok = ok and not overlap
	return ok


## After one agent and one officer are hired and on duty the airport opens and
## the Closed signs and the hint go.
func _control() -> void:
	_beat("control")
	var staff := _main.get_node("Staff") as StaffSim
	_panel.hire_button(StaffMember.Role.CHECKIN).pressed.emit()
	_panel.hire_button(StaffMember.Role.SECURITY).pressed.emit()
	var gate := _main.get_node("AirportGate") as AirportGate
	StarterFlight.advance_until(_clock, gate.is_open, StarterFlight.OPEN_LIMIT_TICKS)
	var expected := _sim.layout.desks.size() + _sim.layout.scanners.size()
	var closed_left := MissSignals.closed_stations(_sim)
	var signs := 0
	for station: int in _sim.layout.desks + _sim.layout.scanners:
		signs += int(_markers.closed_sign_for(station) != null)
	print(
		(
			"CONTROL tick=%d open=%s hired=%d closed_stations=%d of %d closed_signs=%d hint='%s'"
			% [
				_clock.tick,
				gate.is_open(),
				staff.member_ids().size(),
				closed_left.size(),
				expected,
				signs,
				_panel.hint_label().text.replace("\n", " | ")
			]
		)
	)
	# The two hires staff one desk and one scanner, so the others stay closed.
	var ok := gate.is_open() and closed_left.size() == expected - 2 and signs == closed_left.size()
	if not ok or _panel.hint_label().text.begins_with("Airport closed:"):
		_invalid("control: the airport did not open or its closed state did not follow")


func _save(img: Image, name: String) -> void:
	var path := _out_dir.path_join(name + _scale_tag + ".png")
	var err := img.save_png(path)
	if err != OK:
		_invalid("could not save %s (error %d)" % [path, err])
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
