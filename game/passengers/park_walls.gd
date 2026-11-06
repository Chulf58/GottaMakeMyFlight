class_name ParkWalls
extends RefCounted
## Keeps a parked roller out of the walls beside a seat (board a40fdbaf).
## ParkSide first puts the hand, and so the park, on the open side; this is the
## backstop for a seat walled on both sides and for a roller carried with the
## body past a wall (the roll upright and the tip out through the lounge door,
## whose jamb the tip grazed on its last frame). A
## RollerPark move stamped with a seat's face (a gate chair, a cafe seat, a
## booth, a sofa or nap pod) parks the roller standing PARK_SIDE_M out on the
## hand's side, wherever the walls are. BoothRoller.fix_start() keeps, for such
## a move, the walls round the walker as finite boxes (PullSide.walls_near(),
## doors left out), and RollerPark.plan() moves the park out of them by
## shift(), and then every frame of the move as it is drawn (the lift to the
## park, the roll upright and the tip): at the lounge sofa's west seat the
## park stood 0.04 m into the end of the wall beside the door, and the lift,
## the park and the roll upright all drew the roller in it
## (roller_park_walls_probe, wall_22_113_3).
##
## The way out is the shortest one for each wall in turn, in the wall's own
## frame: along it, past the wall's end, or across it, out of its face. At the
## sofa that is along the wall, past its end, not towards the guest's legs. A
## shift is worked out from the roller's transform alone, never from the hand:
## the park's (its frame, hand and scale, fixed for the move) is the same on
## every frame, so the roller lifted to it and rolled from it with the body
## starts from the moved park. What it does not guarantee: that the shifted
## park is clear of furniture, of the guest's legs (a park pushed across a
## wall's middle comes nearer the body) or of a wall the boxes left out
## (more than PullSide.REACH_CELLS from the walker's cell as the move was stamped).

## A wall is read this much thicker and longer, so a roller that only touches
## its face or end (the drawn mesh grazed the end of the wall beside the lounge
## door on the tip's last frame) is moved clear of it.
const SLACK_M := 0.005
## Passes over the walls: a move out of one wall can put the park in the next
## one along.
const PASSES := 4


## The shift (world) that moves the roller drawn at `parked` (world, its
## scale in the basis) out of every one of `walls` (PullSide.walls_near()'s
## boxes): zero when it is in none.
static func shift(parked: Transform3D, walls: Array) -> Vector3:
	var points := _points(parked)
	var moved := Vector3.ZERO
	for n in PASSES:
		var any := false
		for wall: Array in walls:
			var out := _way_out(points, moved, wall, SLACK_M)
			if out != Vector3.ZERO:
				moved += out
				any = true
		if not any:
			break
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
## any roller, so its height is not read.
static func _way_out(points: Array[Vector3], by: Vector3, wall: Array, slack: float) -> Vector3:
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
