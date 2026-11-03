class_name GhostCardNudge
extends RefCounted
## Keeps the build ghost's refusal card (GhostReason) off the HUD (decision
## ghost-refusal-card-nudges-clear-of-hud-panels-and-banners): the card keeps
## its place by the ghost and moves up or down the least that clears every HUD
## panel and banner. A card that cannot clear them either way stays where the
## window edges leave it.

## The clear space kept between the card and a HUD rectangle.
const GAP := 4.0
## A HUD rectangle covering more than this share of the window is a backdrop or
## a fade, not a panel, and does not push the card.
const MAX_COVER := 0.5
## The overlap test grows each obstacle by a hair less than GAP, so a card set
## exactly GAP away is clear however the floats round.
const SLACK := 0.1


## The card's top edge: `card.position.y` moved the least that leaves the card
## clear of `obstacles` by GAP, with the whole card inside `area`. Where no
## place in `area` is clear, the original top edge kept inside `area`.
static func clear_y(card: Rect2, obstacles: Array[Rect2], area: Rect2) -> float:
	var low := area.position.y
	var high := maxf(low, area.end.y - card.size.y)
	var best := clampf(card.position.y, low, high)
	if _is_clear(Rect2(Vector2(card.position.x, best), card.size), obstacles):
		return best
	var tries: Array[float] = []
	for rect in obstacles:
		tries.append(rect.position.y - GAP - card.size.y)
		tries.append(rect.end.y + GAP)
	var moved := false
	var shortest := INF
	for y in tries:
		if y < low or y > high:
			continue
		var move := absf(y - card.position.y)
		if move < shortest and _is_clear(Rect2(Vector2(card.position.x, y), card.size), obstacles):
			shortest = move
			best = y
			moved = true
	return best if moved else clampf(card.position.y, low, high)


## The rectangles (window pixels) of what the HUD draws under every canvas layer
## beside `card` or beside an ancestor of it: the panels, buttons, banners and
## labels MissMarkers.draws_something() finds. Invisible controls, layout
## containers that draw nothing, the card's own layer and any rectangle covering
## most of the window are left out. A panel or button is not walked into.
static func hud_rects(card: Control) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var view := card.get_viewport().get_visible_rect().get_area()
	var own := card.get_parent()
	var node: Node = card
	while node != null and node.get_parent() != null:
		node = node.get_parent()
		for child in node.get_children():
			if child is CanvasLayer and (child as CanvasLayer).visible and child != own:
				_collect(child, card, own, view, rects)
	return rects


static func _collect(
	parent: Node, card: Control, own: Node, view: float, rects: Array[Rect2]
) -> void:
	for child in parent.get_children():
		if child == own or child == card:
			continue
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		if child is Control:
			var control := child as Control
			if MissMarkers.draws_something(control) and control.size.x * control.size.y > 0.0:
				var rect := (
					control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)
				)
				if rect.get_area() <= view * MAX_COVER:
					rects.append(rect)
				if control is Panel or control is PanelContainer or control is BaseButton:
					continue
		_collect(child, card, own, view, rects)


static func _is_clear(card: Rect2, obstacles: Array[Rect2]) -> bool:
	for rect in obstacles:
		if card.intersects(rect.grow(GAP - SLACK)):
			return false
	return true
