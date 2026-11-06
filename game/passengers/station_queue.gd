class_name StationQueue
extends RefCounted
## The external queue rules of a desk or security station, on PassengerSim's
## {"lane", "holding"} record: shared with SecurityForecast's replay, so the
## forecast moves a queue as the sim does.
##
## A station's line is its lane cells then its hold cells
## (TerminalLayout.line_of()); member i of its queue (the lane, then the
## holding list) has line[i] as its place (decision full-queue-design-a-derived-
## hold-line-behind-each-lane-gives). The line's order is the order people
## stand in (decision hold-line-rebuild-the-security-line-follows-where-people-
## sta): a walker committed to the station enters the queue, as its last
## member, when it stands on or steps onto the tail cell (tail(): past every
## cell a member stands on or steps onto, and past an admitted passenger still
## on the line), so the members stand with no gap; walkers entering on one
## tick go by line index, then the walk still to go, then id. The walkers
## off the queue are given the cells behind the tail nearest first, so the
## cell a walker chose gives it no priority. All of it is settled once a tick,
## before anyone steps (arrive()), by PassengerSim and SecurityForecast alike.


## Moves passengers from the holding list into free places at the back of
## the lane, first come first; returns them. Each keeps its index in the
## queue, so its place on the line.
static func promote(queue: Dictionary, cells: Array) -> Array[int]:
	var moved: Array[int] = []
	var lane: Array = queue["lane"]
	var holding: Array = queue["holding"]
	while not holding.is_empty() and lane.size() < cells.size():
		var id: int = holding.pop_front()
		lane.append(id)
		moved.append(id)
	return moved


## Puts passenger `id` at the back of the lane, or in the holding list when
## the lane is full; returns whether it got a lane place.
static func join(queue: Dictionary, cells: Array, id: int) -> bool:
	if (queue["lane"] as Array).size() < cells.size():
		(queue["lane"] as Array).append(id)
		return true
	(queue["holding"] as Array).append(id)
	return false


## The passengers in `queue`: its lane, then its holding list.
static func members(queue: Dictionary) -> Array:
	return (queue["lane"] as Array) + (queue["holding"] as Array)


static func size_of(queue: Dictionary) -> int:
	return (queue["lane"] as Array).size() + (queue["holding"] as Array).size()


## The path from `from` to `line[index]`: along the line when `from` is on it
## (the line's steps are routable, and a turn is walked as the line turns),
## otherwise the grid's path.
static func path_to(grid: BuildGrid, line: Array, from: Vector2i, index: int) -> Array[Vector2i]:
	var at := line.find(from)
	if at < 0:
		return grid.find_path(from, line[index])
	var path: Array[Vector2i] = []
	var step := -1 if index < at else 1
	for i in range(at, index + step, step):
		path.append(line[i])
	return path


## The index of the next free cell of `line` for a walker to join on: past
## the queue's size and past every line cell a member stands on or is
## stepping onto, so a newcomer never joins on a cell a member has not left
## yet. It then joins as the queue's last member behind its place and moves
## up with the ripple (QueueRipple). `by_id` maps ids to passengers; `index`,
## when given, maps each cell of `line` to its index (line_index()).
static func free_index(queue: Dictionary, line: Array, by_id: Dictionary, index := {}) -> int:
	if index.is_empty():
		index = line_index(line)
	var free := size_of(queue)
	for at: int in 2:
		for id: int in queue["holding" if at == 1 else "lane"]:
			var p: Passenger = by_id[id]
			free = maxi(free, int(index.get(p.at, -1)) + 1)
			if p.is_moving():
				free = maxi(free, int(index.get(p.path[p.path_index + 1], -1)) + 1)
	return free


## Cell -> its index on `line`, the first when a cell repeats.
static func line_index(line: Array) -> Dictionary:
	var index := {}
	for i in line.size():
		if not index.has(line[i]):
			index[line[i]] = i
	return index


