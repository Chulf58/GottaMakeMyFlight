class_name PullSide
extends RefCounted
## The hand a one-bag guest pulls its roller with (board 578435a7; user ruling
## a-guest-pulling-a-roller-along-a-wall-on-the-pulling-side-sw, design
## roller-hand-swap-design-a-pulled-roller-keeps-its-hand-while). View state
## only: CarryOnProps.sync() asks it each tick for a pulled roller in hand, and
## the answer is the bag's place, never saved. A two-bag guest keeps hand =
## index and every other bag keeps SecurityLooks.hand_of().
##
## The roller stays in the hand it is drawn in (its view place) while that
## side is clear. It goes to the other hand when a wall or a piece of furniture
## threatens the pulling side and the other side, and the way across behind
## the guest, are clear of walls and furniture. The right hand is the one it
## prefers (decision pullside-amendment-the-roller-goes-back-to-the-right-hand-
## on): a roller on the left goes back to the right once it has been on the
## left HOLD_TICKS and the right's REACH footprint and the way across are clear
## at the guest's pose now, at the roller's own drawn depth behind it and over
## the look-ahead and a hold more, so a wall run cannot flicker and the roller is past the wall
## before it goes back. SecurityLooks.hand_of()'s one-cell look (a wall
## beside the guest on the right, none on the left) threatens a roller on the
## right once it has held HOLD_TICKS since a change of hand (at once after any
## other move, such as the set-down of a new guest's roller), and moves it even
## with both sides blocked, as before PullSide. Otherwise with both sides
## blocked it stays, and the tick is counted on the bag ("pull_side_both"). It
## holds its hand while a move of the bag is under way (a change of hand, a
## park, any other move) and while the guest stands still. In a queue (RollerPark.QUEUE_STAGES but
## the gate's STANDING, where hand_of()'s hand put it into the gate desk) and
## for LOOK_TICKS after a queue stand ends, the roller is in hand_of()'s hand,
## as before PullSide: a roller kept on the right up to a
## cafe queue spot where hand_of() puts it on the left was stood up there on
## the right, and leaving the spot, with no change of hand to carry it round,
## its trail swung into a cafe table. So too bound for a gate chair whose side
## ParkSide has stamped (gate_stamped()), while the stamped side's settled
## footprint is clear: walking along the row of fronts, the
## chairs reached into the right's REACH footprint (never its settled one), the
## roller went left and back and was laid down from the left onto the stamped
## right (board 3c591192). The change of hand is CarryOnProps' own
## move from one pull to the other.
##
## The tests place the roller's footprint (footprint()) behind the guest at
## each point of its walk from now to LOOK_TICKS ticks of its speed ahead, so
## a faster walker starts the change earlier and the roller is in its new hand
## before it reaches the wall. A wall threatens a side when it meets the REACH
## footprint (the axle as far out as the follower takes it at a corner,
## RollerPull.TRAIL_SIDE_MAX_M). The other side is clear when the SETTLED
## footprint (the axle where a straight pull keeps it, TRAIL_SIDE_M out) meets
## no wall and no furniture: a seat row beside the path, past where the roller
## runs, does not keep it on the wall's side. When the other side is threatened
## too, the roller goes across only if its own side is blocked where it runs
## (the settled footprint meets the wall), so it never goes to and fro between
## two threats. Walls are BuildGrid's walled edges as BuildView draws them,
## their ends run on by half a wall's thickness; a door is a way through and is
## left out, but its open leaves are walls (walls_near()). Furniture is the
## real meshes of each piece; it threatens the pulling side as a wall does (a
## scanner, a cafe table) and keeps the roller off the other side. A change
## chosen by a threat ahead does not take the roller onto the inside of a
## corner within the look-ahead (turns_to()): the follower jumps there, so the
## change waits until the guest has turned.
##
## What it does not do: it does not look back along the route (a replan
## replaces the route; the roller's drawn depth stands in for it), a change
## of hand does not clear a wall end at a door (no hand clears a jamb, finding
## which-kinds-of-wall-hit-make-up-the-walking-pull-roller-s-wa: tuck() pulls
## the roller in line behind there instead), and its footprint is a box round
## the axle's whole range of places, not the drawn bag.

