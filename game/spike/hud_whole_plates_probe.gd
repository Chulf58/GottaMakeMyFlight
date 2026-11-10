extends SceneTree
## Windowed plates of the whole HUD (HUD 7/7, board 3bd42402, decision
## hud-grid-and-rails-one-spacing-grid-centred-top-row-right-ra). Boots the real
## main scene once per window size (1920x1080, then 2560x1440; both lay out at
## 1536x864) with a new random sim seed (printed), clock paused, hints on in
## profile mode with a memory file of their own, and opens each HUD window in
## turn:
##   01_start            the start view: money, top row, left column, Reset
##                       hints, the checklist card, the clock panel, the bar
##   02_build_refusal    the Seats tool over a refused cell, its tray open, the
##                       status card holding the refusal
##   03_offers           the Offers sheet
##   04_runway           the Runway sheet
##   05_rail             four alert cards and the flight result card on the rail
##   06_checklist        the starter terminal built: the checklist's staff lines
##   07_departures       staff hired, the airport open and three contracts added
##                       to the starter flight on the one gate, four a day: the list and the
##                       rail under the clock with flights (board item part e)
##   08_staff_card       the bar's Staff card
##   09_inspect          a scanner selected: the inspect card
##   10_debug            the debug panel open
## For every state it walks the scene for every visible HUD window (a Button, or
## a Panel or PanelContainer that draws a panel; a window's children are part of
## it), prints each rect, proves the state's subjects are showing and inside the
## view, then checks that no two windows overlap unless a sheet covers a window
## below the top row (_allowed), and that every edge nearer a screen edge than
## MARGIN + UNIT sits exactly MARGIN from it. A failed check prints PROBE_INVALID
## and the probe exits 1.
## Each size also gets a contact sheet.
##
## Run (one windowed Godot run project-wide; hold tools/blender/out/.windowed.lock):
##   timeout 600 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/hud_whole_plates_probe.gd
##
## Plates go to tools/blender/out/hud-7-whole/.

const OUT_REL := "res://../tools/blender/out/hud-7-whole"
const MAIN_SCENE := "res://main/main.tscn"
const SIZES: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(2560, 1440)]
const LAYOUT := Vector2(1536.0, 864.0)
const HOLD := 1_000_000_000
const SAMPLE_STEP := 2
const LIMIT_MS := 500_000
const SETTINGS := "user://hud_whole_probe_settings.cfg"
const HINTS_MEMORY := "user://hud_whole_probe_hints.cfg"
const THUMB := Vector2i(480, 270)
const CAUSES := [
	["queue_a", "Check-in queue full", "1 desk full: open another desk or hire staff"],
	["route_b", "No route for 3 passengers", "They cannot walk to check-in: join the floor"],
	["gate_c", "Gate seats full", "12 passengers stand at gate C: add seats"],
	["more_d", "Security queue full", "1 lane full: open another lane"],
]
## Three contracts about 200 minutes apart after the starter flight (10:14) on its
## gate, so the day has four flights; earlier ones clash with it at the gate.
const FLIGHTS := [
	["W1", 13 * 60 + 40, "Rome", "Sunhop"],
	["W2", 17 * 60, "Berlin", "Nordic Wing"],
	["W3", 20 * 60 + 20, "Lisbon", "Sunhop"],
]
## The only windows allowed to overlap another: the modal sheets (they pause the
## game). A sheet may cover a window whose top is at or below TOP_ROW_BOTTOM,
## never the top row or the clock panel (_allowed).
const SHEETS: Array[String] = ["sheet:offers", "sheet:runway"]
## The bottom of the top row: money, rating, the centred row and the clock all
## start on the margin and are at least BUTTON_H tall.
const TOP_ROW_BOTTOM := HudLayout.MARGIN + HudLayout.BUTTON_H

var _out_dir := ""
var _failed := false
var _start_ms := 0
var _main: Node
var _hud: PassengerHud
var _stack: AlertStack
var _build: BuildMode
var _menu: BuildMenu
var _staff: StaffPanel
var _hints: Hints
var _causes: Array[Dictionary] = []
var _plates: Array[String] = []


func _initialize() -> void:
	var probe_seed := randi()
	seed(probe_seed)
	print("PROBE probe_seed=", probe_seed)
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_start_ms = Time.get_ticks_msec()
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_invalid(msg)


