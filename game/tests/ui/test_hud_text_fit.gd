class_name TestHudTextFit
extends GdUnitTestSuite
## Build-menu card names wrap onto up to two lines and step their font size down
## cleanly to fit the 72 px width and 80x96 compact card height without clipping,
## keeping the fixed 40x40 thumbnail (decisions build-menu-card-names-wrap-to-
## two-lines-then-shrink-a-font-s and build-menu-slider-free-wrapping-grid-80x96-
## cards-9-columns). The build status line wraps to two lines instead of clipping.

## Sample slot width for the pure HudLayout.fit_size / line_count unit cases.
const SLOT_W := 100.0
const WORD := "Gate"

var _port: SubViewport
var _mode: BuildMode
var _menu: BuildMenu
var _font: Font


func before_test() -> void:
	_font = BuildMenu.HUD_THEME.get_font(&"font", &"HudCardName")


func after_test() -> void:
	if _port != null:
		_port.free()
		_port = null
	DemoMode.clear_override()
	PseudoLocale.disable()


func _build_menu(pseudo: bool) -> void:
	if pseudo:
		PseudoLocale.enable(0.4)
	_port = SubViewport.new()
	_port.size = Vector2i(1536, 864)
	# One expansion, as a real translation: the stored text is already through tr().
	if pseudo:
		_port.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_port)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_port.add_child(_mode)
	_mode.set_process(false)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)
	await _frames(3)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _words(count: int) -> String:
	var words: Array[String] = []
	for i in count:
		words.append(WORD)
	return " ".join(words)


func _labels(card: Button) -> Array[Label]:
	var out: Array[Label] = []
	for child in card.get_child(0).get_children():
		if child is Label:
			out.append(child as Label)
	return out


