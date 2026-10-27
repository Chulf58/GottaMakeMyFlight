extends SceneTree
## Windowed probe: do real mouse clicks reach the HUD buttons, and does a HUD
## click stay out of BuildMode? (board item smoke-playtest-2-real-mouse-clicks-
## through-the-godot-mcp-nev; anti-pattern godot-mcp-simulate-input-mouse-
## events-do-not-move-the-game-s.)
##
## At UI scale 1.0 and 1.25 it boots main.tscn, warps the real mouse
## (Viewport.warp_mouse) onto the bar's Staff button, then onto the staff
## card's check-in Hire button centre, and queues a mouse motion, then a left
## press and release through Input.parse_input_event at that point, in window
## pixels (the viewport point through Window.get_final_transform). It prints the
## control under the pointer, the hire count before and after, the BuildMode
## edits and refusals the click caused, and how many left-button events reached
## _unhandled_input (the stage BuildMode reads; a tap node on the root counts
## them). The floor tool is armed for the Staff click, so a leak would make an
## edit. The Hire card closes when a tool is armed, so that click runs with no
## tool, where an edit cannot happen: its leak check is the tap count, which
## must stay 0. A control click on empty world with the floor tool armed must
## produce a recorded edit or refusal and reach the tap: it proves the
## instrument sees BuildMode. Pass values are positives
## (the hire count rose, the speed changed, the control click was recorded);
## each compared value is printed. A failure prints PROBE_INVALID and exits 1.
## A guard thread calls OS.crash() on a hang.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game -s res://spike/hud_click_probe.gd

const MAIN := "res://main/main.tscn"
const SCALES: Array[float] = [1.0, 1.25]
const HANG_LIMIT_MS := 20000
const TOTAL_LIMIT_MS := 120000

var _guard := Thread.new()
var _mutex := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _done := false
var _failed := false

var _main: Node3D
var _mode: BuildMode
var _staff: StaffSim
var _clock: SimClock
var _applied := 0
var _refused := 0
var _tap := InputTap.new()
var _reached := 0


func _initialize() -> void:
	_beat("boot")
	_guard.start(_watch)
	_run.call_deferred()


func _run() -> void:
	var world_seed := randi()
	print("PROBE world_seed=%d" % world_seed)
	_main = load(MAIN).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(world_seed)
	root.add_child(_main)
	_clock.set_process(false)
	_mode = _main.get_node("BuildMode")
	_staff = _main.get_node("Staff")
	_mode.grid.edit_applied.connect(func(_e: BuildEdit, _r: BuildResult) -> void: _applied += 1)
	_mode.grid.edit_refused.connect(func(_e: BuildEdit, _r: BuildResult) -> void: _refused += 1)
	root.add_child(_tap)
	(_main.get_node("TycoonCamera/Camera3D") as Camera3D).make_current()
	await _frames(6)
	print("PROBE window=%s viewport=%s" % [root.size, root.get_visible_rect().size])
	for scale_value in SCALES:
		await _at_scale(scale_value)
	print("PROBE_INVALID" if _failed else "PROBE_PASS")
	_finish(1 if _failed else 0)


func _at_scale(scale_value: float) -> void:
	root.content_scale_factor = scale_value
	_beat("scale")
	await _frames(6)
	var size := root.get_visible_rect().size
	print("PROBE ui_scale=%.2f viewport=%s" % [root.content_scale_factor, size])
	# The Staff click runs with the floor tool armed, so a leaked click would
	# make an edit. An armed tool closes the hiring card, so the Hire click runs
	# with no tool (the Staff click drops it): its leak check is the tap count.
	_mode.set_tool(BuildMode.Tool.FLOOR)
	var menu := _main.get_node("BuildMenu") as BuildMenu
	var panel := _main.get_node("StaffPanel") as StaffPanel
	var opened := await _click(menu.staff_button, "staff button")
	print(
		(
			"PROBE scale=%.2f staff_button staff_open=%s card_visible=%s build_events=%d reached=%d"
			% [scale_value, menu.staff_open, panel.card().is_visible_in_tree(), opened, _reached]
		)
	)
	_expect(menu.staff_open, "the Staff button click did not open the staff card")
	_expect(panel.card().is_visible_in_tree(), "the staff card is not visible after its button")
	_expect(opened == 0, "the Staff button click reached BuildMode (%d events)" % opened)
	_expect(_reached == 0, "the Staff button click reached _unhandled_input (%d)" % _reached)
	_expect(_mode.tool == BuildMode.Tool.NONE, "the Staff button did not drop the armed tool")
	var hire := panel.hire_button(StaffMember.Role.CHECKIN)
	var before := _staff.count(StaffMember.Role.CHECKIN)
	var events := await _click(hire, "hire")
	var after := _staff.count(StaffMember.Role.CHECKIN)
	print(
		(
			"PROBE scale=%.2f hire hired_before=%d hired_after=%d build_events=%d reached=%d"
			% [scale_value, before, after, events, _reached]
		)
	)
	_expect(after == before + 1, "the Hire click did not hire (%d -> %d)" % [before, after])
	_expect(events == 0, "the Hire click reached BuildMode (%d events)" % events)
	_expect(_reached == 0, "the Hire click reached _unhandled_input (%d)" % _reached)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	var speed_button := _find_button("3x")
	_clock.set_speed(1)
	_clock.set_paused(false)
	var speed_before := _clock.speed
	events = await _click(speed_button, "speed3")
	print(
		(
			"PROBE scale=%.2f speed3 speed_before=%d speed_after=%d paused=%s build_events=%d reached=%d"
			% [scale_value, speed_before, _clock.speed, _clock.paused, events, _reached]
		)
	)
	_expect(_clock.speed == 3, "the 3x click did not set the speed (%d)" % _clock.speed)
	_expect(events == 0, "the 3x click reached BuildMode (%d events)" % events)
	_expect(_reached == 0, "the 3x click reached _unhandled_input (%d)" % _reached)
	# Control: a click on empty world with the floor tool armed must be seen.
	var world_pt := Vector2(root.get_visible_rect().size) * Vector2(0.55, 0.5)
	events = await _click_at(world_pt, "world control")
	print(
		(
			"PROBE scale=%.2f world_control build_events=%d reached=%d"
			% [scale_value, events, _reached]
		)
	)
	_expect(events >= 1, "the control click on the world produced no BuildMode event")
	_expect(_reached >= 1, "the control click on the world did not reach _unhandled_input")
	_mode.set_tool(BuildMode.Tool.NONE)


