extends SceneTree
## Windowed plates of the status banner fade (StaffHintCard, StaffPanel.fade_for),
## board 9c2b0d32 part 1. Boots main.tscn with the starter shell, picks the Gates
## tray's Gate desk tool and moves the pointer (BuildMode.pointer_override) over
## screen points near the "Airport closed" banner. Plate A: the build ghost's
## screen rect overlaps the banner, whose alpha settles at FADED_ALPHA. Plate B:
## the ghost is clear of the banner, alpha back at 1.0. Every plate prints the
## ghost rect, the banner rect and the alpha it compared, and proves the banner
## and the ghost are inside the viewport by MARGIN_PX. Otherwise PROBE_INVALID,
## exit 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/banner_fade_plate_probe.gd [-- --out=<dir>]
##
## Plates go to tools/blender/out/hud-overlaps/ unless --out names a directory.

const OUT_REL := "res://../tools/blender/out/hud-overlaps"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const SETTLE_FRAMES := 40
const PROBE_STEP_PX := 24.0
const ALPHA_EPS := 0.02

var _out_dir := ""
var _failed := false
var _main: Node3D
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


func _run() -> void:
	_main = load(MAIN_SCENE).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(randi())
	root.add_child(_main)
	_cam = _main.get_node("TycoonCamera/Camera3D")
	_build = _main.get_node("BuildMode")
	_menu = _main.get_node("BuildMenu")
	_staff = _main.get_node("StaffPanel")
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
	var card := _staff.hint_card()
	print(
		(
			"PROBE hint='%s' visible=%s card_rect=%s alpha=%.2f"
			% [
				_staff.hint_label().text,
				card.is_visible_in_tree(),
				card.get_global_rect(),
				card.modulate.a
			]
		)
	)
	if not card.is_visible_in_tree():
		_invalid("the banner is not visible")
		_finish()
		return
	var overlap_at := await _find_pointer(card, true)
	var clear_at := await _find_pointer(card, false)
	if overlap_at.x < 0.0 or clear_at.x < 0.0:
		_invalid("no pointer found: overlap=%s clear=%s" % [overlap_at, clear_at])
		_finish()
		return
	await _plate("banner_faded_under_ghost.png", overlap_at, card, true)
	await _plate("banner_full_ghost_clear.png", clear_at, card, false)
	_finish()


## The screen point (a grid over the viewport) whose ghost rect overlaps the
## banner the most (`covers`), or the first one clear of it and its 60 px
## surround. Vector2(-1, -1) when none.
func _find_pointer(card: Control, covers: bool) -> Vector2:
	var screen := root.get_visible_rect()
	var frame := screen.grow(-MARGIN_PX * 4.0)
	var best := Vector2(-1.0, -1.0)
	var best_area := 0.0
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
					if covers and area > best_area:
						best = at
						best_area = area
					elif not covers and not card.get_global_rect().grow(60.0).intersects(ghost):
						print("FOUND covers=false at=%s ghost=%s" % [at, ghost])
						return at
			x += PROBE_STEP_PX
		y -= PROBE_STEP_PX
	if covers:
		print("FOUND covers=true at=%s overlap_px=%.0f" % [best, best_area])
	return best


func _plate(file: String, at: Vector2, card: Control, expect_faded: bool) -> void:
	_build.pointer_override = at
	await _frames(SETTLE_FRAMES)
	var screen := root.get_visible_rect().grow(-MARGIN_PX)
	var ghost := GhostBounds.build_rect(_build, _cam)
	var rect := card.get_global_rect()
	var alpha := card.modulate.a
	var target := StaffPanel.FADED_ALPHA if expect_faded else 1.0
	var overlap := ghost.intersection(rect)
	print(
		(
			"PLATE %s ghost=%s card=%s overlap_px=%.0f alpha=%.3f expected=%.2f"
			% [file, ghost, rect, overlap.get_area() if overlap.has_area() else 0.0, alpha, target]
		)
	)
	for pair: Array in [["ghost", ghost], ["banner", rect]]:
		var r: Rect2 = pair[1]
		var inside := screen.has_point(r.position) and screen.has_point(r.end)
		print("INFRAME %s rect=%s in=%s" % [pair[0], r, inside])
		if not inside:
			_invalid("%s is outside the viewport frame" % pair[0])
	if absf(alpha - target) > ALPHA_EPS:
		_invalid("banner alpha %.3f, expected %.2f" % [alpha, target])
	if expect_faded and not overlap.has_area():
		_invalid("ghost does not overlap the banner")
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
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)
