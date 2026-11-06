class_name StationQueue
extends RefCounted
## The external queue rules of a desk or security station, on PassengerSim's
## {"lane", "holding"} record: shared with SecurityForecast's replay, so the
## forecast moves a queue as the sim does.
##
## A station's line is its lane cells then its hold cells
## (TerminalLayout.line_of()); member i of its queue (the lane, then the
## holding list) stands on line[i] (decision full-queue-design-a-derived-
## hold-line-behind-each-lane-gives). A walker committed to the station joins
## when it stands on, or reaches, line[n], n being the queue's size: the next
## free cell (arrive(), head_for()). A walker passing over line[n] on its way
## further back takes it only when no other walker is heading for it, and one
## standing further back waits while another is heading for a cell between,
## so walkers keep to the cells they chose unless one would stay empty: no
## one turns back for a cell another took.


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
## up with the ripple (QueueRipple). `by_id` maps ids to passengers.
static func free_index(queue: Dictionary, line: Array, by_id: Dictionary) -> int:
	var free := size_of(queue)
	for id: int in members(queue):
		var p: Passenger = by_id[id]
		free = maxi(free, line.find(p.at) + 1)
		if p.is_moving():
			free = maxi(free, line.find(p.path[p.path_index + 1]) + 1)
	return free


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
## none does. A walker joins only once that cell is left (walker_free()).
static func admitted_at(by_id: Dictionary, station: int, line: Array) -> int:
	var at := -1
	for p: Passenger in by_id.values():
		if p.stage == Passenger.Stage.SECURITY and p.station == station:
			at = maxi(at, line.find(p.at))
	return at


## The cell a walker heads for: free_index() `free`, or the cell behind one an
## admitted passenger still stands on (`admitted`, admitted_at()). A walker
## joins only where the two agree; behind an admitted passenger it waits, still
## walking to the queue, one cell back.
static func walker_free(free: int, admitted: int) -> int:
	return maxi(free, admitted + 1)


## Sends a standing walker `w` toward line[free] (free_index()), unless it
## stands further back on the line and another walker is heading for a cell
## between (`ends`: the path ends of the other walkers to the station), or
## every line cell is still taken by a member: it then waits where it is.
## True when it is on its way, waits, or stands on line[free]; false when
## the queue (`n` members) has no place left or no path leads there.
static func head_for(
	grid: BuildGrid, w: Passenger, line: Array, n: int, free: int, ends: Array
) -> bool:
	if n >= line.size():
		return false
	if free >= line.size():
		return true
	var here := line.find(w.at)
	if here == free:
		return true
	for end: Vector2i in ends:
		var there := line.find(end)
		if here > free and there >= free and there < here:
			return true
	var path := approach(grid, line, w.at, free)
	if path.size() < 2:
		return false
	w.set_path(path)
	return true


