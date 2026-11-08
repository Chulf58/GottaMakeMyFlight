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
## STANDS counts the queue stands of rollers (RollerPark.queued()) and those
## whose tip started within SHORT_STOOD ticks of the roller standing up
## (QUEUE_STAND_TICKS into the move): a stand and a tip at once (board
## e7028790; info, for comparing builds).
## Pass (each printed with the values it compared): in the lane column on
## moveup frames no body is within ROLLER_CLEAR_M of the other's roller and no
## two bodies are at BODY_ZERO_M. Control: lane members set off to move up
## (MOVE_UPS > 0), else PROBE_INVALID. THROUGHPUT prints the passengers served
## at the busiest station of the place over WINDOW ticks from its first
## service (info, for comparing builds).
##
## With --strip (windowed): STRIP_FRAMES frames of a full security queue
## whose line runs on behind its lane (TerminalLayout.line_of()), STRIP_EVERY
## ticks apart, from when STRIP_HOLDERS holders stand on their hold cells.
## Before each save every member's feet and head project inside the frame by
## MARGIN_PX and a sight line lands first on each holder's body (PlateSight),
## else the frame is refused; PROBE_INVALID if not every frame is taken.
##
## With --tipplate=ID --with=OTHER (windowed, board d8a66218): a strip of the
## queue stand tip of passenger ID, TIP_SHOTS ticks from the tick its tip is
## marked, framed on ID, its roller and OTHER (the guest ahead, or the desk
## leaver crossing in front). Before each save the three project inside the
## frame by MARGIN_PX and sight lines land first on ID's body, its roller and
## OTHER's body (PlateSight; a control tag no mesh has lands on nothing), else
## the other side and then a high view are tried; PROBE_INVALID unless every
## frame is saved. One contact sheet of the strip is saved too.
##
## With --standplate (windowed, board e7028790): the same strip, TIP_SHOTS
## ticks from the tick a lane walker pulling a roller stops behind a member
## standing still (QueueStandWait.ticks() 0, so its stand starts at once),
## framed on it, its roller and the member behind it within STAND_NEAR_M.
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
const STRIP_FRAMES := 4
const STRIP_EVERY := 15
const STRIP_HOLDERS := 3
## Ticks after a tip is marked that --tipplate frames are taken.
const TIP_SHOTS: Array[int] = [0, 1, 2, 3, 4, 6]
## A queue stand whose tip starts this few ticks after the roller is up is short.
const SHORT_STOOD := 4.0
## --standplate: the member behind is at most this far from the subject.
const STAND_NEAR_M := 2.5

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
var _leaver_traced := 0
## Queue stand tips traced (_tip_trace()), by "id since".
var _tips := {}
var _tipped := 0
## Queue stands seen, by "id since": the ticks into the move its tip started,
## or -1.0 while it has not tipped.
var _stands := {}
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
var _strip_on := false
## The station stripped (0 until one has enough holders), the frames still to
## take and the tick the next is due.
var _strip_station := 0
var _strip_left := 0
var _strip_next := 0
## --tipplate: the walker and the guest framed with it, the tick its tip was
## marked (-1 before), the frames saved.
var _tip_id := 0
var _tip_with := 0
var _tip_mark := -1
var _tip_shots: Array[Image] = []
## --tipplate=corner or front: the first queue stand tip toward its roller of
## a lane member behind another (framed with the one ahead) or of a desk's
## lane front (framed with the desk's last leaver).
var _tip_auto := ""
## --standplate: the strip is of a stop behind a standing member (_stand_pick()).
var _stand_auto := false


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
		elif arg == "--strip":
			_strip_on = true
		elif arg.begins_with("--tipplate="):
			var pick := arg.get_slice("=", 1)
			_tip_auto = pick if pick in ["corner", "front"] else ""
			_tip_id = -1 if _tip_auto != "" else int(pick)
		elif arg == "--standplate":
			_stand_auto = true
			_tip_id = -1
		elif arg.begins_with("--with="):
			_tip_with = int(arg.get_slice("=", 1))
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
		if _strip_on:
			await _strip_step()
		if _tip_id != 0:
			await _tip_step()
		if _plate_on and not _plated and not _shot.is_empty():
			if _clock.tick >= int(_shot[0]) + SHOT_AFTER:
				await _plate(_shot[1], _shot[2])
				_shot = []
	if _plate_on and not _plated:
		print("PROBE_INVALID no move-up plate was taken")
		quit(1)
		return
	if _tip_id != 0 and _tip_shots.size() < TIP_SHOTS.size():
		print(
			(
				"PROBE_INVALID the tip strip has %d of %d frames"
				% [_tip_shots.size(), TIP_SHOTS.size()]
			)
		)
		quit(1)
		return
	if _tip_id != 0:
		_tip_sheet()
	if _strip_on and (_strip_station == 0 or _strip_left > 0):
		print("PROBE_INVALID the strip has %d frames left" % _strip_left)
		quit(1)
		return
	quit(_report())


