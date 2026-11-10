extends SceneTree
## Windowed plate probe for the top-left column (HUD 4/7, decisions hud-grid-
## and-rails-one-spacing-grid-centred-top-row-right-ra part 4 and checklist-
## card-moves-to-the-top-left-column-slim-at-304-px-t) on the real main scene:
##   a_checklist_1920   start view, the checklist card under the list
##   b_departures_1920  the starter terminal built and the airport open, the
##                      departures list with flights open, the card under it
##   c_hint_1920        a first-time hint card in the same slot
##   d_mood_1920        the Mood toggle on, its legend showing
## Before each save it prints the column's rectangles and proves the three
## toggles share a width and x with 8 px gaps, the list and cards are 304 wide at
## x 16, nothing in the column reaches the money row, and the 3D view's centre
## is clear of the column; otherwise it prints PROBE_INVALID and exits 1.
##
## Run (one windowed Godot run project-wide):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy --path game \
##     -s res://spike/hud_left_column_plates_probe.gd

const OUT_DIR := "res://../tools/blender/out/hud-4-left"
const SETTINGS := "user://left_column_probe_settings.cfg"
const HINTS_MEMORY := "user://left_column_probe_hints.cfg"
const LIMIT_MS := 90000

var _failed := false
var _main: Node
var _hud: PassengerHud
var _hints: Hints
var _out := ""
var _start_ms := 0


func _initialize() -> void:
	var probe_seed := randi()
	seed(probe_seed)
	print("PROBE seed=", probe_seed)
	_out = ProjectSettings.globalize_path(OUT_DIR).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out)
	_start_ms = Time.get_ticks_msec()
	_run.call_deferred()


func _run() -> void:
	DirAccess.remove_absolute(HINTS_MEMORY)
	DirAccess.remove_absolute(SETTINGS)
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_hud = _main.get_node("PassengerHud") as PassengerHud
	var mood := _main.get_node("MoodOverlay") as MoodOverlay
	mood.settings_path = SETTINGS
	var board := _main.find_child("DeparturesBoard", true, false) as DeparturesBoard
	board.settings_path = SETTINGS
	await _frames(10)
	print("PROBE window=%s layout=%s" % [root.size, root.get_visible_rect().size])
	if root.size != Vector2i(1920, 1080):
		_invalid("the window is %s, not 1920x1080" % root.size)
	_hints = Hints.new()
	_hints.forced_mode = Hints.Mode.PROFILE
	_hints.settings_path = HINTS_MEMORY
	_hints.hud = _hud
	_hints.scene_root = _main
	_hints.reads_world = false
	_hud.add_child(_hints)
	await _frames(10)
	var sim := _main.get_node("PassengerSim") as PassengerSim
	await _plate("a_checklist_1920", [_main.get_node("StaffPanel").hint_card()])

	# The first-time hint needs a bare floor, so it is plated before the terminal.
	_hints.advance(Hints.GRACE_S + 0.1, HintRules.read_world(sim, []), [])
	for i in 8:
		_hints.advance(0.25, HintRules.read_world(sim, []), ["Check-in"])
	await _frames(10)
	print("PROBE hint showing=%s" % _hints.is_showing())
	if not _hints.is_showing():
		_invalid("c: no first-time hint is showing")
	await _plate("c_hint_1920", [_hints.card()])
	_hints.set_enabled(false)

	_hud.press_starter_terminal()
	var flights := _main.find_child("FlightSim", true, false) as FlightSim
	var gate := _main.get_node("AirportGate") as AirportGate
	print("PROBE gate open=%s" % gate.open())
	for extra in [
		["PLATE2", 20 * 60, "Reykjavik", "Sunhop Regional Airways"],
		["PLATE3", 14 * 60, "Thessaloniki", "Gotta Air"],
	]:
		var terms := TestFlightContracts.terms(extra[0], extra[1])
		terms["destination"] = extra[2]
		terms["airline"] = extra[3]
		terms["plane_size"] = "small"
		terms["booked_passengers"] = 12
		print("PROBE accept %s=%s" % [extra[0], flights.accept_contract(terms)])
	_hud.refresh()
	await _frames(40)
	print("PROBE departures lines: %s" % [board.shown_lines()])
	await _plate("b_departures_1920", [_main.get_node("StaffPanel").hint_card()])

	mood.set_shown(true)
	await _frames(10)
	if not mood.is_shown():
		_invalid("d: the Mood overlay did not turn on")
	await _plate("d_mood_1920", [_main.get_node("StaffPanel").hint_card()])

	DirAccess.remove_absolute(HINTS_MEMORY)
	DirAccess.remove_absolute(SETTINGS)
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _plate(label: String, cards: Array) -> void:
	var m := HudLayout.MARGIN
	var toggles: Array[Rect2] = []
	for node_name in ["MoodToggle", "DeparturesToggle", "HintsToggle"]:
		toggles.append((_main.find_child(node_name, true, false) as Control).get_global_rect())
	print("PLATE %s toggles %s" % [label, toggles])
	for i in toggles.size():
		if (
			not is_equal_approx(toggles[i].size.x, HudLayout.TOGGLE_W)
			or not is_equal_approx(toggles[i].position.x, m)
			or not is_equal_approx(toggles[i].size.y, HudLayout.BUTTON_H)
		):
			_invalid("%s: toggle %d is not 176x40 at x 16" % [label, i])
		if (
			i > 0
			and not is_equal_approx(toggles[i].position.y - toggles[i - 1].end.y, HudLayout.GAP)
		):
			_invalid("%s: gap above toggle %d is not 8" % [label, i])
	var column: Array[Rect2] = toggles.duplicate()
	var panel := (_main.find_child("DeparturesPanel", true, false) as Control).get_global_rect()
	print("  LIST %s" % [panel])
	if panel.size.x > HudLayout.LIST_W + 0.5:
		_invalid("%s: the list is %.1f wide, over %d" % [label, panel.size.x, HudLayout.LIST_W])
	column.append(panel)
	for card in cards:
		var rect := (card as Control).get_global_rect()
		print("  CARD %s %s" % [(card as Control).name, rect])
		if (
			not is_equal_approx(rect.size.x, HudLayout.LIST_W)
			or not is_equal_approx(rect.position.x, m)
		):
			_invalid("%s: card %s is not 304 wide at x 16" % [label, rect])
		if rect.position.y < panel.end.y:
			_invalid("%s: card %s starts above the list's end %.1f" % [label, rect, panel.end.y])
		column.append(rect)
	var legend := _main.find_child("MoodLegend", true, false) as Control
	if legend.is_visible_in_tree():
		print("  LEGEND %s" % [legend.get_global_rect()])
		column.append(legend.get_global_rect())
	var money := (_main.find_child("MoneySlot", true, false) as Control).get_global_rect()
	print("  MONEY %s" % [money])
	var view := root.get_visible_rect()
	var centre := view.get_center()
	for rect in column:
		if rect.intersects(money):
			_invalid("%s: %s overlaps the money slot" % [label, rect])
		if rect.has_point(centre):
			_invalid("%s: %s covers the view centre" % [label, rect])
		if not view.encloses(rect):
			_invalid("%s: %s leaves the window" % [label, rect])
	await RenderingServer.frame_post_draw
	var path := _out.path_join(label + ".png")
	var err := root.get_texture().get_image().save_png(path)
	print("PLATE saved %s err=%d" % [path, err])
	if Time.get_ticks_msec() - _start_ms > LIMIT_MS:
		_invalid("the probe ran past %d ms" % LIMIT_MS)


func _invalid(why: String) -> void:
	_failed = true
	print("PROBE_INVALID: ", why)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