## The word widths the cases below rely on: two words fit a line, three do not
## at the caption size, and three do at one step down.
func test_the_sample_words_measure_as_the_cases_need() -> void:
	var two := _font.get_string_size(_words(2), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var three := _font.get_string_size(_words(3), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var three_small := _font.get_string_size(_words(3), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	print("widths two=%.1f three=%.1f three@12=%.1f slot=%.0f" % [two, three, three_small, SLOT_W])
	assert_float(two).is_less(SLOT_W)
	assert_float(three).is_greater(SLOT_W)
	assert_float(three_small).is_less(SLOT_W)


func test_one_step_down_is_the_type_scale_step_or_two_px_under_caption() -> void:
	assert_int(HudLayout.step_down(HudLayout.TITLE)).is_equal(HudLayout.BODY)
	assert_int(HudLayout.step_down(HudLayout.BODY)).is_equal(HudLayout.CAPTION)
	assert_int(HudLayout.step_down(HudLayout.CAPTION)).is_equal(HudLayout.FIT_STEP)
	assert_int(HudLayout.FIT_STEP).is_equal(12)


func test_a_short_name_stays_on_one_line_at_the_caption_size() -> void:
	assert_int(HudLayout.line_count(WORD, _font, 14, SLOT_W)).is_equal(1)
	assert_int(HudLayout.fit_size(WORD, _font, 14, SLOT_W, 2)).is_equal(14)


func test_a_long_name_wraps_to_two_lines_at_the_caption_size() -> void:
	assert_int(HudLayout.line_count(_words(4), _font, 14, SLOT_W)).is_equal(2)
	assert_int(HudLayout.fit_size(_words(4), _font, 14, SLOT_W, 2)).is_equal(14)


func test_a_name_still_too_long_for_two_lines_drops_one_font_step() -> void:
	assert_int(HudLayout.line_count(_words(5), _font, 14, SLOT_W)).is_equal(3)
	assert_int(HudLayout.fit_size(_words(5), _font, 14, SLOT_W, 2)).is_equal(12)
	assert_int(HudLayout.line_count(_words(5), _font, 12, SLOT_W)).is_equal(2)


## A word wider than the slot would break in two at the caption size, so it takes
## the step down even though two lines would hold it.
func test_a_word_wider_than_the_slot_drops_one_font_step() -> void:
	var word := "Gategategategate"
	var wide := _font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	print("word width=%.1f slot=%.0f" % [wide, SLOT_W])
	assert_float(wide).is_greater(SLOT_W)
	assert_int(HudLayout.line_count(word, _font, 14, SLOT_W)).is_equal(2)
	assert_int(HudLayout.fit_size(word, _font, 14, SLOT_W, 2)).is_equal(12)


func test_a_card_name_wraps_then_shrinks_and_the_card_keeps_its_size() -> void:
	await _build_menu(false)
	_menu.press_category(BuildMenuCatalog.category_of(BuildMode.Tool.DESK))
	await _frames(3)
	var card := _menu.card(BuildMode.Tool.DESK)
	var name_label := _labels(card)[0]
	var picture := card.find_children("*", "TextureRect", true, false)[0] as TextureRect
	assert_bool(name_label.clip_text).is_false()
	assert_int(name_label.autowrap_mode).is_equal(TextServer.AUTOWRAP_WORD_SMART)
	assert_int(name_label.max_lines_visible).is_equal(2)
	var resting := picture.size.y
	name_label.text = _words(3)
	await _frames(3)
	print(
		(
			"two lines: size=%d lines=%d picture=%.0f->%.0f"
			% [
				name_label.get_theme_font_size(&"font_size"),
				name_label.get_line_count(),
				resting,
				picture.size.y
			]
		)
	)
	assert_int(name_label.get_theme_font_size(&"font_size")).is_equal(12)
	assert_int(name_label.get_line_count()).is_equal(2)
	assert_int(name_label.get_visible_line_count()).is_equal(2)
	assert_vector(picture.size).is_equal(Vector2(BuildMenu.THUMB_SIZE, BuildMenu.THUMB_SIZE))
	name_label.text = _words(6)
	await _frames(3)
	assert_int(name_label.get_theme_font_size(&"font_size")).is_less(12)
	assert_int(name_label.get_line_count()).is_equal(2)
	assert_int(name_label.get_visible_line_count()).is_equal(2)
	assert_vector(picture.size).is_equal(Vector2(BuildMenu.THUMB_SIZE, BuildMenu.THUMB_SIZE))
	name_label.text = WORD
	await _frames(3)
	assert_int(name_label.get_theme_font_size(&"font_size")).is_equal(14)
	assert_float(picture.size.y).is_equal_approx(resting, 0.5)
	_assert_card_size(card)
	_assert_inside(card)


## Every card of every tray at +40% (one expansion): no label clips beyond two
## lines, every label and the thumbnail stay inside the 80x96 card, and the card
## keeps its size. Some labels wrap (a positive control that the wrap is reached).
func test_every_card_fits_at_plus_forty_percent() -> void:
	await _build_menu(true)
	var cards := 0
	var wrapped := 0
	var shrunk := 0
	var seen := {}
	var categories := BuildMenuCatalog.categories()
	for i in categories.size():
		if i == BuildMenuCatalog.remove_category():
			continue
		_menu.press_category(i)
		await _frames(2)
		for tool: BuildMode.Tool in categories[i]["tools"]:
			var card := _menu.card(tool)
			if card == null or not card.is_visible_in_tree() or seen.has(tool):
				continue
			seen[tool] = true
			cards += 1
			_assert_card_size(card)
			for label in _labels(card):
				var where := "tool %d '%s'" % [tool, label.text]
				assert_int(label.get_line_count()).override_failure_message(where).is_less_equal(2)
				assert_int(label.get_visible_line_count()).override_failure_message(where).is_equal(
					label.get_line_count()
				)
				wrapped += 1 if label.get_line_count() == 2 else 0
				var small := label.get_theme_font_size(&"font_size") < 14
				shrunk += 1 if small else 0
				_assert_shrink_matches_need(label, small, where)
			_assert_inside(card)
	for room_type: StringName in RoomTypes.ids():
		_menu.enter_room_context(room_type)
		await _frames(2)
		for entry: Dictionary in BuildMenuCatalog.room_context_entries(room_type):
			var tool: BuildMode.Tool = entry["tool"]
			var card := _menu.card(tool)
			if card == null or not card.is_visible_in_tree() or seen.has(tool):
				continue
			seen[tool] = true
			cards += 1
			_assert_card_size(card)
			for label in _labels(card):
				var where := "room %s tool %d '%s'" % [room_type, tool, label.text]
				assert_int(label.get_line_count()).override_failure_message(where).is_less_equal(2)
				assert_int(label.get_visible_line_count()).override_failure_message(where).is_equal(
					label.get_line_count()
				)
				wrapped += 1 if label.get_line_count() == 2 else 0
				var small := label.get_theme_font_size(&"font_size") < 14
				shrunk += 1 if small else 0
				_assert_shrink_matches_need(label, small, where)
			_assert_inside(card)
	print("cards=%d wrapped=%d shrunk=%d" % [cards, wrapped, shrunk])
	assert_int(cards).is_greater(60)
	assert_int(wrapped).is_greater(0)


func test_demo_teaser_in_the_full_game_fits_on_one_line_within_card() -> void:
	DemoMode.set_override_for_test(true)
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	var rating: AirportRating = auto_free(AirportRating.new())
	var pax: PassengerSim = auto_free(PassengerSim.new())
	var unlocks := BuildUnlocks.new()
	unlocks.rating = rating
	unlocks.passengers = pax
	unlocks.manual = true
	_port.add_child(unlocks)
	for i in 100:
		rating.record_passenger(0, true, PassengerSim.MOOD_MAX)
		pax.outcome.emit(i, true)
	unlocks.check()
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_mode.unlocks = unlocks
	_mode.require_unlocks = true
	_port.add_child(_mode)
	_mode.set_process(false)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)
	_menu.press_category(BuildMenu.category_index("decor"))
	await _frames(3)
	var tree_card := _menu.card(BuildMode.Tool.TREE)
	var price_label := _menu.card_price_label(BuildMode.Tool.TREE)
	assert_str(price_label.text).is_equal("In the full game")
	assert_int(price_label.get_line_count()).is_equal(1)
	assert_int(price_label.get_visible_line_count()).is_equal(1)
	_assert_card_size(tree_card)
	_assert_inside(tree_card)


## What the label draws: its text through its own auto-translate switch. The
## character count of the shaped line proves this is the text the Label shows.
func _shown(label: Label) -> String:
	var shown := label.atr(label.text)
	assert_int(label.get_total_character_count()).override_failure_message(shown).is_equal(
		shown.length()
	)
	return shown


## A label drops below 14 px only when 14 px exceeds its horizontal slot or the
## 80x96 card's vertical budget; otherwise it stays at 14 px.
func _assert_shrink_matches_need(label: Label, small: bool, where: String) -> void:
	var shown := _shown(label)
	var font := label.get_theme_font(&"font")
	var width := label.size.x
	var max_lines := label.max_lines_visible if label.max_lines_visible > 0 else 2
	var lines := HudLayout.line_count(shown, font, HudLayout.CAPTION, width)
	var widest := HudLayout.widest_word(shown, font, HudLayout.CAPTION)
	var needed := lines > max_lines or widest > width
	if not needed and max_lines > 1 and lines > 1:
		var avail_h := (
			BuildMenu.CARD_SIZE.y - 2.0 * BuildMenuLayout.CARD_PAD_Y - BuildMenu.THUMB_SIZE - 20.0
		)
		var line_sp := float(label.get_theme_constant(&"line_spacing"))
		var h14 := float(lines) * font.get_height(HudLayout.CAPTION) + float(lines - 1) * line_sp
		needed = h14 > avail_h + 0.5
	var detail := "%s shown '%s' at 14: lines=%d widest=%.1f slot=%.1f"
	detail = detail % [where, shown, lines, widest, width]
	assert_bool(small).override_failure_message(detail).is_equal(needed)


## A line that is already through tr() (one expansion, auto-translate off) and fits
## one line at 14 px stays at 14 px, though a second expansion would wrap/shrink.
func test_an_already_translated_line_that_fits_stays_at_the_caption_size() -> void:
	await _build_menu(true)
	_menu.press_category(BuildMenuCatalog.category_of(BuildMode.Tool.DESK))
	await _frames(3)
	var card := _menu.card(BuildMode.Tool.DESK)
	var label := _labels(card)[0]
	var font := label.get_theme_font(&"font")
	var width := label.size.x
	var shown := ""
	for candidate in ["Gate", "Seat", "Counter", "Seats", "Desk"]:
		var once := tr(candidate)
		var twice := tr(once)
		if (
			HudLayout.line_count(once, font, 14, width) == 1
			and HudLayout.widest_word(once, font, 14) <= width
			and (
				HudLayout.line_count(twice, font, 14, width) > 1
				or HudLayout.widest_word(twice, font, 14) > width
			)
		):
			shown = once
			break
	print("shown=[%s] width=%.0f" % [shown, width])
	assert_str(shown).is_not_empty()
	label.text = shown
	await _frames(3)
	assert_int(label.get_line_count()).is_equal(1)
	assert_int(label.get_theme_font_size(&"font_size")).is_equal(14)
	_assert_shrink_matches_need(label, false, "regression")


## The card keeps its 80x96 size and the tray keeps its row height.
func _assert_card_size(card: Button) -> void:
	var tray := _menu.find_child("ItemTray", true, false) as Control
	assert_float(card.size.x).override_failure_message(card.name).is_equal(BuildMenu.CARD_SIZE.x)
	assert_float(card.size.y).override_failure_message(card.name).is_equal(BuildMenu.CARD_SIZE.y)
	assert_float(tray.size.y).override_failure_message(card.name).is_equal(_menu.tray_height())


func _assert_inside(card: Button) -> void:
	var box := card.get_global_rect().grow(0.5)
	for child in card.find_children("*", "Control", true, false):
		var control := child as Control
		if not control.is_visible_in_tree():
			continue
		var where := "%s in %s" % [control.name, card.name]
		(
			assert_bool(box.encloses(control.get_global_rect()))
			. override_failure_message(where)
			. is_true()
		)


## The status line wraps onto a second line and the card grows up for it; a
## longer status keeps two lines and ends in an ellipsis instead of a third.
func test_the_status_line_wraps_to_two_lines() -> void:
	await _build_menu(false)
	var status := _menu.status_label()
	var card := status.get_parent().get_parent() as Control
	# A rectangle drag held over the HUD keeps the status line showing with no
	# pointer over the grid (as test_build_menu_card_hint does).
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_mode.begin_area(_mode.grid.cell_to_world(Vector2i(3, 3)))
	_mode.move_area(_mode.grid.cell_to_world(Vector2i(8, 8)))
	_mode._area_over_ui = true
	_menu._on_status_changed(_words(30))
	_menu.refresh_preview()
	await _frames(3)
	assert_bool(card.is_visible_in_tree()).is_true()
	print(
		(
			"status lines=%d visible=%d card=%s"
			% [status.get_line_count(), status.get_visible_line_count(), card.get_global_rect()]
		)
	)
	assert_bool(status.clip_text).is_false()
	assert_int(status.autowrap_mode).is_equal(TextServer.AUTOWRAP_WORD_SMART)
	assert_int(status.get_line_count()).is_equal(2)
	assert_float(card.size.y).is_greater(float(HudLayout.BUTTON_H))
	assert_bool(card.get_global_rect().grow(0.5).encloses(status.get_global_rect())).is_true()
	_menu._on_status_changed(_words(120))
	await _frames(3)
	assert_int(status.get_visible_line_count()).is_equal(2)
	assert_int(status.text_overrun_behavior).is_equal(TextServer.OVERRUN_TRIM_ELLIPSIS)
	_menu._on_status_changed(WORD)
	await _frames(3)
	assert_int(status.get_line_count()).is_equal(1)
	assert_float(card.size.y).is_equal_approx(float(HudLayout.BUTTON_H), 0.5)
	_mode._area_over_ui = false
	_mode.cancel_area()
