extends SceneTree
## Measurement probe: do passengers clip into each other, and where. It adds no
## game behaviour and fixes nothing. The sim has no passenger-passenger
## avoidance (decision sim-architecture-fixed-tick-data-records-snapshot-saves-
## grid-astar: "without avoidance, passengers overlap outside queues"), so this
## counts how often and in which stages.
##
## Every sim tick, every live passenger's ground position (PassengerSim
## .world_position, x and z only) is compared with every other. A pair closer
## than OVERLAP_M (0.45 m centre to centre, the brief's body width; the store
## holds no character width) is an overlap frame. The same scan runs on the
## drawn position (PassengerViews.draw_position: the sim position plus the
## gate-chair and security-lane offsets), because that is what the player sees.
## Frames are also binned at NEAR_M and WIDE_M so a count does not hang on one
## threshold. Each pair of passengers gets a class from both stages (queue,
## walking, seated, cafe, shop, toilet, security, boarding, landside, desk,
## standing) and a motion (both still, both moving, mixed). Contiguous frames of
## one pair are one episode; the worst episodes are listed with tick, ids,
## stages, distance and grid cell.
##
## Exclusion: two passengers of one landside party (they got out of one car or
## taxi on one tick, decision landside-groups-passengers-arrive-in-groups-that-
## share-a-car) are skipped while both are still SPAWNED (outside, walking in
## from the curb). The skipped frames are counted and printed.
##
## Scenarios per seed: "n" is the natural flow (the starter's booked
## passengers, three flights); "r" adds a rush (RUSH_COUNT extra arrivals every
## RUSH_GAP_TICKS ticks at each flight's issue).
##
## Controls that make a zero count mean something: a pure scan of two points at
## 0.0 and 0.44 m must fire and one at 0.46 m must not; two passengers spawned
## on one tick in the real sim must fire. The minimum observed distance is
## printed with every count.
##
## Measure (headless; positions need no GPU):
##   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/passenger_overlap_probe.gd [-- --seeds=1,2,3,4]
## Plates (windowed, one run project-wide; same code reaches the same ticks):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy --path <repo>/game \
##     -s res://spike/passenger_overlap_probe.gd -- \
##     --plates=seed,scenario,tick,idA,idB,distance/seed,...
## A plate prints INFRAME for both passengers, or PROBE_INVALID. A guard thread
## ends a hang (anti-pattern a-frame-counting-watchdog-cannot-catch-a-stuck-
## main-thread).

const StarterFlight := preload("res://spike/starter_flight.gd")
const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/passenger_overlap"
const OVERLAP_M := 0.45
const NEAR_M := 0.30
const WIDE_M := 0.60
const MOVE_EPS_M := 0.004
const RANDOM_SEEDS := 4
const RUSH_COUNT := 16
const RUSH_GAP_TICKS := 8
const FLIGHTS_TO_RUN := 1
const MAX_TICKS_AFTER_OPEN := 24000
const WORST := 10
const HANG_LIMIT_MS := 120000
const PLATE_MARGIN_PX := 50.0
const PLATE_MIN_HEIGHT_PX := 90.0
const PLATE_DISTANCE_M := 9.0
const PLATE_FRAMES := 12
const CROP_SIZE := Vector2i(1200, 760)
## Stage -> pair-class label.
const LABELS := {
	Passenger.Stage.SPAWNED: "landside",
	Passenger.Stage.TO_CHECKIN: "walking",
	Passenger.Stage.CHECKIN_QUEUE: "queue",
	Passenger.Stage.CHECKIN: "desk",
	Passenger.Stage.TO_SECURITY: "walking",
	Passenger.Stage.SECURITY_QUEUE: "queue",
	Passenger.Stage.SECURITY: "security",
	Passenger.Stage.TO_GATE: "walking",
	Passenger.Stage.SITTING_DOWN: "seated",
	Passenger.Stage.SEATED: "seated",
	Passenger.Stage.STANDING: "standing",
	Passenger.Stage.STANDING_UP: "seated",
	Passenger.Stage.TO_EXIT: "boarding",
	Passenger.Stage.APRON: "boarding",
	Passenger.Stage.CAFE_WALK: "cafe",
	Passenger.Stage.CAFE_QUEUE: "queue",
	Passenger.Stage.CAFE_ORDER: "cafe",
	Passenger.Stage.CAFE_TO_SEAT: "cafe",
	Passenger.Stage.CAFE_SITTING_DOWN: "cafe",
	Passenger.Stage.CAFE_SEATED: "cafe",
	Passenger.Stage.CAFE_STANDING_UP: "cafe",
	Passenger.Stage.TOILET_WALK: "toilet",
	Passenger.Stage.TOILET_ENTER: "toilet",
	Passenger.Stage.TOILET_SITTING_DOWN: "toilet",
	Passenger.Stage.TOILET_USE: "toilet",
	Passenger.Stage.TOILET_STANDING_UP: "toilet",
	Passenger.Stage.TOILET_EXIT: "toilet",
	Passenger.Stage.SHOP_WALK: "shop",
	Passenger.Stage.SHOP_BROWSE: "shop",
}