## Ticks of walking ahead the threat test covers: the change of hand
## (CarryOnProps.TRANSFER_TICKS) and two more, so the change is over before the
## roller comes level with the wall.
const LOOK_TICKS := CarryOnProps.TRANSFER_TICKS + 2.0
## Walk samples are at most this far apart.
const SAMPLE_M := 0.2
## A guest moving less than this a tick stands still: its hand holds.
const STILL_M := 0.005
## Walls are looked for on the cells this far round a footprint's middle.
const REACH_CELLS := 1
## The settled footprint's slack out past the bag (the walked line the axle
## follows is blended between ticks and swings a little): 0.504 m from the
## centre line, past a cell's edge, so a piece reaching over its cell's edge
## (a bin's rim) counts, and one kept inside its cell does not.
const MARGIN_M := 0.04
## Route cells ahead resolve() hands to pick(): more than LOOK_TICKS of a run.
const AHEAD_CELLS := 3
## Ticks from the start of a roller's last move (its change to the left) before
## it may go back to the right: more than the probe's 12-tick swap-back window.
const HOLD_TICKS := 2.0 * LOOK_TICKS
## A heading change over this along the walk ahead is a corner (degrees).
const CORNER_DEG := 45.0


## Sets `hands` (CarryOnProps.sync()'s, SecurityLooks.hand_of() so far) of a
## pulled roller of one-bag guest `p` to pick()'s hand: one of `kinds` in hand
## (`homes`) and not lifted (`lifts`); `was` the bag records drawn so far,
## `now` sim time. The guest's pose and step are its tick positions as drawn.
static func resolve(
	was: Array,
	sim: PassengerSim,
	views: PassengerViews,
	p: Passenger,
	kinds: Array,
	homes: Array,
	lifts: Array,
	hands: Array,
	now: float
) -> void:
	for i in mini(was.size(), kinds.size()):
		if kinds[i] != SecurityLooks.Kind.ROLLER or homes[i] != SecurityLooks.Home.HAND:
			continue
		if lifts[i]:
			continue
		var bag: Dictionary = was[i] if was[i].get("kind", -1) == kinds[i] else {}
		var walk := walk_of(sim, views, p)
		var frame: Transform3D = walk[0]
		var step_m: float = walk[2]
		var queued := p.stage in RollerPark.QUEUE_STAGES and p.stage != Passenger.Stage.STANDING
		if p.carry_on == 1:
			var parked := gate_stamped(sim, p)
			hands[i] = pick(bag, sim.grid, frame, walk[1], step_m, hands[i], now, queued, parked)
		if not bag.is_empty():
			tuck(bag, sim.grid, frame, walk[1], step_m, hands[i], now)


## [frame, ahead, step_m] of guest `p` this tick, as resolve() hands them to
## pick() and tuck(): its pose at its tick position facing its step, the world
## points of the next AHEAD_CELLS route cells, and how far it stepped.
static func walk_of(sim: PassengerSim, views: PassengerViews, p: Passenger) -> Array:
	var at := views.tick_position(p.id, true)
	var step := at - views.tick_position(p.id, false)
	step.y = 0.0
	var yaw := atan2(step.x, step.z) if step.length() > 0.001 else 0.0
	var ahead: Array = []
	var from := maxi(p.path_index + 1, 0)
	for k in range(from, mini(p.path.size(), from + AHEAD_CELLS)):
		ahead.append(sim.grid.cell_to_world(p.path[k]))
	return [Transform3D(Basis(Vector3.UP, yaw), at), ahead, step.length()]


## tuck() for a bag record resolve() did not see (made in this sync: a new
## guest, or every record after PassengerViews.snap() on a load): RollerPull.step()
## calls it before the record's first draw with `frame` (the guest's pose as it
## draws it, facing its body when it has not stepped) and `step_m`, and a tuck
## it turns on starts in line, with no ease in (RollerPull.tuck()). It looks
## even when the guest has not stepped (a snap puts both tick positions on one
## spot): at its walking pace while it is on its way, else where it stands.
static func tuck_now(
	bag: Dictionary,
	sim: PassengerSim,
	p: Passenger,
	frame: Transform3D,
	step_m: float,
	hand: int,
	now: float
) -> void:
	var ahead: Array = []
	var from := maxi(p.path_index + 1, 0)
	for k in range(from, mini(p.path.size(), from + AHEAD_CELLS)):
		ahead.append(sim.grid.cell_to_world(p.path[k]))
	# A snap puts both tick positions on one spot: a guest still on its way
	# looks ahead at its walking pace, one standing only where it stands.
	var pace := p.pace_mm() / 1000.0 if p.is_moving() else STILL_M
	tuck(bag, sim.grid, frame, ahead, step_m if step_m >= STILL_M else pace, hand, now)


