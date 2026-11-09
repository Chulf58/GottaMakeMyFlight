class_name ParkWalls
extends RefCounted
## Keeps a parked roller out of the walls beside a seat (board a40fdbaf).
## ParkSide first puts the hand, and so the park, on the open side; this is the
## backstop for a seat walled on both sides. A RollerPark move stamped with a
## seat's face (a gate chair, a cafe seat, a booth, a sofa or nap pod) parks the
## roller standing PARK_SIDE_M out on the hand's side. BoothRoller.fix_start()
## keeps, for such a move, the walls round the walker as finite boxes
## (PullSide.walls_near(), doorways out, open leaves in), and RollerPark.plan() moves the park
## out of them by shift(), once for the move: the lift, the park, the roll
## upright and the tip are all drawn from that one park, so the way out is the
## same on every frame (moved frame by frame, a roller turning about a wall's
## end flipped from along to across in one frame, 0.057 m). The roller lying on
## the floor is moved the same way (CarryPlace._off_walls()), the set-down's end
## and the settled roller alike. Before ParkSide, the lounge sofa's west seat
## parked the roller 0.04 m into the end of the wall beside the door
## (roller_park_walls_probe, wall_22_113_3).
##
## The way out is the shortest one for each wall in turn, in the wall's own
## frame: along it, past the wall's end, or across it, out of its face. A
## shift is worked out from the roller's transform and its home (the chair
## front or walker, whose side of a wall a way out of its face keeps to),
## never from the hand.
## What it does not guarantee: that the shifted roller is clear of furniture, of
## the guest's legs (a park pushed across a wall's middle comes nearer the
## body), of a wall the boxes left out (more than PullSide.REACH_CELLS from the
## walker's cell as the move was stamped), or of a wall it is carried past (the
## tip out through the lounge door grazes the jamb, at depth 0, on its last
## frame).

## A wall is read this much thicker and longer, so a roller that only touches
## its face or end is moved clear of it, not left touching it.
const SLACK_M := 0.005
## Passes over the walls: a move out of one wall can put the park in the next
## one along.
const PASSES := 4
## shift()'s `home` when none is given.
const NO_HOME := Vector3(INF, INF, INF)


## The shift (world) that moves the roller drawn at `parked` (world, its
## scale in the basis) out of every one of `walls` (PullSide.walls_near()'s
## boxes): zero when it is in none. With `home` (world: the chair front or the
## walker the roller belongs to), a way out of a wall's face goes only to the
## side of the wall `home` is on, never out through the far face: at a gate
## chair walled on both sides a roller lying with its middle past a wall's
## centre plane went the shorter way, through the wall, 0.58 m out to 0.739 m
## (board f1fc1e54). A home on the wall's centre plane, or none, leaves both
## faces open, as before.
static func shift(parked: Transform3D, walls: Array, home := NO_HOME) -> Vector3:
	var points := _points(parked)
	var moved := Vector3.ZERO
	for n in PASSES:
		var any := false
		for wall: Array in walls:
			var out := _way_out(points, moved, wall, SLACK_M, home)
			if out != Vector3.ZERO:
				moved += out
				any = true
		if not any:
			break
	return moved


## The shift (world) that moves the roller drawn at `xf` (a frame of a move
## whose park is `anchor`, already out of the walls by shift()) out of `walls`
## on one way per wall for the whole move, chosen from the park: out past the
## wall's end, on the park's side, when the park stands past that end, else
## out of the face on the park's side. Carried with the body out through the
## lounge door, the roll and the tip reached 0.028 m into the door's jamb; the
## shortest way frame by frame flipped between along and across (0.057 m in
## a frame), and one way per move cannot.
static func held_out(xf: Transform3D, walls: Array, anchor: Transform3D) -> Vector3:
	var points := _points(xf)
	var home := anchor * CarryOnProps.bag_box(SecurityLooks.Kind.ROLLER).get_center()
	var moved := Vector3.ZERO
	for wall: Array in walls:
		var centre: Vector3 = wall[0]
		var half: Vector3 = wall[2]
		var along := _flat(wall[1][0])
		var across := _flat(wall[1][2])
		var hx := half.x + SLACK_M
		var hz := half.z + SLACK_M
		var a := Vector2(INF, -INF)
		var c := Vector2(INF, -INF)
		for at in points:
			var d := at + moved - centre
			a = Vector2(minf(a.x, d.dot(along)), maxf(a.y, d.dot(along)))
			c = Vector2(minf(c.x, d.dot(across)), maxf(c.y, d.dot(across)))
		if a.y <= -hx or a.x >= hx or c.y <= -hz or c.x >= hz:
			continue
		var side := home - centre
		if absf(side.dot(along)) > hx:
			moved += along * (hx - a.x if side.dot(along) > 0.0 else -hx - a.y)
		else:
			moved += across * (hz - c.x if side.dot(across) > 0.0 else -hz - c.y)
	return moved


## Whether the roller drawn at `xf` (world) reaches into any of `walls`.
static func inside(xf: Transform3D, walls: Array) -> bool:
	var points := _points(xf)
	for wall: Array in walls:
		if _way_out(points, Vector3.ZERO, wall, 0.0) != Vector3.ZERO:
			return true
	return false


## The corners (world) of the roller's box (CarryOnProps.bag_box()) drawn at
## `xf`.
static func _points(xf: Transform3D) -> Array[Vector3]:
	var box := CarryOnProps.bag_box(SecurityLooks.Kind.ROLLER)
	var out: Array[Vector3] = []
	for k in 8:
		out.append(xf * box.get_endpoint(k))
	return out


## The shortest move (world, flat) of `points` (moved by `by`) out of `wall`
## ([centre, axes, half size], axes 0 along the wall, 2 across it), the wall
## read `slack` thicker and longer: zero when
## the points' span misses the wall along or across it. A wall is taller than
## any roller, so its height is not read. Across, only toward `home`'s side
## when `home` (shift()) lies off the wall's centre plane.
static func _way_out(
	points: Array[Vector3], by: Vector3, wall: Array, slack: float, home := NO_HOME
) -> Vector3:
	var centre: Vector3 = wall[0]
	var axes: Array = wall[1]
	var half: Vector3 = wall[2]
	var along := _flat(axes[0])
	var across := _flat(axes[2])
	var a := Vector2(INF, -INF)
	var c := Vector2(INF, -INF)
	for at in points:
		var d := at + by - centre
		a = Vector2(minf(a.x, d.dot(along)), maxf(a.y, d.dot(along)))
		c = Vector2(minf(c.x, d.dot(across)), maxf(c.y, d.dot(across)))
	var hx := half.x + slack
	var hz := half.z + slack
	if a.y <= -hx or a.x >= hx or c.y <= -hz or c.x >= hz:
		return Vector3.ZERO
	var on_along := _least(a, hx)
	var on_across := _least(c, hz)
	var side := (home - centre).dot(across) if home.is_finite() else 0.0
	if side > 0.0:
		on_across = hz - c.x
	elif side < 0.0:
		on_across = -hz - c.y
	if absf(on_along) < absf(on_across):
		return along * on_along
	return across * on_across


## The shorter signed move of the span `span` (least, most) out of the
## interval -`half` to `half`.
static func _least(span: Vector2, half: float) -> float:
	var up := half - span.x
	var down := -half - span.y
	return up if up < -down else down


## `v` flattened onto the floor, unit length.
static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z).normalized()
