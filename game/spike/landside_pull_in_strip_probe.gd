extends SceneTree
## Windowed strip of a car pulling into a curb berth in the real main.tscn: the berth's
## path (LandsidePaths) carries it from road_in into the berth, and LandsideViews draws
## it along that path, facing the way it drives.
##
## Run (one windowed Godot run project-wide; this probe holds the slot while it runs):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/landside_pull_in_strip_probe.gd
##
## main.tscn boots with a random sim seed (printed), the starter terminal (the HUD's
## debug button) and a check-in agent and a security officer hired, and plays until a
## car on road_in takes a berth. The camera aims at the middle of its way in; seven
## frames are taken evenly over the way in (a fraction of a tick apart) and the eighth
## once the car stands in the berth (a tick after its arrival tick), the sim stepped
## by the clock's own advance(), so LandsideViews draws
## through its real tick signal and alpha. Every frame proves the car in frame (its
## projected bounds inside the viewport with a margin), frame 0 also hit by camera
## rays against colliders of every mesh in the scene, else PROBE_INVALID. Per frame it
## prints the car's position, nose and step: each step must be more than 0 and no
## longer than a lane step a tick allows over the frame gap, plus slack, the nose along
## the step (dot over 0.9), and the last frame in the berth (within 5 cm). The strip
## (four frames a row, two rows) goes to tools/blender/out/landside/pull_in/.
##
## Then the multi-storey (lot spot 1) is built and the probe waits for a car to turn in
## for a ground-floor slot (board e3aa4367): eight frames from the gate, through the
## gap cut in the ramp kerb, to the stall, from a camera on the ground floor. Every
## frame proves the car in frame and hit by camera rays, prints its height, and checks
## its nose against its heading over a twentieth of a tick; the last frame has the car
## within 5 cm of its slot. Two stills follow: the kerb gap close up (the toon ramp
## over the floor wedge), and parked cars on the first deck inside its painted stalls
## (cars moved there as a fixture, as the views plates probe does).

const OUT_REL := "res://../tools/blender/out/landside/pull_in"
const MAIN_SCENE := "res://main/main.tscn"
const CAMERA_RIG := "TycoonCamera"
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 120000
const TICK_LIMIT := 60000
const FRAMES := 8
const GLASS := "res://assets/materials/tp_glass.tres"
const MULTI := 1
## How far the nose check looks ahead, in ticks.
const NOSE_TICKS := 0.05
## On the ground floor near the aisle, under the first deck, looking at the gate
## through the entrance opening (x 2.05 to 7.95), over the kerb gap and the stall.
const GROUND_EYE := Vector3(-1.0, 2.8, -8.0)
const GROUND_TARGET := Vector3(-1.0, 0.6, -28.0)
## The kerb gap (x 1.0 to 1.7, z -29.9 to -25.9), seen from the stalls.
const GAP_EYE := Vector3(-3.0, 1.9, -23.0)
const GAP_MID := Vector3(1.35, 0.34, -27.9)
## First-deck stalls the fixture fills (index from the deck's first slot), and the
## still from the first deck's aisle.
const DECK_STALLS: Array[int] = [3, 4, 5]
const DECK_WAIT_TICKS := 20000
const DECK_EYE := Vector3(-0.5, 8.6, 0.0)
const DECK_TARGET := Vector3(-6.6, 5.6, -12.0)
## Low and side-on across the apron, so the access ramp's rise reads against the
## slab's front edge (z -34) with the car on the lane (x 3.5).
const RAMP_EYE := Vector3(-3.0, 1.6, -43.0)
const RAMP_TARGET := Vector3(3.5, 0.2, -36.0)
## From the apron west of the access lane, looking in through the entrance opening
## along the walk's last stretch (x 3.5, z -28 to the gate at -34): 6 to 11 m away.
const WALK_EYE := Vector3(0.0, 2.2, -38.5)
const WALK_TARGET := Vector3(3.5, 1.0, -31.0)
## The ramp and walk strips' tiles: this much of each frame around the subject, not
## scaled down, so the car's wheels and the walker are large enough to judge.
const STRIP_TILE := Vector2i(960, 540)
## The opening in the ground floor's front wall (x), and the wall's middle line
## in the asset's own frame (the clearance test's FRONT_WALL_Z).
const OPENING_X := Vector2(2.05, 7.95)
const FRONT_WALL_LOCAL_Z := -22.55
const WALKER_HEIGHT := 1.7
const WALKER_RADIUS := 0.25

