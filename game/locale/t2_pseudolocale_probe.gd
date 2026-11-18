extends SceneTree
## Windowed plates of a refused build ghost with pseudolocalization on
## (PseudoLocale, expansion 0.4, auto-translate off so a routed string is
## bracketed once). The real main.tscn boots, the Gates tray's Gate desk tool is
## picked and the pointer goes over refused grid cells in turn. Two cells are
## plated: the one whose ghost card (GhostReason) holds the longest line, and
## the one whose status line holds the longest full refusal. Before each save it
## proves its subject: the cell, the ghost's bounds and the card lie inside the
## viewport by MARGIN_PX, the card is visible, the pointer is not over the HUD,
## and both the card and the status line start with "[" (so the text was routed).
## Otherwise it prints PROBE_INVALID and exits 1. It prints the card's text
## width against its room and whether the status line is cut short.
##
## Run (windowed takes the one project-wide slot):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy --path <worktree>/game \
##     -s res://locale/t2_pseudolocale_probe.gd
## The plates go to tools/blender/out/locale/t2/.

const OUT_REL := "res://../tools/blender/out/locale/t2"
const MAIN_SCENE := "res://main/main.tscn"
const WINDOW := Vector2i(1920, 1080)
const MARGIN_PX := 8.0
const SETTLE_FRAMES := 6
const SAMPLE_STEP := 3
const MAX_CANDIDATES := 60
const LIMIT_MS := 180000

var _out_dir := ""
var _failed := false
var _start_ms := 0
var _guard := Thread.new()
var _lock := Mutex.new()
var _stop := false
var _main: Node3D
var _build: BuildMode
var _menu: BuildMenu
var _cam: Camera3D


func _initialize() -> void:
	_start_ms = Time.get_ticks_msec()
	_guard.start(_watch)
	_run.call_deferred()


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_lock.lock()
		var stop := _stop
		_lock.unlock()
		if stop:
			return
		if Time.get_ticks_msec() - _start_ms > LIMIT_MS:
			print("PROBE_INVALID: the probe ran past %d ms" % LIMIT_MS)
			OS.crash("t2_pseudolocale_probe: no finish within %d ms" % LIMIT_MS)


func _finish() -> void:
	_lock.lock()
	_stop = true
	_lock.unlock()
	_guard.wait_to_finish()
	PseudoLocale.disable()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _invalid(why: String) -> void:
	print("PROBE_INVALID: ", why)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	var world_seed := randi()
	print("PROBE world_seed=%d display=%s" % [world_seed, DisplayServer.get_name()])
	if DisplayServer.get_name() == "headless":
		_invalid("run it windowed")
		_finish()
		return
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_size(WINDOW)
	await _frames(5)
	root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	PseudoLocale.enable()
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(world_seed)
	root.add_child(_main)
	_cam = _main.get_node("TycoonCamera/Camera3D")
	_build = _main.get_node("BuildMode")
	_menu = _main.get_node("BuildMenu")
	await _frames(30)
	var gates := -1
	for i in BuildMenu.CATEGORIES.size():
		if BuildMenu.CATEGORIES[i]["name"] == "Gates":
			gates = i
	if gates < 0:
		_invalid("no Gates category")
		_finish()
		return
	_menu.press_category(gates)
	_menu.press_card(BuildMode.Tool.GATE_DESK)
	await _frames(10)
	var screen := root.get_visible_rect()
	var candidates := _refused_cells(screen)
	print("PROBE refused on-screen candidates=%d" % candidates.size())
	var longest_card := {}
	var longest_status := {}
	var reasons := {}
	for at: Vector2 in candidates:
		_build.pointer_override = at
		await _frames(SETTLE_FRAMES)
		var card := _menu.ghost_reason()
		if not card.visible or not screen.grow(-MARGIN_PX).encloses(card.ghost_rect()):
			continue
		var entry := {"at": at, "card": card.text(), "status": _build.status_text()}
		reasons[card.text()] = true
		if longest_card.is_empty() or card.text().length() > longest_card["card"].length():
			longest_card = entry
		if (
			longest_status.is_empty()
			or entry["status"].length() > longest_status["status"].length()
		):
			longest_status = entry
	print("PROBE distinct card texts=%d: %s" % [reasons.size(), reasons.keys()])
	if longest_card.is_empty():
		_invalid("no refused cell showed the reason card")
		_finish()
		return
	await _plate("a_refused_ghost_longest_card", longest_card, screen)
	await _plate("b_refused_ghost_longest_status", longest_status, screen)
	_finish()


