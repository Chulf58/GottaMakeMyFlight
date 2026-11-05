class_name FileWaiters
extends RefCounted
## Where walkers waiting to join a boarding file are drawn (board 3e3cb33e).
## A pending walker stands where it chose its exit (BoardingFiles), so walkers
## that chose it on one point wait there together, and the sim keeps them
## there. In admission order (BoardingFiles.pending_order()), each pending
## walker keeps the spot it had on the last placing while that is still
## BoardingFiles.GAP_MM from every one placed before it, so it stands still
## until it joins its file. Otherwise it is drawn on its own point when that
## is GAP_MM from them, else on the first of WAIT_SPOTS, behind or beside its
## point, that is, and that it can stand on (BODY_M clear, walked to over
## steps a passenger can route). PassengerViews moves the drawn offset at a
## walk, and back onto the walker's path once it joins.
##
## Not guaranteed: with no free spot a waiter takes the one farthest from the
## others; waiters are not drawn apart from filed walkers or from anyone else;
## a walker that joins from a spot catches up with its path at up to twice a
## walk. The placing is derived, never saved: a load places the waiters afresh.

## Where a crowded waiter may be drawn, in GAP_MM, in the order tried:
## (behind its own point, to its left), facing its way out.
const WAIT_SPOTS: Array[Vector2] = [
	Vector2(1, 0),
	Vector2(1, 1),
	Vector2(1, -1),
	Vector2(0, 1),
	Vector2(0, -1),
	Vector2(2, 0),
	Vector2(2, 1),
	Vector2(2, -1),
]
## How far a waiter's body reaches round its drawn point, in metres.
const BODY_M := 0.25
## How finely the walk from a waiter's own point to its drawn one is checked
## for walls, in metres.
const SAMPLE_M := 0.1
const CROWD_M := BoardingFiles.GAP_MM / 1000.0
## The room a waiter needs from each one placed before it: CROWD_M, less a
## millimetre so a spot exactly CROWD_M away is not lost to rounding.
const ROOM_M := CROWD_M - 0.001

## Set when the pending set changes: the waiters are placed again when asked.
var stale := true
## Pending passenger id -> its drawn offset, placed on _tick.
var _offsets: Dictionary = {}
var _tick := -1


## Forgets every placing (a load or an edit): the next one starts afresh.
func clear() -> void:
	_offsets.clear()
	stale = true


## How far pending walker `p` of `files` is drawn from its own point now, in
## metres on the ground; zero for a walker that is not pending, or one with
## room where it stands.
func offset(sim: PassengerSim, files: BoardingFiles, p: Passenger) -> Vector3:
	if not files.is_pending(p.id):
		return Vector3.ZERO
	if stale or _tick != sim.tick:
		_place(sim, files)
	return _offsets.get(p.id, Vector3.ZERO)


func _place(sim: PassengerSim, files: BoardingFiles) -> void:
	_tick = sim.tick
	stale = false
	var before := _offsets
	_offsets = {}
	var placed: Array[Vector2] = []
	for p in files.pending_order(sim):
		var own := p.grid_position()
		# A waiter keeps the spot it was given while that is still free, until
		# it joins its file: it stands still there and the others do not
		# shuffle round when one walks on.
		var kept: Vector3 = before.get(p.id, Vector3.ZERO)
		var spot := own + Vector2(kept.x, kept.z)
		var keeps := kept != Vector3.ZERO and _clearance(spot, placed) >= ROOM_M
		if not keeps or not _standable(sim.grid, own, spot):
			spot = own
			if _clearance(own, placed) < ROOM_M:
				spot = _free_spot(sim, files, p, own, placed)
		placed.append(spot)
		if spot != own:
			_offsets[p.id] = Vector3(spot.x - own.x, 0.0, spot.y - own.y)


## The first WAIT_SPOTS spot round `own` (grid-local metres) that `p` can
## stand on, CROWD_M from every point in `placed`; with none, the standable
## spot (`own` among them) farthest from them.
static func _free_spot(
	sim: PassengerSim, files: BoardingFiles, p: Passenger, own: Vector2, placed: Array[Vector2]
) -> Vector2:
	var ahead := _way_out(sim, files, p, own)
	var left := Vector2(ahead.y, -ahead.x)
	var best := own
	var best_room := _clearance(own, placed)
	for at in WAIT_SPOTS:
		var spot := own + (left * at.y - ahead * at.x) * CROWD_M
		if not _standable(sim.grid, own, spot):
			continue
		var room := _clearance(spot, placed)
		if room >= ROOM_M:
			return spot
		if room > best_room:
			best = spot
			best_room = room
	return best


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


## Whether a waiter on `own` (grid-local metres) can be drawn at `spot`: the
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
