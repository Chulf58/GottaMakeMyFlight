class_name DoorSteer
extends RefCounted
## Where a guest pulling a roller is drawn through an entrance or exit door
## (board 4b062450, decision door-steer: a guest pulling a roller is drawn
## 0.12 m off the door's centre line, away from the pulling hand). The walk
## runs on the door's axis, and the grip bar, rods and hand ride about 0.40 m
## out on the pulling side, where the open leaves start (decision door-leaves-
## as-built-open-sliding-door-leaves-count-as-walls). PassengerViews adds this
## offset to where it draws the guest, so the body, and the roller trailing
## it, pass SIDE_M nearer the other leaf and the pulled parts clear their own.
##
## View only: the sim's walks, queues, boarding files, forecasts and saves are
## not touched, and the hand is CarryOnProps' (PullSide's), which is view
## state too. The offset runs across the door, along its wall, to the side of
## the pulling hand's other hand for the way the guest crosses: its walk
## heading where it walks across the door, else the door's own way (out of an
## exit, in through an entrance), so a guest waiting at a door is drawn where
## it will walk on from. It eases in over EASE_M before the door's plane and
## out over EASE_M after it, and off to the side of the opening, so it never
## steps. Over a change of hand it crosses from one side to the other in step
## with the roller's move (through 0 half way).
##
## PassengerViews reads it after CarryOnProps.sync() has made this tick's
## change of hand, at a tick ahead of the clock (the body is drawn between its
## last two tick positions, the bags at the clock's time), so the body crosses
## with the roller, and a load (snap()) records the steer it draws next.
##
## Not covered: a door wall (WallKind.DOOR, an inside door) has no way of its
## own, so it is not steered; a roller lifted by its handle is not steered (the
## steer eases out over the lift); a guest with another bag in its other hand
## (a hard case) is not steered (user ruling "No steer with a case"), nor one
## pulling two rollers, one in each hand.

## How far off the door's axis the guest is drawn.
const SIDE_M := 0.12
## The offset is whole within FULL_M of the door's plane and none from EASE_M.
const FULL_M := 0.4
const EASE_M := 1.2
## And whole within LATERAL_FULL_M of the door's axis, none from LATERAL_M.
const LATERAL_FULL_M := 0.5
const LATERAL_M := 0.9
## A heading this square to the door (cosine) is taken as crossing it.
const CROSSING := 0.5
## Doors are looked for on the cells this far round the guest's cell.
const REACH_CELLS := 2


## The steer of passenger `p` drawn by `views` at sim time `now`: offset_at()
## of where the sim puts it, with side_of() its bags.
static func offset_of(views: PassengerViews, p: Passenger, now: float) -> Vector3:
	var bags := []
	var props := views.carry_on_props()
	for i in (props.props_of(p.id)["bags"] as Array).size():
		bags.append(props.bag_state(p.id, i))
	var side := side_of(bags, now)
	if side == 0.0:
		return Vector3.ZERO
	return offset_at(views.sim.grid, views.sim.world_position(p), views.walk_heading(p), side)


## Which way bags `bags` (CarryOnProps' records) steer their guest at sim time
## `now`: 1 to its left (a roller pulled in the right hand), -1 to its right
## (in the left), 0 with no roller pulled. Only with the other hand free: a
## hard case or any other bag held in the other hand stops the steer (user
## ruling 2026-11-08, "No steer with a case"), and rollers pulled in both
## hands cancel. While a bag's move is under way (a change of hand, a lift, a
## pick-up, a case taken into or out of the hand) its part goes from its old
## place's to its new one's over the move's ticks from the tick it was seen on
## ("changed"), through 0 half way across a change of hand. The old place is
## the one drawn ("home") until a draw stamps the move, then its start
## ("was"), so the side does not depend on when frames are drawn.
static func side_of(bags: Array, now: float) -> float:
	var pulls: Array[float] = []
	var holds: Array[float] = []
	for bag: Dictionary in bags:
		pulls.append(_eased(bag, now, true))
		holds.append(_eased(bag, now, false))
	var side := 0.0
	for i in bags.size():
		var own := pulls[i]
		for j in bags.size():
			if j != i:
				own *= 1.0 - holds[j]
		side += own
	return clampf(side, -1.0, 1.0)


