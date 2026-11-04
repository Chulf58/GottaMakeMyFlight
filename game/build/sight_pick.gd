class_name SightPick
extends RefCounted
## What the camera's line of sight to a ground point meets first: a placed
## object (seen_object) or a wall edge (seen_wall). The Remove tool picks with
## it (BuildMode._removal_at), and the HUD can pick a built item the same way.

## How far past the pointer's ground point an object box still counts as seen
## (a box's floor face lies on the ground plane itself).
const SIGHT_SLACK_M := 0.001


## The wall edge (WallCutaway.wall_edges form) the camera's line of sight to a
## ground point meets first (WallPick), or an edge whose z is -1 for none, also
## with no camera or the point behind it.
static func seen_wall(
	grid: BuildGrid, view: BuildView, camera: Camera3D, point: Vector3
) -> Vector3i:
	if camera == null or camera.is_position_behind(point):
		return WallPick.NO_EDGE
	var from := camera.project_ray_origin(camera.unproject_position(point))
	return WallPick.first_wall(grid, view, from, point)


## The object the camera's line of sight to a ground point meets first, or 0
## (also 0 with no camera, or the point behind it). Each object is a box over
## its footprint as tall as it is drawn (BuildView.pick_height). A tall object
## hides the ground behind it on screen, so a click on it picks a ground point
## beyond it, maybe beside a wall edge; the object the player sees under the
## pointer wins. An object behind a wall the view draws opaque
## (_wall_distance) is not seen.
static func seen_object(grid: BuildGrid, view: BuildView, camera: Camera3D, point: Vector3) -> int:
	if camera == null or camera.is_position_behind(point):
		return 0
	var from := camera.project_ray_origin(camera.unproject_position(point))
	var reach := from.distance_to(point)
	if reach <= 0.0:
		return 0
	var direction := (point - from) / reach
	var nearest := reach + SIGHT_SLACK_M
	var seen := 0
	for object_id in grid.object_ids():
		var hit: Variant = _object_box(grid, object_id).intersects_ray(from, direction)
		if hit == null:
			continue
		var distance := from.distance_to(hit)
		if distance < nearest:
			nearest = distance
			seen = object_id
	if seen != 0 and nearest >= _wall_distance(grid, view, from, point) - SIGHT_SLACK_M:
		return 0
	return seen


## A placed object's footprint, from the floor up to its drawn height.
static func _object_box(grid: BuildGrid, object_id: int) -> AABB:
	var record := grid.get_object(object_id)
	var def := BuildCatalog.get_def(record["def"])
	var cells := def.footprint(record["anchor"], record["facing"])
	var low: Vector2i = cells[0]
	var high: Vector2i = cells[0]
	for at in cells:
		low = Vector2i(mini(low.x, at.x), mini(low.y, at.y))
		high = Vector2i(maxi(high.x, at.x), maxi(high.y, at.y))
	var corner := grid.origin + Vector3(low.x, 0.0, low.y)
	var extent := Vector3(high.x - low.x + 1, BuildView.pick_height(def), high.y - low.y + 1)
	return AABB(corner, extent)


## How far from `from`, on the straight line to `to`, the first wall edge the
## view draws opaque (BuildView.sight_blocked) stands in the way, or INF. The
## line is walked across the grid lines it crosses, so the cost grows with the
## grid's width, not with the number of walls.
static func _wall_distance(grid: BuildGrid, view: BuildView, from: Vector3, to: Vector3) -> float:
	var start := from - grid.origin
	var span := to - from
	var nearest := INF
	for axis in [0, 2]:
		if absf(span[axis]) < 0.000001:
			continue
		var cells := grid.size.x if axis == 0 else grid.size.y
		var low := maxi(0, ceili(minf(start[axis], start[axis] + span[axis])))
		var high := mini(cells, floori(maxf(start[axis], start[axis] + span[axis])))
		for line in range(low, high + 1):
			var t := (line - start[axis]) / span[axis]
			var at := start + span * t
			var edge := WallPick.edge_on_line(grid, axis, line, at)
			if edge.z >= 0 and view.sight_blocked(edge, fposmod(at[2 - axis], 1.0) - 0.5, at.y):
				nearest = minf(nearest, t * span.length())
	return nearest