func _frames(count: int) -> void:
	for i in count:
		if _hud != null and is_instance_valid(_hud):
			_hud.refresh()
		await process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	_self_check()
	for size in SIZES:
		await _pass(size)
	_clean_files()
	print("PROBE plates=%d elapsed_ms=%d" % [_plates.size(), Time.get_ticks_msec() - _start_ms])
	_expect(Time.get_ticks_msec() - _start_ms < LIMIT_MS, "the probe ran past %d ms" % LIMIT_MS)
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _clean_files() -> void:
	for path in [SETTINGS, HINTS_MEMORY]:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")


## One boot of main.tscn at `size`, through every state.
func _pass(size: Vector2i) -> void:
	_clean_files()
	DisplayServer.window_set_size(size)
	await _frames(6)
	print("PROBE window=%s layout=%s" % [root.size, root.get_visible_rect().size])
	_expect(root.size == size, "the window is %s, not %s" % [root.size, size])
	_expect(
		root.get_visible_rect().size.is_equal_approx(LAYOUT),
		"the layout is %s, not %s" % [root.get_visible_rect().size, LAYOUT]
	)
	await _boot()
	var tag := "%d" % size.x
	var start_count := _plates.size()
	await _state("01_start", tag, _start_subjects())
	await _build_refusal(tag)
	await _sheets(tag)
	for i in CAUSES.size():
		_raise(i)
	_post_result()
	await _frames(10)
	await _state("05_rail", tag, _rail_subjects())
	_hud.press_starter_terminal()
	await _frames(10)
	await _state("06_checklist", tag, {"checklist card": _staff.hint_card()})
	await _open_with_flights()
	await _state("07_departures", tag, _departures_subjects())
	_menu.press_staff()
	await _frames(10)
	await _state("08_staff_card", tag, {"staff card": _staff.card()})
	_menu.press_staff()
	await _select_scanner()
	await _state("09_inspect", tag, _inspect_subjects())
	_hud.set_debug_open(true)
	await _frames(10)
	var debug := _hud.find_child("DebugPanel", true, false) as Control
	await _state("10_debug", tag, {"debug panel": debug})
	_contact_sheet(tag, _plates.slice(start_count))
	_main.queue_free()
	_main = null
	_hud = null
	_causes.clear()
	await _frames(4)


func _boot() -> void:
	_main = load(MAIN_SCENE).instantiate()
	var clock: SimClock = _main.get_node("SimClock")
	var sim_seed := randi()
	clock.seed_rng(sim_seed)
	print("PROBE sim_seed=", sim_seed)
	# Isolated settings, set before the scene reads them, so the player's own
	# choices never reach the probe and the probe never writes them.
	_hud = _main.get_node("PassengerHud")
	_hud.alert_settings_path = SETTINGS
	_hud.departures_settings_path = SETTINGS
	(_main.get_node("MoodOverlay") as MoodOverlay).settings_path = SETTINGS
	root.add_child(_main)
	clock.set_paused(true)
	_stack = _hud.find_child("AlertStack", false, false) as AlertStack
	_build = _main.get_node("BuildMode") as BuildMode
	_menu = _main.get_node("BuildMenu") as BuildMenu
	_staff = _main.get_node("StaffPanel") as StaffPanel
	# Hints in profile mode, so the column shows Hints and Reset hints as a
	# player sees them; reads_world off, so no first-time hint card pops up.
	_hints = Hints.new()
	_hints.forced_mode = Hints.Mode.PROFILE
	_hints.settings_path = HINTS_MEMORY
	_hints.hud = _hud
	_hints.scene_root = _main
	_hints.reads_world = false
	_hud.add_child(_hints)
	await _frames(30)


func _start_subjects() -> Dictionary:
	return {
		"checklist card": _staff.hint_card(),
		"clock panel": _hud.find_child("FlightPanel", true, false),
		"hints toggle": _hints.toggle_button(),
		"reset hints": _hints.reset_button(),
		"bar": _menu.bar(),
	}


func _build_refusal(tag: String) -> void:
	_build.set_tool(BuildMode.Tool.SEATS)
	await _frames(6)
	var at := _refused_point()
	if at.x < 0.0:
		_invalid("%s: no refused cell in frame for the Seats tool" % tag)
	_build.pointer_override = at
	await _frames(10)
	print(
		(
			"PLATE 02_build_refusal_%s status='%s' hint='%s' cost='%s'"
			% [
				tag,
				_menu.status_label().text,
				_menu.rotate_hint_label().text,
				_menu.preview_label().text
			]
		)
	)
	_expect(_menu.status_label().text != "", "%s: no refusal on the status card" % tag)
	await _state(
		"02_build_refusal",
		tag,
		{"tray": _menu.tray(), "status card": _menu.status_card(), "sign": _sign()}
	)
	_build.pointer_override = Vector2(-1.0, -1.0)
	_build.set_tool(BuildMode.Tool.NONE)
	await _frames(6)
	if _menu.is_tray_open():
		_menu.press_category(_menu.open_category())
		await _frames(6)
	_expect(not _menu.is_tray_open(), "%s: the tray stayed open" % tag)


