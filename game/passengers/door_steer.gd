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
## Not covered: a door wall (WallKind.DOOR, an inside door) has no way of its
## own, so it is not steered; a guest with two bags in its hands, or a roller
## lifted by its handle, is not steered; on a load the bags start over
## (PassengerViews.snap()), so the first tick after a load draws no offset.

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
## (in the left), 0 unless the one bag held in a hand is a pulled roller.
## Through a change of hand (PullSide.swapped()) it goes from the old side to
## the new over the move's ticks.
static func side_of(bags: Array, now: float) -> float:
	var held := 0
	var pulled := {}
	for bag: Dictionary in bags:
		var place := int(bag.get("place", -1))
		if not bag.has("kind"):
			continue
		var carry: int = bag.get("carry", SecurityLooks.KIND_CARRY[bag["kind"]])
		if CarryLead.end_of(place, carry) != CarryLead.End.HELD:
			continue
		held += 1
		if bag["kind"] == SecurityLooks.Kind.ROLLER and place % 2 == 0:
			pulled = bag
	if held != 1 or pulled.is_empty():
		return 0.0
	var side := 1.0 if CarryLead.hand_of(int(pulled["place"])) == 0 else -1.0
	if PullSide.swapped(pulled):
		var since := float(pulled.get("changed", -INF))
		var k := clampf((now - since) / CarryLead.ticks_of(pulled), 0.0, 1.0)
		side *= lerpf(-1.0, 1.0, k)
	return side


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
