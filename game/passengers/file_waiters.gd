class_name FileWaiters
extends RefCounted
## Wait spots for walkers waiting to join a boarding file (board 3e3cb33e; the
## sim fixes each cause, decision passenger-spacing-fixed-per-cause-standing-
## spots-staggered-unloading-ordered-files). A pending walker waits where it
## chose its exit (BoardingFiles), so walkers that chose it on one point would
## wait on it together.
##
## Placing (place(), run whenever a walker turns or stays pending, so every
## tick in BoardingFiles.pending_order()): each pending walker with no spot that
## stands within GAP_MM of another waiter (a pending walker, a walker on or
## walking to or from a spot, or a filed walker with no room to step) is given
## the first of WAIT_SPOTS, beside or behind its point, that it can stand on
## (BODY_M clear, reached in a straight line over steps a passenger can route),
## that is GAP_MM from every other waiter's place, from the walks back of
## those on spots and from passengers on standing spots, and whose straight
## walk comes no nearer to any of them than GAP_MM or than it already stands.
## Only a waiter placed before it, or one walking back, crowds it. With
## none free it stays pending with its exit, on its own point, and is placed
## again on the next pass: a spot frees when its waiter joins its file, a
## walker ahead moves on or a file admits someone. Lateness gets no priority.
##
## Walking (step()): a pending walker walks out to its spot and waits there.
## It joins its file only once its walk back comes no nearer to anyone than
## the gap or than it stands (may_return()). Once it joins, or its spot is
## dropped (drop(): its exit or route changed and it left the files, or a grid
## edit made the spot or the walk to it impossible), it walks straight back to
## its point before anything else, so its position never jumps. The files count
## that walk back as walk left for the walkers behind it (BoardingFiles._left());
## the forecast counts what is owed (owed_mm()).
##
## Saved (to_list()) and checked on load (load_list()) against the loaded grid
## and standing claims. Not guaranteed: walkers already on one point when they
## turn out (the stack comes from upstream) wait there until placed; a walk
## back over a wall built since crosses it.

## Where a waiter may stand, in GAP_MM, in the order tried: (behind its own
## point, to its left), facing its way out. Beside first, straight behind
## last: the walkers coming up its file walk in along the line behind it.
const WAIT_SPOTS: Array[Vector2] = [
	Vector2(0, 1),
	Vector2(0, -1),
	Vector2(1, 1),
	Vector2(1, -1),
	Vector2(2, 1),
	Vector2(2, -1),
	Vector2(1, 0),
	Vector2(2, 0),
]
## How far a waiter's body reaches round its point, in metres.
const BODY_M := 0.25
## How finely a walk to or from a spot is checked, in metres.
const SAMPLE_M := 0.1
const CROWD_M := BoardingFiles.GAP_MM / 1000.0
## The room a waiter needs from each other one: CROWD_M, less a millimetre so
## a spot exactly CROWD_M away is not lost to rounding.
const ROOM_M := CROWD_M - 0.001
## How far a saved spot may be from the offset WAIT_SPOTS gives, in mm.
const SAVED_SLACK_MM := 2
## Which places _others() takes: for a new spot, for whether a walker is
## crowded, and for a walk back.
const PLACING := 0
const CROWDING := 1
const RETURNING := 2

## Passenger id -> {"off": Vector2i, the spot from its own point in grid-local
## mm; "at": int, mm out from its point; "out": bool, true while it walks to
## or waits on the spot, false once it walks back}.
var _spots: Dictionary = {}


## Places the pending walkers of `files` (the header's "Placing").
func place(sim: PassengerSim, files: BoardingFiles) -> void:
	var order := files.pending_order(sim)
	var taken := _taken(sim, files, order)
	for rank in order.size():
		var p := order[rank]
		if _spots.has(p.id):
			continue
		var own := own_point(sim, p)
		# Crowded only by a waiter placed before it: the first of walkers on
		# one point keeps the point.
		if _clearance(own, _others(taken, p.id, rank, CROWDING)) >= ROOM_M:
			continue
		var others := _others(taken, p.id, order.size())
		var spot := _free_spot(sim, files, p, own, others)
		if spot == own:
			continue
		_spots[p.id] = {"off": Vector2i(((spot - own) * 1000.0).round()), "at": 0, "out": true}
		taken.append_array(_kept(p.id, own, spot))


