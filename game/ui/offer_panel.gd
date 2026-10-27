class_name OfferPanel
extends CanvasLayer
## Today's airline offers (Economy 6/8b). A button at the top right shows how
## many offers are open; it opens a cream card sheet below it with one card per
## open offer: airline, destination, departure, gate, plane size, booked
## passengers and fee per passenger, with Accept and Decline. Look follows
## decision hud-look-warm-cozy-cream-cards-with-a-dark-outline-toon-pale: cream
## cards, a dark navy outline and text, a Toon accent per element.
##
## Accept asks FlightSim.accept_problem first, so a refusal (a gate clash, say)
## shows its reason on the sheet and the offer stays open; otherwise the board
## turns the offer into a contract. The sheet rebuilds whenever the board
## changes, so midnight expiry and the new day's offers appear on their own.

const SHEET_W := 560.0
const TOP := 12.0
## The panel sits at the top, left of PassengerHud's 440 px flight panel (which
## starts 460 px from the right edge).
const RIGHT_CLEARANCE := 472.0
const CARD_TEXT_W := 380.0
const EMPTY_TEXT := "No offers right now. New offers arrive at midnight."

const PAPER := Color(0.96, 0.93, 0.86)
const CARD_FILL := Color(0.99, 0.97, 0.92)
const NAVY := Color(0.1, 0.13, 0.26)
const TEAL := Color(0.25, 0.68, 0.68)
const YELLOW := Color(1.0, 0.8, 0.3)
const GREEN := Color(0.5, 0.8, 0.45)
const CORAL := Color(0.92, 0.45, 0.4)
const REFUSAL_TEXT := Color(0.72, 0.2, 0.18)

@export var desk: OfferDesk
@export var flights: FlightSim

var _button: Button
var _sheet: PanelContainer
var _cards: VBoxContainer
var _message: Label
var _card_nodes: Dictionary = {}
var _accept_buttons: Dictionary = {}
var _decline_buttons: Dictionary = {}


## The text lines of an offer's card: who and where, when and what plane, and
## the money.
static func card_lines(offer: Dictionary) -> PackedStringArray:
	var minute: int = offer["departure_minute"]
	var time := GameCalendar.clock_text(GameCalendar.tick_at(0, minute))
	var size: String = offer["plane_size"]
	return PackedStringArray(
		[
			"%s to %s" % [offer["airline"], offer["destination"]],
			"Departs %s daily   Gate %s   %s plane" % [time, offer["gate"], size.capitalize()],
			(
				"%d passengers booked   $%d per passenger"
				% [offer["booked_passengers"], offer["fee_per_passenger"]]
			),
		]
	)


static func sheet_style() -> StyleBoxFlat:
	var style := _box(PAPER, NAVY, 3, 10)
	style.set_content_margin_all(10.0)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.3)
	style.shadow_size = 6
	return style


static func card_style() -> StyleBoxFlat:
	var style := _box(CARD_FILL, NAVY, 2, 8)
	style.set_content_margin_all(6.0)
	style.content_margin_left = 10.0
	return style


## A button in the sheet's look: a coloured fill, a navy outline, navy text.
static func style_button(button: Button, fill: Color) -> void:
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", _box(fill, NAVY, 2, 8, 6.0))
	button.add_theme_stylebox_override("hover", _box(fill.lightened(0.25), NAVY, 2, 8, 6.0))
	button.add_theme_stylebox_override("pressed", _box(fill.darkened(0.15), NAVY, 3, 8, 6.0))
	button.add_theme_stylebox_override("disabled", _box(fill.darkened(0.3), NAVY, 2, 8, 6.0))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, NAVY)
	button.add_theme_font_override("font", _bold_font())
	button.add_theme_font_size_override("font_size", 18)