func _plate(plate: String, entry: Dictionary, screen: Rect2) -> void:
	var at: Vector2 = entry["at"]
	_build.pointer_override = at
	await _frames(SETTLE_FRAMES + 4)
	var card := _menu.ghost_reason()
	var frame := screen.grow(-MARGIN_PX)
	var ghost := card.ghost_rect()
	var label := card.find_child("ReasonText", true, false) as Label
	print(
		(
			"PLATE %s at=%s card='%s' card_rect=%s ghost_rect=%s status='%s'"
			% [plate, at, card.text(), card.get_global_rect(), ghost, _build.status_text()]
		)
	)
	_expect(frame.has_point(at), "%s: the pointer is outside the viewport" % plate)
	_expect(not _under_hud(at), "%s: the pointer is over the HUD" % plate)
	_expect(card.visible, "%s: the reason card is hidden" % plate)
	_expect(ghost.has_area() and frame.encloses(ghost), "%s: the ghost is not in frame" % plate)
	_expect(frame.encloses(card.get_global_rect()), "%s: the card is outside the viewport" % plate)
	_expect(card.text().begins_with("["), "%s: the card text is not bracketed" % plate)
	_expect(_build.status_text().begins_with("["), "%s: the status line is not bracketed" % plate)
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var wide := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	print("PLATE %s card text width=%.0f label width=%.0f" % [plate, wide, label.size.x])
	_expect(wide <= label.size.x + 0.5, "%s: the card text is wider than its label" % plate)
	var status := _menu.status_label()
	var status_wide := (
		status
		. get_theme_font("font")
		. get_string_size(
			status.text, HORIZONTAL_ALIGNMENT_LEFT, -1, status.get_theme_font_size("font_size")
		)
		. x
	)
	print(
		(
			"PLATE %s status text width=%.0f label width=%.0f cut_short=%s"
			% [plate, status_wide, status.size.x, status_wide > status.size.x + 0.5]
		)
	)
	await RenderingServer.frame_post_draw
	var path := _out_dir.path_join(plate + ".png")
	var err := root.get_texture().get_image().save_png(path)
	print("PLATE saved %s err=%d" % [path, err])
	_expect(err == OK, "the plate %s was not saved" % plate)


## Screen points over cells the Gate desk tool refuses, one per SAMPLE_STEP
## cells, kept to the ones in the viewport and clear of the bar and tray, the
## MAX_CANDIDATES nearest the middle of the window.
func _refused_cells(screen: Rect2) -> Array[Vector2]:
	var frame := screen.grow(-MARGIN_PX)
	var all: Array[Vector2] = []
	var def_id := BuildMode.tool_object(BuildMode.Tool.GATE_DESK)
	for y in range(0, _build.grid.size.y, SAMPLE_STEP):
		for x in range(0, _build.grid.size.x, SAMPLE_STEP):
			var cell := Vector2i(x, y)
			var world := _build.grid.cell_to_world(cell)
			if _cam.is_position_behind(world):
				continue
			var at := _cam.unproject_position(world)
			if not frame.has_point(at) or _under_hud(at):
				continue
			if not _build.check(BuildEdit.place_object(def_id, cell, 0)).ok:
				all.append(at)
	var centre := screen.get_center()
	all.sort_custom(
		func(a: Vector2, b: Vector2) -> bool: return a.distance_to(centre) < b.distance_to(centre)
	)
	return all.slice(0, MAX_CANDIDATES)


func _under_hud(at: Vector2) -> bool:
	if _menu.bar().get_global_rect().has_point(at):
		return true
	return _menu.is_tray_open() and _menu.tray().get_global_rect().has_point(at)


func _expect(condition: bool, why: String) -> void:
	if not condition:
		_invalid(why)