var _out_dir := ""
var _failed := false
var _stage := "init"
var _heartbeat_ms := 0
var _guard_mutex := Mutex.new()
var _guard_stop := false
var _guard: Thread
var _main: Node3D
var _clock: SimClock
var _landside: LandsideSim
var _views: LandsideViews
var _rig: TycoonCamera
var _cam: Camera3D


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_beat("init")
	_guard = Thread.new()
	_guard.start(_watch)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	_beat(_stage)
	return false


func _beat(stage: String) -> void:
	_guard_mutex.lock()
	_stage = stage
	_heartbeat_ms = Time.get_ticks_msec()
	_guard_mutex.unlock()


## Guard thread: a frozen main thread never reaches _process, so check from here.
func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_guard_mutex.lock()
		var stop := _guard_stop
		var idle_ms := Time.get_ticks_msec() - _heartbeat_ms
		var stage := _stage
		_guard_mutex.unlock()
		if stop:
			return
		if idle_ms > HANG_LIMIT_MS:
			print("PROBE_INVALID hang stage=%s no heartbeat for %d ms" % [stage, idle_ms])
			OS.crash("landside pull-in probe hung")


func _run() -> void:
	await _boot()
	await _plate_pull_in()
	if not _failed:
		await _plate_ground_floor()
	if not _failed:
		await _plate_access_ramp()
	if not _failed:
		await _plate_ground_walk()
	if not _failed:
		await _plate_kerb_gap()
	if not _failed:
		await _plate_upper_deck()
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _grab() -> Image:
	await _frames(4)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _boot() -> void:
	_beat("boot")
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_clock = _main.get_node("SimClock")
	var sim_seed := randi()
	_clock.seed_rng(sim_seed)
	print("PROBE sim_seed=", sim_seed)
	root.add_child(_main)
	_clock.set_process(false)
	_landside = _main.get_node("LandsideSim")
	_views = _main.get_node("LandsideViews")
	_rig = _main.get_node(CAMERA_RIG)
	_cam = _main.get_node(CAMERA_RIG + "/Camera3D")
	var mode: BuildMode = _main.get_node("BuildMode")
	(mode.get_node("Ghost") as Node3D).visible = false
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	var staff: StaffSim = _main.get_node("Staff")
	staff.hire(StaffMember.Role.CHECKIN)
	staff.hire(StaffMember.Role.SECURITY)
	await _frames(10)


func _tick() -> void:
	_advance(1.0)


## Runs the clock `ticks` (a fraction allowed) through its own advance().
func _advance(ticks: float) -> void:
	_clock.set_paused(false)
	_clock.advance(SimClock.STEP * ticks)
	_clock.set_paused(true)


## Steps until a drawn car has just left road_in for a berth's path; its id, or 0.
func _await_pull_in() -> int:
	_stage = "wait"
	var on_road := {}
	while _clock.tick < TICK_LIMIT:
		for id in _landside.vehicle_ids():
			on_road[id] = _landside.get_vehicle(id).lane == LandsideVehicle.Lane.ROAD_IN
		_tick()
		for id in _landside.vehicle_ids():
			var v := _landside.get_vehicle(id)
			var took: bool = v.lane == LandsideVehicle.Lane.BERTH and on_road.get(id, false)
			if took and v.stage == LandsideVehicle.Stage.DRIVE and _views.has_vehicle(id):
				return id
		if _clock.tick % 200 == 0:
			_beat("wait %d" % _clock.tick)
			await process_frame
	return 0