func _find_button(label: String) -> Button:
	for node in _main.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == label and button.is_visible_in_tree():
			return button
	_fail("no visible button labelled %s" % label)
	return null


func _click(control: Control, what: String) -> int:
	return await _click_at(control.get_global_rect().get_center(), what, control)


## Warps the mouse onto `point` (viewport coordinates), queues a motion, then a
## left press and release; returns the BuildMode edits and refusals it caused and
## sets _reached to the left-button events that reached _unhandled_input.
func _click_at(point: Vector2, what: String, target: Control = null) -> int:
	_beat("click " + what)
	var window_pt := root.get_final_transform() * point
	root.warp_mouse(point)
	await _frames(2)
	var motion := InputEventMouseMotion.new()
	motion.position = window_pt
	motion.global_position = window_pt
	Input.parse_input_event(motion)
	await _frames(2)
	var hovered := root.gui_get_hovered_control()
	var ground: Variant = _mode._mouse_ground()
	print(
		(
			(
				"PROBE %s point=%s window_pt=%s mouse=%s hovered=%s is_target=%s"
				+ " target_hovered=%s ground=%s over_ui=%s"
			)
			% [
				what,
				point,
				window_pt,
				root.get_mouse_position(),
				hovered.get_path() if hovered != null else "<none>",
				hovered == target if target != null else "n/a",
				target.is_hovered() if target != null else "n/a",
				ground,
				_mode._pointer_over_ui(),
			]
		)
	)
	var base := _applied + _refused
	_tap.count = 0
	for pressed in [true, false]:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		button.position = window_pt
		button.global_position = window_pt
		button.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(button)
		await _frames(2)
	_reached = _tap.count
	return _applied + _refused - base


func _expect(ok: bool, reason: String) -> void:
	if not ok:
		_failed = true
		print("PROBE_FAIL %s" % reason)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
		_beat(_stage)


func _fail(reason: String) -> void:
	print("PROBE_INVALID %s" % reason)
	_finish(1)


func _finish(code: int) -> void:
	_mutex.lock()
	_done = true
	_mutex.unlock()
	if _guard.is_started():
		_guard.wait_to_finish()
	if _main != null:
		_main.queue_free()
	quit(code)


func _beat(stage: String) -> void:
	_mutex.lock()
	_beat_ms = Time.get_ticks_msec()
	_stage = stage
	_mutex.unlock()


func _watch() -> void:
	var started := Time.get_ticks_msec()
	while true:
		OS.delay_msec(500)
		_mutex.lock()
		var done := _done
		var beat := _beat_ms
		var stage := _stage
		_mutex.unlock()
		if done:
			return
		var now := Time.get_ticks_msec()
		if now - beat > HANG_LIMIT_MS or now - started > TOTAL_LIMIT_MS:
			print(
				(
					"PROBE_INVALID hang in stage '%s': %d ms since the last beat, %d ms in all"
					% [stage, now - beat, now - started]
				)
			)
			OS.crash("hud click probe hung")


## Counts left-button events that reach the unhandled-input stage, the one
## BuildMode reads: a control that consumed its click keeps them from here.
class InputTap:
	extends Node
	var count := 0

	func _unhandled_input(event: InputEvent) -> void:
		var button := event as InputEventMouseButton
		if button != null and button.button_index == MOUSE_BUTTON_LEFT:
			count += 1
