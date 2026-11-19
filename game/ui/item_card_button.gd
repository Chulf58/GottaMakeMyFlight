class_name ItemCardButton
extends Button
## A build tray's item card with its hover card (decisions build-menu-items-show-
## a-hover-card-with-a-description and build-menu-rework-six-domain-tabs-
## progressive-tab-and-card-u). Hovering the card pops a 280 px info card above
## it: the item's name, live lock/demo requirement, footprint size, placement
## mode (Click/Drag), upkeep/needs chips, and [about, how it works, needs] from
## ItemInfo.
##
## The card is a tooltip popup, as MoneySlot's is. It is placed above the item
## card at its left edge from get_screen_transform() of the card's local origin
## (decision a-new-game-starts-with-no-build-tool-selected-refusal-status), not
## from get_global_rect(), which would carry the card's own offset twice. It keeps
## inside the window sideways.

const HUD_THEME := preload("res://ui/hud_theme.tres")
## The headings of the card's second and third parts.
## The English msgids of the headings: tests compare against them, and the card says
## tr() of the literal, because the POT extractor reads only literals.
const HOW_HEADING := "How it works"
const NEEDS_HEADING := "Needs and upkeep"
## Width of the info card's text, in layout units.
const CARD_TEXT_W := 280.0
## Space between the item card and the info card above it.
const CARD_GAP := 6.0

## The item's name, its [about, how, needs] text, and optional [text, variation] chips.
var title := ""
var info: Array = []
var details: Array = []
## Returns why the item is locked, asked each time the hover card is built so
## the numbers in it are current (BuildMenu sets it on a locked card; an empty
## Callable or an empty text leaves the card as it was).
var requirement := Callable()

## The card last handed to the tooltip popup.
var _card: Control


## Gives the card its hover card. Empty `with_info` and `with_details` with no
## lock requirement leaves it with none.
func set_info(with_title: String, with_info: Array, with_details: Array = []) -> void:
	title = with_title
	info = with_info
	details = with_details
	tooltip_text = card_text(title, info, requirement_now(), _detail_texts())


## Why the item is locked right now, "" when it is not.
func requirement_now() -> String:
	return requirement.call() if requirement.is_valid() else ""


## The info as plain text, one part per line under the name, and under the name
## the `needs` line of a locked item plus any `extra` detail lines; "" when
## nothing beyond the title exists. It is also what makes Godot ask for the hover card.
static func card_text(
	card_title: String, card_info: Array, needs := "", extra: Array = []
) -> String:
	var lines: Array[String] = [card_title]
	if needs != "":
		lines.append(needs)
	for entry: Variant in extra:
		var detail := str(entry)
		if detail != "":
			lines.append(detail)
	if card_info.size() >= 1 and str(card_info[0]) != "":
		lines.append(str(card_info[0]))
	var words := Words.new()
	if card_info.size() >= 2 and str(card_info[1]) != "":
		lines.append(words.how_line(str(card_info[1])))
	if card_info.size() >= 3 and str(card_info[2]) != "":
		lines.append(words.needs_line(str(card_info[2])))
	return "\n".join(lines) if lines.size() > 1 else ""


## The hover text, asked afresh each time the pointer rests on the card, so a
## locked card's "now" numbers are current and not those of the menu's setup.
func _get_tooltip(_at_position: Vector2) -> String:
	return card_text(title, info, requirement_now(), _detail_texts())


## The info card: the name, live lock requirement, detail chips, what the item is,
## then the headed parts.
func make_card() -> Control:
	var box := VBoxContainer.new()
	box.theme = HUD_THEME
	box.name = "ItemInfoCard"
	box.add_child(_text(title, &"HudTitle"))
	var needs := requirement_now()
	if needs != "":
		var lock := _text(needs, &"HudAttentionText")
		lock.name = "Requirement"
		box.add_child(lock)
	if not details.is_empty():
		box.add_child(_make_details_row())
	if info.size() >= 1 and str(info[0]) != "":
		box.add_child(_text(str(info[0]), &""))
	if info.size() >= 2 and str(info[1]) != "":
		box.add_child(_text(tr("How it works"), &"HudHint"))
		box.add_child(_text(str(info[1]), &""))
	if info.size() >= 3 and str(info[2]) != "":
		box.add_child(_text(tr("Needs and upkeep"), &"HudHint"))
		box.add_child(_text(str(info[2]), &""))
	return box


func _make_details_row() -> Control:
	var row := HFlowContainer.new()
	row.name = "DetailsRow"
	row.custom_minimum_size.x = CARD_TEXT_W
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 2)
	for entry: Variant in details:
		var line := ""
		var variation := &"HudHint"
		if entry is Array and entry.size() >= 2:
			line = str(entry[0])
			variation = entry[1]
		else:
			line = str(entry)
		if line == "":
			continue
		var chip := Label.new()
		chip.text = line
		chip.theme_type_variation = variation
		var font := HUD_THEME.get_font(&"font", variation)
		var fsize := HUD_THEME.get_font_size(&"font_size", variation)
		var wide := (
			font != null
			and font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > CARD_TEXT_W
		)
		if wide:
			chip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			chip.custom_minimum_size.x = CARD_TEXT_W
		row.add_child(chip)
	return row


func _detail_texts() -> Array[String]:
	var out: Array[String] = []
	for entry: Variant in details:
		if entry is Array and not entry.is_empty():
			out.append(str(entry[0]))
		else:
			out.append(str(entry))
	return out


func _text(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = CARD_TEXT_W
	return label


func _has_popup_content() -> bool:
	if requirement_now() != "":
		return true
	for item_line in _detail_texts():
		if item_line != "":
			return true
	for part: Variant in info:
		if str(part) != "":
			return true
	return false


func _make_custom_tooltip(_for_text: String) -> Object:
	if not _has_popup_content():
		return null
	_card = make_card()
	_card.tree_entered.connect(_place_card, CONNECT_ONE_SHOT | CONNECT_DEFERRED)
	_card.minimum_size_changed.connect(_place_card, CONNECT_DEFERRED)
	return _card


## Where the popup's top-left goes: above the item card at its left edge, kept
## inside the window sideways. `card_size` is the popup's size. The card's
## screen position is the screen transform of its local origin; the popup's own
## height and the gap are screen units already, so the UI scale is not applied to
## them again.
func card_screen_position(card_size: Vector2) -> Vector2i:
	var top := get_screen_transform() * Vector2.ZERO
	var room := get_viewport().get_visible_rect().size.x - card_size.x
	var at := Vector2(
		clampf(top.x, 0.0, maxf(room, 0.0)), maxf(top.y - card_size.y - CARD_GAP, 0.0)
	)
	return Vector2i(at.round())


func _place_card() -> void:
	if not is_inside_tree() or not is_instance_valid(_card) or not _card.is_inside_tree():
		return
	var popup := _card.get_window()
	if popup == null or popup == get_window():
		return
	popup.reset_size()
	popup.position = card_screen_position(Vector2(popup.size))


## tr() is an instance method, so the static card_text() asks a Words.
class Words:
	extends RefCounted

	func how_line(text: String) -> String:
		return tr("How it works: {text}").format({"text": text})

	func needs_line(text: String) -> String:
		return tr("Needs and upkeep: {text}").format({"text": text})