func _sign() -> Control:
	return _menu.build_frame.sign_panel()


func _sheets(tag: String) -> void:
	var offers := _main.get_node("OfferPanel") as OfferPanel
	var runway := _main.get_node("RunwayCard") as RunwayCard
	offers.open()
	await _frames(10)
	await _state("03_offers", tag, {"offers sheet": offers.sheet()})
	runway.open()
	await _frames(10)
	_expect(not offers.is_open(), "%s: the Offers sheet stayed open under Runway" % tag)
	await _state("04_runway", tag, {"runway sheet": runway.sheet()})
	runway.close()
	await _frames(10)


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
	_reraise()


func _reraise() -> void:
	_stack.board().update(_causes, (_main.get_node("PassengerSim") as PassengerSim).tick)
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
	# Held far past its 20 s, so real time in the probe cannot take it down.
	_stack.post_notice(
		PassengerHud.RESULT_KEY,
		card,
		FlightResultPanel.SHOW_SECONDS * 1000.0,
		lines[0],
		"\n".join(lines.slice(1))
	)


func _rail_subjects() -> Dictionary:
	var out := {}
	for key in _stack.shown_keys():
		var part := _stack.card_node(key)
		out["rail card %s" % key] = part if part != null else _stack.notice_card(key)
	_expect(out.size() >= 4, "the rail shows %d cards, expected 4 or more" % out.size())
	_expect(
		_stack.shown_keys().has(PassengerHud.RESULT_KEY), "the rail shows no flight result card"
	)
	return out


## Hires every role, steps the clock until the airport opens, then accepts
## FLIGHTS on the starter gate. The alert causes are raised again afterwards,
## since the running clock lets the HUD's own sources update the rail.
func _open_with_flights() -> void:
	var clock: SimClock = _main.get_node("SimClock")
	var flights := _main.get_node("FlightSim") as FlightSim
	print("PROBE hired=%d" % StaffTestKit.staff_all(_main.get_node("Staff") as StaffSim))
	clock.set_paused(false)
	for i in 20:
		clock.advance(SimClock.STEP)
		if flights.opened_tick >= 0:
			break
	clock.set_paused(true)
	print("PROBE opened_tick=%d tick=%d" % [flights.opened_tick, clock.tick])
	_expect(flights.opened_tick >= 0, "the airport did not open")
	var accepted := 0
	for f in FLIGHTS:
		var terms := TestFlightContracts.terms(f[0], f[1])
		terms["destination"] = f[2]
		terms["airline"] = f[3]
		terms["plane_size"] = "small"
		terms["booked_passengers"] = 12
		var ok := flights.accept_contract(terms)
		print("PROBE accept %s=%s" % [f[0], ok])
		if ok:
			accepted += 1
	_expect(
		accepted == FLIGHTS.size(), "only %d of %d contracts accepted" % [accepted, FLIGHTS.size()]
	)
	_reraise()
	await _frames(20)


func _departures_subjects() -> Dictionary:
	var board := _main.find_child("DeparturesBoard", true, false) as DeparturesBoard
	var lines := board.shown_lines()
	print("PLATE departures lines=%s" % [lines])
	# Today's rows only: the board's entries up to its Tomorrow heading.
	var rows := 0
	var clock: SimClock = _main.get_node("SimClock")
	for entry in DeparturesBoard.entries_for(_main.get_node("FlightSim"), clock.tick):
		if entry["text"] == DeparturesBoard.TOMORROW_HEADING:
			break
		if entry["kind"] == "row":
			rows += 1
	print("PLATE departures today_rows=%d" % rows)
	_expect(rows >= 4, "the departures list shows %d flights today, expected 4 or more" % rows)
	var panel := _hud.find_child("FlightPanel", true, false) as Control
	var rail := _stack.get_global_rect()
	print("PLATE clock=%s rail=%s" % [panel.get_global_rect(), rail])
	_expect(
		is_equal_approx(rail.position.y, panel.get_global_rect().end.y + HudLayout.GROUP_GAP),
		"the rail top %s is not GROUP_GAP under the clock panel" % rail.position.y
	)
	var out := _rail_subjects()
	out["departures list"] = _main.find_child("DeparturesPanel", true, false)
	out["clock panel"] = panel
	return out


