class_name SelectReveal
extends RefCounted
## Whether the camera must move for a selected built item, and where to
## (decision clicking-a-built-desk-outside-build-mode-moves-the-camera-on).
## Selecting an item with no build tool leaves the camera still while the item
## is fully on screen and clear of the panels, the inspect window that opens
## included. Otherwise the focus moves along the ground just far enough that
## the item's screen box lies inside the screen share the panels leave free.
## Pure geometry: PassengerHud supplies the eye, the item's floor rectangle and
## the panel rectangles, and sends the camera to the focus returned.

## How far above the floor an item's box reaches, in metres: a desk.
const ITEM_HEIGHT := 1.2
## Space kept around the item's box when it is tested against the panels, in
## pixels.
const MARGIN := 12.0


## The screen box that holds `world` (an xz rectangle in metres) standing on the
## plane at `floor_y`, as seen from `eye`, grown by MARGIN. Empty when any
## corner is behind the eye.
static func screen_box(eye: Camera3D, world: Rect2, floor_y: float) -> Rect2:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var corners := [
		world.position,
		world.end,
		Vector2(world.position.x, world.end.y),
		Vector2(world.end.x, world.position.y)
	]
	for corner in corners:
		for y in [floor_y, floor_y + ITEM_HEIGHT]:
			var point := Vector3(corner.x, y, corner.y)
			if eye.is_position_behind(point):
				return Rect2()
			var px := eye.unproject_position(point)
			low = low.min(px)
			high = high.max(px)
	return Rect2(low, high - low).grow(MARGIN)


## The pixels `box` must move to be on `viewport` and clear of `panels`; zero
## when it already is. It goes into the largest rectangle the panels leave
## free (PanelRoom.free_rect) by the shortest move, or centres there when it is
## too big to fit.
static func shift_for(box: Rect2, viewport: Rect2, panels: Array[Rect2]) -> Vector2:
	if viewport.encloses(box) and not _meets_any(box, panels):
		return Vector2.ZERO
	# Aim a margin inside the free space: the box is measured from where the
	# camera stands now, and perspective changes it a little once the camera moves.
	var free := PanelRoom.free_rect(viewport, panels).grow(-MARGIN)
	if box.size.x > free.size.x or box.size.y > free.size.y:
		return free.get_center() - box.get_center()
	var shift := Vector2.ZERO
	shift.x = maxf(free.position.x - box.position.x, 0.0) + minf(free.end.x - box.end.x, 0.0)
	shift.y = maxf(free.position.y - box.position.y, 0.0) + minf(free.end.y - box.end.y, 0.0)
	return shift


## The focus the camera should move to, or null when it should stay put. `focus`
## is where it looks on the ground now; `world` is the item's floor rectangle.
static func focus_target(
	eye: Camera3D,
	focus: Vector3,
	world: Rect2,
	floor_y: float,
	viewport: Rect2,
	panels: Array[Rect2]
) -> Variant:
	if not world.has_area():
		return null
	var box := screen_box(eye, world, floor_y)
	if not box.has_area():
		return null
	var shift := shift_for(box, viewport, panels)
	if shift == Vector2.ZERO:
		return null
	var centre := Vector3(world.get_center().x, floor_y, world.get_center().y)
	var seen_at := eye.unproject_position(centre) + shift
	var landing: Variant = BuildMode.ground_point(
		eye.project_ray_origin(seen_at), eye.project_ray_normal(seen_at), floor_y
	)
	if landing == null:
		return null
	var move: Vector3 = centre - (landing as Vector3)
	return Vector3(focus.x + move.x, focus.y, focus.z + move.z)


static func _meets_any(box: Rect2, panels: Array[Rect2]) -> bool:
	for panel in panels:
		if panel.intersects(box):
			return true
	return false
