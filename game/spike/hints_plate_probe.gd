extends SceneTree
## Windowed plates of the first-time hints (HUD 7/7, decision first-time-hints-
## above-the-build-bar-moment-of-need-per-profile-memory). Boots main.tscn with
## the explicit hints switch, so the mounted Hints run in ISOLATED mode with a
## memory file of their own. Hints' world reading is switched off (reads_world)
## and the probe drives advance() with explicit worlds, so every plate is
## deterministic.
##
## Plate A: the check-in hint with the Check-in tray open, docked above the tray
##   stack, the status banner gone from the slot.
## Plate B: the toilet hint with no tray open, docked just above the bar.
## Plate C: hints turned off with H's toggle: no card, the banner back, the
##   settings row (Hints (H), Reset hints) visible.
## Plate D: the build ghost over the hint, which fades to FADED_ALPHA.
## Every plate prints the rects and values it compared and proves the card, and
## on plate D the ghost, are inside the viewport by MARGIN_PX and that the card
## overlaps no other drawn HUD rectangle. Otherwise PROBE_INVALID, exit 1.
##
## Run (one windowed Godot run project-wide; take the slot first). The user
## arguments after "--" matter: --hints switches the hints on for this run.
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/hints_plate_probe.gd -- --hints [--out=<dir>]
##
## Plates go to tools/blender/out/hud-hints/ unless --out names a directory.

const OUT_REL := "res://../tools/blender/out/hud-hints"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const SETTLE_FRAMES := 40
const PROBE_STEP_PX := 96.0
const ALPHA_EPS := 0.02

var _out_dir := ""
var _failed := false
var _main: Node3D
var _hud: PassengerHud
var _hints: Hints
var _build: BuildMode
var _menu: BuildMenu
var _staff: StaffPanel
var _cam: Camera3D


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var world_seed := randi()
	seed(world_seed)
	print("PROBE seed=%d out_dir=%s" % [world_seed, _out_dir])
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _category(category_name: String) -> int:
	for i in BuildMenu.CATEGORIES.size():
		if BuildMenu.CATEGORIES[i]["name"] == category_name:
			return i
	return BuildMenu.NO_CATEGORY


## The real world with `over` merged in.
func _world(over := {}) -> Dictionary:
	var world := HintRules.read_world(_hud.sim, _staff.hiring_hint_roles())
	world.merge(over, true)
	return world


## Drives the hints for `seconds` of real time, the way _process would.
func _drive(seconds: float, world: Dictionary, open: Array) -> void:
	var left := seconds
	while left > 0.0:
		var step := minf(0.25, left)
		_hints.advance(step, world, open)
		left -= step


func _run() -> void:
	_main = load(MAIN_SCENE).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(randi())
	root.add_child(_main)
	_cam = _main.get_node("TycoonCamera/Camera3D")
	_build = _main.get_node("BuildMode")
	_menu = _main.get_node("BuildMenu")
	_staff = _main.get_node("StaffPanel")
	_hud = _main.get_node("PassengerHud")
	await _frames(30)
	_hints = _hud.find_child("Hints", false, false) as Hints
	if _hints == null or _hints.mode() != Hints.Mode.ISOLATED:
		_invalid("the mounted Hints are not in ISOLATED mode; run with -- --hints")
		_finish()
		return
	print("PROBE memory=%s row_visible=%s" % [_hints.memory_path(), _hints.settings_row().visible])
	_hints.reads_world = false
	_hints.reset_session()
	_hints.advance(Hints.GRACE_S + 0.1, _world(), [])

	# Plate A: Check-in tray open, the check-in hint.
	_menu.press_category(_category("Check-in"))
	await _frames(5)
	_drive(Hints.GRACE_S, _world(), ["Check-in"])
	await _frames(SETTLE_FRAMES)
	await _plate("hint_checkin_over_tray.png", HintRules.PLACE_CHECKIN)

	# Plate B: no tray, the toilet hint (a needy passenger and no stall).
	_hints.reset_seen()
	_menu.press_category(_category("Check-in"))
	await _frames(5)
	_hints.reset_session()
	_hints.advance(Hints.GRACE_S + 0.1, _world(), [])
	_drive(HintRules.HOLD_S + 0.5, _world({"desks": 1, "scanners": 1}), [])
	_drive(
		HintRules.HOLD_S + 0.5,
		_world({"desks": 1, "scanners": 1, "stalls": 0, "max_toilet_need": 99}),
		[]
	)
	await _frames(SETTLE_FRAMES)
	await _plate("hint_toilet_over_bar.png", HintRules.TOILET)

	# Plate D: the ghost over the hint (needs a tool armed), then plate C.
	var card := _hints.card()
	_menu.press_category(_category("Gates"))
	_menu.press_card(BuildMode.Tool.GATE_DESK)
	await _frames(10)
	var overlap_at := await _find_pointer(card)
	if overlap_at.x < 0.0:
		_invalid("no pointer found whose ghost overlaps the hint")
	else:
		_build.pointer_override = overlap_at
		await _frames(SETTLE_FRAMES)
		await _plate("hint_faded_under_ghost.png", HintRules.TOILET, true)
	_build.pointer_override = Vector2(-1.0, -1.0)
	_hints.set_enabled(false)
	await _frames(SETTLE_FRAMES)
	await _plate_off("hints_off_banner_back.png")
	_finish()


