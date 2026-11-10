extends SceneTree
## Windowed plate of the inspect card after HUD 5/7 (board a2e95d4e): a built
## item selected in the starter terminal, so the card shows in the bottom-left
## place, one GAP above the category bar and clear of the Templates button on the
## bar's baseline. Boots the real main scene with a new random sim seed
## (printed), clock paused. Checks, and prints, the card's bottom edge (the bar's
## top less GAP), its left edge on the margin, that it is in the view and meets
## neither the bar, the Templates dock nor Debug. A failed check prints
## PROBE_INVALID and the probe exits 1.
##
## Run (one windowed Godot run project-wide; hold tools/blender/out/.windowed.lock):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/hud_inspect_plate_probe.gd
##
## The plate goes to tools/blender/out/hud-5-bottom/04_inspect_card.png.

const OUT_REL := "res://../tools/blender/out/hud-5-bottom"
const MAIN_SCENE := "res://main/main.tscn"
const WINDOW := Vector2i(1920, 1080)

var _failed := false
var _main: Node
var _hud: PassengerHud


func _initialize() -> void:
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		_hud.refresh()
		await process_frame
	await RenderingServer.frame_post_draw


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
	await _frames(20)
	_hud.press_starter_terminal()
	await _frames(10)
	var build := _main.get_node("BuildMode") as BuildMode
	var scanners: Array = ReferenceTerminal.object_ids(build.grid)["scanners"]
	if scanners.is_empty():
		_invalid("the starter terminal has no scanner to select")
	else:
		var selection: BuiltSelection = _hud._built
		selection.kind = BuiltSelection.Kind.OBJECT
		selection.id = scanners[0]
		await _frames(10)
		_plate()
	_main.queue_free()
	await process_frame
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _plate() -> void:
	var menu := _main.get_node("BuildMenu") as BuildMenu
	var view := root.get_visible_rect()
	var card := _hud.find_child("PassengerInspect", true, false) as Control
	if card == null or not card.is_visible_in_tree():
		_invalid("the inspect card is not showing")
		return
	var rect := card.get_global_rect()
	var bar := menu.bar().get_global_rect()
	var templates := menu.templates_page.dock.get_global_rect()
	var debug := (_hud.find_child("DebugToggle", true, false) as Button).get_global_rect()
	print(
		"PLATE card=%s bar=%s templates=%s debug=%s view=%s" % [rect, bar, templates, debug, view]
	)
	if not is_equal_approx(rect.end.y, bar.position.y - HudLayout.GAP):
		_invalid("card bottom %s is not GAP above the bar top %s" % [rect.end.y, bar.position.y])
	if not is_equal_approx(rect.position.x, float(HudLayout.MARGIN)):
		_invalid("card left %s is not on the margin" % rect.position.x)
	if not view.encloses(rect):
		_invalid("the card is outside the view")
	for other in [bar, templates, debug]:
		if rect.intersects(other):
			_invalid("the card %s meets %s" % [rect, other])
	var path := ProjectSettings.globalize_path(OUT_REL).simplify_path().path_join(
		"04_inspect_card.png"
	)
	var err := root.get_texture().get_image().save_png(path)
	print("PLATE saved=%s err=%d" % [path, err])
	if err != OK:
		_invalid("the plate could not be saved")
