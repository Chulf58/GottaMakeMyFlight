class_name HudRects
extends RefCounted
## The rectangles (screen pixels) of what the HUD draws, for world-space labels
## that keep clear of it (MissMarkers' lane-hint captions, RoomView's room
## labels).


## The Controls under every canvas layer beside `from` or beside an ancestor of
## it, found by MissMarkers.draws_something(), scaled by `to_output` (layout
## coordinates to screen pixels). Invisible ones and layout containers that draw
## nothing are not counted, however large; a drawn control is, also one spanning
## the view. A counted panel or button is not walked into: its children lie
## inside it.
static func collect(from: Node, to_output: float) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var scale := Transform2D().scaled(Vector2(to_output, to_output))
	var node: Node = from
	while node != null and node.get_parent() != null:
		node = node.get_parent()
		for child in node.get_children():
			if child is CanvasLayer and (child as CanvasLayer).visible:
				_collect(child, scale, rects)
	return rects


static func _collect(parent: Node, scale: Transform2D, rects: Array[Rect2]) -> void:
	for child in parent.get_children():
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		if child is Control:
			var control := child as Control
			if MissMarkers.draws_something(control) and control.size.x * control.size.y > 0.0:
				var rect := (
					scale
					* control.get_global_transform_with_canvas()
					* Rect2(Vector2.ZERO, control.size)
				)
				rects.append(rect)
				if MissMarkers.is_box(control):
					continue
		_collect(child, scale, rects)
