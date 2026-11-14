class_name LeftColumn
extends RefCounted
## The top-left column (decisions hud-grid-and-rails-one-spacing-grid-centred-
## top-row-right-ra, part 4, and checklist-card-moves-to-the-top-left-column-
## slim-at-304-px-t): the Mood, Departures and Hints toggles and the Reset hints
## button stacked on the margin under the money row, then the departures list,
## then the checklist or first-time hint card. Every number is HudLayout's. The
## buttons and the cards live in different scenes, so this holds the one place
## each takes its slot.

## The group the departures list joins, so a card finds where the list ends.
const LIST_GROUP := &"left_column_list"
## The group the checklist and hint card joins, so the list leaves it room.
const CARD_GROUP := &"left_column_card"
## The group a card of its own size (the first-time hint card) joins: the list
## leaves it the height it has now, not CARD_RESERVE.
const HINT_GROUP := &"left_column_hint"
## What the list leaves the card under it when the card shows: the card's padding,
## its title, one line and a "+N more" line.
const CARD_RESERVE := 136.0

## The toggles' slots, top to bottom.
const SLOT_MOOD := 0
const SLOT_DEPARTURES := 1
const SLOT_HINTS := 2
## Reset hints, the row under Hints (HUD 7/7, board 3bd42402). The slot is kept
## when a run has no hints row (a test or a probe), so the list never moves.
const SLOT_RESET := 3
const SLOTS := 4

## Under the money row (which is BUTTON_H high on the margin), one group gap.
const TOP := HudLayout.MARGIN + HudLayout.BUTTON_H + HudLayout.GROUP_GAP
## Where the departures list starts, under the last column button.
const LIST_TOP := TOP + SLOTS * (HudLayout.BUTTON_H + HudLayout.GAP)


## The y of toggle slot `slot`, in layout pixels.
static func slot_top(slot: int) -> float:
	return float(TOP + slot * (HudLayout.BUTTON_H + HudLayout.GAP))


## Gives `button` the column's toggle size.
static func size_toggle(button: Button) -> void:
	button.custom_minimum_size = Vector2(HudLayout.TOGGLE_W, HudLayout.BUTTON_H)


## Anchors `card` to the column, LIST_W wide, growing down from LIST_TOP. The
## first-time hint card and the checklist card both sit in this slot.
static func dock_card(card: Control) -> void:
	card.anchor_left = 0.0
	card.anchor_right = 0.0
	card.anchor_top = 0.0
	card.anchor_bottom = 0.0
	card.offset_left = HudLayout.MARGIN
	card.offset_right = HudLayout.MARGIN + HudLayout.LIST_W
	card.offset_top = LIST_TOP
	card.offset_bottom = LIST_TOP
	card.grow_horizontal = Control.GROW_DIRECTION_END
	card.grow_vertical = Control.GROW_DIRECTION_END


## The y a card takes now: under the departures list while it is open, under the
## toggles otherwise.
static func card_top(tree: SceneTree) -> float:
	if tree == null:
		return float(LIST_TOP)
	var list := tree.get_first_node_in_group(LIST_GROUP) as Control
	if list == null or not list.is_visible_in_tree():
		return float(LIST_TOP)
	return list.global_position.y + list.get_combined_minimum_size().y + HudLayout.GAP


## Moves `card` to card_top(); the card's owner calls it every frame.
static func follow(card: Control) -> void:
	var top := card_top(card.get_tree())
	if not is_equal_approx(card.offset_top, top):
		card.offset_top = top
		card.offset_bottom = top


## The height a card at `top` may take in a layer `layer` big: down to a GAP above
## the Templates dock (BottomDocks), which the column's x-range always reaches
## (the dock sits on the same margin), so the cards never cover the bar's left
## end or the dock.
static func room_below(top: float, layer: Vector2, bar_width: float) -> float:
	return maxf(0.0, BottomDocks.top(layer, bar_width) - HudLayout.GAP - top)


## The height the departures list may take: the room under the toggles, less what
## the card under it needs while one shows and the gap between. The checklist card
## folds to fit, so it is given CARD_RESERVE; the first-time hint card is kept
## whole, so it is given the height it has. The two share one slot and the larger
## is kept. A scene can hold several hint cards (a test's own), so every one in
## the group is looked at.
static func list_room(tree: SceneTree, layer: Vector2, bar_width: float) -> float:
	var need := 0.0
	for card in tree.get_nodes_in_group(CARD_GROUP):
		if (card as Control).is_visible_in_tree():
			need = maxf(need, CARD_RESERVE)
	for card in tree.get_nodes_in_group(HINT_GROUP):
		if (card as Control).is_visible_in_tree():
			need = maxf(need, (card as Control).get_combined_minimum_size().y)
	var room := room_below(float(LIST_TOP), layer, bar_width)
	if need > 0.0:
		room -= need + HudLayout.GAP
	return maxf(0.0, room)