## The hand (0 right, 1 left) bag record `bag` (CarryOnProps' record of a
## pulled roller in hand) is pulled with on this tick. `frame` is the guest's
## pose now (its origin on the floor, -z of its basis behind it), `ahead` the
## world points of its route still to walk, in order, `step_m` how far it
## walked this tick, `first` SecurityLooks.hand_of() (the hand to start a pull
## with; a roller on the left goes back to the right only while it is the
## right, its one-cell look finding no wall beside the guest on the right),
## `now` sim time, `queued` the guest is in a queue (RollerPark.QUEUE_STAGES
## but STANDING),
## where the roller takes `first`, as it does just after a queue stand
## (stood()), `parked` the guest is bound for a gate chair whose side ParkSide
## has stamped (gate_stamped()), where, walking, it takes `first` while that
## side's SETTLED footprint (and for a change the way across) meets no wall
## and no furniture. A change of hand starts the roller's trail afresh
## (RollerPull.step() "walked"), straight behind on the new side: the old
## side's walked line ends in a jump across the legs.
static func pick(
	bag: Dictionary,
	grid: BuildGrid,
	frame: Transform3D,
	ahead: Array,
	step_m: float,
	first: int,
	now: float,
	queued := false,
	parked := false
) -> int:
	var hand := drawn_hand(bag, first)
	# hand_of() finding a wall beside the guest on the right (and none on the
	# left) threatens a roller on the right too, once it has held HOLD_TICKS
	# since a change of hand (at once after any other move: a new guest's
	# roller set down before its route turned hand_of() left), standing still
	# as well.
	var held := not swapped(bag) or now - float(bag.get("changed", -INF)) >= HOLD_TICKS
	# Not while the roller is tucked in line behind (tuck()): it goes back out
	# to the side it is drawn on, not across at hand_of()'s word mid-doorway.
	var told := first == 1 and hand == 0 and held and RollerPull.tuck_weight(bag, now) <= 0.0
	if holds(bag, now):
		return hand
	if queued or stood(bag, now):
		return hand if hand == first else _change(bag, "pull_side_queue", first)
	if step_m < STILL_M and not told:
		return hand
	var poses := walk_poses(frame, ahead, step_m * LOOK_TICKS)
	if parked and not blocked(grid, poses, footprint(first, false), true):
		# The stamped side is where the roller is laid down (ParkSide.hand()):
		# the chairs of the row reach into its REACH footprint on the way along
		# the fronts (never its SETTLED one), and a change away from them laid it
		# down from the other hand. Its settled footprint meeting a wall or a
		# piece (a bin beside the stamped side) leaves the hand to the rules below.
		if hand == first:
			return hand
		if not blocked(grid, poses, crossing(), true):
			return _change(bag, "pull_side_park", first)
	if not told and not blocked(grid, poses, footprint(hand, true), true):
		if hand == 1 and first == 0:
			# Clear for a hold as well, so the right is not threatened again
			# as soon as the roller is there.
			var on := walk_poses(frame, ahead, step_m * (LOOK_TICKS + HOLD_TICKS))
			if may_return(bag, grid, frame, on, now):
				return _change(bag, "pull_side_returns", 0)
		return hand
	var other := 1 - hand
	var shut := (
		blocked(grid, poses, crossing(), true)
		or blocked(grid, poses, footprint(other, false), true)
		or (
			blocked(grid, poses, footprint(other, true), true)
			and not blocked(grid, poses, footprint(hand, false), true)
		)
	)
	if shut:
		bag["pull_side_both"] = int(bag.get("pull_side_both", 0)) + 1
		# Both sides blocked, the roller stays unless hand_of() tells it across,
		# as before PullSide (by a scanner with a wall on the left it hit the
		# wall, not the scanner).
		if not told:
			return hand
	elif not told and turns_to(poses, other):
		# Not onto the inside of a corner ahead: the follower jumps there (the
		# hand-to-axle distance changes 0.066 m in a frame at 1x, a 90 degree
		# corner in the cafe walk). The change waits until the guest has turned.
		return hand
	return _change(bag, "pull_side_swaps", other)


