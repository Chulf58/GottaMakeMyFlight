class_name BottomDocks
extends RefCounted
## Unified bottom-edge and corner clearance coordinator for the HUD (decisions
## hud-grid-and-rails-one-spacing-grid-centred-top-row-right-ra and
## hud-layout-templates-tab-refinement-320-px-right-rail-compac).
## Places the bottom-left and bottom-right docks beside the centred build bar
## (or lifts them a bar height above it when the bar leaves no room), and
## gives LeftColumn, PassengerInspect, FollowCard, DebugPanel and AlertStack
## one shared source of truth for floor and rail stop lines.

## The wider of the two docks: the Templates dock (a 104 px button in its card).
const DOCK_W := 112.0
## Controls that grow up from the bottom-left corner above Templates (the
## inspect card, the follow card): LeftColumn cards stop a GAP above them.
const LEFT_FLOOR_GROUP := &"left_column_floor"
## Controls that grow up from the bottom-right corner (DebugCorner, DebugPanel):
## AlertStack stops GROUP_GAP above them.
const RIGHT_FLOOR_GROUP := &"right_rail_floor"


## Whether the docks stand beside a bar `bar_width` wide in a layer `layer_width` wide.
static func beside_bar(layer_width: float, bar_width: float) -> bool:
	var side := (layer_width - bar_width) / 2.0
	return side >= float(HudLayout.MARGIN + HudLayout.GROUP_GAP) + DOCK_W


## How far up from the screen's bottom edge a dock's bottom edge is.
static func bottom(beside: bool) -> float:
	var base := float(HudLayout.MARGIN)
	return base if beside else base + HudLayout.BAR_H + HudLayout.GAP


## The y of the docks' top edge in a layer `layer` big, whichever row they stand
## on: what stands above them in the left column ends a GAP higher (LeftColumn).
static func top(layer: Vector2, bar_width: float) -> float:
	return layer.y - bottom(beside_bar(layer.x, bar_width)) - HudLayout.BAR_H


## How far up from the bottom edge bottom-left corner cards (PassengerInspect,
## FollowCard) start: a GAP above the bar / Templates dock when beside the bar,
## or a GAP above the lifted Templates dock when not beside the bar.
static func left_floor_bottom(layer_width: float, bar_width: float) -> float:
	return bottom(beside_bar(layer_width, bar_width)) + HudLayout.BAR_H + HudLayout.GAP


## Maximum width left of BuildMenu's centred column for bottom-left corner cards.
static func left_corner_width(layer_width: float, min_w: float, max_w: float) -> float:
	var room := (
		(layer_width - float(HudLayout.TRAY_W)) / 2.0
		- float(HudLayout.MARGIN + HudLayout.GROUP_GAP)
	)
	return clampf(room, min_w, max_w)


## Lowest y a LeftColumn card starting at `top_y` may reach: a GAP above the
## bottom docks and above any visible LEFT_FLOOR_GROUP card under the column.
static func left_floor_y(tree: SceneTree, top_y: float, layer: Vector2, bar_width: float) -> float:
	var floor_y := top(layer, bar_width) - HudLayout.GAP
	var column := Rect2(HudLayout.MARGIN, top_y, HudLayout.LIST_W, layer.y)
	for node in tree.get_nodes_in_group(LEFT_FLOOR_GROUP) if tree != null else []:
		var card := node as Control
		if card == null or not card.is_visible_in_tree():
			continue
		var rect := card.get_global_rect()
		if rect.intersects(column):
			floor_y = minf(floor_y, rect.position.y - HudLayout.GAP)
	return floor_y


## Lowest screen y AlertStack may reach on the right rail: GROUP_GAP above the
## category bar (or the open build tray stack) and GROUP_GAP above any visible
## RIGHT_FLOOR_GROUP control (DebugCorner, DebugPanel) inside the rail's x-band.
static func right_stop_y(
	tree: SceneTree, layer: Vector2, tray_open: bool, stack_top: float
) -> float:
	var below := stack_top if tray_open else float(HudLayout.MARGIN + HudLayout.BAR_H)
	var stop := layer.y - below - HudLayout.GROUP_GAP
	var rail_band := Rect2(
		layer.x - float(HudLayout.MARGIN + HudLayout.RAIL_W), 0.0, float(HudLayout.RAIL_W), layer.y
	)
	for node in tree.get_nodes_in_group(RIGHT_FLOOR_GROUP) if tree != null else []:
		var card := node as Control
		if card == null or not card.is_visible_in_tree():
			continue
		var rect := card.get_global_rect()
		if rect.has_area() and rect.intersects(rail_band):
			stop = minf(stop, rect.position.y - HudLayout.GROUP_GAP)
	return stop
