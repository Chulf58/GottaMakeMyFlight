class_name FileWaiters
extends RefCounted
## Wait spots for walkers waiting to join a boarding file (board 3e3cb33e; the
## sim fixes each cause, decision passenger-spacing-fixed-per-cause-standing-
## spots-staggered-unloading-ordered-files). A walker that chose its exit where
## it stands waits there to join its door file (BoardingFiles), so walkers that
## chose it on one point would wait on it together. When a walker becomes
## pending (assign()) within BoardingFiles.GAP_MM of a walker already waiting
## (pending, or filed with no room to step), it is given a wait spot: the first
## of WAIT_SPOTS, behind or beside its point, that is GAP_MM from each of them
## and that it can stand on (BODY_M clear, reached in a straight line over
## steps a passenger can route). It walks there in the sim while it waits
## (step()), and once it joins its file it walks back to its point before it
## walks on: the files count that walk back as walk left (BoardingFiles), and
## the forecast counts what is owed of it (owed_mm()). A walker given no spot
## because none is free does not join (BoardingFiles.join_door()): it gives up
## its exit and stands where it is, choosing again on its next step.
##
## A spot is fixed when given and kept until the walker is back on its point
## or leaves the walk out (forget()); it is saved (to_list()) and checked on
## load against the loaded grid (load_list()). Not guaranteed: walkers already
## on one point when they turn out (none free and nowhere to stand) stay
## there; waiters are not spaced from walkers with room to step or from anyone
## not heading out.

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
## How finely the walk from a waiter's own point to its spot is checked for
## walls, in metres.
const SAMPLE_M := 0.1
const CROWD_M := BoardingFiles.GAP_MM / 1000.0
## The room a waiter needs from each one before it: CROWD_M, less a
## millimetre so a spot exactly CROWD_M away is not lost to rounding.
const ROOM_M := CROWD_M - 0.001
## The farthest a spot can be from its walker's point, in mm.
const FARTHEST_MM := 1566

## Passenger id -> {"off": Vector2i, the spot from its own point in grid-local
## mm; "at": int, mm walked from its point toward the spot}.
var _spots: Dictionary = {}


## Gives pending walker `p` of `files` a wait spot if it stands within GAP_MM
## of a walker already waiting. Returns false when it needs one and none is
## free; true when it has one or needs none.
func assign(sim: PassengerSim, files: BoardingFiles, p: Passenger) -> bool:
	if _spots.has(p.id):
		return true
	var own := own_point(sim, p)
	var waiting: Array[Passenger] = files.pending_order(sim)
	for id in files.door_file(p.exit_object):
		var filed := sim.get_passenger(id)
		if files.allowed(sim, filed, PassengerSim.WALK_MM) == 0:
			waiting.append(filed)
	var placed: Array[Vector2] = []
	for q in waiting:
		if q.id != p.id:
			# Where it will stand: its spot, if it is walking there.
			placed.append(own_point(sim, q) + spot_of(q.id))
	if _clearance(own, placed) >= ROOM_M:
		return true
	var spot := _free_spot(sim, files, p, own, placed)
	if spot == own:
		return false
	var off := Vector2i(((spot - own) * 1000.0).round())
	_spots[p.id] = {"off": off, "at": 0, "out": true}
	return true


## The ids with a wait spot, lowest first.
func ids() -> Array[int]:
	var out: Array[int] = []
	out.assign(_spots.keys())
	out.sort()
	return out


## `id`'s wait spot from its own point, in grid-local metres; zero with none.
func spot_of(id: int) -> Vector2:
	return Vector2(_spots[id]["off"]) / 1000.0 if _spots.has(id) else Vector2.ZERO


## How far `p` stands from its own point now, in metres on the ground.
func shift(p: Passenger) -> Vector3:
	if not _spots.has(p.id) or p.stage != Passenger.Stage.TO_EXIT:
		return Vector3.ZERO
	var s: Dictionary = _spots[p.id]
	var off: Vector2i = s["off"]
	var share: float = s["at"] / Vector2(off).length()
	return Vector3(off.x, 0.0, off.y) * share / 1000.0


## The walk `p` has to its spot and back that it has not walked yet, in mm.
func owed_mm(id: int) -> int:
	if not _spots.has(id):
		return 0
	var length := _length(_spots[id])
	return 2 * length - _spots[id]["at"] if _spots[id].get("out", true) else _spots[id]["at"]


## The walk back from where `id` stands to its own point, in mm: walk left in
## the files on top of its path.
func back_mm(id: int) -> int:
	return _spots[id]["at"] if _spots.has(id) else 0