## --tipplate=corner or front: takes `p` as the subject when its queue stand
## tip was set this tick on a turn toward its roller's side, and it is a lane
## member behind another (corner) or a desk's lane front with a leaver (front).
func _tip_pick(p: Passenger) -> void:
	var node := _views.node_for(p.id)
	if node == null or p.station == 0 or not p.stage in RollerPark.QUEUE_STAGES:
		return
	var bag := _views.carry_on_props().bag_state(p.id, 0)
	if not RollerPark.queued(bag) or not bag.has("queue_tip"):
		return
	var heading := _views.walk_heading(p)
	if heading == Vector2.ZERO:
		return
	var turn := angle_difference(node.rotation.y, atan2(heading.x, heading.y))
	var hand := CarryLead.hand_of(int(bag.get("place", 0)))
	if absf(turn) <= RollerPark.TIP_TURN_RAD or (turn > 0.0) != (hand == 1):
		return
	var lane := _sim.queue_of(p.station)
	var i := lane.find(p.id)
	var other := 0
	if _tip_auto == "corner" and i > 0 and not _held.has(p.id):
		other = lane[i - 1]
	elif _tip_auto == "front" and i == 0:
		other = int(_leaver.get(p.station, 0))
	if other == 0 or _views.node_for(other) == null:
		return
	_tip_id = p.id
	_tip_with = other
	print(
		(
			"TIPPICK t%d %s id %d with %d turn %.2f hand %d"
			% [_clock.tick, _tip_auto, p.id, other, turn, hand]
		)
	)


## --standplate: takes lane walker `p` of `station` as the subject on the tick
## it stops pulling a roller behind a member standing still (no stand wait),
## with the member behind it within STAND_NEAR_M, and marks the strip's start.
func _stand_pick(p: Passenger, station: int) -> void:
	if not _stand_auto or _tip_mark >= 0 or p.is_moving() or not _moving.get(p.id, false):
		return
	if not _pulls_roller(p) or QueueStandWait.ticks(_sim, p) != 0:
		return
	var members := _sim.queue_of(station) + _sim.holding_of(station)
	var i := members.find(p.id)
	if i < 0 or i + 1 >= members.size():
		return
	var body := _views.node_for(p.id)
	var behind := _views.node_for(members[i + 1])
	if body == null or behind == null:
		return
	var gap := body.global_position.distance_to(behind.global_position)
	if gap > STAND_NEAR_M:
		return
	_tip_id = p.id
	_tip_with = members[i + 1]
	_tip_mark = _clock.tick
	print(
		(
			"STANDPICK t%d id %d behind %d, followed by %d at %.2f m"
			% [_clock.tick, p.id, members[i - 1], _tip_with, gap]
		)
	)