func _select_scanner() -> void:
	var scanners: Array = ReferenceTerminal.object_ids(_build.grid)["scanners"]
	if scanners.is_empty():
		_invalid("the starter terminal has no scanner to select")
		return
	var selection: BuiltSelection = _hud._built
	selection.kind = BuiltSelection.Kind.OBJECT
	selection.id = scanners[0]
	await _frames(10)


func _inspect_subjects() -> Dictionary:
	return {"inspect card": _hud.find_child("PassengerInspect", true, false)}


## A screen point over a cell the Seats tool refuses, in the middle of the
## viewport and clear of the bar and tray; -1,-1 when there is none.
func _refused_point() -> Vector2:
	var cam := root.get_camera_3d()
	var view := root.get_visible_rect()
	var frame := view.grow(-160.0)
	var def_id := BuildMode.tool_object(BuildMode.Tool.SEATS)
	var best := Vector2(-1.0, -1.0)
	var best_gap := INF
	for y in range(0, _build.grid.size.y, SAMPLE_STEP):
		for x in range(0, _build.grid.size.x, SAMPLE_STEP):
			var world := _build.grid.cell_to_world(Vector2i(x, y))
			if cam.is_position_behind(world):
				continue
			var at := cam.unproject_position(world)
			var tray_slot_top := view.size.y - BuildMenu.tray_stack_top() - 80.0
			if not frame.has_point(at) or at.y > tray_slot_top:
				continue
			if _build.check(BuildEdit.place_object(def_id, Vector2i(x, y), 0)).ok:
				continue
			var gap := at.distance_to(view.size / 2.0)
			if gap < best_gap:
				best_gap = gap
				best = at
	return best


## Every visible HUD window under the main scene, as {key: [Rect2, Control]}.
func _windows() -> Dictionary:
	var out := {}
	_collect(_main, out)
	return out


func _collect(node: Node, out: Dictionary) -> void:
	if node is SubViewport:
		return
	if node is CanvasLayer and not (node as CanvasLayer).visible:
		return
	var c := node as Control
	if c != null:
		if not c.is_visible_in_tree():
			return
		if _is_window(c):
			var r := c.get_global_rect()
			if r.has_area():
				out[_key(c, out)] = [r, c]
			return
	for child in node.get_children():
		_collect(child, out)


func _is_window(c: Control) -> bool:
	if c is BaseButton:
		return true
	if c is PanelContainer or c is Panel:
		var style := c.get_theme_stylebox("panel")
		return style != null and not style is StyleBoxEmpty
	return false


func _key(c: Control, taken: Dictionary) -> String:
	var offers := _main.get_node("OfferPanel") as OfferPanel
	var runway := _main.get_node("RunwayCard") as RunwayCard
	var key := String(c.name)
	if c == offers.sheet():
		key = "sheet:offers"
	elif c == runway.sheet():
		key = "sheet:runway"
	var at := key
	var n := 2
	while taken.has(at):
		at = "%s#%d" % [key, n]
		n += 1
	return at


## True when one of the pair is a sheet and the other window starts at or below
## the top row's bottom (TOP_ROW_BOTTOM): a sheet may cover the column, the
## rail and the world under the row, never the row itself or the clock panel.
func _allowed(a: String, ra: Rect2, b: String, rb: Rect2) -> bool:
	if SHEETS.has(a) and rb.position.y >= TOP_ROW_BOTTOM - 0.5:
		return true
	return SHEETS.has(b) and ra.position.y >= TOP_ROW_BOTTOM - 0.5


## Checks one state against the grid, prints every rect and saves the plate.
func _state(label: String, tag: String, subjects: Dictionary) -> void:
	await _frames(4)
	var name := "%s_%s" % [label, tag]
	var view := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var windows := _windows()
	print("PLATE %s windows=%d view=%s" % [name, windows.size(), view.size])
	for key in windows:
		print("  RECT %s %s" % [key, windows[key][0]])
	for what in subjects:
		var node := subjects[what] as Control
		if node == null or not node.is_visible_in_tree():
			_invalid("%s: %s is not showing" % [name, what])
			continue
		var r := node.get_global_rect()
		print("  SUBJECT %s %s in_view=%s" % [what, r, view.encloses(r)])
		_expect(view.encloses(r) and r.has_area(), "%s: %s at %s is not in frame" % [name, what, r])
	_overlaps(name, windows)
	_margins(name, windows, view.size)
	var img := root.get_texture().get_image()
	var path := _out_dir.path_join("%s.png" % name)
	var err := img.save_png(path)
	print("PLATE %s saved=%s err=%d size=%s" % [name, path, err, img.get_size()])
	_expect(err == OK, "%s could not be saved" % name)
	_plates.append(path)


