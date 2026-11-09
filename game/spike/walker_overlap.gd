extends RefCounted
## The walker-against-queue column of queue_spacing_probe (board 43881776,
## research_finding f2016a2a): how often and how deep the body of a passenger
## still walking to the place (TO_CHECKIN at a desk, TO_SECURITY at a scanner)
## crosses the body of a queued guest (a lane or holding member of a station
## of the place), and which members of one station's queue stand on one spot.
## A pair is measured on the drawn skinned bodies (CarryContact.body_points(),
## every STRIDE-th vertex, nearest vertex to vertex in 3D), so a gap is an upper
## bound on the true surface gap, which is 0 for touching and for overlapping
## bodies alike. A pair is CROSSED on a frame whose surface gap is at most
## CROSS_M. Its DEPTH is a proxy for how far the walker pushed in: the root
## (node origin) distance when the surfaces first met, minus the least root
## distance on a crossed frame. A pair is DEEP when that is at least DEEP_M.
## Crossed pairs are split by whether the guest queues at the walker's own
## station. WALKROUTE counts the walkers that step onto their own line ahead
## of its free cell, which the route rule keeps them off (decision queue-
## walkers-route-around-their-own-line-a-walker-heading-t), split into
## fallbacks (no way round, the stated residual) and the rest.
## Load with preload(); no class_name.

const QueueSpacing := preload("res://spike/queue_spacing.gd")
## Only pairs whose roots are this near are skinned and measured.
const NEAR_M := 1.0
const STRIDE := 4
const CROSS_M := 0.02
const DEEP_M := 0.10
## Two members of one station this near by root share a spot.
const SHARE_M := 0.15
## Rows printed per list.
const LISTED := 8

## Frames on which a walker had a queued guest within NEAR_M (the control), and
## those on which both bodies were skinned.
var near_frames := 0
var skinned_frames := 0
var _sim: PassengerSim
var _views: PassengerViews
## "walker/queued" -> [first tick, last tick, frames crossed, least gap,
## least root, walker stages, queued stages, frames measured, root when the
## surfaces first met, least root on a crossed frame, whether the walker's
## rest path ran over the queued guest's cell at first touch, where both stood].
var _crossed := {}
## "a/b" -> [first tick, last tick, frames, least root, stages, frames both standing].
var _shared := {}
var _near_walkers := {}
var _points := {}
## Walker id -> [tick, fallback, where]: the first step it took onto its own
## line's cells ahead of the line's free cell (_route()).
var _route_over := {}
## The cell map of the first fallback (_cell_map()), printed as WALKMAP lines.
var _map: Array[String] = []


func _init(sim: PassengerSim, views: PassengerViews) -> void:
	_sim = sim
	_views = views


## One frame at `tick`: every walker (stage `walking`) of the place against the
## queue members of `stations`, and the members of each station against each
## other.
func watch(tick: int, stations: Array[int], walking: Passenger.Stage) -> void:
	_points.clear()
	var queued := {}
	for station in stations:
		var members := _sim.queue_of(station) + _sim.holding_of(station)
		for id in members:
			queued[id] = true
		_share(tick, members)
	for id in _sim.passenger_ids():
		var w := _sim.get_passenger(id)
		if w.stage == walking and stations.has(w.station):
			_route(tick, w)
		if w.stage != walking or _views.node_for(id) == null:
			continue
		for other: int in queued:
			_pair(tick, w, _sim.get_passenger(other))


func _pair(tick: int, w: Passenger, q: Passenger) -> void:
	var a := _views.node_for(w.id)
	var b := _views.node_for(q.id)
	if b == null:
		return
	var root := QueueSpacing.flat(a.global_position, b.global_position)
	if root > NEAR_M:
		return
	near_frames += 1
	_near_walkers[w.id] = true
	var gap := _gap(w.id, q.id)
	skinned_frames += int(is_finite(gap))
	var key := "%d/%d" % [w.id, q.id]
	var row: Array = _crossed.get_or_add(
		key, [tick, tick, 0, INF, INF, {}, {}, 0, INF, INF, false, "", w.station == q.station]
	)
	row[7] += 1
	row[3] = minf(row[3], gap)
	row[4] = minf(row[4], root)
	if gap <= CROSS_M:
		row[1] = tick
		row[2] += 1
		row[5][_stage_name(w)] = true
		row[6][_stage_name(q)] = true
		row[9] = minf(row[9], root)
		if row[2] == 1:
			row[0] = tick
			row[8] = root
			row[10] = w.path.slice(w.path_index).has(q.at)
			row[11] = "walker at %s to %s, queued at %s" % [w.at, w.path_end(), q.at]


