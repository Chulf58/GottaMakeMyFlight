class_name ShellSight
extends RefCounted
## Whether the terminal shell, as ShellView draws it now, stands between the
## camera and a point inside the build grid. BuildMode's Remove tool asks it
## so that it does not pick an object the player cannot see. View rules only:
## it reads ShellView.cutaway and changes nothing.
##
## While any of the roof is drawn the shell is closed. Once it is gone, a line
## from outside enters through one outer face, and that face hides what is
## under its squashed height: the full facade for a side the camera does not
## look from, a kerb for a cut one (ShellCutaway.stub_transform). The faces
## are the four sides of the grid's rectangle, each bounded to its own length.


## Whether the shell stands between the camera `camera` and the ground point
## `point`; false with no shell view, no camera or a point behind it.
static func hides_point(view: ShellView, grid: BuildGrid, camera: Camera3D, point: Vector3) -> bool:
	if view == null or camera == null or camera.is_position_behind(point):
		return false
	var from := camera.project_ray_origin(camera.unproject_position(point))
	return in_sight(view, grid, from, point)


## Whether the shell stands on the straight line from `from` to the point `to`
## inside the grid.
static func in_sight(view: ShellView, grid: BuildGrid, from: Vector3, to: Vector3) -> bool:
	if view == null or not view.is_ready():
		return false
	var cutaway := view.cutaway
	if cutaway.roof_level < 1.0:
		return true
	var low := Vector2(grid.origin.x, grid.origin.z)
	var high := low + Vector2(grid.size)
	# Each face: its side, the axis it is perpendicular to (0 x, 2 z), the
	# plane's coordinate, which way is outside, and the face's extent along the
	# other horizontal axis. A line crossing the plane beyond that extent is
	# outside the building and enters through another face.
	var faces := [
		[ShellCutaway.Side.WEST, 0, low.x, -1.0, low.y, high.y],
		[ShellCutaway.Side.EAST, 0, high.x, 1.0, low.y, high.y],
		[ShellCutaway.Side.NORTH, 2, low.y, -1.0, low.x, high.x],
		[ShellCutaway.Side.SOUTH, 2, high.y, 1.0, low.x, high.x],
	]
	for face in faces:
		var axis: int = face[1]
		var plane: float = face[2]
		var outward: float = face[3]
		if (from[axis] - plane) * outward <= 0.0 or (to[axis] - plane) * outward > 0.0:
			continue
		var t := (plane - from[axis]) / (to[axis] - from[axis])
		var along := lerpf(from[2 - axis], to[2 - axis], t)
		if along < face[4] or along > face[5]:
			continue
		var height := lerpf(from.y, to.y, t) - grid.origin.y
		var standing := lerpf(
			ShellCutaway.FACADE_HEIGHT, InteriorKit.STUB_HEIGHT, cutaway.cut(face[0])
		)
		if height < standing:
			return true
	return false
