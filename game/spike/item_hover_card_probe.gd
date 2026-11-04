extends SceneTree
## Windowed probe: does the real hover card of a build tray item open above its
## card (board 702a474e, decision build-menu-items-show-a-hover-card-with-a-
## description)? It boots main.tscn, opens the tray of each subject, warps the
## real mouse onto the item card, waits for Godot's own tooltip popup, lets
## frames pass, then reads the popup's final rect and checks, in the space the
## popup is placed in:
##   - the item card is in frame and the pointer is on it (hovered control);
##   - the popup starts at the card's left edge, sits above it and misses it;
##   - the popup lies inside the window;
##   - the popup holds the item's three texts, every label wraps inside the
##     card's text width, and the popup is at least as tall as its content.
## Subjects: a short card, a long-text card and a card at the right of its tray.
## It runs at 1920x1080 and 1280x720 (stretch scale 1.25). A popup that never
## opens is PROBE_INVALID. Plates go to tools/blender/out/hover-card/.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy --path <game dir> \
##     -s res://spike/item_hover_card_probe.gd

const MAIN := "res://main/main.tscn"
const UI_SCALE := 1.25
const WINDOWS: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(1280, 720)]
const SUBJECTS: Array[BuildMode.Tool] = [
	BuildMode.Tool.DESK,
	BuildMode.Tool.CAFE_ROOM,
	BuildMode.Tool.GATE_DESK,
	BuildMode.Tool.PRIZE_PODIUM,
]
const SETTLE_FRAMES := 20
const OPEN_LIMIT_FRAMES := 400
const EDGE_TOLERANCE_PX := 2.0
const HANG_LIMIT_MS := 20000
const TOTAL_LIMIT_MS := 240000

var _guard := Thread.new()
var _mutex := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _done := false
var _failed := false

var _main: Node3D
var _menu: BuildMenu


func _initialize() -> void:
	_beat("boot")
	_guard.start(_watch)
	_run.call_deferred()


func _run() -> void:
	var world_seed := randi()
	print("PROBE world_seed=%d" % world_seed)
	_main = load(MAIN).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(world_seed)
	root.add_child(_main)
	(_main.get_node("SimClock") as SimClock).set_process(false)
	(_main.get_node("TycoonCamera/Camera3D") as Camera3D).make_current()
	_menu = _main.get_node("BuildMenu")
	root.content_scale_factor = UI_SCALE
	for window_size in WINDOWS:
		root.size = window_size
		await _frames(8)
		for tool in SUBJECTS:
			await _hover(window_size, tool)
	print("PROBE_INVALID" if _failed else "PROBE_PASS")
	_finish(1 if _failed else 0)


func _open_tray_of(tool: BuildMode.Tool) -> void:
	for i in BuildMenu.categories().size():
		if BuildMenu.categories()[i]["tools"].has(tool):
			_menu.press_category(i)
			return


func _hover(window_size: Vector2i, tool: BuildMode.Tool) -> void:
	_beat("hover")
	_open_tray_of(tool)
	await _frames(8)
	var card := _menu.card(tool) as ItemCardButton
	if card == null or not card.is_visible_in_tree():
		_fail("no visible card for tool %d" % tool)
		return
	var to_window := root.get_final_transform()
	var visible := root.get_visible_rect()
	var card_r := card.get_global_rect()
	print(
		(
			"PROBE %s window=%s layout=%s card_r=%s"
			% [BuildMenu.item(tool)[0], window_size, visible.size, card_r]
		)
	)
	_expect(visible.grow(-4.0).encloses(card_r), "the item card is not inside the window")
	var target := to_window * card_r.get_center()
	root.warp_mouse(card_r.get_center())
	var shown: Control = null
	for i in OPEN_LIMIT_FRAMES:
		var motion := InputEventMouseMotion.new()
		motion.position = target
		motion.global_position = target
		Input.parse_input_event(motion)
		await _frames(1)
		shown = _open_card(card)
		if shown != null:
			break
	if shown == null:
		_fail("the hover card never opened for %s" % BuildMenu.item(tool)[0])
		return
	await _frames(SETTLE_FRAMES)
	shown = _open_card(card)
	if shown == null:
		_fail("the hover card closed before it could be measured")
		return
	var popup := shown.get_window()
	var popup_r := Rect2(Vector2(popup.position), Vector2(popup.size))
	print("PROBE hovered=%s popup_r=%s" % [root.gui_get_hovered_control(), popup_r])
	_expect(root.gui_get_hovered_control() == card, "the pointer is not on the item card")
	_expect(popup_r.has_area(), "the popup has no area")
	var at_left := absf(popup_r.position.x - card_r.position.x) <= EDGE_TOLERANCE_PX
	var at_window_edge := absf(popup_r.end.x - visible.end.x) <= EDGE_TOLERANCE_PX
	print("PROBE at_left=%s kept_in_by_window_edge=%s" % [at_left, at_window_edge])
	_expect(at_left or at_window_edge, "the popup is not at the card's left edge")
	_expect(popup_r.end.y <= card_r.position.y, "the popup is not above the card")
	_expect(not popup_r.intersects(card_r), "the popup covers the item card")
	_expect(visible.encloses(popup_r), "the popup is not inside the window")
	_check_text(shown, ItemInfo.of(tool), BuildMenu.item(tool)[0])
	_save_plate(window_size, BuildMenu.item(tool)[1])
	root.warp_mouse(visible.size * 0.5)
	await _frames(12)


## The labels hold the name and the three texts, each wraps inside the text
## width, and the box is tall enough for its content (nothing clipped).
func _check_text(box: Control, info: Array, item_name: String) -> void:
	var texts := []
	for label in box.find_children("*", "Label", true, false):
		var l := label as Label
		texts.append(l.text)
		var lines := l.get_line_count()
		print("PROBE   label lines=%d size=%s text=%s" % [lines, l.size, l.text.left(40)])
		_expect(
			l.size.x <= ItemCardButton.CARD_TEXT_W + 1.0, "a label is wider than the text width"
		)
		_expect(l.size.y + 1.0 >= l.get_minimum_size().y, "a label is shorter than its text")
	_expect(texts.has(item_name) and texts.has(info[0]), "the name or the about text is missing")
	_expect(texts.has(info[1]) and texts.has(info[2]), "the how or needs text is missing")
	var window_h := float(box.get_window().size.y)
	print("PROBE   box min_h=%.1f popup_h=%.1f" % [box.get_combined_minimum_size().y, window_h])
	_expect(window_h + 1.0 >= box.get_combined_minimum_size().y, "the popup clips its content")


## The card while it is shown in a tooltip popup window, or null.
func _open_card(item_card: ItemCardButton) -> Control:
	var shown: Control = item_card._card
	if not is_instance_valid(shown) or not shown.is_inside_tree():
		return null
	var popup := shown.get_window()
	if popup == null or popup == root or not popup.visible:
		return null
	return shown


func _save_plate(window_size: Vector2i, thumb: String) -> void:
	var dir := ProjectSettings.globalize_path("res://../tools/blender/out/hover-card")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := "%s/%s-%dx%d.png" % [dir, thumb, window_size.x, window_size.y]
	var err := root.get_texture().get_image().save_png(path)
	print("PROBE plate=%s err=%d" % [path, err])


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
			OS.crash("item hover card probe hung")
