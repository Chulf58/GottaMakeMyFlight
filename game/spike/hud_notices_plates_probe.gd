extends SceneTree
## Windowed plates of the Offers notices (HUD 6/7, decision hud-grid-and-rails-
## one-spacing-grid-centred-top-row-right-ra, parts 1 and 6). Boots the real main
## scene with a new random sim seed (printed), clock paused, rating pushed below
## two stars through its own record_passenger, then:
##   01_rail_notices: the coral rating warning and an ended-contract card on the
##      right rail, newest first (ended, then warning)
##   02_offers_sheet: the Offers sheet open with offers only, no warning line
## Every plate prints what it compared: the rail on the margin RAIL_W wide, each
## notice card visible, inside the view and clear of the clock panel, drawn in
## the theme's HudCardCoral fill, the sheet's offer cards inside the view and
## no label on the sheet carrying the warning. A failed check prints
## PROBE_INVALID and the probe exits 1.
##
## Run (one windowed Godot run project-wide; hold tools/blender/out/.windowed.lock):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/hud_notices_plates_probe.gd
##
## Plates go to tools/blender/out/hud-6-notices/.

const OUT_REL := "res://../tools/blender/out/hud-6-notices"
const MAIN_SCENE := "res://main/main.tscn"
const WINDOW := Vector2i(1920, 1080)

var _out_dir := ""
var _failed := false
var _main: Node
var _hud: PassengerHud
var _stack: AlertStack
var _panel: OfferPanel
var _desk: OfferDesk


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


func _run() -> void:
	root.size = WINDOW
	_main = load(MAIN_SCENE).instantiate()
	var clock := _main.get_node("SimClock") as SimClock
	var seed := randi()
	clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	root.add_child(_main)
	clock.set_paused(true)
	_hud = _main.get_node("PassengerHud")
	_stack = _hud.find_child("AlertStack", false, false) as AlertStack
	_panel = _main.get_node("OfferPanel") as OfferPanel
	_desk = _main.get_node("OfferDesk") as OfferDesk
	await _frames(30)
	for i in 10:
		_desk.rating.record_passenger(10, false, 0)
	var contract := {"airline": "Nordic Wing", "destination": "Rome"}
	_desk.contract_ended.emit(contract)
	await _frames(10)
	await _plate_rail("01_rail_notices")
	if _panel.card_ids().is_empty():
		_desk.board.ensure_day(0, RandomNumberGenerator.new())
	_panel.open()
	await _frames(10)
	await _plate_sheet("02_offers_sheet")
	_main.queue_free()
	await process_frame
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _plate_rail(label: String) -> void:
	var view := root.get_visible_rect().size
	var panel := (_hud.find_child("FlightPanel", false, false) as Control).get_global_rect()
	var rail := _stack.get_global_rect()
	var shown := _stack.shown_keys()
	print("PLATE %s view=%s panel=%s rail=%s shown=%s" % [label, view, panel, rail, shown])
	if rail.position.x != view.x - HudLayout.MARGIN - HudLayout.RAIL_W:
		_invalid("%s rail x %s is off the margin" % [label, rail.position.x])
	if not is_equal_approx(rail.size.x, float(HudLayout.RAIL_W)):
		_invalid("%s rail width %s is not RAIL_W" % [label, rail.size.x])
	if shown.size() < 2 or shown[0] != OfferPanel.ENDED_KEY or shown[1] != OfferPanel.WARNING_KEY:
		_invalid("%s drawn order %s is not ended then warning" % [label, shown])
	var coral := (
		(BuildMenu.HUD_THEME.get_stylebox("normal", "HudButtonCoral") as StyleBoxFlat).bg_color
	)
	for key in [OfferPanel.ENDED_KEY, OfferPanel.WARNING_KEY]:
		var card := _stack.notice_card(key)
		if card == null or not card.is_visible_in_tree():
			_invalid("%s %s card is not drawn" % [label, key])
			continue
		var r := card.get_global_rect()
		var fill := (card.get_theme_stylebox("panel") as StyleBoxFlat).bg_color
		print("PLATE %s %s rect=%s fill=%s coral=%s" % [label, key, r, fill, coral])
		if r.intersects(panel) or not Rect2(Vector2.ZERO, view).encloses(r):
			_invalid("%s %s card %s meets the clock panel or leaves the view" % [label, key, r])
		if not fill.is_equal_approx(coral):
			_invalid("%s %s card is not coral" % [label, key])
	_save(label)


func _plate_sheet(label: String) -> void:
	var view := root.get_visible_rect().size
	var ids := _panel.card_ids()
	print("PLATE %s open=%s offer_cards=%d" % [label, _panel.is_open(), ids.size()])
	if not _panel.is_open() or ids.is_empty():
		_invalid("%s sheet is not open with offers" % label)
	for id in ids:
		var r := _panel.card(id).get_global_rect()
		print("PLATE %s card %s rect=%s" % [label, id, r])
		if not Rect2(Vector2.ZERO, view).encloses(r):
			_invalid("%s card %s leaves the view" % [label, id])
	for node in _panel.find_children("*", "Label", true, false):
		var text := (node as Label).text
		if text.contains("below") or text.contains("ended its contract"):
			_invalid("%s a sheet label carries a notice: %s" % [label, text])
	_save(label)


func _save(label: String) -> void:
	var img := root.get_texture().get_image()
	var path := _out_dir.path_join("%s.png" % label)
	var err := img.save_png(path)
	print("PLATE %s saved=%s err=%d size=%s" % [label, path, err, img.get_size()])
	if err != OK:
		_invalid("%s could not be saved" % label)