static func _box(
	fill: Color, border: Color, border_width: int, radius: int, margin := 0.0
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	if margin > 0.0:
		style.set_content_margin_all(margin)
	return style


static func _bold_font() -> FontVariation:
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = 0.7
	return font


func _ready() -> void:
	if desk == null or flights == null:
		push_error("OfferPanel: desk and flights must both be set, so nothing is shown")
		return
	layer = 2
	_build()
	desk.board.changed.connect(_refresh)
	_refresh()


func is_open() -> bool:
	return _sheet.visible


func open() -> void:
	_sheet.visible = true


func close() -> void:
	_sheet.visible = false


func toggle_button() -> Button:
	return _button


## Ids of the offers shown, in the order drawn.
func card_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in _card_nodes:
		ids.append(id)
	return ids


func card(id: String) -> Control:
	return _card_nodes.get(id)


func accept_button(id: String) -> Button:
	return _accept_buttons.get(id)


func decline_button(id: String) -> Button:
	return _decline_buttons.get(id)


## All the text on one offer's card.
func card_text(id: String) -> String:
	var lines := PackedStringArray()
	for label in _card_nodes[id].find_children("*", "Label", true, false):
		lines.append((label as Label).text)
	return "\n".join(lines)


## What the sheet says under the cards: the last accept's result or refusal,
## or EMPTY_TEXT when no offer is open.
func message() -> String:
	return _message.text


func _build() -> void:
	_button = Button.new()
	_sheet = PanelContainer.new()
	_cards = VBoxContainer.new()
	_message = Label.new()
	var column := VBoxContainer.new()
	column.name = "OfferColumn"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.custom_minimum_size = Vector2(SHEET_W, 0.0)
	column.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	column.offset_right = -RIGHT_CLEARANCE
	column.offset_left = -RIGHT_CLEARANCE - SHEET_W
	column.offset_top = TOP
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(column)
	_button.name = "OffersButton"
	_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_button.custom_minimum_size = Vector2(170.0, 40.0)
	style_button(_button, TEAL)
	_button.pressed.connect(_on_toggle)
	column.add_child(_button)
	_sheet.name = "OfferSheet"
	_sheet.visible = false
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet.add_theme_stylebox_override("panel", sheet_style())
	column.add_child(_sheet)
	var sheet_column := VBoxContainer.new()
	sheet_column.add_theme_constant_override("separation", 6)
	_sheet.add_child(sheet_column)
	var title := Label.new()
	title.name = "OfferTitle"
	title.text = "Today's offers"
	_style_label(title, 22, NAVY)
	sheet_column.add_child(title)
	_cards.name = "OfferCards"
	_cards.add_theme_constant_override("separation", 6)
	sheet_column.add_child(_cards)
	_message.name = "OfferMessage"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(SHEET_W - 30.0, 0.0)
	_style_label(_message, 16, NAVY)
	sheet_column.add_child(_message)


func _on_toggle() -> void:
	_sheet.visible = not _sheet.visible


## Rebuilds the cards and the button text from the board's open offers.
func _refresh() -> void:
	for node in _card_nodes.values():
		_cards.remove_child(node)
		node.queue_free()
	_card_nodes.clear()
	_accept_buttons.clear()
	_decline_buttons.clear()
	var offers := desk.board.open_offers()
	for offer in offers:
		_add_card(offer)
	_button.text = "Offers (%d)" % offers.size()
	style_button(_button, YELLOW if offers.size() > 0 else TEAL)
	_say(EMPTY_TEXT if offers.is_empty() else "")


func _add_card(offer: Dictionary) -> void:
	var id: String = offer["id"]
	var card_box := PanelContainer.new()
	card_box.name = "Offer_%s" % id
	card_box.add_theme_stylebox_override("panel", card_style())
	_cards.add_child(card_box)
	_card_nodes[id] = card_box
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card_box.add_child(row)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)
	var lines := card_lines(offer)
	for i in lines.size():
		var label := Label.new()
		label.text = lines[i]
		label.custom_minimum_size = Vector2(CARD_TEXT_W, 0.0)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_style_label(label, 21 if i == 0 else 16, NAVY, i == 0)
		texts.add_child(label)
	var buttons := VBoxContainer.new()
	row.add_child(buttons)
	var accept := _card_button("Accept", GREEN, id)
	accept.pressed.connect(_on_accept.bind(id))
	buttons.add_child(accept)
	_accept_buttons[id] = accept
	var decline := _card_button("Decline", CORAL, id)
	decline.pressed.connect(_on_decline.bind(id))
	buttons.add_child(decline)
	_decline_buttons[id] = decline


func _card_button(text: String, fill: Color, id: String) -> Button:
	var button := Button.new()
	button.name = "%s_%s" % [text, id]
	button.text = text
	button.custom_minimum_size = Vector2(110.0, 36.0)
	style_button(button, fill)
	return button


func _on_accept(id: String) -> void:
	var offer := desk.board.offer_of(id)
	var problem := flights.accept_problem(OfferBoard.terms_of(offer))
	if problem != "":
		_say(
			"Can't accept %s to %s: %s" % [offer["airline"], offer["destination"], problem],
			REFUSAL_TEXT
		)
		return
	if desk.board.accept(id, flights):
		_say("Accepted %s to %s" % [offer["airline"], offer["destination"]])


## Shows `text` under the cards, hiding the line when it is empty.
func _say(text: String, color := NAVY) -> void:
	_message.text = text
	_message.visible = text != ""
	_message.add_theme_color_override("font_color", color)


func _on_decline(id: String) -> void:
	desk.board.decline(id)


func _style_label(label: Label, size: int, color: Color, bold := false) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if bold:
		label.add_theme_font_override("font", _bold_font())
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