## Whether `p` stands on its spot, there to wait.
func at_spot(p: Passenger) -> bool:
	return _spots.has(p.id) and _spots[p.id]["at"] == _length(_spots[p.id])


## One tick of `p`'s walk, `step` its room in the files and `speed` its pace:
## a pending walker walks out to its spot; a filed one walks back to its point
## first. Returns the step left for its path.
func step(p: Passenger, pending: bool, step_mm: int, speed: int) -> int:
	if not _spots.has(p.id):
		return step_mm
	var s: Dictionary = _spots[p.id]
	var length := _length(s)
	var walked := 0
	if pending:
		s["out"] = true
		walked = mini(speed, length - s["at"])
		s["at"] += walked
	else:
		s["out"] = false
		walked = mini(step_mm, s["at"])
		s["at"] -= walked
		if s["at"] == 0:
			_spots.erase(p.id)
	p.odometer_mm += walked
	# A pending walker has no room on its path (BoardingFiles.allowed()).
	return 0 if pending else step_mm - walked


## `id` has left the walk out: its spot is given up.
func forget(id: int) -> void:
	_spots.erase(id)


## The spots for a save, by passenger id.
func to_list() -> Array:
	var ids: Array = _spots.keys()
	ids.sort()
	var out := []
	for id: int in ids:
		var s: Dictionary = _spots[id]
		var off: Vector2i = s["off"]
		out.append({"id": id, "x": off.x, "y": off.y, "at": s["at"], "out": s.get("out", true)})
	return out


## Loads a saved to_list(): every waiter is heading for its exit, its spot one
## it can stand on in the loaded grid, at most FARTHEST_MM out, and walked at
## most to it (BoardingFiles.checked() then checks each is held in the files).
## Returns a problem, or "".
func load_list(list: Variant, by_id: Dictionary, sim: PassengerSim) -> String:
	if typeof(list) != TYPE_ARRAY:
		return "boarding waiters must be a list"
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
		var off := Vector2i(int(entry["x"]), int(entry["y"]))
		var s := {"off": off, "at": int(entry["at"]), "out": entry["out"]}
		var length := _length(s) if off != Vector2i.ZERO else 0
		if (
			p == null
			or _spots.has(id)
			or p.stage != Passenger.Stage.TO_EXIT
			or length == 0
			or length > FARTHEST_MM
			or s["at"] < 0
			or s["at"] > length
		):
			return "boarding waiter %d is unknown, repeated, not waiting or off its spot" % id
		var own := own_point(sim, p)
		if not _standable(sim.grid, own, own + Vector2(off) / 1000.0):
			return "boarding waiter %d's spot cannot be stood on" % id
		_spots[id] = s
	return ""


## Where `p` stands with no spot, in grid-local metres: its sim position less
## its walk toward a spot (the sim's own spots: on load, those of the files it
## still has).
static func own_point(sim: PassengerSim, p: Passenger) -> Vector2:
	var at := sim.world_position(p) - sim.grid.origin - sim.files.waiters.shift(p)
	return Vector2(at.x, at.z)


static func _length(s: Dictionary) -> int:
	return roundi(Vector2(s["off"]).length())


## The first WAIT_SPOTS spot round `own` (grid-local metres) that `p` can
## stand on, CROWD_M from every point in `placed`; `own` with none.
static func _free_spot(
	sim: PassengerSim, files: BoardingFiles, p: Passenger, own: Vector2, placed: Array[Vector2]
) -> Vector2:
	var ahead := _way_out(sim, files, p, own)
	var left := Vector2(ahead.y, -ahead.x)
	for at in WAIT_SPOTS:
		var spot := own + (left * at.y - ahead * at.x) * CROWD_M
		if _standable(sim.grid, own, spot) and _clearance(spot, placed) >= ROOM_M:
			return spot
	return own


## The ground direction `p` waits to walk in from `own`: its path's next step,
## or at its door the start of its walk outside; straight up the grid with
## neither.
static func _way_out(
	sim: PassengerSim, files: BoardingFiles, p: Passenger, own: Vector2
) -> Vector2:
	var way := Vector2.ZERO
	if p.is_moving():
		way = Vector2(p.path[p.path_index + 1] - p.path[p.path_index])
	else:
		var points: Array = files.apron_of(sim, p.exit_object)["points"]
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


## The distance from `spot` to the nearest point in `placed`; INF with none.
static func _clearance(spot: Vector2, placed: Array[Vector2]) -> float:
	var room := INF
	for other in placed:
		room = minf(room, spot.distance_to(other))
	return room