var _guard := Thread.new()
var _mutex := Mutex.new()
var _beat_ms := 0
var _stage_name := "boot"
var _stop_guard := false
var _failed := false
var _main: Node3D
var _clock: SimClock
var _sim: PassengerSim
var _flights: FlightSim
var _views: PassengerViews
var _cam: Camera3D
var _rig: TycoonCamera
var _party := {}
var _out_dir := ""


## What one position source (sim or drawn) saw over one run.
class Tally:
	extends RefCounted
	var label := ""
	var origin := Vector3.ZERO
	var frames_by_class := {}
	var episodes_by_class := {}
	var frames_by_motion := {}
	var bins := [0, 0, 0]
	var excluded_frames := 0
	var party_episodes := 0
	var min_d := INF
	var min_by_class := {}
	var pax_ticks := 0
	var open_eps := {}
	var closed_eps: Array = []
	var _prev := {}

	## pos: id -> Vector2 (x, z); info: id -> {"label", "stage", "party"}.
	func scan(tick: int, pos: Dictionary, info: Dictionary) -> void:
		pax_ticks += pos.size()
		var moving := {}
		for id in pos:
			moving[id] = _prev.has(id) and (_prev[id] as Vector2).distance_to(pos[id]) > MOVE_EPS_M
		_prev = pos
		var buckets := {}
		for id in pos:
			var key := _bucket(pos[id])
			if not buckets.has(key):
				buckets[key] = []
			(buckets[key] as Array).append(id)
		var hit := {}
		for id in pos:
			var base := _bucket(pos[id])
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					for other: int in buckets.get(base + Vector2i(dx, dz), []):
						if other > id:
							_pair(tick, id, other, pos, info, moving, hit)
		for key in open_eps.keys():
			if not hit.has(key):
				_close(open_eps[key])
				open_eps.erase(key)

	func finish() -> void:
		for key in open_eps.keys():
			_close(open_eps[key])
		open_eps.clear()

	func _close(ep: Dictionary) -> void:
		closed_eps.append(ep)
		episodes_by_class[ep["cls"]] = episodes_by_class.get(ep["cls"], 0) + 1
		if ep["party"]:
			party_episodes += 1

	func _bucket(at: Vector2) -> Vector2i:
		return Vector2i(floori(at.x), floori(at.y))

	func _pair(
		tick: int,
		a: int,
		b: int,
		pos: Dictionary,
		info: Dictionary,
		moving: Dictionary,
		hit: Dictionary
	) -> void:
		var d := (pos[a] as Vector2).distance_to(pos[b])
		var ia: Dictionary = info[a]
		var ib: Dictionary = info[b]
		if (
			ia["stage"] == Passenger.Stage.SPAWNED
			and ib["stage"] == Passenger.Stage.SPAWNED
			and ia["party"] != ""
			and ia["party"] == ib["party"]
		):
			if d < OVERLAP_M:
				excluded_frames += 1
			return
		var labels := [ia["label"], ib["label"]]
		labels.sort()
		var cls := "%s+%s" % labels
		min_d = minf(min_d, d)
		min_by_class[cls] = minf(min_by_class.get(cls, INF), d)
		if d >= WIDE_M:
			return
		bins[2] += 1
		if d < NEAR_M:
			bins[0] += 1
		if d >= OVERLAP_M:
			return
		bins[1] += 1
		var motion := "mixed"
		if moving[a] and moving[b]:
			motion = "both-moving"
		elif not moving[a] and not moving[b]:
			motion = "both-still"
		frames_by_class[cls] = frames_by_class.get(cls, 0) + 1
		frames_by_motion[motion] = frames_by_motion.get(motion, 0) + 1
		var key := a * 1000000 + b
		hit[key] = true
		if not open_eps.has(key):
			open_eps[key] = {
				"a": a,
				"b": b,
				"start": tick,
				"d": INF,
				"frames": 0,
				"party": ia["party"] != "" and ia["party"] == ib["party"]
			}
		var ep: Dictionary = open_eps[key]
		ep["frames"] += 1
		ep["last"] = tick
		if d < ep["d"]:
			var mid: Vector2 = ((pos[a] as Vector2) + (pos[b] as Vector2)) * 0.5
			ep["d"] = d
			ep["tick"] = tick
			ep["cls"] = cls
			ep["motion"] = motion
			ep["stage_a"] = ia["stage"]
			ep["stage_b"] = ib["stage"]
			ep["cell"] = Vector2i(floori(mid.x - origin.x), floori(mid.y - origin.z))


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	_beat("init")
	_guard.start(_watch)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	_beat(_stage_name)
	return false