## The path from `from` to `line[index]` for a walker joining there: one that
## steps onto it facing the front of the line or across it (_faces_front()).
## When the plain way would come at it from the front side it comes round by
## line[index + 1], or, for the line's last cell, by a neighbour beside or
## behind it off the line. A walker stopping with its back to the front would
## leave its pulled roller trailing into the passenger ahead.
static func approach(grid: BuildGrid, line: Array, from: Vector2i, index: int) -> Array[Vector2i]:
	var path := path_to(grid, line, from, index)
	if path.size() < 2 or _faces_front(line, index, path[path.size() - 2]):
		return path
	var cell: Vector2i = line[index]
	var rounds: Array[Vector2i] = []
	if index + 1 < line.size():
		rounds.append(line[index + 1])
	else:
		for step: Vector2i in BuildGrid.SIDE_STEP:
			var near := cell + step
			if not line.has(near) and _faces_front(line, index, near):
				rounds.append(near)
	for near in rounds:
		if near != from and not grid.can_passenger_route(near, cell):
			continue
		var round := (
			path_to(grid, line, from, index + 1)
			if line.find(near) == index + 1
			else grid.find_path(from, near)
		)
		if not round.is_empty():
			round.append(cell)
			return round
	return path


## Whether a step from `from` onto line[index] faces the front of the line, or
## across it: never away from line[index - 1].
static func _faces_front(line: Array, index: int, from: Vector2i) -> bool:
	if index == 0:
		return true
	var step: Vector2i = line[index] - from
	var front: Vector2i = line[index - 1] - line[index]
	return step.x * front.x + step.y * front.y >= 0


## The cell index a walker to `station` waits behind: past every cell of
## `line` a passenger admitted there (Stage.SECURITY) still stands on, such as
## a security lane's first cell, where the admitted passenger unpacks; -1 when
## none does. A walker enters only behind that cell (tail(), may_enter()).
static func admitted_at(by_id: Dictionary, station: int, line: Array) -> int:
	var at := -1
	for p: Passenger in by_id.values():
		if p.stage == Passenger.Stage.SECURITY and p.station == station:
			at = maxi(at, line.find(p.at))
	return at


## The cell a walker heads for and enters the queue at, or behind: past the
## queue's members (free_index()) and past an admitted passenger still on the
## line (admitted_at()), and past `held`, the last line cell a walker waiting
## behind that admitted passenger stands on (-1: none).
static func tail(free: int, admitted: int, held := -1) -> int:
	return maxi(maxi(free, admitted + 1), held + 1)


## Whether a walker may enter `queue` now: not while an admitted passenger
## still stands on the place it would be given (index `admitted` or less).
static func may_enter(queue: Dictionary, admitted: int) -> bool:
	return size_of(queue) > admitted