## Walker `w` stepping onto a cell of its own station's line ahead of the
## line's free cell (past every member's cell), which the route rule keeps it
## off (decision queue-walkers-route-around-their-own-line-a-walker-heading-t):
## a FALLBACK when there was no way round from where it stands to where it
## heads (BuildGrid.find_path_around()), else OTHER. Each walker is counted
## once, on the tick it first does.
func _route(tick: int, w: Passenger) -> void:
	if not w.is_moving() or _route_over.has(w.id):
		return
	var line := _sim.layout.line_of(w.station)
	var free := 0
	for id in _sim.queue_of(w.station) + _sim.holding_of(w.station):
		free = maxi(free, line.find(_sim.get_passenger(id).at) + 1)
	var next := w.path[w.path_index + 1]
	var onto := line.find(next)
	if onto < 0 or onto >= free:
		return
	var shut := line.slice(0, free)
	var fallback := _sim.grid.find_path_around(w.at, w.path_end(), shut).is_empty()
	if fallback and _map.is_empty():
		_map = _cell_map(tick, w, line, free)
	_route_over[w.id] = [
		tick,
		fallback,
		(
			"walker %d at %s onto %s (line %d, free %d) to %s"
			% [w.id, w.at, next, onto, free, w.path_end()]
		)
	]


## The cells around fallback walker `w` and its station's `line`, one string
## a row: W the walker, T where it heads, M a line cell ahead of `free` (the
## members' block), o a later line cell, a-z another station's line cell, .
## a cell passengers may stand on, # one they may not. Walls on cell edges are
## not drawn; the route check (find_path_around()) does count them.
func _cell_map(tick: int, w: Passenger, line: Array, free: int) -> Array[String]:
	var lo := w.at
	var hi := w.at
	for cell: Vector2i in line + [w.path_end()]:
		lo = Vector2i(mini(lo.x, cell.x), mini(lo.y, cell.y))
		hi = Vector2i(maxi(hi.x, cell.x), maxi(hi.y, cell.y))
	var others := {}
	var letter := 0
	for station: int in _sim.layout.desks + _sim.layout.scanners:
		if station == w.station:
			continue
		for cell: Vector2i in _sim.layout.line_of(station):
			others[cell] = char(97 + letter % 26)
		letter += 1
	var rows: Array[String] = [
		(
			"t%d walker %d station %d, x %d..%d, y %d..%d"
			% [tick, w.id, w.station, lo.x - 2, hi.x + 2, lo.y - 2, hi.y + 2]
		)
	]
	for y in range(lo.y - 2, hi.y + 3):
		var row := "%4d " % y
		for x in range(lo.x - 2, hi.x + 3):
			var cell := Vector2i(x, y)
			var at := line.find(cell)
			if cell == w.at:
				row += "W"
			elif cell == w.path_end():
				row += "T"
			elif at >= 0:
				row += "M" if at < free else "o"
			elif others.has(cell):
				row += others[cell]
			elif _sim.grid.in_bounds(cell) and _sim.grid.is_passenger_cell(cell):
				row += "."
			else:
				row += "#"
		rows.append(row)
	return rows


## Members of one station that are drawn on one spot.
func _share(tick: int, members: Array[int]) -> void:
	for i in members.size():
		for j in range(i + 1, members.size()):
			var a := _sim.get_passenger(members[i])
			var b := _sim.get_passenger(members[j])
			var na := _views.node_for(a.id)
			var nb := _views.node_for(b.id)
			if na == null or nb == null:
				continue
			var root := QueueSpacing.flat(na.global_position, nb.global_position)
			if root > SHARE_M:
				continue
			var key := "%d/%d" % [a.id, b.id]
			var row: Array = _shared.get_or_add(key, [tick, tick, 0, INF, {}, 0])
			row[1] = tick
			row[2] += 1
			row[5] += int(not a.is_moving() and not b.is_moving())
			row[3] = minf(row[3], root)
			row[4][_stage_name(a)] = true
			row[4][_stage_name(b)] = true


## The nearest vertex-to-vertex distance between the drawn bodies of `a`, `b`.
func _gap(a: int, b: int) -> float:
	var pa := _body(a)
	var pb := _body(b)
	var best := INF
	for u in pa:
		for v in pb:
			best = minf(best, u.distance_squared_to(v))
	return sqrt(best)


func _body(id: int) -> PackedVector3Array:
	if not _points.has(id):
		_points[id] = skinned_points(_views.node_for(id))
	return _points[id]


