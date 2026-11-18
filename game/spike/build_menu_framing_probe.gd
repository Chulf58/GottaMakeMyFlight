extends SceneTree
## Windowed probe for board D3c: does the camera hold its framing while the
## player switches between build menus (decision camera-makes-room-once-per-
## build-mode-open-not-on-every-menu-switch)? Boots the real main scene with a
## new random sim seed (printed), clock paused, and runs:
##   plain: opens Check-in, waits 20 frames, settles, then presses Security,
##     Gates, Lane, Cafe and Check-in, 30 frames after each
##   alert_before: the same with a "Nobody on duty" alert card already up
##   alert_mid: the alert card comes up while Check-in is open, then the switches
##   cards: Security, its Scanner card, Gates, the Gate desk card, the Seats
##     card, with the alert card up (the playtest's path to screenshot 06)
##   staff: Check-in, the Staff card, Gates (a new tray open, by design a
##     refit), then Lane, Cafe and Check-in, with the alert card up
## After each press it prints the camera's position, distance, target distance,
## room target, PanelRoom.open_key() and _kept, and the deltas from the view
## the switches started from. Each run ends with a control: closing the tray
## must change the distance. Every frame in which the camera's target distance
## changes prints a DIST line with PanelRoom's state, which names the trigger.
## Last, board D3c (3): after a follow ends, and after a glide, with no input,
## the camera position is printed once a second for 10 s.
##
## Pass: every switch moves the distance less than 0.01 and the position less
## than 0.05, every opened tray frames at the plain run's distance (within
## 0.01) with or without an alert card, every tray-close control changes the
## distance by more, and the camera stays put after the follow and the glide. A failure prints
## PROBE_INVALID and the probe exits 1.
##
## Run (one windowed Godot run project-wide; hold tools/blender/out/.windowed.lock):
##   timeout 600 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/build_menu_framing_probe.gd

const MAIN_SCENE := "res://main/main.tscn"
const WINDOW := Vector2i(1920, 1080)
const SETTLE := 30
const OPEN_WAIT := 20
const CALM := 60
const HOLD := 1_000_000_000
const SWITCHES := ["Security", "Gates", "Lane", "Cafe", "Check-in"]
const MAX_DISTANCE_DELTA := 0.01
const MAX_POSITION_DELTA := 0.05
const HANG_MS := 60000
const ALERT := [
	"nobody_on_duty", "Nobody on duty", "1 station is closed · hire staff on the Staff card"
]

var _failed := false
var _main: Node
var _clock: SimClock
var _sim: PassengerSim
var _hud: PassengerHud
var _stack: AlertStack
var _cam: TycoonCamera
var _room: PanelRoom
var _menu: BuildMenu
var _stage := "init"
var _last_target := NAN
var _guard := Thread.new()
var _lock := Mutex.new()
var _beat := 0
var _done := false
var _plain_open := NAN


func _initialize() -> void:
	_beat = Time.get_ticks_msec()
	_guard.start(_watchdog)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	_lock.lock()
	_beat = Time.get_ticks_msec()
	_lock.unlock()
	_trace()
	return false


## Runs on its own thread: a frozen main thread stops the heartbeat, and only a
## crash gives a non-zero exit code on Windows (anti-pattern 59593d53).
func _watchdog() -> void:
	while true:
		OS.delay_msec(1000)
		_lock.lock()
		var since := Time.get_ticks_msec() - _beat
		var done := _done
		var stage := _stage
		_lock.unlock()
		if done:
			return
		if since > HANG_MS:
			printerr("PROBE_INVALID hang stage=%s silent_ms=%d" % [stage, since])
			OS.crash("build_menu_framing_probe hang")


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _set_stage(stage: String) -> void:
	_lock.lock()
	_stage = stage
	_lock.unlock()


func _run() -> void:
	root.size = WINDOW
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	var seed := randi()
	_clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	root.add_child(_main)
	_clock.set_paused(true)
	_sim = _main.get_node("PassengerSim")
	_hud = _main.get_node("PassengerHud")
	_menu = _main.get_node("BuildMenu")
	_cam = _hud.camera
	_room = _hud.get_node("PanelRoom")
	_stack = _hud.find_child("AlertStack", false, false) as AlertStack
	await _frames(CALM)
	print("PROBE viewport=%s at_home=%s" % [root.get_visible_rect().size, _cam._at_home])
	await _switch_run("plain", false, false)
	await _switch_run("alert_before", true, false)
	await _switch_run("alert_mid", true, false, true)
	await _cards_run()
	await _switch_run("staff", true, true)
	await _still_after("follow")
	await _still_after("glide")
	_set_stage("done")
	_main.queue_free()
	await process_frame
	print("PROBE done failed=", _failed)
	_lock.lock()
	_done = true
	_lock.unlock()
	_guard.wait_to_finish()
	quit(1 if _failed else 0)


