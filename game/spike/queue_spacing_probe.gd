extends SceneTree
## Headless probe of the spacing in desk and security lanes as they move up
## (board 34b0c378, QueueRipple). It boots main.tscn, builds CafeTestLayout
## with a gate desk, opens the airport, sends GUESTS calm passengers with a
## roller each and EXTRA more of the first flight to check in (SECURITY_EXTRA
## at security, unless --extra is given), and plays
## TICKS ticks, one a frame. Each frame, for every lane of the place (desks
## for --place=checkin, scanners for --place=security), it measures each pair
## of lane neighbours and, at a desk, the passenger who just checked in
## against the new front: body to body and each body to the other's roller
## (QueueSpacing.pair(); node transforms only, so headless is valid for these
## distances, unlike body points inside a bag).
## TRACE lines name each member's facing (yaw) and how near its own roller is
## to the other body, so a failing pair says whose roller it is.
## Columns: "lane" pairs count against the ripple; "held" pairs have a member
## that was in a holding list or joined the lane on a cell another queue member
## stood on (board c5b6664f) and are reported apart; pairs of holders and the
## lane's last member against the first holder are measured into it too.
## Rows: "moveup" frames (either member walking) and "still" frames.
## HOLDERS prints the most holders seen at one station and the frames on
## which standing holders shared a cell (holders N on N distinct cells).
## Pass (each printed with the values it compared): in the lane column on
## moveup frames no body is within ROLLER_CLEAR_M of the other's roller and no
## two bodies are at BODY_ZERO_M. Control: lane members set off to move up
## (MOVE_UPS > 0), else PROBE_INVALID. THROUGHPUT prints the passengers served
## at the busiest station of the place over WINDOW ticks from its first
## service (info, for comparing builds).
##
## Run: Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##   --path game -s res://spike/queue_spacing_probe.gd -- --place=checkin \
##   [--seed=N] [--ticks=N] [--extra=N]

const StarterFlight := preload("res://spike/starter_flight.gd")
const QueueSpacing := preload("res://spike/queue_spacing.gd")
const PlateSight := preload("res://spike/plate_sight.gd")
const NO_TAG := "nothing_has_this_tag"
const GUESTS := 4
const EXTRA := 16
## With EXTRA, security seeds 2 and 4 measured no in-order lane pair moving up
## (every move-up pair was out of order: PROBE_INVALID); with 40 all of seeds
## 1 to 4 build lanes of 369 to 924 in-order move-up frames (board de64b195).
const SECURITY_EXTRA := 40
const ROLLER_CLEAR_M := 0.30
const BODY_ZERO_M := 0.001
const WINDOW := 1000
## How far a desk leaver is followed against the new front.
const LEAVER_M := 3.0
## Ticks into a move-up its plate is taken, and the move-ups tried at most.
const SHOT_AFTER := 5
const PLATE_TRIES := 12
const MARGIN_PX := 12.0
const OUT_REL := "res://../tools/blender/out/queue-spacing"
## TRACE lines printed on failing lane pairs.
const TRACES := 12

var _seed := 0
var _place := "checkin"
var _ticks := 2500
var _extra := -1
var _main: Node3D
var _clock: SimClock
var _sim: PassengerSim
var _views: PassengerViews
## Ids that were ever in a holding list or joined the lane stacked.
var _held := {}
## Ids that joined a lane out of the order of its cells (_joined()).
var _order := {}
var _in_lane := {}
var _moving := {}
var _move_ups := 0
## The most holders at one station on one frame, and the frames on which two
## standing holders of one station shared a cell.
var _holders_max := 0
var _holders_shared := 0
var _holder_frames := 0
var _traced := 0
## Station -> the passenger who last left it.
var _leaver := {}
var _stage := {}
var _station_of := {}
## Station -> [served ticks].
var _served := {}
## "column row" -> [frames, min body, at zero, min roller, below clear].
var _rows := {}
var _plate_on := false
var _plated := false
var _plate_tries := 0
## [set-off tick, follower id, id ahead] of the move-up to plate, or [].
var _shot: Array = []
var _cam: Camera3D