## Whether `p` may join its file now: true unless it keeps a wait spot it
## has not reached yet (so the walk owed, owed_mm(), that orders the pending
## walkers and the forecast is the walk it will make), or one whose straight
## walk back to its point would come nearer to another waiter of `files` than
## the gap or than it now stands.
func may_return(sim: PassengerSim, files: BoardingFiles, p: Passenger) -> bool:
	if not _spots.has(p.id) or not _spots[p.id]["out"]:
		return true
	if not at_spot(p):
		return false
	var order := files.pending_order(sim)
	var others := _others(_taken(sim, files, order), p.id, order.size(), RETURNING)
	var own := own_point(sim, p)
	return _walk_clear(own + _ground(shift(p)), own, others)


## The ids with a wait spot, lowest first.
func ids() -> Array[int]:
	var out: Array[int] = []
	out.assign(_spots.keys())
	out.sort()
	return out


## How far `p` stands from its own point now, in metres on the ground.
func shift(p: Passenger) -> Vector3:
	if not _spots.has(p.id):
		return Vector3.ZERO
	var s: Dictionary = _spots[p.id]
	var off: Vector2i = s["off"]
	var share: float = s["at"] / Vector2(off).length()
	return Vector3(off.x, 0.0, off.y) * share / 1000.0


## The walk to its spot and back that `id` has not walked yet, in mm.
func owed_mm(id: int) -> int:
	if not _spots.has(id):
		return 0
	var s: Dictionary = _spots[id]
	return 2 * _length(s) - s["at"] if s["out"] else s["at"]


## The walk back from where `id` stands to its own point, in mm.
func back_mm(id: int) -> int:
	return _spots[id]["at"] if _spots.has(id) else 0


## Whether `p` stands on its spot, there to wait.
func at_spot(p: Passenger) -> bool:
	if not _spots.has(p.id):
		return false
	var s: Dictionary = _spots[p.id]
	return s["out"] and s["at"] == _length(s)


## `id`'s spot is given up (its exit or route changed): it walks back.
func drop(id: int) -> void:
	if _spots.has(id):
		_spots[id]["out"] = false


## `id` has left the walk out: its spot is forgotten.
func forget(id: int) -> void:
	_spots.erase(id)


## One tick of `p`'s walk (the header's "Walking"), `step_mm` its room in the
## files and `speed` its pace. Returns the step left for its path.
func step(sim: PassengerSim, p: Passenger, pending: bool, step_mm: int, speed: int) -> int:
	if not _spots.has(p.id):
		return step_mm
	var s: Dictionary = _spots[p.id]
	var own := own_point(sim, p)
	if s["out"] and not _standable(sim.grid, own, own + Vector2(s["off"]) / 1000.0):
		s["out"] = false
	var walked := 0
	if pending and s["out"]:
		walked = mini(speed, _length(s) - s["at"])
		s["at"] += walked
	else:
		s["out"] = false
		walked = mini(speed if pending else step_mm, s["at"])
		s["at"] -= walked
		if s["at"] == 0:
			_spots.erase(p.id)
	p.odometer_mm += walked
	# A pending walker has no room on its path (BoardingFiles.allowed()).
	return 0 if pending else step_mm - walked


## The spots for a save, by passenger id.
func to_list() -> Array:
	var out := []
	for id in ids():
		var s: Dictionary = _spots[id]
		var off: Vector2i = s["off"]
		out.append({"id": id, "x": off.x, "y": off.y, "at": s["at"], "out": s["out"]})
	return out