## World points of every STRIDE-th vertex of `body`'s visible meshes, skinned on
## the CPU from the skeleton's pose: the headless renderer's own
## bake_mesh_from_current_skeleton_pose() (CarryContact.body_points()) gave none.
static func skinned_points(body: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for mi: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var skeleton := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		var skinned := mi.skin != null and skeleton != null
		var binds: Array[Transform3D] = []
		if skinned:
			for b in mi.skin.get_bind_count():
				var bone := mi.skin.get_bind_bone(b)
				if bone < 0:
					bone = skeleton.find_bone(mi.skin.get_bind_name(b))
				binds.append(
					(
						skeleton.global_transform
						* skeleton.get_bone_global_pose(bone)
						* mi.skin.get_bind_pose(b)
					)
				)
		for surface in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			var per: int = bones.size() / verts.size() if skinned and verts.size() > 0 else 0
			for i in range(0, verts.size(), STRIDE):
				if per == 0:
					out.append(mi.global_transform * verts[i])
					continue
				var at := Vector3.ZERO
				var total := 0.0
				for k in per:
					var w: float = weights[i * per + k]
					if w > 0.0:
						at += w * (binds[bones[i * per + k]] * verts[i])
						total += w
				out.append(at / total if total > 0.0 else mi.global_transform * verts[i])
	return out


## How far pair `key` was pushed in (see the header), 0 when never crossed.
func _depth(key: String) -> float:
	var row: Array = _crossed[key]
	return maxf(0.0, row[8] - row[9]) if row[2] > 0 else 0.0


func _stage_name(p: Passenger) -> String:
	return Passenger.Stage.keys()[p.stage]


## Prints the WALKCROSS and SHARESPOT lines for `place`; false when the control
## failed (no walker was ever near a queued guest, or no body was skinned).
func report(place: String) -> bool:
	var near := _crossed.keys()
	near.sort_custom(func(a: String, b: String) -> bool: return _depth(a) > _depth(b))
	var rows := near.filter(func(k: String) -> bool: return _crossed[k][2] > 0)
	var over := rows.filter(func(k: String) -> bool: return _crossed[k][10])
	var deep := near.filter(func(k: String) -> bool: return _depth(k) >= DEEP_M)
	var frames := 0
	var first := 1 << 30
	var last := -1
	for key: String in rows:
		var row: Array = _crossed[key]
		frames += row[2]
		first = mini(first, row[0])
		last = maxi(last, row[1])
	print(
		(
			(
				"WALKCROSS %s pairs crossed (gap <= %.3f m) %d, deep (depth >= %.2f m) %d, of %d "
				+ "walker-queue pairs near, walker's path over the guest's cell at first touch in %d of the "
				+ "crossed; frames crossed %d, ticks %s to %s"
			)
			% [
				place,
				CROSS_M,
				rows.size(),
				DEEP_M,
				deep.size(),
				_crossed.size(),
				over.size(),
				frames,
				first if last >= 0 else "-",
				last if last >= 0 else "-"
			]
		)
	)
	var own := rows.filter(func(k: String) -> bool: return _crossed[k][12])
	var own_deep := own.filter(func(k: String) -> bool: return _depth(k) >= DEEP_M)
	print(
		(
			"WALKCROSS %s crossed pairs by the guest's station: own %d (deep %d), other %d (deep %d)"
			% [
				place,
				own.size(),
				own_deep.size(),
				rows.size() - own.size(),
				deep.size() - own_deep.size()
			]
		)
	)
	var fallbacks := _route_over.keys().filter(func(id: int) -> bool: return _route_over[id][1])
	print(
		(
			(
				"WALKROUTE %s walkers stepping onto their own line ahead of its free cell %d: "
				+ "with no way round (fallback, the stated residual) %d, with a way round %d"
			)
			% [place, _route_over.size(), fallbacks.size(), _route_over.size() - fallbacks.size()]
		)
	)
	var listed := _route_over.keys()
	listed.sort()
	for id: int in listed.slice(0, LISTED):
		var row: Array = _route_over[id]
		print("WALKROUTE %s t%d fallback %s, %s" % [place, row[0], row[1], row[2]])
	for line: String in _map:
		print("WALKMAP %s %s" % [place, line])
	for key: String in near.slice(0, LISTED):
		var row: Array = _crossed[key]
		print(
			(
				(
					"WALKCROSS %s deepest pair %s: t%d-t%d, crossed %d of %d frames, least surface gap %.3f m, "
					+ "root %.3f m at first touch, %.3f m least, depth %.3f m, walker %s, queued %s; "
					+ "over cell %s, %s"
				)
				% [
					place,
					key,
					row[0],
					row[1],
					row[2],
					row[7],
					row[3],
					row[8],
					row[9],
					_depth(key),
					",".join(row[5].keys()),
					",".join(row[6].keys()),
					row[10],
					row[11]
				]
			)
		)
	var spots := _shared.keys()
	spots.sort_custom(func(a: String, b: String) -> bool: return _shared[a][3] < _shared[b][3])
	var spot_frames := 0
	var still_frames := 0
	for key: String in spots:
		spot_frames += _shared[key][2]
		still_frames += _shared[key][5]
	print(
		(
			(
				"SHARESPOT %s lane/holding pairs within %.2f m of each other: pairs %d, frames %d, "
				+ "of those both standing %d"
			)
			% [place, SHARE_M, spots.size(), spot_frames, still_frames]
		)
	)
	for key: String in spots.slice(0, LISTED):
		var row: Array = _shared[key]
		print(
			(
				"SHARESPOT %s pair %s: t%d-t%d, %d frames (%d both standing), least root %.3f m, %s"
				% [place, key, row[0], row[1], row[2], row[5], row[3], ",".join(row[4].keys())]
			)
		)
	print(
		(
			(
				"WALKCONTROL %s walker frames with a queued guest within %.1f m %d (> 0), "
				+ "distinct walkers %d (> 0), skinned pair frames %d (> 0)"
			)
			% [place, NEAR_M, near_frames, _near_walkers.size(), skinned_frames]
		)
	)
	return near_frames > 0 and not _near_walkers.is_empty() and skinned_frames > 0