func _initialize() -> void:
	_seed = randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--place="):
			_place = arg.get_slice("=", 1)
		elif arg.begins_with("--ticks="):
			_ticks = int(arg.get_slice("=", 1))
		elif arg.begins_with("--extra="):
			_extra = int(arg.get_slice("=", 1))
		elif arg == "--plate":
			_plate_on = true
	if _extra < 0:
		_extra = SECURITY_EXTRA if _place == "security" else EXTRA
	print("PROBE sim_seed=%d place=%s ticks=%d extra=%d" % [_seed, _place, _ticks, _extra])
	_run.call_deferred()


func _run() -> void:
	if not await _boot():
		quit(1)
		return
	_send()
	for t in _ticks:
		_clock.advance(SimClock.STEP)
		await process_frame
		_watch()
		if _plate_on and not _plated and not _shot.is_empty():
			if _clock.tick >= int(_shot[0]) + SHOT_AFTER:
				await _plate(_shot[1], _shot[2])
				_shot = []
	if _plate_on and not _plated:
		print("PROBE_INVALID no move-up plate was taken")
		quit(1)
		return
	quit(_report())


func _boot() -> bool:
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	_clock = _main.get_node("SimClock") as SimClock
	_clock.seed_rng(_seed)
	(_main.get_node("BuildMode") as BuildMode).starter_shell = false
	root.add_child(_main)
	_clock.set_process(false)
	_clock.set_paused(false)
	for i in 3:
		await process_frame
	var mode := _main.get_node("BuildMode") as BuildMode
	mode.set_process(false)
	_sim = _main.get_node("PassengerSim") as PassengerSim
	_views = _main.get_node("PassengerViews") as PassengerViews
	CafeTestLayout.build(mode.grid)
	if not StarterFlight.add_gate_desk(mode.grid):
		print("PROBE_INVALID the gate desk was refused")
		return false
	(mode.get_node("BuildView") as BuildView).refresh(mode.grid)
	for i in 4:
		await process_frame
	_sim.cafes.refresh()
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(
		_clock, _main.get_node("FlightSim") as FlightSim, staff
	)
	print("PROBE hired=%d opened tick=%d" % [hired, _clock.tick])
	if hired == 0 or doors < 0:
		print("PROBE_INVALID the airport did not open")
		return false
	return true


## GUESTS calm passengers with a roller and EXTRA more as they come, all
## walking in to check in.
func _send() -> void:
	var rollers := 0
	for attempt in 400:
		if rollers >= GUESTS and attempt >= GUESTS + _extra:
			break
		var p := _sim.get_passenger(_sim.spawn_now(StarterFlight.first_flight(), attempt % 2))
		var roller := _pulls_roller(p)
		if rollers < GUESTS and not roller:
			p.carry_on = 0
			continue
		rollers += 1 if roller else 0
		ToiletTestLayout.calm(p)
		p.liquids = false
		p.alarm = false
		p.shop_cooldown = 1000000
		p.cafe_cooldown = 1000000
		p.boredom = 0
		if _place == "security":
			# Checked in already (SecurityTestWorld.send()), so security queues build.
			p.stage = Passenger.Stage.TO_SECURITY
			p.clear_path()
	print("PROBE sent rollers=%d tick=%d" % [rollers, _clock.tick])


