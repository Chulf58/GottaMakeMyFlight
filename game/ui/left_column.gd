class_name LeftColumn
extends RefCounted
## The HUD's top-left column (decisions hud-grid-and-rails-one-spacing-grid-centred-
## top-row-right-ra, part 4, and checklist-card-moves-to-the-top-left-column-
## slim-at-304-px-t): the Mood, Departures and Hints toggles stacked on the
## margin under the money row, then the departures list, then the checklist or
## first-time hint card. Every number is HudLayout's. The buttons and the cards
## live in different scenes, so this holds the one place each takes its slot.

## The group the departures list joins, so a card finds where the list ends.
const LIST_GROUP := &"left_column_list"
## The group the checklist and hint card joins, so the list leaves it room.
const CARD_GROUP := &"left_column_card"
## The group a card of its own size (the first-time hint card) joins: the list
## leaves it the height it has now, not CARD_RESERVE.
const HINT_GROUP := &"left_column_hint"
## The Departures toggle, and the Planner toggle that sits a GAP right of it
## however wide a translation makes it (board T10).
const DEPARTURES_TOGGLE_GROUP := &"left_column_departures_toggle"
const PLANNER_TOGGLE_GROUP := &"left_column_planner_toggle"
## Every column toggle joins this with META_SLOT, so list_top() collapses hidden
## rows (such as Hints) dynamically.
const TOGGLE_ROW_GROUP := &"left_column_toggles"
const META_SLOT := &"left_column_slot"
## A card that grows up from the bottom-left (FollowCard): while one shows over
## the column, the column's cards stop a GAP above it.
const FLOOR_GROUP := BottomDocks.LEFT_FLOOR_GROUP
## What the list leaves the card under it when the card shows: the card's padding,
## its title, one line and a "+N more" line.
const CARD_RESERVE := 136.0

## The toggles' slots, top to bottom.
const SLOT_MOOD := 0
const SLOT_DEPARTURES := 1
const SLOT_HINTS := 2
const SLOTS := 3

## Under the money row (which is BUTTON_H high on the margin), one group gap.
const TOP := HudLayout.MARGIN + HudLayout.BUTTON_H + HudLayout.GROUP_GAP
## Full 3-slot LIST_TOP constant (when Mood, Departures and Hints are all shown).
const LIST_TOP := TOP + SLOTS * (HudLayout.BUTTON_H + HudLayout.GAP)


## The x a GAP right of the first visible control in `group`, and never left of
## `least` (where it sits while that control fits its grid slot or is missing).
static func right_of(tree: SceneTree, group: StringName, least: float) -> float:
	var control := tree.get_first_node_in_group(group) as Control if tree != null else null
	if control == null or not control.is_visible_in_tree():
		return least
	return maxf(least, control.get_global_rect().end.x + HudLayout.GAP)


## The x a GAP right of every visible left-column toggle or card, and never
## left of `least`.
static func clear_right(tree: SceneTree, least: float) -> float:
	var x := least
	if tree == null:
		return x
	for group in [
		TOGGLE_ROW_GROUP,
		DEPARTURES_TOGGLE_GROUP,
		PLANNER_TOGGLE_GROUP,
		LIST_GROUP,
		CARD_GROUP,
		HINT_GROUP,
	]:
		for node in tree.get_nodes_in_group(group):
			var control := node as Control
			if control != null and control.is_visible_in_tree():
				x = maxf(x, control.get_global_rect().end.x + HudLayout.GAP)
	return x


## The y of toggle slot `slot`, in layout pixels.
static func slot_top(slot: int) -> float:
	return float(TOP + slot * (HudLayout.BUTTON_H + HudLayout.GAP))


## Where the departures list (and collapsed card slot) starts: a GAP below the
## lowest visible column toggle, collapsing hidden rows (SLOT_HINTS) instead of
## leaving a dead 48 px gap.
static func list_top(tree: SceneTree) -> float:
	var bottom := slot_top(SLOT_DEPARTURES) + float(HudLayout.BUTTON_H + HudLayout.GAP)
	if tree == null:
		return bottom
	for node in tree.get_nodes_in_group(TOGGLE_ROW_GROUP):
		var control := node as Control
		if control == null or not control.is_visible_in_tree():
			continue
		var slot := int(control.get_meta(META_SLOT, -1))
		var end_y := (
			slot_top(slot) + maxf(control.size.y, control.custom_minimum_size.y)
			if slot >= 0
			else (
				control.global_position.y
				+ maxf(control.size.y, control.get_combined_minimum_size().y)
			)
		)
		bottom = maxf(bottom, end_y + HudLayout.GAP)
	return bottom