## Loads a saved to_list() for the passengers `by_id`, with `files` being
## loaded and `standing` the loaded standing claims (checked_standing()): each
## entry names a passenger not done, once, walked out 1 mm or more and at most
## its spot's length; a spot still kept ("out") belongs to a walker heading
## for its exit, sits within SAVED_SLACK_MM of a WAIT_SPOTS offset for that
## walker's way out, can be stood on and walked to in the loaded grid, is
## GAP_MM from every other kept spot, and of each two kept walks one keeps
## clear of the other as placing a later spot does; a walk back is from a
## WAIT_SPOTS offset for some grid heading (_back_problem()).
## BoardingFiles.checked() then checks each kept spot's walker is pending.
## Returns a problem, or "".
func load_list(
	list: Variant, by_id: Dictionary, sim: PassengerSim, files: BoardingFiles, standing: Dictionary
) -> String:
	if typeof(list) != TYPE_ARRAY:
		return "boarding waiters must be a list"
	var kept: Array = []
	for entry: Variant in list:
		var keys := ["id", "x", "y", "at"]
		if (
			typeof(entry) != TYPE_DICTIONARY
			or (entry as Dictionary).size() != 5
			or typeof(entry.get("out")) != TYPE_BOOL
			or not keys.all(func(k: String) -> bool: return WholeNumber.is_whole(entry.get(k)))
		):
			return "boarding waiter %s is malformed" % str(entry).left(80)
		var id := int(entry["id"])
		var p: Passenger = by_id.get(id)
		var s := {"off": Vector2i(int(entry["x"]), int(entry["y"])), "at": int(entry["at"])}
		s["out"] = entry["out"]
		if p == null or p.is_done() or _spots.has(id) or s["at"] < 1 or s["at"] > _length(s):
			return "boarding waiter %d is unknown, repeated or off its walk" % id
		var own := _loaded_base(sim, p, standing)
		var problem := ""
		if s["out"]:
			problem = _kept_problem(sim, files, p, own, s["off"])
		else:
			problem = _back_problem(sim, p, own, s)
		if problem != "":
			return problem
		if s["out"]:
			var spot := own + Vector2(s["off"]) / 1000.0
			for other: Array in kept:
				if spot.distance_to(other[2]) < ROOM_M or not _either_after(own, spot, other):
					return "boarding waiters %d and %d wait or walk within the gap" % [other[0], id]
			kept.append([id, own, spot])
		_spots[id] = s
	return ""


## Why returning entry `s` of `p` (its point `own`) is not a walk back from a
## spot it could have been given, or "": the spot a WAIT_SPOTS offset for a
## walker heading along any of the eight grid steps (its route may have changed
## since), and the walk back from where it stands one it can make.
static func _back_problem(sim: PassengerSim, p: Passenger, own: Vector2, s: Dictionary) -> String:
	var off := Vector2(s["off"])
	var given := false
	for step: Vector2i in StandingSpots.STEPS:
		var ahead := Vector2(step).normalized()
		var left := Vector2(ahead.y, -ahead.x)
		for at in WAIT_SPOTS:
			if (
				((left * at.y - ahead * at.x) * BoardingFiles.GAP_MM).distance_to(off)
				<= SAVED_SLACK_MM
			):
				given = true
	var share: float = s["at"] / off.length()
	var now := own + off / 1000.0 * share
	if not given or not _standable(sim.grid, own, now):
		return "boarding waiter %d walks back from a spot it could not have been given" % p.id
	return ""


## Whether one of two kept walks, `own` to `spot` and other's [id, own, spot],
## keeps clear of the other as placing a later spot does (place()).
static func _either_after(own: Vector2, spot: Vector2, other: Array) -> bool:
	var theirs: Array[Vector2] = _walk_points(other[1], other[2])
	var mine: Array[Vector2] = _walk_points(own, spot)
	var me_after := _clearance(spot, theirs) >= ROOM_M and _walk_clear(own, spot, theirs)
	var them_after := _clearance(other[2], mine) >= ROOM_M and _walk_clear(other[1], other[2], mine)
	return me_after or them_after


