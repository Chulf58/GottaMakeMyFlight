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


## The row's width: the slots and the gaps between them.
static func row_width() -> float:
	return float(SLOT_COUNT * HudLayout.TOGGLE_W + (SLOT_COUNT - 1) * HudLayout.GAP)


## The left edge of `slot` in a layer that is `layer_width` wide.
static func slot_left(slot: int, layer_width: float) -> float:
	return (layer_width - row_width()) / 2.0 + slot * (HudLayout.TOGGLE_W + HudLayout.GAP)


## Puts `control` in `slot` of the row with anchors on the layer's centre, so
## the row stays centred when the layer's width changes.
static func place_in_slot(control: Control, slot: int) -> void:
	var left := -row_width() / 2.0 + slot * (HudLayout.TOGGLE_W + HudLayout.GAP)
	_anchor_top_centre(control, left, TOP, SLOT_SIZE)


## Puts `sheet` under the row: SHEET_W wide, starting at the row's left edge.
## Its height is its content's.
static func place_sheet(sheet: Control) -> void:
	_anchor_top_centre(sheet, -row_width() / 2.0, SHEET_TOP, Vector2(SHEET_W, 0.0))


## Closes every other sheet of the row; call before showing `opening`.
static func close_others(opening: Node) -> void:
	if not opening.is_inside_tree():
		return
	for other in opening.get_tree().get_nodes_in_group(SHEET_GROUP):
		if other != opening and other.has_method("close"):
			other.close()


static func _anchor_top_centre(control: Control, left: float, top: float, extent: Vector2) -> void:
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	control.anchor_top = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = left
	control.offset_right = left + extent.x
	control.offset_top = top
	control.offset_bottom = top + extent.y
	control.grow_horizontal = Control.GROW_DIRECTION_END
	control.grow_vertical = Control.GROW_DIRECTION_END
