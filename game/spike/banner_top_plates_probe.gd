extends SceneTree
## Windowed plates of the status banner and a first-time hint at the top centre
## (decision status-banner-and-first-time-hints-sit-at-the-top-centre, board
## c6166195). Boots main.tscn with a new random sim seed (printed), opens a build
## tray (build mode: the Build mode sign shows), raises one dirty-terminal alert
## card, and at 1920x1080 and 1280x720 saves two plates each:
##   banner  a long two-line closed-airport message in the banner
##   hint    a first-time hint holding the slot (the banner yields)
## Both window sizes have the same 1536x864 layout (stretch scale 1.25), so the
## plates differ in pixels only. Each plate proves its card is inside the viewport by MARGIN_PX, in the top
## band, centred, and clear of every other top HUD rectangle (all printed).
## Otherwise PROBE_INVALID is printed and the probe exits 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/banner_top_plates_probe.gd
##
## Plates go to tools/blender/out/banner-top/.

const OUT_REL := "res://../tools/blender/out/banner-top"
const MAIN_SCENE := "res://main/main.tscn"
const HINTS_PATH := "user://banner_top_probe_hints.cfg"
const MARGIN_PX := 4.0
const SIZES: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(1280, 720)]
const OTHERS: Array[String] = [
	"MoneySlot",
	"RatingCard",
	"OffersButton",
	"FlightPanel",
	"AlertHistoryButton",
	"MoodToggle",
	"DeparturesToggle",
	"BuildModeSign",
]

var _out_dir := ""
var _failed := false
var _main: Node
var _menu: BuildMenu
var _staff: StaffPanel
var _hud: PassengerHud
var _stack: AlertStack
var _hints: Hints


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
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
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	_menu = _main.get_node("BuildMenu")
	_staff = _main.get_node("StaffPanel")
	_hud = _main.get_node("PassengerHud")
	_stack = _hud.find_child("AlertStack", false, false) as AlertStack
	await _frames(30)
	_staff.hint_label().text = (
		StaffPanel.CLOSED_HINTS[AirportGate.Blocker.STAFF_SPOT] + "\n" + StaffPanel.GAP_HINT
	)
	_staff.hint_card().visible = true
	_menu.press_category(0)
	_spills(_main.get_node("PassengerSim"))
	_hints = _make_hints()
	for size in SIZES:
		root.size = size
		await _frames(30)
		_hud.refresh()
		await _plate("banner", size, _staff.hint_card())
		_show_hint()
		await _frames(30)
		_hud.refresh()
		await _frames(5)
		await _plate("hint", size, _hints.card())
		_hints.set_enabled(false)
		_staff.set_hint_yielded(false)
		_hints.set_enabled(true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HINTS_PATH))
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _make_hints() -> Hints:
	var hints := Hints.new()
	hints.forced_mode = Hints.Mode.PROFILE
	hints.settings_path = HINTS_PATH
	hints.hud = _hud
	hints.scene_root = _main
	hints.reads_world = false
	_hud.add_child(hints)
	hints._process(0.0)
	hints.advance(Hints.GRACE_S + 0.1, HintRules.read_world(_main.get_node("PassengerSim"), []), [])
	return hints


func _show_hint() -> void:
	_hints.reset_seen()
	var world := HintRules.read_world(_main.get_node("PassengerSim"), [])
	for i in 8:
		_hints.advance(0.25, world, ["Check-in"])
	if not _hints.is_showing():
		_invalid("no hint is showing")
	_stack.avoid = func() -> Rect2: return _hints.card().get_global_rect()


func _plate(label: String, size: Vector2i, card: Control) -> void:
	var view := root.get_visible_rect().size
	var rect := card.get_global_rect()
	print("PLATE %s window=%s view=%s card=%s lines=%s" % [label, size, view, rect, _lines(card)])
	var screen := Rect2(Vector2.ZERO, view).grow(-MARGIN_PX)
	if not card.is_visible_in_tree() or not screen.encloses(rect):
		_invalid("%s %s: card %s not in frame %s" % [label, size, rect, screen])
	if absf(rect.get_center().x - view.x / 2.0) > 1.0:
		_invalid("%s %s: card is not centred" % [label, size])
	if rect.position.y >= view.y * 0.4:
		_invalid("%s %s: card is not in the top band" % [label, size])
	var rects: Array[Control] = []
	for node_name in OTHERS:
		rects.append(_main.find_child(node_name, true, false) as Control)
	for key in _stack.card_keys():
		rects.append(_stack.card_node(key))
	for other in rects:
		if other == null or not other.is_visible_in_tree():
			continue
		var r := other.get_global_rect()
		var clash := rect.intersects(r)
		print("  vs %s %s overlap=%s" % [other.name, r, clash])
		if clash:
			_invalid("%s %s: card overlaps %s" % [label, size, other.name])
	if _failed:
		return
	await _frames(2)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := _out_dir.path_join("%s_%dx%d.png" % [label, size.x, size.y])
	if img.save_png(path) != OK:
		_invalid("could not save " + path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _lines(card: Control) -> int:
	for label in card.find_children("*", "Label", true, false):
		if (label as Label).is_visible_in_tree() and (label as Label).text.length() > 20:
			return (label as Label).get_line_count()
	return 0


## DirtyAlert.SHOW_AT spills on floored, object-free cells three apart.
func _spills(sim: PassengerSim) -> void:
	var grid := sim.grid
	var placed: Array[Vector2i] = []
	for y in grid.size.y:
		for x in grid.size.x:
			var c := Vector2i(x, y)
			if placed.size() == DirtyAlert.SHOW_AT:
				return
			if grid.floor_at(c) == BuildGrid.FLOOR_NONE or grid.object_at(c) != 0:
				continue
			if placed.any(func(p: Vector2i) -> bool: return maxi(absi(p.x - x), absi(p.y - y)) < 3):
				continue
			if sim.messes.add(MessSim.Kind.SPILL, c) != 0:
				placed.append(c)