## --tipplate: marks the tick the walker's queue stand tip is set, then takes a
## frame on each of TIP_SHOTS ticks after it.
func _tip_step() -> void:
	var node := _views.node_for(_tip_id) if _tip_id > 0 else null
	if node == null:
		return
	if _tip_mark < 0:
		var bag := _views.carry_on_props().bag_state(_tip_id, 0)
		if RollerPark.queued(bag) and bag.has("queue_tip"):
			_tip_mark = _clock.tick
		else:
			return
	var at := _clock.tick - _tip_mark
	if at in TIP_SHOTS and _tip_shots.size() == TIP_SHOTS.find(at):
		var img := await _tip_frame(at)
		if img == null:
			print("PROBE_INVALID tip frame +%d refused from every view" % at)
			quit(1)
			return
		_tip_shots.append(img)


## One --tipplate frame `at` ticks into the tip: the views tried in turn (each
## side of the pair, then high); the first that proves the subjects in frame
## and seen is saved and returned, else null.
func _tip_frame(at: int) -> Image:
	var body := _views.node_for(_tip_id)
	var other := _views.node_for(_tip_with)
	var rollers := QueueSpacing.rollers(_views, _sim, _tip_id)
	if body == null or other == null or rollers.is_empty():
		print("TIPPLATE refused: %d, %d or the roller not drawn" % [_tip_id, _tip_with])
		return null
	var roller := rollers[0]
	var bag := _views.carry_on_props().bag_state(_tip_id, 0)
	var k := (float(_clock.tick) - float(bag.get("since", _clock.tick))) / CarryLead.ticks_of(bag)
	var d := QueueSpacing.pair(_views, _sim, _tip_id, _tip_with)
	print(
		(
			"TIPPLATE t%d +%d id %d with %d: tip share %.2f, body %.3f m, roller to body %.3f m"
			% [
				_clock.tick,
				at,
				_tip_id,
				_tip_with,
				RollerPark.tip_share(bag, clampf(k, 0.0, 1.0)),
				d.get("body", INF),
				d.get("roller", INF)
			]
		)
	)
	var mid := (body.global_position + other.global_position) * 0.5 + Vector3.UP * 0.8
	var along := other.global_position - body.global_position
	along.y = 0.0
	var side := Vector3.UP.cross(along.normalized() if along.length() > 0.01 else Vector3.FORWARD)
	if side.dot(roller.global_position - body.global_position) < 0.0:
		side = -side
	# High first: from beside the pair at head height the crowd in front hid the
	# stood roller behind a nearer guest while its handle still passed the sight
	# test.
	var views: Array[Vector3] = [
		side * 2.4 + Vector3.UP * 4.6,
		-side * 2.4 + Vector3.UP * 4.6,
		side * 3.2 + Vector3.UP * 2.2,
		-side * 3.2 + Vector3.UP * 2.2,
	]
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 45.0
		_main.add_child(_cam)
	_cam.current = true
	for v in views.size():
		_cam.look_at_from_position(mid + views[v], mid, Vector3.UP)
		await process_frame
		if await _tip_seen(body, other, roller, v):
			var img := await PlateSight.grab(self)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_REL))
			var file := "/%s_%s_s%d_id%d_t%d.png" % [_kind(), _place, _seed, _tip_id, _clock.tick]
			img.save_png(ProjectSettings.globalize_path(OUT_REL + file))
			print("PLATE saved %s (view %d)" % [ProjectSettings.globalize_path(OUT_REL + file), v])
			return img
	return null