## One tick's line rules, before anyone steps. `walkers` (in id order) are
## committed to a station of `queues`, whose lane cells are `lanes` and whose
## line is `lines`, by station; `by_id` maps ids to passengers.
## - A walker standing on the tail cell (tail()), or reaching it at its pace
##   on this tick (it never covers more than one cell a tick), enters the
##   queue there, by line index, then the walk still to go, then id; one
##   passing over it on its way on enters only facing the front or across the
##   line (_faces_front()), when no other walker heads there. One that
##   reaches its cell walks just onto it and stops; the cells it walked stay,
##   so its last step is kept (SecurityLooks.carry_front() reads it).
## - A walker standing on a cell a member holds or takes steps off it
##   (step_off()); one stepping onto the cell it was heading for while the
##   queue holds it, or onto one another entered at on this tick, turns back
##   on its step (turn_back()); one passing over a member's cell walks on.
## - Behind an admitted passenger still on the line a walker does not enter
##   (may_enter()): it stops on its cell and waits there, and the tail is
##   behind it.
## - Then the walkers off the queue, nearest the tail first (from the cell each
##   last reached), then id, are given the cells behind the tail in turn: a moving one heading for a
##   cell the queue holds is sent on toward its cell (send_to()), a standing
##   one sets off for it (approach()); one with no way there is put in
##   `stranded`.
## Returns the walkers that entered, in order, a moving one with halt_tick
## `now`.
static func arrive(
	grid: BuildGrid,
	queues: Dictionary,
	lanes: Dictionary,
	lines: Dictionary,
	walkers: Array,
	by_id: Dictionary,
	now: int,
	stranded: Array = []
) -> Array[Passenger]:
	var indexes := {}
	var arrivals := []
	for w: Passenger in walkers:
		if not lines.has(w.station) or not queues.has(w.station):
			continue
		if not indexes.has(w.station):
			indexes[w.station] = line_index(lines[w.station])
		var index: Dictionary = indexes[w.station]
		if not w.is_moving():
			if index.has(w.at):
				arrivals.append([w.station, index[w.at], 0, w.id, w, false])
			continue
		var next := w.path[w.path_index + 1]
		var need := Passenger.segment_mm(w.at, next) - w.seg_mm
		if index.has(next) and need <= w.pace_mm():
			arrivals.append([w.station, index[next], need, w.id, w, true])
	arrivals.sort_custom(_before)
	var ends := {}
	for w: Passenger in walkers:
		if w.is_moving():
			var end := w.path_end()
			var key := Vector3i(w.station, end.x, end.y)
			ends[key] = ends.get(key, 0) + 1
	var joined: Array[Passenger] = []
	var lost := {}
	var taken := {}
	var admitted := {}
	var held := {}
	for entry: Array in arrivals:
		var station: int = entry[0]
		var at: int = entry[1]
		var w: Passenger = entry[4]
		var moving: bool = entry[5]
		var queue: Dictionary = queues[station]
		var line: Array = lines[station]
		if not admitted.has(station):
			admitted[station] = admitted_at(by_id, station, line)
		var free := free_index(queue, line, by_id, indexes[station])
		var into: Vector2i = line[at]
		if at < free:
			if not moving:
				# Standing on a cell a member holds or takes on this tick.
				lost[w.id] = true
				step_off(grid, w, line)
			elif taken.has(Vector3i(station, into.x, into.y)) or w.path_end() == into:
				# Stepping onto the cell it was heading for, now held, or one
				# another entered at on this tick: it turns back.
				lost[w.id] = true
				turn_back(w)
			continue
		var to := tail(free, admitted[station], held.get(station, -1))
		if at < to or (at > to and may_enter(queue, admitted[station])):
			# Off the tail cell: one further back heads for it, with no gap.
			continue
		# One passing over a cell on its way on enters there only on the tail
		# cell itself, facing the front, and when no other walker heads there:
		# a route that crosses the line further back does not make it walk the
		# line from there.
		var passing := moving and w.path_index + 2 < w.path.size()
		var headed: bool = ends.get(Vector3i(station, into.x, into.y), 0) > 0
		if passing and (headed or not _faces_front(line, at, w.at)):
			continue
		if not may_enter(queue, admitted[station]):
			# Behind an admitted passenger: it stops here and waits.
			if moving:
				w.walk(entry[2])
				_stop_here(w)
				w.halt_tick = now
			held[station] = maxi(held.get(station, -1), at)
			continue
		if moving:
			w.walk(entry[2])
			_stop_here(w)
			w.halt_tick = now
		join(queue, lanes[station], w.id)
		joined.append(w)
		taken[Vector3i(station, into.x, into.y)] = true
	# The queues no longer change on this tick. By station, the walkers off
	# the queue are given the cells behind the tail in turn.
	var outside := {}
	for w: Passenger in walkers:
		if lost.has(w.id) or joined.has(w) or not lines.has(w.station):
			continue
		if not queues.has(w.station):
			continue
		if not outside.has(w.station):
			outside[w.station] = []
		(outside[w.station] as Array).append(w)
	for station: int in outside:
		var line: Array = lines[station]
		if not indexes.has(station):
			indexes[station] = line_index(line)
		if not admitted.has(station):
			admitted[station] = admitted_at(by_id, station, line)
		var index: Dictionary = indexes[station]
		var free := free_index(queues[station], line, by_id, index)
		var base := tail(free, admitted[station])
		var waiting := _held_at(queues[station], walkers, index, admitted[station], free, station)
		var to := tail(free, admitted[station], maxi(held.get(station, -1), waiting))
		var blocked := not may_enter(queues[station], admitted[station])
		var heading: Array = []
		for w: Passenger in outside[station]:
			if blocked and not w.is_moving() and int(index.get(w.at, -1)) >= base:
				# Waiting behind an admitted passenger, on its cell.
				continue
			heading.append(w)
		# Nearest the tail first, from the cell each last reached, then id: the
		# order changes only on a tick someone reaches a cell or the tail moves.
		var mark: Vector2i = line[mini(to, line.size() - 1)]
		heading.sort_custom(
			func(a: Passenger, b: Passenger) -> bool:
				var da := _cells_to(a.at, mark)
				var db := _cells_to(b.at, mark)
				return da < db or (da == db and a.id < b.id)
		)
		for j in heading.size():
			var w: Passenger = heading[j]
			var k: int = to + j
			if w.is_moving():
				# Only one heading for a cell the queue now holds is sent on: one
				# heading for a cell behind the tail keeps its way, and one
				# turning back or stepping off the line finishes that first.
				if int(index.get(w.path_end(), to)) < to:
					send_to(grid, w, line, k, free)
			elif k < line.size() and w.at != line[k]:
				var path := approach(grid, line, w.at, k)
				if path.size() >= 2:
					w.set_path(path)
				elif path.is_empty():
					stranded.append(w)
	_pass_centres(queues, walkers, lost, by_id)
	return joined


