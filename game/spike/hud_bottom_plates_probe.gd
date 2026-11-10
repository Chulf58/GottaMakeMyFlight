extends SceneTree
## Windowed plates of the bottom of the HUD (HUD 5/7, decision hud-grid-and-
## rails-one-spacing-grid-centred-top-row-right-ra part 1). Boots the real main
## scene with a new random sim seed (printed), clock paused, then:
##   01_start: the start view, the build bar, Templates and Debug
##   02_build_refusal: a rotatable piece in hand, the pointer over a cell the
##      tool refuses, its tray open; the status card shows the refusal, the
##      "R rotate" hint and the cost
##   03_rail_over_tray: the same tray with four alert cards raised on the right
##      rail, which stops above the status card
## Every plate checks, and prints, the bar MARGIN off the bottom, the tray GAP
## above it, the status card TRAY_W x BUTTON_H, GAP above the tray's slot,
## Templates on the bar's baseline at the left margin, Debug on the corner
## margin, and no overlap among the visible bottom windows; plate 02 also that
## the ghost is in frame and the card holds a refusal and the hint; plate 03
## that every drawn rail card ends above the card. A failed check prints
## PROBE_INVALID and the probe exits 1.
##
## Run (one windowed Godot run project-wide; hold tools/blender/out/.windowed.lock):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/hud_bottom_plates_probe.gd
##
## Plates go to tools/blender/out/hud-5-bottom/.

const OUT_REL := "res://../tools/blender/out/hud-5-bottom"
const MAIN_SCENE := "res://main/main.tscn"
const WINDOW := Vector2i(1920, 1080)
const HOLD := 1_000_000_000
const SAMPLE_STEP := 2
const CAUSES := [
	["queue_a", "Check-in queue full", "1 desk full: open another desk or hire staff"],
	["route_b", "No route for 3 passengers", "They cannot walk to check-in: join the floor"],
	["gate_c", "Gate seats full", "12 passengers stand at gate C: add seats"],
	["more_d", "Security queue full", "1 lane full: open another lane"],
]

var _out_dir := ""
var _failed := false
var _main: Node
var _hud: PassengerHud
var _stack: AlertStack
var _build: BuildMode
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


func _menu() -> BuildMenu:
	return _main.get_node("BuildMenu") as BuildMenu


func _run() -> void:
	root.size = WINDOW
	_main = load(MAIN_SCENE).instantiate()
	var clock: SimClock = _main.get_node("SimClock")
	var seed := randi()
	clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	root.add_child(_main)
	clock.set_paused(true)
	_hud = _main.get_node("PassengerHud")
	_stack = _hud.find_child("AlertStack", false, false) as AlertStack
	_build = _main.get_node("BuildMode") as BuildMode
	await _frames(30)
	await _plate("01_start", false, false)
	_build.set_tool(BuildMode.Tool.SEATS)
	await _frames(6)
	var at := _refused_point()
	if at.x < 0.0:
		_invalid("no refused cell in frame for the Seats tool")
	else:
		_build.pointer_override = at
		await _frames(10)
		await _plate("02_build_refusal", true, false)
		for i in CAUSES.size():
			_raise(i)
		await _frames(10)
		await _plate("03_rail_over_tray", true, true)
	_main.queue_free()
	await process_frame
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


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
	_stack.board().update(_causes, (_main.get_node("PassengerSim") as PassengerSim).tick)
	_hud.refresh()


## A screen point over a cell the Seats tool refuses, in the middle of the
## viewport and clear of the bar and tray; -1,-1 when there is none.
func _refused_point() -> Vector2:
	var cam := root.get_camera_3d()
	var view := root.get_visible_rect()
	var frame := view.grow(-96.0)
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