## Tucks pulled roller `bag` in line behind its guest, or lets it back out to
## its side (RollerPull.tuck()), for a pull in `hand` (pick()'s, the hand it is
## drawn in, so the two agree on its side): tucked while its SETTLED footprint
## on that side meets a wall at any of the guest's poses from `frame` (its pose
## now) along `ahead` for LOOK_TICKS and RollerPull.TUCK_TICKS of `step_m`
## (walk_poses(), straight on past the route's end), so the axle is in line
## (eased over TUCK_TICKS) before the roller reaches the wall; out once none
## does, so the roller is past it (user ruling a-guest-pulling-a-roller-
## through-a-doorway-tucks-it-in-line, board cd4ff4e0). At a
## doorway the jambs meet both sides, so no change of hand clears them; along
## a wall with the other side clear pick() changes hand first and the new side
## is clear. Standing still it stays as it is. Walls only, as pick() has them
## (doors left out but their open leaves, their ends run on).
static func tuck(
	bag: Dictionary,
	grid: BuildGrid,
	frame: Transform3D,
	ahead: Array,
	step_m: float,
	hand: int,
	now: float
) -> void:
	if step_m < STILL_M:
		return
	var look := step_m * (LOOK_TICKS + RollerPull.TUCK_TICKS)
	# The route can end at the doorway (the gate's door out to the apron: the
	# walk to the plane is not on it), so the look runs on straight past its end.
	var route := ahead.duplicate()
	var last: Vector3 = route[-1] if not route.is_empty() else frame.origin
	var before: Vector3 = route[-2] if route.size() > 1 else frame.origin
	var on := Vector3(last.x - before.x, 0.0, last.z - before.z)
	if on.length() < 0.001:
		on = frame.basis.z
	route.append(last + on.normalized() * look)
	var poses := walk_poses(frame, route, look)
	RollerPull.tuck(bag, blocked(grid, poses, footprint(hand, false), false), now)


## Counts a change of `bag` to `hand` in its `tally` and starts its trail
## afresh; returns `hand`.
static func _change(bag: Dictionary, tally: String, hand: int) -> int:
	bag[tally] = int(bag.get(tally, 0)) + 1
	bag.erase("walked")
	return hand


## Whether a roller `bag` on the left may go back to the right at `now`: it
## has been there HOLD_TICKS since its last move began, and the right's REACH
## footprint, run forward to beside the guest (hand_of()'s wall at a queue
## spot ahead) and back to the roller's drawn depth (its "drawn_axle"), and
## the way across meet no wall and no furniture at `poses` (walk_poses() from
## `frame`, the guest's pose now).
static func may_return(
	bag: Dictionary, grid: BuildGrid, frame: Transform3D, poses: Array, now: float
) -> bool:
	if now - float(bag.get("changed", -INF)) < HOLD_TICKS:
		return false
	var right := footprint(0, true)
	right.size.z = -right.position.z
	if bag.has("drawn_axle"):
		var depth := (frame.affine_inverse() * (bag["drawn_axle"] as Vector3)).z
		var size := Vector3(right.size.x, right.size.y, _bag_size().z * 2.0)
		var at := Vector3(right.position.x, 0.0, depth - _bag_size().z)
		right = right.merge(AABB(at, size))
	return not (blocked(grid, poses, right, true) or blocked(grid, poses, crossing(), true))


## Whether the walk `poses` (walk_poses(), the first the guest's pose now)
## turns more than CORNER_DEG toward hand `hand`'s side (0 right, 1 left).
static func turns_to(poses: Array, hand: int) -> bool:
	var now := (poses[0] as Transform3D).basis.get_euler().y
	var toward := 1.0 if hand == 1 else -1.0
	for pose: Transform3D in poses:
		if angle_difference(now, pose.basis.get_euler().y) * toward > deg_to_rad(CORNER_DEG):
			return true
	return false