func _plate_pull_in() -> void:
	var id := await _await_pull_in()
	if id == 0:
		_invalid("no car took a berth by tick %d" % TICK_LIMIT)
		return
	var v := _landside.get_vehicle(id)
	var berth := _landside.definition.berth_position(v.stop)
	_views.draw()
	var start := _views.node_for(id).global_position
	print(
		(
			"PULL_IN vehicle=%d berth=%d at %s from %s tick=%d"
			% [id, v.stop, berth, start, _clock.tick]
		)
	)
	await _aim("pull_in", (start + berth) * 0.5, 22.0, 0.0)
	var strip := Image.create(1920, 540, false, Image.FORMAT_RGBA8)
	var last := Vector3.INF
	var left := ceili(float(_landside.paths.berth_stand[v.stop] - v.pos_mm) / LandsideSim.SPEED_MM)
	var gap := left / float(FRAMES - 1)
	print("PULL_IN %d ticks to the berth, frames %.2f ticks apart" % [left, gap])
	for i in FRAMES:
		# The ticks advanced since the frame before; a step may cover a lane step each.
		var advanced := 0.0
		if i > 0 and i < FRAMES - 1:
			_advance(gap)
			advanced = gap
		elif i == FRAMES - 1:
			# The last frame waits for the car to stand in its berth (fractions of a
			# tick add up short of the tick count), then one tick more, so the view's
			# tick before is in the berth too and every alpha draws it there.
			var guard := 0
			while v.stage == LandsideVehicle.Stage.DRIVE and guard < left * 4:
				_advance(0.25)
				advanced += 0.25
				guard += 1
			_advance(1.0)
			advanced += 1.0
		var longest := advanced * LandsideSim.SPEED_MM / 1000.0 + 0.01
		_views.draw()
		var node := _views.node_for(id)
		if node == null:
			_invalid("frame %d: vehicle %d left the view" % [i, id])
			return
		var at := node.global_position
		var nose := node.global_basis.z
		var step := at - last if i > 0 else Vector3.ZERO
		print(
			(
				"STRIP frame=%d tick=%d alpha=%.2f stage=%d at=%s nose=%s step=%.3f nose_dot=%.3f"
				% [
					i,
					_clock.tick,
					_clock.alpha,
					v.stage,
					at,
					nose,
					step.length(),
					nose.dot(step.normalized()) if step.length() > 0.001 else NAN
				]
			)
		)
		if i > 0:
			if step.length() <= 0.001 and v.stage == LandsideVehicle.Stage.DRIVE:
				_invalid("frame %d: the car did not move while pulling in" % i)
			if step.length() > longest:
				_invalid("frame %d: the car jumped %.3f m" % [i, step.length()])
			if step.length() > 0.001 and nose.dot(step.normalized()) < 0.9:
				_invalid("frame %d: the car moves %s but faces %s" % [i, step, nose])
		last = at
		if not _prove_in_frame("pull_in/frame %d" % i, _aabb_of(node)):
			return
		if i == 0 and not _prove_visible("pull_in/frame 0", node):
			return
		var img := await _grab()
		var tile := img.get_region(Rect2i(Vector2i(320, 180), Vector2i(1280, 720)))
		tile.resize(480, 270, Image.INTERPOLATE_LANCZOS)
		strip.blit_rect(
			tile,
			Rect2i(Vector2i.ZERO, Vector2i(480, 270)),
			Vector2i((i % 4) * 480, floori(i / 4.0) * 270)
		)
	print("PULL_IN last at %s, %.2f m from the berth" % [last, last.distance_to(berth)])
	if last.distance_to(berth) > 0.05:
		_invalid("the car ended %.2f m from its berth" % last.distance_to(berth))
	var path := _out_dir.path_join("landside_pull_in_strip.png")
	if strip.save_png(path) != OK:
		_invalid("could not save %s" % path)
	else:
		print("PLATE saved %s" % path)


# ------------------------------------------------------------ multi-storey


## Steps until a drawn car has just left the multi-storey's access lane for a
## ground-floor slot; its id, or 0.
func _await_ground_slot() -> int:
	_stage = "wait ground slot"
	var lot := _landside.definition.lots[MULTI]
	var on_access := {}
	while _clock.tick < TICK_LIMIT:
		for id in _landside.vehicle_ids():
			var w := _landside.get_vehicle(id)
			on_access[id] = w.lane == LandsideVehicle.Lane.ACCESS and w.lot == MULTI
		_tick()
		for id in _landside.vehicle_ids():
			var v := _landside.get_vehicle(id)
			if (
				v.lane != LandsideVehicle.Lane.SLOT
				or v.lot != MULTI
				or not on_access.get(id, false)
			):
				continue
			if LandsidePaths.deck_of(lot, lot.slots[v.stop]) == 0 and _views.has_vehicle(id):
				return id
		if _clock.tick % 200 == 0:
			_beat("wait ground slot %d" % _clock.tick)
			await process_frame
	return 0


## A fixed camera at `eye` looking at `target` (the rig stops driving it).
func _place_camera(label: String, eye: Vector3, target: Vector3) -> void:
	_beat(label)
	_rig.stop_follow()
	_rig.set_process(false)
	_rig.set_process_unhandled_input(false)
	_cam.look_at_from_position(eye, target, Vector3.UP)
	await _frames(4)
	_views.draw()
	await _rebuild_colliders()
	print("CAMERA %s eye=%s target=%s" % [label, eye, target])