## The screen point (a grid over the viewport) whose ghost rect overlaps the hint
## card the most. Vector2(-1, -1) when none.
func _find_pointer(card: Control) -> Vector2:
	var frame := root.get_visible_rect().grow(-MARGIN_PX * 4.0)
	var best := Vector2(-1.0, -1.0)
	var best_area := 0.0
	# The ghost follows the pointer, so points at the card itself come first; the
	# grid scan below is the fallback and is coarse to stay inside the time limit.
	var centre := card.get_global_rect().get_center()
	for offset: Vector2 in [Vector2.ZERO, Vector2(0, -80), Vector2(0, -160), Vector2(160, 0)]:
		var at := centre + offset
		if _menu.bar().get_global_rect().has_point(at):
			continue
		_build.pointer_override = at
		await _frames(3)
		var ghost := GhostBounds.build_rect(_build, _cam)
		var shared := ghost.intersection(card.get_global_rect())
		if ghost.has_area() and frame.encloses(ghost) and shared.has_area():
			print("FOUND at=%s overlap_px=%.0f (near the card)" % [at, shared.get_area()])
			return at
	var y := frame.end.y
	while y > frame.position.y:
		var x := frame.position.x
		while x < frame.end.x:
			var at := Vector2(x, y)
			if not _menu.bar().get_global_rect().has_point(at):
				_build.pointer_override = at
				await _frames(3)
				var ghost := GhostBounds.build_rect(_build, _cam)
				if ghost.has_area() and frame.encloses(ghost):
					var shared := ghost.intersection(card.get_global_rect())
					var area := shared.get_area() if shared.has_area() else 0.0
					if area > best_area:
						best = at
						best_area = area
			x += PROBE_STEP_PX
		y -= PROBE_STEP_PX
	print("FOUND at=%s overlap_px=%.0f" % [best, best_area])
	return best


func _plate(file: String, id: StringName, expect_faded := false) -> void:
	var card := _hints.card()
	var screen := root.get_visible_rect().grow(-MARGIN_PX)
	var rect := card.get_global_rect()
	var banner := _staff.hint_card()
	var alpha := card.modulate.a
	print(
		(
			"PLATE %s shown=%s text='%s' card=%s alpha=%.3f banner_visible=%s top=%.1f"
			% [
				file,
				_hints.shown_id(),
				_hints.body_label().text,
				rect,
				alpha,
				banner.visible,
				StaffPanel.BANNER_TOP
			]
		)
	)
	if _hints.shown_id() != id or not card.is_visible_in_tree():
		_invalid("%s: hint '%s' is not showing" % [file, id])
	if banner.visible:
		_invalid("%s: the banner still stands in the hint's slot" % file)
	var inside := screen.has_point(rect.position) and screen.has_point(rect.end)
	print("INFRAME card rect=%s in=%s" % [rect, inside])
	if not inside:
		_invalid("%s: the card is outside the viewport frame" % file)
	for other in HudRects.collect(_hints, 1.0):
		if other.encloses(rect) or rect.encloses(other):
			continue
		if other.intersects(rect):
			print("OVERLAP other=%s" % other)
			_invalid("%s: the card overlaps another HUD rectangle %s" % [file, other])
	var target := StaffPanel.FADED_ALPHA if expect_faded else 1.0
	if absf(alpha - target) > ALPHA_EPS:
		_invalid("%s: card alpha %.3f, expected %.2f" % [file, alpha, target])
	_save(file)


func _plate_off(file: String) -> void:
	var row := _hints.settings_row().get_global_rect()
	print(
		(
			"PLATE %s card_visible=%s banner_visible=%s banner_text='%s' row=%s"
			% [
				file,
				_hints.card().visible,
				_staff.hint_card().visible,
				_staff.hint_label().text,
				row
			]
		)
	)
	if _hints.card().visible:
		_invalid("%s: the card still shows with hints off" % file)
	if not _staff.hint_card().visible:
		_invalid("%s: the banner did not come back" % file)
	var screen := root.get_visible_rect().grow(-MARGIN_PX)
	if not (_hints.settings_row().is_visible_in_tree() and screen.encloses(row)):
		_invalid("%s: the settings row is not inside the frame" % file)
	_save(file)


func _save(file: String) -> void:
	if _failed:
		return
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save " + path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _finish() -> void:
	DirAccess.remove_absolute(Hints.ISOLATED_PATH)
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)