## A kept spot and its walk back, every SAMPLE_M, as placing sees them.
static func _walk_points(own: Vector2, spot: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for entry: Array in _kept(0, own, spot):
		out.append(entry[1])
	return out


## Whether every kept spot's walker is pending in `files`, or a problem.
func held_problem(files: BoardingFiles) -> String:
	for id in ids():
		if _spots[id]["out"] and not files.is_pending(id):
			return "boarding waiter %d keeps a spot but is not waiting to join" % id
	return ""


## Where `p` stands with no spot, in grid-local metres: its sim position less
## its walk toward a spot.
static func own_point(sim: PassengerSim, p: Passenger) -> Vector2:
	var at := sim.world_position(p) - sim.grid.origin - sim.files.waiters.shift(p)
	return Vector2(at.x, at.z)


## Where loaded walker `p` stands with no spot: on its loaded standing spot if
## it set off from one and has not stepped yet, else its path's point.
static func _loaded_base(sim: PassengerSim, p: Passenger, standing: Dictionary) -> Vector2:
	var claims: Dictionary = standing.get("claims", {})
	if claims.has(p.id) and p.path_index == 0 and p.seg_mm == 0:
		var spots: StandingSpots = standing["spots"]
		var at := spots.world_of(sim.grid, claims[p.id]) - sim.grid.origin
		return Vector2(at.x, at.z)
	return p.grid_position()


## Why kept spot `off` (mm) is not one `p` on `own` could have been given, or "".
static func _kept_problem(
	sim: PassengerSim, files: BoardingFiles, p: Passenger, own: Vector2, off: Vector2i
) -> String:
	if p.stage != Passenger.Stage.TO_EXIT or p.exit_object == 0:
		return "boarding waiter %d keeps a spot but is not heading for an exit" % p.id
	var spot := own + Vector2(off) / 1000.0
	var given := _offsets(sim, files, p, own).any(
		func(at: Vector2) -> bool: return (at * 1000.0).distance_to(Vector2(off)) <= SAVED_SLACK_MM
	)
	if not given or not _standable(sim.grid, own, spot):
		return "boarding waiter %d keeps a spot it could not have been given" % p.id
	return ""


static func _length(s: Dictionary) -> int:
	return roundi(Vector2(s["off"]).length())


## [id, point, rank] of every waiter's place (the header's "Placing"): each
## pending walker in `order` (its own point, ranked by its place in `order`
## while it has no spot; else where it stands and its kept spot), each walker
## on its way back from a spot, and each filed walker with no room (rank -1).
func _taken(sim: PassengerSim, files: BoardingFiles, order: Array[Passenger]) -> Array:
	var taken := []
	var doors := {}
	var seen := {}
	for rank in order.size():
		var p := order[rank]
		seen[p.id] = true
		doors[p.exit_object] = true
		var own := own_point(sim, p)
		var kept := _spots.has(p.id)
		# Walking out or on its spot it crowds no one where it stands (its spot
		# does); walking back, all of its way back does.
		if not kept:
			taken.append([p.id, own, rank])
		elif _spots[p.id]["out"]:
			taken.append([p.id, own + _ground(shift(p)), -2])
			taken.append_array(_kept(p.id, own, own + Vector2(_spots[p.id]["off"]) / 1000.0))
		else:
			taken.append_array(_back(p.id, own, own + _ground(shift(p))))
	for id in ids():
		if not seen.has(id):
			var q := sim.get_passenger(id)
			taken.append_array(_back(id, own_point(sim, q), own_point(sim, q) + _ground(shift(q))))
	for door: int in doors:
		for id in files.door_file(door):
			var filed := sim.get_passenger(id)
			if not seen.has(id) and files.allowed(sim, filed, PassengerSim.WALK_MM) == 0:
				seen[id] = true
				taken.append([id, own_point(sim, filed) + _ground(shift(filed)), -1])
	# Passengers on a standing spot, about to set off: a wait spot and the walks
	# to and from it keep clear of them, though they crowd no one (the 0.6 m
	# lattice is closer than the gap).
	for id in sim.passenger_ids():
		if not seen.has(id) and sim.standing.spot_of(id) != StandingSpots.NO_SPOT:
			var q := sim.get_passenger(id)
			taken.append([id, own_point(sim, q) + _ground(shift(q)), -2])
	return taken


## The places of walker `id` keeping wait spot `spot` (its point `own`): the
## spot (crowding, rank -1), and its walk back, every SAMPLE_M (rank -3, kept
## clear by later spots so that walk back is never blocked by them).
static func _kept(id: int, own: Vector2, spot: Vector2) -> Array:
	var out := [[id, spot, -1]]
	var samples := ceili(own.distance_to(spot) / SAMPLE_M)
	for i in range(1, samples + 1):
		out.append([id, spot.lerp(own, i / float(samples)), -3])
	return out


## The places of walker `id` walking back from `at` to its point `own`: where
## it stands and the rest of its walk, every SAMPLE_M, all crowding (rank -1).
static func _back(id: int, own: Vector2, at: Vector2) -> Array:
	var out := [[id, at, -1]]
	var samples := ceili(own.distance_to(at) / SAMPLE_M)
	for i in range(1, samples + 1):
		out.append([id, at.lerp(own, i / float(samples)), -1])
	return out


## The points of `taken` that are not `id`'s and rank before `before`, by
## `mode`: PLACING takes all; CROWDING leaves out where a walker walking out
## stands (rank -2) and the walks back (rank -3); RETURNING leaves out only the
## walks back, which no one stands on yet.
static func _others(taken: Array, id: int, before: int, mode := PLACING) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for entry: Array in taken:
		var rank: int = entry[2]
		var counts := rank < before
		if mode == CROWDING:
			counts = rank >= -1 and rank < before
		elif mode == RETURNING:
			counts = rank != -3
		if entry[0] != id and counts:
			out.append(entry[1])
	return out


static func _ground(at: Vector3) -> Vector2:
	return Vector2(at.x, at.z)


## The WAIT_SPOTS offsets round `own` for `p`, in grid-local metres.
static func _offsets(
	sim: PassengerSim, files: BoardingFiles, p: Passenger, own: Vector2
) -> Array[Vector2]:
	var ahead := _way_out(sim, files, p, own)
	var left := Vector2(ahead.y, -ahead.x)
	var out: Array[Vector2] = []
	for at in WAIT_SPOTS:
		out.append((left * at.y - ahead * at.x) * CROWD_M)
	return out


## The first WAIT_SPOTS spot round `own` (grid-local metres) that `p` can
## stand on and walk to, ROOM_M from every point in `others`, whose straight
## walk comes no nearer to any of them than ROOM_M or than `own` is; `own`
## with none.
static func _free_spot(
	sim: PassengerSim, files: BoardingFiles, p: Passenger, own: Vector2, others: Array[Vector2]
) -> Vector2:
	for off in _offsets(sim, files, p, own):
		var spot := own + off
		if not _standable(sim.grid, own, spot) or _clearance(spot, others) < ROOM_M:
			continue
		if _walk_clear(own, spot, others):
			return spot
	return own


## Whether the straight walk from `own` to `spot` keeps ROOM_M, or the room it
## had at `own` if less, from every point in `others`.
static func _walk_clear(own: Vector2, spot: Vector2, others: Array[Vector2]) -> bool:
	var samples := ceili(own.distance_to(spot) / SAMPLE_M)
	for other in others:
		var need := minf(ROOM_M, own.distance_to(other)) - 0.001
		for i in range(1, samples + 1):
			if own.lerp(spot, i / float(samples)).distance_to(other) < need:
				return false
	return true


## The ground direction `p` waits to walk in from `own`: its path's next step,
## or at its door the start of its walk outside; straight up the grid with
## neither.
static func _way_out(
	sim: PassengerSim, files: BoardingFiles, p: Passenger, own: Vector2
) -> Vector2:
	var way := Vector2.ZERO
	if p.is_moving():
		way = Vector2(p.path[p.path_index + 1] - p.path[p.path_index])
	elif p.exit_object != 0:
		var points: Array = files.apron_of(sim, p.exit_object, p)["points"]
		if not points.is_empty():
			var start: Vector3 = points[0] - sim.grid.origin
			way = Vector2(start.x, start.z) - own
	return way.normalized() if way != Vector2.ZERO else Vector2(0, -1)


## Whether a waiter on `own` (grid-local metres) can stand at `spot`: the
## straight walk there crosses only steps a passenger can route, and so does
## the step from the spot's cell to each cell its body (BODY_M) reaches into.
static func _standable(grid: BuildGrid, own: Vector2, spot: Vector2) -> bool:
	var samples := ceili(own.distance_to(spot) / SAMPLE_M)
	var cell := _cell(own)
	for i in range(1, samples + 1):
		var next := _cell(own.lerp(spot, i / float(samples)))
		if next != cell and not _passes(grid, cell, next):
			return false
		cell = next
	for edge: Vector2 in [
		Vector2(BODY_M, 0), Vector2(-BODY_M, 0), Vector2(0, BODY_M), Vector2(0, -BODY_M)
	]:
		var reached := _cell(spot + edge)
		if reached != cell and not _passes(grid, cell, reached):
			return false
	return true


static func _cell(at: Vector2) -> Vector2i:
	return Vector2i(floori(at.x), floori(at.y))


## Whether a passenger can step from cell `a` to the next cell `b`: one
## routable step, or for a diagonal two through either cell beside both.
static func _passes(grid: BuildGrid, a: Vector2i, b: Vector2i) -> bool:
	var d := b - a
	if absi(d.x) + absi(d.y) == 1:
		return grid.can_passenger_route(a, b)
	if absi(d.x) != 1 or absi(d.y) != 1:
		return false
	var across := a + Vector2i(d.x, 0)
	var along := a + Vector2i(0, d.y)
	return (
		(grid.can_passenger_route(a, across) and grid.can_passenger_route(across, b))
		or (grid.can_passenger_route(a, along) and grid.can_passenger_route(along, b))
	)


## The distance from `spot` to the nearest point in `others`; INF with none.
static func _clearance(spot: Vector2, others: Array[Vector2]) -> float:
	var room := INF
	for other in others:
		room = minf(room, spot.distance_to(other))
	return room