## Whether the walker `body`, its `roller` and `other` project inside the
## frame by MARGIN_PX and the sight lines land first on each (view `v`).
func _tip_seen(body: Node3D, other: Node3D, roller: Node3D, v: int) -> bool:
	var owners: Array[Node] = [_views]
	var holder := PlateSight.colliders(
		root, owners, {body: "walker", roller: "roller", other: "other"}
	)
	var boxes: Dictionary = holder.get_meta("bounds")
	if not boxes.has("roller"):
		holder.queue_free()
		print("TIPPLATE view %d refused: the roller draws no mesh" % v)
		return false
	var bag: Vector3 = (boxes["roller"] as AABB).get_center()
	var points := {
		"walker feet": body.global_position,
		"walker head": body.global_position + Vector3.UP * 1.7,
		"roller": bag,
		"other feet": other.global_position,
		"other head": other.global_position + Vector3.UP * 1.7,
	}
	var frame := Rect2(Vector2.ZERO, _cam.get_viewport().get_visible_rect().size).grow(-MARGIN_PX)
	for name: String in points:
		var at := _cam.unproject_position(points[name])
		print("TIPPLATE view %d %s at %s (frame %s)" % [v, name, at, frame])
		if _cam.is_position_behind(points[name]) or not frame.has_point(at):
			print("TIPPLATE view %d refused: %s out of frame" % [v, name])
			holder.queue_free()
			return false
	await physics_frame
	var space := holder.get_world_3d().direct_space_state
	var eye := _cam.global_position
	var skin := Array(QueueSpacing.surface(roller))
	skin.sort_custom(
		func(a: Vector3, b: Vector3) -> bool: return a.distance_to(eye) < b.distance_to(eye)
	)
	var to_roller: Array[Vector3] = []
	to_roller.assign(skin.slice(0, 5))
	# The bag's middle too: the nearest surface points can all be on the handle.
	to_roller.append(bag)
	var to_walker: Array[Vector3] = []
	var to_other: Array[Vector3] = []
	for up in [0.5, 1.0, 1.4]:
		to_walker.append(body.global_position + Vector3.UP * up)
		to_other.append(other.global_position + Vector3.UP * up)
	var seen := true
	for pair: Array in [[to_walker, "walker"], [to_roller, "roller"], [to_other, "other"]]:
		var lines := PlateSight.sight_lines(space, eye, pair[0], pair[1])
		print(
			(
				"TIPPLATE view %d sight %s: %d of %d on, blockers %s"
				% [v, pair[1], lines["on_subject"].size(), pair[0].size(), lines["blockers"]]
			)
		)
		# Most of each subject's lines land on it first.
		seen = seen and lines["on_subject"].size() * 2 > pair[0].size()
	var control := PlateSight.sight_lines(space, eye, to_walker, NO_TAG)
	print("TIPPLATE view %d control (tag %s) on %d (0)" % [v, NO_TAG, control["on_subject"].size()])
	holder.queue_free()
	if not seen or not control["on_subject"].is_empty():
		print("TIPPLATE view %d refused: a subject is hidden" % v)
		return false
	return true


## The --tipplate strip as one contact sheet, frames left to right.
func _tip_sheet() -> void:
	var w := _tip_shots[0].get_width() / 2
	var h := _tip_shots[0].get_height() / 2
	var sheet := Image.create(w * 3, h * 2, false, Image.FORMAT_RGBA8)
	for i in _tip_shots.size():
		var img := _tip_shots[i].duplicate() as Image
		img.convert(Image.FORMAT_RGBA8)
		img.resize(w, h)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % 3) * w, (i / 3) * h))
	var file := "/%s_%s_s%d_id%d_sheet.png" % [_kind(), _place, _seed, _tip_id]
	sheet.save_png(ProjectSettings.globalize_path(OUT_REL + file))
	print("SHEET saved %s" % ProjectSettings.globalize_path(OUT_REL + file))


## Starts the strip at the first scanner with STRIP_HOLDERS holders all on
## their places, then takes a frame every STRIP_EVERY ticks.
func _strip_step() -> void:
	if _strip_station == 0:
		for station in _sim.layout.scanners:
			if _sim.holding_of(station).size() >= STRIP_HOLDERS and _all_placed(station):
				_strip_station = station
				_strip_left = STRIP_FRAMES
				_strip_next = _clock.tick
				break
	if _strip_left > 0 and _clock.tick >= _strip_next:
		if await _strip_frame():
			_strip_left -= 1
		_strip_next = _clock.tick + STRIP_EVERY


func _all_placed(station: int) -> bool:
	var line := _line(station)
	var members := _sim.queue_of(station) + _sim.holding_of(station)
	for i in members.size():
		var p := _sim.get_passenger(members[i])
		if p.is_moving() or p.at != line[i]:
			return false
	return true