func _watch() -> void:
	var stations: Array[int] = _sim.layout.desks if _place == "checkin" else _sim.layout.scanners
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		var was: int = _stage.get(id, p.stage)
		if was == Passenger.Stage.CHECKIN and p.stage == Passenger.Stage.TO_SECURITY:
			_leaver[_station_of[id]] = id
			_serve(_station_of[id])
		if was == Passenger.Stage.SECURITY and p.stage == Passenger.Stage.TO_GATE:
			_serve(_station_of[id])
		_stage[id] = p.stage
		_station_of[id] = p.station
	for station in stations:
		var lane := _sim.queue_of(station)
		for id in _sim.holding_of(station):
			_held[id] = true
		for id in lane:
			var p := _sim.get_passenger(id)
			if not _in_lane.has(id):
				_in_lane[id] = true
				_joined(station, p, lane)
			if p.is_moving() and not _moving.get(id, false):
				_move_ups += 1
				_candidate(lane, id)
			_moving[id] = p.is_moving()
			if not p.is_moving() and p.at == _line(station)[lane.find(id)]:
				# Alone on its own place once: from here it moves up as any lane walker.
				var shared := (lane + _sim.holding_of(station)).any(
					func(o: int) -> bool: return o != id and _sim.get_passenger(o).at == p.at
				)
				if not shared:
					_held.erase(id)
					_order.erase(id)
		for i in range(lane.size() - 1):
			_measure(lane[i], lane[i + 1])
		var holding := _sim.holding_of(station)
		if not holding.is_empty():
			_count_holders(holding)
			if not lane.is_empty():
				_measure(lane[lane.size() - 1], holding[0])
			for i in range(holding.size() - 1):
				_measure(holding[i], holding[i + 1])
		var left: int = _leaver.get(station, 0)
		if left != 0 and not lane.is_empty() and lane[0] != left and _views.node_for(left) != null:
			var d := QueueSpacing.pair(_views, _sim, left, lane[0])
			if d.is_empty() or d["body"] > LEAVER_M:
				_leaver.erase(station)
			else:
				_measure(left, lane[0], true)


## Marks a newcomer `p` to `lane` that joined on a queue member's cell
## (held, c5b6664f), or on a lane cell nearer the front than one an earlier
## member stands on: it then walks through that member to its place, the lane
## order not being the order on the cells ("order").
func _joined(station: int, p: Passenger, lane: Array[int]) -> void:
	var cells: Array = _line(station)
	for other in lane + _sim.holding_of(station):
		if other != p.id and _sim.get_passenger(other).at == p.at:
			_held[p.id] = true
	var mine := cells.find(p.at)
	for other in lane.slice(0, lane.find(p.id)):
		var theirs := cells.find(_sim.get_passenger(other).at)
		if mine >= 0 and theirs > mine:
			_order[p.id] = true
			_order[other] = true


## The places of `station`'s queue members in order: its lane cells, then its
## hold cells where the layout derives them (TerminalLayout.line_of()).
func _line(station: int) -> Array:
	if _sim.layout.has_method("line_of"):
		return _sim.layout.call("line_of", station)
	return _sim.layout.lanes[station]


## Counts the holders of one station on this frame and whether two of them
## standing still share a cell.
func _count_holders(holding: Array[int]) -> void:
	_holders_max = maxi(_holders_max, holding.size())
	_holder_frames += 1
	var cells := {}
	for id in holding:
		var p := _sim.get_passenger(id)
		if p.is_moving():
			continue
		if cells.has(p.at):
			_holders_shared += 1
			return
		cells[p.at] = true


func _serve(station: int) -> void:
	(_served.get_or_add(station, []) as Array).append(_clock.tick)


## Measures pair `a`, `b` into its column and row. A desk leaver `a` against
## the front `b` (`leaver`) goes in the "leaver" column: its row is "moveup"
## while the front steps up to the desk, "wait" while the front stands and
## the leaver walks off.
func _measure(a: int, b: int, leaver := false) -> void:
	var d := QueueSpacing.pair(_views, _sim, a, b)
	if d.is_empty():
		return
	var moving := _sim.get_passenger(a).is_moving() or _sim.get_passenger(b).is_moving()
	var column := "lane"
	if leaver:
		moving = _sim.get_passenger(b).is_moving()
		column = "leaver"
	elif _held.has(a) or _held.has(b):
		column = "held"
	elif _order.has(a) or _order.has(b):
		column = "order"
	var key := "%s %s" % [column, "moveup" if moving else "still"]
	if column == "lane" and moving and _traced < TRACES and d["roller"] < ROLLER_CLEAR_M:
		_traced += 1
		_trace(a, b, d)
	var row: Array = _rows.get_or_add(key, [0, INF, 0, INF, 0, ""])
	row[0] += 1
	if d["body"] < row[1]:
		row[1] = d["body"]
	if d["body"] < BODY_ZERO_M:
		row[2] += 1
	if d["roller"] < row[3]:
		row[3] = d["roller"]
		row[5] = "t%d ids %d/%d" % [_clock.tick, a, b]
	if d["roller"] < ROLLER_CLEAR_M:
		row[4] += 1


