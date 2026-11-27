class_name BottomDocks
extends RefCounted
## Unified bottom-edge and corner clearance coordinator for the HUD (decisions
## hud-grid-and-rails-one-spacing-grid-centred-top-row-right-ra and
## hud-layout-templates-tab-refinement-320-px-right-rail-compac).
## Places the bottom-left and bottom-right docks beside the centred build bar
## (or lifts them a bar height above it when the bar leaves no room), and
## gives LeftColumn, PassengerInspect, FollowCard, DebugPanel and AlertStack
## one shared source of truth for floor and rail stop lines.

## Maximum dock width reserved beside the centred CategoryBar (DebugCorner bottom-right).
const DOCK_W := 112.0
## Controls that grow up from the bottom-left corner (the inspect card, the
## follow card): LeftColumn cards stop a GAP above them.
const LEFT_FLOOR_GROUP := &"left_column_floor"
## Controls that grow up from the bottom-right corner (DebugCorner, DebugPanel):
## AlertStack stops GROUP_GAP above them.
const RIGHT_FLOOR_GROUP := &"right_rail_floor"
## Wide bottom-centre popups (StaffCard) that right-floor cards lift above on
## narrow viewports when they overlap horizontally.
const BOTTOM_STACK_GROUP := &"bottom_centre_stack"


## Whether the right dock stands beside a bar `bar_width` wide in a layer `layer_width` wide.
static func beside_bar(layer_width: float, bar_width: float) -> bool:
	var side := (layer_width - bar_width) / 2.0
	return side >= float(HudLayout.MARGIN + HudLayout.GROUP_GAP) + DOCK_W


## Whether a bottom-left panel `left_width` wide at MARGIN clears the centred bar
## `bar_width` wide by at least GROUP_GAP (defaults to left_corner_width).
static func left_beside_bar(layer_width: float, bar_width: float, left_width: float = -1.0) -> bool:
	var side := (layer_width - bar_width) / 2.0
	var card_w := left_corner_width(layer_width, 160.0, 288.0) if left_width < 0.0 else left_width
	return side >= float(HudLayout.MARGIN + HudLayout.GROUP_GAP) + card_w


## How far up from the screen's bottom edge a dock's bottom edge is.
static func bottom(beside: bool) -> float:
	var base := float(HudLayout.MARGIN)
	return base if beside else base + HudLayout.BAR_H + HudLayout.GAP


## The y of the left floor stop in a layer `layer` big (before LEFT_FLOOR_GROUP cards).
static func top(layer: Vector2, bar_width: float) -> float:
	return layer.y - left_floor_bottom(layer.x, bar_width, HudLayout.LIST_W)


## How far up from the bottom edge bottom-left corner cards (PassengerInspect,
## FollowCard) start: at HudLayout.MARGIN when horizontally clear of CategoryBar,
## or a GAP above CategoryBar when viewport width brings the bar within GROUP_GAP.
static func left_floor_bottom(
	layer_width: float, bar_width: float, left_width: float = -1.0
) -> float:
	var clear := left_beside_bar(layer_width, bar_width, left_width)
	return bottom(clear)


## Maximum width left of BuildMenu's centred column for bottom-left corner cards.
static func left_corner_width(layer_width: float, min_w: float, max_w: float) -> float:
	var room := (
		(layer_width - float(HudLayout.TRAY_W)) / 2.0
		- float(HudLayout.MARGIN + HudLayout.GROUP_GAP)
	)
	return clampf(room, min_w, max_w)