## Gives `button` the column's toggle size.
static func size_toggle(button: Button) -> void:
	button.custom_minimum_size = Vector2(HudLayout.TOGGLE_W, HudLayout.BUTTON_H)


## Anchors `card` to the column, LIST_W wide, growing down from list_top(). The
## first-time hint card and the checklist card both sit in this slot.
static func dock_card(card: Control) -> void:
	var top := list_top(card.get_tree() if card.is_inside_tree() else null)
	card.anchor_left = 0.0
	card.anchor_right = 0.0
	card.anchor_top = 0.0
	card.anchor_bottom = 0.0
	card.offset_left = HudLayout.MARGIN
	card.offset_right = HudLayout.MARGIN + HudLayout.LIST_W
	card.offset_top = top
	card.offset_bottom = top
	card.grow_horizontal = Control.GROW_DIRECTION_END
	card.grow_vertical = Control.GROW_DIRECTION_END


## The y a card takes now: under the departures list while it is open, under the
## visible toggles otherwise.
static func card_top(tree: SceneTree) -> float:
	if tree == null:
		return list_top(null)
	var list := tree.get_first_node_in_group(LIST_GROUP) as Control
	if list == null or not list.is_visible_in_tree():
		return list_top(tree)
	return list.global_position.y + list.get_combined_minimum_size().y + HudLayout.GAP


## The y a first-time hint card takes now: under any visible checklist card
## (CARD_GROUP), or at card_top() when none is showing.
static func hint_top(tree: SceneTree) -> float:
	var top := card_top(tree)
	if tree == null:
		return top
	for node in tree.get_nodes_in_group(CARD_GROUP):
		var control := node as Control
		if control == null or not control.is_visible_in_tree():
			continue
		var height := maxf(control.size.y, control.get_combined_minimum_size().y)
		top = maxf(top, control.global_position.y + height + HudLayout.GAP)
	return top


## Height plus gap reserved under the checklist card for any visible hint card.
static func hint_reserve(tree: SceneTree) -> float:
	if tree == null:
		return 0.0
	var reserve := 0.0
	for node in tree.get_nodes_in_group(HINT_GROUP):
		var control := node as Control
		if control == null or not control.is_visible_in_tree():
			continue
		reserve = maxf(reserve, control.get_combined_minimum_size().y + HudLayout.GAP)
	return reserve


## Moves `card` to card_top() (or hint_top() for a hint card); the card's owner
## calls it every frame.
static func follow(card: Control) -> void:
	var tree := card.get_tree()
	var top := hint_top(tree) if card.is_in_group(HINT_GROUP) else card_top(tree)
	if not is_equal_approx(card.offset_top, top):
		card.offset_top = top
		card.offset_bottom = top


## The height a card at `top` may take in a layer `layer` big: down to a GAP above
## the Templates dock (BottomDocks) and any bottom-left floor card (PassengerInspect,
## FollowCard) under the column.
static func room_below(top: float, layer: Vector2, bar_width: float) -> float:
	var tree := Engine.get_main_loop() as SceneTree
	var bottom := BottomDocks.left_floor_y(tree, top, layer, bar_width)
	return maxf(0.0, bottom - top)


## The height the departures list may take: the room under the toggles, less what
## the cards under it need while showing and the gaps between.
static func list_room(tree: SceneTree, layer: Vector2, bar_width: float) -> float:
	var card_need := 0.0
	for card in tree.get_nodes_in_group(CARD_GROUP):
		var control := card as Control
		if control == null or not control.is_visible_in_tree():
			continue
		if control.get_node_or_null("Checklist") != null:
			card_need = maxf(card_need, CARD_RESERVE)
		else:
			card_need = maxf(card_need, control.get_combined_minimum_size().y)
	var hint_need := 0.0
	for card in tree.get_nodes_in_group(HINT_GROUP):
		if (card as Control).is_visible_in_tree():
			hint_need = maxf(hint_need, (card as Control).get_combined_minimum_size().y)
	var need := card_need + hint_need
	if card_need > 0.0 and hint_need > 0.0:
		need += HudLayout.GAP
	var room := room_below(list_top(tree), layer, bar_width)
	if need > 0.0:
		room -= need + HudLayout.GAP
	return maxf(0.0, room)