func _beat(stage: String) -> void:
	_mutex.lock()
	_stage_name = stage
	_beat_ms = Time.get_ticks_msec()
	_mutex.unlock()


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_mutex.lock()
		var stop := _stop_guard
		var idle := Time.get_ticks_msec() - _beat_ms
		var stage := _stage_name
		_mutex.unlock()
		if stop:
			return
		if idle > HANG_LIMIT_MS:
			print("PROBE_INVALID hang stage=%s no heartbeat for %d ms" % [stage, idle])
			OS.crash("passenger overlap probe hung")


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _arg(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return ""


func _run() -> void:
	var plates := _arg("--plates=")
	if plates == "":
		await _measure()
	else:
		await _plates(plates.split("/", false))
	_mutex.lock()
	_stop_guard = true
	_mutex.unlock()
	_guard.wait_to_finish()
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


## A fresh main scene with the starter terminal staffed and the airport open,
## the clock paused (nothing ticks between frames).
func _boot(world_seed: int) -> bool:
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(world_seed)
	root.add_child(_main)
	_clock.set_paused(true)
	_flights = _main.get_node("FlightSim")
	_sim = _main.get_node("PassengerSim")
	_views = _main.get_node("PassengerViews")
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	_party.clear()
	_sim.arrivals.released.connect(_on_released)
	await _frames(5)
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	(_main.get_node("BuildMode") as BuildMode).set_tool(BuildMode.Tool.NONE)
	await _frames(2)
	var staff := _main.get_node("Staff") as StaffSim
	StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(_clock, _flights, staff)
	if doors < 0:
		_invalid("the airport did not open and issue the starter's first flight")
		return false
	return true


func _free_main() -> void:
	_main.queue_free()
	await _frames(3)


func _on_released(_booking: int, pid: int) -> void:
	var p := _sim.get_passenger(pid)
	if p != null and not p.apron.is_empty():
		_party[pid] = "%d:%s" % [_sim.tick, p.apron[0]]


func _step() -> void:
	_clock.set_paused(false)
	_clock.advance(SimClock.STEP)
	_clock.set_paused(true)


func _occurrence(index: int) -> String:
	return FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, index)


