extends SceneTree
## Windowed probe: where does the real money hover card open (smoke playtest 5
## note e)? It boots main.tscn, warps the real mouse onto the Money slot, waits
## for Godot's own tooltip popup to open, lets several frames pass, then reads
## the popup's final window rect and checks, in window pixels:
##   - it starts at the slot's left edge and sits below the slot;
##   - it misses the "Money N" figure and the rating stars card;
##   - it lies inside the window.
## It runs at a 1920x1080 window, where the stretch (canvas_items, scale 1.25)
## gives a 1536x864 layout, and at 1280x720 for a second layout. A popup that
## never opens, or opens empty, is PROBE_INVALID: every pass value compares
## printed numbers, and the popup is read from the slot's own card.
##
## Window pixels are the viewport point through Window.get_final_transform,
## plus the window's screen position when popups are native windows
## (gui_embed_subwindows false), which is how Godot places them.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/money_hover_placement_probe.gd

const MAIN := "res://main/main.tscn"
const UI_SCALE := 1.25
const WINDOWS: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(1280, 720)]
## Frames to let pass after the card opens, so a late reposition would show.
const SETTLE_FRAMES := 20
const OPEN_LIMIT_FRAMES := 400
const EDGE_TOLERANCE_PX := 2.0
const HANG_LIMIT_MS := 20000
const TOTAL_LIMIT_MS := 120000

var _guard := Thread.new()
var _mutex := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _done := false
var _failed := false

var _main: Node3D
var _slot: MoneySlot
var _menu: BuildMenu
var _badge: RatingBadge


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
	_badge = _main.get_node("RatingBadge")
	_slot = _menu.money_label().get_parent() as MoneySlot
	if _slot == null or _slot.ledger == null:
		_fail("the money slot has no ledger, so it has no card")
		return
	root.content_scale_factor = UI_SCALE
	for window_size in WINDOWS:
		await _at_window(window_size)
	print("PROBE_INVALID" if _failed else "PROBE_PASS")
	_finish(1 if _failed else 0)


func _at_window(window_size: Vector2i) -> void:
	_beat("window")
	root.size = window_size
	await _frames(8)
	print(
		(
			"PROBE window=%s root.size=%s layout=%s scale=%.2f embed=%s root.position=%s"
			% [
				window_size,
				root.size,
				root.get_visible_rect().size,
				root.content_scale_factor,
				root.gui_embed_subwindows,
				root.position,
			]
		)
	)
	_expect(root.size == window_size, "the window is %s, not %s" % [root.size, window_size])
	var to_window := root.get_final_transform()
	var offset := Vector2.ZERO if root.gui_embed_subwindows else Vector2(root.position)
	var slot_px := _px(_slot.get_global_rect(), to_window, offset)
	var money_px := _px(_menu.money_label().get_global_rect(), to_window, offset)
	var stars_px := _px(_badge.card().get_global_rect(), to_window, offset)
	var inside := Rect2(offset, Vector2(root.size))
	# The pointer goes onto the slot's middle; the tooltip opens after Godot's
	# own delay, so motion is sent until the card is in the tree.
	var target := slot_px.get_center() - offset
	_beat("hover")
	root.warp_mouse(root.get_final_transform().affine_inverse() * target)
	var card: Control = null
	for i in OPEN_LIMIT_FRAMES:
		var motion := InputEventMouseMotion.new()
		motion.position = target
		motion.global_position = target
		Input.parse_input_event(motion)
		await _frames(1)
		card = _open_card()
		if card != null:
			break
	if card == null:
		_fail("the tooltip card never opened after %d frames" % OPEN_LIMIT_FRAMES)
		return
	await _frames(SETTLE_FRAMES)
	card = _open_card()
	if card == null:
		_fail("the tooltip card closed before it could be measured")
		return
	var popup := card.get_window()
	var popup_px := Rect2(Vector2(popup.position), Vector2(popup.size))
	print("PROBE hovered=%s" % [root.gui_get_hovered_control()])
	print("PROBE slot_px=%s money_px=%s stars_px=%s" % [slot_px, money_px, stars_px])
	print("PROBE popup_px=%s window_rect=%s" % [popup_px, inside])
	print(
		(
			"PROBE popup.x=%.1f slot.x=%.1f popup.y=%.1f slot.bottom=%.1f"
			% [popup_px.position.x, slot_px.position.x, popup_px.position.y, slot_px.end.y]
		)
	)
	_expect(popup_px.has_area(), "the popup has no area")
	_expect(
		absf(popup_px.position.x - slot_px.position.x) <= EDGE_TOLERANCE_PX,
		"the popup does not start at the slot's left edge"
	)
	_expect(popup_px.position.y >= slot_px.end.y, "the popup is not below the slot")
	_expect(not popup_px.intersects(money_px), "the popup covers the Money figure")
	_expect(not popup_px.intersects(stars_px), "the popup covers the rating stars")
	_expect(inside.encloses(popup_px), "the popup is not inside the window")
	var away := Vector2(root.size) * 0.55
	root.warp_mouse(away / to_window.get_scale())
	await _frames(8)


## The slot's card while it is shown in a popup window, or null.
func _open_card() -> Control:
	var card: Control = _slot._card
	if not is_instance_valid(card) or not card.is_inside_tree():
		return null
	var popup := card.get_window()
	if popup == null or popup == root or not popup.visible:
		return null
	return card


## A viewport rect in window pixels (plus the window's screen offset).
func _px(rect: Rect2, to_window: Transform2D, offset: Vector2) -> Rect2:
	return Rect2(to_window * rect.position + offset, rect.size * to_window.get_scale())


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
			OS.crash("money hover placement probe hung")
