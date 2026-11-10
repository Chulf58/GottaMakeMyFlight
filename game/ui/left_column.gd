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