## One tick's joins, before anyone steps. `walkers` (in id order) are
## committed to a station of `queues`, whose lane cells are `lanes` and whose
## line is `lines`, by station. A walker standing on a line cell, or reaching
## one at its pace on this tick (it never covers more than one cell a tick),
## joins when that cell is the next free one (free_index()), one reaching it on its way further back
## only when no other walker's path ends there. Those standing go first, then by line
## index, then id, so of two reaching the line on one tick the one nearer the
## front joins first and the next cell is then free for the other. One
## standing on a cell the queue holds or takes steps off it (step_off()). One
## stepping onto the cell it was heading for when the queue holds it, or onto
## one another took on this tick, turns back on its step (turn_back()) and
## heads on from there; one passing over a member's cell walks on. A joiner
## that reaches its cell walks just onto it and stops there: the rest of its
## step is dropped, it is not drawn back. Then a walker whose path ends on a
## cell the queue now holds is sent on toward the free cell (send_on()),
## never to stop on that cell. `by_id` maps ids to passengers. Returns the
## joiners in join order, standing, a moving one with halt_tick `now`.
static func arrive(
	grid: BuildGrid,
	queues: Dictionary,
	lanes: Dictionary,
	lines: Dictionary,
	walkers: Array,
	by_id: Dictionary,
	now: int
) -> Array[Passenger]:
	var arrivals := []
	var ends := {}
	for w: Passenger in walkers:
		if w.is_moving():
			var key := [w.station, w.path_end()]
			ends[key] = ends.get(key, 0) + 1
	for w: Passenger in walkers:
		if not lines.has(w.station) or not queues.has(w.station):
			continue
		var line: Array = lines[w.station]
		if not w.is_moving():
			var here := line.find(w.at)
			if here >= 0:
				arrivals.append([w.station, here, 0, w.id, w, 0])
			continue
		var next := w.path[w.path_index + 1]
		var need := Passenger.segment_mm(w.at, next) - w.seg_mm
		var there := line.find(next)
		if there >= 0 and need <= w.pace_mm():
			arrivals.append([w.station, there, 1, w.id, w, need])
	arrivals.sort_custom(_before)
	var joined: Array[Passenger] = []
	var lost := {}
	var taken := {}
	var admitted := {}
	for entry: Array in arrivals:
		var queue: Dictionary = queues[entry[0]]
		var free := free_index(queue, lines[entry[0]], by_id)
		if not admitted.has(entry[0]):
			admitted[entry[0]] = admitted_at(by_id, entry[0], lines[entry[0]])
		var target := walker_free(free, admitted[entry[0]])
		var into: Vector2i = lines[entry[0]][entry[1]]
		var contested: bool = (
			entry[1] < free
			and entry[2] == 1
			and (taken.has([entry[0], into]) or (entry[4] as Passenger).path_end() == into)
		)
		if contested:
			# Stepping onto the cell it was heading for, now taken, or one another
			# took on this tick: it loses it and turns back.
			lost[entry[3]] = true
			turn_back(entry[4])
			continue
		if entry[1] < free and entry[2] == 0:
			# Standing on a cell a member holds or takes on this tick: it steps off.
			lost[entry[3]] = true
			step_off(grid, entry[4], lines[entry[0]])
			continue
		if entry[1] != free or target != free:
			continue
		var w: Passenger = entry[4]
		var line: Array = lines[entry[0]]
		var cell: Vector2i = line[entry[1]]
		# One passing over the cell on its way on takes it only when no other
		# walker heads there and it steps onto it facing the front.
		var passing: bool = entry[2] == 1 and w.path_index + 2 < w.path.size()
		if (
			passing
			and (ends.get([entry[0], cell], 0) > 0 or not _faces_front(line, entry[1], w.at))
		):
			continue
		if entry[2] == 1:
			w.walk(entry[5])
			# It stops on the cell it reached; the cells it walked stay, so its
			# last step is kept (SecurityLooks.carry_front() reads it).
			var walked: Array[Vector2i] = []
			walked.assign(w.path.slice(0, w.path_index + 1))
			w.path = walked
			w.halt_tick = now
		join(queue, lanes[entry[0]], w.id)
		joined.append(w)
		taken[[entry[0], cell]] = true
	for w: Passenger in walkers:
		if lost.has(w.id):
			continue
		if w.is_moving() and lines.has(w.station) and queues.has(w.station):
			var line: Array = lines[w.station]
			if not admitted.has(w.station):
				admitted[w.station] = admitted_at(by_id, w.station, line)
			var free := free_index(queues[w.station], line, by_id)
			send_on(grid, w, line, walker_free(free, admitted[w.station]))
	_pass_centres(queues, walkers, lost, by_id)
	return joined


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


## Ordering of arrive()'s entries [station, line index, moving, id, ...]: by
## station, line index, then id. Whether a walker stands or steps onto the
## cell on this tick plays no part.
static func _before(a: Array, b: Array) -> bool:
	for i in [0, 1, 3]:
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


## A walker `w` whose path ends on a cell of its station's `line` that a
## queue member holds or has not left yet (index below `n`, free_index())
## heads for line[n] instead: on from the cell it steps to, or turning back where it is when
## that way is shorter, so it never stops on the held cell. With no free cell
## yet (members still stand on every cell) it stops short of the taken cells,
## turning back mid-step only if it is stepping onto one, and waits. A walker
## heading for a free cell or off the line is left as it is.
static func send_on(grid: BuildGrid, w: Passenger, line: Array, n: int) -> void:
	var end := line.find(w.path_end())
	if end < 0 or end >= n:
		return
	var next := w.path[w.path_index + 1]
	var seg := Passenger.segment_mm(w.at, next)
	if n >= line.size():
		# No cell is free yet: it stops short of the taken cells and waits.
		var into := line.find(next)
		if into < 0 or into >= n:
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
	var ahead := _approach_or_here(grid, line, next, n)
	var back := _approach_or_here(grid, line, w.at, n)
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