## The last line cell at or behind the tail that a standing walker waits on
## behind an admitted passenger, or -1 (arrive()).
static func _held_at(
	queue: Dictionary, walkers: Array, index: Dictionary, admitted: int, free: int, station: int
) -> int:
	if may_enter(queue, admitted):
		return -1
	var held := -1
	for w: Passenger in walkers:
		if w.station == station and not w.is_moving():
			var at: int = index.get(w.at, -1)
			if at >= tail(free, admitted):
				held = maxi(held, at)
	return held


## Octile distance in cells, times 2 (a diagonal step is 3), from `a` to `b`.
static func _cells_to(a: Vector2i, b: Vector2i) -> int:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return 2 * maxi(dx, dy) + mini(dx, dy)


## Stops walker `w` on the cell it has just reached, keeping the cells it
## walked.
static func _stop_here(w: Passenger) -> void:
	var walked: Array[Vector2i] = []
	walked.assign(w.path.slice(0, w.path_index + 1))
	w.path = walked


## A walker that would end this tick exactly on the centre of a cell a queue
## member stands on, and walk on from it, is taken 1 mm further now, so it is
## never left standing on that centre between two ticks.
static func _pass_centres(
	queues: Dictionary, walkers: Array, lost: Dictionary, by_id: Dictionary
) -> void:
	var held := {}
	for queue: Dictionary in queues.values():
		for id: int in members(queue):
			if by_id.has(id):
				held[(by_id[id] as Passenger).at] = true
	for w: Passenger in walkers:
		if lost.has(w.id) or not w.is_moving() or w.path_index + 2 >= w.path.size():
			continue
		var next := w.path[w.path_index + 1]
		if held.has(next) and Passenger.segment_mm(w.at, next) - w.seg_mm == w.pace_mm():
			w.walk(1)