func _overlaps(name: String, windows: Dictionary) -> void:
	for miss in _overlap_misses(windows):
		_invalid("%s: %s" % [name, miss])


## Every pair of windows that overlaps by more than half a pixel and that
## _allowed does not excuse, as text.
func _overlap_misses(windows: Dictionary) -> Array[String]:
	var misses: Array[String] = []
	var keys := windows.keys()
	for i in keys.size():
		var a: Rect2 = windows[keys[i]][0]
		for j in range(i + 1, keys.size()):
			var b: Rect2 = windows[keys[j]][0]
			var meet := a.intersection(b)
			if meet.size.x <= 0.5 or meet.size.y <= 0.5:
				continue
			if _allowed(keys[i], a, keys[j], b):
				print("  OVERLAP allowed %s / %s" % [keys[i], keys[j]])
				continue
			misses.append("%s %s overlaps %s %s" % [keys[i], a, keys[j], b])
	return misses


func _margins(name: String, windows: Dictionary, view: Vector2) -> void:
	for miss in _margin_misses(windows, view):
		_invalid("%s: %s" % [name, miss])


## Every window edge nearer a screen edge than MARGIN + UNIT that does not sit
## MARGIN off it, as text.
func _margin_misses(windows: Dictionary, view: Vector2) -> Array[String]:
	var misses: Array[String] = []
	var near := HudLayout.MARGIN + HudLayout.UNIT - 0.5
	for key in windows:
		var r: Rect2 = windows[key][0]
		var gaps := {
			"left": r.position.x,
			"top": r.position.y,
			"right": view.x - r.end.x,
			"bottom": view.y - r.end.y,
		}
		for side in gaps:
			var gap: float = gaps[side]
			if gap < near and absf(gap - HudLayout.MARGIN) > 0.5:
				misses.append("%s %s edge is %.1f off the screen, not MARGIN" % [key, side, gap])
	return misses


## A control: both checks must fire on rects built to fail them, so a clean
## state cannot pass because a check never looks.
func _self_check() -> void:
	var view := Vector2(1536.0, 864.0)
	var bad := {
		"a": [Rect2(16.0, 16.0, 100.0, 40.0), null],
		"b": [Rect2(80.0, 30.0, 100.0, 40.0), null],
		"c": [Rect2(8.0, 400.0, 100.0, 40.0), null],
	}
	var overlaps := _overlap_misses(bad)
	var margins := _margin_misses(bad, view)
	print("PROBE self_check overlaps=%s margins=%s" % [overlaps, margins])
	_expect(overlaps.size() == 1, "self check: the overlap check missed a b")
	_expect(margins.size() == 1, "self check: the margin check missed c at x 8")
	# A sheet over a column card under the row is allowed; a sheet that rises
	# over a top-row button is not.
	var over_column := {
		"sheet:offers": [Rect2(200.0, 64.0, 560.0, 300.0), null],
		"StaffHintCard": [Rect2(16.0, 264.0, 304.0, 120.0), null],
	}
	var over_row := {
		"sheet:runway": [Rect2(600.0, 40.0, 560.0, 300.0), null],
		"OffersButton": [Rect2(864.0, 16.0, 176.0, 40.0), null],
	}
	var column_misses := _overlap_misses(over_column)
	var row_misses := _overlap_misses(over_row)
	print("PROBE self_check sheet_column=%s sheet_row=%s" % [column_misses, row_misses])
	_expect(column_misses.is_empty(), "self check: a sheet over a column card was refused")
	_expect(row_misses.size() == 1, "self check: a sheet over the top row was allowed")


func _contact_sheet(tag: String, paths: Array[String]) -> void:
	var cols := 5
	var rows := ceili(paths.size() / float(cols))
	var sheet := Image.create(THUMB.x * cols, THUMB.y * rows, false, Image.FORMAT_RGBA8)
	for i in paths.size():
		var img := Image.load_from_file(paths[i])
		img.convert(Image.FORMAT_RGBA8)
		img.resize(THUMB.x, THUMB.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(
			img, Rect2i(Vector2i.ZERO, THUMB), Vector2i((i % cols) * THUMB.x, (i / cols) * THUMB.y)
		)
	var path := _out_dir.path_join("contact_%s.png" % tag)
	print("PLATE contact %s err=%d" % [path, sheet.save_png(path)])