## Whether `p` is bound for or at the gate chair (ParkSide.GATE_STAGES, its
## seat_cell) whose side ParkSide has stamped for it (ParkSide.hand(), from
## ParkSide.NEAR_CELLS out): hand_of() is then the stamp's hand, the side the
## roller is laid down on. A stamp for another seat is not this one's.
static func gate_stamped(sim: PassengerSim, p: Passenger) -> bool:
	if p.stage not in ParkSide.GATE_STAGES or p.seat_cell == Passenger.NO_CELL:
		return false
	var stamps: Dictionary = sim.get_meta(ParkSide.STAMPS, {})
	var stamp: Array = stamps.get(p.id, [])
	return not stamp.is_empty() and stamp[0] == "gate %s" % p.seat_cell


## Whether `bag`'s last move was a queue stand (RollerPark.queued()) that
## ended less than LOOK_TICKS before `now`: the guest is leaving its spot.
static func stood(bag: Dictionary, now: float) -> bool:
	var since := float(bag.get("since", -INF))
	return RollerPark.queued(bag) and now - since < CarryLead.ticks_of(bag) + LOOK_TICKS


## Whether `bag`'s last move was a change of hand, from one pull to the other.
static func swapped(bag: Dictionary) -> bool:
	var was := int(bag.get("was", -1))
	var place := int(bag.get("place", -1))
	if was < 0 or place < 0 or CarryLead.hand_of(was) == CarryLead.hand_of(place):
		return false
	var hand := SecurityLooks.Home.HAND
	return was / 4 == hand and was % 2 == 0 and place / 4 == hand and place % 2 == 0


## The hand `bag` is drawn in now: its place's while it is in a hand
## (CarryLead.hand_of()) while it is pulled (in a hand, not lifted), else
## `first`: a roller set down from a lift (out of a tray, past a stall) starts
## its pull in hand_of()'s hand, as it did before PullSide.
static func drawn_hand(bag: Dictionary, first: int) -> int:
	var place := int(bag.get("place", -1))
	if place >= 0 and place / 4 == SecurityLooks.Home.HAND and place % 2 == 0:
		return CarryLead.hand_of(place)
	return first


## Whether a move of `bag` is under way at `now` (a change of hand, any other
## move, or a park: RollerPark stamps one with "since").
static func holds(bag: Dictionary, now: float) -> bool:
	var ticks := CarryLead.ticks_of(bag)
	if now - float(bag.get("changed", -INF)) < ticks:
		return true
	return bag.get("park", false) and now - float(bag.get("since", -INF)) < ticks


## The guest's poses along its walk: `frame` and then one every SAMPLE_M or
## less along `ahead` up to `look_m` on, each facing the way it walks there.
static func walk_poses(frame: Transform3D, ahead: Array, look_m: float) -> Array[Transform3D]:
	var poses: Array[Transform3D] = [frame]
	var at := frame.origin
	var left := look_m
	for next: Vector3 in ahead:
		var leg := Vector3(next.x - at.x, 0.0, next.z - at.z)
		var length := leg.length()
		if length < 0.001:
			continue
		var turn := Basis(Vector3.UP, atan2(leg.x, leg.z))
		var n := ceili(minf(length, left) / SAMPLE_M)
		for k in range(1, n + 1):
			var d := minf(length, left) * k / n
			poses.append(Transform3D(turn, at + leg / length * d))
		left -= length
		if left <= 0.0:
			break
		at = Vector3(next.x, at.y, next.z)
	return poses


## The space a roller pulled in `hand` (0 right) takes behind its guest, in the
## guest's frame (+x its left, -z behind), as an AABB: its axle from
## RollerPull.TRAIL_SIDE_MIN_M out to TRAIL_SIDE_MAX_M with `reach` (the
## follower at a corner) or TRAIL_SIDE_M and MARGIN_M without (a straight
## pull), and from
## TRAIL_BEHIND_MIN_M to TRAIL_M back, with the bag round it (bag_box(): its
## half width out, its whole length either way of the axle, as tall as it is
## long).
static func footprint(hand: int, reach: bool) -> AABB:
	var bag := _bag_size()
	var inner := RollerPull.TRAIL_SIDE_MIN_M - bag.x
	var axle_out := RollerPull.TRAIL_SIDE_MAX_M if reach else RollerPull.TRAIL_SIDE_M + MARGIN_M
	var outer := axle_out + bag.x
	var x0 := -outer if hand == 0 else inner
	var near := RollerPull.TRAIL_BEHIND_MIN_M - bag.z
	var far := RollerPull.TRAIL_M + bag.z
	return AABB(Vector3(x0, 0.0, -far), Vector3(outer - inner, bag.z, far - near))