## One line on a failing lane pair: each member's stage, cell, walk and halt
## tick, and the lane.
func _trace(a: int, b: int, d: Dictionary) -> void:
	var line := "TRACE t%d body %.3f roller %.3f" % [_clock.tick, d["body"], d["roller"]]
	for pair in [[a, b], [b, a]]:
		var p := _sim.get_passenger(pair[0])
		var node := _views.node_for(pair[0])
		var other := _views.node_for(pair[1]).global_position
		var near := INF
		for roller in QueueSpacing.rollers(_views, _sim, pair[0]):
			near = minf(near, QueueSpacing.least(QueueSpacing.surface(roller), other))
		line += (
			" | %d st%d at %s moving %s halt %d station %d yaw %.2f its roller to %d %.3f"
			% [
				pair[0],
				p.stage,
				p.at,
				p.is_moving(),
				p.halt_tick,
				p.station,
				node.rotation.y,
				pair[1],
				near
			]
		)
		if p.station != 0:
			line += " lane %s" % [_sim.queue_of(p.station)]
	print(line)


func _report() -> int:
	var failed := false
	for key in [
		"lane moveup",
		"lane still",
		"leaver moveup",
		"leaver still",
		"order moveup",
		"order still",
		"held moveup",
		"held still",
	]:
		var row: Array = _rows.get(key, [0, INF, 0, INF, 0, ""])
		print(
			(
				(
					"SPACING %s %s: frames %d, least body to body %.3f m (at %.3f m: %d), "
					+ "least body to roller %.3f m (%s; under %.2f m: %d)"
				)
				% [
					_place,
					key,
					row[0],
					row[1],
					BODY_ZERO_M,
					row[2],
					row[3],
					row[5],
					ROLLER_CLEAR_M,
					row[4]
				]
			)
		)
		if key in ["lane moveup", "leaver moveup"] and (row[2] > 0 or row[4] > 0):
			failed = true
	print(
		(
			(
				"HOLDERS most at one station %d; frames with holders %d, "
				+ "with two standing holders on one cell %d"
			)
			% [_holders_max, _holder_frames, _holders_shared]
		)
	)
	var lane_frames: int = (_rows.get("lane moveup", [0]) as Array)[0]
	print(
		"CONTROL move-ups %d (> 0), lane pair frames moving up %d (> 0)" % [_move_ups, lane_frames]
	)
	if _move_ups == 0 or lane_frames == 0:
		print("PROBE_INVALID no lane neighbours were measured moving up")
		return 1
	var best := 0
	var best_station := 0
	for station: int in _served:
		var ticks: Array = _served[station]
		var count := ticks.filter(func(t: int) -> bool: return t < int(ticks[0]) + WINDOW).size()
		if count > best:
			best = count
			best_station = station
	print(
		(
			"THROUGHPUT %s station %d served %d in %d ticks from its first"
			% [_place, best_station, best, WINDOW]
		)
	)
	print("PROBE done failed=%s" % failed)
	return 1 if failed else 0


## Whether `p` has a roller among its bags (SecurityLooks.bag_kind()).
static func _pulls_roller(p: Passenger) -> bool:
	for i in p.carry_on:
		if SecurityLooks.bag_kind(p, i) == SecurityLooks.Kind.ROLLER:
			return true
	return false


## A lane move-up worth a plate: `id` sets off behind a walker pulling a
## roller in a lane of the place, neither held nor out of order.
func _candidate(lane: Array[int], id: int) -> void:
	var i := lane.find(id)
	if not _plate_on or _plated or not _shot.is_empty() or i <= 0:
		return
	var ahead := lane[i - 1]
	if _held.has(id) or _held.has(ahead) or _order.has(id) or _order.has(ahead):
		return
	if _pulls_roller(_sim.get_passenger(ahead)) and _plate_tries < PLATE_TRIES:
		_plate_tries += 1
		_shot = [_clock.tick, id, ahead]


