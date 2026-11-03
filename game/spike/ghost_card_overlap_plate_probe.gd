extends SceneTree
## Windowed plate of the build ghost's refusal card (GhostReason) against the
## "Airport closed" hint card (StaffPanel), board 9afe06b6 part 1. Boots
## main.tscn with the starter shell, picks the Gates tray's Gate desk tool, and
## puts the pointer over refused grid cells in turn; on each the probe prints the
## reason card's rect, the hint card's rect, the pixels they share and the gap
## between them, then a count of cards shown and cards that overlapped. The
## cell whose cards overlap most is plated; when none overlaps, the cell whose
## card sits nearest the hint card is plated, so the plate says so either way.
## Proof before the save: the cell, the reason card and the hint card are inside
## the viewport by MARGIN_PX, the reason card is visible, and the pointer is not
## over the HUD. Otherwise PROBE_INVALID, exit 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/ghost_card_overlap_plate_probe.gd [-- --out=<dir>]
##
## Plates go to tools/blender/out/plates-1102/ unless --out names a directory.

const OUT_REL := "res://../tools/blender/out/plates-1102"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const SETTLE_FRAMES := 6
const SAMPLE_STEP := 3
const MAX_CANDIDATES := 60

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
	var screen := root.get_visible_rect()
	var hint := _staff.hint_label()
	var hint_card := (hint.get_parent() as Control) if hint.get_parent() is Control else hint
	print(
		(
			"PROBE tool=%d tray_open=%s hint_visible=%s hint=%s hint_rect=%s"
			% [
				_build.tool,
				_menu.is_tray_open(),
				hint.is_visible_in_tree(),
				hint.text,
				hint_card.get_global_rect()
			]
		)
	)
	var candidates := _refused_cells(screen)
	print("PROBE refused on-screen candidates=%d" % candidates.size())
	var best := {}
	var shown := 0
	var overlapped := 0
	for at: Vector2 in candidates:
		_build.pointer_override = at
		await _frames(SETTLE_FRAMES)
		var reason := _menu.ghost_reason()
		if not reason.visible:
			continue
		shown += 1
		var shared := reason.get_global_rect().intersection(hint_card.get_global_rect())
		var area := shared.get_area() if shared.has_area() else 0.0
		var gap := _gap(reason.get_global_rect(), hint_card.get_global_rect())
		if area > 0.0:
			overlapped += 1
		# The plate shows the worst overlap, or with none the card nearest the hint card.
		if best.is_empty() or area > best["area"] or (area == best["area"] and gap < best["gap"]):
			best = {
				"at": at,
				"area": area,
				"gap": gap,
				"text": reason.text(),
				"rect": reason.get_global_rect()
			}
		print(
			(
				"OVERLAP at=%s reason='%s' reason_rect=%s hint_rect=%s shared_px=%.0f gap_px=%.0f"
				% [
					at,
					reason.text(),
					reason.get_global_rect(),
					hint_card.get_global_rect(),
					area,
					gap
				]
			)
		)
	print(
		(
			"PROBE cards_shown=%d overlapped=%d plated_at=%s plated_gap_px=%.0f"
			% [shown, overlapped, best.get("at"), best.get("gap", -1.0)]
		)
	)
	if best.is_empty():
		_invalid("no refused cell showed the reason card")
		_finish()
		return
	_build.pointer_override = best["at"]
	await _frames(SETTLE_FRAMES + 4)
	await _plate(best, hint_card, screen)
	_finish()


## Screen points over cells the Gate desk tool refuses, one per SAMPLE_STEP
## cells, kept to the ones in the viewport and clear of the bar and tray, at
## most MAX_CANDIDATES spread over the list.
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
	var picked: Array[Vector2] = []
	var step := maxf(1.0, all.size() / float(MAX_CANDIDATES))
	var i := 0.0
	while int(i) < all.size():
		picked.append(all[int(i)])
		i += step
	return picked


## The screen distance between two rects, 0 when they touch or overlap.
func _gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(0.0, maxf(b.position.x - a.end.x, a.position.x - b.end.x))
	var dy := maxf(0.0, maxf(b.position.y - a.end.y, a.position.y - b.end.y))
	return Vector2(dx, dy).length()


func _under_hud(at: Vector2) -> bool:
	if _menu.bar().get_global_rect().has_point(at):
		return true
	return _menu.is_tray_open() and _menu.tray().get_global_rect().has_point(at)


func _plate(best: Dictionary, hint_card: Control, screen: Rect2) -> void:
	var frame := screen.grow(-MARGIN_PX)
	var reason := _menu.ghost_reason()
	var status := _menu.status_label()
	for pair: Array in [
		["pointer", Rect2(best["at"], Vector2.ZERO)],
		["reason_card", reason.get_global_rect()],
		["hint_card", hint_card.get_global_rect()],
	]:
		var rect: Rect2 = pair[1]
		var inside := frame.has_point(rect.position) and frame.has_point(rect.end)
		print("INFRAME %s rect=%s in=%s" % [pair[0], rect, inside])
		if not inside:
			_invalid("%s is outside the viewport frame" % pair[0])
	if not reason.visible:
		_invalid("the reason card is not visible")
	var shared := reason.get_global_rect().intersection(hint_card.get_global_rect())
	print(
		(
			"PLATE reason='%s' reason_rect=%s hint='%s' hint_rect=%s shared_px=%.0f"
			% [
				reason.text(),
				reason.get_global_rect(),
				_staff.hint_label().text,
				hint_card.get_global_rect(),
				shared.get_area() if shared.has_area() else 0.0
			]
		)
	)
	print(
		(
			"PLATE status_label='%s' visible=%s rect=%s"
			% [status.text, status.is_visible_in_tree(), status.get_global_rect()]
		)
	)
	if _failed:
		return
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := _out_dir.path_join("ghost_card_overlap.png")
	if img.save_png(path) != OK:
		_invalid("could not save " + path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _finish() -> void:
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)
