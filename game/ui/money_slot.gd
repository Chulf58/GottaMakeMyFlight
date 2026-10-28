class_name MoneySlot
extends PanelContainer
## The money slot's hover card (HUD 2/7, decision money-hover-design-
## categorised-wallet-transactions-feed-a-sa, point 5). Hovering the slot shows
## today's money from the DayLedger: airline fees, shops, wages paid and the
## operating result; then building (net), the rescue grant and the cash change
## today; and owed wages, in the attention style, while some are owed. After a
## load of a save that held no ledger the card is headed "Since load".
##
## It follows the ledger's changed signal and the settlement's owed wages, not
## Wallet.changed: a credit that owed wages take whole leaves the balance as it
## was but still changes the card. A card already open is filled again in
## place and its popup resized to fit, so it never shows stale totals. The
## card has no on/off setting (decision
## hud-steal-list-self-clearing-alert-cards-money-hover-departu). With no
## ledger the slot has no card.

const ATTENTION := &"HudAttentionText"
## The first rows are the operating result and its parts; a rule follows them.
const OPERATING_ROWS := 4
## The grid's theme type: room between a label and its value.
const GRID := &"HudMoneyGrid"
## Space between the slot and the card opened under it.
const CARD_GAP := 6.0

var ledger: DayLedger
## Optional: without it no owed wages are shown.
var settlement: Settlement

## The card last handed to the tooltip popup; refilled while it is shown.
var _card: Control


## Shows `day_ledger`'s totals and `with_settlement`'s owed wages, and follows
## both.
func watch(day_ledger: DayLedger, with_settlement: Settlement) -> void:
	ledger = day_ledger
	settlement = with_settlement
	if ledger != null and not ledger.changed.is_connected(refresh):
		ledger.changed.connect(refresh)
	if settlement != null and not settlement.wages_owed_changed.is_connected(_on_wages_owed):
		settlement.wages_owed_changed.connect(_on_wages_owed)
	refresh()


func refresh() -> void:
	tooltip_text = card_text()
	if ledger == null or not is_instance_valid(_card) or not _card.is_inside_tree():
		return
	_fill(_card, heading(ledger), rows(ledger, _owed()))
	var popup := _card.get_window() as Popup
	if popup != null:
		popup.reset_size()


## The card as plain text, one "Label  value" row per line under the
## heading; "" with no ledger.
func card_text() -> String:
	if ledger == null:
		return ""
	var lines: Array[String] = [heading(ledger)]
	for row in rows(ledger, _owed()):
		lines.append("%s  %s" % [row[0], row[1]])
	return "\n".join(lines)


## "Today", or "Since load" while the ledger counts from a load.
static func heading(day_ledger: DayLedger) -> String:
	return "Since load" if day_ledger.is_since_load() else "Today"


## The card's rows as [label, value, theme type variation].
static func rows(day_ledger: DayLedger, owed: int) -> Array:
	var cash_label := (
		"Cash change since load" if day_ledger.is_since_load() else "Cash change today"
	)
	var out: Array = [
		["Airline fees", signed(day_ledger.amount(Wallet.Category.FEES)), &""],
		["Shops", signed(day_ledger.amount(Wallet.Category.SHOP)), &""],
		["Wages paid", signed(-day_ledger.wages_paid()), &""],
		["Operating result", signed(day_ledger.operating_result()), &""],
		["Building", signed(day_ledger.amount(Wallet.Category.BUILD)), &""],
		["Rescue grant", signed(day_ledger.amount(Wallet.Category.GRANT)), &""],
		[cash_label, signed(day_ledger.cash_change()), &""],
	]
	if owed > 0:
		out.append(["Owed wages", str(owed), ATTENTION])
	return out


## "+300", "-90" or "0".
static func signed(value: int) -> String:
	return "+%d" % value if value > 0 else str(value)


## The hover card: the heading, then a two-column grid of the rows with a
## rule after the operating result.
func make_card(title: String, card_rows: Array) -> Control:
	var box := VBoxContainer.new()
	box.theme = BuildMenu.HUD_THEME
	_fill(box, title, card_rows)
	return box


## Replaces the card's contents. Old children are detached before they are
## freed, so nothing reads them in between.
func _fill(box: Control, title: String, card_rows: Array) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var head := Label.new()
	head.text = title
	head.theme_type_variation = &"HudTitle"
	box.add_child(head)
	var grid := _grid()
	box.add_child(grid)
	for i in card_rows.size():
		if i == OPERATING_ROWS:
			box.add_child(HSeparator.new())
			grid = _grid()
			box.add_child(grid)
		var row: Array = card_rows[i]
		var label := Label.new()
		label.text = row[0]
		label.theme_type_variation = row[2]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(label)
		var value := Label.new()
		value.text = row[1]
		value.theme_type_variation = row[2]
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value)


func _make_custom_tooltip(_for_text: String) -> Object:
	if ledger == null:
		return null
	_card = make_card(heading(ledger), rows(ledger, _owed()))
	_card.tree_entered.connect(_place_card, CONNECT_ONE_SHOT | CONNECT_DEFERRED)
	return _card


## Where the card's top-left sits, in the canvas the slot is drawn in: under
## the slot at its left edge, so it covers neither the money figure nor the
## rating stars beside the slot. Godot would open it at the pointer, over both.
func card_origin() -> Vector2:
	var slot := get_global_rect()
	return Vector2(slot.position.x, slot.end.y + CARD_GAP)


## Moves the tooltip popup holding the card to card_origin(), as a screen
## position.
func _place_card() -> void:
	if not is_inside_tree() or not is_instance_valid(_card) or not _card.is_inside_tree():
		return
	var popup := _card.get_window()
	if popup == null or popup == get_window():
		return
	popup.position = Vector2i(get_screen_transform() * card_origin())


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.theme_type_variation = GRID
	return grid


func _owed() -> int:
	return settlement.wages_owed() if settlement != null else 0


func _on_wages_owed(_owed_now: int) -> void:
	refresh()