## Prints a DIST line on every frame the camera's target distance changes.
func _trace() -> void:
	if _cam == null or not is_instance_valid(_cam):
		return
	var target := _cam.target_distance
	if not is_nan(_last_target) and absf(target - _last_target) > 0.0001:
		print(
			(
				(
					"DIST stage=%s frame=%d target %.3f -> %.3f key=%d tray=%s kept=%s refit=%d"
					% [
						_stage,
						Engine.get_process_frames(),
						_last_target,
						target,
						_room.open_key(),
						_menu.is_tray_open(),
						_room._kept,
						_room._refit_frames,
					]
				)
				+ (
					" at_home=%s room_target=%s rail=%s"
					% [_cam._at_home, _cam._room_target, _stack.room_rect()]
				)
			)
		)
	_last_target = target


func _state(label: String) -> Dictionary:
	var s := {
		"position": _cam.position,
		"distance": _cam.distance,
		"target": _cam.target_distance,
		"room": _cam._room_target,
	}
	print(
		(
			"CAM %s/%s pos=%s dist=%.4f target=%.4f room=%s key=%d kept=%s open=%d tray=%s"
			% [
				_stage,
				label,
				s["position"],
				s["distance"],
				s["target"],
				s["room"],
				_room.open_key(),
				_room._kept,
				_menu.open_category(),
				_menu.is_tray_open(),
			]
		)
	)
	return s


## Closes the tray and the Staff card, drops the alert cards and frames the
## start view again, so each run starts from the same view.
func _reset() -> void:
	if _menu.is_tray_open():
		_menu.press_category(_menu.open_category())
	if _menu.staff_open:
		_menu.press_staff()
	_stack.reset()
	await _frames(SETTLE)
	_hud._frame_start_view()
	await _frames(CALM)


func _raise_alert() -> void:
	var causes: Array[Dictionary] = [
		{
			"key": StringName(ALERT[0]),
			"title": ALERT[1],
			"detail": ALERT[2],
			"targets": [],
			"show_after": 0,
			"clear_after": HOLD,
		}
	]
	_stack.board().update(causes, _sim.tick)
	_hud.refresh()


func _category(category_name: String) -> int:
	var all := BuildMenu.categories()
	for i in all.size():
		if all[i]["name"] == category_name:
			return i
	_invalid("no category %s" % category_name)
	return BuildMenu.NO_CATEGORY


func _press(category_name: String) -> void:
	_set_stage("%s:%s" % [_stage.get_slice(":", 0), category_name])
	_menu.press_category(_category(category_name))


func _switch_run(run: String, alert: bool, via_staff: bool, alert_mid := false) -> void:
	_set_stage(run)
	await _reset()
	if alert and not alert_mid:
		_raise_alert()
		await _frames(SETTLE)
	print("RUN %s alert_cards=%s" % [run, _stack.shown_keys()])
	_press("Check-in")
	await _frames(OPEN_WAIT)
	_state("open+20")
	await _frames(CALM)
	if alert_mid:
		_raise_alert()
		_set_stage(run + ":alert_up")
		await _frames(SETTLE)
		print("RUN %s alert_cards=%s" % [run, _stack.shown_keys()])
	var switches: Array = SWITCHES
	if via_staff:
		_set_stage(run + ":staff")
		_menu.press_staff()
		await _frames(SETTLE)
		_state("staff")
		_press("Gates")
		await _frames(CALM)
		switches = SWITCHES.slice(2)
	var base := _state("base")
	_check_open(base)
	for category_name in switches:
		_press(category_name)
		await _frames(SETTLE)
		_compare(base, _state(category_name))
	await _control(base)