## The way across behind the guest a change of hand takes the roller: between
## the two footprints, as deep as they are.
static func crossing() -> AABB:
	var right := footprint(0, false)
	var inner := RollerPull.TRAIL_SIDE_MIN_M - _bag_size().x
	var size := Vector3(inner * 2.0, right.size.y, right.size.z)
	return AABB(Vector3(-inner, 0.0, right.position.z), size)


## Whether `box` (the guest's frame) at any of `poses` meets a wall, or with
## `furniture` a piece of furniture, of `grid`.
static func blocked(grid: BuildGrid, poses: Array, box: AABB, furniture: bool) -> bool:
	for pose: Transform3D in poses:
		var shape := _box(pose, box)
		var middle: Vector3 = shape[0]
		var near := walls_near(grid, middle)
		if furniture:
			near.append_array(pieces_near(grid, middle))
		for other: Array in near:
			if _overlap(shape, other) > 0.0:
				return true
	return false


## [half width, bag length] of a roller at scale 1 (bag_box()), as x and z.
static func _bag_size() -> Vector3:
	var size := CarryOnProps.bag_box(SecurityLooks.Kind.ROLLER).size
	return Vector3(size.x * 0.5, 0.0, size.z)


## Every walled edge (but a door) of the cells round `at`'s cell, once each, as
## a box [centre, axes, half size] as BuildView draws it, its length run on by
## half the wall's thickness at each end. Ported from RollerGuard.walls_near
## (branch worktree-agent-afb7a5a26eee179b7). A door's way through is left out,
## but the two open leaves of a sliding door (a door wall, or an entrance or exit
## door's piece) are in, each as its own box (door_leaves()): parked beside the
## opening they stand proud of the wall's face (user ruling open-sliding-door-
## leaves-count-as-obstacles-for-a-pulled-rol). The leaves are always open (no
## door closes) and count whether or not the cutaway draws them.
static func walls_near(grid: BuildGrid, at: Vector3) -> Array:
	var out := []
	var seen := {}
	var under := grid.world_to_cell(at)
	var thick := BuildView.WALL_THICKNESS
	var half := Vector3(0.5 + thick / 2.0, BuildView.WALL_HEIGHT / 2.0, thick / 2.0)
	for dx in range(-REACH_CELLS, REACH_CELLS + 1):
		for dy in range(-REACH_CELLS, REACH_CELLS + 1):
			var cell := under + Vector2i(dx, dy)
			var id := grid.object_at(cell)
			if id != 0 and not seen.has(-id):
				seen[-id] = true
				out.append_array(door_leaves(grid, id))
			for side in 4:
				var kind := grid.wall_kind(cell, side)
				if kind == BuildGrid.WallKind.NONE:
					continue
				var xf := BuildView.wall_transform(grid, cell, side)
				# An edge's middle is on a half metre in one axis: one key per edge.
				var key := Vector2i(roundi(xf.origin.x * 2.0), roundi(xf.origin.z * 2.0))
				if seen.has(key):
					continue
				seen[key] = true
				if kind == BuildGrid.WallKind.DOOR:
					out.append_array(_leaves_at(xf))
					continue
				out.append(_box(xf.translated_local(Vector3.UP * half.y), AABB(-half, half * 2.0)))
	return out


## The open leaves of object `object_id` as boxes when it is a door (its
## piece's leaves where BuildView draws them), else none.
static func door_leaves(grid: BuildGrid, object_id: int) -> Array:
	var record := grid.get_object(object_id)
	if record.is_empty() or not BuildCatalog.is_door(record["def"]):
		return []
	var def := BuildCatalog.get_def(record["def"])
	var cells := def.footprint(record["anchor"], record["facing"])
	var frame := BuildView.object_transform(grid, cells, record["facing"])
	return _leaves_at(frame * Transform3D(Basis.IDENTITY, InteriorKit.object_offset(def.id)))