func _all_departed() -> bool:
	for i in FLIGHTS_TO_RUN:
		if _flights.state_of(_occurrence(i)) != FlightSim.State.DEPARTED:
			return false
	return _sim.active_count() == 0


## Collects every live passenger's position and info for one source.
func _collect(drawn: bool) -> Array:
	var pos := {}
	var info := {}
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		if p == null or p.is_done():
			continue
		var w := _views.draw_position(p) if drawn else _sim.world_position(p)
		pos[id] = Vector2(w.x, w.z)
		info[id] = {
			"label": LABELS.get(p.stage, "other"), "stage": p.stage, "party": _party.get(id, "")
		}
	return [pos, info]


func _new_tally(name: String) -> Tally:
	var t := Tally.new()
	t.label = name
	t.origin = _sim.grid.origin
	return t


## Steps the scenario. With `tallies` it scans each tick; `stop_tick` >= 0 stops
## there (a plate reaches the measured tick), else it runs until the flights
## have departed or MAX_TICKS_AFTER_OPEN pass. Returns the ticks run.
func _run_scenario(rush: bool, stop_tick: int, tallies: Array) -> int:
	var start := _clock.tick
	var seen := {}
	var queue: Array = []
	while _clock.tick < start + MAX_TICKS_AFTER_OPEN:
		_step()
		if rush:
			_rush(seen, queue)
		for t: Tally in tallies:
			var got := _collect(t.label == "drawn")
			t.scan(_clock.tick, got[0], got[1])
		if _clock.tick % 200 == 0:
			_beat("scenario tick %d" % _clock.tick)
		if stop_tick >= 0 and _clock.tick >= stop_tick:
			break
		if stop_tick < 0 and _all_departed():
			break
	return _clock.tick - start


func _rush(seen: Dictionary, queue: Array) -> void:
	for i in FLIGHTS_TO_RUN:
		var id := _occurrence(i)
		if not seen.has(id) and _flights.flight_ids().has(id):
			seen[id] = true
			for n in RUSH_COUNT:
				queue.append([_clock.tick + n * RUSH_GAP_TICKS, id])
	while not queue.is_empty() and queue[0][0] <= _clock.tick:
		var entry: Array = queue.pop_front()
		if not _flights.is_doors_closed(entry[1]):
			_sim.spawn_now(entry[1])


func _measure() -> void:
	var seeds: Array[int] = []
	var given := _arg("--seeds=")
	if given != "":
		for s in given.split(",", false):
			seeds.append(int(s))
	else:
		for i in RANDOM_SEEDS:
			seeds.append(randi())
	await _control()
	var worst_all: Array = []
	for world_seed in seeds:
		for rush in [false, true]:
			print("PROBE seed=%d scenario=%s" % [world_seed, "r" if rush else "n"])
			if not await _boot(world_seed):
				return
			var sim_tally := _new_tally("sim")
			var drawn_tally := _new_tally("drawn")
			var ticks := _run_scenario(rush, -1, [sim_tally, drawn_tally])
			sim_tally.finish()
			drawn_tally.finish()
			_report(world_seed, rush, ticks, sim_tally)
			_report(world_seed, rush, ticks, drawn_tally)
			if ticks >= MAX_TICKS_AFTER_OPEN:
				_invalid("seed %d: flights not departed by tick limit" % world_seed)
			for ep: Dictionary in sim_tally.closed_eps:
				ep["seed"] = world_seed
				ep["rush"] = rush
				worst_all.append(ep)
			await _free_main()
	worst_all.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["d"] < y["d"])
	print("WORST_ALL (sim positions, all seeds and scenarios; plate spec after =)")
	for ep: Dictionary in worst_all.slice(0, WORST):
		print(_episode_line(ep), " spec=", _spec(ep))


func _spec(ep: Dictionary) -> String:
	return (
		"%d,%s,%d,%d,%d,%.3f"
		% [ep["seed"], "r" if ep["rush"] else "n", ep["tick"], ep["a"], ep["b"], ep["d"]]
	)