## `_value()` of bag record `bag` at sim time `now`, eased from its old place
## to its new over a move still under way (see side_of()).
static func _eased(bag: Dictionary, now: float, pull: bool) -> float:
	var kind := int(bag.get("kind", -1))
	var place := int(bag.get("place", -1))
	var to := _value(place, kind, pull)
	var k := (now - float(bag.get("changed", -INF))) / CarryLead.ticks_of(bag)
	var home := int(bag.get("home", -1))
	var from := home if home != place else int(bag.get("was", -1))
	if k < 1.0 and from >= 0:
		return lerpf(_value(from, kind, pull), to, clampf(k, 0.0, 1.0))
	return to


## For a bag of `kind` at `place` (CarryOnProps' (home * 2 + hand) * 2 +
## lifted): with `pull`, the side a pulled roller steers to (right hand 1, left
## -1, else 0); else 1 when it fills a hand without being a pulled roller (a
## hard case, a lifted bag), else 0.
static func _value(place: int, kind: int, pull: bool) -> float:
	if kind < 0 or place < 0 or place / 4 != SecurityLooks.Home.HAND:
		return 0.0
	var lifted := place % 2 == 1
	var roller := kind == SecurityLooks.Kind.ROLLER
	if pull:
		if not roller or lifted:
			return 0.0
		return 1.0 if CarryLead.hand_of(place) == 0 else -1.0
	if roller:
		return 1.0 if lifted else 0.0
	return 1.0 if lifted or SecurityLooks.KIND_CARRY[kind] == SecurityLooks.Carry.HAND else 0.0


## The offset of a guest the sim puts at `here`, walking `heading` (world x, z;
## zero standing), steered `side` (side_of()) through the nearest entrance or
## exit door on `grid`: SIDE_M times `side` to its left as it crosses, eased
## by its distance from the door's plane and from its axis.
static func offset_at(grid: BuildGrid, here: Vector3, heading: Vector2, side: float) -> Vector3:
	if side == 0.0:
		return Vector3.ZERO
	var best := Vector3.ZERO
	var best_weight := 0.0
	var seen := {}
	var under := grid.world_to_cell(here)
	for dx in range(-REACH_CELLS, REACH_CELLS + 1):
		for dy in range(-REACH_CELLS, REACH_CELLS + 1):
			var id := grid.object_at(under + Vector2i(dx, dy))
			if id == 0 or seen.has(id):
				continue
			seen[id] = true
			var record := grid.get_object(id)
			if not BuildCatalog.is_door(record["def"]):
				continue
			var step := DoorPlacement.back_step(record["facing"])
			var out := Vector2(step)
			var plane := grid.cell_to_world(record["anchor"]) + Vector3(step.x, 0.0, step.y) * 0.5
			var rel := Vector2(here.x - plane.x, here.z - plane.z)
			var along := absf(rel.dot(out))
			var across := absf(rel.dot(Vector2(out.y, -out.x)))
			var weight := (
				(1.0 - smoothstep(FULL_M, EASE_M, along))
				* (1.0 - smoothstep(LATERAL_FULL_M, LATERAL_M, across))
			)
			if weight <= best_weight:
				continue
			# The way it crosses: its heading where that is across the door, else
			# the door's own way.
			var way := out if record["def"] == &"exit_door" else -out
			var walking := heading.normalized()
			if absf(walking.dot(out)) >= CROSSING:
				way = out * signf(walking.dot(out))
			best_weight = weight
			best = Vector3(way.y, 0.0, -way.x) * (SIDE_M * side * weight)
	return best