## The two leaves of a sliding door piece (wall_door) drawn at `xf`, as boxes:
## the piece's parts off its axis (test_build_view_kit pins them at 0.61 m
## either side), the part on it being the frame round the way through.
static func _leaves_at(xf: Transform3D) -> Array:
	var out := []
	for part in InteriorKit.meshes(InteriorKit.WALL_PIECES[InteriorKit.WallKind.DOOR]):
		var local: Transform3D = part[1]
		if absf(local.origin.x) > 0.01:
			out.append(_box(xf * local, (part[0] as Mesh).get_aabb()))
	return out


## The meshes of every piece on the cells round `at`'s cell, each as a box
## (piece_boxes()), once per piece. An entrance or exit door is left out: its
## frame's box would close the way through, and walls_near() has its leaves.
static func pieces_near(grid: BuildGrid, at: Vector3) -> Array:
	var out := []
	var seen := {}
	var under := grid.world_to_cell(at)
	for dx in range(-REACH_CELLS, REACH_CELLS + 1):
		for dy in range(-REACH_CELLS, REACH_CELLS + 1):
			var id := grid.object_at(under + Vector2i(dx, dy))
			if id == 0 or seen.has(id):
				continue
			if BuildCatalog.is_door(grid.get_object(id)["def"]):
				continue
			seen[id] = true
			out.append_array(piece_boxes(grid, id))
	return out


## The meshes of object `object_id` as BuildView draws it, each as a box; a
## type with no kit piece is its placeholder box. Ported from
## RollerGuard.piece_boxes (branch worktree-agent-afb7a5a26eee179b7).
static func piece_boxes(grid: BuildGrid, object_id: int) -> Array:
	var record := grid.get_object(object_id)
	if record.is_empty():
		return []
	var def := BuildCatalog.get_def(record["def"])
	var cells := def.footprint(record["anchor"], record["facing"])
	var frame := BuildView.object_transform(grid, cells, record["facing"])
	var piece := InteriorKit.object_piece(def.id)
	if piece == "":
		var size := Vector3(def.size.x - 0.1, def.height, def.size.y - 0.1)
		return [_box(frame, AABB(Vector3(-size.x / 2.0, 0.0, -size.z / 2.0), size))]
	var lift := Transform3D(Basis.IDENTITY, InteriorKit.object_offset(def.id))
	var out := []
	for part in InteriorKit.meshes(piece):
		out.append(_box(frame * lift * (part[1] as Transform3D), (part[0] as Mesh).get_aabb()))
	return out


## An oriented box [centre, unit axes, half size] of `aabb` under `xf`.
static func _box(xf: Transform3D, aabb: AABB) -> Array:
	var axes: Array[Vector3] = []
	var half := Vector3.ZERO
	for i in 3:
		var column := xf.basis[i]
		var length := column.length()
		axes.append(column / maxf(length, 1e-6))
		half[i] = aabb.size[i] * 0.5 * length
	return [xf * aabb.get_center(), axes, half]


## How far two oriented boxes (_box()) overlap: the least overlap over the 15
## separating axes, 0 when one separates them.
static func _overlap(a: Array, b: Array) -> float:
	var axes: Array[Vector3] = []
	axes.append_array(a[1])
	axes.append_array(b[1])
	for u: Vector3 in a[1]:
		for v: Vector3 in b[1]:
			var cross := u.cross(v)
			if cross.length_squared() > 1e-6:
				axes.append(cross.normalized())
	var apart: Vector3 = b[0] - a[0]
	var least := INF
	for axis in axes:
		var gap := _radius(a, axis) + _radius(b, axis) - absf(apart.dot(axis))
		if gap <= 0.0:
			return 0.0
		least = minf(least, gap)
	return least


static func _radius(box: Array, axis: Vector3) -> float:
	var half: Vector3 = box[2]
	var axes: Array = box[1]
	var r := 0.0
	for i in 3:
		r += half[i] * absf((axes[i] as Vector3).dot(axis))
	return r