## A plate of a lane move-up at the place: `id` walking up behind `ahead`, whose roller
## stands beside it. Before the save the follower's feet and head, the roller
## and the head ahead project inside the frame by MARGIN_PX, and sight lines
## from the camera land first on the follower's body and on the roller
## (PlateSight; a control with a tag no mesh has lands on nothing), else it is
## refused; PROBE_INVALID if none of PLATE_TRIES move-ups gives one.
func _plate(id: int, ahead: int) -> void:
	var body := _views.node_for(id)
	var front := _views.node_for(ahead)
	var rollers := QueueSpacing.rollers(_views, _sim, ahead)
	if body == null or front == null or rollers.is_empty():
		print("PLATE refused: not drawn")
		return
	var roller := rollers[0]
	var mid := (body.global_position + roller.global_position) * 0.5 + Vector3.UP * 0.7
	var along := front.global_position - body.global_position
	along.y = 0.0
	var side := Vector3.UP.cross(along.normalized())
	if side.dot(roller.global_position - front.global_position) < 0.0:
		side = -side
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 45.0
		_main.add_child(_cam)
	_cam.current = true
	_cam.look_at_from_position(mid + side * 3.6 + Vector3.UP * 1.8, mid, Vector3.UP)
	await process_frame
	var owners: Array[Node] = [_views]
	var holder := PlateSight.colliders(root, owners, {body: "follower", roller: "roller"})
	var boxes: Dictionary = holder.get_meta("bounds")
	if not boxes.has("roller"):
		holder.queue_free()
		print("PLATE refused: the roller ahead draws no mesh")
		return
	# The middle of the bag's meshes: the roller's origin is up at its handle.
	var bag: Vector3 = (boxes["roller"] as AABB).get_center()
	var points := {
		"feet": body.global_position,
		"head": body.global_position + Vector3.UP * 1.7,
		"roller": bag,
		"ahead_head": front.global_position + Vector3.UP * 1.7,
	}
	var frame := Rect2(Vector2.ZERO, _cam.get_viewport().get_visible_rect().size).grow(-MARGIN_PX)
	for name: String in points:
		var at := _cam.unproject_position(points[name])
		print("PLATE %s at %s (frame %s)" % [name, at, frame])
		if _cam.is_position_behind(points[name]) or not frame.has_point(at):
			print("PLATE refused: %s out of frame" % name)
			holder.queue_free()
			return
	await physics_frame
	var space := holder.get_world_3d().direct_space_state
	var eye := _cam.global_position
	var to_body: Array[Vector3] = [
		body.global_position + Vector3.UP * 1.0, body.global_position + Vector3.UP * 1.4
	]
	# Its surface points nearest the camera: the bounds' middle can fall in a gap
	# between the stood bag and its handle.
	var skin := Array(QueueSpacing.surface(roller))
	skin.sort_custom(
		func(a: Vector3, b: Vector3) -> bool: return a.distance_to(eye) < b.distance_to(eye)
	)
	var to_roller: Array[Vector3] = []
	to_roller.assign(skin.slice(0, 5))
	var on_body := PlateSight.sight_lines(space, eye, to_body, "follower")
	var on_roller := PlateSight.sight_lines(space, eye, to_roller, "roller")
	var control := PlateSight.sight_lines(space, eye, to_body, NO_TAG)
	holder.queue_free()
	print(
		(
			(
				"PLATE sight: follower %d of %d on, blockers %s; roller %d of %d on, blockers %s; "
				+ "control (tag %s) on %d (0)"
			)
			% [
				on_body["on_subject"].size(),
				to_body.size(),
				on_body["blockers"],
				on_roller["on_subject"].size(),
				to_roller.size(),
				on_roller["blockers"],
				NO_TAG,
				control["on_subject"].size()
			]
		)
	)
	if on_body["on_subject"].is_empty() or not on_body["blockers"].is_empty():
		print("PLATE refused: the follower is hidden")
		return
	if on_roller["on_subject"].is_empty() or not on_roller["blockers"].is_empty():
		print("PLATE refused: the roller ahead is hidden")
		return
	var img := await PlateSight.grab(self)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_REL))
	var file := "/%s_moveup_s%d_t%d.png" % [_place, _seed, _clock.tick]
	var path := ProjectSettings.globalize_path(OUT_REL + file)
	img.save_png(path)
	print("PLATE saved %s tick %d follower %d ahead %d" % [path, _clock.tick, id, ahead])
	_plated = true