## Lowest y a LeftColumn card starting at `top_y` may reach: a GAP above the
## bottom floor (or lifted bar) and above any visible LEFT_FLOOR_GROUP card under the column.
static func left_floor_y(tree: SceneTree, top_y: float, layer: Vector2, bar_width: float) -> float:
	var floor_y := top(layer, bar_width)
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
## RIGHT_FLOOR_GROUP control (DebugCorner, DebugPanel, PassengerInspect) inside
## the rail's x-band.
static func right_stop_y(
	tree: SceneTree, layer: Vector2, tray_open: bool, stack_top: float
) -> float:
	var below := stack_top if tray_open else float(HudLayout.MARGIN + HudLayout.BAR_H)
	var stop := layer.y - below - HudLayout.GROUP_GAP
	var rail_band := Rect2(
		layer.x - float(HudLayout.MARGIN + HudLayout.RAIL_W), 0.0, float(HudLayout.RAIL_W), layer.y
	)
	for node in tree.get_nodes_in_group(BOTTOM_STACK_GROUP) if tree != null else []:
		var stack_card := node as Control
		if stack_card == null or not stack_card.is_visible_in_tree():
			continue
		var stack_rect := stack_card.get_global_rect()
		if stack_rect.has_area() and stack_rect.intersects(rail_band):
			stop = minf(stop, stack_rect.position.y - HudLayout.GROUP_GAP)
	for node in tree.get_nodes_in_group(RIGHT_FLOOR_GROUP) if tree != null else []:
		var card := node as Control
		if card == null or not card.is_visible_in_tree():
			continue
		var rect := card.get_global_rect()
		if rect.has_area() and rect.intersects(rail_band):
			stop = minf(stop, rect.position.y - HudLayout.GROUP_GAP)
	return stop


## Bottom offset from viewport bottom for a right-anchored inspect card
## (`card_width` wide at MARGIN from right edge): sits at MARGIN when clear of
## CategoryBar, BuildTray/StatusCard/StaffCard, and any other RIGHT_FLOOR_GROUP
## control (such as DebugCorner/DebugPanel), lifting GAP above whichever sits
## under its x-band.
static func right_floor_bottom(
	tree: SceneTree,
	layer: Vector2,
	card_width: float,
	bar_width: float,
	tray_open: bool,
	stack_top: float,
	ignore: Control = null
) -> float:
	var bottom_y := float(HudLayout.MARGIN)
	var card_left := layer.x - float(HudLayout.MARGIN) - card_width
	if bar_width > 0.0:
		var bar_right := (layer.x + bar_width) / 2.0
		if bar_right + float(HudLayout.GROUP_GAP) > card_left:
			bottom_y = maxf(bottom_y, float(BuildMenu.MARGIN + BuildMenu.BAR_H + HudLayout.GAP))
	var stack_right := (layer.x + float(HudLayout.TRAY_W)) / 2.0
	if tray_open and stack_right + float(HudLayout.GROUP_GAP) > card_left:
		bottom_y = maxf(bottom_y, stack_top + float(HudLayout.GAP))
	elif stack_top > float(BuildMenu.MARGIN + BuildMenu.BAR_H):
		var col_right := (layer.x + float(BuildMenu.COLUMN_W)) / 2.0
		if col_right + float(HudLayout.GROUP_GAP) > card_left:
			bottom_y = maxf(bottom_y, stack_top + float(HudLayout.GAP))
	for node in tree.get_nodes_in_group(BOTTOM_STACK_GROUP) if tree != null else []:
		var stack_card := node as Control
		if stack_card == null or not stack_card.is_visible_in_tree():
			continue
		var stack_rect := stack_card.get_global_rect()
		if stack_rect.has_area() and stack_rect.end.x + float(HudLayout.GROUP_GAP) > card_left:
			bottom_y = maxf(bottom_y, layer.y - stack_rect.position.y + float(HudLayout.GAP))
	for node in tree.get_nodes_in_group(RIGHT_FLOOR_GROUP) if tree != null else []:
		var other := node as Control
		if other == null or other == ignore or not other.is_visible_in_tree():
			continue
		var rect := other.get_global_rect()
		if rect.has_area() and rect.end.x > card_left and rect.position.x < layer.x:
			bottom_y = maxf(bottom_y, layer.y - rect.position.y + float(HudLayout.GAP))
	return bottom_y