func _plate_ground_floor() -> void:
	if not _landside.build_lot(MULTI):
		_invalid("the multi-storey could not be built")
		return
	_views.draw()
	var id := await _await_ground_slot()
	if id == 0:
		_invalid("no car took a ground-floor slot by tick %d" % TICK_LIMIT)
		return
	var v := _landside.get_vehicle(id)
	var slot := _landside.definition.lots[MULTI].slots[v.stop]
	var gate_lane := _landside.definition.lots[MULTI].access
	var gate := gate_lane[gate_lane.size() - 1]
	print("GROUND vehicle=%d slot=%d at %s gate %s tick=%d" % [id, v.stop, slot, gate, _clock.tick])
	await _place_camera("ground", GROUND_EYE, GROUND_TARGET)
	var stand: int = _landside.paths.slot_stand[MULTI][v.stop]
	var left := ceili(float(stand - v.pos_mm) / LandsideSim.SPEED_MM)
	var gap := left / float(FRAMES - 1)
	print("GROUND %d ticks to the slot, frames %.2f ticks apart" % [left, gap])
	var strip := Image.create(1920, 540, false, Image.FORMAT_RGBA8)
	var lowest := INF
	var highest := -INF
	var last := Vector3.INF
	for i in FRAMES:
		if i > 0 and i < FRAMES - 1:
			_advance(gap - NOSE_TICKS)
		elif i == FRAMES - 1:
			var guard := 0
			while v.stage == LandsideVehicle.Stage.DRIVE and guard < left * 4:
				_advance(0.25)
				guard += 1
			_advance(1.0)
		# The nose against the way the car moves over a twentieth of a tick.
		_views.draw()
		var node := _views.node_for(id)
		if node == null:
			_invalid("ground frame %d: vehicle %d left the view" % [i, id])
			return
		var before := node.global_position
		var parked := v.stage == LandsideVehicle.Stage.PARKED
		if not parked:
			_advance(NOSE_TICKS)
			_views.draw()
		var at := node.global_position
		var nose := node.global_basis.z
		var step := at - before
		var dot := nose.dot(step.normalized()) if step.length() > 0.001 else NAN
		lowest = minf(lowest, at.y)
		highest = maxf(highest, at.y)
		print(
			(
				"GROUND_STRIP frame=%d tick=%d stage=%d at=%s nose=%s step=%.3f nose_dot=%.3f"
				% [i, _clock.tick, v.stage, at, nose, step.length(), dot]
			)
		)
		# Frame 0 is the tick the gate lets the car in: it stood at the gate, so its
		# view has not moved yet. Later frames must move.
		if i > 0 and not parked and step.length() <= 0.001:
			_invalid("ground frame %d: the car did not move" % i)
		if not parked and step.length() > 0.001 and dot < 0.9:
			_invalid("ground frame %d: the car moves %s but faces %s" % [i, step, nose])
		if not _prove_in_frame("ground/frame %d" % i, _aabb_of(node)):
			return
		# The probe colliders ride on the car's meshes; let physics see where it is now.
		await physics_frame
		await physics_frame
		if not _prove_visible("ground/frame %d" % i, node):
			return
		last = at
		var img := await _grab()
		var tile := img.get_region(Rect2i(Vector2i(0, 0), img.get_size()))
		tile.resize(480, 270, Image.INTERPOLATE_LANCZOS)
		strip.blit_rect(
			tile,
			Rect2i(Vector2i.ZERO, Vector2i(480, 270)),
			Vector2i((i % 4) * 480, floori(i / 4.0) * 270)
		)
	var off := Vector2(last.x - slot.x, last.z - slot.z).length()
	print(
		(
			"GROUND last at %s, %.3f m from slot %s, car height %.3f..%.3f"
			% [last, off, slot, lowest, highest]
		)
	)
	if off > 0.05:
		_invalid("the car ended %.2f m from its slot" % off)
	_save(strip, "landside_ground_floor_strip.png")


