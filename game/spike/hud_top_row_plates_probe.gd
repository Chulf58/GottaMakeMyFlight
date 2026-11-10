extends SceneTree
## Windowed plate probe for HUD 2/7 (the top row) on the real main.tscn at
## 1920x1080 (layout 1536x864):
##   a_start    a new game outside build mode: the sign slot is empty
##   b_build    build mode: the Build mode sign shows
##   c_offers   the Offers sheet open
##   d_runway   the Runway sheet open (Offers closes)
## Before each save it prints every top-row rect and proves: all five windows
## are 40 px tall with their top on 16, no two overlap, the sign shows only in
## build mode, the rating reads "No flights yet", and an open sheet is under the
## row, 560 wide and left of the clock panel. Otherwise PROBE_INVALID, exit 1.
## A guard thread crashes past LIMIT_MS.
##
## Run (one windowed Godot run project-wide):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/.claude/worktrees/<lane>/game \
##     -s res://spike/hud_top_row_plates_probe.gd

const OUT_REL := "res://../tools/blender/out/hud-2-top"
const LIMIT_MS := 120000
const WINDOW := Vector2i(1920, 1080)
## The top band cropped beside each full plate, in window px.
const CROP := Rect2i(0, 0, 1920, 420)

var _out_dir := ""
var _failed := false
var _start_ms := 0
var _guard := Thread.new()
var _lock := Mutex.new()
var _stop := false
var _main: Node3D
var _menu: BuildMenu
var _hud: PassengerHud
var _badge: RatingBadge
var _runway: RunwayCard
var _offers: OfferPanel


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
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
			OS.crash("hud_top_row_plates_probe: no finish within %d ms" % LIMIT_MS)


func _finish() -> void:
	_lock.lock()
	_stop = true
	_lock.unlock()
	_guard.wait_to_finish()


func _run() -> void:
	var world_seed := randi()
	print("PROBE world_seed=%d" % world_seed)
	DisplayServer.window_set_size(WINDOW)
	await _frames(5)
	if root.size != WINDOW:
		_invalid("the window is %s, not %s" % [root.size, WINDOW])
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(world_seed)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	root.add_child(_main)
	_menu = _main.get_node("BuildMenu") as BuildMenu
	_hud = _main.get_node("PassengerHud") as PassengerHud
	_badge = _main.get_node("RatingBadge") as RatingBadge
	_runway = _main.get_node("RunwayCard") as RunwayCard
	_offers = _main.get_node("OfferPanel") as OfferPanel
	root.warp_mouse(Vector2(WINDOW.x / 2.0, WINDOW.y - 4.0))
	await _frames(8)
	print("PROBE layout=%s" % root.get_visible_rect().size)
	await _state("a_start", false, "")
	_menu.press_category(0)
	await _state("b_build", true, "")
	_offers.open()
	await _state("c_offers", true, "offers")
	_runway.open()
	_expect(not _offers.is_open(), "d: the Offers sheet stayed open under Runway")
	await _state("d_runway", true, "runway")
	print("PROBE done failed=%s" % _failed)
	_finish()
	quit(1 if _failed else 0)


func _rects() -> Dictionary:
	return {
		"money": (_menu.find_child("MoneySlot", true, false) as Control).get_global_rect(),
		"rating": _badge.card().get_global_rect(),
		"sign": _menu.build_frame.sign_panel().get_global_rect(),
		"runway": _runway.toggle_button().get_global_rect(),
		"offers": _offers.toggle_button().get_global_rect(),
		"clock": (_hud.find_child("FlightPanel", true, false) as Control).get_global_rect(),
	}


func _state(label: String, building: bool, sheet: String) -> void:
	await _frames(4)
	print("PLATE %s" % label)
	var rects := _rects()
	for key in rects:
		print("  RECT %s %s" % [key, rects[key]])
	var sign_node := _menu.build_frame.sign_panel()
	_expect(
		sign_node.is_visible_in_tree() == building,
		"%s: sign visible=%s, wanted %s" % [label, sign_node.is_visible_in_tree(), building]
	)
	var text := (_badge.card().find_child("RatingText", true, false) as Label).text
	print("  TEXT rating='%s'" % text)
	_expect(text == "No flights yet", "%s: rating label is '%s'" % [label, text])
	var view := root.get_visible_rect()
	var names := ["money", "rating", "runway", "offers"]
	if building:
		names.append("sign")
	for key in names:
		var rect: Rect2 = rects[key]
		_expect(is_equal_approx(rect.size.y, 40.0), "%s: %s is %s tall" % [label, key, rect.size.y])
		_expect(
			is_equal_approx(rect.position.y, 16.0),
			"%s: %s top is %s" % [label, key, rect.position.y]
		)
		_expect(
			Rect2(Vector2.ZERO, view.size / 1.25).encloses(rect), "%s: %s outside" % [label, key]
		)
	names.append("clock")
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: Rect2 = rects[names[i]]
			var b: Rect2 = rects[names[j]]
			if a.intersects(b):
				_invalid("%s: %s overlaps %s" % [label, names[i], names[j]])
	if sheet != "":
		var sheet_node: Control = (_offers if sheet == "offers" else _runway).sheet()
		var sheet_rect := sheet_node.get_global_rect()
		var button: Rect2 = rects[sheet]
		print("  RECT sheet %s" % sheet_rect)
		_expect(
			is_equal_approx(sheet_rect.size.x, 560.0),
			"%s: sheet is %s wide" % [label, sheet_rect.size.x]
		)
		_expect(sheet_rect.position.y >= button.end.y, "%s: sheet not under the row" % label)
		_expect(
			sheet_rect.end.x < (rects["clock"] as Rect2).position.x,
			"%s: sheet reaches the clock" % label
		)
	await _save(label)


func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := _out_dir.path_join(label + ".png")
	var err := image.save_png(path)
	print("PLATE saved %s err=%d" % [path, err])
	if err != OK:
		_invalid("%s: the plate was not saved (error %d)" % [label, err])
	var crop := image.get_region(CROP)
	var crop_path := _out_dir.path_join(label + "_top.png")
	_expect(crop.save_png(crop_path) == OK, "%s: crop not saved" % label)
	print("PLATE saved %s" % crop_path)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_invalid(message)


func _invalid(message: String) -> void:
	print("PROBE_INVALID: ", message)
	_failed = true