func _episode_line(ep: Dictionary) -> String:
	return (
		"  tick=%d ids=%d,%d stages=%s,%s d=%.3f cell=%s class=%s motion=%s frames=%d party=%s seed=%s"
		% [
			ep["tick"],
			ep["a"],
			ep["b"],
			Passenger.Stage.keys()[ep["stage_a"]],
			Passenger.Stage.keys()[ep["stage_b"]],
			ep["d"],
			ep["cell"],
			ep["cls"],
			ep["motion"],
			ep["frames"],
			ep["party"],
			ep.get("seed", "-")
		]
	)


func _report(world_seed: int, rush: bool, ticks: int, t: Tally) -> void:
	var minutes := t.pax_ticks / float(SimClock.TICK_RATE * 60)
	var frames := 0
	for cls in t.frames_by_class:
		frames += t.frames_by_class[cls]
	var per_min := frames / maxf(minutes, 0.0001)
	print(
		(
			"RESULT seed=%d scenario=%s source=%s ticks=%d made=%d missed=%d pax_minutes=%.1f"
			% [
				world_seed,
				"r" if rush else "n",
				t.label,
				ticks,
				_sim.made_count(),
				_sim.missed_count(),
				minutes
			]
		)
	)
	print(
		(
			"  overlap_frames(<%.2f)=%d episodes=%d per_passenger_minute=%.3f"
			% [OVERLAP_M, frames, t.closed_eps.size(), per_min]
		)
	)
	print(
		(
			"  bins <%.2f=%d <%.2f=%d <%.2f=%d min_distance=%.3f excluded_party_frames=%d party_episodes=%d"
			% [
				NEAR_M,
				t.bins[0],
				OVERLAP_M,
				t.bins[1],
				WIDE_M,
				t.bins[2],
				t.min_d,
				t.excluded_frames,
				t.party_episodes
			]
		)
	)
	for cls in t.frames_by_class:
		print(
			(
				"  class %s frames=%d episodes=%d min_d=%.3f"
				% [
					cls,
					t.frames_by_class[cls],
					t.episodes_by_class.get(cls, 0),
					t.min_by_class[cls]
				]
			)
		)
	print("  motion ", t.frames_by_motion)
	if t.label == "sim":
		var eps: Array = t.closed_eps.duplicate()
		eps.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["d"] < y["d"])
		for ep: Dictionary in eps.slice(0, WORST):
			print(_episode_line(ep))


## The controls: a pure scan, then the real sim with two passengers spawned on
## one tick.
func _control() -> void:
	var pure := Tally.new()
	pure.label = "control"
	var info := {}
	for id in [1, 2, 3, 4]:
		info[id] = {"label": "walking", "stage": Passenger.Stage.TO_GATE, "party": ""}
	pure.scan(
		1, {1: Vector2(10, 10), 2: Vector2(10, 10), 3: Vector2(20, 20), 4: Vector2(20.44, 20)}, info
	)
	pure.scan(
		2,
		{1: Vector2(10, 10), 2: Vector2(10.46, 10), 3: Vector2(20, 20), 4: Vector2(20.46, 20)},
		info
	)
	pure.finish()
	print(
		(
			"CONTROL pure frames_under_%.2f=%d (expected 2) min_d_seen=%.3f bins=%s"
			% [OVERLAP_M, pure.bins[1], pure.min_d, pure.bins]
		)
	)
	if pure.bins[1] != 2:
		_invalid("pure control: expected exactly 2 overlap frames")
	if not await _boot(1):
		return
	var a := _sim.spawn_now(StarterFlight.first_flight())
	var b := _sim.spawn_now(StarterFlight.first_flight())
	var real := _new_tally("sim")
	var got := _collect(false)
	real.scan(_clock.tick, got[0], got[1])
	real.finish()
	var d := INF
	if got[0].has(a) and got[0].has(b):
		d = (got[0][a] as Vector2).distance_to(got[0][b])
	print(
		(
			"CONTROL real sim two spawn_now passengers ids=%d,%d d=%.3f frames=%s"
			% [a, b, d, real.frames_by_class]
		)
	)
	if real.bins[1] < 1:
		_invalid("real-sim control: two passengers on one point did not count")
	await _free_main()