## A car climbing the access lane's ramp onto the slab, from a low camera across the
## apron: each frame proves the car in frame and hit by camera rays, and that it
## stands on the lane's own height there (never under the slab top at or past the
## slab's front edge), and that a ray down through the car's middle meets the car
## park's own mesh (its paved apron, then the slab) within 3 cm of the car's height,
## so the car is drawn on a surface, not over the lawn. The strip is eight frames
## evenly over the ramp, each a STRIP_TILE tile around the car, not scaled down, so its
## wheels on the paving can be judged (strip 3840x1080).
func _plate_access_ramp() -> void:
	var lot := _landside.definition.lots[MULTI]
	var access := lot.access
	var first := 1
	while first < access.size() and access[first].y <= access[first - 1].y + 0.001:
		first += 1
	if first >= access.size():
		_invalid("the multi-storey's access lane has no ramp")
		return
	var start_mm := LandsideDefinition.length_mm(access.slice(0, first))
	var end_mm := LandsideDefinition.length_mm(access)
	var slab_y := access[access.size() - 1].y
	var edge_z := lot.centre.z - lot.footprint.y / 2.0
	var id := await _await_on_access(start_mm - 3000)
	if id == 0:
		_invalid("no car came up the access lane by tick %d" % TICK_LIMIT)
		return
	var v := _landside.get_vehicle(id)
	while v.pos_mm < start_mm and _clock.tick < TICK_LIMIT:
		_tick()
	print(
		(
			"RAMP vehicle=%d ramp %d..%d mm, slab %.2f, edge z %.2f"
			% [id, start_mm, end_mm, slab_y, edge_z]
		)
	)
	await _place_camera("ramp", RAMP_EYE, RAMP_TARGET)
	var gap := float(end_mm - start_mm) / LandsideSim.SPEED_MM / float(FRAMES - 1)
	var strip := Image.create(STRIP_TILE.x * 4, STRIP_TILE.y * 2, false, Image.FORMAT_RGBA8)
	var first_y := NAN
	var last_y := NAN
	for i in FRAMES:
		if i > 0:
			_advance(gap)
		_views.draw()
		var node := _views.node_for(id)
		if node == null:
			_invalid("ramp frame %d: vehicle %d left the view" % [i, id])
			return
		var at := node.global_position
		var want := _lane_height(access, at.z)
		print("RAMP_STRIP frame=%d tick=%d at=%s lane_height=%.3f" % [i, _clock.tick, at, want])
		if absf(at.y - want) > 0.05:
			_invalid("ramp frame %d: the car is at y %.3f, the lane says %.3f" % [i, at.y, want])
		if at.z >= edge_z and at.y < slab_y - 0.01:
			_invalid("ramp frame %d: the car is under the slab top at z %.2f" % [i, at.z])
		if not is_nan(last_y) and at.y < last_y - 0.01:
			_invalid("ramp frame %d: the car went down the ramp" % i)
		first_y = at.y if is_nan(first_y) else first_y
		last_y = at.y
		var crop := _tile_around(node.global_position)
		if not _prove_in_frame("ramp/frame %d" % i, _aabb_of(node), Rect2(crop)):
			return
		await physics_frame
		await physics_frame
		if not _prove_visible("ramp/frame %d" % i, node):
			return
		if not _prove_on_lot("ramp/frame %d" % i, node):
			return
		var img := await _grab()
		strip.blit_rect(img, crop, Vector2i((i % 4) * STRIP_TILE.x, floori(i / 4.0) * STRIP_TILE.y))
	print("RAMP rose %.3f m, %.3f -> %.3f" % [last_y - first_y, first_y, last_y])
	# The control: the car did climb, and ended on the slab.
	if last_y - first_y < 0.1 or absf(last_y - slab_y) > 0.05:
		_invalid("the car rose %.3f m and ended at %.3f" % [last_y - first_y, last_y])
	_save(strip, "landside_access_ramp_strip.png")


## A ray down through the car's middle (its own colliders left out) first meets a mesh
## of the multi-storey's drawn lot within 3 cm of the car's height.
func _prove_on_lot(label: String, car: Node3D) -> bool:
	var lot := _views.get_node("LandsidePlaces") as LandsidePlaces
	var park := lot.lot_node(MULTI) if lot != null else null
	if park == null:
		_invalid("%s: no drawn multi-storey" % label)
		return false
	var exclude: Array[RID] = []
	for body in car.find_children("ProbeBody", "StaticBody3D", true, false):
		exclude.append((body as StaticBody3D).get_rid())
	var at := car.global_position
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP, at + Vector3.DOWN)
	q.exclude = exclude
	var hit := _cam.get_world_3d().direct_space_state.intersect_ray(q)
	var on: Node = hit.collider.get_parent() if hit else null
	var gap: float = at.y - hit.position.y if hit else INF
	var ok := hit and park.is_ancestor_of(hit.collider) and absf(gap) <= 0.03
	print(
		(
			"SURFACE %s car_y=%.3f ground_y=%.3f gap=%.3f on=%s pitch=%.3f ok=%s"
			% [
				label,
				at.y,
				hit.position.y if hit else NAN,
				gap,
				on.name if on != null else "nothing",
				car.global_basis.z.y,
				ok
			]
		)
	)
	if not ok:
		_invalid("%s: the car is not on the car park's surface" % label)
	return ok


