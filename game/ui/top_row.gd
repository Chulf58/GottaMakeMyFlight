class_name TopRow
extends RefCounted
## The HUD's centred top row (decision hud-grid-and-rails-one-spacing-grid-
## centred-top-row-right-ra, part 2): three TOGGLE_W x BUTTON_H slots, GAP
## apart, centred on the viewport with their tops on MARGIN. The slots are the
## Build mode sign, Runway and Offers, left to right. The sign slot stays
## reserved outside build mode, so Runway and Offers never move when build
## mode toggles. Each owner sits in its own CanvasLayer and places itself from
## these numbers; a sheet opened from the row is SHEET_W wide, starts at the
## row's left edge and opens under the row, and opening one closes the other.

const SIGN_SLOT := 0
const RUNWAY_SLOT := 1
const OFFERS_SLOT := 2
const SLOT_COUNT := 3
## A sheet's group: every owner of a sheet joins it, so one open closes the rest.
const SHEET_GROUP := &"top_row_sheets"
## The sheets' CanvasLayer: above the HUD's layer 2, so an open sheet is not
## covered by the checklist card (StaffPanel) or an alert, and below the intro.
const SHEET_LAYER := 3
const SLOT_SIZE := Vector2(HudLayout.TOGGLE_W, HudLayout.BUTTON_H)
const SHEET_W := float(HudLayout.SHEET_W)
const TOP := float(HudLayout.MARGIN)
## Where a sheet opens: under the row, one GAP below the buttons.
const SHEET_TOP := float(HudLayout.MARGIN + HudLayout.BUTTON_H + HudLayout.GAP)

## The widest the rating card gets (stars + "No flights yet" stay inside 200 px),
## so the centred top row keeps full TOGGLE_W slots at 1280 px too.
const RATING_W := 200.0
## The narrowest slot, when the layout is too narrow for three TOGGLE_W slots.
const MIN_SLOT_W := 88.0
## The left-most a sheet starts: right of the top-left column's LIST_W cards
## (DeparturesPanel, PlannerToggle, StaffHintCard, HintCard) by a GAP.
const SHEET_MIN_LEFT := float(HudLayout.MARGIN + HudLayout.LIST_W + HudLayout.GAP)


## The slot width in a layer `layer_width` wide: TOGGLE_W while the row, centred
## on the layer, clears the rating card and the clock panel by a GAP, else the
## widest grid step of three slots whose centred row does (UI scale 1.5 is a
## 1280 px layout, where the slots are 88 wide).
static func slot_width(layer_width: float) -> float:
	var half := minf(layer_width / 2.0 - _span_left(), _span_right(layer_width) - layer_width / 2.0)
	if half * 2.0 >= row_width():
		return float(HudLayout.TOGGLE_W)
	var step := float(HudLayout.UNIT)
	var fit := floorf((half * 2.0 - (SLOT_COUNT - 1) * HudLayout.GAP) / SLOT_COUNT / step) * step
	return maxf(MIN_SLOT_W, fit)


## The row's width: the slots and the gaps between them.
static func row_width(slot_w: float = HudLayout.TOGGLE_W) -> float:
	return SLOT_COUNT * slot_w + (SLOT_COUNT - 1) * HudLayout.GAP


## The row's left edge in a layer `layer_width` wide: the row is always centred.
static func row_left(layer_width: float) -> float:
	return (layer_width - row_width(slot_width(layer_width))) / 2.0


## The sheet's left edge and width in a layer `layer_width` wide: from the row's
## left edge, SHEET_W wide, moved left (never past `min_left`) so it ends a
## GAP before the clock panel. In a layout too narrow to leave a sheet any room
## (the rail starts left of `min_left`) the width is 0 and the sheet is as
## wide as its content.
static func sheet_extent(layer_width: float, min_left := SHEET_MIN_LEFT) -> Vector2:
	var right := _span_right(layer_width)
	if right <= min_left:
		return Vector2(min_left, 0.0)
	var left := clampf(minf(row_left(layer_width), right - SHEET_W), min_left, right)
	return Vector2(left, minf(SHEET_W, right - left))


## The left-most x a top-row sheet may start: SHEET_MIN_LEFT or, when the
## Planner toggle pushes past it, a GAP right of PlannerToggle.
static func sheet_min_left(tree: SceneTree) -> float:
	return LeftColumn.right_of(tree, LeftColumn.PLANNER_TOGGLE_GROUP, SHEET_MIN_LEFT)


## The left edge of `slot` in a layer that is `layer_width` wide.
static func slot_left(slot: int, layer_width: float) -> float:
	return row_left(layer_width) + slot * (slot_width(layer_width) + HudLayout.GAP)


## Puts `control` in `slot` of the row for the layout width of `host`'s viewport.
## The owner calls it again when that viewport's size_changed fires (a UI scale
## change).
static func place_in_slot(control: Control, slot: int, host: Node) -> void:
	var width := _layer_width(host)
	var slot_w := slot_width(width)
	_anchor_top_left(control, slot_left(slot, width), TOP, Vector2(slot_w, HudLayout.BUTTON_H))
	# A narrow slot takes the caption size, so "Offers (12)" stays inside it.
	if slot_w < HudLayout.TOGGLE_W:
		control.add_theme_font_size_override("font_size", HudLayout.CAPTION)
	else:
		control.remove_theme_font_size_override("font_size")


## Puts `sheet` under the row (see sheet_extent). Its height is its content's.
static func place_sheet(sheet: Control, host: Node) -> void:
	var min_left := sheet_min_left(host.get_tree()) if host.is_inside_tree() else SHEET_MIN_LEFT
	var extent := sheet_extent(_layer_width(host), min_left)
	_anchor_top_left(sheet, extent.x, SHEET_TOP, Vector2(extent.y, 0.0))


## Closes every other sheet of the row; call before showing `opening`.
static func close_others(opening: Node) -> void:
	if not opening.is_inside_tree():
		return
	for other in opening.get_tree().get_nodes_in_group(SHEET_GROUP):
		if other != opening and other.has_method("close"):
			other.close()


## True when any open top-row sheet overlaps `rect` (used by AlertStack when a
## narrow viewport forces a sheet across the right rail).
static func sheet_overlaps(tree: SceneTree, rect: Rect2) -> bool:
	if tree == null or not rect.has_area():
		return false
	for node in tree.get_nodes_in_group(SHEET_GROUP):
		if not node.has_method("is_open") or not node.is_open():
			continue
		if not node.has_method("sheet"):
			continue
		var s := node.sheet() as Control
		if s != null and s.is_visible_in_tree() and s.get_global_rect().intersects(rect):
			return true
	return false


static func _anchor_top_left(control: Control, left: float, top: float, extent: Vector2) -> void:
	control.anchor_left = 0.0
	control.anchor_right = 0.0
	control.anchor_top = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = left
	control.offset_right = left + extent.x
	control.offset_top = top
	control.offset_bottom = top + extent.y
	control.grow_horizontal = Control.GROW_DIRECTION_END
	control.grow_vertical = Control.GROW_DIRECTION_END


static func _span_left() -> float:
	return float(HudLayout.MARGIN + HudLayout.MONEY_W + HudLayout.GAP) + RATING_W + HudLayout.GAP


static func _span_right(layer_width: float) -> float:
	return layer_width - HudLayout.MARGIN - HudLayout.RAIL_W - HudLayout.GAP


static func _layer_width(host: Node) -> float:
	return host.get_viewport().get_visible_rect().size.x