func _plates(specs: PackedStringArray) -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	var index := 0
	for spec in specs:
		var f := spec.split(",")
		index += 1
		print("PROBE plate_spec=", spec)
		if not await _boot(int(f[0])):
			return
		_run_scenario(f[1] == "r", int(f[2]), [])
		await _plate(index, int(f[3]), int(f[4]), float(f[5]), int(f[0]))
		await _free_main()


func _plate(index: int, id_a: int, id_b: int, expected: float, world_seed: int) -> void:
	var a := _sim.get_passenger(id_a)
	var b := _sim.get_passenger(id_b)
	if a == null or b == null:
		_invalid(
			"plate %d: passenger %d or %d missing at tick %d" % [index, id_a, id_b, _clock.tick]
		)
		return
	var sim_a := _sim.world_position(a)
	var sim_b := _sim.world_position(b)
	var sim_d := Vector2(sim_a.x, sim_a.z).distance_to(Vector2(sim_b.x, sim_b.z))
	var pa := _views.draw_position(a)
	var pb := _views.draw_position(b)
	print(
		(
			"PLATE_CHECK %d tick=%d ids=%d,%d stages=%s,%s sim_d=%.3f expected=%.3f drawn_d=%.3f"
			% [
				index,
				_clock.tick,
				id_a,
				id_b,
				Passenger.Stage.keys()[a.stage],
				Passenger.Stage.keys()[b.stage],
				sim_d,
				expected,
				Vector2(pa.x, pa.z).distance_to(Vector2(pb.x, pb.z))
			]
		)
	)
	if absf(sim_d - expected) > 0.002:
		_invalid(
			"plate %d: sim distance %.3f differs from the measured %.3f" % [index, sim_d, expected]
		)
		return
	var mid := (pa + pb) * 0.5
	for yaw_deg in [0, 90]:
		_rig.stop_follow()
		_rig.position = Vector3(mid.x, 0.0, mid.z)
		_rig.yaw = deg_to_rad(yaw_deg)
		_rig.distance = PLATE_DISTANCE_M
		await _frames(PLATE_FRAMES)
		if not _inframe(id_a) or not _inframe(id_b):
			_invalid("plate %d yaw %d: a passenger is not in frame" % [index, yaw_deg])
			continue
		var image := root.get_texture().get_image()
		var centre := Vector2i(_cam.unproject_position(mid + Vector3(0, 0.9, 0)))
		var origin := (centre - CROP_SIZE / 2).clamp(Vector2i.ZERO, image.get_size() - CROP_SIZE)
		var crop := image.get_region(Rect2i(origin, CROP_SIZE))
		var path := (
			"%s/plate%d_seed%d_t%d_%s_%s_yaw%d.png"
			% [
				_out_dir,
				index,
				world_seed,
				_clock.tick,
				Passenger.Stage.keys()[a.stage],
				Passenger.Stage.keys()[b.stage],
				yaw_deg
			]
		)
		print("PLATE saved ", path, " err=", crop.save_png(path))


func _inframe(id: int) -> bool:
	var node := _views.node_for(id)
	if node == null:
		_invalid("no view node for passenger %d" % id)
		return false
	var foot := node.global_position
	var head := foot + Vector3(0, 1.7, 0)
	var size := Vector2(root.get_visible_rect().size)
	var f := _cam.unproject_position(foot)
	var h := _cam.unproject_position(head)
	var inside := (
		not _cam.is_position_behind(foot)
		and f.x > PLATE_MARGIN_PX
		and f.x < size.x - PLATE_MARGIN_PX
		and h.y > PLATE_MARGIN_PX
		and f.y < size.y - PLATE_MARGIN_PX
	)
	var tall := f.y - h.y
	print("INFRAME id=%d foot=%s head=%s height_px=%.0f inside=%s" % [id, f, h, tall, inside])
	return inside and tall >= PLATE_MIN_HEIGHT_PX
