class_name GhostBounds
extends RefCounted
## Where BuildMode's build ghost is on screen, for the refusal card beside it
## (GhostReason). A read only: it changes nothing in the ghost or BuildMode.

## The ghost node BuildMode keeps its tinted preview meshes under.
const GHOST_NODE := "Ghost"


## The ghost node of `mode`, or null when it has none.
static func ghost_of(mode: BuildMode) -> Node3D:
	return mode.get_node_or_null(GHOST_NODE) as Node3D if mode != null else null


## The drawn ghost's bounds on screen, in viewport coordinates: every ghost
## mesh's box projected through `camera`. An empty Rect2 while the ghost is
## hidden or holds no mesh, or with no camera. Parts a redraw has queued for
## freeing (they stay children until the frame ends) do not count.
static func screen_rect(ghost: Node3D, camera: Camera3D) -> Rect2:
	if ghost == null or camera == null or not ghost.is_visible_in_tree():
		return Rect2()
	var points := PackedVector2Array()
	for node in ghost.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or _going(mesh, ghost):
			continue
		var box := mesh.global_transform * mesh.get_aabb()
		for i in 8:
			var corner := box.get_endpoint(i)
			if not camera.is_position_behind(corner):
				points.append(camera.unproject_position(corner))
	if points.is_empty():
		return Rect2()
	var rect := Rect2(points[0], Vector2.ZERO)
	for point in points:
		rect = rect.expand(point)
	return rect


## True when `node`, or a parent of it below `ghost`, is queued for freeing.
static func _going(node: Node, ghost: Node3D) -> bool:
	while node != null and node != ghost:
		if node.is_queued_for_deletion():
			return true
		node = node.get_parent()
	return false