## Sends standing walker `w` off its cell of `line`: back to the cell it came
## from when that is off the line, else to the first neighbour off the line it
## may step to, straight ones first. It stays when there is none.
static func step_off(grid: BuildGrid, w: Passenger, line: Array) -> void:
	var cells: Array[Vector2i] = []
	if w.path_index >= 1:
		cells.append(w.path[w.path_index - 1])
	for step: Vector2i in BuildGrid.SIDE_STEP:
		cells.append(w.at + step)
	for step: Vector2i in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		cells.append(w.at + step)
	for cell in cells:
		if not line.has(cell) and grid.can_passenger_route(w.at, cell):
			var off: Array[Vector2i] = [w.at, cell]
			w.set_path(off)
			return


## Ordering of arrive()'s entries [station, line index, walk to go, id, ...]:
## by station, line index, the walk still to go (none for one standing), then
## id: where each stands along the line.
static func _before(a: Array, b: Array) -> bool:
	for i in [0, 1, 2, 3]:
		if a[i] != b[i]:
			return a[i] < b[i]
	return false


## Turns walker `w` back on the step it is on, where it is: the same point,
## now walked from the cell ahead back to the one it came from, where it
## stops. A walker still on its cell just stays there.
static func turn_back(w: Passenger) -> void:
	if w.seg_mm == 0:
		w.clear_path()
		return
	var next := w.path[w.path_index + 1]
	var walked := Passenger.segment_mm(w.at, next) - w.seg_mm
	var turned: Array[Vector2i] = [next, w.at]
	w.at = next
	w.set_path(turned)
	w.seg_mm = walked


## Sends moving walker `w` on toward line[`index`]: on from the cell it steps
## to, or turning back where it is when that way is shorter. Past the line's
## end (no cell for it yet) it stops at the end of its step, turning back
## mid-step only if it is stepping onto a cell a member holds (index below
## `free`, free_index()), and waits. One already heading there is left as it
## is.
static func send_to(grid: BuildGrid, w: Passenger, line: Array, index: int, free: int) -> void:
	var next := w.path[w.path_index + 1]
	var seg := Passenger.segment_mm(w.at, next)
	if index >= line.size():
		var into := line.find(next)
		if into < 0 or into >= free:
			if w.path_index + 2 < w.path.size():
				var stop: Array[Vector2i] = []
				stop.assign(w.path.slice(0, w.path_index + 2))
				_keep_step(w, stop)
		else:
			var walked := seg - w.seg_mm
			var turned: Array[Vector2i] = [next, w.at]
			w.at = next
			w.set_path(turned)
			w.seg_mm = walked
		return
	if w.path_end() == line[index]:
		return
	var ahead := _approach_or_here(grid, line, next, index)
	var back := _approach_or_here(grid, line, w.at, index)
	var via_ahead := seg - w.seg_mm + Passenger.path_mm(ahead)
	var via_back := w.seg_mm + Passenger.path_mm(back)
	if not back.is_empty() and (ahead.is_empty() or via_back < via_ahead):
		if w.seg_mm == 0:
			w.set_path(back)
			return
		# Turned round mid-step: the same point, seen from the cell ahead.
		var turned: Array[Vector2i] = [next]
		turned.append_array(back)
		var walked := seg - w.seg_mm
		w.at = next
		w.set_path(turned)
		w.seg_mm = walked
	elif not ahead.is_empty():
		var path: Array[Vector2i] = []
		path.assign(w.path.slice(0, w.path_index + 1))
		path.append_array(ahead)
		_keep_step(w, path)


## Gives walker `w` the new `path`, which starts with the cells it walked, and
## keeps it where it is along its step.
static func _keep_step(w: Passenger, path: Array[Vector2i]) -> void:
	var index := w.path_index
	var walked := w.seg_mm
	w.path = path
	w.path_index = index
	w.seg_mm = walked


## approach(), or just [from] when it stands on line[index] already.
static func _approach_or_here(
	grid: BuildGrid, line: Array, from: Vector2i, index: int
) -> Array[Vector2i]:
	if from == line[index]:
		var here: Array[Vector2i] = [from]
		return here
	return approach(grid, line, from, index)
