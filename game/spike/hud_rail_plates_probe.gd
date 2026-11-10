extends SceneTree
## Windowed plates of the right rail (HUD 3/7, AlertStack, decision hud-grid-and-
## rails-one-spacing-grid-centred-top-row-right-ra, parts 1, 3 and 5). Boots the
## real main scene with a new random sim seed (printed), clock paused, then:
##   01_start: the start view, the clock panel and an empty rail
##   02_alerts_result_1_flight: three alert cards and the flight result card,
##      raised in the order A, B, result, C, so newest first reads C, result, B, A
##   (no 03: the start world has no gate stand, so no contract or one-off
##      flight can be added to grow the clock panel; the rail following a taller
##      panel is covered by test_alert_rail_hud.gd)
##   04_more: three more alert cards, so '+N more' shows
##   05_history_tray: the Alerts button pressed, the history tray in the cards'
##      place
##   06_build_tray_open: the history tray closed and the first build menu
##      opened; the rail stops above the tray stack and the rest go to '+N more'
## The alert cards come from causes fed to the rail's own AlertBoard (show_after
## 0, a clear_after the paused clock never reaches), the same path a real cause
## takes; the result card is a FlightResultPanel posted as the HUD posts one.
## Every plate checks, and prints, the rail on the margin RAIL_W wide and
## GROUP_GAP under the clock panel, each drawn card inside the view, clear of
## the clock panel and above the build tray, and the order of the cards. A failed
## check prints PROBE_INVALID and the probe exits 1.
##
## Run (one windowed Godot run project-wide; hold tools/blender/out/.windowed.lock):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/hud_rail_plates_probe.gd
##
## Plates go to tools/blender/out/hud-3-rail/.

const OUT_REL := "res://../tools/blender/out/hud-3-rail"
const MAIN_SCENE := "res://main/main.tscn"
const WINDOW := Vector2i(1920, 1080)
const HOLD := 1_000_000_000
const CAUSES := [
	["queue_a", "Check-in queue full", "1 desk full: open another desk or hire staff"],
	["route_b", "No route for 3 passengers", "They cannot walk to check-in: join the floor"],
	["gate_c", "Gate seats full", "12 passengers stand at gate C: add seats"],
	["more_d", "Security queue full", "1 lane full: open another lane"],
	["more_e", "Terminal is dirty", "Spills are piling up: hire a cleaner"],
	["more_f", "Toilets queue full", "8 passengers wait: build more stalls"],
]

var _out_dir := ""
var _failed := false
var _main: Node
var _clock: SimClock
var _sim: PassengerSim
var _hud: PassengerHud
var _stack: AlertStack
var _causes: Array[Dictionary] = []


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		_hud.refresh()
		await process_frame
	await RenderingServer.frame_post_draw


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
	_stack = _hud.find_child("AlertStack", false, false) as AlertStack
	await _frames(30)
	await _plate("01_start", [])
	_raise(0)
	_raise(1)
	_post_result()
	_raise(2)
	await _frames(10)
	await _plate("02_alerts_result_1_flight", [&"gate_c", PassengerHud.RESULT_KEY, &"route_b"])
	for i in range(3, CAUSES.size()):
		_raise(i)
	await _frames(10)
	await _plate("04_more", [&"more_f"])
	(_stack.find_child("AlertHistoryButton", true, false) as Button).button_pressed = true
	await _frames(10)
	await _plate("05_history_tray", [])
	(_stack.find_child("AlertHistoryButton", true, false) as Button).button_pressed = false
	_menu().press_category(0)
	await _frames(10)
	await _plate("06_build_tray_open", [&"more_f"])
	_main.queue_free()
	await process_frame
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _menu() -> BuildMenu:
	return _main.get_node("BuildMenu") as BuildMenu


## Raises CAUSES[i] as an alert card, held while the clock is paused.
func _raise(i: int) -> void:
	var c: Array = CAUSES[i]
	(
		_causes
		. append(
			{
				"key": StringName(c[0]),
				"title": c[1],
				"detail": c[2],
				"targets": [],
				"show_after": 0,
				"clear_after": HOLD,
			}
		)
	)
	_stack.board().update(_causes, _sim.tick)
	_hud.refresh()