## The tray closing must refit the distance: proof the camera is still on the
## start view, where a switch would zoom it if anything did.
func _control(base: Dictionary) -> void:
	_set_stage(_stage.get_slice(":", 0) + ":close")
	_menu.press_category(_menu.open_category())
	await _frames(CALM)
	var after := _state("closed")
	var moved := absf(after["distance"] - base["distance"])
	print("CONTROL %s distance_delta=%.4f" % [_stage, moved])
	if moved <= MAX_DISTANCE_DELTA:
		_invalid("%s: closing the tray did not change the distance" % _stage)


## An opened tray must frame the same with an alert card up as without one: the
## plain run's opened distance is the reference.
func _check_open(base: Dictionary) -> void:
	if is_nan(_plain_open):
		_plain_open = base["distance"]
		return
	var dd := absf(base["distance"] - _plain_open)
	print(
		"OPEN %s distance=%.4f plain=%.4f delta=%.4f" % [_stage, base["distance"], _plain_open, dd]
	)
	if dd >= MAX_DISTANCE_DELTA:
		_invalid("%s: the opened tray framed %.4f farther than with no card" % [_stage, dd])


func _compare(base: Dictionary, now: Dictionary) -> void:
	var dd := absf(now["distance"] - base["distance"])
	var dp: float = (now["position"] as Vector3).distance_to(base["position"])
	var cam_pos := _cam.get_node("Camera3D").global_position as Vector3
	print("DELTA %s distance=%.4f position=%.4f eye=%s" % [_stage, dd, dp, cam_pos])
	if dd >= MAX_DISTANCE_DELTA or dp >= MAX_POSITION_DELTA:
		_invalid("%s: the view moved (distance %.4f, position %.4f)" % [_stage, dd, dp])


## The playtest's way to screenshot 06: a tool picked from a card, then Gates.
func _cards_run() -> void:
	_set_stage("cards")
	await _reset()
	_raise_alert()
	await _frames(SETTLE)
	print("RUN cards alert_cards=%s" % [_stack.shown_keys()])
	_press("Security")
	await _frames(OPEN_WAIT)
	_state("open+20")
	await _frames(CALM)
	var base := _state("base")
	_check_open(base)
	var steps := [
		["card Scanner", BuildMode.Tool.SCANNER],
		["Gates", -1],
		["card Gate desk", BuildMode.Tool.GATE_DESK],
		["card Seats", BuildMode.Tool.SEATS],
	]
	for step in steps:
		_set_stage("cards:" + step[0])
		if step[1] == -1:
			_menu.press_category(_category(step[0]))
		else:
			_menu.press_card(step[1])
		await _frames(SETTLE)
		_compare(base, _state(step[0]))
	_menu.press_category(_menu.open_category())
	await _frames(SETTLE)


## Board D3c (3): after a follow ends (or a glide), with no input for 10 s, the
## camera must not move. Prints the position once a second.
func _still_after(kind: String) -> void:
	_set_stage("still_" + kind)
	await _reset()
	var mover := Node3D.new()
	_main.add_child(mover)
	mover.global_position = _cam.position + Vector3(6.0, 0.0, 4.0)
	if kind == "follow":
		_cam.follow(mover)
		await _frames(CALM * 2)
		_cam.stop_follow()
	else:
		_cam.glide_to(mover.global_position, _cam.distance * 0.8)
		await _frames(CALM * 2)
	mover.queue_free()
	var start := _cam.position
	var start_distance := _cam.distance
	var pressed: Array[String] = []
	for action in InputMap.get_actions():
		if String(action).begins_with("cam_") and Input.is_action_pressed(action):
			pressed.append(String(action))
	print(
		(
			"STILL %s following=%s gliding=%s cam_pressed=%s"
			% [kind, _cam.is_following(), _cam.is_gliding(), pressed]
		)
	)
	var t0 := Time.get_ticks_msec()
	var worst := 0.0
	for second in range(1, 11):
		while Time.get_ticks_msec() - t0 < second * 1000:
			await process_frame
		var moved := _cam.position.distance_to(start)
		worst = maxf(worst, moved)
		print(
			(
				"STILL %s t=%ds pos=%s moved=%.4f distance=%.4f"
				% [kind, second, _cam.position, moved, _cam.distance]
			)
		)
	var distance_moved := absf(_cam.distance - start_distance)
	print("STILL %s worst=%.4f distance_moved=%.4f" % [kind, worst, distance_moved])
	if worst >= MAX_POSITION_DELTA or distance_moved >= MAX_DISTANCE_DELTA:
		_invalid("%s: the camera moved with no input" % kind)
