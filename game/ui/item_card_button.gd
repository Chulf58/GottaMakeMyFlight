class_name ItemCardButton
extends Button
## A build tray's item card with its hover card (decision build-menu-items-show-
## a-hover-card-with-a-description). Hovering the card pops a small info card
## above it: the item's name, what it is, how it works and what it needs or
## costs to run. Nothing extra shows until the pointer rests on the card. The
## info is [about, how it works, needs] from ItemInfo.
##
## The card is a tooltip popup, as MoneySlot's is. It is placed above the item
## card at its left edge from get_screen_transform() of the card's local origin
## (decision a-new-game-starts-with-no-build-tool-selected-refusal-status), not
## from get_global_rect(), which would carry the card's own offset twice. It keeps
## inside the window sideways.

const HUD_THEME := preload("res://ui/hud_theme.tres")
## The headings of the card's second and third parts.
const HOW_HEADING := "How it works"
const NEEDS_HEADING := "Needs and upkeep"
## Width of the info card's text, in layout units.
const CARD_TEXT_W := 280.0
## Space between the item card and the info card above it.
const CARD_GAP := 6.0

## The item's name and its [about, how, needs] text.
var title := ""
var info: Array = []
## Returns why the item is locked, asked each time the hover card is built so
## the numbers in it are current (BuildMenu sets it on a locked card; an empty
## Callable or an empty text leaves the card as it was).
var requirement := Callable()

## The card last handed to the tooltip popup.
var _card: Control


## Gives the card its hover card. An empty `with_info` leaves it with none.
func set_info(with_title: String, with_info: Array) -> void:
	title = with_title
	info = with_info
	tooltip_text = card_text(title, info, requirement_now())


## Why the item is locked right now, "" when it is not.
func requirement_now() -> String:
	return requirement.call() if requirement.is_valid() else ""


## The info as plain text, one part per line under the name, and under the name
## the `needs` line of a locked item; "" with no info and no requirement. It is
## also what makes Godot ask for the hover card at all.
static func card_text(card_title: String, card_info: Array, needs := "") -> String:
	var lines: Array[String] = [card_title]
	if needs != "":
		lines.append(needs)
	if card_info.size() >= 3:
		lines.append(card_info[0])
		lines.append("%s: %s" % [HOW_HEADING, card_info[1]])
		lines.append("%s: %s" % [NEEDS_HEADING, card_info[2]])
	return "\n".join(lines) if lines.size() > 1 else ""


## The hover text, asked afresh each time the pointer rests on the card, so a
## locked card's "now" numbers are current and not those of the menu's setup.
func _get_tooltip(_at_position: Vector2) -> String:
	return card_text(title, info, requirement_now())


## The info card: the name, what the item is, then the two headed parts.
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
	if info.size() >= 3:
		box.add_child(_text(info[0], &""))
		box.add_child(_text(HOW_HEADING, &"HudHint"))
		box.add_child(_text(info[1], &""))
		box.add_child(_text(NEEDS_HEADING, &"HudHint"))
		box.add_child(_text(info[2], &""))
	return box


func _text(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = CARD_TEXT_W
	return label


func _make_custom_tooltip(_for_text: String) -> Object:
	if info.size() < 3 and requirement_now() == "":
		return null
	_card = make_card()
	_card.tree_entered.connect(_place_card, CONNECT_ONE_SHOT | CONNECT_DEFERRED)
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