## One strip frame of the stripped station's queue; returns whether it was saved.
func _strip_frame() -> bool:
	var members := _sim.queue_of(_strip_station) + _sim.holding_of(_strip_station)
	var holding := _sim.holding_of(_strip_station)
	var mid := Vector3.ZERO
	var tags := {}
	for id in members:
		var node := _views.node_for(id)
		if node == null:
			print("STRIP refused: %d not drawn" % id)
			return false
		mid += node.global_position
		tags[node] = "m%d" % id
	mid /= members.size()
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 50.0
		_main.add_child(_cam)
	_cam.current = true
	_cam.look_at_from_position(mid + Vector3(6.0, 12.0, 6.0), mid, Vector3.UP)
	await process_frame
	var frame := Rect2(Vector2.ZERO, _cam.get_viewport().get_visible_rect().size).grow(-MARGIN_PX)
	for id in members:
		var feet := _views.node_for(id).global_position
		for point in [feet, feet + Vector3.UP * 1.7]:
			var at := _cam.unproject_position(point)
			if _cam.is_position_behind(point) or not frame.has_point(at):
				print("STRIP refused: %d at %s out of frame %s" % [id, at, frame])
				return false
	var owners: Array[Node] = [_views]
	var holder := PlateSight.colliders(root, owners, tags)
	await physics_frame
	var space := holder.get_world_3d().direct_space_state
	var eye := _cam.global_position
	var seen := 0
	var cells := {}
	for id in holding:
		var chest: Array[Vector3] = [_views.node_for(id).global_position + Vector3.UP * 1.2]
		seen += int(
			not PlateSight.sight_lines(space, eye, chest, "m%d" % id)["on_subject"].is_empty()
		)
		cells[_sim.get_passenger(id).at] = true
	var middle: Array[Vector3] = [mid + Vector3.UP * 1.2]
	var control := PlateSight.sight_lines(space, eye, middle, NO_TAG)
	holder.queue_free()
	print(
		(
			"STRIP t%d station %d members %d holders %d on %d cells, holders seen %d, control %d (0)"
			% [
				_clock.tick,
				_strip_station,
				members.size(),
				holding.size(),
				cells.size(),
				seen,
				control["on_subject"].size()
			]
		)
	)
	if seen < holding.size():
		print("STRIP refused: a holder is hidden")
		return false
	var img := await PlateSight.grab(self)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_REL))
	var file := "/security_holdline_s%d_t%d.png" % [_seed, _clock.tick]
	img.save_png(ProjectSettings.globalize_path(OUT_REL + file))
	print("PLATE saved %s" % ProjectSettings.globalize_path(OUT_REL + file))
	return true


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
		_tip_trace(p)
		_count_stand(p)
		if _tip_auto != "" and _tip_mark < 0:
			_tip_pick(p)
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
			_stand_pick(p, station)
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
			_count_holders(station, holding)
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
func _count_holders(station: int, holding: Array[int]) -> void:
	_holders_max = maxi(_holders_max, holding.size())
	_holder_frames += 1
	var cells := {}
	for id in holding:
		var p := _sim.get_passenger(id)
		if p.is_moving():
			continue
		if cells.has(p.at):
			_holders_shared += 1
			if _traced < TRACES:
				_traced += 1
				_trace_holders(station, cells[p.at], id)
			return
		cells[p.at] = id


## HOLDTRACE: two standing holders `a` and `b` of `station` on one cell, each
## with its stage, cell, place on the line and the index it holds there.
func _trace_holders(station: int, a: int, b: int) -> void:
	var line := _line(station)
	var members := _sim.queue_of(station) + _sim.holding_of(station)
	var text := (
		"HOLDTRACE t%d station %d line %d lane %d"
		% [_clock.tick, station, line.size(), _sim.queue_of(station).size()]
	)
	for id in [a, b]:
		var p := _sim.get_passenger(id)
		var index := members.find(id)
		text += (
			" | %d st%d stuck%d at %s index %d place %s halt %d"
			% [
				id,
				p.stage,
				p.stuck,
				p.at,
				index,
				line[index] if index < line.size() else "none",
				p.halt_tick
			]
		)
	print(text)