func _post_result() -> void:
	var summary := {
		"flight": "GMF101-d0",
		"title": "Sunhop Lisbon",
		"made": 31,
		"missed": 6,
		"reasons":
		[
			{"count": 3, "text": "Still at the cafe"},
			{"count": 2, "text": "Held up by crowds at the gate"},
			{"count": 1, "text": "Still at a shop"},
		],
	}
	var card := FlightResultPanel.new()
	card.show_result(summary)
	var lines := card.result_text().split("\n")
	var detail := "\n".join(lines.slice(1))
	# Held far past its 20 s, so real time in the probe cannot take it down.
	_stack.post_notice(
		PassengerHud.RESULT_KEY, card, FlightResultPanel.SHOW_SECONDS * 1000.0, lines[0], detail
	)


## Checks the rail against the grid, prints what it compared and saves the plate.
## `top_keys` must start the drawn order.
func _plate(label: String, top_keys: Array) -> void:
	var view := root.get_visible_rect().size
	var panel := (_hud.find_child("FlightPanel", false, false) as Control).get_global_rect()
	var rail := _stack.get_global_rect()
	var below := BuildMenu.MARGIN + BuildMenu.BAR_H
	if _menu().is_tray_open():
		below = BuildMenu.tray_stack_top()
	var stop := view.y - below - HudLayout.GROUP_GAP
	var shown := _stack.shown_keys()
	print(
		(
			"PLATE %s view=%s panel=%s rail=%s stop=%.0f shown=%s more=%d tray=%s"
			% [label, view, panel, rail, stop, shown, _stack.more_count(), _stack.is_tray_open()]
		)
	)
	_check(
		label,
		"panel on margin",
		panel.position,
		Vector2(view.x - HudLayout.MARGIN - HudLayout.RAIL_W, HudLayout.MARGIN)
	)
	_check(label, "rail x", rail.position.x, view.x - HudLayout.MARGIN - HudLayout.RAIL_W)
	_check(label, "rail w", rail.size.x, float(HudLayout.RAIL_W))
	_check(label, "rail top", rail.position.y, panel.end.y + HudLayout.GROUP_GAP)
	for i in top_keys.size():
		if i >= shown.size() or shown[i] != top_keys[i]:
			_invalid("%s order %s does not start with %s" % [label, shown, top_keys])
			break
	var parts: Array[Control] = []
	for key in shown:
		var card := _stack.card_node(key)
		parts.append(card if card != null else _stack.notice_card(key))
	for name in ["AlertsMore", "AlertHistory"]:
		var part := _stack.find_child(name, true, false) as Control
		if part.is_visible_in_tree():
			parts.append(part)
	for part in parts:
		var r := part.get_global_rect()
		print("PLATE %s part %s rect=%s" % [label, part.name, r])
		if r.intersects(panel) or r.end.y > stop + 0.5 or not Rect2(Vector2.ZERO, view).encloses(r):
			_invalid(
				"%s %s at %s meets the panel, the tray line or the edge" % [label, part.name, r]
			)
	var result := _stack.notice_card(PassengerHud.RESULT_KEY)
	if result != null and result.is_visible_in_tree():
		var style := result.get_theme_stylebox("panel") as StyleBoxFlat
		var green := FlightResultPanel.green_card().bg_color
		print("PLATE %s result bg=%s green=%s" % [label, style.bg_color, green])
		if not style.bg_color.is_equal_approx(green):
			_invalid("%s result card is not green" % label)
	var img := root.get_texture().get_image()
	var path := _out_dir.path_join("%s.png" % label)
	var err := img.save_png(path)
	print("PLATE %s saved=%s err=%d size=%s" % [label, path, err, img.get_size()])
	if err != OK:
		_invalid("%s could not be saved" % label)


func _check(label: String, what: String, actual: Variant, expected: Variant) -> void:
	var ok: bool = (
		actual.is_equal_approx(expected) if actual is Vector2 else is_equal_approx(actual, expected)
	)
	if not ok:
		_invalid("%s %s is %s, expected %s" % [label, what, actual, expected])