## Checks the bottom windows against the grid, prints what it compared and
## saves the plate.
func _plate(label: String, refusal: bool, rail: bool) -> void:
	var menu := _menu()
	var view := root.get_visible_rect().size
	var bar := menu.bar().get_global_rect()
	var tray := menu.tray().get_global_rect()
	var card := menu.status_card().get_global_rect()
	var templates := menu.templates_page.dock.get_global_rect()
	var debug := (_hud.find_child("DebugToggle", true, false) as Button).get_global_rect()
	print(
		(
			"PLATE %s view=%s bar=%s tray=%s(open=%s) card=%s(visible=%s) templates=%s debug=%s"
			% [
				label,
				view,
				bar,
				tray,
				menu.is_tray_open(),
				card,
				menu.status_card().visible,
				templates,
				debug
			]
		)
	)
	_check(label, "bar bottom", bar.end.y, view.y - HudLayout.MARGIN)
	_check(label, "bar h", bar.size.y, float(HudLayout.BAR_H))
	_check(label, "templates bottom", templates.end.y, bar.end.y)
	_check(label, "templates left", templates.position.x, float(HudLayout.MARGIN))
	_check(label, "debug right", debug.end.x, view.x - HudLayout.MARGIN)
	_check(label, "debug bottom", debug.end.y, view.y - HudLayout.MARGIN)
	var rects := {"bar": bar, "templates": templates, "debug": debug}
	if menu.is_tray_open():
		_check(label, "tray bottom", tray.end.y, bar.position.y - HudLayout.GAP)
		rects["tray"] = tray
	if menu.status_card().visible:
		_check(label, "card w", card.size.x, float(HudLayout.TRAY_W))
		_check(label, "card h", card.size.y, float(HudLayout.BUTTON_H))
		_check(
			label,
			"card bottom",
			card.end.y,
			bar.position.y - HudLayout.GAP - BuildMenu.TRAY_H - HudLayout.GAP
		)
		rects["card"] = card
	if refusal:
		_refusal_checks(label, menu)
	var keys := rects.keys()
	for i in keys.size():
		if not Rect2(Vector2.ZERO, view).encloses(rects[keys[i]]):
			_invalid("%s %s is outside the view" % [label, keys[i]])
		for j in range(i + 1, keys.size()):
			if (rects[keys[i]] as Rect2).intersects(rects[keys[j]]):
				_invalid("%s %s overlaps %s" % [label, keys[i], keys[j]])
	if rail:
		_rail_checks(label, card)
	var img := root.get_texture().get_image()
	var path := _out_dir.path_join("%s.png" % label)
	var err := img.save_png(path)
	print("PLATE %s saved=%s err=%d size=%s" % [label, path, err, img.get_size()])
	if err != OK:
		_invalid("%s could not be saved" % label)


## The card holds a refusal, the hint and (in a tray) the cost, and the ghost is
## in frame.
func _refusal_checks(label: String, menu: BuildMenu) -> void:
	print(
		(
			"PLATE %s status='%s' hint='%s'(%s) cost='%s'(%s) line_count=%d"
			% [
				label,
				menu.status_label().text,
				menu.rotate_hint_label().text,
				menu.rotate_hint_label().visible,
				menu.preview_label().text,
				menu.preview_label().visible,
				menu.rotate_hint_label().get_line_count()
			]
		)
	)
	if menu.status_label().text == "" or not menu.status_label().visible:
		_invalid("%s: no refusal on the status card" % label)
	if not menu.rotate_hint_label().visible:
		_invalid("%s: no R rotate hint" % label)
	if menu.rotate_hint_label().get_line_count() != 1:
		_invalid("%s: the hint wraps" % label)
	var ghost := GhostBounds.build_rect(_build, root.get_camera_3d())
	print("PLATE %s ghost rect=%s" % [label, ghost])
	if not ghost.has_area() or not root.get_visible_rect().encloses(ghost):
		_invalid("%s: the ghost is not in frame" % label)


## Every drawn rail card ends GROUP_GAP above the status card.
func _rail_checks(label: String, card: Rect2) -> void:
	var shown := _stack.shown_keys()
	print(
		(
			"PLATE %s rail shown=%s more=%d rect=%s"
			% [label, shown, _stack.more_count(), _stack.get_global_rect()]
		)
	)
	if shown.size() < 3:
		_invalid("%s: the rail shows %d cards, expected 3 or more" % [label, shown.size()])
	for key in shown:
		var part := _stack.card_node(key)
		if part == null:
			part = _stack.notice_card(key)
		var r := part.get_global_rect()
		print("PLATE %s rail card %s rect=%s" % [label, key, r])
		if r.end.y > card.position.y - HudLayout.GROUP_GAP + 0.5:
			_invalid("%s: rail card %s at %s reaches the status card %s" % [label, key, r, card])


func _check(label: String, what: String, actual: Variant, expected: Variant) -> void:
	if not is_equal_approx(actual, expected):
		_invalid("%s %s is %s, expected %s" % [label, what, actual, expected])