## Steps until a drawn car on the multi-storey's access lane is no further than
## `before_mm` along it; its id, or 0.
func _await_on_access(before_mm: int) -> int:
	_stage = "wait access"
	while _clock.tick < TICK_LIMIT:
		_tick()
		for id in _landside.vehicle_ids():
			var v := _landside.get_vehicle(id)
			if (
				v.lane == LandsideVehicle.Lane.ACCESS
				and v.lot == MULTI
				and v.pos_mm <= before_mm
				and _views.has_vehicle(id)
			):
				return id
		if _clock.tick % 200 == 0:
			_beat("wait access %d" % _clock.tick)
			await process_frame
	return 0


## The height of a lane (running along z) at `z`: the last point's if it is past the end.
func _lane_height(lane: PackedVector3Array, z: float) -> float:
	for i in range(1, lane.size()):
		var a := lane[i - 1]
		var b := lane[i]
		if z >= minf(a.z, b.z) and z <= maxf(a.z, b.z) and not is_equal_approx(a.z, b.z):
			return lerpf(a.y, b.y, (z - a.z) / (b.z - a.z))
	return lane[lane.size() - 1].y if z > lane[lane.size() - 1].z else lane[0].y


## A stand-in walker (a capsule, the real passengers' size) on the multi-storey's own
## ground-floor walk (LandsidePaths.lot_walk). The walk from the aisle to the gate must
## cross the front wall line once, inside the opening (x 2.05 to 7.95). The strip shows
## its last stretch, from the entrance point inside the wall out through the opening to
## the gate, from a camera on the apron looking in: eight frames evenly by distance, each
## a STRIP_TILE tile around the opening (strip 3840x1080). Every frame proves the walker
## inside its tile and hit by camera rays. The cars are hidden for this plate (they are
## frozen on the same lane and would stand in front of the walker); the count is printed.
func _plate_ground_walk() -> void:
	var lot := _landside.definition.lots[MULTI]
	var slot := 0
	while LandsidePaths.deck_of(lot, lot.slots[slot]) != 0:
		slot += 1
	var walk := _landside.paths.lot_walk(MULTI, slot)
	var gate := lot.access[lot.access.size() - 1]
	var end := walk.find(gate)
	if end < 2:
		_invalid("the ground-floor walk does not reach the gate %s" % gate)
		return
	# From the aisle (the point after the stall) to the gate.
	var route := PackedVector3Array(walk.slice(1, end + 1))
	var wall_z := lot.centre.z + FRONT_WALL_LOCAL_Z
	var crossings := 0
	for k in range(1, route.size()):
		var a := route[k - 1]
		var b := route[k]
		if (a.z - wall_z) * (b.z - wall_z) < 0.0:
			var x := a.x + (b.x - a.x) * (wall_z - a.z) / (b.z - a.z)
			print("WALK crosses the front wall line z %.2f at x %.2f" % [wall_z, x])
			crossings += 1
			if x < OPENING_X.x or x > OPENING_X.y:
				_invalid("the walk crosses the front wall at x %.2f, outside the opening" % x)
	if crossings != 1:
		_invalid("the walk crosses the wall line %d times" % crossings)
	# The stretch the strip shows: from the entrance point inside the wall to the gate.
	var inside := walk.find(lot.entrance[lot.entrance.size() - 1])
	if inside < 1 or inside >= end or walk[inside].z <= wall_z:
		_invalid("the walk has no entrance point inside the wall before the gate")
		return
	var shown := PackedVector3Array(walk.slice(inside, end + 1))
	var hidden: Array[Node3D] = []
	for id in _landside.vehicle_ids():
		var car := _views.node_for(id)
		if car != null and car.visible:
			car.visible = false
			hidden.append(car)
	print("WALK hid %d vehicles for the plate" % hidden.size())
	var walker := MeshInstance3D.new()
	walker.name = "ProbeWalker"
	var capsule := CapsuleMesh.new()
	capsule.radius = WALKER_RADIUS
	capsule.height = WALKER_HEIGHT
	walker.mesh = capsule
	_main.add_child(walker)
	walker.global_position = shown[0] + Vector3.UP * (WALKER_HEIGHT / 2.0)
	await _place_camera("walk", WALK_EYE, WALK_TARGET)
	var crop := _tile_around(WALK_TARGET)
	print("WALK tile %s of the %s viewport" % [crop, root.get_visible_rect().size])
	var total := LandsideDefinition.length_mm(shown)
	var strip := Image.create(STRIP_TILE.x * 4, STRIP_TILE.y * 2, false, Image.FORMAT_RGBA8)
	for i in FRAMES:
		var at := LandsideDefinition.point_on(shown, roundi(total * i / float(FRAMES - 1)))
		walker.global_position = at + Vector3.UP * (WALKER_HEIGHT / 2.0)
		print(
			"WALK_STRIP frame=%d at=%s of %d points, %.1f m" % [i, at, shown.size(), total / 1000.0]
		)
		if not _prove_in_frame("walk/frame %d" % i, _aabb_of(walker), Rect2(crop)):
			break
		await physics_frame
		await physics_frame
		if not _prove_visible("walk/frame %d" % i, walker):
			break
		var img := await _grab()
		strip.blit_rect(img, crop, Vector2i((i % 4) * STRIP_TILE.x, floori(i / 4.0) * STRIP_TILE.y))
	walker.free()
	for car in hidden:
		car.visible = true
	if not _failed:
		_save(strip, "landside_ground_walk_strip.png")


