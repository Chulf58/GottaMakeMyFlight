extends SceneTree
## Windowed plate probe for the four furniture-bearing domain tabs of the build
## menu (Facilities, Food & Drink, Shops and Decor & Parking; decision
## build-menu-rework-six-domain-tabs-progressive-tab-and-card-u).
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/build_menu_furniture_probe.gd
##
## For each tab: opens its tray through its bar button, proves the tray's drawn
## rectangle is no wider than BuildMenu.COLUMN_W and lies inside the window, and
## scrolls each card into view to prove every card is visible inside the tray,
## holds its rendered thumbnail (the texture of THUMBNAIL_DIR for its card, no
## placeholder tile, some opaque pixels) and has a name that fits up to two
## lines inside the card's width without breaking words. It then picks Remove
## and checks the tray closes and the Remove button is pressed. Every pass value
## is printed, and a failure prints PROBE_INVALID and exits 1. Plates go to
## tools/blender/out/hud-6-7/groups/: one full-window plate per tab
## (menu_page_<n>.png) and menu_pages_sheet.png, the lower part of every tab
## in one image. The window is 1920x1080 at the project's 1.25 UI scale.

const OUT_REL := "res://../tools/blender/out/hud-6-7/groups"
const STAGE_LIMIT_MS := 60000
## The share of the window's height, from the bottom, a sheet tile keeps.
const BAND_SHARE := 0.34
const CARD_LINE := "CARD %s thumbnail=%s want=%s tiles=%d opaque_px=%d lines=%d"
const CARD_LINE_FIT := " label_w=%.1f in_tray=%s visible=%s"

var _out_dir := ""
var _failed := false
var _stage := "init"
var _stage_started_ms := 0


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _stage_started_ms > STAGE_LIMIT_MS:
		print("PROBE_INVALID hang stage=%s" % _stage)
		quit(1)
	return false


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _grab() -> Image:
	await _frames(4)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _run() -> void:
	_stage = "build"
	_stage_started_ms = Time.get_ticks_msec()
	var finances := Finances.new()
	root.add_child(finances)
	var mode := BuildMode.new()
	mode.finances = finances
	root.add_child(mode)
	var menu := BuildMenu.new()
	menu.build_mode = mode
	root.add_child(menu)
	mode.set_tool(BuildMode.Tool.NONE)
	await _frames(4)
	var leaders := _leaders()
	if leaders.size() != 4:
		_invalid("%d furniture tabs, want 4" % leaders.size())
		quit(1)
		return
	var sheet: Image
	var seen := {}
	var n := 0
	for page in leaders:
		menu.category_button(page).pressed.emit()
		_stage = "page %d" % n
		_stage_started_ms = Time.get_ticks_msec()
		await _frames(4)
		if menu.open_category() != page:
			_invalid("page %d: open category is %d, want %d" % [n, menu.open_category(), page])
		print("TAB %s" % [BuildMenu.categories()[page]["name"]])
		var img := await _grab()
		await _check_page(menu, page, seen)
		_save(img, "menu_page_%d.png" % (n + 1))
		var band := int(img.get_height() * BAND_SHARE)
		var half := Vector2i(int(img.get_width() * 0.5), int(band * 0.5))
		if sheet == null:
			sheet = Image.create(half.x, half.y * leaders.size(), false, Image.FORMAT_RGBA8)
		var tile := img.get_region(Rect2i(0, img.get_height() - band, img.get_width(), band))
		tile.resize(half.x, half.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(tile, Rect2i(Vector2i.ZERO, half), Vector2i(0, n * half.y))
		n += 1
	if seen.size() < FurnitureTools.OBJECTS.size():
		_invalid(
			(
				"tabs showed %d cards, fewer than %d furniture"
				% [seen.size(), FurnitureTools.OBJECTS.size()]
			)
		)
	_save(sheet, "menu_pages_sheet.png")
	_check_remove(menu, mode)
	print("PROBE done failed=%s cards_seen=%d" % [_failed, seen.size()])
	quit(1 if _failed else 0)


## The four furniture-bearing domain tabs, in bar order.
func _leaders() -> Array[int]:
	var out: Array[int] = []
	for cat_id in ["facilities", "food", "shops", "decor"]:
		out.append(BuildMenu.category_index(cat_id))
	return out


func _check_page(menu: BuildMenu, page: int, seen: Dictionary) -> void:
	var screen := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var tray := menu.tray().get_global_rect()
	var centre := screen.size.x / 2.0
	var in_column := (
		tray.size.x <= BuildMenu.COLUMN_W
		and absf(tray.get_center().x - centre) <= 1.0
		and screen.encloses(tray)
	)
	print(
		(
			"PAGE %d tray=%s width=%.1f limit=%.1f screen=%s open=%s"
			% [page, tray, tray.size.x, BuildMenu.COLUMN_W, screen, menu.is_tray_open()]
		)
	)
	if not (in_column and menu.is_tray_open()):
		_invalid("page %d: the tray is wider than the column or off screen" % page)
	for tool in BuildMenu.categories()[page]["tools"]:
		seen[tool] = true
		await _check_card(menu, tool, tray)


func _check_card(menu: BuildMenu, tool: BuildMode.Tool, tray: Rect2) -> void:
	var card := menu.card(tool)
	menu.tray_scroll().ensure_control_visible(card)
	await _frames(1)
	var picture := card.find_children("*", "TextureRect", true, false)[0] as TextureRect
	var want := BuildMenu.THUMBNAIL_DIR % BuildMenu.item(tool)[1]
	var path: String = picture.texture.resource_path if picture.texture != null else "none"
	var tiles := picture.find_children("*", "ColorRect", true, false).size()
	var opaque := 0
	if picture.texture != null:
		var pixels := picture.texture.get_image()
		for y in pixels.get_height():
			for x in pixels.get_width():
				if pixels.get_pixel(x, y).a > 0.5:
					opaque += 1
	var name_label := card.find_children("*", "Label", true, false)[0] as Label
	var font := name_label.get_theme_font("font")
	var font_size := name_label.get_theme_font_size("font_size")
	var shown := name_label.atr(name_label.text)
	var lines := HudLayout.line_count(shown, font, font_size, name_label.size.x)
	var widest := HudLayout.widest_word(shown, font, font_size)
	var fits_name := lines <= 2 and widest <= name_label.size.x + 0.5
	var on_tray := tray.grow(1.0).encloses(card.get_global_rect())
	var line := CARD_LINE % [name_label.text, path, want, tiles, opaque, lines]
	line += CARD_LINE_FIT % [name_label.size.x, on_tray, card.is_visible_in_tree()]
	print(line)
	if path != want or tiles != 0 or opaque == 0:
		_invalid("%s: no rendered thumbnail" % name_label.text)
	if not (fits_name and on_tray and card.is_visible_in_tree()):
		_invalid("%s: the card is clipped or outside the tray" % name_label.text)


func _check_remove(menu: BuildMenu, mode: BuildMode) -> void:
	menu.press_category(BuildMenu.remove_category())
	var pressed := menu.category_button(BuildMenu.remove_category()).button_pressed
	print("REMOVE tool=%d pressed=%s tray_open=%s" % [mode.tool, pressed, menu.is_tray_open()])
	if mode.tool != BuildMode.Tool.REMOVE or not pressed or menu.is_tray_open():
		_invalid("Remove does not pick the remove tool with the tray closed")