## Notes the queue stand of `p`'s roller in _stands, and when its tip starts.
func _count_stand(p: Passenger) -> void:
	if _views.node_for(p.id) == null:
		return
	var bag := _views.carry_on_props().bag_state(p.id, 0)
	if not RollerPark.queued(bag):
		return
	var key := "%d %.1f" % [p.id, float(bag["since"])]
	if float(_stands.get(key, -1.0)) < 0.0:
		_stands[key] = float(bag.get("queue_tip", -1.0))


## TIPTRACE once per queue stand tip (board d8a66218): the walker's stage, its
## drawn yaw and way as it walks off, how far it turns (+ left), the roller's
## hand (0 right) and the ticks the tip waits.
func _tip_trace(p: Passenger) -> void:
	var node := _views.node_for(p.id)
	if node == null or _tipped >= TRACES * 4:
		return
	var bag := _views.carry_on_props().bag_state(p.id, 0)
	if not RollerPark.queued(bag) or not bag.has("queue_tip"):
		return
	var key := "%d %.1f" % [p.id, float(bag["since"])]
	if _tips.has(key):
		return
	_tips[key] = true
	_tipped += 1
	var heading := _views.walk_heading(p)
	var at := float(_clock.tick) - float(bag["since"])
	print(
		(
			"TIPTRACE t%d %d st%d at %s yaw %.2f way %s turn %.2f hand %d waits %.1f"
			% [
				_clock.tick,
				p.id,
				p.stage,
				p.at,
				node.rotation.y,
				heading,
				angle_difference(node.rotation.y, atan2(heading.x, heading.y)),
				CarryLead.hand_of(int(bag.get("place", 0))),
				float(bag["queue_tip"]) - at
			]
		)
	)


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
	var traced := (column == "lane" and moving) or column == "held"
	if traced and _traced < TRACES and d["roller"] < ROLLER_CLEAR_M:
		_traced += 1
		_trace(a, b, d)
	# Leaver frames are traced on a budget of their own (board d8a66218): the
	# held rows spend TRACES early in a run, before the first desk leaver.
	if leaver and _leaver_traced < TRACES and d["roller"] < ROLLER_CLEAR_M:
		_leaver_traced += 1
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
		# Where the body and its roller are drawn (x, z), so a trace says which
		# way the roller lies from its own body (board d8a66218).
		var bag := "none"
		for roller in QueueSpacing.rollers(_views, _sim, pair[0]):
			near = minf(near, QueueSpacing.least(QueueSpacing.surface(roller), other))
			var local := node.global_transform.affine_inverse() * roller.global_position
			bag = (
				"(%.2f, %.2f) local (%.2f, %.2f)"
				% [roller.global_position.x, roller.global_position.z, local.x, local.z]
			)
		line += (
			(
				" | %d st%d at %s moving %s halt %d station %d yaw %.2f drawn (%.2f, %.2f)"
				+ " roller %s its roller to %d %.3f"
			)
			% [
				pair[0],
				p.stage,
				p.at,
				p.is_moving(),
				p.halt_tick,
				p.station,
				node.rotation.y,
				node.global_position.x,
				node.global_position.z,
				bag,
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
	var tipped := 0
	var short := 0
	for tip: float in _stands.values():
		if tip >= 0.0:
			tipped += 1
			short += int(tip < RollerPark.QUEUE_STAND_TICKS + SHORT_STOOD)
	print(
		(
			"STANDS %s queue stands %d, tipped %d, tipped within %.0f ticks of standing up %d"
			% [_place, _stands.size(), tipped, SHORT_STOOD, short]
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


## The strip's file name prefix: "stand" for --standplate, else "tip".
func _kind() -> String:
	return "stand" if _stand_auto else "tip"


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