## A STRIP_TILE rectangle of the viewport centred on where `at` projects, kept inside it.
func _tile_around(at: Vector3) -> Rect2i:
	var view := Vector2i(root.get_visible_rect().size)
	var centre := Vector2i(_cam.unproject_position(at))
	return Rect2i((centre - STRIP_TILE / 2).clamp(Vector2i.ZERO, view - STRIP_TILE), STRIP_TILE)


## Rays from the camera to `target`: at least one lands within 0.3 m of it.
func _prove_point(label: String, target: Vector3) -> bool:
	var space := _cam.get_world_3d().direct_space_state
	var from := _cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, target + (target - from).normalized() * 0.5)
	var hit := space.intersect_ray(q)
	var off: float = (hit.position - target).length() if hit else INF
	print("VISIBLE %s ray lands %.2f m from the target" % [label, off])
	if off > 0.3:
		_invalid("%s: the ray to %s stops %.2f m away" % [label, target, off])
	return off <= 0.3


func _plate_kerb_gap() -> void:
	await _place_camera("kerb_gap", GAP_EYE, GAP_MID)
	var box := AABB(Vector3(1.0, 0.3, -29.9), Vector3(0.7, 0.15, 4.0))
	if not _prove_in_frame("kerb_gap", box) or not _prove_point("kerb_gap", GAP_MID):
		return
	_save(await _grab(), "landside_kerb_gap.png")


## Parked cars moved into consecutive first-deck stalls (a fixture), then a still from
## the first deck's aisle.
func _plate_upper_deck() -> void:
	var lot := _landside.definition.lots[MULTI]
	var first := 0
	for k in lot.slots.size():
		if LandsidePaths.deck_of(lot, lot.slots[k]) == 1:
			first = k
			break
	# Let more cars park first, so the deck shows a row of them.
	var waited := 0
	while _parked_in_multi() < DECK_STALLS.size() and waited < DECK_WAIT_TICKS:
		_tick()
		waited += 1
		if waited % 200 == 0:
			_beat("wait deck %d" % waited)
			await process_frame
	var moved: Array[int] = []
	for id in _landside.vehicle_ids():
		var v := _landside.get_vehicle(id)
		if v.lot == MULTI and v.stage == LandsideVehicle.Stage.PARKED and moved.size() < 3:
			v.stop = first + DECK_STALLS[moved.size()]
			v.pos_mm = _landside.paths.slot_stand[MULTI][v.stop]
			moved.append(id)
	if moved.is_empty():
		_invalid("no parked car to move onto the first deck")
		return
	_views.snap()
	print("DECK moved %s to slots %s" % [moved, DECK_STALLS.slice(0, moved.size())])
	await _place_camera("deck", DECK_EYE, DECK_TARGET)
	for id in moved:
		var node := _views.node_for(id)
		if not _prove_in_frame("deck/%d" % id, _aabb_of(node)):
			return
		if not _prove_visible("deck/%d" % id, node):
			return
		print("DECK car %d at %s" % [id, node.global_position])
	_save(await _grab(), "landside_upper_deck_stalls.png")


func _parked_in_multi() -> int:
	var count := 0
	for id in _landside.vehicle_ids():
		var v := _landside.get_vehicle(id)
		count += int(v.lot == MULTI and v.stage == LandsideVehicle.Stage.PARKED)
	return count


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
	else:
		print("PLATE saved %s" % path)


# ------------------------------------------------------------ checks


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		out.append(mi)
	return out


func _aabb_of(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(node):
		if not mi.is_visible_in_tree():
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _opaque_faces(mi: MeshInstance3D) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for i in mi.mesh.get_surface_count():
		var mat := mi.get_active_material(i)
		if mat != null and mat.resource_path == GLASS:
			continue
		var arrays := mi.mesh.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if index.is_empty():
			faces.append_array(verts)
		else:
			for k in index:
				faces.append(verts[k])
	return faces


## A static body per visible mesh with a trimesh of its opaque surfaces; old ones go.
func _rebuild_colliders() -> void:
	for body in _main.find_children("ProbeBody", "StaticBody3D", true, false):
		body.free()
	for mi in _meshes(_main):
		if mi.mesh == null or mi.skin != null or not mi.is_visible_in_tree() or _dropped(mi):
			continue
		var faces := _opaque_faces(mi)
		if faces.is_empty():
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		var shape_node := CollisionShape3D.new()
		shape_node.shape = shape
		var body := StaticBody3D.new()
		body.name = "ProbeBody"
		body.add_child(shape_node)
		mi.add_child(body)
	await physics_frame
	await physics_frame


## Whether a dissolve material has fully dropped this mesh (dissolve >= 0.99).
func _dropped(mi: MeshInstance3D) -> bool:
	for i in mi.mesh.get_surface_count():
		var mat := mi.get_active_material(i) as ShaderMaterial
		if mat != null:
			var amount: Variant = mat.get_shader_parameter("dissolve")
			if amount != null and float(amount) >= 0.99:
				return true
	return false


## The box's projected corners inside `within` (the viewport when it is empty), with
## MARGIN_PX to spare.
func _prove_in_frame(label: String, box: AABB, within := Rect2()) -> bool:
	var whole := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var rect := (whole if within.size == Vector2.ZERO else within).grow(-MARGIN_PX)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var p := box.get_endpoint(i)
		if _cam.is_position_behind(p):
			_invalid("%s: a corner is behind the camera" % label)
			return false
		var s := _cam.unproject_position(p)
		lo = lo.min(s)
		hi = hi.max(s)
	var ok := rect.has_point(lo) and rect.has_point(hi)
	print(
		(
			"INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) size_px=(%.0f, %.0f) ok=%s"
			% [label, lo.x, lo.y, hi.x, hi.y, hi.x - lo.x, hi.y - lo.y, ok]
		)
	)
	if not ok:
		_invalid("%s: projected bounds leave the viewport" % label)
	return ok


## Rays from the camera to the subject's camera-facing opaque triangles: at least half
## must hit the subject first.
func _prove_visible(label: String, subject: Node3D) -> bool:
	var targets: Array[Vector3] = []
	for mi in _meshes(subject):
		if not mi.is_visible_in_tree():
			continue
		var faces := _opaque_faces(mi)
		var facing: Array[Vector3] = []
		for i in range(0, faces.size() - 2, 3):
			var a: Vector3 = mi.global_transform * faces[i]
			var b: Vector3 = mi.global_transform * faces[i + 1]
			var c: Vector3 = mi.global_transform * faces[i + 2]
			var mid := (a + b + c) / 3.0
			if (b - a).cross(c - a).dot(_cam.global_position - mid) < 0.0:
				facing.append(mid)
		var step := maxi(1, floori(facing.size() / 12.0))
		for i in range(0, facing.size(), step):
			targets.append(facing[i])
	var space := _cam.get_world_3d().direct_space_state
	var hits := 0
	var blockers := {}
	for t in targets:
		var from := _cam.global_position
		var q := PhysicsRayQueryParameters3D.create(from, t + (t - from).normalized() * 0.05)
		var hit := space.intersect_ray(q)
		if hit and subject.is_ancestor_of(hit.collider):
			hits += 1
		elif hit:
			var by: Node = hit.collider.get_parent()
			blockers[by.name] = int(blockers.get(by.name, 0)) + 1
	var ok := hits > 0 and hits * 2 >= targets.size()
	print(
		(
			"VISIBLE %s ray_hits=%d/%d ok=%s blocked_by=%s"
			% [label, hits, targets.size(), ok, blockers]
		)
	)
	if not ok:
		_invalid("%s: occluded or not hit (%d of %d rays)" % [label, hits, targets.size()])
	return ok


## Moves the camera, waits for the roof cutaway, and rebuilds colliders for it.
func _aim(label: String, focus: Vector3, distance: float, yaw: float) -> void:
	_beat(label)
	_rig.stop_follow()
	_rig.position = focus
	_rig.yaw = yaw
	_rig.distance = distance
	_rig.zoom(1.0)
	await create_timer(1.5).timeout
	await _frames(4)
	_views.draw()
	await _rebuild_colliders()
	print(
		(
			"CAMERA %s pos=%s focus=%s distance=%.1f yaw=%.2f"
			% [label, _cam.global_position, focus, distance, yaw]
		)
	)
